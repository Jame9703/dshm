import { util } from '@kit.ArkTS';
import { getArray, getNumber, getRecord, getString, toStringArray } from 'connection';
import type { RpcResult } from 'connection';
import { EVENT_PLUGIN_INSTALL_LOG, EVENT_PLUGIN_INSTALL_STATE, EVENT_PLUGIN_MANAGER_CHANGED } from 'dshcompat';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';

const MAX_OUTPUT: number = 24000;
const OUTPUT_ESCAPE = new RegExp('\\x1b\\[[0-?]*[ -/]*[@-~]|[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]', 'g');

@Observed
export class DesktopPluginInstall {
  phase: string = 'idle';
  spec: string = '';
  registry: string = '';
  registries: string[] = [];
  name: string = '';
  version: string = '';
  description: string = '';
  source: string = '';
  problem: string = '';
  output: string = '';
  tried: string = '';
  logPath: string = '';
  installedName: string = '';
  restartRequired: boolean = false;
  enabled: boolean = false;
  enabling: boolean = false;

  private readonly host: DesktopHostActions;
  private readonly listeners: Set<() => void> = new Set();
  private active: boolean = true;
  private inspection: number = 0;
  private requested: string = '';
  private accepted: boolean = false;
  private cancelWhenAccepted: boolean = false;
  private recovering: boolean = false;
  private readRegistries: boolean = false;
  private inspectedRegistry: string = '';

  constructor(host: DesktopHostActions) { this.host = host; }

  dispose(): void {
    this.active = false;
    this.listeners.clear();
  }

  busy(): boolean {
    return this.phase === 'starting' || this.phase === 'running' || this.phase === 'applying' ||
      this.phase === 'cancelling' || this.phase === 'unconfirmed';
  }

  private applying(): boolean { return this.phase === 'applying'; }

  watchCatalog(listener: () => void): () => void {
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }

  private catalogChanged(): void {
    this.listeners.forEach((listener: () => void): void => { listener(); });
  }

  offer(spec: string, registry: string): void {
    if (spec && !this.busy() && this.phase !== 'checking' && !this.enabling) {
      this.reset();
      this.spec = spec;
      this.registry = registry;
    }
    this.loadRegistries();
  }

  private async loadRegistries(): Promise<void> {
    if (this.readRegistries) { return; }
    this.readRegistries = true;
    const result = await this.host.call('pluginManager/registries');
    if (!this.active || !result.ok) { this.readRegistries = false; return; }
    const entries = [getString(result.value, 'registry') ?? '', getString(result.value, 'resolved') ?? '',
      ...toStringArray(getArray(result.value, 'fallbackRegistries') ?? [])];
    this.registries = Array.from(new Set<string>(entries.filter((value: string): boolean => value.length > 0)));
  }

  closeInspection(): void {
    if (this.phase === 'checking') {
      this.inspection++;
      this.phase = 'idle';
    }
  }

  edit(): void {
    if (!this.busy() && !this.enabling) { this.phase = 'idle'; this.problem = ''; }
  }

  reset(): void {
    if (this.busy() || this.enabling) { return; }
    this.inspection++;
    this.phase = 'idle';
    this.spec = '';
    this.registry = '';
    this.problem = '';
    this.output = '';
    this.tried = '';
    this.logPath = '';
    this.installedName = '';
    this.restartRequired = false;
    this.enabled = false;
  }

  async inspect(): Promise<void> {
    if (this.phase !== 'idle' || !this.spec.trim()) { return; }
    const version = ++this.inspection;
    this.spec = this.spec.trim();
    this.registry = this.registry.trim();
    if (this.registry && !new RegExp('^https?://[^\\s/]+', 'i').test(this.registry)) {
      this.problem = '请输入 HTTP 或 HTTPS 仓库地址';
      return;
    }
    const opts: Record<string, Object> = {};
    if (this.registry) { opts['registry'] = this.registry; }
    this.problem = '';
    this.phase = 'checking';
    const result = await this.host.call('pluginManager/inspect', { 'spec': this.spec, 'options': opts });
    if (!this.active || this.inspection !== version) { return; }
    if (!result.ok || getString(result.value, 'status') !== 'accepted') {
      this.problem = desktopHostProblem(result) || getString(result.value, 'reason') || '宿主无法识别插件';
      this.phase = 'idle';
      return;
    }
    this.name = getString(result.value, 'name') ?? '';
    this.version = getString(result.value, 'version') ?? '';
    this.description = getString(result.value, 'description') ?? '';
    this.inspectedRegistry = getString(result.value, 'registry') ?? this.registry;
    this.source = getString(result.value, 'host') || this.inspectedRegistry;
    this.phase = 'review';
  }

  async start(): Promise<void> {
    if (this.phase !== 'review') { return; }
    const id = util.generateRandomUUID();
    this.requested = id;
    this.accepted = false;
    this.cancelWhenAccepted = false;
    this.output = '';
    this.logPath = '';
    this.tried = '';
    this.problem = '';
    this.installedName = '';
    this.enabled = false;
    this.restartRequired = false;
    this.phase = 'starting';
    const opts: Record<string, Object> = { 'enabled': false, 'requestId': id };
    if (this.inspectedRegistry) { opts['registry'] = this.inspectedRegistry; }
    const result = await this.host.call('pluginManager/installBundle', { 'spec': this.spec, 'options': opts }, 180000);
    if (!this.current(id)) { return; }
    if (result.ok) { this.settle(result); return; }
    this.problem = desktopHostProblem(result);
    if (!this.applying()) { this.phase = 'unconfirmed'; }
    this.recover();
  }

  private current(id: string): boolean { return this.active && this.requested === id; }

  async recover(): Promise<void> {
    const id = this.requested;
    if (!id || this.recovering) { return; }
    this.recovering = true;
    const result = await this.host.call('pluginManager/waitForInstall', { 'requestId': id }, 180000);
    this.recovering = false;
    if (!this.current(id)) { return; }
    if (!result.ok) {
      this.problem = desktopHostProblem(result);
      if (this.phase !== 'applying') { this.phase = 'unconfirmed'; }
    } else if (getString(result.value, 'application')) {
      this.settle(result);
    } else {
      this.requested = '';
      this.cancelWhenAccepted = false;
      this.phase = 'unknown';
      this.problem = '宿主未保留这次安装的结果，请查看插件列表确认';
      this.catalogChanged();
    }
  }

  reconnect(): void {
    if (this.phase === 'unconfirmed' || (this.phase === 'applying' && this.problem)) { this.recover(); }
  }

  async cancel(): Promise<void> {
    const id = this.requested;
    if (!id || !this.busy() || this.phase === 'applying' || this.phase === 'cancelling') { return; }
    const acceptedBefore = this.accepted;
    this.phase = 'cancelling';
    this.problem = '';
    const result = await this.host.call('pluginManager/cancelInstall', { 'requestId': id }, 180000);
    if (!this.current(id)) { return; }
    const status = getString(result.value, 'status');
    if (status === 'cancelled') {
      this.requested = '';
      this.cancelWhenAccepted = false;
      this.phase = 'cancelled';
      this.catalogChanged();
    } else if (status === 'too-late' || this.applying()) {
      this.phase = 'applying';
    } else if (status === 'not-running' && !acceptedBefore && this.accepted) {
      this.phase = 'running';
      this.cancel();
    } else {
      const retryOnAcceptance = status === 'not-running' && !acceptedBefore;
      this.cancelWhenAccepted = retryOnAcceptance;
      this.phase = retryOnAcceptance ? 'starting' : 'unconfirmed';
      if (!retryOnAcceptance) { this.problem = desktopHostProblem(result) || '宿主未确认取消'; }
    }
  }

  private appendOutput(chunk: string): void {
    this.output = (this.output + chunk.replace(OUTPUT_ESCAPE, '')).slice(-MAX_OUTPUT);
  }

  observe(frame: Object): void {
    const event = getString(frame, 'event');
    if (event === EVENT_PLUGIN_MANAGER_CHANGED) { this.catalogChanged(); }
    if (!this.requested || (event !== EVENT_PLUGIN_INSTALL_STATE && event !== EVENT_PLUGIN_INSTALL_LOG)) { return; }
    const value = getArray(frame, 'args')?.[0];
    if (getString(value, 'requestId') !== this.requested) { return; }
    this.accepted = true;
    if (event === EVENT_PLUGIN_INSTALL_LOG) {
      this.appendOutput(getString(value, 'text') ?? '');
    }
    const phase = getString(value, 'phase');
    if (phase === 'applying') {
      this.phase = 'applying';
      this.cancelWhenAccepted = false;
    } else if (this.phase !== 'applying') {
      if (phase === 'cancelling') { this.phase = 'cancelling'; }
      if (phase === 'installing') {
        const attempt = getRecord(value, 'attempt');
        const index = getNumber(attempt, 'index');
        const total = getNumber(attempt, 'total');
        const registry = getString(attempt, 'registry') ?? '';
        this.tried = index !== undefined && total !== undefined ? `${index} / ${total}  ${registry}` : registry;
      }
      if (phase === 'installing' || this.phase === 'starting') {
        if (this.phase !== 'cancelling') { this.phase = 'running'; }
        if (this.cancelWhenAccepted) { this.cancelWhenAccepted = false; this.cancel(); }
      }
    }
  }

  private settle(result: RpcResult): void {
    this.requested = '';
    this.cancelWhenAccepted = false;
    const value = result.value;
    const output = getRecord(value, 'packageResult');
    this.logPath = getString(output, 'logPath') ?? '';
    const finalOutput = getString(output, 'output') ?? '';
    if (finalOutput && !this.output) { this.appendOutput(finalOutput); }
    const application = getString(value, 'application');
    if (application === 'cancelled') { this.phase = 'cancelled'; this.problem = ''; }
    else if (application === 'applied' || application === 'restart-required') {
      this.phase = 'done';
      this.problem = '';
      this.installedName = getString(value, 'bundle') ?? '';
      this.version = getString(value, 'version') ?? this.version;
      this.restartRequired = application === 'restart-required';
      this.enabled = false;
    } else {
      this.phase = 'failed';
      this.problem = desktopHostProblem(result) || '宿主未确认安装结果';
    }
    this.catalogChanged();
  }

  async enable(): Promise<string> {
    if (this.phase !== 'done' || !this.installedName || this.enabling || this.enabled) { return ''; }
    const name = this.installedName;
    this.enabling = true;
    const result = await this.host.call('pluginManager/setBundleEnabled', { 'name': name, 'enabled': true });
    if (!this.active) { return ''; }
    this.enabling = false;
    this.problem = desktopHostProblem(result);
    if (!this.problem) {
      this.enabled = true;
      this.restartRequired = getString(result.value, 'application') === 'restart-required';
      this.catalogChanged();
      return this.restartRequired ? '' : name;
    }
    return '';
  }
}
