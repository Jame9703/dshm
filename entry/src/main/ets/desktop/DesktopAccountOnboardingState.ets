import { getArray, getBoolean, getField, getNumber, getRecord, getString, isStringArray, toStringArray } from 'connection';
import { CREDENTIALS_DESCRIBE_ENDPOINT, LLM_LIST_CONFIGURABLE_PROVIDERS_ENDPOINT, SETTINGS_MUTATE_ENDPOINT } from 'dshcompat';
import { desktopAccountLocale, desktopAccountMetadata } from './DesktopAccountClient';
import { desktopAccountPlatformLink } from './DesktopAccountSettingsModel';
import type { DesktopHostActions } from './DesktopHostActions';
import { readDesktopPluginDocument } from './DesktopPluginSettingsModel';
import type { DesktopPluginDocument } from './DesktopPluginSettingsModel';

export const DESKTOP_ACCOUNT_ONBOARDING_NS: string = 'ui-settings-account';
const CHAT_NS: string = 'ui-chat';
const TOOLS_NS: string = 'ui-settings';

export type DesktopOnboardingStep = 'welcome' | 'credit' | 'purpose' | 'process' | 'done';
export type DesktopOnboardingPurpose = '' | 'office' | 'development' | 'both';
export type DesktopOnboardingProcess = '' | 'compact' | 'standard' | 'detailed';

interface DesktopOnboardingProgress {
  step: DesktopOnboardingStep;
  purpose: DesktopOnboardingPurpose;
  process: DesktopOnboardingProcess;
  completion: string;
  usage: string;
  developerTools: boolean;
}

export interface DesktopOnboardingView {
  visible: boolean;
  loading: boolean;
  busy: boolean;
  error: boolean;
  step: DesktopOnboardingStep;
  purpose: DesktopOnboardingPurpose;
  process: DesktopOnboardingProcess;
  funded: boolean;
  zeroBalance: boolean;
  topUpUrl: string;
}

interface DesktopOnboardingWrite {
  before: DesktopOnboardingProgress;
  next: DesktopOnboardingProgress;
  applyPreferences: boolean;
}

interface DesktopOnboardingField {
  name: string;
  value: Object | null;
}

interface DesktopOnboardingOp {
  op: string;
  path: string[];
  value: Object | null;
}

export function emptyDesktopOnboardingView(): DesktopOnboardingView {
  return { visible: false, loading: false, busy: false, error: false, step: 'welcome', purpose: '', process: '',
    funded: false, zeroBalance: false, topUpUrl: '' };
}

function readProgress(value?: Object): DesktopOnboardingProgress {
  const step = getString(value, 'step');
  const purpose = getString(value, 'purpose');
  const process = getString(value, 'process');
  return {
    step: step === 'credit' || step === 'purpose' || step === 'process' || step === 'done' ? step : 'welcome',
    purpose: purpose === 'office' || purpose === 'development' || purpose === 'both' ? purpose : '',
    process: process === 'compact' || process === 'standard' || process === 'detailed' ? process : '',
    completion: getString(value, 'completion') ?? '', usage: getString(value, 'usage') ?? 'compact',
    developerTools: getBoolean(value, 'developerTools') === true
  };
}

function progressFields(value: DesktopOnboardingProgress): DesktopOnboardingField[] {
  return [{ name: 'version', value: 1 }, { name: 'step', value: value.step },
    { name: 'purpose', value: value.purpose || null }, { name: 'process', value: value.process || null },
    { name: 'completion', value: value.completion || null }, { name: 'usage', value: value.usage },
    { name: 'developerTools', value: value.developerTools }];
}

function copyProgress(value: DesktopOnboardingProgress): DesktopOnboardingProgress {
  return { step: value.step, purpose: value.purpose, process: value.process, completion: value.completion,
    usage: value.usage, developerTools: value.developerTools };
}

function hasPositiveWallet(wallets: Object[]): boolean {
  const decimal = /^\+?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i;
  return wallets.some((wallet: Object): boolean => {
    const balance = getString(wallet, 'balance') ?? '';
    return decimal.test(balance) && /[1-9]/.test(balance.split(/[eE]/)[0]);
  });
}

export class DesktopAccountOnboardingState {
  private readonly host: DesktopHostActions;
  private readonly onChange: (view: DesktopOnboardingView) => void;
  private readonly readSettings: () => Promise<void>;
  private readonly documents: Map<string, DesktopPluginDocument> = new Map<string, DesktopPluginDocument>();
  private lastView: DesktopOnboardingView = emptyDesktopOnboardingView();
  private active: boolean = true;
  private accountStatus: string = '';
  private accountEpoch: number = 0;
  private topUpUrl: string = '';
  private locale: string = 'system';
  private settingsReady: boolean = false;
  private settingsFailed: boolean = false;
  private writable: boolean = false;
  private saving: boolean = false;
  private retrying: boolean = false;
  private pendingRetry?: DesktopOnboardingWrite;
  private balance?: boolean;
  private creditFunded?: boolean;
  private balanceRequested: boolean = false;
  private balanceEpoch: number = 0;
  private credentialEpoch: number = 0;
  private checkedCredentials: boolean = false;
  private credentialNamespaces: Object[] = [];
  private credentialSettingsRevisions: string = '';

  constructor(host: DesktopHostActions, onChange: (view: DesktopOnboardingView) => void,
    readSettings: () => Promise<void>) {
    this.host = host;
    this.onChange = onChange;
    this.readSettings = readSettings;
  }

  setLocale(locale: string): void { this.locale = locale; }

  observeSettings(value?: Object): void {
    if (!this.active) { return; }
    if (value === undefined) {
      this.settingsFailed = !this.settingsReady;
      this.publish();
      return;
    }
    this.settingsReady = true;
    this.settingsFailed = false;
    this.writable = getBoolean(value, 'writable') === true;
    const rows = getArray(value, 'namespaces') ?? [];
    for (const ns of [DESKTOP_ACCOUNT_ONBOARDING_NS, CHAT_NS, TOOLS_NS]) {
      const next = readDesktopPluginDocument(rows.find((row: Object): boolean => getString(row, 'ns') === ns));
      if (next === undefined) { this.documents.delete(ns); }
      else { this.accept(next); }
    }
    this.credentialNamespaces = this.eligible() ? rows : [];
    const revisions = this.credentialNamespaces.filter((row: Object): boolean => {
      const ns = getString(row, 'ns') ?? '';
      return ns !== DESKTOP_ACCOUNT_ONBOARDING_NS && ns !== CHAT_NS && ns !== TOOLS_NS;
    }).map((row: Object): string => `${getString(row, 'ns')}:${getNumber(row, 'revision')}`).join('|');
    if (this.credentialSettingsRevisions !== revisions) {
      this.credentialSettingsRevisions = revisions;
      this.invalidateCredentialRead();
    }
    this.publish();
    this.refreshIfNeeded();
  }

  observeAccount(state?: Object, changed: boolean = false): void {
    if (!this.active) { return; }
    const status = getString(state, 'status') ?? '';
    if (status !== this.accountStatus || changed) {
      this.accountEpoch++;
      this.invalidateCredentialRead();
      this.accountStatus = status;
      this.pendingRetry = undefined;
      this.balanceRequested = false;
      this.balance = undefined;
      this.creditFunded = undefined;
      this.balanceEpoch++;
    }
    this.topUpUrl = status === 'credential-stored' ?
      desktopAccountPlatformLink(getString(getRecord(state, 'links'), 'topUpUrl') ?? '') : '';
    this.publish();
    this.refreshIfNeeded();
  }

  credentialsChanged(): void {
    this.invalidateCredentialRead();
    this.refreshIfNeeded();
  }

  private invalidateCredentialRead(): void {
    this.credentialEpoch++;
    this.checkedCredentials = false;
  }

  stop(): void {
    this.active = false;
    this.accountEpoch++;
    this.balanceEpoch++;
    this.invalidateCredentialRead();
  }

  refreshBalance(): void {
    if (!this.active || this.accountStatus !== 'credential-stored' || !this.eligible()) { return; }
    this.balanceRequested = true;
    const epoch = ++this.balanceEpoch;
    this.host.call('account/getBalance', { 'client': desktopAccountMetadata(desktopAccountLocale(this.locale)) })
      .then((result): void => {
        if (epoch !== this.balanceEpoch || !result.ok || getString(result.value, 'status') !== 'ready') { return; }
        const normal = getArray(result.value, 'value');
        const bonus = getArray(result.value, 'bonusWallets');
        if (normal === undefined || bonus === undefined) { return; }
        this.balance = hasPositiveWallet(normal) || hasPositiveWallet(bonus);
        this.publish();
      });
  }

  next(): void {
    const current = this.lastProgress();
    switch (current.step) {
      case 'welcome': this.changeStep('credit'); break;
      case 'credit': this.changeStep('purpose'); break;
      case 'purpose':
        if (current.purpose === 'office') { this.finish('completed'); }
        else if (current.purpose) { this.changeStep('process'); }
        break;
      case 'process': if (current.process) { this.finish('completed'); } break;
    }
  }

  back(): void {
    switch (this.lastProgress().step) {
      case 'credit': this.changeStep('welcome'); break;
      case 'purpose': this.changeStep('credit'); break;
      case 'process': this.changeStep('purpose'); break;
    }
  }

  choosePurpose(purpose: DesktopOnboardingPurpose): void {
    const before = this.lastProgress();
    if (before.step !== 'purpose' || purpose === before.purpose) { return; }
    const next = copyProgress(before);
    next.purpose = purpose;
    this.save({ before: before, next: next, applyPreferences: false });
  }

  chooseProcess(process: DesktopOnboardingProcess): void {
    const before = this.lastProgress();
    if (before.step !== 'process' || process === before.process) { return; }
    const next = copyProgress(before);
    next.process = process;
    this.save({ before: before, next: next, applyPreferences: false });
  }

  skip(): void { this.finish('skipped'); }

  async retry(): Promise<void> {
    if (!this.active || this.saving || this.retrying || this.accountStatus !== 'credential-stored') { return; }
    const failed = this.pendingRetry;
    const epoch = this.accountEpoch;
    this.retrying = true;
    this.pendingRetry = undefined;
    this.publish();
    try { await this.readSettings(); } finally { this.retrying = false; }
    if (this.stillCurrent(epoch) && failed !== undefined && this.sameProgress(failed.before, this.lastProgress())) {
      await this.save(failed);
    }
    else { this.publish(); }
  }

  private changeStep(step: DesktopOnboardingStep): void {
    const before = this.lastProgress();
    const next = copyProgress(before);
    next.step = step;
    this.save({ before: before, next: next, applyPreferences: false });
  }

  private finish(reason: string): void {
    const before = this.lastProgress();
    if (before.step === 'welcome' || before.step === 'done') { return; }
    const office = reason === 'completed' && before.purpose === 'office';
    const development = reason === 'completed' && !office;
    if (development && !before.process) { return; }
    const next: DesktopOnboardingProgress = { step: 'done', purpose: before.purpose, completion: reason,
      process: office ? 'compact' : reason === 'skipped' ? 'standard' : before.process,
      usage: development ? 'detailed' : 'compact', developerTools: development };
    this.save({ before: before, next: next, applyPreferences: true });
  }

  private lastProgress(): DesktopOnboardingProgress {
    return readProgress(this.documents.get(DESKTOP_ACCOUNT_ONBOARDING_NS)?.value);
  }

  private sameProgress(a: DesktopOnboardingProgress, b: DesktopOnboardingProgress): boolean {
    return a.step === b.step && a.purpose === b.purpose && a.process === b.process && a.completion === b.completion &&
      a.usage === b.usage && a.developerTools === b.developerTools;
  }

  private eligible(): boolean {
    const document = this.documents.get(DESKTOP_ACCOUNT_ONBOARDING_NS);
    return this.writable && document !== undefined && (getNumber(document.value, 'version') ?? 1) === 1 &&
      getString(document.value, 'step') !== 'done';
  }

  private accept(document: DesktopPluginDocument): void {
    if (document.revision >= (this.documents.get(document.id)?.revision ?? -1)) {
      this.documents.set(document.id, document);
    }
  }

  private stillCurrent(epoch: number): boolean { return this.active && epoch === this.accountEpoch; }

  private async write(ns: string, fields: DesktopOnboardingField[]): Promise<boolean> {
    const doc = this.documents.get(ns);
    if (doc === undefined || !this.writable) { return false; }
    const ops = fields.map((field: DesktopOnboardingField): DesktopOnboardingOp =>
      ({ op: 'set', path: [field.name], value: field.value }));
    const result = await this.host.call(SETTINGS_MUTATE_ENDPOINT, { 'ns': ns, 'expectedRevision': doc.revision, 'ops': ops });
    const accepted = result.ok ? readDesktopPluginDocument(result.value) : undefined;
    if (accepted?.id !== ns) { return false; }
    this.accept(accepted);
    const current = this.documents.get(ns)?.value;
    return fields.every((field: DesktopOnboardingField): boolean => (getField(current, field.name) ?? null) === field.value);
  }

  private async save(operation: DesktopOnboardingWrite): Promise<void> {
    const requiredStatus = operation.next.completion === 'api-key' ? 'signed-out' : 'credential-stored';
    if (!this.active || this.saving || this.retrying || this.accountStatus !== requiredStatus || !this.eligible() ||
      !this.sameProgress(operation.before, this.lastProgress())) { return; }
    const epoch = this.accountEpoch;
    const next = operation.next;
    this.saving = true;
    this.pendingRetry = undefined;
    this.publish();
    let accepted: boolean = false;
    try {
      if (operation.applyPreferences) {
        const chat = await this.write(CHAT_NS, [{ name: 'transcriptView', value: next.process },
          { name: 'performanceUsage', value: next.usage }]);
        if (!chat || !this.stillCurrent(epoch) || !this.sameProgress(operation.before, this.lastProgress())) { return; }
        const tools = await this.write(TOOLS_NS, [{ name: 'enabled', value: next.developerTools }]);
        if (!tools || !this.stillCurrent(epoch) || !this.sameProgress(operation.before, this.lastProgress())) { return; }
      }
      accepted = await this.write(DESKTOP_ACCOUNT_ONBOARDING_NS, progressFields(next));
      if (accepted && operation.applyPreferences && this.stillCurrent(epoch)) { await this.readSettings(); }
    } catch (_) {
      accepted = false;
    } finally {
      this.saving = false;
      if (!accepted && this.stillCurrent(epoch) && this.eligible()) { this.pendingRetry = operation; }
      this.publish();
      if (!this.stillCurrent(epoch)) { this.refreshIfNeeded(); }
    }
  }

  private refreshIfNeeded(): void {
    if (!this.active || !this.eligible()) { return; }
    if (this.accountStatus === 'credential-stored' && !this.balanceRequested) { this.refreshBalance(); }
    if (this.accountStatus !== 'signed-out' || this.saving || this.checkedCredentials ||
      this.credentialNamespaces.length === 0 || !this.documents.has(CHAT_NS) || !this.documents.has(TOOLS_NS)) { return; }
    this.checkedCredentials = true;
    const epoch = this.credentialEpoch;
    this.checkProviderCredentials(epoch);
  }

  private async checkProviderCredentials(epoch: number): Promise<void> {
    const catalog = await this.host.call(LLM_LIST_CONFIGURABLE_PROVIDERS_ENDPOINT);
    if (epoch !== this.credentialEpoch || !catalog.ok || !this.eligible()) { return; }
    const value = catalog.value;
    if (value === undefined) { return; }
    const wrapped: Record<string, Object> = { 'rows': value };
    const providers = getArray(wrapped, 'rows') ?? getArray(catalog.value, 'providers') ?? [];
    const names = new Set<string>();
    for (const provider of providers) {
      const id = getString(provider, 'provider');
      const ns = getString(provider, 'settingsNs');
      const path = getArray(provider, 'settingsPath');
      if (!id || id === 'deepseek-account' || !ns || path === undefined || !isStringArray(path)) { continue; }
      const document = this.credentialNamespaces.find((row: Object): boolean => getString(row, 'ns') === ns);
      let profile = getRecord(document, 'value');
      for (const segment of toStringArray(path)) { profile = getRecord(profile, segment); }
      const ref = getString(profile, 'apiKeyEnv') ?? '';
      if (ref) { names.add(ref); }
    }
    if (names.size === 0) { return; }
    const result = await this.host.call(CREDENTIALS_DESCRIBE_ENDPOINT, { 'refs': Array.from(names) });
    if (epoch !== this.credentialEpoch || !result.ok || !Array.from(names).some((ref: string): boolean =>
      getBoolean(getRecord(result.value, ref), 'configured') === true)) { return; }
    const before = this.lastProgress();
    const next: DesktopOnboardingProgress = { step: 'done', purpose: before.purpose, process: 'standard',
      completion: 'api-key', usage: 'detailed', developerTools: true };
    await this.save({ before: before, next: next, applyPreferences: true });
  }

  private publish(): void {
    if (!this.active) { return; }
    const progress = this.lastProgress();
    const visible = this.accountStatus === 'credential-stored' && (!this.settingsReady || this.eligible());
    if (visible && progress.step === 'credit' && this.creditFunded === undefined) {
      this.creditFunded = this.balance === true;
    }
    const next: DesktopOnboardingView = { visible: visible, loading: visible && !this.settingsReady,
      busy: this.saving || this.retrying, error: this.settingsFailed || this.pendingRetry !== undefined, step: progress.step,
      purpose: progress.purpose, process: progress.process, funded: this.creditFunded === true,
      zeroBalance: this.balance === false, topUpUrl: this.topUpUrl };
    const previous = this.lastView;
    if (!next.visible && !previous.visible) { return; }
    if (next.visible === previous.visible && next.loading === previous.loading && next.busy === previous.busy &&
      next.error === previous.error && next.step === previous.step && next.purpose === previous.purpose &&
      next.process === previous.process && next.funded === previous.funded && next.zeroBalance === previous.zeroBalance &&
      next.topUpUrl === previous.topUpUrl) { return; }
    this.lastView = next;
    this.onChange(next);
  }
}
