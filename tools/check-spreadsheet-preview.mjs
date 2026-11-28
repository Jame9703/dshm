#!/usr/bin/env node
/** Native workbook safety and registration checks. An optional packed stage verifies the real wire descriptor. */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  MAX_CELLS, normalizeWorkbook, validateArchive, validateLegacyWorkbook
} from '../hostcore/spreadsheet/model.mjs';
import {
  bundledSpreadsheetWorker, patchSpreadsheetHostDescriptor, patchSpreadsheetService, patchSpreadsheetSharePolicy
} from './lib/spreadsheet-preview.mjs';

const endpoint = 'workspaceFiles/spreadsheet';

function selfTest() {
  const source = readFileSync('dshcompat/src/main/ets/SpreadsheetEndpoint.ets', 'utf8').replace(/\r\n/g, '\n');
  assert.ok(source.includes(
    "params: ['workspaceFileScopeId', 'path'],\n  stream: false,\n  cancellable: true"));
  assert.ok(source.includes("= '" + endpoint + "'"));
  assert.throws(() => bundledSpreadsheetWorker("'missing'"), /anchor/);
  assert.throws(() => bundledSpreadsheetWorker("'(function(){var e=Object.create,t=Object.defineProperty,altered'"),
    /changed bundled spreadsheet worker/);
  assert.throws(() => patchSpreadsheetHostDescriptor('no descriptor'), /anchor/);
  assert.throws(() => patchSpreadsheetService('no method'), /anchor/);
  assert.throws(() => patchSpreadsheetSharePolicy('\t"workspaceFiles/spreadsheet": "reader-owned",'), /policy/);
  const ownerRule = '\t"workspaceFiles/readBytes": "owner-only",';
  assert.ok(patchSpreadsheetSharePolicy(ownerRule).includes('\t"' + endpoint + '": "owner-only",'));

  assert.throws(() => validateArchive(Buffer.from('not a zip')), /invalid/);
  const emptyZip = Buffer.alloc(22);
  emptyZip.writeUInt32LE(0x06054b50, 0);
  emptyZip.writeUInt16LE(4097, 8);
  emptyZip.writeUInt16LE(4097, 10);
  assert.throws(() => validateArchive(emptyZip), /tooLarge/);
  assert.throws(() => validateLegacyWorkbook(Uint8Array.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])), /invalid/);

  const input = {
    sheets: [
      { id: '1', name: 'Hidden', hide: 1, status: 1, row: 1, column: 1, celldata: [] },
      { id: '2', name: 'Visible', hide: 0, status: 0, row: 2, column: 2, celldata: [
        { r: 0, c: 0, v: { v: 4, m: '4.00', f: '=2+2', ct: { fa: '0.00' }, bl: 1, ht: 0 } },
        { r: 1, c: 0, v: { v: true, m: 'true', tb: '2' } },
      ], config: { rowlen: { 1: 34 }, rowhidden: { 1: 0 }, merge: { '0_0': { r: 0, c: 0, rs: 1, cs: 2 } } } },
    ],
    missingResults: 0,
    unsupportedFeatures: ['charts'],
  };
  const preview = normalizeWorkbook(input);
  assert.deepEqual(preview.sheets.map(({ active }) => active), [false, true]);
  const sheet = preview.sheets[1];
  assert.deepEqual(sheet.cells[0], {
    row: 0, column: 0, value: '4', display: '4.00', formula: '=2+2', format: '0.00', bold: true, horizontal: 'center'
  });
  assert.deepEqual(sheet.rowHeights, [{ index: 1, pixels: 34 }]);
  assert.deepEqual(sheet.hiddenRows, [1]);
  assert.deepEqual(sheet.merges, [{ row: 0, column: 0, rows: 1, columns: 2 }]);
  assert.deepEqual(preview.unsupportedFeatures, ['charts']);
  assert.throws(() => normalizeWorkbook({ ...input, sheets: [{ ...input.sheets[1], column: MAX_CELLS }] }), /tooLarge/);
  assert.throws(() => normalizeWorkbook({ ...input, sheets: [input.sheets[0]] }), /invalid/);
  console.log('PASS spreadsheet preview safety, typed wire shape, and patch mutation checks');
}

async function packedStage(dir) {
  const packages = join(dir, 'node_modules', '@deepseek-ai');
  const api = join(packages, 'dsh-api-workspace-files', 'lib');
  const { TYPERT } = await import(pathToFileURL(join(api, 'typert.host.js')));
  const descriptor = TYPERT.invocations.find((item) => item.namespace + '/' + item.method === endpoint);
  assert.ok(descriptor, 'packed core must expose ' + endpoint);
  assert.deepEqual(descriptor.parameters.map(({ wire }) => wire), ['workspaceFileScopeId', 'path']);
  assert.equal(descriptor.parameters[0].lookup, 'workspaceFileScope');
  assert.equal(descriptor.cancellation.parameter, 'signal');
  assert.equal(descriptor.input({ strict: true }).create().safeParse({
    workspaceFileScopeId: 'scope', path: 'book.xlsx', workspaceRoot: 'invalid'
  }).success, false);
  const service = await import(pathToFileURL(join(api, 'index.js')));
  assert.equal(typeof service.WorkspaceFiles.prototype.spreadsheet, 'function');
  assert.ok(readFileSync(join(api, 'dshm-spreadsheet-engine.mjs'), 'utf8').includes('globalThis.onmessage'));
  console.log('PASS packed spreadsheet method, scoped lookup, strict input, and worker asset');
}

const stageArgument = process.argv.indexOf('--stage');
if (stageArgument >= 0) await packedStage(process.argv[stageArgument + 1]);
else selfTest();
