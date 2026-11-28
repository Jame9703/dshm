import { Worker } from 'node:worker_threads';
import { RemoteError } from '@deepseek-ai/dsh-typert-protocol';
import { MAX_FILE_BYTES, TIMEOUT_MS } from './dshm-spreadsheet-model.mjs';

const MAX_CONCURRENT = 2;
let active = 0;

function failure(code) {
  const messages = {
    invalid: 'Unable to read this workbook',
    'too-large': 'Workbook exceeds the preview limits',
    timeout: 'Workbook preview timed out',
    busy: 'Workbook preview workers are busy',
  };
  return new RemoteError('spreadsheet/' + code, messages[code], {});
}

function awaitWorker(worker, signal) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal.removeEventListener('abort', abort);
      if (error) reject(error);
      else resolve(result);
    };
    const abort = () => finish(signal.reason ?? new DOMException('Workbook preview cancelled', 'AbortError'));
    const timer = setTimeout(() => finish(failure('timeout')), TIMEOUT_MS);
    worker.on('error', (error) => finish(failure(error?.code === 'ERR_WORKER_OUT_OF_MEMORY' ? 'too-large' : 'invalid')));
    worker.once('exit', () => finish(failure('invalid')));
    worker.once('message', (reply) => {
      if (reply.workbook) finish(undefined, reply.workbook);
      else finish(failure(reply.error === 'too-large' ? 'too-large' : 'invalid'));
    });
    signal.addEventListener('abort', abort, { once: true });
    if (signal.aborted) abort();
  });
}

/** Apply the original WorkspaceFiles read policy and pass only bytes to the parser. */
export async function spreadsheetPreview(files, scope, path, signal) {
  const format = /\.(xlsx|xls)$/i.exec(path)?.[1].toLowerCase();
  if (!format) throw failure('invalid');
  signal.throwIfAborted();
  if (active >= MAX_CONCURRENT) throw failure('busy');
  active++;
  let worker;
  try {
    const stat = await files.stat(scope, path, signal);
    if (stat.bytes > MAX_FILE_BYTES) throw failure('too-large');
    const content = await files.readBytes(scope, path, {}, signal);
    signal.throwIfAborted();
    if (!(content.data instanceof Uint8Array) || !content.eof || content.offset !== 0) throw failure('invalid');
    if (content.data.byteLength > MAX_FILE_BYTES) throw failure('too-large');
    if (content.bytes !== undefined && content.bytes !== content.data.byteLength) throw failure('invalid');
    // Consolidate onto an owned ArrayBuffer so Worker transfer cannot detach shared fs buffers.
    const bytes = Uint8Array.from(content.data);
    try {
      worker = new Worker(new URL('./dshm-spreadsheet-worker.mjs', import.meta.url), {
        workerData: { bytes, format },
        transferList: [bytes.buffer],
        resourceLimits: { maxOldGenerationSizeMb: 160, maxYoungGenerationSizeMb: 16 },
      });
    } catch (_) { throw failure('invalid'); }
    const workbook = await awaitWorker(worker, signal);
    return { absolutePath: content.absolutePath, version: content.version, ...workbook };
  } finally {
    try {
      if (worker) await worker.terminate().catch(() => {});
    } finally { active--; }
  }
}
