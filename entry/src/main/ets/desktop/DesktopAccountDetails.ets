import { getRecord, getString } from 'connection';
import { desktopAccountLocale, desktopAccountMetadata } from './DesktopAccountClient';
import { desktopAccountSettingsBalances, desktopAccountSettingsProfile,
  emptyDesktopAccountSettingsIdentity } from './DesktopAccountSettingsModel';
import type { DesktopAccountSettingsBalances, DesktopAccountSettingsIdentity,
  DesktopAccountSettingsProfile } from './DesktopAccountSettingsModel';
import type { DesktopHostActions } from './DesktopHostActions';

export interface DesktopAccountDetailsSnapshot {
  identity: DesktopAccountSettingsIdentity;
  profile?: DesktopAccountSettingsProfile;
  profileId: string;
  profileLoaded: boolean;
  profileRevision: number;
  balances?: DesktopAccountSettingsBalances;
  balanceLoaded: boolean;
}

export interface DesktopAccountDetailsAccess {
  observe: (listener: (snapshot: DesktopAccountDetailsSnapshot) => void) => () => void;
  refreshAfterCurrent: () => void;
}

export class DesktopAccountDetails {
  private readonly host: DesktopHostActions;
  private readonly observers = new Set<(snapshot: DesktopAccountDetailsSnapshot) => void>();
  private state: DesktopAccountDetailsSnapshot = { identity: emptyDesktopAccountSettingsIdentity(),
    profileId: '', profileLoaded: false, profileRevision: 0, balanceLoaded: false };
  private locale: string = desktopAccountLocale();
  private active: boolean = true;
  private generation: number = 0;
  private request?: Promise<void>;

  constructor(host: DesktopHostActions) { this.host = host; }

  observe(listener: (snapshot: DesktopAccountDetailsSnapshot) => void): () => void {
    this.observers.add(listener);
    listener(this.state);
    return (): void => { this.observers.delete(listener); };
  }

  private publish(): void {
    this.observers.forEach((listener: (snapshot: DesktopAccountDetailsSnapshot) => void): void => {
      listener(this.state);
    });
  }

  setIdentity(identity: DesktopAccountSettingsIdentity): void {
    if (!this.active) { return; }
    const previous = this.state.identity;
    if (identity.signedIn !== previous.signedIn || identity.revision !== previous.revision) {
      this.generation++;
      this.request = undefined;
      this.state = { identity: identity, profileId: '', profileLoaded: false,
        profileRevision: this.state.profileRevision + 1, balanceLoaded: false };
      this.publish();
      this.refresh();
    } else if (identity.ready !== previous.ready || identity.usageUrl !== previous.usageUrl ||
        identity.topUpUrl !== previous.topUpUrl) {
      this.state.identity = identity;
      this.publish();
    }
  }

  setLocale(locale: string): void { this.locale = locale; }

  refresh(): Promise<void> {
    if (!this.active || !this.state.identity.signedIn) { return Promise.resolve(); }
    if (this.request !== undefined) { return this.request; }
    const generation = this.generation;
    const params: Record<string, Object> = { 'client': desktopAccountMetadata(this.locale) };
    const request = Promise.all([this.readProfile(generation, params), this.readBalance(generation, params)])
      .then((): void => {});
    this.request = request;
    request.finally((): void => { if (this.request === request) { this.request = undefined; } });
    return request;
  }

  async refreshAfterCurrent(): Promise<void> {
    const generation = this.generation;
    await this.request;
    if (generation === this.generation) { await this.refresh(); }
  }

  private async readProfile(generation: number, params: Record<string, Object>): Promise<void> {
    let profile: DesktopAccountSettingsProfile | undefined;
    let id = '';
    try {
      const result = await this.host.call('account/getProfile', params);
      if (result.ok) {
        profile = desktopAccountSettingsProfile(result.value);
        if (profile !== undefined) { id = getString(getRecord(result.value, 'value'), 'id') ?? ''; }
      }
    } catch (_) {}
    if (!this.active || generation !== this.generation) { return; }
    this.state.profile = profile;
    this.state.profileId = id;
    this.state.profileLoaded = true;
    this.state.profileRevision++;
    this.publish();
  }

  private async readBalance(generation: number, params: Record<string, Object>): Promise<void> {
    let balances: DesktopAccountSettingsBalances | undefined;
    try {
      const result = await this.host.call('account/getBalance', params);
      if (result.ok) { balances = desktopAccountSettingsBalances(result.value); }
    } catch (_) {}
    if (!this.active || generation !== this.generation) { return; }
    this.state.balances = balances;
    this.state.balanceLoaded = true;
    this.publish();
  }

  stop(): void {
    this.active = false;
    this.generation++;
    this.request = undefined;
    this.observers.clear();
  }
}
