import { getArray, getNumber, getRecord, getString, parseJson } from 'connection';

export interface DesktopTimelineLocation {
  session: string;
  tree: string;
  task: string;
  revision: number;
}

export interface DesktopTimelineSource {
  sequence: number;
  value: Object;
}

export interface DesktopTimelineProgressPart {
  fraction: number;
  leaves: number;
  titles: string[];
}

export interface DesktopTimelineParts {
  done: DesktopTimelineProgressPart;
  active: DesktopTimelineProgressPart;
  pending: DesktopTimelineProgressPart;
  blocked: DesktopTimelineProgressPart;
}

interface DesktopTimelineMeasure {
  progress: number;
  status: string;
  parts: DesktopTimelineParts;
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
  ownPriority: string;
  share: number;
  unitsDone: number;
  unitsTotal: number;
  progress: number;
  parts: DesktopTimelineParts;
  depth: number;
  children: number;
  history: Object[];
}

export interface DesktopTimelineTree {
  id: string;
  raw: Object;
  title: string;
  description: string;
  tasks: DesktopTimelineTask[];
  createdAt: number;
  latestActivityAt: number;
  status: string;
  progress: number;
  parts?: DesktopTimelineParts;
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

export function desktopTimelineStatus(value: string): Resource {
  switch (value) {
    case 'active': return $r('app.string.desktop_timeline_active');
    case 'done': return $r('app.string.desktop_timeline_done');
    case 'blocked': return $r('app.string.desktop_timeline_blocked');
    case 'paused': return $r('app.string.desktop_timeline_paused');
    case 'retired': return $r('app.string.desktop_timeline_retired');
    default: return $r('app.string.desktop_timeline_pending');
  }
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
  const unitsDone = numeric(done[0]);
  const unitsTotal = numeric(done[1]);
  const progress = status === 'done' ? 1 : unitsTotal > 0 ? Math.max(0, Math.min(1, unitsDone / unitsTotal)) : 0;
  const share = getNumber(item, 'timeShare') ?? 1;
  return { id: id, title: title, status: status, parent: getString(item, 'parent') ?? '',
    description: getString(item, 'description') ?? '', note: getString(item, 'note') ?? '',
    details: getString(item, 'details') ?? '', priority: getString(item, 'priority') ?? '',
    ownPriority: getString(item, 'priority') ?? '',
    share: Number.isFinite(share) && share > 0 ? share : 1, unitsDone: unitsDone, unitsTotal: unitsTotal,
    progress: progress, parts: leafParts(progress, status, title),
    depth: 0, children: 0, history: getArray(item, 'history') ?? [] };
}

function emptyPart(): DesktopTimelineProgressPart { return { fraction: 0, leaves: 0, titles: [] }; }

function emptyParts(): DesktopTimelineParts {
  return { done: emptyPart(), active: emptyPart(), pending: emptyPart(), blocked: emptyPart() };
}

function unfinishedPart(parts: DesktopTimelineParts, status: string): DesktopTimelineProgressPart {
  return status === 'active' ? parts.active : status === 'blocked' ? parts.blocked : parts.pending;
}

function leafParts(progress: number, status: string, title: string): DesktopTimelineParts {
  const parts = emptyParts();
  parts.done.fraction = progress;
  const unfinished = unfinishedPart(parts, status);
  unfinished.fraction = 1 - progress;
  const bucket = status === 'done' ? parts.done : unfinished;
  bucket.leaves = 1;
  bucket.titles.push(title);
  return parts;
}

function accumulatePart(target: DesktopTimelineProgressPart, child: DesktopTimelineProgressPart, weight: number): void {
  target.fraction += weight * child.fraction;
  target.leaves += child.leaves;
  for (const title of child.titles) {
    if (target.titles.length >= 6) { break; }
    target.titles.push(title);
  }
}

function measureGroup(rows: DesktopTimelineTask[]): DesktopTimelineMeasure {
  let largest = 0;
  for (const row of rows) { largest = Math.max(largest, row.share); }
  const parts = emptyParts();
  let sum = 0;
  let total = 0;
  let done = true;
  let active = false;
  let blocked = false;
  let paused = false;
  for (const row of rows) {
    const weight = row.share / largest;
    sum += row.progress * weight;
    total += weight;
    done = done && row.status === 'done';
    active = active || row.status === 'active';
    blocked = blocked || row.status === 'blocked';
    paused = paused || row.status === 'paused';
    accumulatePart(parts.done, row.parts.done, weight);
    accumulatePart(parts.active, row.parts.active, weight);
    accumulatePart(parts.pending, row.parts.pending, weight);
    accumulatePart(parts.blocked, row.parts.blocked, weight);
  }
  const status = done ? 'done' : active ? 'active' : blocked ? 'blocked' : paused ? 'paused' : 'pending';
  const progress = done ? 1 : Math.min(0.9999, sum / total);
  const rest = parts.active.fraction + parts.pending.fraction + parts.blocked.fraction;
  const scale = rest > 0 ? (1 - progress) / rest : 0;
  parts.done.fraction = progress;
  parts.active.fraction *= scale;
  parts.pending.fraction *= scale;
  parts.blocked.fraction *= scale;
  if (rest === 0) { unfinishedPart(parts, status).fraction = 1 - progress; }
  return { progress: progress, status: status, parts: parts };
}

function parseTree(raw: Object): DesktopTimelineTree | undefined {
  const id = getString(raw, 'id');
  const title = getString(raw, 'title');
  if (!id || !title) { return undefined; }
  const branches = new Map<string, DesktopTimelineTask[]>();
  const seen = new Set<string>();
  const createdAt = numeric(getNumber(raw, 'createdAt'));
  let latestActivityAt = createdAt;
  for (const rawTask of getArray(raw, 'tasks') ?? []) {
    latestActivityAt = Math.max(latestActivityAt, numeric(getNumber(rawTask, 'updatedAt')));
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
      const group = measureGroup(children);
      task.progress = group.progress;
      task.status = group.status;
      task.parts = group.parts;
    }
  }
  const measure = root.length > 0 ? measureGroup(root) : undefined;
  return { id: id, raw: raw, title: title, description: getString(raw, 'description') ?? '', tasks: tasks,
    createdAt: createdAt, latestActivityAt: latestActivityAt, status: measure?.status ?? 'pending',
    progress: measure?.progress ?? 0, parts: measure?.parts };
}

export function readDesktopTimelineActiveTree(value?: Object): DesktopTimelineTree | undefined {
  const active = getString(value, 'activeTreeId');
  if (!active) { return undefined; }
  const tree = getArray(value, 'trees')?.find((row: Object): boolean => getString(row, 'id') === active);
  return tree === undefined ? undefined : parseTree(tree);
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
