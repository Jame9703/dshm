import { getArray, getNumber, getRecord, getString } from 'connection';
import { desktopAccountLocale, desktopAccountMetadata } from './DesktopAccountClient';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopAccountSettingsIdentity, emptyDesktopAccountSettingsIdentity } from './DesktopAccountSettingsModel';

export interface DesktopAccountNoticeAction {
  label: string;
  primary: boolean;
  target: string;
}

export interface DesktopAccountNotice {
  id: string;
  title: string;
  body: string;
  expiresAt: number;
  actions: DesktopAccountNoticeAction[];
}

const DEFAULT_POLL_MS: number = 600000;
const MAX_TIMER_MS: number = 2147483647;

function projectNotice(raw: Object | undefined): DesktopAccountNotice | undefined {
  const id = getString(raw, 'id') ?? '';
  const title = getString(raw, 'title');
  const body = getString(raw, 'body');
  if (!id || title === undefined || body === undefined) { return undefined; }
  const end = Date.parse(getString(raw, 'displayUntil') ?? '');
  const actions: DesktopAccountNoticeAction[] = [];
  for (const row of getArray(raw, 'actions') ?? []) {
    const label = getString(row, 'label') ?? '';
    const target = getRecord(row, 'target');
    const type = getString(target, 'type');
    if (label && (type === 'dismiss' || (type === 'app_route' && getString(target, 'name') === 'account'))) {
      actions.push({ label: label, primary: getString(row, 'style') === 'primary', target: type });
    }
  }
  return { id: id, title: title, body: body, expiresAt: Number.isFinite(end) ? end : 0, actions: actions };
}

function liveNotice(notice: DesktopAccountNotice, at: number): boolean {
  return notice.expiresAt === 0 || notice.expiresAt > at;
}

export class DesktopAccountNotices {
  private readonly host: DesktopHostActions;
  private readonly publish: (notices: DesktopAccountNotice[]) => void;
  private active: boolean = true;
  private signedIn: boolean = false;
  private watchVersion: number = 0;
  private accountVersion: number = 0;
  private localeVersion: number = 0;
  private locale: string = desktopAccountLocale();
  private stopWatch?: () => void;
  private poll: number = -1;
  private expiry: number = -1;
  private interval: number = DEFAULT_POLL_MS;
  private current: DesktopAccountNotice[] = [];
  private accountIdentity: DesktopAccountSettingsIdentity = emptyDesktopAccountSettingsIdentity();
  private accountObservers?: Set<(identity: DesktopAccountSettingsIdentity) => void>;
  private readonly displayed: Set<string> = new Set<string>();
  private readonly dismissed: Set<string> = new Set<string>();

  constructor(host: DesktopHostActions, publish: (notices: DesktopAccountNotice[]) => void) {
    this.host = host;
    this.publish = publish;
  }

  observeAccount(listener: (identity: DesktopAccountSettingsIdentity) => void): () => void {
    if (this.accountObservers === undefined) {
      this.accountObservers = new Set<(identity: DesktopAccountSettingsIdentity) => void>();
    }
    this.accountObservers.add(listener);
    listener(this.accountIdentity);
    return (): void => { this.accountObservers?.delete(listener); };
  }

  private publishAccount(state?: Object): void {
    const previous = this.accountIdentity;
    const signedIn = getString(state, 'status') === 'credential-stored';
    const links = signedIn ? getRecord(state, 'links') : undefined;
    const usageUrl = getString(links, 'usageUrl') ?? '';
    const topUpUrl = getString(links, 'topUpUrl') ?? '';
    if (previous.ready && signedIn === previous.signedIn && (!signedIn || (previous.revision === this.accountVersion &&
      previous.usageUrl === usageUrl && previous.topUpUrl === topUpUrl))) { return; }
    this.accountIdentity = { ready: true, signedIn: signedIn, revision: this.accountVersion,
      usageUrl: usageUrl, topUpUrl: topUpUrl };
    this.accountObservers?.forEach((listener: (identity: DesktopAccountSettingsIdentity) => void): void => {
      listener(this.accountIdentity);
    });
  }

  connect(): void {
    if (!this.active || this.stopWatch !== undefined) { return; }
    const version = ++this.watchVersion;
    const ended = (): void => {
      if (version === this.watchVersion) {
        this.watchVersion++;
        this.stopWatch = undefined;
        this.clearAccount();
        this.publishAccount();
      }
    };
    this.stopWatch = this.host.watch('account/watch', {}, {
      onItem: (frame: Object): void => {
        if (version !== this.watchVersion) { return; }
        const state = getRecord(frame, 'state');
        if (state === undefined) { return; }
        if (getString(frame, 'type') === 'credentials-changed' || getString(state, 'status') !== 'credential-stored') {
          this.clearAccount();
        }
        if (!this.signedIn && getString(state, 'status') === 'credential-stored') {
          this.signedIn = true;
          this.read(this.accountVersion);
        }
        this.publishAccount(state);
      },
      onError: ended,
      onEnd: ended
    });
    if (this.stopWatch === undefined) { ended(); }
  }

  stop(): void {
    this.active = false;
    this.watchVersion++;
    this.stopWatch?.();
    this.stopWatch = undefined;
    this.clearAccount();
    this.publishAccount();
    this.accountObservers?.clear();
  }

  private clearAccount(): void {
    this.signedIn = false;
    this.accountVersion++;
    clearTimeout(this.poll);
    clearTimeout(this.expiry);
    this.interval = DEFAULT_POLL_MS;
    this.displayed.clear();
    this.dismissed.clear();
    if (this.current.length > 0) {
      this.current = [];
      this.publish([]);
    }
  }

  setLocale(preference: string): void {
    const locale = desktopAccountLocale(preference);
    if (locale === this.locale) { return; }
    this.locale = locale;
    const language = ++this.localeVersion;
    if (!this.signedIn) { return; }
    for (const notice of this.current) { this.translate(notice.id, this.accountVersion, language); }
  }

  private async translate(id: string, account: number, language: number): Promise<void> {
    const result = await this.host.call('account/getNotificationContent', {
      'id': id, 'client': desktopAccountMetadata(this.locale)
    });
    if (this.accountVersion !== account || this.localeVersion !== language || !result.ok) { return; }
    const updated = projectNotice(result.value);
    if (updated?.id === id) {
      this.replace(this.current.map((notice: DesktopAccountNotice): DesktopAccountNotice => {
        if (notice.id !== id) { return notice; }
        return { id: id, title: updated.title, body: updated.body, actions: updated.actions, expiresAt: notice.expiresAt };
      }));
    }
  }

  private async read(account: number): Promise<void> {
    const language = this.localeVersion;
    const result = await this.host.call('account/getNotifications', { 'client': desktopAccountMetadata(this.locale) });
    if (this.accountVersion !== account) { return; }
    const values = result.ok ? getArray(result.value, 'notifications') : undefined;
    if (values !== undefined) {
      const proposed = getNumber(result.value, 'nextPollAfterSeconds') ?? 0;
      if (proposed > 0 && Number.isFinite(proposed)) { this.interval = Math.min(MAX_TIMER_MS, Math.max(1, proposed * 1000)); }
      this.acceptBatch(values, language !== this.localeVersion);
    }
    clearTimeout(this.poll);
    this.poll = setTimeout((): void => { this.read(account); }, this.interval);
  }

  private acceptBatch(values: Object[], localeChanged: boolean): void {
    const seen = new Set<string>();
    const batch: DesktopAccountNotice[] = [];
    for (const row of values) {
      const notice = projectNotice(row);
      if (notice === undefined || seen.has(notice.id)) { continue; }
      seen.add(notice.id);
      const existing = localeChanged ? this.current.find(
        (entry: DesktopAccountNotice): boolean => entry.id === notice.id) : undefined;
      if (existing !== undefined) {
        notice.title = existing.title;
        notice.body = existing.body;
        notice.actions = existing.actions;
      }
      batch.push(notice);
    }
    const front = this.current[0];
    if (front !== undefined && this.displayed.has(front.id)) {
      const incoming = batch.find((entry: DesktopAccountNotice): boolean => entry.id === front.id);
      this.replace([incoming ?? front, ...batch.filter((entry: DesktopAccountNotice): boolean => entry.id !== front.id)]);
    } else {
      this.replace(batch);
    }
    if (localeChanged) {
      for (const notice of this.current) { this.translate(notice.id, this.accountVersion, this.localeVersion); }
    }
  }

  private replace(notices: DesktopAccountNotice[]): void {
    const now = Date.now();
    const current = notices.filter((entry: DesktopAccountNotice): boolean =>
      !this.dismissed.has(entry.id) && liveNotice(entry, now));
    if (JSON.stringify(current) !== JSON.stringify(this.current)) {
      this.current = current;
      this.publish(current);
    }
    const expires = current.reduce((soonest: number, entry: DesktopAccountNotice): number =>
      entry.expiresAt > now && entry.expiresAt < soonest ? entry.expiresAt : soonest, Infinity);
    clearTimeout(this.expiry);
    if (Number.isFinite(expires)) {
      this.expiry = setTimeout((): void => { this.replace(this.current); }, Math.min(MAX_TIMER_MS, expires - now));
    }
  }

  reportDisplayed(id: string): void {
    if (this.isCurrent(id) && !this.displayed.has(id)) {
      this.displayed.add(id);
      this.report(id, 'displayed');
    }
  }

  openAccount(id: string): boolean {
    if (!this.isCurrent(id)) { return false; }
    this.report(id, 'cta_clicked');
    return true;
  }

  dismiss(id: string): void {
    if (!this.isCurrent(id)) { return; }
    this.report(id, 'dismissed');
    this.dismissed.add(id);
    this.replace(this.current);
  }

  private isCurrent(id: string): boolean {
    return this.signedIn && this.current[0]?.id === id && liveNotice(this.current[0], Date.now());
  }

  private report(id: string, event: string): void {
    this.host.call('account/reportNotificationEvent', { 'id': id, 'event': event,
      'client': desktopAccountMetadata(this.locale) });
  }
}
