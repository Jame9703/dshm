import { util } from '@kit.ArkTS';
import { parseConnectionResponse } from './Envelope';
import { getArray, getField, getRecord, getString, parseJson } from './JsonValue';
import { RemoteFailure, rpcFail, rpcOk } from './RpcTypes';
import type { RpcResult } from './RpcTypes';

const HEADER_LIMIT: number = 8192;
const METADATA_LIMIT: number = 32768;

interface Part {
  name: string;
  start: number;
  end: number;
  next: number;
  final: boolean;
}

interface AttachmentValue {
  metadata: Object;
  data: ArrayBuffer;
}

function matches(bytes: Uint8Array, text: string, offset: number): boolean {
  if (offset + text.length > bytes.length) { return false; }
  for (let index = 0; index < text.length; index++) {
    if (bytes[offset + index] !== text.charCodeAt(index)) { return false; }
  }
  return true;
}

function find(bytes: Uint8Array, text: string, start: number, end: number): number {
  for (let offset = start; offset <= end - text.length; offset++) {
    if (bytes[offset] === text.charCodeAt(0) && matches(bytes, text, offset)) { return offset; }
  }
  return -1;
}

function decode(bytes: Uint8Array): string { return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes); }

function partAt(bytes: Uint8Array, marker: string, offset: number, limit: number): Part | undefined {
  if (!matches(bytes, marker + '\r\n', offset)) { return undefined; }
  const headerStart = offset + marker.length + 2;
  const headerEnd = find(bytes, '\r\n\r\n', headerStart, Math.min(bytes.length, headerStart + HEADER_LIMIT));
  if (headerEnd < 0) { return undefined; }
  const headers = decode(bytes.subarray(headerStart, headerEnd));
  const disposition = headers.split('\r\n').find((line: string): boolean => /^content-disposition:/i.test(line));
  const name = /(?:^|;)\s*name="([a-z0-9-]+)"(?:;|$)/i.exec(disposition ?? '')?.[1];
  const start = headerEnd + 4;
  const delimiter = '\r\n' + marker;
  const searchEnd = Math.min(bytes.length, start + limit + delimiter.length + 2);
  let end = find(bytes, delimiter, start, searchEnd);
  while (end >= 0 && end - start <= limit && name !== undefined) {
    const after = end + delimiter.length;
    const final = matches(bytes, '--', after);
    if (final || matches(bytes, '\r\n', after)) {
      return { name: name, start: start, end: end, next: final ? after + 2 : end + 2, final: final };
    }
    end = find(bytes, delimiter, end + 1, searchEnd);
  }
  return undefined;
}

/** Decode the Workspace byte reply without turning any binary part into text. */
export function parseByteAttachment(body: ArrayBuffer, contentType: string, rpcId: string,
  endpoint: string): RpcResult {
  const bytes = new Uint8Array(body);
  const invalid = (): RpcResult => rpcFail(RemoteFailure.parse(`invalid byte attachment for ${endpoint}`));
  try {
    if (!/^multipart\/form-data(?:;|$)/i.test(contentType)) {
      return bytes.length <= METADATA_LIMIT ? parseConnectionResponse(decode(bytes), rpcId, endpoint) : invalid();
    }
    const boundaryMatch = /(?:^|;)\s*boundary\s*=\s*(?:"([0-9a-z'()+_,.\/:=?-]{1,70})"|([0-9a-z'()+_,.\/:=?-]{1,70}))\s*(?:;|$)/i
      .exec(contentType);
    const boundary = boundaryMatch?.[1] ?? boundaryMatch?.[2];
    if (boundary === undefined) { return invalid(); }
    const marker = '--' + boundary;
    const first = partAt(bytes, marker, 0, bytes.length);
    if (first === undefined || first.final) { return invalid(); }
    const second = partAt(bytes, marker, first.next, bytes.length);
    if (second === undefined || !second.final ||
      !(second.next === bytes.length || (second.next + 2 === bytes.length && matches(bytes, '\r\n', second.next)))) {
      return invalid();
    }
    const metadata = first.name === 'metadata' ? first : second;
    const data = metadata === first ? second : first;
    if (metadata.name !== 'metadata' || metadata.end - metadata.start > METADATA_LIMIT) { return invalid(); }
    const text = decode(bytes.subarray(metadata.start, metadata.end));
    const result = parseConnectionResponse(text, rpcId, endpoint);
    if (!result.ok) { return result; }
    const envelope = parseJson(text);
    const items = getArray(envelope, 'attachments');
    if (items?.length !== 1) { return invalid(); }
    const item = items[0];
    const path = getArray(item, 'path');
    const partName = getString(item, 'part');
    const value = getRecord(getRecord(envelope, 'result'), 'value');
    if (getString(item, 'codec') !== 'bytes' || path?.length !== 1 || path[0] !== 'data' || !partName ||
      value === undefined || getField(value, 'data') !== null) { return invalid(); }
    if (data.name !== partName || data.name === 'metadata') { return invalid(); }
    const decoded: AttachmentValue = { metadata: value, data: body.slice(data.start, data.end) };
    return rpcOk(decoded);
  } catch (_) { return invalid(); }
}
