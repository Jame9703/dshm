import { getArray, getBoolean, getField, getNumber, getString } from 'connection';
import type { RpcResult } from 'connection';

export interface DesktopPluginVersionTarget {
  name: string;
  version: string;
  update: string;
  source?: string;
}

export interface DesktopPluginVersionEntry {
  version: string;
  prerelease: boolean;
  deprecated?: string;
  installable: boolean;
}

export interface DesktopPluginVersionResult {
  name: string;
  status: 'listed' | 'refused';
  installed: string;
  registry?: string | null;
  versions: DesktopPluginVersionEntry[];
  omitted: number;
  recommendedVersion: string;
  reason: string;
}

export interface DesktopPluginVersionScanSnapshot {
  scanning: boolean;
  total: number;
  completed: number;
  available: number;
  refused: number;
  finished: boolean;
  results: DesktopPluginVersionResult[];
}

interface DesktopPluginVersionPending {
  target: DesktopPluginVersionTarget;
  epoch: number;
  task: Promise<DesktopPluginVersionResult | undefined>;
}

export function emptyDesktopPluginVersionScanSnapshot(): DesktopPluginVersionScanSnapshot {
  return { scanning: false, total: 0, completed: 0, available: 0, refused: 0, finished: false, results: [] };
}

function refused(target: DesktopPluginVersionTarget, reason: string): DesktopPluginVersionResult {
  return { name: target.name, status: 'refused', installed: target.version, versions: [], omitted: 0,
    recommendedVersion: '', reason: reason };
}

/** The Host returns only newer releases in descending semver order. */
export function desktopPluginVersionResult(target: DesktopPluginVersionTarget,
  reply: RpcResult): DesktopPluginVersionResult | undefined {
  if (!reply.ok) { return refused(target, reply.error?.message ?? ''); }
  const value = reply.value;
  const status = getString(value, 'status');
  if (status !== 'listed') {
    return refused(target, getString(value, 'reason') ?? '');
  }
  if (getString(value, 'installed') !== target.version) { return undefined; }
  const raw = getArray(value, 'versions');
  if (raw === undefined) { return refused(target, ''); }
  const entries: DesktopPluginVersionEntry[] = [];
  const seen = new Set<string>();
  let recommended = '';
  for (const data of raw) {
    const version = getString(data, 'version') ?? '';
    if (!version || version === target.version || seen.has(version)) { continue; }
    seen.add(version);
    const entry: DesktopPluginVersionEntry = { version: version, prerelease: getBoolean(data, 'prerelease') === true,
      deprecated: getString(data, 'deprecated'),
      installable: getBoolean(data, 'bundle') === true && getField(data, 'incompatible') === undefined };
    entries.push(entry);
    if (!recommended && entry.installable && entry.deprecated === undefined && !entry.prerelease) {
      recommended = version;
    }
  }
  const registry = getField(value, 'registry') === null ? null : getString(value, 'registry');
  const omitted = getNumber(value, 'omitted') ?? 0;
  return { name: target.name, status: 'listed', installed: target.version, registry: registry, versions: entries,
    omitted: Number.isSafeInteger(omitted) && omitted > 0 ? omitted : 0,
    recommendedVersion: recommended, reason: '' };
}

/** A pane owns one registry queue. Individual checks share its in-flight jobs without restarting the batch. */
export class DesktopPluginVersionScan {
  private readonly read: (name: string) => Promise<RpcResult>;
  private readonly onChange: (snapshot: DesktopPluginVersionScanSnapshot) => void;
  private targets = new Map<string, DesktopPluginVersionTarget>();
  private readonly pending = new Map<string, DesktopPluginVersionPending>();
  private readonly results = new Map<string, DesktopPluginVersionResult>();
  private tail: Promise<void> = Promise.resolve();
  private batch?: Promise<void>;
  private epoch: number = 0;
  private disposed: boolean = false;

  constructor(read: (name: string) => Promise<RpcResult>, onChange: (snapshot: DesktopPluginVersionScanSnapshot) => void) {
    this.read = read;
    this.onChange = onChange;
  }

  replaceTargets(targets: DesktopPluginVersionTarget[]): void {
    if (this.disposed) { return; }
    const next = new Map<string, DesktopPluginVersionTarget>();
    let changed = false;
    for (const target of targets) {
      if (!target.name || !target.version || target.update !== 'registry' || next.has(target.name)) { continue; }
      const prior = this.targets.get(target.name);
      if (prior !== undefined && prior.version === target.version && prior.source === target.source) {
        next.set(target.name, prior);
      } else {
        next.set(target.name, { name: target.name, version: target.version, update: target.update, source: target.source });
        changed = true;
      }
    }
    const previousNames = Array.from(this.targets.keys());
    const nextNames = Array.from(next.keys());
    changed = changed || previousNames.length !== nextNames.length ||
      previousNames.some((name: string, index: number): boolean => name !== nextNames[index]);
    if (!changed) { return; }
    this.targets.forEach((target: DesktopPluginVersionTarget, name: string): void => {
      if (next.get(name) !== target) {
        this.results.delete(name);
        this.pending.delete(name);
      }
    });
    this.targets = next;
    this.publish();
  }

  scan(): Promise<void> {
    if (this.disposed || this.targets.size === 0) { return Promise.resolve(); }
    if (this.batch !== undefined) { return this.batch; }
    const epoch = this.epoch;
    const jobs: Promise<DesktopPluginVersionResult | undefined>[] = [];
    this.targets.forEach((target: DesktopPluginVersionTarget): void => { jobs.push(this.enqueue(target)); });
    const batch = Promise.all(jobs).then((): void => {
      if (this.epoch === epoch) {
        this.batch = undefined;
        this.publish();
      }
    });
    this.batch = batch;
    this.publish();
    return batch;
  }

  check(name: string): Promise<DesktopPluginVersionResult | undefined> {
    const target = this.targets.get(name);
    if (this.disposed || target === undefined) { return Promise.resolve(undefined); }
    const existing = this.pending.get(name);
    if (existing?.target === target) { return existing.task; }
    const result = this.results.get(name);
    if (this.batch !== undefined && result !== undefined) { return Promise.resolve(result); }
    const task = this.enqueue(target);
    this.publish();
    return task;
  }

  result(name: string): DesktopPluginVersionResult | undefined { return this.results.get(name); }

  snapshot(): DesktopPluginVersionScanSnapshot {
    const results: DesktopPluginVersionResult[] = [];
    let available = 0;
    let refusals = 0;
    this.targets.forEach((_target: DesktopPluginVersionTarget, name: string): void => {
      const result = this.results.get(name);
      if (result === undefined) { return; }
      results.push(result);
      if (result.recommendedVersion) { available++; }
      if (result.status === 'refused') { refusals++; }
    });
    const scanning = this.batch !== undefined;
    const total = this.targets.size;
    return { scanning: scanning, total: total, completed: results.length, available: available, refused: refusals,
      finished: !scanning && total > 0 && results.length === total, results: results };
  }

  reset(): void {
    this.epoch++;
    this.targets.clear();
    this.results.clear();
    this.pending.clear();
    this.batch = undefined;
    this.publish();
  }

  dispose(): void {
    this.disposed = true;
    this.reset();
  }

  private enqueue(target: DesktopPluginVersionTarget): Promise<DesktopPluginVersionResult | undefined> {
    const existing = this.pending.get(target.name);
    if (existing?.target === target) { return existing.task; }
    const epoch = this.epoch;
    const work = this.tail.then((): Promise<DesktopPluginVersionResult | undefined> => this.readTarget(target, epoch));
    const task = work.then((result: DesktopPluginVersionResult | undefined): DesktopPluginVersionResult | undefined => {
      const pending = this.pending.get(target.name);
      if (!this.current(target, epoch) || pending?.target !== target || pending.epoch !== epoch) { return undefined; }
      this.pending.delete(target.name);
      if (result !== undefined) { this.results.set(target.name, result); }
      this.publish();
      return result;
    });
    this.tail = task.then((): void => {}, (): void => {});
    this.pending.set(target.name, { target: target, epoch: epoch, task: task });
    this.results.delete(target.name);
    return task;
  }

  private async readTarget(target: DesktopPluginVersionTarget, epoch: number): Promise<DesktopPluginVersionResult | undefined> {
    if (!this.current(target, epoch)) { return undefined; }
    try {
      const answer = await this.read(target.name);
      return this.current(target, epoch) ? desktopPluginVersionResult(target, answer) : undefined;
    } catch (error) {
      return this.current(target, epoch) ? refused(target, error instanceof Error ? error.message : '') : undefined;
    }
  }

  private current(target: DesktopPluginVersionTarget, epoch: number): boolean {
    return !this.disposed && this.epoch === epoch && this.targets.get(target.name) === target;
  }

  private publish(): void {
    if (!this.disposed) { this.onChange(this.snapshot()); }
  }
}
