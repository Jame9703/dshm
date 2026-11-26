import { DiffLine, DiffLineKind, diffLines } from 'appstate';
import { getArray, getBoolean, getField, getNumber, getRecord, getString, isStringArray, parseJson, toStringArray } from 'connection';

export interface DesktopDeliveredFile {
  id: string;
  sequence: number;
  index: number;
  path: string;
  name: string;
  description: string;
}

export interface DesktopTurnArtifacts {
  turn: number;
  closeSequence: number;
  changeSequence: number;
  files: DesktopDeliveredFile[];
  applied: DesktopAppliedEdit[];
  writes: Map<string, string>;
}

interface DesktopAppliedEdit {
  sequence: number;
  path: string;
  before: string | null;
  after?: string;
  created: boolean;
  callId?: string;
}

export interface DesktopChangedFile {
  path: string;
  display: string;
  added: number;
  deleted: number;
  binary: boolean;
  oversized: boolean;
  edits?: DesktopAppliedEdit[];
}

export interface DesktopChangeSummary {
  turn: number;
  cwd: string;
  total: number;
  added: number;
  deleted: number;
  files: DesktopChangedFile[];
  applied?: boolean;
}

export interface DesktopChangeTarget {
  sessionId: string;
  sequence: number;
  summary: DesktopChangeSummary;
  index: number;
  split?: boolean;
  wrap?: boolean;
}

export interface DesktopDiffCell {
  number: number;
  text: string;
  kind: string;
}

export interface DesktopDiffRow {
  id: number;
  title: string;
  left?: DesktopDiffCell;
  right?: DesktopDiffCell;
}

export interface DesktopDiff {
  rows: DesktopDiffRow[];
  splitRows: DesktopDiffRow[];
  allowSplit: boolean;
  notice: string;
  showNumbers: boolean;
}

function count(value: Object | undefined, key: string, min: number = 0): number {
  const number = getNumber(value, key) ?? -1;
  return Number.isSafeInteger(number) && number >= min ? number : -1;
}

export function desktopFileName(path: string): string {
  return path.substring(Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\')) + 1);
}

export function desktopChangedPath(cwd: string, path: string): string {
  if (path.startsWith('/') || path.startsWith('\\') || new RegExp('^[A-Za-z]:[/\\\\]').test(path) || !cwd) {
    return path;
  }
  return cwd.endsWith('/') || cwd.endsWith('\\') ? cwd + path : cwd + '/' + path;
}

export function observeDesktopArtifacts(events: Map<number, DesktopTurnArtifacts>, event?: Object): void {
  const type = getString(event, 'type');
  if (type !== 'deliverables/presented' && type !== 'workspace/changes' && type !== 'turn/end' &&
    type !== 'tool/result' && type !== 'tool/call') {
    return;
  }
  const body = getRecord(event, 'data');
  const turn = count(body, 'turn', 1);
  const sequence = count(event, 'seq');
  if (turn < 1 || sequence < 0) {
    return;
  }
  const row: DesktopTurnArtifacts = events.get(turn) ?? {
    turn: turn, closeSequence: -1, changeSequence: -1, files: [], applied: [], writes: new Map<string, string>()
  };
  if (type === 'turn/end') {
    row.closeSequence = Math.max(sequence, row.closeSequence);
  } else if (type === 'workspace/changes') {
    row.changeSequence = Math.max(sequence, row.changeSequence);
  } else if (type === 'tool/call') {
    const callId = getString(body, 'callId') ?? '';
    if (getString(body, 'name') === 'write' && callId) {
      const content = getString(parseJson(getString(body, 'arguments') ?? ''), 'content');
      if (content !== undefined) {
        row.writes.set(callId, content);
      }
    }
  } else if (type === 'tool/result') {
    const message = getRecord(body, 'message');
    const meta = getRecord(body, 'meta');
    const path = getString(meta, 'path');
    if (message !== undefined && getBoolean(message, 'isError') !== true && path &&
      !row.applied.some((edit: DesktopAppliedEdit): boolean => edit.sequence === sequence)) {
      const created = getString(meta, 'operation') === 'create';
      const changes = getArray(meta, 'diffs') ?? [];
      if (created && changes.length === 0) {
        row.applied.push({ sequence: sequence, path: path, before: null, created: true,
          callId: getString(getRecord(message, 'source'), 'callId') });
      }
      for (const change of changes) {
        const before = getString(change, 'oldText');
        const after = getString(change, 'newText');
        if (after !== undefined && (before !== undefined || getField(change, 'oldText') === null) && before !== after) {
          row.applied.push({ sequence: sequence, path: path, before: before ?? null, after: after, created: created });
        }
      }
    }
  } else if ((getString(body, 'callId') ?? '').length > 0 &&
    !row.files.some((file: DesktopDeliveredFile): boolean => file.sequence === sequence)) {
    const files = getArray(body, 'files') ?? [];
    files.forEach((file: Object, index: number): void => {
      const path = getString(file, 'path') ?? '';
      if (path.trim().length > 0) {
        row.files.push({ id: `${sequence}:${index}`, sequence: sequence, index: index, path: path,
          name: desktopFileName(path) || path, description: getString(file, 'description') ?? '' });
      }
    });
    row.files.sort((a: DesktopDeliveredFile, b: DesktopDeliveredFile): number =>
      a.sequence - b.sequence || a.index - b.index);
  }
  events.set(turn, row);
}

export function desktopAppliedSummary(artifacts: DesktopTurnArtifacts): DesktopChangeSummary {
  const files: Map<string, DesktopChangedFile> = new Map();
  const ordered = artifacts.applied.slice().sort((a: DesktopAppliedEdit, b: DesktopAppliedEdit): number =>
    a.sequence - b.sequence);
  for (const edit of ordered) {
    const applied: DesktopAppliedEdit = { sequence: edit.sequence, path: edit.path, before: edit.before,
      after: edit.after ?? artifacts.writes.get(edit.callId ?? ''), created: edit.created };
    const previous = files.get(edit.path);
    if (previous === undefined) {
      files.set(edit.path, { path: edit.path, display: desktopFileName(edit.path) || edit.path,
        added: 0, deleted: 0, binary: false, oversized: false, edits: [applied] });
    } else {
      previous.edits?.push(applied);
    }
  }
  return { turn: artifacts.turn, cwd: '', total: files.size, added: 0, deleted: 0,
    files: Array.from(files.values()), applied: true };
}

export function desktopAppliedDiff(file: DesktopChangedFile): DesktopDiff {
  const hunks: Object[] = [];
  for (const edit of file.edits ?? []) {
    if (edit.after === undefined) {
      continue;
    }
    const before = edit.before?.replace(new RegExp('\\n$'), '') ?? null;
    const after = edit.after.replace(new RegExp('\\n$'), '');
    const lines = diffLines(before, after).map((line: DiffLine): string =>
      (line.kind === DiffLineKind.ADDED ? '+' : line.kind === DiffLineKind.REMOVED ? '-' : ' ') + line.text);
    const hunk: Record<string, Object> = { 'oldStart': 0, 'newStart': 0, 'oldLines': 0, 'newLines': 0, 'lines': lines };
    hunks.push(hunk);
  }
  const payload: Record<string, Object> = {
    'kind': 'text', 'before': file.edits?.[0]?.created !== true, 'after': true, 'hunks': hunks, 'coarse': false
  };
  return desktopFileDiff(payload, false) ?? { rows: [], splitRows: [], allowSplit: false, notice: '', showNumbers: false };
}

export function desktopChangeSummary(value?: Object): DesktopChangeSummary | undefined {
  const turn = count(value, 'turn', 1);
  const total = count(value, 'total');
  const added = count(value, 'added');
  const deleted = count(value, 'deleted');
  const cwd = getString(value, 'cwd');
  const raw = getArray(value, 'files');
  if (turn < 1 || total < 0 || added < 0 || deleted < 0 || cwd === undefined || raw === undefined) {
    return undefined;
  }
  const files: DesktopChangedFile[] = [];
  for (const entry of raw) {
    const path = getString(entry, 'path') ?? '';
    const display = getString(entry, 'display') ?? '';
    const plus = count(entry, 'added');
    const minus = count(entry, 'deleted');
    if (!path || !display || plus < 0 || minus < 0) {
      return undefined;
    }
    files.push({ path: path, display: display, added: plus, deleted: minus,
      binary: getBoolean(entry, 'binary') === true, oversized: getBoolean(entry, 'oversized') === true });
  }
  return { turn: turn, cwd: cwd, total: total, added: added, deleted: deleted, files: files };
}

function appendSplitChanges(rows: DesktopDiffRow[], removed: DesktopDiffCell[], added: DesktopDiffCell[]): void {
  for (let i = 0; i < Math.max(removed.length, added.length); i++) {
    rows.push({ id: rows.length, title: '', left: removed[i], right: added[i] });
  }
  removed.length = 0;
  added.length = 0;
}

export function desktopFileDiff(value?: Object, showNumbers: boolean = true): DesktopDiff | undefined {
  const kind = getString(value, 'kind');
  const rows: DesktopDiffRow[] = [];
  const split: DesktopDiffRow[] = [];
  if (kind === 'binary' || kind === 'oversized') {
    return { rows: rows, splitRows: split, allowSplit: false, showNumbers: showNumbers,
      notice: kind === 'binary' ? '二进制文件，无法显示改动' : '文件过大，无法显示改动' };
  }
  const hunks = getArray(value, 'hunks');
  const before = getBoolean(value, 'before');
  const after = getBoolean(value, 'after');
  const coarse = getBoolean(value, 'coarse');
  if (kind !== 'text' || hunks === undefined || before === undefined || after === undefined || coarse === undefined) {
    return undefined;
  }
  let hasAdditions = false;
  let hasDeletions = false;
  for (const hunk of hunks) {
    let oldNumber = count(hunk, 'oldStart');
    let newNumber = count(hunk, 'newStart');
    const oldLines = count(hunk, 'oldLines');
    const newLines = count(hunk, 'newLines');
    const raw = getArray(hunk, 'lines');
    if (oldNumber < 0 || newNumber < 0 || oldLines < 0 || newLines < 0 || raw === undefined || !isStringArray(raw)) {
      return undefined;
    }
    const title = showNumbers ? `@@ -${oldNumber},${oldLines} +${newNumber},${newLines} @@` : '工具记录的改动片段';
    rows.push({ id: rows.length, title: title });
    split.push({ id: split.length, title: title });
    const removed: DesktopDiffCell[] = [];
    const added: DesktopDiffCell[] = [];
    for (const line of toStringArray(raw)) {
      const marker = line.charAt(0);
      const text = line.substring(1);
      if (marker === '-') {
        const cell: DesktopDiffCell = { number: oldNumber++, text: text, kind: '-' };
        rows.push({ id: rows.length, title: '', left: cell });
        removed.push(cell);
        hasDeletions = true;
      } else if (marker === '+') {
        const cell: DesktopDiffCell = { number: newNumber++, text: text, kind: '+' };
        rows.push({ id: rows.length, title: '', right: cell });
        added.push(cell);
        hasAdditions = true;
      } else if (marker === ' ') {
        appendSplitChanges(split, removed, added);
        const left: DesktopDiffCell = { number: oldNumber++, text: text, kind: ' ' };
        const right: DesktopDiffCell = { number: newNumber++, text: text, kind: ' ' };
        rows.push({ id: rows.length, title: '', left: left, right: right });
        split.push({ id: split.length, title: '', left: left, right: right });
      } else {
        return undefined;
      }
    }
    appendSplitChanges(split, removed, added);
  }
  const notice = coarse ? '逐行对比超时，按整个文件替换显示' :
    (!before ? '本轮新建的文件' : !after ? '本轮删除的文件' : (rows.length === 0 ? '两侧内容相同' : ''));
  return { rows: rows, splitRows: split, allowSplit: hasAdditions && hasDeletions, notice: notice, showNumbers: showNumbers };
}
