import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';
import type { RpcResult } from 'connection';
import { SETTINGS_DESCRIBE_ENDPOINT } from 'dshcompat';
import { dialogMaterial } from 'platform';
import { DesktopHostActions, desktopHostItems, desktopHostProblem, desktopLocalizedText } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopPluginSettings } from './DesktopPluginSettings';
import { DESKTOP_FORGE_BUNDLE, desktopPluginConfigurationScopes, readDesktopPluginConfiguration, SHELL_PLUGIN_SETTINGS,
  SUBAGENT_SETTINGS, WEB_PLUGIN_SETTINGS, WORKTREE_SETTINGS } from './DesktopPluginSettingsModel';
import { DesktopPluginBundleComponents, desktopPluginComponents } from './DesktopPluginBundleComponents';
import type { DesktopPluginComponent, DesktopPluginComponentView } from './DesktopPluginBundleComponents';
import { DESKTOP_VOICE_BUNDLE, DesktopVoiceSettings } from './DesktopVoiceSettings';
import { desktopVoiceNeedsInstallation, desktopVoiceSelectedProvider, readDesktopVoiceCatalog } from './DesktopVoiceSettingsModel';
import { showDesktopVoiceSetup } from './DesktopVoiceSettingsPrompt';
import { DesktopPluginInstall } from './DesktopPluginInstall';
import type { DesktopPluginCatalogTarget } from './DesktopPluginInstall';
import { DesktopPluginInstallDialog } from './DesktopPluginInstallDialog';
import { DesktopPluginMaintenance } from './DesktopPluginMaintenance';
import { DesktopPluginMaintenanceDialog } from './DesktopPluginMaintenanceDialog';
import { DesktopPluginMarketDetail } from './DesktopPluginMarketDetail';
import { DesktopTimelineSettings } from './DesktopTimelineSettings';
import { DESKTOP_TIMELINE_BUNDLE, DESKTOP_TIMELINE_NS } from './DesktopTimelineSettingsModel';
import { DesktopConnectorAccounts } from './DesktopConnectorAccounts';
import type { DesktopConnectorAccount, DesktopConnectorAction, DesktopConnectorPrompt } from './DesktopConnectorAccounts';
import { DesktopConnectorAccountView, DesktopConnectorBadge, DesktopConnectorDialog } from './DesktopConnectorAccountView';
import { MarkdownRenderer } from '../view/MarkdownRenderer';

const MARKET_BUNDLE: string = '@deepseek-ai/dsh-experimental-plugin-market-bundle';

interface DesktopPluginRow {
  id: string;
  title: string;
  description: string;
  enabled: boolean;
  toggle: boolean;
  removable: boolean;
  installed: boolean;
  availability: string;
  unsupportedPlatform: boolean;
  version: string;
  update: string;
  installSpec: string;
  installVersion: string;
  phase: string;
  diagnostic: string;
  components: DesktopPluginComponent[];
}

interface DesktopPluginVersion {
  version: string;
  prerelease: boolean;
  deprecated: string | undefined;
  installable: boolean;
}

interface DesktopMarketSource {
  url: string;
  title: string;
}

function pluginRows(result: RpcResult, bundle: boolean): DesktopPluginRow[] {
  const rows: DesktopPluginRow[] = [];
  for (const value of desktopHostItems(result)) {
      const id = getString(value, bundle ? 'name' : 'entryId') ?? '';
      const enabled = getBoolean(value, 'enabled') === true;
      const optional = getBoolean(value, 'optional') === true;
      const installed = getBoolean(value, 'installed') === true;
      if (id.length === 0 || (bundle && !enabled && !optional && !installed &&
        getBoolean(value, 'listedByDefault') !== true)) {
        continue;
      }
      const target = getRecord(value, 'installTarget');
      const availability = bundle ? getString(value, 'availability') ?? '' : '';
      const installSpec = getString(target, 'spec') ?? '';
      const installVersion = getString(target, 'version') ?? '';
      const error = getRecord(value, 'error');
      const unsupportedPlatform = bundle && getString(error, 'code') === 'unsupported-platform';
      const canEnableBundle = !unsupportedPlatform && (availability === 'missing' ?
        !!installSpec && !!installVersion : error === undefined);
      const meta = getRecord(value, 'meta');
      rows.push({
        id: id,
        title: bundle ? desktopLocalizedText(meta, 'title') || id : getString(value, 'moduleName') ?? id,
        description: bundle ? desktopLocalizedText(meta, 'description') || getString(value, 'description') || '' :
          getString(value, 'fiberPhase') ?? getString(value, 'phase') ?? '',
        version: getString(value, 'version') ?? '',
        installed: installed,
        availability: availability,
        unsupportedPlatform: unsupportedPlatform,
        enabled: enabled,
        toggle: !getString(value, 'readOnlyReason') && (bundle ?
          enabled || ((optional || installed) && canEnableBundle) : !!getString(value, 'patchId')),
        removable: bundle && getBoolean(value, 'removable') === true && !getString(value, 'readOnlyReason'),
        update: bundle ? getString(value, 'update') ?? '' : '',
        installSpec: installSpec,
        installVersion: installVersion,
        phase: getString(value, 'fiberPhase') ?? '',
        diagnostic: getString(value, 'diagnostic') ?? '',
        components: bundle && availability !== 'missing' ? desktopPluginComponents(value) : []
      });
  }
  return rows;
}

@Component
export struct DesktopPluginsPane {
  host?: DesktopHostActions;
  @ObjectLink installer: DesktopPluginInstall;
  @ObjectLink maintenance: DesktopPluginMaintenance;
  @Prop localePreference: string = 'system';
  @ObjectLink connectorAccounts: DesktopConnectorAccounts;
  @Prop @Watch('requestedBundleChanged') requestedBundle: string = '';
  @Prop requestedTitle: string = '';
  @Prop requestedDescription: string = '';
  onWeb: (name: string) => void = (_name: string): void => {};
  @State private detailName: string = '';
  @State private detailText: string = '';
  @State private detailError: string = '';
  @State private detailLoading: boolean = false;
  @State private tab: string = 'bundles';
  @State private settingsVisited: boolean = false;
  @State private basicScopes: string[] = [];
  @State private optionalNamespaces: string[] = [];
  @State private componentDetail: boolean = false;
  @State private worktreeVisited: boolean = false;
  @State private settingsDetail: string = '';
  @State private bundles: DesktopPluginRow[] = [];
  @State private plugins: DesktopPluginRow[] = [];
  @State private sources: DesktopMarketSource[] = [];
  @State private source: string = '';
  @State private sourceInput: string = '';
  @State private editSources: boolean = false;
  @State private marketError: string = '';
  @State private query: string = '';
  @State private nextOffset: number = -1;
  @State private fetchedAt: number = 0;
  @State private market: Object[] = [];
  @State private marketDetail?: Object = undefined;
  @State private marketDetailSource: string = '';
  @State private status: string = '';
  @State private catalogError: string = '';
  @State private catalogBusy: boolean = false;
  @State private paneWidth: number = 500;
  @State private busy: boolean = false;
  @State private versionOwner: string = '';
  @State private versions: DesktopPluginVersion[] = [];
  @State private recommendedVersion: string = '';
  @State private versionStatus: string = '';
  @State private versionInstalled: string = '';
  private versionRegistry?: string | null;
  private maintenanceDialog: number = -1;
  private maintenanceOpening: boolean = false;
  private active: boolean = false;
  private detailRead: number = 0;
  private refreshAgain: boolean = false;
  private basicRead: number = 0;
  private stopCatalog?: () => void;
  private stopAccounts?: () => void;
  private installDialog: number = -1;
  private installOpening: boolean = false;
  private connectorDialog: number = -1;
  private connectorOpening: boolean = false;
  private activationBundle: string = '';
  private activationShowing: string = '';
  private voiceSetupGeneration: number = 0;
  private stopVoiceSetupFollow?: () => void;
  private voiceSetupTimer: number = -1;

  aboutToAppear(): void {
    this.active = true;
    this.stopCatalog = this.installer.watchCatalog((): void => { this.refresh(); });
    this.stopAccounts = this.connectorAccounts.watch((): void => { this.updateActivation(); });
    this.refresh();
    this.requestedBundleChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.stopCatalog?.();
    this.stopCatalog = undefined;
    this.stopAccounts?.();
    this.stopAccounts = undefined;
    this.closeInstall();
    this.closeConnectorDialog();
    this.closeMaintenance();
    this.stopVoiceSetup();
  }

  private requestedBundleChanged(): void {
    if (this.requestedBundle) { this.openBundle(this.requestedBundle); }
    else { this.closeBundle(); }
  }

  private closeBundle(): void {
    this.detailRead++;
    this.detailName = '';
    this.componentDetail = false;
    this.worktreeVisited = false;
    this.resetVersions();
  }

  private async openBundle(name: string): Promise<void> {
    this.tab = 'bundles';
    this.settingsDetail = '';
    this.marketDetail = undefined;
    this.resetVersions();
    this.detailName = name;
    this.componentDetail = false;
    this.worktreeVisited = false;
    this.detailText = '';
    this.detailError = '';
    this.detailLoading = true;
    const version = ++this.detailRead;
    const result = await this.host?.call('pluginManager/readBundleDetail', { 'name': name, 'language': 'zh-CN' });
    if (!this.active || version !== this.detailRead) { return; }
    this.detailLoading = false;
    if (!result?.ok) { this.detailError = result?.error?.message || '无法读取插件详情'; }
    else if (getString(result.value, 'status') === 'found') { this.detailText = getString(result.value, 'markdown') ?? ''; }
  }

  private async refresh(): Promise<void> {
    const host = this.host;
    if (host === undefined || !this.active) { return; }
    if (this.catalogBusy) { this.refreshAgain = true; return; }
    this.catalogBusy = true;
    do {
      this.refreshAgain = false;
      await this.loadCatalog(host);
    } while (this.active && this.refreshAgain);
    this.catalogBusy = false;
  }

  private async loadBasicScopes(host: DesktopHostActions): Promise<void> {
    const read = ++this.basicRead;
    const result = await host.call(SETTINGS_DESCRIBE_ENDPOINT);
    if (this.active && read === this.basicRead && result.ok) {
      this.basicScopes = desktopPluginConfigurationScopes(readDesktopPluginConfiguration(result.value).documents);
      this.optionalNamespaces = (getArray(result.value, 'namespaces') ?? [])
        .map((entry: Object): string => getString(entry, 'ns') ?? '')
        .filter((id: string): boolean => id === WORKTREE_SETTINGS || id === DESKTOP_TIMELINE_NS);
    }
  }

  private async loadCatalog(host: DesktopHostActions): Promise<void> {
    this.loadBasicScopes(host);
    const results = await Promise.all([
      host.call('pluginManager/listBundles'),
      host.call('pluginManager/listPlugins'),
      host.call('pluginMarket/listIndexes')
    ]);
    if (!this.active) {
      return;
    }
    this.bundles = pluginRows(results[0], true);
    const checked = this.bundles.find((row: DesktopPluginRow): boolean => row.id === this.versionOwner);
    if (this.versionInstalled && results[0].ok && checked?.version !== this.versionInstalled) { this.resetVersions(); }
    this.plugins = pluginRows(results[1], false);
    this.marketError = desktopHostProblem(results[2]);
    if (results[2].ok) {
      const sources: DesktopMarketSource[] = [];
      for (const item of desktopHostItems(results[2])) {
        const url = getString(item, 'url') ?? '';
        if (url.length > 0) {
          sources.push({ url: url, title: desktopLocalizedText(item, 'title') || url });
        }
      }
      this.sources = sources;
      if (!sources.some((row: DesktopMarketSource): boolean => row.url === this.source)) {
        this.source = sources[0]?.url ?? '';
        this.market = [];
        this.nextOffset = -1;
      }
    }
    this.catalogError = desktopHostProblem(results[0]) || desktopHostProblem(results[1]);
    this.updateActivation();
  }

  private async saveSources(urls: string[]): Promise<void> {
    if (this.host === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.host.call('pluginMarket/setIndexes', { 'urls': urls });
    if (!this.active) {
      return;
    }
    this.busy = false;
    const error = desktopHostProblem(result);
    if (error.length > 0) {
      this.status = error;
      return;
    }
    this.sourceInput = '';
    await this.refresh();
  }

  private addSource(): void {
    const url = this.sourceInput.trim();
    if (!(/^(?:https?:\/\/|git\+)/i.test(url)) || this.sources.some((row: DesktopMarketSource): boolean => row.url === url)) {
      this.status = '请填写尚未添加的 HTTP、HTTPS 或 Git 索引地址';
      return;
    }
    this.saveSources([...this.sources.map((row: DesktopMarketSource): string => row.url), url]);
  }

  private async searchMarket(append: boolean): Promise<void> {
    if (this.host === undefined || this.busy || this.source.length === 0 || (append && this.nextOffset < 0)) {
      return;
    }
    this.busy = true;
    const sort: Record<string, Object> = { 'kind': 'relevance' };
    const query: Record<string, Object> = {
      'text': this.query.trim(), 'offset': append ? this.nextOffset : 0, 'limit': 30, 'sort': sort
    };
    if (append) {
      query['fetchedAt'] = this.fetchedAt;
    }
    const result = await this.host.call('pluginMarket/search', { 'url': this.source, 'query': query });
    if (!this.active) {
      return;
    }
    this.busy = false;
    this.status = desktopHostProblem(result);
    if (result.ok) {
      const entries = getArray(result.value, 'entries') ?? [];
      const fetchedAt = getNumber(result.value, 'fetchedAt') ?? 0;
      if (append && fetchedAt !== this.fetchedAt) {
        this.status = '市场目录已变化，请重新搜索';
        this.nextOffset = -1;
        return;
      }
      this.market = append ? [...this.market, ...entries] : entries;
      this.fetchedAt = fetchedAt;
      this.nextOffset = getNumber(result.value, 'nextOffset') ?? -1;
    }
  }

  private async mutate(endpoint: string, payload: Record<string, Object>, activate: string = ''): Promise<void> {
    if (this.host === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.status = '正在等待宿主处理…';
    const result = await this.host.call(endpoint, payload, 180000);
    if (!this.active) {
      return;
    }
    this.busy = false;
    const value = getRecord(result.value, 'result') ?? result.value;
    const outcome: RpcResult = { ok: result.ok, value: value, error: result.error };
    const problem = desktopHostProblem(outcome);
    await this.refresh();
    if (!this.active) { return; }
    this.status = problem || (getString(value, 'application') === 'restart-required' ?
      '已保存，重启核心后生效' : '操作已完成');
    if (activate && !problem && getString(value, 'application') !== 'restart-required') {
      this.activationBundle = activate;
      this.updateActivation();
    }
  }

  @Builder
  private InstallDialog() {
    DesktopPluginInstallDialog({ installer: this.installer, onClose: (): void => { this.closeInstall(); },
      onEnable: (): void => { this.enableInstalled(); } })
  }

  private async openInstall(spec: string = '', registry: string = '', target?: DesktopPluginCatalogTarget): Promise<void> {
    if (!this.active || this.installOpening || this.installDialog >= 0 || this.maintenance.phase === 'running') { return; }
    this.installOpening = true;
    if (target === undefined) { this.installer.offer(spec, registry); }
    else { this.installer.installCatalogTarget(target); }
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({ builder: (): void => { this.InstallDialog(); },
        alignment: DialogAlignment.Center, width: Math.max(240, Math.min(496, this.paneWidth - 28)),
        isModal: true, autoCancel: true, cornerRadius: 22, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          this.installDialog = -1;
          this.installer.closeInspection();
          this.updateActivation();
        }
      });
      if (this.active) { this.installDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.active) { prompt.showToast({ message: $r('app.string.desktop_plugin_install_open_failed') }); }
    } finally {
      this.installOpening = false;
      this.updateActivation();
    }
  }

  private closeInstall(): void {
    if (this.installDialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(this.installDialog); }
  }

  private async enableInstalled(): Promise<void> {
    const name = await this.installer.enable();
    if (this.active && name) {
      this.activationBundle = name;
      this.updateActivation();
    }
  }

  private stopVoiceSetup(): void {
    ++this.voiceSetupGeneration;
    this.stopVoiceSetupFollow?.();
    this.stopVoiceSetupFollow = undefined;
    clearTimeout(this.voiceSetupTimer);
    this.voiceSetupTimer = -1;
  }

  private openVoiceActivation(): void {
    this.stopVoiceSetup();
    const generation = this.voiceSetupGeneration;
    this.voiceSetupTimer = setTimeout((): void => { this.stopVoiceSetup(); }, 30000);
    const stop = this.host?.watch('speech/follow', {}, {
      onItem: (frame: Object): void => {
        if (!this.active || generation !== this.voiceSetupGeneration) { return; }
        const provider = desktopVoiceSelectedProvider(readDesktopVoiceCatalog(frame));
        if (provider === undefined || provider.preparation.phase === 'checking') { return; }
        this.stopVoiceSetup();
        if (desktopVoiceNeedsInstallation(provider)) {
          showDesktopVoiceSetup(this.getUIContext(), true, (): void => { this.openBundle(DESKTOP_VOICE_BUNDLE); });
        }
      },
      onError: (_code: string, _message: string): void => {
        if (generation === this.voiceSetupGeneration) { this.stopVoiceSetup(); }
      },
      onEnd: (): void => {
        if (generation === this.voiceSetupGeneration) { this.stopVoiceSetup(); }
      }
    });
    if (generation === this.voiceSetupGeneration) { this.stopVoiceSetupFollow = stop; }
    else { stop?.(); }
  }

  private updateActivation(): void {
    if (!this.active) { return; }
    const catalog = this.installer.takeCatalogActivation();
    if (catalog) { this.activationBundle = catalog; }
    if (this.installOpening) { return; }
    if (this.activationBundle === DESKTOP_VOICE_BUNDLE) {
      if (!this.bundles.some((row: DesktopPluginRow): boolean => row.id === DESKTOP_VOICE_BUNDLE && row.enabled)) { return; }
      if (this.installDialog >= 0) { this.closeInstall(); return; }
      this.activationBundle = '';
      this.openVoiceActivation();
      return;
    }
    if (!this.connectorAccounts.linked) { return; }
    if (this.activationShowing && this.connectorAccounts.byBundle(this.activationShowing)?.phase !== 'disconnected') {
      this.closeConnectorDialog();
    }
    if (!this.activationBundle || this.connectorOpening || this.connectorDialog >= 0 ||
      !this.bundles.some((row: DesktopPluginRow): boolean => row.id === this.activationBundle && row.enabled)) { return; }
    const account = this.connectorAccounts.byBundle(this.activationBundle);
    if (account === undefined) { return; }
    if (account.phase === 'connected' || account.phase === 'unavailable') { this.activationBundle = ''; return; }
    const prompt = account.activation;
    if (account.phase !== 'disconnected' || prompt === undefined) { return; }
    if (this.installDialog >= 0) { this.closeInstall(); return; }
    this.activationBundle = '';
    this.showConnectorDialog(account, prompt, true, (): void => {
      const latest = this.connectorAccounts.byBundle(account.packageName);
      if (latest?.key !== account.key || latest.phase !== 'disconnected') { return; }
      this.openBundle(account.packageName);
      if (latest.connect !== undefined) { this.connectorAccounts.run(latest, latest.connect, true); }
    });
  }

  private accountAction(account: DesktopConnectorAccount, action: DesktopConnectorAction): void {
    if (action.confirm === undefined) {
      this.connectorAccounts.run(account, action);
    } else {
      this.showConnectorDialog(account, action.confirm, false, (): void => { this.connectorAccounts.run(account, action); });
    }
  }

  @Builder
  private ConnectorDialog(accountKey: string, data: DesktopConnectorPrompt, activation: boolean, action: () => void) {
    DesktopConnectorDialog({ accounts: this.connectorAccounts, prompt: data, accountKey: accountKey, activation: activation,
      onDismiss: (): void => { this.closeConnectorDialog(); },
      onConfirm: (): void => { this.closeConnectorDialog(); if (this.active) { action(); } } })
  }

  private async showConnectorDialog(account: DesktopConnectorAccount, data: DesktopConnectorPrompt, activation: boolean,
    action: () => void): Promise<void> {
    if (!this.active || this.connectorOpening || this.connectorDialog >= 0) { return; }
    this.connectorOpening = true;
    this.activationShowing = activation ? account.packageName : '';
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.ConnectorDialog(account.key, data, activation, action); },
        alignment: DialogAlignment.Center, width: Math.max(240, Math.min(442, this.paneWidth - 28)),
        isModal: true, autoCancel: true, cornerRadius: 22, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          this.connectorDialog = -1;
          this.activationShowing = '';
          this.updateActivation();
        }
      });
      if (this.active) { this.connectorDialog = id; this.updateActivation(); }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      this.activationShowing = '';
      if (this.active) { prompt.showToast({ message: $r('app.string.desktop_connector_failed') }); }
    } finally {
      this.connectorOpening = false;
    }
  }

  private closeConnectorDialog(): void {
    if (this.connectorDialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(this.connectorDialog); }
  }

  private resetVersions(): void {
    this.versionOwner = '';
    this.versionInstalled = '';
    this.versions = [];
    this.recommendedVersion = '';
    this.versionStatus = '';
    this.versionRegistry = undefined;
  }

  private async listVersions(row: DesktopPluginRow): Promise<void> {
    if (this.host === undefined || this.busy || this.maintenance.phase === 'running') { return; }
    this.busy = true;
    this.resetVersions();
    this.versionOwner = row.id;
    const result = await this.host.call('pluginManager/listVersions', { 'name': row.id });
    if (!this.active) { return; }
    this.busy = false;
    if (this.versionOwner !== row.id || this.detailName !== row.id) { return; }
    if (!result.ok || getString(result.value, 'status') !== 'listed') {
      this.versionStatus = desktopHostProblem(result) || getString(result.value, 'reason') || '无法检查更新';
      return;
    }
    this.versionInstalled = getString(result.value, 'installed') ?? '';
    this.versionRegistry = getField(result.value, 'registry') === null ? null : getString(result.value, 'registry');
    const versions: DesktopPluginVersion[] = [];
    for (const value of getArray(result.value, 'versions') ?? []) {
      const version = getString(value, 'version');
      if (!version || version === this.versionInstalled) { continue; }
      const info: DesktopPluginVersion = { version: version, prerelease: getBoolean(value, 'prerelease') === true,
        deprecated: getString(value, 'deprecated'), installable: getBoolean(value, 'bundle') === true &&
          getRecord(value, 'incompatible') === undefined };
      if (!this.recommendedVersion && info.installable && !info.prerelease && info.deprecated === undefined) {
        this.recommendedVersion = info.version;
      }
      versions.push(info);
    }
    this.versions = versions;
    if (!versions.some((info: DesktopPluginVersion): boolean => info.installable)) {
      this.versionStatus = '没有可用更新';
    }
  }

  private offerRegistryUpdate(row: DesktopPluginRow, version: string): void {
    if (this.maintenanceOpening || this.maintenanceDialog >= 0 || this.installer.busy() || this.busy ||
      this.versionOwner !== row.id || this.versionInstalled !== row.version ||
      !this.versions.some((info: DesktopPluginVersion): boolean => info.version === version && info.installable)) { return; }
    if (this.maintenance.offerUpdate(row.id, row.title, this.versionInstalled, version, this.versionRegistry)) {
      this.openMaintenance();
    }
  }

  private offerRemove(row: DesktopPluginRow): void {
    if (!row.removable || this.maintenanceOpening || this.maintenanceDialog >= 0 || this.installer.busy() || this.busy) { return; }
    if (this.maintenance.offerRemove(row.id, row.title)) { this.openMaintenance(); }
  }

  @Builder
  private MaintenanceDialog() {
    DesktopPluginMaintenanceDialog({ model: this.maintenance, onClose: (): void => { this.closeMaintenance(); },
      onConfirm: (): void => { this.confirmMaintenance(); } })
  }

  private async openMaintenance(): Promise<void> {
    this.maintenanceOpening = true;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({ builder: (): void => { this.MaintenanceDialog(); },
        alignment: DialogAlignment.Center, width: Math.max(240, Math.min(496, this.paneWidth - 28)),
        isModal: true, autoCancel: false, cornerRadius: 22, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onWillDismiss: (action): void => { if (this.maintenance.phase !== 'running') { action.dismiss(); } },
        onDidDisappear: (): void => { this.maintenanceDialog = -1; this.maintenance.close(); }
      });
      if (this.active) { this.maintenanceDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      this.maintenance.close();
      if (this.active) { prompt.showToast({ message: $r('app.string.desktop_plugin_install_open_failed') }); }
    } finally {
      this.maintenanceOpening = false;
    }
  }

  private closeMaintenance(): void {
    if (this.maintenanceDialog >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.maintenanceDialog);
    }
  }

  private async confirmMaintenance(): Promise<void> {
    if (!await this.maintenance.confirm() || !this.active) { return; }
    const name = this.maintenance.name;
    const removed = this.maintenance.action === 'remove' && this.maintenance.application === 'applied';
    if (this.versionOwner === name && this.maintenance.action === 'update' &&
      (this.maintenance.application === 'applied' || this.maintenance.application === 'restart-required')) {
      this.resetVersions();
    }
    await this.refresh();
    if (!this.active) { return; }
    if (removed && this.detailName === name && !this.catalogError &&
      !this.bundles.some((row: DesktopPluginRow): boolean => row.id === name && row.installed)) {
      this.closeBundle();
    }
    if (this.tab === 'market') { this.searchMarket(false); }
  }

  private confirm(title: string, message: string, action: () => void): void {
    this.getUIContext().getPromptAction().showDialog({
      title: title, message: message,
      buttons: [{ 'text': '取消', color: '#777777' }, { 'text': title, color: '#3165D7' }]
    }).then((result): void => {
      if (result.index === 1 && this.active) {
        action();
      }
    }).catch((): void => {});
  }

  private toggleBundle(name: string, enabled: boolean): void {
    const row = this.bundles.find((item: DesktopPluginRow): boolean => item.id === name);
    if (!this.active || this.busy || row?.toggle !== true || row.enabled === enabled) { return; }
    if (enabled && row.availability === 'missing') {
      this.openInstall('', '', { name: row.id, version: row.installVersion, spec: row.installSpec,
        description: row.description });
      return;
    }
    if (!enabled && this.activationBundle === row.id) { this.activationBundle = ''; }
    if (!enabled && row.id === DESKTOP_VOICE_BUNDLE) { this.stopVoiceSetup(); }
    this.mutate('pluginManager/setBundleEnabled', { 'name': row.id, 'enabled': enabled }, enabled ? row.id : '');
  }

  private rowActions(row: DesktopPluginRow): MenuElement[] {
    const result: MenuElement[] = [];
    if (row.toggle) {
      result.push({ value: row.enabled ? '停用' : '启用', action: (): void => {
        if (this.tab === 'bundles') {
          this.toggleBundle(row.id, !row.enabled);
        } else {
          this.mutate('pluginManager/setPluginEnabled', { 'id': row.id, 'enabled': !row.enabled });
        }
      } });
    }
    if (row.installSpec.length > 0 && !row.unsupportedPlatform) {
      result.push({ value: '安装', action: (): void => {
        const current = this.bundles.find((item: DesktopPluginRow): boolean => item.id === row.id);
        if (current?.installSpec === row.installSpec && !current.unsupportedPlatform) {
          this.openInstall(row.installSpec);
        }
      } });
    }
    return result;
  }

  private marketActions(entry: Object): MenuElement[] {
    if (getString(getRecord(entry, 'installation'), 'status') !== 'not-installed') { return []; }
    return (getArray(entry, 'versions') ?? []).flatMap((row: Object): MenuElement[] => {
      const install = getRecord(row, 'install');
      const compatibility = getRecord(row, 'compatibility');
      const spec = getString(install, 'spec') ?? '';
      const version = getString(row, 'version') ?? '';
      const registry = getString(install, 'registry') ?? '';
      if (spec.length === 0 || version.length === 0 ||
        (getBoolean(compatibility, 'compatible') !== true && getBoolean(compatibility, 'exempted') !== true)) {
        return [];
      }
      return [{ value: version, action: (): void => { this.openInstall(spec, registry); } }];
    });
  }

  @Builder
  private PluginRow(row: DesktopPluginRow, navigable: boolean = false) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(row.title).fontSize(15).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text([row.enabled ? '已启用' : '未启用', row.version || (navigable ? '' : row.description)]
          .filter((item: string): boolean => item.length > 0).join(' · '))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
        if (navigable && row.description) {
          Text(row.description).fontSize(13).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('sys.color.font_secondary'))
        }
        if (row.unsupportedPlatform) {
          Text($r('app.string.desktop_plugin_unsupported_platform')).key('desktopPluginUnavailable-' + row.id)
            .fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (navigable) {
        Button($r('app.string.desktop_plugin_maintenance_view'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPluginBundle-' + row.id).onClick((): void => { this.openBundle(row.id); })
      }
      if (this.rowActions(row).length > 0) {
        Button('更多', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPluginManage-' + row.id).accessibilityText('管理 ' + row.title).enabled(!this.busy)
          .bindMenu(this.rowActions(row), desktopMenuOptions(Placement.BottomRight))
      }
    }
    .width('100%').constraintSize({ minHeight: 60 }).padding(10)
    .borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private BundleActions(row: DesktopPluginRow) {
    Row({ space: 8 }) {
      if (row.update === 'registry' && row.removable) {
        Button($r('app.string.desktop_plugin_maintenance_check'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPluginCheckVersions-' + row.id).enabled(!this.busy && this.maintenance.phase !== 'running')
          .onClick((): void => { this.listVersions(row); })
      }
      if (row.installed || row.removable) {
        Button($r('app.string.desktop_plugin_maintenance_remove_action'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPluginRemove-' + row.id)
          .enabled(row.removable && !this.busy && !this.installer.busy() && this.maintenance.phase !== 'running')
          .fontColor($r('app.color.workspace_status_error')).onClick((): void => { this.offerRemove(row); })
      }
    }.width('100%')
    if (this.versionOwner === row.id) {
      if (this.versionStatus) {
        Text(this.versionStatus).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      ForEach(this.versions, (version: DesktopPluginVersion): void => {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(version.version).key('desktopPluginListedVersion-' + version.version).fontSize(14)
            if (!version.installable) {
              Text($r('app.string.desktop_plugin_maintenance_incompatible')).fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            } else if (version.deprecated !== undefined) {
              Text(version.deprecated || $r('app.string.desktop_plugin_maintenance_deprecated')).fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            } else if (version.prerelease) {
              Text($r('app.string.desktop_plugin_maintenance_prerelease')).fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (version.installable) {
            Button(version.version === this.recommendedVersion ? $r('app.string.desktop_plugin_maintenance_update_to',
              version.version) : $r('app.string.desktop_plugin_maintenance_update_action'),
              { buttonStyle: version.version === this.recommendedVersion ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.TEXTUAL })
              .key('desktopPluginUpdateVersion-' + version.version)
              .enabled(!this.busy && !this.installer.busy() && this.maintenance.phase !== 'running')
              .onClick((): void => { this.offerRegistryUpdate(row, version.version); })
          }
        }.width('100%').padding(8)
      }, (version: DesktopPluginVersion): string => version.version)
    }
  }

  private basicTitle(scope: string): Resource {
    switch (scope) {
      case SUBAGENT_SETTINGS: return $r('app.string.desktop_plugin_basic_subagent');
      case WEB_PLUGIN_SETTINGS: return $r('app.string.desktop_plugin_basic_web');
      case SHELL_PLUGIN_SETTINGS: return $r('app.string.desktop_plugin_basic_shell');
      default: return $r('app.string.desktop_plugin_basic_loop');
    }
  }

  private basicSummary(scope: string): Resource {
    switch (scope) {
      case SUBAGENT_SETTINGS: return $r('app.string.desktop_plugin_basic_subagent_summary');
      case WEB_PLUGIN_SETTINGS: return $r('app.string.desktop_plugin_basic_web_summary');
      case SHELL_PLUGIN_SETTINGS: return $r('app.string.desktop_plugin_basic_shell_summary');
      default: return $r('app.string.desktop_plugin_basic_loop_summary');
    }
  }

  private basicArtwork(scope: string): Resource {
    switch (scope) {
      case SUBAGENT_SETTINGS: return $r('app.media.dsh_plugin_artwork_subagent');
      case WEB_PLUGIN_SETTINGS: return $r('app.media.dsh_plugin_artwork_web');
      case SHELL_PLUGIN_SETTINGS: return $r('app.media.dsh_plugin_artwork_shell');
      default: return $r('app.media.dsh_plugin_artwork_loop');
    }
  }

  @Builder
  private BasicSettingsCards() {
    Column({ space: 8 }) {
      Text($r('app.string.desktop_plugin_basic_title')).fontSize(17).fontWeight(FontWeight.Medium)
      ForEach(this.basicScopes, (scope: string): void => {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 12 }) {
            Image(this.basicArtwork(scope)).width(36).height(36).supportSvg2(true).draggable(false).accessibilityLevel('no')
            Column({ space: 4 }) {
              Text(this.basicTitle(scope)).fontSize(15).fontWeight(FontWeight.Medium)
              Text(this.basicSummary(scope)).fontSize(13).fontColor($r('sys.color.font_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Image($r('app.media.dsh_browser_chevron_right_outline')).width(16).height(16)
              .supportSvg2(true).draggable(false).accessibilityLevel('no')
          }.width('100%').padding(9)
        }.width('100%').constraintSize({ minHeight: 60 }).padding(0).borderRadius(12)
          .backgroundColor($r('app.color.workspace_panel')).key('desktopPluginBasic-' + scope)
          .accessibilityText(this.basicTitle(scope)).enabled(!this.busy)
          .onClick((): void => { this.settingsDetail = scope; })
      }, (scope: string): string => scope)
    }.key('desktopPluginBasicSettings').width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private BasicSettingsDetail() {
    Column({ space: 12 }) {
      Button($r('app.string.desktop_plugin_basic_back'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopPluginSettingsBack').onClick((): void => { this.settingsDetail = ''; })
      ForEach([this.settingsDetail], (scope: string): void => {
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Image(this.basicArtwork(scope)).width(36).height(36).supportSvg2(true).draggable(false).accessibilityLevel('no')
            Text(this.basicTitle(scope)).fontSize(22).fontWeight(FontWeight.Medium)
          }.width('100%')
          Text(this.basicSummary(scope)).fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
          DesktopPluginSettings({ host: this.host, scope: scope })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (scope: string): string => scope)
    }.key('desktopPluginBasicDetail-' + this.settingsDetail).width('100%').alignItems(HorizontalAlign.Start)
  }

  private bundleComponentState(bundle: DesktopPluginRow): DesktopPluginComponentView[] {
    return bundle.components.map((component: DesktopPluginComponent): DesktopPluginComponentView => {
      const live = component.entryId ? this.plugins.find((row: DesktopPluginRow): boolean => row.id === component.entryId) :
        undefined;
      return { component: component, toggle: bundle.enabled && live?.toggle === true,
        settings: bundle.enabled && bundle.id === DESKTOP_FORGE_BUNDLE && component.rowId === WORKTREE_SETTINGS &&
          component.module === '@deepseek-ai/dsh-experimental-worktree' &&
          this.optionalNamespaces.includes(WORKTREE_SETTINGS),
        enabled: bundle.enabled && live?.enabled === true,
        phase: bundle.enabled ? live?.phase ?? '' : '', diagnostic: bundle.enabled ? live?.diagnostic ?? '' : '' };
    });
  }

  private toggleBundleComponent(bundleId: string, entryId: string, enabled: boolean): void {
    const current = this.bundles.find((row: DesktopPluginRow): boolean => row.id === bundleId);
    if (this.detailName !== bundleId || current === undefined || this.catalogBusy || this.installer.busy() ||
      this.maintenance.phase === 'running') { return; }
    const row = this.bundleComponentState(current).find((item: DesktopPluginComponentView): boolean =>
      item.component.entryId === entryId);
    if (row?.toggle && row.enabled !== enabled) {
      this.mutate('pluginManager/setPluginEnabled', { 'id': entryId, 'enabled': enabled });
    }
  }

  @Builder
  private WorktreeDetail() {
    Column({ space: 12 }) {
      Button($r('app.string.desktop_plugin_component_back'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopPluginComponentBack').onClick((): void => { this.componentDetail = false; })
      Text($r('app.string.desktop_worktree_configuration')).fontSize(22).fontWeight(FontWeight.Medium)
      Text('@deepseek-ai/dsh-experimental-worktree').fontSize(13).fontColor($r('sys.color.font_secondary'))
      DesktopPluginSettings({ host: this.host, scope: WORKTREE_SETTINGS })
    }.key('desktopPluginComponentDetail').width('100%').alignItems(HorizontalAlign.Start)
      .visibility(this.componentDetail ? Visibility.Visible : Visibility.None)
  }

  @Builder
  private BundleDetail() {
    Column({ space: 12 }) {
      if (!this.componentDetail) { this.BundleOverview() }
      if (this.worktreeVisited && this.detailName === DESKTOP_FORGE_BUNDLE) { this.WorktreeDetail() }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private BundleOverview() {
    Column({ space: 12 }) {
      Button('返回插件包', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginDetailBack')
        .onClick((): void => { this.closeBundle(); })
      Row({ space: 8 }) {
        Text((this.detailName === this.requestedBundle ? this.requestedTitle : '') ||
          this.bundles.find((row: DesktopPluginRow): boolean => row.id === this.detailName)?.title || this.detailName)
          .key('desktopPluginDetailTitle').fontSize(22).fontWeight(FontWeight.Medium)
        if (this.bundles.some((row: DesktopPluginRow): boolean => row.id === this.detailName && row.enabled) &&
          this.connectorAccounts.byBundle(this.detailName)?.badge) {
          DesktopConnectorBadge({ text: this.connectorAccounts.byBundle(this.detailName)?.badge ?? '',
            phase: this.connectorAccounts.byBundle(this.detailName)?.phase ?? '' })
        }
      }.width('100%')
      if (this.detailName === this.requestedBundle && this.requestedDescription) {
        Text(this.requestedDescription).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      ForEach(this.bundles.filter((row: DesktopPluginRow): boolean => row.id === this.detailName), (row: DesktopPluginRow): void => {
        Column({ space: 8 }) {
          this.PluginRow(row)
          this.BundleActions(row)
          if (row.components.length > 0) {
            DesktopPluginBundleComponents({ rows: this.bundleComponentState(row),
              busy: this.busy || this.catalogBusy || this.installer.busy() || this.maintenance.phase === 'running',
              onSettings: (_rowId: string): void => { this.worktreeVisited = true; this.componentDetail = true; },
              onToggle: (entryId: string, enabled: boolean): void => { this.toggleBundleComponent(row.id, entryId, enabled); } })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (row: DesktopPluginRow): string => JSON.stringify(row))
      DesktopConnectorAccountView({ account: this.connectorAccounts.byBundle(this.detailName),
        actionsEnabled: this.connectorAccounts.linked &&
          !this.connectorAccounts.pending.includes(this.connectorAccounts.byBundle(this.detailName)?.key ?? ''),
        onAction: (account: DesktopConnectorAccount, action: DesktopConnectorAction): void => {
          this.accountAction(account, action);
        } })
      if (this.detailName === DESKTOP_VOICE_BUNDLE &&
        this.bundles.some((row: DesktopPluginRow): boolean => row.id === this.detailName && row.enabled)) {
        DesktopVoiceSettings({ host: this.host })
      }
      if (this.detailName === DESKTOP_TIMELINE_BUNDLE && this.optionalNamespaces.includes(DESKTOP_TIMELINE_NS) &&
        this.bundles.some((bundle: DesktopPluginRow): boolean => bundle.id === this.detailName && bundle.enabled)) {
        DesktopTimelineSettings({ host: this.host })
      }
      if (this.detailLoading) {
        LoadingProgress().width(22).height(22)
      } else if (this.detailError) {
        Text(this.detailError).fontSize(13).fontColor($r('app.color.workspace_status_error'))
        Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.openBundle(this.detailName); })
      } else if (this.detailText) {
        MarkdownRenderer({ text: this.detailText })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private canEnableMarket(): boolean {
    return this.bundles.some((row: DesktopPluginRow): boolean =>
      row.id === MARKET_BUNDLE && row.toggle && !row.enabled);
  }

  private installedMarketBundle(): DesktopPluginRow | undefined {
    const name = getString(this.marketDetail, 'name');
    return this.bundles.find((row: DesktopPluginRow): boolean => row.id === name && row.installed);
  }

  private offerMarketUpdate(name: string, title: string, from: string, to: string, spec: string): void {
    const installed = this.installedMarketBundle();
    if (installed?.id !== name || installed?.update !== 'git' || installed?.version !== from || !spec ||
      this.maintenanceOpening || this.maintenanceDialog >= 0 || this.installer.busy() || this.busy) { return; }
    if (this.maintenance.offerUpdate(name, title, from, to, undefined, spec)) { this.openMaintenance(); }
  }

  @Builder
  private MarketDetail() {
    DesktopPluginMarketDetail({ host: this.host, source: this.marketDetailSource, entry: this.marketDetail,
      localePreference: this.localePreference,
      installed: this.installedMarketBundle() !== undefined,
      installedVersion: this.installedMarketBundle()?.version ?? '',
      busy: this.busy || this.maintenance.phase === 'running',
      onBack: (): void => { this.marketDetail = undefined; },
      onOpenInstalled: (name: string): void => { this.marketDetail = undefined; this.openBundle(name); },
      onInstall: (spec: string, registry: string): void => { this.openInstall(spec, registry); },
      onUpdate: (name: string, title: string, from: string, to: string, spec: string): void => {
        this.offerMarketUpdate(name, title, from, to, spec);
      } })
  }

  @Builder
  private Discover() {
    Row({ space: 8 }) {
      Button(this.sources.find((row: DesktopMarketSource): boolean => row.url === this.source)?.title || '索引来源',
        { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(!this.busy && this.sources.length > 0)
        .bindMenu(this.sources.map((row: DesktopMarketSource): MenuElement => {
          return { value: row.title, action: (): void => {
            this.source = row.url;
            this.market = [];
            this.nextOffset = -1;
            this.searchMarket(false);
          } };
        }), desktopMenuOptions(Placement.BottomLeft))
      TextInput({ 'text': this.query, placeholder: '搜索市场插件' }).layoutWeight(1)
        .onChange((value: string): void => { this.query = value; })
        .onSubmit((): void => { this.searchMarket(false); })
      Button('搜索').enabled(!this.busy && this.source.length > 0).onClick((): void => { this.searchMarket(false); })
      Button('管理索引', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(this.marketError.length === 0 && !this.busy)
        .onClick((): void => { this.editSources = !this.editSources; })
    }
    .width('100%')
    if (this.marketError.length > 0) {
      if (this.canEnableMarket()) {
        Row({ space: 8 }) {
          Text('当前核心未启用插件市场').fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          Button('启用插件市场', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .onClick((): void => {
              this.toggleBundle(MARKET_BUNDLE, true);
            })
        }
        .width('100%')
      } else {
        Text(this.marketError).fontColor($r('sys.color.warning'))
      }
    } else if (this.sources.length === 0 && !this.editSources) {
      Text('未配置可用的市场索引').fontColor($r('sys.color.font_secondary'))
    }
    if (this.editSources) {
      Row({ space: 8 }) {
        TextInput({ text: this.sourceInput, placeholder: '索引 URL' }).layoutWeight(1)
          .onChange((value: string): void => { this.sourceInput = value; })
        Button('添加索引').enabled(!this.busy && this.sourceInput.trim().length > 0)
          .onClick((): void => { this.addSource(); })
      }
      .width('100%')
      ForEach(this.sources, (row: DesktopMarketSource) => {
        Row({ space: 8 }) {
          Text(row.title).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('移除索引', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .onClick((): void => {
              this.confirm('移除索引', row.url, (): void => {
                this.saveSources(this.sources.filter((source: DesktopMarketSource): boolean => source.url !== row.url)
                  .map((source: DesktopMarketSource): string => source.url));
              });
            })
        }
        .width('100%').padding(8)
      }, (row: DesktopMarketSource): string => row.url)
    }
    ForEach(this.market, (entry: Object) => {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(desktopLocalizedText(entry, 'title') || getString(entry, 'name') || '').fontSize(15)
          Text(desktopLocalizedText(entry, 'description')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button($r('app.string.desktop_plugin_maintenance_view'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPluginMarketEntry-' + getString(entry, 'name'))
          .onClick((): void => { this.marketDetailSource = this.source; this.marketDetail = entry; })
        if (this.marketActions(entry).length > 0) {
          Button('选择版本', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .bindMenu(this.marketActions(entry), desktopMenuOptions(Placement.BottomRight))
        }
      }
      .width('100%').padding(10).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
    }, (entry: Object): string => getString(entry, 'name') ?? '')
    if (this.nextOffset >= 0) {
      Button('加载更多', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .onClick((): void => { this.searchMarket(true); })
    }
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('插件').fontSize(26).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy && !this.catalogBusy)
          .onClick((): void => { this.connectorAccounts.reconnect(); this.refresh(); })
        Button('在 WebUI 打开', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginOpenWeb')
          .enabled(!this.busy).onClick((): void => { this.onWeb(this.detailName); })
      }
      .width('100%')
      if (!this.detailName && !this.settingsDetail && this.marketDetail === undefined) {
        Row({ space: 8 }) {
          Button(this.tab === 'bundles' ? '插件包' : this.tab === 'entries' ? '运行中的插件' :
            this.tab === 'settings' ? '配置' : '插件市场',
            { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopPluginsView').enabled(!this.busy)
            .bindMenu([
              { value: '插件包', action: (): void => { this.tab = 'bundles'; } },
              { value: '运行中的插件', action: (): void => { this.tab = 'entries'; } },
              { value: '配置', action: (): void => { this.settingsVisited = true; this.tab = 'settings'; } },
              { value: '插件市场', action: (): void => {
                this.tab = 'market';
                if (this.market.length === 0) {
                  this.searchMarket(false);
                }
              } }
            ], desktopMenuOptions(Placement.BottomLeft))
          Blank()
          if (this.tab === 'bundles' || this.installer.phase !== 'idle') {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL }) {
              Row({ space: 6 }) {
                Image($r('app.media.dsh_reference_menu_plus')).width(16).height(16).supportSvg2(true)
                  .draggable(false).accessibilityLevel('no')
                Text(this.installer.phase === 'idle' ? $r('app.string.desktop_plugin_install_add') :
                  $r('app.string.desktop_plugin_install_task')).fontSize(14).fontColor($r('sys.color.font_primary'))
              }
            }.height(34).borderRadius(8).padding({ left: 10, right: 10 }).key('desktopPluginOpenInstall')
            .onClick((): void => { this.openInstall(); })
          }
          if (this.busy || this.catalogBusy) {
            LoadingProgress().width(24).height(24)
          }
        }.width('100%')
      }
      if (this.status || this.catalogError) {
        Text(this.status || this.catalogError).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
      }
      Scroll() {
        Column({ space: 8 }) {
          if (this.detailName) {
            this.BundleDetail()
          } else if (this.settingsDetail) {
            this.BasicSettingsDetail()
          } else if (this.marketDetail !== undefined) {
            this.MarketDetail()
          } else {
            if (this.settingsVisited) {
              DesktopPluginSettings({ host: this.host }).visibility(this.tab === 'settings' ? Visibility.Visible : Visibility.None)
            }
            if (this.tab === 'market') {
              this.Discover()
            } else if (this.tab !== 'settings') {
              if (this.tab === 'bundles' && this.basicScopes.length > 0) { this.BasicSettingsCards() }
              ForEach(this.tab === 'bundles' ? this.bundles : this.plugins, (row: DesktopPluginRow) => {
                this.PluginRow(row, this.tab === 'bundles')
              }, (row: DesktopPluginRow): string => JSON.stringify(row))
              if (!this.busy && !this.catalogBusy && (this.tab === 'bundles' ?
                this.bundles.length === 0 && this.basicScopes.length === 0 : this.plugins.length === 0)) {
                Text('暂无插件').fontColor($r('sys.color.font_secondary'))
              }
            }
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').layoutWeight(1).align(Alignment.TopStart)
    }
    .padding(20).height('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
    .onAreaChange((_previous: Area, current: Area): void => { this.paneWidth = Number(current.width); })
  }
}
