import { parentPort, workerData } from 'node:worker_threads';
import { MAX_CELLS, MAX_FILE_BYTES, TIMEOUT_MS, normalizeWorkbook, validateArchive, validateLegacyWorkbook } from './dshm-spreadsheet-model.mjs';

function report(error) {
  parentPort.postMessage({ error: error?.message === 'tooLarge' ? 'too-large' : 'invalid' });
}

try {
  const { bytes, format } = workerData;
  if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length > MAX_FILE_BYTES) throw Error('tooLarge');
  if (format === 'xlsx') validateArchive(bytes);
  else if (format === 'xls') validateLegacyWorkbook(bytes);
  else throw Error('invalid');
  globalThis.self = globalThis;
  globalThis.postMessage = (message) => {
    try {
      if (message.ok) parentPort.postMessage({ workbook: normalizeWorkbook(message.value) });
      else report(Error(message.code));
    } catch (error) { report(error); }
  };
  await import('./dshm-spreadsheet-engine.mjs');
  globalThis.onmessage({ data: { bytes, format, limits: {
    maxBytes: MAX_FILE_BYTES, maxCells: MAX_CELLS, timeoutMs: TIMEOUT_MS
  } } });
} catch (error) { report(error); }
