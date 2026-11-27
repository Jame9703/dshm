import { Speaker } from 'appstate';
import { getArray, getNumber, getString } from 'connection';
import { DesktopTranscriptItem } from './DesktopConversation';
import { desktopSecretRanges } from './DesktopSecretMask';

const PROMPT_PREVIEW_LENGTH: number = 50;
const RESPONSE_PREVIEW_LENGTH: number = 120;
const WHITESPACE: RegExp = new RegExp('\\s+', 'gu');

export interface DesktopTurnOutlineEntry {
  turn: number;
  seq: number;
  prompt: string;
  response: string;
}

export interface DesktopTurnOutlineItem {
  turn: number;
  seq: number;
  anchorIndex: number;
  prompt: string;
  response: string;
  promptFromOutline: boolean;
  responseFromOutline: boolean;
}

interface LoadedTurn {
  firstIndex: number;
  firstUserIndex: number;
  sequence: number;
  prompt: string;
  response: string;
}

function nonNegativeInteger(value: number | undefined): boolean {
  return value !== undefined && Number.isSafeInteger(value) && value >= 0 && (value !== 0 || 1 / value > 0);
}

function readPreview(raw: string | undefined, limit: number): string {
  const value = raw ?? '';
  return value.length > limit ? value.slice(0, limit - 1) + '…' : value;
}

/** Absence is distinct from a valid, empty projection update. */
export function readDesktopTurnOutline(values?: Object): DesktopTurnOutlineEntry[] | undefined {
  const outline = getArray(values, 'turnOutline');
  if (outline === undefined) { return undefined; }

  const byTurn = new Map<number, DesktopTurnOutlineEntry>();
  for (const value of outline) {
    const turn = getNumber(value, 'turn') ?? -1;
    const seq = getNumber(value, 'seq') ?? -1;
    if (!nonNegativeInteger(turn) || !nonNegativeInteger(seq)) { continue; }
    byTurn.set(turn, {
      turn: turn, seq: seq,
      prompt: readPreview(getString(value, 'prompt'), PROMPT_PREVIEW_LENGTH),
      response: readPreview(getString(value, 'response'), RESPONSE_PREVIEW_LENGTH)
    });
  }
  return Array.from(byTurn.values()).sort((left: DesktopTurnOutlineEntry, right: DesktopTurnOutlineEntry): number =>
    left.turn - right.turn);
}

function loadedTurnOf(row: DesktopTranscriptItem, boundary: DesktopTurnOutlineEntry | undefined): number {
  const explicit = row.turn ?? row.process?.turn ?? row.replyTail?.turn ?? row.artifacts?.turn;
  return explicit !== undefined && nonNegativeInteger(explicit) ? explicit : boundary?.turn ?? -1;
}

/** Merge timeline anchors with the host projection. Neither history paging nor a stream chunk copies full messages. */
export function desktopTurnOutlineItems(transcript: DesktopTranscriptItem[],
  outline: DesktopTurnOutlineEntry[]): DesktopTurnOutlineItem[] {
  const bySequence = outline.slice().sort((left: DesktopTurnOutlineEntry, right: DesktopTurnOutlineEntry): number =>
    left.seq - right.seq);
  const loaded = new Map<number, LoadedTurn>();
  let boundaryIndex = -1;

  for (let index = 0; index < transcript.length; index++) {
    const row = transcript[index];
    const sequence = row.sequence;
    if (row.inheritedHistory || !nonNegativeInteger(sequence)) { continue; }
    while (boundaryIndex + 1 < bySequence.length && bySequence[boundaryIndex + 1].seq <= sequence) {
      boundaryIndex++;
    }
    const boundary = boundaryIndex >= 0 ? bySequence[boundaryIndex] : undefined;
    const turn = loadedTurnOf(row, boundary);
    if (turn < 0) { continue; }

    let entry = loaded.get(turn);
    if (entry === undefined) {
      entry = { firstIndex: index, firstUserIndex: -1, sequence: sequence, prompt: '', response: '' };
      loaded.set(turn, entry);
    }
    const message = row.message;
    if (message?.speaker === Speaker.USER && entry.firstUserIndex < 0) {
      entry.firstUserIndex = index;
      entry.prompt = message.body;
    } else if (message?.speaker === Speaker.ASSISTANT && message.body.trim()) {
      entry.response = message.body;
    }
  }

  const all = new Map<number, DesktopTurnOutlineItem>();
  for (const value of outline) {
    all.set(value.turn, {
      turn: value.turn, seq: value.seq, anchorIndex: -1,
      prompt: value.prompt, response: value.response, promptFromOutline: true, responseFromOutline: true
    });
  }
  loaded.forEach((entry: LoadedTurn, turn: number): void => {
    const projected = all.get(turn);
    const promptFromOutline = !entry.prompt.trim();
    const responseFromOutline = !entry.response.trim();
    all.set(turn, {
      turn: turn, seq: projected?.seq ?? entry.sequence,
      anchorIndex: entry.firstUserIndex >= 0 ? entry.firstUserIndex : entry.firstIndex,
      prompt: promptFromOutline ? projected?.prompt ?? '' : entry.prompt,
      response: responseFromOutline ? projected?.response ?? '' : entry.response,
      promptFromOutline: promptFromOutline, responseFromOutline: responseFromOutline
    });
  });
  return Array.from(all.values()).sort((left: DesktopTurnOutlineItem, right: DesktopTurnOutlineItem): number =>
    left.turn - right.turn);
}

export function desktopTurnOutlineActiveTurn(items: DesktopTurnOutlineItem[], firstVisible: number): number {
  let lastAnchor = -1;
  let activeTurn = -1;
  let firstAnchor = Number.MAX_SAFE_INTEGER;
  let firstTurn = -1;
  for (const item of items) {
    if (item.anchorIndex < 0) { continue; }
    if (item.anchorIndex < firstAnchor) {
      firstAnchor = item.anchorIndex;
      firstTurn = item.turn;
    }
    if (item.anchorIndex <= firstVisible && item.anchorIndex >= lastAnchor) {
      lastAnchor = item.anchorIndex;
      activeTurn = item.turn;
    }
  }
  return activeTurn >= 0 ? activeTurn : firstTurn;
}

function maskedPrefix(source: string, limit: number): string {
  let text = '';
  let start = 0;
  for (const range of desktopSecretRanges(source)) {
    if (range.start >= limit) { break; }
    text += source.slice(start, range.start);
    text += range.masked.slice(0, Math.min(range.end, limit) - range.start);
    start = Math.min(range.end, limit);
  }
  return text + source.slice(start, limit);
}

/**
 * The server's ellipsis may cut a credential before its terminator. Avoid displaying the
 * incomplete token in that case, even when the shared scanner cannot classify it yet.
 */
function obscureClippedTail(value: string): string {
  if (!value.endsWith('…')) { return value; }
  const prefix = value.slice(0, -1);
  const address = new RegExp('([a-z][a-z0-9+.-]*://[^\\s/:@?#]{1,256}:)[^\\s/@?#]+$', 'u').exec(prefix);
  if (address !== null) { return prefix.slice(0, address.index) + address[1] + '****…'; }
  const tail = new RegExp('[A-Za-z0-9][A-Za-z0-9._:/@%+\\-]*$', 'u').exec(prefix);
  if (tail !== null && (tail[0].length > 8 || new RegExp('[_:/@%.+\\-]', 'u').test(tail[0]))) {
    return prefix.slice(0, tail.index) + '****…';
  }
  return value;
}

/** Called only for a shown preview. Redaction precedes the fixed display budget. */
export function desktopTurnOutlinePreview(source: string, isPrompt: boolean, fromOutline: boolean): string {
  const budget = isPrompt ? PROMPT_PREVIEW_LENGTH : RESPONSE_PREVIEW_LENGTH;
  const limit = Math.min(source.length, budget * 2);
  const masked = maskedPrefix(source, limit);
  const safe = fromOutline ? obscureClippedTail(masked) : masked;
  const text = safe.replace(WHITESPACE, ' ').trim();
  if (text.length >= budget) { return text.slice(0, budget - 1).trimEnd() + '…'; }
  return limit < source.length ? text + '…' : text;
}
