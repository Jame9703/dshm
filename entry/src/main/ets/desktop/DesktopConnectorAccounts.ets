import { url } from '@kit.ArkTS';
import { getArray, getRecord, getString, toStringArray } from 'connection';
import { desktopAccountLocale } from './DesktopAccountClient';
import { DesktopHostActions } from './DesktopHostActions';

export interface DesktopConnectorPrompt {
  title: string;
  body: string;
  label: string;
}

export interface DesktopConnectorAction {
  kind: string;
  operation: string;
  label: string;
  variant: string;
  confirm?: DesktopConnectorPrompt;
}

export interface DesktopConnectorNote {
  text: string;
  action?: DesktopConnectorAction;
}

export interface DesktopConnectorAccount {
  key: string;
  packageName: string;
  title: string;
  hint: string;
  status: string;
  phase: string;
  badge: string;
  detail: string;
  failure: string;
  diagnostics: string[];
  actions: DesktopConnectorAction[];
  notes: DesktopConnectorNote[];
  activation?: DesktopConnectorPrompt;
  connect?: DesktopConnectorAction;
  operationId: string;
  authorize: string;
  resultId: string;
  notice: string;
}

interface FollowedOperation {
  id: string;
  opened: Set<string>;
}

function localized(value: Object | undefined, field: string, locale: string): string {
  const map = getRecord(value, field);
  const language = locale.toLowerCase();
  const base = language.split('-')[0];
  return getString(value, field) ?? getString(map, language) ?? getString(map, locale) ?? getString(map, base) ??
    getString(map, 'en') ?? '';
}

function promptFrom(value: Object | undefined, label: string, locale: string): DesktopConnectorPrompt | undefined {
  const title = localized(value, 'title', locale);
  const action = localized(value, label, locale);
  return title && action ? { title: title, body: localized(value, 'body', locale), label: action } : undefined;
}

function actionFrom(command: Object | undefined, label: string, variant: string = '',
  confirm?: DesktopConnectorPrompt): DesktopConnectorAction | undefined {
  const kind = getString(command, 'kind') ?? '';
  const operation = getString(command, 'operation') ?? '';
  if (kind !== 'cancel' && kind !== 'open' && (kind !== 'start' || !operation)) { return undefined; }
  return { kind: kind, operation: operation, label: label, variant: variant, confirm: confirm };
}

function buttonFrom(value: Object | undefined, locale: string): DesktopConnectorAction | undefined {
  const label = localized(value, 'label', locale);
  return label ? actionFrom(getRecord(value, 'command'), label, getString(value, 'variant') ?? '',
    promptFrom(getRecord(value, 'confirm'), 'label', locale)) : undefined;
}

function accountFrom(value: Object, locale: string): DesktopConnectorAccount | undefined {
  const key = getString(value, 'key') ?? '';
  const copy = getRecord(value, 'copy');
  const display = getRecord(value, 'display');
  if (!key || copy === undefined || display === undefined) { return undefined; }
  const activation = promptFrom(getRecord(copy, 'activation'), 'connect', locale);
  const operation = getRecord(value, 'operation');
  const result = getRecord(value, 'result');
  const failure = getRecord(display, 'failure');
  const actions: DesktopConnectorAction[] = [];
  for (const item of getArray(display, 'buttons') ?? []) {
    const action = buttonFrom(item, locale);
    if (action !== undefined) { actions.push(action); }
  }
  const notes: DesktopConnectorNote[] = [];
  for (const item of getArray(display, 'notes') ?? []) {
    const text = localized(item, 'text', locale);
    if (text) { notes.push({ text: text, action: buttonFrom(getRecord(item, 'button'), locale) }); }
  }
  return { key: key, packageName: getString(value, 'packageName') ?? '', title: localized(copy, 'title', locale),
    hint: localized(copy, 'hint', locale), status: localized(display, 'status', locale), phase: getString(display, 'phase') ?? '',
    badge: localized(display, 'badge', locale), detail: localized(display, 'detail', locale),
    failure: localized(failure, 'text', locale), diagnostics: toStringArray(getArray(failure, 'details') ?? []),
    actions: actions, notes: notes, activation: activation,
    connect: actionFrom(getRecord(display, 'connect'), activation?.label ?? '', 'primary'),
    operationId: getString(operation, 'id') ?? '', authorize: getString(operation, 'authorizationUrl') ?? '',
    resultId: getString(result, 'id') ?? '', notice: localized(result, 'notice', locale) };
}

function authorizationLink(value: string): string {
  if (!value) { return ''; }
  try {
    const parsed = url.URL.parseURL(value);
    const host = parsed.hostname;
    const local = host === '127.0.0.1' || host === 'localhost' || host === '[::1]';
    return parsed.protocol === 'https:' || (parsed.protocol === 'http:' && local) ? parsed.href : '';
  } catch (_) { return ''; }
}

function sameCommand(first: DesktopConnectorAction, second: DesktopConnectorAction): boolean {
  return first.kind === second.kind && first.operation === second.operation &&
    first.confirm?.title === second.confirm?.title && first.confirm?.body === second.confirm?.body &&
    first.confirm?.label === second.confirm?.label;
}

@Observed
export class DesktopConnectorAccounts {
  accounts: DesktopConnectorAccount[] = [];
  linked: boolean = false;
  pending: string[] = [];
  private readonly host: DesktopHostActions;
  private readonly openLink: (link: string) => Promise<boolean>;
  private readonly notice: (message: ResourceStr) => void;
  private readonly followed: Map<string, FollowedOperation> = new Map();
  private readonly watchers: Set<() => void> = new Set();
  private entries: Object[] = [];
  private localePreference: string = 'system';
  private locale: string = '';
  private active: boolean = true;
  private requested: boolean = false;
  private streamVersion: number = 0;
  private stopWatch?: () => void;

  constructor(host: DesktopHostActions, openLink: (link: string) => Promise<boolean>,
    notice: (message: ResourceStr) => void) {
    this.host = host;
    this.openLink = openLink;
    this.notice = notice;
  }

  watch(listener: () => void): () => void {
    this.watchers.add(listener);
    if (!this.requested) { this.locale = desktopAccountLocale(this.localePreference); }
    this.requested = true;
    this.reconnect();
    return (): void => { this.watchers.delete(listener); };
  }

  reconnect(): void {
    if (!this.active || !this.requested || this.stopWatch !== undefined) { return; }
    const version = ++this.streamVersion;
    const end = (): void => {
      if (version !== this.streamVersion) { return; }
      this.stopWatch = undefined;
      this.linked = false;
    };
    this.stopWatch = this.host.watch('connectorAccounts/watch', {}, {
      onItem: (value: Object): void => {
        if (version !== this.streamVersion) { return; }
        const accounts = getArray(value, 'accounts');
        if (accounts !== undefined) {
          this.entries = accounts;
          this.linked = true;
          this.project();
        }
      },
      onError: end, onEnd: end
    });
  }

  dispose(): void {
    this.active = false;
    this.streamVersion++;
    this.stopWatch?.();
    this.stopWatch = undefined;
    this.followed.clear();
    this.watchers.clear();
  }

  setLocale(preference: string): void {
    this.localePreference = preference;
    if (!this.requested) { return; }
    const locale = desktopAccountLocale(preference);
    if (this.locale !== locale) { this.locale = locale; this.project(); }
  }

  byBundle(name: string): DesktopConnectorAccount | undefined {
    if (!name) { return undefined; }
    return this.accounts.find((account: DesktopConnectorAccount): boolean => account.packageName === name);
  }

  async run(selected: DesktopConnectorAccount, action: DesktopConnectorAction, activate: boolean = false): Promise<void> {
    const account = this.byKey(selected.key);
    if (!this.active || !this.linked || account === undefined || this.pending.includes(account.key) ||
      !this.isCurrentAction(account, action, activate)) { return; }
    if (action.kind !== 'start' && (!account.operationId || account.operationId !== selected.operationId)) { return; }
    if (action.kind === 'open') { this.authorize(account.authorize, true); return; }
    this.pending = [...this.pending, account.key];
    try {
      if (action.kind === 'cancel') {
        const result = await this.host.call('connectorAccounts/cancel', { 'key': account.key, 'id': account.operationId }, 60000);
        if (!result.ok) { this.reportFailure(); }
      } else {
        const result = await this.host.call('connectorAccounts/start', { 'key': account.key, 'operation': action.operation });
        if (!this.active) { return; }
        const id = typeof result.value === 'string' && result.ok ? result.value : '';
        if (!id) { this.reportFailure(); return; }
        this.followed.set(account.key, { id: id, opened: new Set() });
        const latest = this.byKey(account.key);
        if (latest !== undefined && this.linked) { this.track(latest); }
      }
    } catch (_) {
      this.reportFailure();
    } finally {
      this.pending = this.pending.filter((key: string): boolean => key !== account.key);
    }
  }

  private isCurrentAction(account: DesktopConnectorAccount, action: DesktopConnectorAction, activate: boolean): boolean {
    if (activate) { return account.phase === 'disconnected' && account.connect !== undefined && sameCommand(account.connect, action); }
    return account.actions.some((item: DesktopConnectorAction): boolean => sameCommand(item, action)) ||
      account.notes.some((item: DesktopConnectorNote): boolean => item.action !== undefined && sameCommand(item.action, action));
  }

  private byKey(key: string): DesktopConnectorAccount | undefined {
    return this.accounts.find((account: DesktopConnectorAccount): boolean => account.key === key);
  }

  private project(): void {
    const next: DesktopConnectorAccount[] = [];
    for (const item of this.entries) {
      const account = accountFrom(item, this.locale);
      if (account !== undefined) { next.push(account); }
    }
    this.accounts = next;
    if (this.linked) {
      for (const key of this.followed.keys()) {
        if (this.byKey(key) === undefined) { this.followed.delete(key); }
      }
      this.accounts.forEach((account: DesktopConnectorAccount): void => { this.track(account); });
      this.watchers.forEach((listener: () => void): void => { listener(); });
    }
  }

  private track(account: DesktopConnectorAccount): void {
    const followed = this.followed.get(account.key);
    if (followed === undefined) { return; }
    if (account.resultId === followed.id) {
      this.followed.delete(account.key);
      if (account.notice) { this.notice(account.notice); }
    } else if (account.operationId === followed.id && account.authorize && !followed.opened.has(account.authorize)) {
      followed.opened.add(account.authorize);
      this.authorize(account.authorize, false);
    }
  }

  private async authorize(value: string, explicit: boolean): Promise<void> {
    const link = authorizationLink(value);
    if (!link) { if (explicit) { this.reportFailure(); } return; }
    if (!(await this.openLink(link))) { this.reportFailure(); }
  }

  private reportFailure(): void {
    if (this.active) { this.notice($r('app.string.desktop_connector_failed')); }
  }
}
