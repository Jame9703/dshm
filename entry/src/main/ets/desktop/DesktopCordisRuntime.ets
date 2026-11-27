import { getArray, getBoolean, getRecord, getString } from 'connection';
import type { RpcResult } from 'connection';
import { DesktopHostActions, desktopHostItems } from './DesktopHostActions';

const RUNNER: string = 'dynamicCordisRunner/';

export interface DesktopCordisPackage {
  id: string;
  name: string;
  purpose: string;
  hasClient: boolean;
}

export interface DesktopCordisRow {
  id: string;
  session: string;
  packages: DesktopCordisPackage[];
  running: string;
  current: string;
  next: string;
  approval: string;
  target: string;
  status: string;
  problem: string;
}

export interface DesktopCordisSnapshot {
  rows: DesktopCordisRow[];
  problem: string;
}

function readRow(raw: Object): DesktopCordisRow | undefined {
  const id = getString(raw, 'pluginId');
  const session = getString(raw, 'agentId');
  if (!id || !session) { return undefined; }
  const packages: DesktopCordisPackage[] = [];
  for (const item of getArray(raw, 'packages') ?? []) {
    const packageId = getString(item, 'packageId');
    if (packageId) {
      packages.push({ id: packageId, name: getString(item, 'name') || packageId,
        purpose: getString(item, 'purpose') ?? '', hasClient: getBoolean(item, 'hasClientHalf') === true });
    }
  }
  const attempt = getRecord(raw, 'latestRun');
  const status = getString(attempt, 'status') ?? '';
  return {
    id: id, session: session, packages: packages,
    running: getString(getRecord(raw, 'activeRun'), 'packageId') ?? '',
    current: getString(raw, 'currentPackageId') ?? '', next: getString(raw, 'nextPackageId') ?? '',
    approval: status === 'awaiting-approval' ? getString(attempt, 'approvalRequestId') ?? '' : '',
    target: getString(attempt, 'packageId') ?? '', status: status,
    problem: getString(getRecord(attempt, 'error'), 'message') ?? ''
  };
}

export class DesktopCordisRuntime {
  private readonly host: DesktopHostActions;
  private readonly listeners: Set<(snapshot: DesktopCordisSnapshot) => void> = new Set();
  private snapshot: DesktopCordisSnapshot = { rows: [], problem: '' };
  private enabled: boolean = false;
  private generation: number = 0;
  private reading: boolean = false;
  private queued: boolean = false;

  constructor(host: DesktopHostActions) { this.host = host; }

  watch(listener: (snapshot: DesktopCordisSnapshot) => void): () => void {
    this.listeners.add(listener);
    listener(this.snapshot);
    return (): void => { this.listeners.delete(listener); };
  }

  private publish(snapshot: DesktopCordisSnapshot): void {
    this.snapshot = snapshot;
    this.listeners.forEach((listener: (value: DesktopCordisSnapshot) => void): void => listener(snapshot));
  }

  start(): void {
    this.enabled = true;
    this.refresh();
  }

  reconnect(): void {
    this.generation++;
    this.reading = false;
    this.queued = false;
    this.refresh();
  }

  dispose(): void {
    this.enabled = false;
    this.reconnect();
    this.listeners.clear();
  }

  observe(event: string | undefined): void {
    if (event === 'cordis/dynamic-package' || event === 'cordis/dynamic-retract' ||
      event === 'cordis/request-run' || event === 'cordis/request-run-resolved') {
      this.refresh();
    }
  }

  async refresh(): Promise<void> {
    if (!this.enabled) { return; }
    if (this.reading) { this.queued = true; return; }
    const generation = this.generation;
    this.reading = true;
    const result = await this.host.call(RUNNER + 'inventory');
    if (generation !== this.generation) { return; }

    if (result.ok) {
      const rows: DesktopCordisRow[] = [];
      for (const item of desktopHostItems(result)) {
        const row = readRow(item);
        if (row !== undefined) { rows.push(row); }
      }
      this.publish({ rows: rows, problem: '' });
    } else {
      this.publish({ rows: this.snapshot.rows, problem: result.error?.message ?? '' });
    }
    this.reading = false;
    if (this.queued) {
      this.queued = false;
      this.refresh();
    }
  }

  run(row: DesktopCordisRow, pkg: DesktopCordisPackage): Promise<string> {
    // The host commits host-only runs itself. Client packages must go through the browser runner.
    return this.perform('runHostHalf', { 'agentId': row.session, 'pluginId': row.id, 'packageId': pkg.id,
      'mode': row.current && row.current !== pkg.id ? 'update' : 'run', 'requestId': null,
      'approveFutureVersions': false });
  }

  stop(row: DesktopCordisRow): Promise<string> {
    return this.perform('stopFromPanel', { 'agentId': row.session, 'pluginId': row.id });
  }

  remove(row: DesktopCordisRow): Promise<string> {
    return this.perform('undefineFromPanel', { 'agentId': row.session, 'pluginId': row.id });
  }

  decline(row: DesktopCordisRow): Promise<string> {
    const resolution: Record<string, Object> = { 'ok': false, 'reason': 'rejected' };
    return this.perform('resolveRequestRun', { 'requestId': row.approval, 'resolution': resolution });
  }

  private async perform(method: string, body: Record<string, Object | null>): Promise<string> {
    const result: RpcResult = await this.host.call(RUNNER + method, body);
    this.refresh();
    if (result.ok &&
      (getBoolean(result.value, 'ok') === true || getBoolean(result.value, 'accepted') === true ||
        (method === 'stopFromPanel' && getString(result.value, 'reason') === 'not-running'))) { return ''; }
    return result.error?.message || getString(result.value, 'message') ||
      getString(result.value, 'reason') || '操作未完成，请刷新后重试';
  }
}
