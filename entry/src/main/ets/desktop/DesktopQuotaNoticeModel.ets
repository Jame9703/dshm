import { getNumber, getRecord, getString } from 'connection';

export type DesktopQuotaNoticeCode = 'QUOTA' | 'ACCOUNT_QUOTA';

export interface DesktopQuotaNotice {
  token: number;
  sessionId: string;
  sequence: number;
  code: DesktopQuotaNoticeCode;
}

const RECENT_QUOTA_EVENTS: number = 256;

/** One notice per frame shared by the live main and dock sessions. */
export class DesktopQuotaNoticeModel {
  private readonly recent: Set<string> = new Set<string>();
  private readonly holds: Set<number> = new Set<number>();
  private current: DesktopQuotaNotice | undefined = undefined;
  private nextNotice: number = 0;
  private nextHold: number = 0;

  observe(sessionId: string, record: Object, live: boolean): boolean {
    if (!live || !sessionId) { return false; }
    const event = getRecord(record, 'event');
    if (getString(event, 'type') !== 'turn/end') { return false; }
    const sequence = getNumber(event, 'seq') ?? -1;
    if (!Number.isSafeInteger(sequence) || sequence < 0) { return false; }
    const reason = getRecord(getRecord(event, 'data'), 'reason');
    if (getString(reason, 'kind') !== 'error') { return false; }
    const code = getString(getRecord(reason, 'error'), 'code');
    if (code !== 'QUOTA' && code !== 'ACCOUNT_QUOTA') { return false; }

    const key = `${sessionId}\u0000${sequence}`;
    if (this.recent.has(key)) { return false; }
    this.recent.add(key);
    if (this.recent.size > RECENT_QUOTA_EVENTS) {
      const oldest = this.recent.values().next();
      if (!oldest.done) { this.recent.delete(oldest.value); }
    }
    // The same event may arrive again from another panel after the hold ends.
    if (this.holds.size > 0) { return false; }
    this.current = { token: ++this.nextNotice, sessionId: sessionId, sequence: sequence, code: code };
    return true;
  }

  snapshot(): DesktopQuotaNotice | undefined { return this.current; }

  dismiss(token: number): boolean {
    if (this.current?.token !== token) { return false; }
    this.holds.clear();
    this.current = undefined;
    return true;
  }

  hold(token: number): () => void {
    if (this.current?.token !== token) { return (): void => {}; }
    const hold = ++this.nextHold;
    this.holds.add(hold);
    return (): void => { this.holds.delete(hold); };
  }

  clear(): void {
    this.recent.clear();
    this.holds.clear();
    this.current = undefined;
  }
}
