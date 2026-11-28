import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const WORKER_SHA256 = 'af2e1a317ba377c9dda470aca82c99fe0e9423ef5b1dac218162f601f3e4eeb7';
const WORKER_START = "'(function(){var e=Object.create,t=Object.defineProperty,";
const WORKER_PACKAGE = 'dsh-client-ui-sidebar-documentpreview/lib/client.excel.js';
const API_PACKAGE = 'dsh-api-workspace-files/lib';

function replaceOnce(input, needle, replacement) {
  if (input.split(needle).length !== 2) throw Error('Missing or duplicate spreadsheet patch anchor: ' + needle.slice(0, 88));
  return input.replace(needle, () => replacement);
}

/** Decode a trusted, pinned build-time string literal without evaluating its containing bundle. */
export function bundledSpreadsheetWorker(source) {
  if (source.split(WORKER_START).length !== 2) throw Error('Review the bundled spreadsheet worker anchor');
  const parts = [];
  const simpleEscapes = { "'": "'", '"': '"', '\\': '\\', n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', v: '\v', 0: '\0' };
  let start = source.indexOf(WORKER_START) + 1;
  for (let i = start; i < source.length; i++) {
    if (source[i] === "'") {
      parts.push(source.slice(start, i));
      const worker = parts.join('');
      if (createHash('sha256').update(worker).digest('hex') !== WORKER_SHA256) {
        throw Error('Review the changed bundled spreadsheet worker before packaging it');
      }
      return worker;
    }
    if (source[i] !== '\\') continue;
    parts.push(source.slice(start, i));
    const escape = source[++i];
    if (Object.hasOwn(simpleEscapes, escape)) {
      parts.push(simpleEscapes[escape]);
    } else if (escape === 'u' || escape === 'x') {
      const length = escape === 'u' ? 4 : 2;
      const digits = source.slice(i + 1, i + 1 + length);
      if (digits.length !== length || !/^[0-9a-f]+$/i.test(digits)) throw Error('Invalid spreadsheet worker escape');
      parts.push(String.fromCharCode(Number.parseInt(digits, 16)));
      i += length;
    } else {
      throw Error('Unsupported spreadsheet worker encoding: ' + escape);
    }
    start = i + 1;
  }
  throw Error('Unterminated bundled spreadsheet worker');
}

const METHOD = 'async spreadsheet(workspaceFileScope, path, signal) {';
const STAT = 'async stat(workspaceFileScope, path, signal) {';
const DECORATOR = '__esDecorate(this, null, _stat_decorators, {';
const MARKER = 'name: "spreadsheet",';
const DESCRIPTOR = "    'workspaceFiles/spreadsheet': spreadsheetMethod(z),";
const DESCRIPTOR_IMPORT = "import { spreadsheetMethod } from './dshm-spreadsheet-descriptor.mjs'\n";
const SPREADSHEET_METHOD = [
  METHOD,
  "\t\t\tconst { spreadsheetPreview } = await import('./dshm-spreadsheet-service.mjs');",
  '\t\t\treturn spreadsheetPreview(this, workspaceFileScope, path, signal);',
  '\t\t}',
].join('\n');

export function patchSpreadsheetService(source) {
  const block = [
    DECORATOR,
    '\t\t\t\tkind: "method",',
    '\t\t\t\t' + MARKER,
    '\t\t\t\tstatic: false,',
    '\t\t\t\tprivate: false,',
    '\t\t\t\taccess: { has: (obj) => "spreadsheet" in obj, get: (obj) => obj.spreadsheet },',
    '\t\t\t\tmetadata: _metadata',
    '\t\t\t}, null, _instanceExtraInitializers);',
  ].join('\n');
  if (source.includes(METHOD) || source.includes(MARKER)) {
    if (!source.includes(block) || !source.includes(SPREADSHEET_METHOD)) throw Error('Incomplete spreadsheet service patch');
    return source;
  }
  return replaceOnce(replaceOnce(source, DECORATOR, block + '\n\t\t\t' + DECORATOR),
    STAT, SPREADSHEET_METHOD + '\n\t\t' + STAT);
}

export function patchSpreadsheetHostDescriptor(source) {
  if (source.includes('workspaceFiles/spreadsheet') || source.includes(DESCRIPTOR_IMPORT)) {
    if (!source.includes(DESCRIPTOR_IMPORT) || !source.includes(DESCRIPTOR)) throw Error('Incomplete spreadsheet descriptor patch');
    return source;
  }
  const methods = "    'workspaceFiles/changes': {";
  return DESCRIPTOR_IMPORT + replaceOnce(source, methods, DESCRIPTOR + '\n' + methods);
}

/** Record the new read with the same owner policy as the WorkspaceFiles byte source. */
export function patchSpreadsheetSharePolicy(source) {
  const after = '\t"workspaceFiles/spreadsheet": "owner-only",';
  if (source.includes('workspaceFiles/spreadsheet')) {
    if (!source.includes(after)) throw Error('Unexpected spreadsheet viewer policy');
    return source;
  }
  const bytes = '\t"workspaceFiles/readBytes": "owner-only",';
  return replaceOnce(source, bytes, bytes + '\n' + after);
}

export function prepareSpreadsheetPreview(stage, root) {
  const modules = join(stage, 'node_modules', '@deepseek-ai');
  const path = join(modules, API_PACKAGE);
  const engine = bundledSpreadsheetWorker(readFileSync(join(modules, WORKER_PACKAGE), 'utf8'));
  const index = join(path, 'index.js');
  const face = join(path, 'typert.host.js');
  const policy = join(modules, 'dsh-experimental-liveshare/lib/index.js');
  const indexSource = patchSpreadsheetService(readFileSync(index, 'utf8'));
  const faceSource = patchSpreadsheetHostDescriptor(readFileSync(face, 'utf8'));
  const policySource = existsSync(policy) ? patchSpreadsheetSharePolicy(readFileSync(policy, 'utf8')) : undefined;
  for (const file of ['descriptor', 'model', 'service', 'worker']) {
    copyFileSync(join(root, 'hostcore', 'spreadsheet', file + '.mjs'), join(path, 'dshm-spreadsheet-' + file + '.mjs'));
  }
  writeFileSync(join(path, 'dshm-spreadsheet-engine.mjs'), engine);
  writeFileSync(index, indexSource);
  writeFileSync(face, faceSource);
  if (policySource !== undefined) writeFileSync(policy, policySource);
}
