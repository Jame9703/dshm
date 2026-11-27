import { getArray, getRecord, getString } from 'connection';

export const TIMELINE_DISCUSSION_LIMIT: number = 4000;
export const TIMELINE_PRIORITIES: string[] = ['P0', 'P1', 'P2', 'P3'];

export interface DesktopTimelineDiscussionTarget {
  kind: string;
  tree: string;
  id: string;
}

export interface DesktopTimelineNoticeLabels {
  header: string;
  report: string;
  task: string;
  tree: string;
  progress: string;
  uncertainties: string;
  actions: string;
  reference: string;
  instructions: string;
  message: string;
}

export function desktopTimelineDiscussionKey(target: DesktopTimelineDiscussionTarget): string {
  return JSON.stringify([target.kind, target.tree, target.id]);
}

export function desktopTimelineDiscussionPayload(target: DesktopTimelineDiscussionTarget): Record<string, Object> {
  if (target.kind === 'report') { return { 'kind': 'report', 'report': target.id }; }
  if (target.kind === 'task') { return { 'kind': 'task', 'tree': target.tree, 'task': target.id }; }
  return { 'kind': 'tree', 'tree': target.tree };
}

export function desktopTimelineOwnAnnotation(annotation: Object | undefined, id: string,
  target: DesktopTimelineDiscussionTarget, message: string): boolean {
  const saved = getRecord(annotation, 'target');
  return getString(annotation, 'id') === id && getString(annotation, 'text') === message &&
    getString(saved, 'kind') === target.kind && (target.kind === 'report' ? getString(saved, 'report') === target.id :
      getString(saved, 'tree') === target.tree && (target.kind !== 'task' || getString(saved, 'task') === target.id));
}

function values(value: Object | undefined, field: string): string {
  return (getArray(value, field) ?? []).filter((item: Object): boolean => typeof item === 'string')
    .map((item: Object): string => String(item)).join(' ');
}

function titled(title: string | undefined, fallback: string): string {
  return title ? title + ' (' + fallback + ')' : fallback;
}

export function desktopTimelineDiscussionNotice(target: DesktopTimelineDiscussionTarget, id: string, message: string,
  context: Object | undefined, labels: DesktopTimelineNoticeLabels, control: boolean = false): string {
  const lines: string[] = [labels.header, ''];
  if (target.kind === 'report') {
    const start = getString(context, 'start');
    const end = getString(context, 'end');
    lines.push(labels.report + ' ' + (start && end ? start + ' – ' + end + ' (' + target.id + ')' : target.id));
    const summary = getRecord(context, 'summary');
    const progress = values(summary, 'progress');
    const uncertainties = values(summary, 'uncertainties');
    const actions = values(summary, 'userActions');
    if (progress) { lines.push(labels.progress + ' ' + progress); }
    if (uncertainties) { lines.push(labels.uncertainties + ' ' + uncertainties); }
    if (actions) { lines.push(labels.actions + ' ' + actions); }
  } else {
    if (target.kind === 'task') { lines.push(labels.task + ' ' + titled(getString(context, 'taskTitle'), target.id)); }
    lines.push(labels.tree + ' ' + titled(getString(context, 'treeTitle'), target.tree));
    const note = getString(context, 'note') || getString(context, 'description') || '';
    if (note) { lines.push(note.length > 200 ? note.slice(0, 200) + '…' : note); }
  }
  lines.push(labels.reference + ' ' + id, '');
  if (control) { lines.push(message, labels.instructions); }
  else { lines.push(labels.instructions, '', labels.message, message); }
  return lines.join('\n');
}
