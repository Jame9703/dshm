import { getArray, getField, getNumber, getRecord, getString, isRecord, parseJson, stringifyJson } from 'connection';
import { readDesktopTimeline } from './DesktopTimelineModel';

export const TIMELINE_CHECKPOINT_BYTES: number = 2 * 1024 * 1024;
const CHECKPOINT_TYPE: string = 'dsh-timeline-tree';
const STATUSES: string[] = ['pending', 'active', 'paused', 'blocked', 'done', 'retired'];
const PRIORITIES: string[] = ['P0', 'P1', 'P2', 'P3'];
const ROOT_FIELDS: string[] = ['format', 'version', 'title', 'description', 'elapsedMs', 'tasks', 'discussions', 'metadata'];
const TASK_FIELDS: string[] = ['id', 'parent', 'title', 'description', 'status', 'done', 'weight', 'note', 'details',
  'priority', 'history'];
const HISTORY_FIELDS: string[] = ['parent', 'title', 'description', 'status', 'done', 'note', 'details', 'priority',
  'at', 'progress', 'previousProgress', 'weight'];

export interface DesktopTimelineCheckpointPreview {
  title: string;
  tasks: number;
  progress: number;
}

interface TimelineCheckpointTask {
  id: string;
  parent: string;
  title: string;
  status: string;
  done: number[];
  weight: number;
  hasState: boolean;
}

function exact(value: Object, fields: string[]): boolean {
  return isRecord(value) && Object.keys(value).every((key: string): boolean => fields.includes(key));
}

function label(value: Object | undefined, max: number, empty: boolean = false): boolean {
  if (typeof value !== 'string') { return false; }
  const text = empty ? value : value.trim();
  return text.length <= max && (empty || text.length > 0);
}

function boundedNumber(value: Object | undefined, low: number, high: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= low && value <= high;
}

function textField(value: Object, key: string, max: number, optional: boolean = true): boolean {
  const field = getField(value, key);
  return (field === undefined && optional) || label(field, max, true);
}

function priority(value?: Object): boolean {
  return value === undefined || value === null || (typeof value === 'string' && PRIORITIES.includes(value));
}

function parent(value?: Object): boolean { return value === null || label(value, 80); }

function pair(value: Object, key: string): number[] | undefined {
  const pair = getArray(value, key);
  if (pair === undefined || pair.length !== 2 || !boundedNumber(pair[0], 0, Number.MAX_VALUE) ||
    !boundedNumber(pair[1], Number.MIN_VALUE, Number.MAX_VALUE)) { return undefined; }
  return [Number(pair[0]), Number(pair[1])];
}

function timestamp(value?: Object): boolean { return boundedNumber(value, 0, 8640000000000000); }

function history(value: Object): boolean {
  const prior = getField(value, 'previousProgress');
  return exact(value, HISTORY_FIELDS) && parent(getField(value, 'parent')) &&
    label(getField(value, 'title'), 120) && textField(value, 'description', 320, false) &&
    STATUSES.includes(getString(value, 'status') ?? '') && pair(value, 'done') !== undefined &&
    textField(value, 'note', 400, false) && textField(value, 'details', 4000, false) &&
    priority(getField(value, 'priority')) && timestamp(getField(value, 'at')) &&
    boundedNumber(getField(value, 'progress'), 0, 1) && (prior === null || boundedNumber(prior, 0, 1)) &&
    boundedNumber(getField(value, 'weight'), Number.MIN_VALUE, Number.MAX_VALUE);
}

function parseTask(value: Object): TimelineCheckpointTask | undefined {
  const title = (getString(value, 'title') ?? '').trim();
  const id = (getString(value, 'id') ?? '').trim();
  const parentValue = getField(value, 'parent');
  const statusValue = getField(value, 'status');
  const declared = getString(value, 'status');
  const doneValue = getField(value, 'done');
  const done = pair(value, 'done') ?? [0, 1];
  const weight = getField(value, 'weight');
  const trail = getField(value, 'history');
  const entries = getArray(value, 'history');
  if (!exact(value, TASK_FIELDS) || !label(id, 80) || !label(title, 120) ||
    (parentValue !== undefined && !parent(parentValue)) ||
    (statusValue !== undefined && (declared === undefined || !STATUSES.includes(declared))) ||
    (doneValue !== undefined && pair(value, 'done') === undefined) || done[0] > done[1] ||
    (weight !== undefined && !boundedNumber(weight, Number.MIN_VALUE, Number.MAX_VALUE)) ||
    !textField(value, 'description', 320) || !textField(value, 'note', 400) || !textField(value, 'details', 4000) ||
    !priority(getField(value, 'priority')) ||
    (trail !== undefined && (entries === undefined || !entries.every(history)))) { return undefined; }
  const status = declared ?? (done[0] === done[1] ? 'done' : done[0] > 0 ? 'active' : 'pending');
  if (status === 'pending' && done[0] > 0) { return undefined; }
  return { id: id, parent: (getString(value, 'parent') ?? '').trim(), title: title, status: status, done: done,
    weight: getNumber(value, 'weight') ?? 1, hasState: doneValue !== undefined || statusValue !== undefined };
}

function discussion(value: Object, tasks: Map<string, TimelineCheckpointTask>): boolean {
  const task = getField(value, 'task');
  const time = getField(value, 'createdAt');
  const replyValue = getField(value, 'reply');
  const reply = getRecord(value, 'reply');
  if (!exact(value, ['task', 'text', 'createdAt', 'reply']) || !label(getField(value, 'text'), 4000) ||
    (task !== undefined && (typeof task !== 'string' || !tasks.has(task.trim()))) ||
    (time !== undefined && !timestamp(time))) { return false; }
  if (replyValue === undefined) { return true; }
  if (reply === undefined || !exact(reply, ['text', 'createdAt']) || !label(getField(reply, 'text'), 4000)) { return false; }
  const replyTime = getField(reply, 'createdAt');
  return replyTime === undefined || timestamp(replyTime);
}

function validGraph(tasks: Map<string, TimelineCheckpointTask>, values: TimelineCheckpointTask[]): boolean {
  const checked = new Set<string>();
  for (const task of values) {
    const local = new Set<string>();
    let current: TimelineCheckpointTask | undefined = task;
    while (current !== undefined && !checked.has(current.id)) {
      if (local.has(current.id)) { return false; }
      local.add(current.id);
      const other: TimelineCheckpointTask | undefined = current.parent ? tasks.get(current.parent) : undefined;
      if (current.parent && (other === undefined ||
        (current.status !== 'retired' && (other.status === 'retired' || other.hasState)))) { return false; }
      current = other;
    }
    for (const id of local) { checked.add(id); }
  }
  return true;
}

export function previewDesktopTimelineCheckpoint(content: string): DesktopTimelineCheckpointPreview | undefined {
  const raw = parseJson(content);
  if (raw === undefined || !exact(raw, ROOT_FIELDS) || getString(raw, 'format') !== CHECKPOINT_TYPE ||
    getNumber(raw, 'version') !== 1) { return undefined; }
  const title = (getString(raw, 'title') ?? '').trim();
  const elapsed = getField(raw, 'elapsedMs');
  const rawTasks = getArray(raw, 'tasks');
  const notes = getArray(raw, 'discussions');
  if (!label(title, 120) || !textField(raw, 'description', 320) ||
    (elapsed !== undefined && !boundedNumber(elapsed, 0, Number.MAX_SAFE_INTEGER)) ||
    (getField(raw, 'metadata') !== undefined && !isRecord(getField(raw, 'metadata'))) ||
    rawTasks === undefined || rawTasks.length > 1000 ||
    (getField(raw, 'discussions') !== undefined && (notes === undefined || notes.length > 10000))) { return undefined; }
  const registry = new Map<string, TimelineCheckpointTask>();
  const tasks: TimelineCheckpointTask[] = [];
  for (const row of rawTasks) {
    const task = parseTask(row);
    if (task === undefined || registry.has(task.id)) { return undefined; }
    tasks.push(task);
    registry.set(task.id, task);
  }
  if (!validGraph(registry, tasks) || !(notes ?? []).every((note: Object): boolean => discussion(note, registry))) {
    return undefined;
  }
  const measure: Record<string, Object> = { 'id': 'preview', 'title': title,
    'tasks': tasks.map((task: TimelineCheckpointTask): Object => {
      const row: Record<string, Object> = { 'id': task.id, 'title': task.title, 'parent': task.parent,
        'status': task.status, 'done': task.done, 'timeShare': task.weight };
      return row;
    }) };
  const preview: Record<string, Object> = { 'trees': [measure] };
  return { title: title, tasks: tasks.length, progress: readDesktopTimeline(preview).trees[0]?.progress ?? 0 };
}

function addText(result: Record<string, Object>, row: Object, key: string): void {
  const value = getString(row, key);
  if (value) { result[key] = value; }
}

function checkpointTask(row: Object, parents: Set<string>): Object {
  const id = getString(row, 'id') ?? '';
  const result: Record<string, Object> = { 'id': id, 'title': getString(row, 'title') ?? '' };
  addText(result, row, 'parent');
  addText(result, row, 'description');
  if (!parents.has(id)) {
    const status = getString(row, 'status') ?? '';
    if (status !== 'pending' && status) { result['status'] = status; }
    const done = getArray(row, 'done');
    if (done !== undefined && (done[0] !== 0 || done[1] !== 1)) { result['done'] = done; }
  }
  const weight = getNumber(row, 'timeShare') ?? 1;
  if (weight !== 1) { result['weight'] = weight; }
  addText(result, row, 'note');
  addText(result, row, 'details');
  addText(result, row, 'priority');
  const changes = getArray(row, 'history');
  if (changes !== undefined && changes.length > 0) { result['history'] = changes; }
  return result;
}

export function desktopTimelineCheckpoint(tree: Object, annotations: Object[], sessionId: string,
  now: number): string | undefined {
  const treeId = getString(tree, 'id');
  if (!treeId) { return undefined; }
  const raw = getArray(tree, 'tasks') ?? [];
  const parents = new Set<string>();
  const begin = getNumber(tree, 'createdAt') ?? now;
  let last = begin;
  let completed = true;
  for (const row of raw) {
    const status = getString(row, 'status');
    if (status !== 'retired') {
      parents.add(getString(row, 'parent') ?? '');
      if (status !== 'done') { completed = false; }
    }
    last = Math.max(last, getNumber(row, 'updatedAt') ?? begin);
  }
  const result: Record<string, Object> = {
    'format': CHECKPOINT_TYPE, 'version': 1, 'title': getString(tree, 'title') ?? '',
    'tasks': raw.map((row: Object): Object => checkpointTask(row, parents))
  };
  addText(result, tree, 'description');
  const elapsed = Math.max(0, (completed ? last : now) - begin);
  if (elapsed > 0) { result['elapsedMs'] = elapsed; }
  const discussions: Object[] = [];
  for (const row of annotations) {
    const target = getRecord(row, 'target');
    const kind = getString(target, 'kind');
    if (getRecord(row, 'control') !== undefined || getString(target, 'tree') !== treeId ||
      (kind !== 'task' && kind !== 'tree')) { continue; }
    const note: Record<string, Object> = { 'text': getString(row, 'text') ?? '' };
    if (kind === 'task') { note['task'] = getString(target, 'task') ?? ''; }
    const created = getNumber(row, 'createdAt');
    if (created !== undefined) { note['createdAt'] = created; }
    const reply = getRecord(row, 'reply');
    if (reply !== undefined) { note['reply'] = reply; }
    discussions.push(note);
  }
  if (discussions.length > 0) { result['discussions'] = discussions; }
  const metadata: Record<string, Object> = { 'plugin': '@deepseek-ai/dsh-timeline', 'exportedAt': new Date(now).toISOString(),
    'sourceSessionId': sessionId, 'sourceTreeId': treeId, 'treeCreatedAt': new Date(begin).toISOString(),
    'lastTaskUpdatedAt': new Date(last).toISOString() };
  result['metadata'] = metadata;
  try {
    return JSON.stringify(result, null, 2) + '\n';
  } catch (_) {
    return stringifyJson(result);
  }
}

export function desktopTimelineCheckpointName(title: string): string {
  const safe = title.trim().replace(/[<>:"/\\|?*\u0000-\u001f]/g, '-').slice(0, 80);
  return (safe || 'timeline') + '.timeline.json';
}
