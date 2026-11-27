import { getArray, getNumber, getRecord, getString, parseJson } from 'connection';

export interface DesktopTimelineSource {
  sequence: number;
  value: Object;
}

export interface DesktopTimelineTask {
  id: string;
  parent: string;
  title: string;
  description: string;
  note: string;
  details: string;
  status: string;
  priority: string;
  share: number;
  progress: number;
  depth: number;
  children: number;
  history: Object[];
}

export interface DesktopTimelineTree {
  id: string;
  title: string;
  description: string;
  tasks: DesktopTimelineTask[];
  progress: number;
}

export interface DesktopTimelineReport {
  id: string;
  level: number;
  start: number;
  end: number;
  workMs?: number;
  savedPeriod?: number;
  toolCount: number;
  source: string;
  children: string[];
  progress: string[];
  uncertainties: string[];
  actions: string[];
}

export interface DesktopTimelineView {
  trees: DesktopTimelineTree[];
  activeTree: string;
  reports: DesktopTimelineReport[];
  annotations: Object[];
  error: string;
}

function numeric(value?: Object): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function texts(values?: Object[]): string[] {
  return (values ?? []).filter((value: Object): boolean => typeof value === 'string')
    .map((value: Object): string => String(value));
}

function parseTask(item: Object): DesktopTimelineTask | undefined {
  const id = getString(item, 'id');
  const title = getString(item, 'title');
  const status = getString(item, 'status') ?? 'pending';
  if (!id || !title || status === 'retired') { return undefined; }
  const done = getArray(item, 'done') ?? [];
  const total = numeric(done[1]);
  return { id: id, title: title, status: status, parent: getString(item, 'parent') ?? '',
    description: getString(item, 'description') ?? '', note: getString(item, 'note') ?? '',
    details: getString(item, 'details') ?? '', priority: getString(item, 'priority') ?? '',
    share: Math.max(Number.EPSILON, getNumber(item, 'timeShare') ?? 1),
    progress: status === 'done' ? 1 : total > 0 ? Math.max(0, Math.min(1, numeric(done[0]) / total)) : 0,
    depth: 0, children: 0, history: getArray(item, 'history') ?? [] };
}

function weighted(rows: DesktopTimelineTask[]): number {
  if (rows.length === 0) { return 0; }
  if (rows.every((row: DesktopTimelineTask): boolean => row.status === 'done')) { return 1; }
  let largest = 1;
  for (const row of rows) { largest = Math.max(largest, row.share); }
  let sum = 0;
  let total = 0;
  for (const row of rows) {
    const weight = row.share / largest;
    sum += row.progress * weight;
    total += weight;
  }
  return total > 0 ? Math.min(0.9999, sum / total) : 0;
}

function groupStatus(rows: DesktopTimelineTask[]): string {
  if (rows.every((row: DesktopTimelineTask): boolean => row.status === 'done')) { return 'done'; }
  for (const status of ['active', 'blocked', 'paused']) {
    if (rows.some((row: DesktopTimelineTask): boolean => row.status === status)) { return status; }
  }
  return 'pending';
}

function parseTree(raw: Object): DesktopTimelineTree | undefined {
  const id = getString(raw, 'id');
  const title = getString(raw, 'title');
  if (!id || !title) { return undefined; }
  const branches = new Map<string, DesktopTimelineTask[]>();
  const seen = new Set<string>();
  for (const rawTask of getArray(raw, 'tasks') ?? []) {
    const task = parseTask(rawTask);
    if (task === undefined || seen.has(task.id)) { continue; }
    seen.add(task.id);
    const siblings = branches.get(task.parent) ?? [];
    siblings.push(task);
    branches.set(task.parent, siblings);
  }
  const tasks: DesktopTimelineTask[] = [];
  const root = branches.get('') ?? [];
  const pending = root.slice().reverse();
  while (pending.length > 0) {
    const task = pending.pop();
    if (task === undefined) { break; }
    tasks.push(task);
    const children = branches.get(task.id) ?? [];
    task.children = children.length;
    for (let i = children.length - 1; i >= 0; i--) {
      const child = children[i];
      child.depth = task.depth + 1;
      if (!child.priority) { child.priority = task.priority; }
      pending.push(child);
    }
  }
  for (let i = tasks.length - 1; i >= 0; i--) {
    const task = tasks[i];
    const children = branches.get(task.id);
    if (children !== undefined && children.length > 0) {
      task.progress = weighted(children);
      task.status = groupStatus(children);
    }
  }
  return { id: id, title: title, description: getString(raw, 'description') ?? '', tasks: tasks, progress: weighted(root) };
}

function readSavedPeriod(report: Object, level: number): number | undefined {
  const encoded = getString(report, 'policy');
  const timing = encoded ? parseJson(encoded) : undefined;
  const container: Record<string, Object> = { 'items': timing ?? '' };
  const items = getArray(container, 'items');
  if (items === undefined || level >= items.length) { return undefined; }
  let value = numeric(items[0]);
  for (let i = 1; i <= level; i++) { value = Math.round(value * numeric(items[i])); }
  return value > 0 && Number.isFinite(value) ? value : undefined;
}

function parseReport(row: Object): DesktopTimelineReport | undefined {
  const id = getString(row, 'id');
  const start = getNumber(row, 'start');
  const end = getNumber(row, 'end');
  const level = getNumber(row, 'level') ?? -1;
  if (!id || start === undefined || end === undefined || start < 0 || end <= start || end > 8640000000000000 ||
    !Number.isInteger(level) || level < 0 || level > 4) { return undefined; }
  const summary = getRecord(row, 'summary');
  return { id: id, start: start, end: end, level: level, savedPeriod: readSavedPeriod(row, level),
    workMs: getNumber(row, 'workMs'), toolCount: getNumber(row, 'toolCount') ?? 0,
    source: getString(row, 'source') ?? 'model', children: texts(getArray(row, 'children')),
    progress: texts(getArray(summary, 'progress')), uncertainties: texts(getArray(summary, 'uncertainties')),
    actions: texts(getArray(summary, 'userActions')) };
}

export function readDesktopTimeline(value?: Object): DesktopTimelineView {
  const trees: DesktopTimelineTree[] = [];
  const reports: DesktopTimelineReport[] = [];
  for (const row of getArray(value, 'trees') ?? []) {
    const tree = parseTree(row);
    if (tree !== undefined) { trees.push(tree); }
  }
  for (const row of getArray(value, 'reports') ?? []) {
    const report = parseReport(row);
    if (report !== undefined) { reports.push(report); }
  }
  reports.sort((left: DesktopTimelineReport, right: DesktopTimelineReport): number => right.end - left.end);
  return { trees: trees, reports: reports, activeTree: getString(value, 'activeTreeId') ?? '',
    error: getString(value, 'error') ?? '', annotations: getArray(value, 'annotations') ?? [] };
}

export function desktopTimelineValue(frame: Object): DesktopTimelineSource | undefined {
  const sequence = getNumber(frame, 'seq');
  if (sequence === undefined || !Number.isSafeInteger(sequence) || sequence < 0) { return undefined; }
  for (const change of getArray(frame, 'changes') ?? []) {
    if (getString(change, 'key') === 'timeline') {
      const value = getRecord(change, 'val');
      return value !== undefined ? { sequence: sequence, value: value } : undefined;
    }
  }
  return undefined;
}
