import { getField, getNumber, getRecord, getString } from 'connection';
import type { DesktopTimelineDiscussionTarget } from './DesktopTimelineActions';
import type { DesktopTimelineTask, DesktopTimelineTree } from './DesktopTimelineModel';

export const DESKTOP_TIMELINE_CONTROL_WAIT_MS: number = 120000;

export interface DesktopTimelinePlayback {
  available: boolean;
  complete: boolean;
  waiting: boolean;
  retry: boolean;
  intent: string;
  receipt?: Object;
}

interface ControlAddress {
  kind: string;
  tree: string;
  task: string;
}

function controlAddress(annotation: Object): ControlAddress | undefined {
  const target = getRecord(annotation, 'target');
  const kind = getString(target, 'kind');
  const tree = getString(target, 'tree');
  const task = getString(target, 'task') ?? '';
  return tree && (kind === 'tree' || (kind === 'task' && !!task)) ?
    { kind: kind, tree: tree, task: task } : undefined;
}

function descends(parents: Map<string, string>, child: string, ancestor: string): boolean {
  const seen = new Set<string>();
  while (child && !seen.has(child)) {
    if (child === ancestor) { return true; }
    seen.add(child);
    child = parents.get(child) ?? '';
  }
  return false;
}

export function desktopTimelinePlayback(tree: DesktopTimelineTree | undefined, target: DesktopTimelineDiscussionTarget,
  annotations: Object[], now: number): DesktopTimelinePlayback {
  const task = target.kind === 'task' && tree !== undefined ?
    tree.tasks.find((row: DesktopTimelineTask): boolean => row.id === target.id) : undefined;
  const state = target.kind === 'task' ? task?.status : tree?.status;
  const complete = state === 'done';
  const available = !complete && state !== undefined && state !== 'retired' && (tree?.tasks.length ?? 0) > 0;
  const parents = new Map<string, string>();
  let latest: Object | undefined = undefined;
  let pending: Object | undefined = undefined;
  for (let i = annotations.length - 1; i >= 0; i--) {
    const annotation = annotations[i];
    const control = getRecord(annotation, 'control');
    const address = control === undefined ? undefined : controlAddress(annotation);
    if (address === undefined || address.tree !== target.tree) { continue; }
    if (latest === undefined && address.kind === target.kind &&
      (target.kind === 'tree' || address.task === target.id)) {
      latest = annotation;
    }
    if (getField(control, 'outcome') !== null ||
      now - (getNumber(annotation, 'createdAt') ?? 0) >= DESKTOP_TIMELINE_CONTROL_WAIT_MS) { continue; }
    if (address.kind === 'tree' || target.kind === 'tree') {
      pending = annotation;
      break;
    }
    if (parents.size === 0) {
      for (const row of tree?.tasks ?? []) { parents.set(row.id, row.parent); }
    }
    if (descends(parents, target.id, address.task) || descends(parents, address.task, target.id)) {
      pending = annotation;
      break;
    }
  }
  const receipt = pending ?? latest;
  const control = getRecord(receipt, 'control');
  const waiting = pending !== undefined;
  const retry = !waiting && (getField(control, 'outcome') === null ||
    getString(getRecord(control, 'outcome'), 'status') === 'answered');
  const prior = getString(control, 'action');
  const intent = (waiting || retry) && (prior === 'pause' || prior === 'resume') ?
    prior : state === 'active' ? 'pause' : 'resume';
  return { available: available, complete: complete, waiting: waiting, retry: retry, intent: intent, receipt: receipt };
}

export function desktopTimelineControlDeadline(annotations: Object[], now: number): number {
  let nearest = Infinity;
  for (const annotation of annotations) {
    if (getField(getRecord(annotation, 'control'), 'outcome') !== null) { continue; }
    const until = (getNumber(annotation, 'createdAt') ?? 0) + DESKTOP_TIMELINE_CONTROL_WAIT_MS;
    if (until > now) { nearest = Math.min(nearest, until); }
  }
  return nearest;
}
