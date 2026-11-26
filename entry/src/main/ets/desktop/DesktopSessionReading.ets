import { getArray, getBoolean, getNumber, getRecord, getString } from 'connection';
import type { StreamSink } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';

const FOLLOW: string = 'sessionStatus/follow';
const MARK: string = 'sessionStatus/mark';

interface ReadingRecord {
  sessionId: string;
  completedTurn: number;
  readTurn: number;
  manualUnread: boolean;
  failed: boolean;
}

export interface DesktopUnreadSession {
  id: string;
  failed: boolean;
}

function readingRecord(raw?: Object): ReadingRecord | undefined {
  const id = getString(raw, 'sessionId') ?? '';
  if (!id) { return undefined; }
  return { sessionId: id, completedTurn: getNumber(raw, 'completedTurn') ?? 0,
    readTurn: getNumber(raw, 'readTurn') ?? 0, manualUnread: getBoolean(raw, 'manualUnread') === true,
    failed: getBoolean(raw, 'failed') === true };
}

function isUnread(row?: ReadingRecord): boolean {
  return row !== undefined && (row.manualUnread || row.completedTurn > row.readTurn);
}

export class DesktopSessionReading {
  private readonly host: DesktopHostActions;
  private readonly listener: (items: DesktopUnreadSession[], ready: boolean) => void;
  private readonly afterFrame: (run: () => void) => void;
  private records: Map<string, ReadingRecord> = new Map<string, ReadingRecord>();
  private readonly writing: Set<string> = new Set<string>();
  private cancelStream?: () => void;
  private streamGeneration: number = 0;
  private retry: number = -1;
  private attempts: number = 0;
  private closed: boolean = false;
  private ready: boolean = false;
  private sessionId: string = '';
  private historyLoaded: boolean = false;
  private receivedThrough: number = 0;
  private visible: boolean = false;
  private entering: boolean = false;
  private attemptedTurn: number = -1;
  private confirming: boolean = false;
  private frameQueued: boolean = false;

  constructor(host: DesktopHostActions, listener: (items: DesktopUnreadSession[], ready: boolean) => void,
    afterFrame: (run: () => void) => void) {
    this.host = host;
    this.listener = listener;
    this.afterFrame = afterFrame;
  }

  connect(): void {
    if (this.closed || this.cancelStream !== undefined || this.retry !== -1) { return; }
    this.attempts = 0;
    this.open();
  }

  private open(): void {
    const generation = ++this.streamGeneration;
    const sink: StreamSink = {
      onItem: (frame: Object): void => { if (generation === this.streamGeneration) { this.receive(frame); } },
      onEnd: (): void => { this.ended(generation); },
      onError: (): void => { this.ended(generation); }
    };
    this.cancelStream = this.host.watch(FOLLOW, {}, sink);
    if (this.cancelStream === undefined) { this.ended(generation); }
  }

  private ended(generation: number): void {
    if (this.closed || generation !== this.streamGeneration) { return; }
    this.streamGeneration++;
    this.cancelStream = undefined;
    if (this.ready) {
      this.ready = false;
      this.publish();
    }
    if (this.attempts < 3) {
      this.attempts++;
      this.retry = setTimeout((): void => {
        this.retry = -1;
        this.open();
      }, 1000 * this.attempts);
    }
  }

  private receive(frame: Object): void {
    const type = getString(frame, 'type');
    if (type === 'baseline') {
      this.records.clear();
      for (const raw of getArray(frame, 'items') ?? []) {
        const row = readingRecord(raw);
        if (row !== undefined) { this.records.set(row.sessionId, row); }
      }
      this.ready = true;
      this.attempts = 0;
      this.attemptedTurn = -1;
      this.publish();
    } else if (type === 'changed' && this.ready) {
      const row = readingRecord(getRecord(frame, 'state'));
      if (row === undefined) { return; }
      const previous = this.records.get(row.sessionId);
      this.records.set(row.sessionId, row);
      if (isUnread(previous) !== isUnread(row) || (isUnread(row) && previous?.failed !== row.failed)) {
        this.publish();
      }
    } else {
      return;
    }
    this.settleEntry();
    this.schedule();
  }

  show(sessionId: string, loaded: boolean, receivedThrough: number, visible: boolean): void {
    if (this.sessionId === sessionId && this.historyLoaded === loaded &&
      this.receivedThrough === receivedThrough && this.visible === visible) { return; }
    if (this.sessionId !== sessionId) {
      this.sessionId = sessionId;
      this.entering = sessionId.length > 0;
      this.attemptedTurn = -1;
      this.settleEntry();
    } else if (this.visible !== visible && visible) {
      this.attemptedTurn = -1;
    }
    this.historyLoaded = loaded;
    this.receivedThrough = receivedThrough;
    this.visible = visible;
    this.schedule();
  }

  private settleEntry(): void {
    if (this.ready && !this.records.get(this.sessionId)?.manualUnread) { this.entering = false; }
  }

  private pendingRecord(): ReadingRecord | undefined {
    if (!this.visible || !this.ready || !this.historyLoaded || this.confirming) { return undefined; }
    const row = this.records.get(this.sessionId);
    if (row === undefined || this.receivedThrough < row.completedTurn || this.attemptedTurn === row.completedTurn) {
      return undefined;
    }
    return this.entering || row.completedTurn > row.readTurn ? row : undefined;
  }

  private schedule(): void {
    if (this.closed || this.frameQueued || this.pendingRecord() === undefined) { return; }
    this.frameQueued = true;
    this.afterFrame((): void => {
      this.frameQueued = false;
      this.acknowledge();
    });
  }

  private async acknowledge(): Promise<void> {
    const row = this.pendingRecord();
    if (this.closed || row === undefined) { return; }
    const type = this.entering ? 'read' : 'acknowledge';
    this.entering = false;
    this.attemptedTurn = row.completedTurn;
    this.confirming = true;
    try {
      await this.write(row.sessionId, type, row.completedTurn);
    } finally {
      this.confirming = false;
      this.schedule();
    }
  }

  async mark(sessionId: string): Promise<string> {
    if (!this.ready) { return '阅读状态暂不可用'; }
    if (this.writing.has(sessionId)) { return ''; }
    this.writing.add(sessionId);
    const row = this.records.get(sessionId);
    try {
      return await this.write(sessionId, isUnread(row) ? 'read' : 'unread', row?.completedTurn ?? 0);
    } finally {
      this.writing.delete(sessionId);
    }
  }

  private async write(sessionId: string, type: string, throughTurn: number): Promise<string> {
    const action: Record<string, Object> = { 'type': type };
    if (type !== 'unread') { action['throughTurn'] = throughTurn; }
    const result = await this.host.call(MARK, { 'sessionId': sessionId, 'action': action });
    return result.ok ? '' : '未能确认阅读状态，请重试';
  }

  private publish(): void {
    const items: DesktopUnreadSession[] = [];
    this.records.forEach((row: ReadingRecord): void => {
      if (isUnread(row)) { items.push({ id: row.sessionId, failed: row.failed }); }
    });
    this.listener(items, this.ready);
  }

  close(): void {
    this.closed = true;
    this.streamGeneration++;
    this.cancelStream?.();
    if (this.retry !== -1) { clearTimeout(this.retry); }
  }
}
