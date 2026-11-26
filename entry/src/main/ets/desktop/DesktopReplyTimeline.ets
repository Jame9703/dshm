import { getNumber, getRecord, getString } from 'connection';

export interface DesktopReplyTail {
  turn: number;
  messageId: string;
  text: string;
  messageSeq: number;
  endSeq: number;
  responseTime: number;
  lastContentSeq: number;
}

/** Pair the last durable text reply with its completed turn, including paged history. */
export class DesktopReplyTimeline {
  private readonly tails: Map<number, DesktopReplyTail> = new Map<number, DesktopReplyTail>();

  clear(): void {
    this.tails.clear();
  }

  observe(event: Object | undefined, assistantText: string = ''): void {
    const type = getString(event, 'type');
    const data = getRecord(event, 'data');
    const append = getString(event, 'surfaceOp') === 'append';
    const assistant = type === 'assistant/message' && append;
    const end = type === 'turn/end';
    const visible = assistant || type === 'tool/call' || (type === 'tool/result' && append) ||
      type === 'llm/retry' || (end && getString(getRecord(data, 'reason'), 'kind') === 'error');
    if (!end && !visible) { return; }
    const turn = getNumber(data, 'turn') ?? -1;
    const seq = getNumber(event, 'seq') ?? -1;
    if (turn < 0 || seq < 0) { return; }
    const row: DesktopReplyTail = this.tails.get(turn) ?? {
      turn: turn, messageId: '', text: '', messageSeq: -1, endSeq: -1, responseTime: 0, lastContentSeq: -1
    };
    if (visible) { row.lastContentSeq = Math.max(row.lastContentSeq, seq); }
    if (end) {
      row.endSeq = Math.max(row.endSeq, seq);
    } else if (assistant && assistantText.trim().length > 0 && seq > row.messageSeq) {
      const id = getString(getRecord(data, 'message'), 'id') ?? '';
      if (!id) { return; }
      row.messageId = id;
      row.text = assistantText;
      row.messageSeq = seq;
      row.responseTime = getNumber(event, 'time') ?? 0;
    }
    this.tails.set(turn, row);
  }

  canFork(endSeq: number): boolean {
    return this.completed().some((row: DesktopReplyTail): boolean =>
      row.endSeq === endSeq && row.lastContentSeq === row.messageSeq);
  }

  completed(): DesktopReplyTail[] {
    const rows: DesktopReplyTail[] = [];
    this.tails.forEach((row: DesktopReplyTail): void => {
      if (row.messageId && row.endSeq > row.messageSeq) { rows.push(row); }
    });
    return rows;
  }
}

function incrementForkTitle(title: string): string {
  const ascii = new RegExp('^(.*?)\\((\\d+)\\)$').exec(title);
  if (ascii !== null) { return `${ascii[1]}(${BigInt(ascii[2]) + BigInt(1)})`; }
  const wide = new RegExp('^(.*?)（(\\d+)）$').exec(title);
  if (wide !== null) { return `${wide[1]}（${BigInt(wide[2]) + BigInt(1)}）`; }
  return `${title} (1)`;
}

export function desktopForkTitle(title: string, taken: Set<string>): string {
  let candidate = incrementForkTitle(title);
  while (taken.has(candidate)) { candidate = incrementForkTitle(candidate); }
  return candidate;
}
