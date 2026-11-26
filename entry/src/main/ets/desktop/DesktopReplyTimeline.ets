import { getNumber, getRecord, getString } from 'connection';

export interface DesktopReplyTail {
  turn: number;
  messageId: string;
  text: string;
  messageSeq: number;
  endSeq: number;
  responseTime: number;
}

/** Pair the last durable text reply with its completed turn, including paged history. */
export class DesktopReplyTimeline {
  private readonly tails: Map<number, DesktopReplyTail> = new Map<number, DesktopReplyTail>();

  clear(): void {
    this.tails.clear();
  }

  observe(event: Object | undefined, assistantText: string = ''): void {
    const type = getString(event, 'type');
    const appendReply = type === 'assistant/message' && getString(event, 'surfaceOp') === 'append' &&
      assistantText.trim().length > 0;
    if (type !== 'turn/end' && !appendReply) { return; }
    const data = getRecord(event, 'data');
    const turn = getNumber(data, 'turn') ?? -1;
    const seq = getNumber(event, 'seq') ?? -1;
    if (turn < 0 || seq < 0) { return; }
    const row: DesktopReplyTail = this.tails.get(turn) ?? {
      turn: turn, messageId: '', text: '', messageSeq: -1, endSeq: -1, responseTime: 0
    };
    if (type === 'turn/end') {
      row.endSeq = Math.max(row.endSeq, seq);
    } else if (seq > row.messageSeq) {
      const id = getString(getRecord(data, 'message'), 'id') ?? '';
      if (!id) { return; }
      row.messageId = id;
      row.text = assistantText;
      row.messageSeq = seq;
      row.responseTime = getNumber(event, 'time') ?? 0;
    }
    this.tails.set(turn, row);
  }

  completed(): DesktopReplyTail[] {
    const rows: DesktopReplyTail[] = [];
    this.tails.forEach((row: DesktopReplyTail): void => {
      if (row.messageId && row.endSeq > row.messageSeq) { rows.push(row); }
    });
    return rows;
  }
}
