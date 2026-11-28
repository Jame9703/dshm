import { getArray, getBoolean, getString } from 'connection';
import { SETTINGS_MUTATE_ENDPOINT } from 'dshcompat';
import { desktopHostProblem } from './DesktopHostActions';
import type { DesktopHostActions } from './DesktopHostActions';
import { desktopPluginPathOps, readDesktopPluginDocument } from './DesktopPluginSettingsModel';
import type { DesktopPluginDocument, DesktopPluginEdit } from './DesktopPluginSettingsModel';

export const DESKTOP_CODING_TOOLS_NS: string = 'ui-settings';

export interface DesktopCodingToolsSnapshot {
  enabled: boolean;
  available: boolean;
  writable: boolean;
  busy: boolean;
  error: string;
}

export function emptyDesktopCodingToolsSnapshot(): DesktopCodingToolsSnapshot {
  return { enabled: false, available: false, writable: false, busy: false, error: '' };
}

export function desktopPresetVisible(id: string, name: string | undefined, developerTools: boolean): boolean {
  return developerTools || name !== undefined || (id !== 'ptc' && id !== 'minimal');
}

export class DesktopCodingTools {
  private readonly host: DesktopHostActions;
  private readonly readSettings: () => Promise<void>;
  private readonly onChange: (state: DesktopCodingToolsSnapshot) => void;
  private state: DesktopCodingToolsSnapshot = emptyDesktopCodingToolsSnapshot();
  private document?: DesktopPluginDocument;
  private alive: boolean = true;
  private ready: boolean = false;
  private waitingForSettings: boolean = true;
  private epoch: number = 0;
  private writable: boolean = false;
  private saving: boolean = false;
  private error: string = '';

  constructor(host: DesktopHostActions, readSettings: () => Promise<void>,
    onChange: (state: DesktopCodingToolsSnapshot) => void) {
    this.host = host;
    this.readSettings = readSettings;
    this.onChange = onChange;
  }

  observeSettings(value?: Object): void {
    if (!this.alive || value === undefined) { return; }
    this.ready = true;
    this.writable = getBoolean(value, 'writable') === true;
    const row = getArray(value, 'namespaces')?.find((raw: Object): boolean =>
      getString(raw, 'ns') === DESKTOP_CODING_TOOLS_NS);
    const doc = readDesktopPluginDocument(row);
    if (this.waitingForSettings || doc === undefined) { this.document = doc; }
    else { this.accept(doc); }
    this.waitingForSettings = false;
    this.publish();
  }

  stop(): void { this.alive = false; }

  connectionLost(): void {
    if (this.waitingForSettings) { return; }
    this.epoch++;
    this.waitingForSettings = true;
    this.saving = false;
    this.error = '';
    this.publish();
  }

  async setEnabled(enabled: boolean): Promise<void> {
    const document = this.document;
    if (!this.alive || this.waitingForSettings || !this.writable || this.saving || document === undefined ||
      this.state.enabled === enabled) { return; }
    const epoch = this.epoch;
    const edit: DesktopPluginEdit = { namespace: DESKTOP_CODING_TOOLS_NS, field: 'enabled', value: enabled };
    this.saving = true;
    this.error = '';
    this.publish();
    try {
      const result = await this.host.call(SETTINGS_MUTATE_ENDPOINT, { 'ns': DESKTOP_CODING_TOOLS_NS,
        'expectedRevision': document.revision, 'ops': desktopPluginPathOps([edit], DESKTOP_CODING_TOOLS_NS) });
      if (!this.alive || epoch !== this.epoch) { return; }
      const next = result.ok ? readDesktopPluginDocument(result.value) : undefined;
      if (next?.id === DESKTOP_CODING_TOOLS_NS) { this.accept(next); }
      if (!result.ok || getBoolean(this.document?.value, 'enabled') !== enabled) { await this.readSettings(); }
      if (epoch === this.epoch && getBoolean(this.document?.value, 'enabled') !== enabled) {
        this.error = desktopHostProblem(result) || 'settings';
      }
    } catch (_) {
      if (epoch === this.epoch) { this.error = 'settings'; }
    } finally {
      if (epoch === this.epoch) {
        this.saving = false;
        this.publish();
      }
    }
  }

  private accept(document: DesktopPluginDocument): void {
    if (document.revision >= (this.document?.revision ?? -1)) { this.document = document; }
  }

  private publish(): void {
    if (!this.alive) { return; }
    const available = this.document !== undefined;
    const next: DesktopCodingToolsSnapshot = {
      enabled: this.ready && (getBoolean(this.document?.value, 'enabled') ?? true), available: available,
      writable: available && !this.waitingForSettings && this.writable, busy: this.saving, error: this.error
    };
    if (next.enabled === this.state.enabled && next.available === this.state.available &&
      next.writable === this.state.writable && next.busy === this.state.busy && next.error === this.state.error) { return; }
    this.state = next;
    this.onChange(next);
  }
}
