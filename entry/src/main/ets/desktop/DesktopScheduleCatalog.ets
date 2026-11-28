import { getRecord, getString } from 'connection';
import { DesktopHostActions, desktopHostItems, desktopHostProblem } from './DesktopHostActions';

export interface DesktopScheduleCatalogSnapshot {
  tasks: Object[];
  ready: boolean;
  loading: boolean;
  error: string;
}

type CatalogListener = (snapshot: DesktopScheduleCatalogSnapshot) => void;

export class DesktopScheduleCatalog {
  private readonly listeners = new Set<CatalogListener>();
  private generation: number = 0;
  private queued: boolean = false;
  private reader?: Promise<boolean>;
  private snapshot: DesktopScheduleCatalogSnapshot = { tasks: [], ready: false, loading: false, error: '' };

  private readonly host: DesktopHostActions;

  constructor(host: DesktopHostActions) { this.host = host; }

  watch(listener: CatalogListener): () => void {
    this.listeners.add(listener);
    listener(this.snapshot);
    if (this.listeners.size === 1) { this.refresh(); }
    return (): void => {
      if (!this.listeners.delete(listener) || this.listeners.size > 0) { return; }
      this.generation++;
      this.reader = undefined;
      this.queued = false;
    };
  }

  refresh(): Promise<boolean> {
    if (this.listeners.size === 0) { return Promise.resolve(false); }
    this.queued = true;
    if (this.reader !== undefined) { return this.reader; }
    const generation = this.generation;
    const current = this.read(generation);
    this.reader = current;
    return current;
  }

  private publish(snapshot: DesktopScheduleCatalogSnapshot): void {
    this.snapshot = snapshot;
    for (const listener of this.listeners) { listener(snapshot); }
  }

  private async read(generation: number): Promise<boolean> {
    this.publish({ tasks: this.snapshot.tasks, ready: false, loading: true, error: '' });
    let confirmed = false;
    try {
      while (generation === this.generation && this.queued) {
        this.queued = false;
        const result = await this.host.call('schedule/catalog');
        if (generation !== this.generation) { return false; }
        if (this.queued) { continue; }
        const error = desktopHostProblem(result);
        confirmed = error.length === 0;
        this.publish({ tasks: confirmed ? desktopHostItems(result) : this.snapshot.tasks, ready: confirmed,
          loading: false, error: error });
      }
    } catch (_) {
      if (generation === this.generation) {
        this.publish({ tasks: this.snapshot.tasks, ready: false, loading: false, error: '读取自动化任务失败' });
      }
      return false;
    } finally {
      if (generation === this.generation) { this.reader = undefined; }
    }
    return confirmed;
  }
}

export function desktopScheduleNextTime(row: Object): string {
  const scheduled = getString(row, 'scheduledAt') ?? '';
  const floor = getString(row, 'deliveryFloorEndsAt') ?? '';
  return Date.parse(floor) > Date.parse(scheduled) ? floor : scheduled;
}

export function desktopScheduleShowsRecommendations(ready: boolean, rows: number, search: string, filter: string): boolean {
  return ready && rows === 0 && !search.trim() && (filter === 'active' || filter === 'all');
}

function linkedSession(row: Object): string {
  const target = getRecord(row, 'target');
  return (getString(target, 'kind') === 'new' ? getString(getRecord(row, 'lastDelivery'), 'targetSessionId') :
    getString(target, 'sessionId')) ?? '';
}

function fuzzyTitle(title: string, query: string): boolean {
  let cursor = 0;
  for (const part of query) {
    cursor = title.indexOf(part, cursor) + 1;
    if (cursor === 0) { return false; }
  }
  return true;
}

export function desktopScheduleRows(tasks: Object[], filter: string, search: string): Object[] {
  const query = search.trim().toLocaleLowerCase();
  return tasks.filter((row: Object): boolean => {
    if (filter !== 'all' && getString(row, 'status') !== filter) { return false; }
    if (!query) { return true; }
    const title = (getString(row, 'title') || getString(row, 'prompt') || '').toLocaleLowerCase();
    return fuzzyTitle(title, query) || (getString(row, 'prompt') ?? '').toLocaleLowerCase().includes(query) ||
      linkedSession(row).toLocaleLowerCase().includes(query);
  }).sort((left: Object, right: Object): number => {
    const earlier = Date.parse(desktopScheduleNextTime(left));
    const later = Date.parse(desktopScheduleNextTime(right));
    return (Number.isFinite(earlier) ? earlier : Number.MAX_SAFE_INTEGER) -
      (Number.isFinite(later) ? later : Number.MAX_SAFE_INTEGER);
  });
}
