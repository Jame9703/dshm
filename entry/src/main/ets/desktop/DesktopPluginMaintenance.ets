import { util } from '@kit.ArkTS';
import { getArray, getRecord, getString } from 'connection';
import type { RpcResult } from 'connection';
import { EVENT_PLUGIN_INSTALL_LOG, EVENT_PLUGIN_UPDATE_STATE } from 'dshcompat';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';

const OUTPUT_ESCAPE = new RegExp('\\x1b\\[[0-?]*[ -/]*[@-~]|[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]', 'g');

export interface DesktopPluginCatalogUpdate {
  fromVersion: string;
  fromSource: string;
  targetSpec: string;
}

@Observed
export class DesktopPluginMaintenance {
  phase: 'idle' | 'confirm' | 'running' | 'done' = 'idle';
  action: 'update' | 'remove' = 'update';
  name: string = '';
  title: string = '';
  fromVersion: string = '';
  toVersion: string = '';
  catalog?: DesktopPluginCatalogUpdate;
  step: string = '';
  application: string = '';
  problem: string = '';
  restore: string = '';
  output: string = '';
  connectionLost: boolean = false;
  private active: boolean = true;
  private requestId: string = '';
  private registry?: string | null;
  private spec: string = '';

  private readonly host: DesktopHostActions;

  constructor(host: DesktopHostActions) { this.host = host; }

  dispose(): void { this.active = false; }

  offerUpdate(name: string, title: string, from: string, to: string, registry?: string | null, spec: string = ''): boolean {
    if (!from || !to || from === to || !this.offer('update', name, title)) { return false; }
    this.fromVersion = from;
    this.toVersion = to;
    this.registry = registry;
    this.spec = spec;
    return true;
  }

  offerRemove(name: string, title: string): boolean { return this.offer('remove', name, title); }

  offerCatalogUpdate(name: string, title: string, to: string, change: DesktopPluginCatalogUpdate): boolean {
    if (!to || !change.fromVersion || !change.fromSource || !change.targetSpec || !this.offer('update', name, title)) {
      return false;
    }
    this.catalog = change;
    this.fromVersion = change.fromVersion;
    this.toVersion = to;
    return true;
  }

  close(): void {
    if (this.phase !== 'running') { this.phase = 'idle'; }
  }

  private offer(action: 'update' | 'remove', name: string, title: string): boolean {
    if (!this.active || !name || this.phase === 'running') { return false; }
    this.action = action;
    this.name = name;
    this.title = title;
    this.fromVersion = '';
    this.toVersion = '';
    this.catalog = undefined;
    this.step = '';
    this.application = '';
    this.problem = '';
    this.restore = '';
    this.output = '';
    this.connectionLost = false;
    this.phase = 'confirm';
    return true;
  }

  async confirm(): Promise<boolean> {
    if (!this.active || this.phase !== 'confirm') { return false; }
    this.phase = 'running';
    let result: RpcResult;
    if (this.action === 'update') {
      this.requestId = util.generateRandomUUID();
      const options: Record<string, Object | null> = { 'requestId': this.requestId };
      if (this.catalog !== undefined) { options['catalog'] = this.catalog; }
      else if (this.spec) { options['spec'] = this.spec; }
      else if (this.registry !== undefined) { options['registry'] = this.registry; }
      this.step = 'checking';
      result = await this.host.call('pluginManager/updateBundle', {
        'name': this.name, 'version': this.toVersion, 'options': options
      }, 180000);
    } else {
      this.step = 'removing';
      result = await this.host.call('pluginManager/removeBundle', { 'name': this.name }, 180000);
    }
    if (!this.active) { return false; }
    this.requestId = '';
    const resultValue = this.action === 'update' ? getRecord(result.value, 'result') : result.value;
    const restore = getRecord(result.value, 'restore');
    const packageResult = getRecord(resultValue, 'packageResult');
    const error = getRecord(resultValue, 'error');
    const outcome: RpcResult = { ok: result.ok, value: resultValue, error: result.error };
    this.connectionLost = !result.ok;
    this.application = getString(resultValue, 'application') ?? '';
    this.problem = getString(error, 'diagnostic') || desktopHostProblem(outcome);
    this.restore = getString(restore, 'application') ?? '';
    const finalOutput = getString(packageResult, 'output') ?? '';
    if (finalOutput && !this.output) { this.appendOutput(finalOutput); }
    this.phase = 'done';
    return true;
  }

  observe(frame: Object): void {
    if (!this.requestId || this.phase !== 'running') { return; }
    const event = getString(frame, 'event');
    if (event !== EVENT_PLUGIN_UPDATE_STATE && event !== EVENT_PLUGIN_INSTALL_LOG) { return; }
    const value = getArray(frame, 'args')?.[0];
    if (getString(value, 'requestId') !== this.requestId) { return; }
    if (event === EVENT_PLUGIN_UPDATE_STATE) {
      this.step = getString(value, 'step') ?? this.step;
    } else {
      this.appendOutput(getString(value, 'text') ?? '');
    }
  }

  private appendOutput(text: string): void {
    this.output = (this.output + text.replace(OUTPUT_ESCAPE, '')).slice(-24000);
  }
}
