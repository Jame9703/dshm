import type { TerminalPaintFrame, TerminalSelectionBuffer, TerminalSelectionLine, TerminalSelectionMarker }
  from './terminal/TerminalEmulator';

export interface DesktopTerminalSelectionSpan {
  row: number;
  start: number;
  end: number;
}

interface TerminalHit {
  line: number;
  start: number;
  end: number;
  text: string;
}

interface TerminalSelectionPoint {
  marker: TerminalSelectionMarker;
  start: number;
  end: number;
}

interface TerminalSelectionRange {
  first: number;
  start: number;
  last: number;
  end: number;
}

interface TerminalSelectionUnit {
  first: TerminalHit;
  last: TerminalHit;
}

enum TerminalSelectionMode {
  CELL,
  WORD,
  LINE
}

const WORD_SEPARATORS: string = ' ()[]{}\',"' + String.fromCharCode(96);
const NONBREAKING_SPACE: RegExp = new RegExp('\u00a0', 'g');

function hitAt(buffer: TerminalSelectionBuffer, row: number, column: number): TerminalHit | undefined {
  const line = buffer.lineAt(row);
  if (line === undefined || column < 0 || column >= buffer.columns) { return undefined; }
  let start = column;
  let cell = line.cellAt(start);
  while (cell?.width === 0 && start > 0) { cell = line.cellAt(--start); }
  if (cell === undefined) { return undefined; }
  return { line: row, start: start, end: Math.min(buffer.columns, start + Math.max(cell.width, 1)), text: cell.text };
}

function visibleHit(frame: TerminalPaintFrame, column: number, row: number): TerminalHit | undefined {
  const buffer = frame.selection;
  if (!Number.isFinite(column) || !Number.isFinite(row) ||
      frame.rows.length === 0 || buffer.columns <= 0) { return undefined; }
  const x = Math.max(0, Math.min(buffer.columns - 1, Math.floor(column)));
  const y = Math.max(0, Math.min(frame.rows.length - 1, Math.floor(row)));
  return hitAt(buffer, buffer.viewportTop + y, x);
}

function pointAt(buffer: TerminalSelectionBuffer, hit: TerminalHit): TerminalSelectionPoint | undefined {
  const marker = buffer.markerAt(hit.line);
  return marker === undefined ? undefined : { marker: marker, start: hit.start, end: hit.end };
}

function wordNeighbor(buffer: TerminalSelectionBuffer, hit: TerminalHit, left: boolean,
  across: boolean): TerminalHit | undefined {
  if (left && hit.start > 0) { return hitAt(buffer, hit.line, hit.start - 1); }
  if (!left && hit.end < buffer.columns) {
    const next = hitAt(buffer, hit.line, hit.end);
    if (across && next?.text === '' && next.end === buffer.columns && buffer.lineAt(hit.line + 1)?.wrapped) {
      const wrapped = hitAt(buffer, hit.line + 1, 0);
      // A wide character wraps before the last column and leaves a padding cell.
      if (wrapped !== undefined && wrapped.end > 1) { return wrapped; }
    }
    return next;
  }
  if (!across) { return undefined; }
  if (left && buffer.lineAt(hit.line)?.wrapped) {
    const prior = hitAt(buffer, hit.line - 1, buffer.columns - 1);
    return prior?.text === '' && hit.end > 1 ? hitAt(buffer, hit.line - 1, buffer.columns - 2) : prior;
  }
  return !left && buffer.lineAt(hit.line + 1)?.wrapped ? hitAt(buffer, hit.line + 1, 0) : undefined;
}

function wordEdge(buffer: TerminalSelectionBuffer, hit: TerminalHit, left: boolean): TerminalHit {
  const spaces = hit.text === '' || hit.text === ' ';
  if (!spaces && WORD_SEPARATORS.includes(hit.text)) { return hit; }
  let edge = hit;
  let next = wordNeighbor(buffer, edge, left, !spaces);
  while (next !== undefined && (spaces ? next.text === '' || next.text === ' ' :
    next.text !== '' && !WORD_SEPARATORS.includes(next.text))) {
    edge = next;
    next = wordNeighbor(buffer, edge, left, !spaces);
  }
  return edge;
}

function fullRows(buffer: TerminalSelectionBuffer, first: number, last: number): TerminalSelectionUnit {
  const from: TerminalHit = { line: first, start: 0, end: buffer.columns, text: '' };
  const to: TerminalHit = { line: last, start: 0, end: buffer.columns, text: '' };
  return { first: from, last: to };
}

function logicalRows(buffer: TerminalSelectionBuffer, row: number): TerminalSelectionUnit {
  let first = row;
  while (first > 0 && buffer.lineAt(first)?.wrapped) { first--; }
  let last = row;
  while (last + 1 < buffer.length && buffer.lineAt(last + 1)?.wrapped) { last++; }
  return fullRows(buffer, first, last);
}

/** Scoped grid selection with xterm markers for stable normal-buffer rows. */
export class DesktopTerminalSelection {
  private epoch: number = -1;
  private anchor?: TerminalSelectionPoint;
  private anchorTail?: TerminalSelectionPoint;
  private focus?: TerminalSelectionPoint;
  private floor?: TerminalSelectionMarker;
  private backwards: boolean = false;
  private mode: TerminalSelectionMode = TerminalSelectionMode.CELL;

  clear(): void {
    this.floor?.dispose();
    this.anchor?.marker.dispose();
    this.releaseFocus();
    this.anchorTail?.marker.dispose();
    this.floor = undefined;
    this.anchor = undefined;
    this.anchorTail = undefined;
    this.epoch = -1;
    this.backwards = false;
    this.mode = TerminalSelectionMode.CELL;
  }

  private releaseFocus(): void {
    if (this.focus !== this.anchorTail) { this.focus?.marker.dispose(); }
    this.focus = undefined;
  }

  begin(frame: TerminalPaintFrame, column: number, row: number): boolean {
    this.clear();
    const hit = visibleHit(frame, column, row);
    if (hit === undefined) { return false; }
    const buffer = frame.selection;
    const anchor = pointAt(buffer, hit);
    if (anchor === undefined) { return false; }
    this.epoch = buffer.epoch;
    this.anchor = anchor;
    this.floor = buffer.markerAt(0);
    return true;
  }

  extend(frame: TerminalPaintFrame, column: number, row: number): boolean {
    const buffer = frame.selection;
    if (this.epoch !== buffer.epoch) { this.clear(); return false; }
    const anchor = this.anchor;
    if (anchor === undefined || anchor.marker.isDisposed) { return false; }
    const hit = visibleHit(frame, column, row);
    if (hit === undefined) { return false; }
    const tail = this.anchorTail;
    if (tail !== undefined) { return this.extendUnit(buffer, anchor, tail, hit); }
    const focus = this.focus;
    if (hit.line === anchor.marker.line && hit.start === anchor.start) {
      this.releaseFocus();
      return focus !== undefined;
    }
    if (focus !== undefined && hit.line === focus.marker.line && hit.start === focus.start) { return false; }
    const next = pointAt(buffer, hit);
    if (next === undefined) { return false; }
    this.releaseFocus();
    this.focus = next;
    this.backwards = hit.line < anchor.marker.line || (hit.line === anchor.marker.line && hit.start < anchor.start);
    return true;
  }

  private extendUnit(buffer: TerminalSelectionBuffer, anchor: TerminalSelectionPoint, tail: TerminalSelectionPoint,
    hit: TerminalHit): boolean {
    if (tail.marker.isDisposed) { return false; }
    const before = hit.line < anchor.marker.line || (hit.line === anchor.marker.line && hit.start < anchor.start);
    const after = hit.line > tail.marker.line || (hit.line === tail.marker.line && hit.start >= tail.end);
    if (!before && !after) {
      if (this.focus === tail) { return false; }
      this.releaseFocus();
      this.backwards = false;
      this.focus = tail;
      return true;
    }
    const position = this.mode === TerminalSelectionMode.WORD ?
      wordEdge(buffer, hit, before) : this.lineEdge(buffer, hit.line, before);
    const focus = this.focus;
    if (focus !== undefined && focus.marker.line === position.line && focus.start === position.start &&
        focus.end === position.end && this.backwards === before) { return false; }
    const next = pointAt(buffer, position);
    if (next === undefined) { return false; }
    this.releaseFocus();
    this.focus = next;
    this.backwards = before;
    return true;
  }

  private lineEdge(buffer: TerminalSelectionBuffer, row: number, first: boolean): TerminalHit {
    const unit = logicalRows(buffer, row);
    return first ? unit.first : unit.last;
  }

  selectWord(frame: TerminalPaintFrame, column: number, row: number): boolean {
    const hit = visibleHit(frame, column, row);
    if (hit === undefined) { this.clear(); return false; }
    const buffer = frame.selection;
    const unit: TerminalSelectionUnit = { first: wordEdge(buffer, hit, true), last: wordEdge(buffer, hit, false) };
    return this.storeRange(buffer, unit, TerminalSelectionMode.WORD);
  }

  selectLine(frame: TerminalPaintFrame, column: number, row: number): boolean {
    const hit = visibleHit(frame, column, row);
    if (hit === undefined) { this.clear(); return false; }
    const buffer = frame.selection;
    return this.storeRange(buffer, logicalRows(buffer, hit.line), TerminalSelectionMode.LINE);
  }

  selectAll(frame: TerminalPaintFrame): boolean {
    const buffer = frame.selection;
    if (buffer.columns <= 0 || buffer.length <= 0) { this.clear(); return false; }
    return this.storeRange(buffer, fullRows(buffer, 0, buffer.length - 1), TerminalSelectionMode.LINE);
  }

  private storeRange(buffer: TerminalSelectionBuffer, unit: TerminalSelectionUnit, mode: TerminalSelectionMode): boolean {
    this.clear();
    const anchor = pointAt(buffer, unit.first);
    const focus = pointAt(buffer, unit.last);
    if (anchor === undefined || focus === undefined) {
      anchor?.marker.dispose();
      focus?.marker.dispose();
      return false;
    }
    this.epoch = buffer.epoch;
    this.anchor = anchor;
    this.focus = focus;
    this.anchorTail = focus;
    this.floor = buffer.markerAt(0);
    this.mode = mode;
    return true;
  }

  private range(frame: TerminalPaintFrame): TerminalSelectionRange | undefined {
    if (this.anchor === undefined) { return undefined; }
    if (this.epoch !== frame.selection.epoch) { this.clear(); return undefined; }
    const first = this.backwards ? this.focus : this.anchor;
    const last = this.backwards ? this.anchorTail ?? this.anchor : this.focus;
    if (first === undefined || last === undefined) { return undefined; }
    if (last.marker.isDisposed) { this.clear(); return undefined; }
    if (first.marker.isDisposed) {
      // History trimmed past the earlier endpoint, so select only the surviving rows.
      if (this.floor?.isDisposed !== true) { this.clear(); return undefined; }
      return { first: 0, start: 0, last: last.marker.line, end: last.end };
    }
    return { first: first.marker.line, start: first.start, last: last.marker.line, end: last.end };
  }

  hasSelection(frame: TerminalPaintFrame): boolean { return this.range(frame) !== undefined; }

  spans(frame: TerminalPaintFrame): DesktopTerminalSelectionSpan[] {
    const range = this.range(frame);
    const spans: DesktopTerminalSelectionSpan[] = [];
    if (range === undefined) { return spans; }
    const buffer = frame.selection;
    const first = Math.max(range.first, buffer.viewportTop);
    const last = Math.min(range.last, buffer.viewportTop + frame.rows.length - 1);
    for (let row = first; row <= last; row++) {
      const start = row === range.first ? range.start : 0;
      const end = row === range.last ? range.end : buffer.columns;
      if (end > start) { spans.push({ row: row - buffer.viewportTop, start: start, end: end }); }
    }
    return spans;
  }

  text(frame: TerminalPaintFrame): string {
    const range = this.range(frame);
    if (range === undefined) { return ''; }
    const buffer = frame.selection;
    const chunks: string[] = [];
    for (let row = range.first; row <= range.last; row++) {
      const line: TerminalSelectionLine | undefined = buffer.lineAt(row);
      if (line === undefined) { return ''; }
      if (row > range.first && !line.wrapped) { chunks.push('\n'); }
      chunks.push(line.text(row === range.first ? range.start : 0, row === range.last ? range.end : buffer.columns));
    }
    return chunks.join('').replace(NONBREAKING_SPACE, ' ');
  }
}
