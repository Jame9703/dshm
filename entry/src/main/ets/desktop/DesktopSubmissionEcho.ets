import type { TrajectoryItem } from 'appstate';
import { getArray, getNumber, getRecord, getString } from 'connection';
import type { DesktopMediaAttachment } from './DesktopAttachments';

export interface DesktopSubmissionEcho {
  sessionId: string;
  requestId: string;
  placement: 'transcript' | 'steering';
  message: TrajectoryItem;
  attachments: DesktopMediaAttachment[];
}

interface SubmissionReceipt {
  target: string;
  index: number;
  sequence: number;
}

interface TrackedSubmission {
  echo: DesktopSubmissionEcho;
  accepted: boolean;
  receipt?: SubmissionReceipt;
}

function submissionId(message?: Object): string {
  const source = getRecord(message, 'source');
  return getString(source, 'kind') === 'user' ? getString(source, 'rpcId') ?? '' : '';
}

export class DesktopSubmissionEchoes {
  private readonly tracked: Map<string, TrackedSubmission> = new Map();
  private cachedSession: string = '';
  private dirty: boolean = false;
  private visible: DesktopSubmissionEcho[] = [];

  begin(echo: DesktopSubmissionEcho): void {
    if (!this.tracked.has(echo.requestId)) {
      this.tracked.set(echo.requestId, { echo: echo, accepted: false });
    }
  }

  accept(id: string): boolean {
    const entry = this.tracked.get(id);
    if (entry === undefined || entry.accepted) { return false; }
    entry.accepted = true;
    this.dirty = true;
    return true;
  }

  retire(id: string): boolean {
    const entry = this.tracked.get(id);
    if (entry === undefined) { return false; }
    this.tracked.delete(id);
    this.dirty = this.dirty || entry.accepted;
    return entry.accepted;
  }

  clear(): void {
    this.tracked.clear();
    this.dirty = true;
  }

  forSession(id: string): DesktopSubmissionEcho[] {
    if (this.dirty || id !== this.cachedSession) {
      this.cachedSession = id;
      this.visible = [];
      this.tracked.forEach((entry: TrackedSubmission): void => {
        if (entry.accepted && entry.echo.sessionId === id) { this.visible.push(entry.echo); }
      });
      this.dirty = false;
    }
    return this.visible;
  }

  observe(sessionId: string, event?: Object): void {
    if (this.tracked.size === 0) { return; }
    const type = getString(event, 'type');
    const data = getRecord(event, 'data');
    if (type === 'user/message') {
      const id = submissionId(data);
      if (this.tracked.get(id)?.echo.sessionId === sessionId) { this.retire(id); }
    } else if (type === 'agent/inbox/spliced') {
      this.observeSplice(sessionId, data, getNumber(event, 'seq') ?? -1);
    } else if (type === 'request/context' || type === 'turn/end') {
      const sequence = getNumber(event, 'seq') ?? -1;
      this.tracked.forEach((entry: TrackedSubmission, id: string): void => {
        const receipt = entry.receipt;
        if (entry.echo.sessionId === sessionId && receipt !== undefined && receipt.index === -1 &&
            receipt.sequence < sequence) { this.retire(id); }
      });
    }
  }

  observeInbox(sessionId: string, values: Object | undefined, sequence: number): boolean {
    if (this.tracked.size === 0 || sequence < 0) { return false; }
    const inbox = getRecord(values, 'inbox');
    let changed = false;
    for (const target of ['next-turn', 'next-step']) {
      const messages = getArray(inbox, target) ?? [];
      changed = this.observeInsertions(sessionId, target, messages, 0, sequence) || changed;
    }
    return changed;
  }

  private observeSplice(sessionId: string, data: Object | undefined, sequence: number): void {
    const target = getString(data, 'target') ?? '';
    const start = getNumber(data, 'start') ?? -1;
    if (!target || start < 0 || sequence < 0) { return; }
    const removed = getNumber(data, 'removedCount') ?? 0;
    const inserted = getArray(data, 'inserted') ?? [];
    const cancelled = getString(data, 'outcome') === 'canceled';
    this.tracked.forEach((entry: TrackedSubmission, id: string): void => {
      const receipt = entry.receipt;
      if (entry.echo.sessionId !== sessionId || receipt === undefined || receipt.target !== target ||
          receipt.index < 0 || receipt.sequence >= sequence) { return; }
      if (receipt.index >= start && receipt.index < start + removed) {
        if (cancelled) { this.retire(id); }
        else { entry.receipt = { target: target, sequence: sequence, index: -1 }; }
      } else {
        const index = receipt.index < start ? receipt.index : receipt.index + inserted.length - removed;
        entry.receipt = { target: target, sequence: sequence, index: index };
      }
    });
    this.observeInsertions(sessionId, target, inserted, start, sequence);
  }

  private observeInsertions(sessionId: string, target: string, messages: Object[],
    start: number, sequence: number): boolean {
    let changed = false;
    messages.forEach((message: Object, index: number): void => {
      const id = submissionId(message);
      const entry = this.tracked.get(id);
      if (entry !== undefined && entry.echo.sessionId === sessionId && (entry.receipt?.sequence ?? -1) <= sequence) {
        entry.receipt = { target: target, sequence: sequence, index: start + index };
        changed = this.accept(id) || changed;
      }
    });
    return changed;
  }
}
