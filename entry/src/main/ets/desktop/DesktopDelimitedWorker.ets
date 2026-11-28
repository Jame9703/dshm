import { util } from '@kit.ArkTS';
import { DesktopDelimitedTable, parseDesktopDelimited } from './DesktopDelimitedTable';

interface DesktopDelimitedParse {
  table?: DesktopDelimitedTable;
  problem: string;
}

@Concurrent
export function parseDesktopDelimitedBytes(input: ArrayBuffer, delimiter: string,
  maxBytes: number, maxCells: number): DesktopDelimitedParse {
  if (input.byteLength > maxBytes) { return { problem: 'tooLarge' }; }
  const bytes = new Uint8Array(input);
  const encoding = bytes[0] === 0xff && bytes[1] === 0xfe ? 'utf-16le' :
    bytes[0] === 0xfe && bytes[1] === 0xff ? 'utf-16be' : 'utf-8';
  let text: string;
  try { text = util.TextDecoder.create(encoding, { fatal: true }).decodeToString(bytes); }
  catch (_) { return { problem: 'encoding' }; }
  try {
    return { table: parseDesktopDelimited(text.charCodeAt(0) === 0xfeff ? text.slice(1) : text, delimiter, maxCells),
      problem: '' };
  } catch (error) {
    return { problem: error instanceof Error && error.message === 'tooLarge' ? 'tooLarge' : 'invalid' };
  }
}
