import { getArray, getBoolean, getNumber, getRecord, getString } from 'connection';
import { DESKTOP_TABLE_MAX_CELLS } from './DesktopDelimitedTable';

export interface DesktopWorkbookTextStyle {
  foreground?: string;
  fontFamily?: string;
  fontSize?: number;
  bold?: boolean;
  italic?: boolean;
  underline?: boolean;
  strike?: boolean;
}

export interface DesktopWorkbookRun {
  text: string;
  decoration: DesktopWorkbookTextStyle;
}

export interface DesktopWorkbookBorder {
  color: string;
  style: number;
}

export interface DesktopWorkbookCell {
  value: string;
  display: string;
  formula: string;
  background?: string;
  horizontal?: string;
  vertical?: string;
  wrap?: boolean;
  rotation?: number;
  verticalText?: boolean;
  decoration: DesktopWorkbookTextStyle;
  runs: DesktopWorkbookRun[];
  top?: DesktopWorkbookBorder;
  right?: DesktopWorkbookBorder;
  bottom?: DesktopWorkbookBorder;
  left?: DesktopWorkbookBorder;
}

export interface DesktopWorkbookMerge {
  row: number;
  column: number;
  rows: number;
  columns: number;
}

export interface DesktopWorkbook {
  sheets: DesktopWorkbookSheet[];
  active: number;
  formulas: boolean;
  unsupported: string[];
}

function indexOf(value: number | undefined, bound: number): number {
  return value !== undefined && Number.isSafeInteger(value) && value >= 0 && value < bound ? value : -1;
}

function readMetrics(raw: Object[] | undefined, count: number): Map<number, number> {
  const metrics = new Map<number, number>();
  for (const item of raw ?? []) {
    const index = indexOf(getNumber(item, 'index'), count);
    const size = getNumber(item, 'pixels') ?? 0;
    if (index >= 0 && Number.isFinite(size) && size > 0) { metrics.set(index, Math.min(2048, size)); }
  }
  return metrics;
}

function readHidden(raw: Object[] | undefined, count: number): Set<number> {
  const hidden = new Set<number>();
  for (const value of raw ?? []) {
    if (typeof value === 'number' && indexOf(value, count) >= 0) { hidden.add(value); }
  }
  return hidden;
}

/** Translate visible positions without allocating an index for an ordinary fixed-size sheet. */
export class DesktopWorkbookAxis {
  readonly count: number;
  private readonly ordinarySize: number;
  private readonly positions?: number[];
  private readonly offsets?: number[];

  constructor(count: number, sizes: Map<number, number>, hidden: Set<number>, ordinarySize: number) {
    this.count = count - hidden.size;
    this.ordinarySize = ordinarySize;
    if (hidden.size > 0) {
      const positions: number[] = [];
      for (let index = 0; index < count; index++) {
        if (!hidden.has(index)) { positions.push(index); }
      }
      this.positions = positions;
    }
    if (sizes.size > 0) {
      const offsets: number[] = [0];
      for (let position = 0; position < this.count; position++) {
        offsets.push(offsets[position] + (sizes.get(this.logical(position)) ?? ordinarySize));
      }
      this.offsets = offsets;
    }
  }

  logical(position: number): number { return this.positions?.[position] ?? position; }

  /** Return the first visible position whose workbook index is at or after the requested index. */
  position(logical: number): number {
    if (this.positions === undefined) { return Math.max(0, Math.min(logical, this.count)); }
    let low = 0;
    let high = this.count;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.positions[middle] < logical) { low = middle + 1; } else { high = middle; }
    }
    return low;
  }

  offset(position: number): number {
    const bounded = Math.max(0, Math.min(position, this.count));
    return this.offsets?.[bounded] ?? bounded * this.ordinarySize;
  }

  atOffset(offset: number): number {
    if (this.offsets === undefined) {
      return Math.max(0, Math.min(this.count - 1, Math.floor(offset / this.ordinarySize)));
    }
    let low = 0;
    let high = this.count;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.offsets[middle + 1] <= offset) { low = middle + 1; } else { high = middle; }
    }
    return Math.max(0, Math.min(this.count - 1, low));
  }
}

export class DesktopWorkbookSheet {
  readonly id: string;
  readonly name: string;
  readonly rows: DesktopWorkbookAxis;
  readonly columns: DesktopWorkbookAxis;
  readonly cells: Map<number, DesktopWorkbookCell> = new Map();
  readonly merges: Map<number, DesktopWorkbookMerge> = new Map();
  readonly columnCount: number;

  constructor(id: string, name: string, rows: number, columns: number, raw: Object) {
    this.id = id;
    this.name = name;
    this.columnCount = columns;
    this.rows = new DesktopWorkbookAxis(rows, readMetrics(getArray(raw, 'rowHeights'), rows),
      readHidden(getArray(raw, 'hiddenRows'), rows), 20);
    this.columns = new DesktopWorkbookAxis(columns, readMetrics(getArray(raw, 'columnWidths'), columns),
      readHidden(getArray(raw, 'hiddenColumns'), columns), 72);
  }

  key(row: number, column: number): number { return row * this.columnCount + column; }

  merge(row: number, column: number): DesktopWorkbookMerge | undefined { return this.merges.get(this.key(row, column)); }

  cell(row: number, column: number): DesktopWorkbookCell | undefined {
    const merge = this.merge(row, column);
    return this.cells.get(merge === undefined ? this.key(row, column) : this.key(merge.row, merge.column));
  }
}

function readDecoration(raw: Object): DesktopWorkbookTextStyle {
  const points = getNumber(raw, 'fontSize');
  return {
    foreground: getString(raw, 'foreground'), fontFamily: getString(raw, 'fontFamily'),
    fontSize: points !== undefined && points > 0 && points <= 192 ? points * 4 / 3 : undefined,
    bold: getBoolean(raw, 'bold'), italic: getBoolean(raw, 'italic'),
    underline: getBoolean(raw, 'underline'), strike: getBoolean(raw, 'strike')
  };
}

function readBorder(raw: Object | undefined, edge: string): DesktopWorkbookBorder | undefined {
  const value = getRecord(raw, edge);
  const color = getString(value, 'color');
  const style = getNumber(value, 'style');
  return color && style !== undefined && style > 0 ? { color: color, style: style } : undefined;
}

function readCell(raw: Object): DesktopWorkbookCell {
  const value = getString(raw, 'value') ?? '';
  const runs: DesktopWorkbookRun[] = [];
  for (const run of getArray(raw, 'runs') ?? []) {
    const text = getString(run, 'text');
    if (text !== undefined) { runs.push({ text: text, decoration: readDecoration(run) }); }
  }
  const edges = getRecord(raw, 'borders');
  return {
    value: value, display: getString(raw, 'display') ?? value, formula: getString(raw, 'formula') ?? '',
    background: getString(raw, 'background'), horizontal: getString(raw, 'horizontal'), vertical: getString(raw, 'vertical'),
    wrap: getBoolean(raw, 'wrap'), rotation: getNumber(raw, 'rotation'), verticalText: getBoolean(raw, 'verticalText'),
    decoration: readDecoration(raw), runs: runs, top: readBorder(edges, 'top'), right: readBorder(edges, 'right'),
    bottom: readBorder(edges, 'bottom'), left: readBorder(edges, 'left')
  };
}

function readMerges(sheet: DesktopWorkbookSheet, raw: Object, rows: number, columns: number): boolean {
  let covered = 0;
  for (const item of getArray(raw, 'merges') ?? []) {
    const row = indexOf(getNumber(item, 'row'), rows);
    const column = indexOf(getNumber(item, 'column'), columns);
    const height = getNumber(item, 'rows') ?? 0;
    const width = getNumber(item, 'columns') ?? 0;
    if (row < 0 || column < 0 || !Number.isSafeInteger(height) || !Number.isSafeInteger(width) ||
      height <= 0 || width <= 0 || row + height > rows || column + width > columns) { return false; }
    covered += height * width;
    if (covered > rows * columns) { return false; }
    const merge: DesktopWorkbookMerge = { row: row, column: column, rows: height, columns: width };
    for (let r = row; r < row + height; r++) {
      for (let c = column; c < column + width; c++) {
        const key = sheet.key(r, c);
        if (sheet.merges.has(key)) { return false; }
        sheet.merges.set(key, merge);
      }
    }
  }
  return true;
}

export function desktopWorkbookFormat(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.xlsx')) { return 'XLSX'; }
  if (lower.endsWith('.xls')) { return 'XLS'; }
  return '';
}

export function readDesktopWorkbook(raw: Object | undefined): DesktopWorkbook | undefined {
  const rawSheets = getArray(raw, 'sheets');
  if (rawSheets === undefined) { return undefined; }
  const sheets: DesktopWorkbookSheet[] = [];
  const unsupported: string[] = [];
  let active = 0;
  let occupied = 0;
  let formulas = false;
  for (const item of rawSheets) {
    const rows = getNumber(item, 'rows') ?? 0;
    const columns = getNumber(item, 'columns') ?? 0;
    if (!Number.isSafeInteger(rows) || !Number.isSafeInteger(columns) || rows <= 0 || columns <= 0 ||
      rows * columns > DESKTOP_TABLE_MAX_CELLS - occupied) { return undefined; }
    occupied += rows * columns;
    if (getBoolean(item, 'hidden') === true) { continue; }
    const sheet = new DesktopWorkbookSheet(getString(item, 'id') || String(sheets.length),
      getString(item, 'name') || String(sheets.length + 1), rows, columns, item);
    const cells = getArray(item, 'cells');
    if (cells === undefined || cells.length > rows * columns || !readMerges(sheet, item, rows, columns)) {
      return undefined;
    }
    for (const entry of cells) {
      const row = indexOf(getNumber(entry, 'row'), rows);
      const column = indexOf(getNumber(entry, 'column'), columns);
      if (row < 0 || column < 0) { return undefined; }
      const cell = readCell(entry);
      if (cell.formula) { formulas = true; }
      sheet.cells.set(sheet.key(row, column), cell);
    }
    if (getBoolean(item, 'active') === true) { active = sheets.length; }
    sheets.push(sheet);
  }
  for (const item of getArray(raw, 'unsupportedFeatures') ?? []) {
    if (typeof item === 'string' && !unsupported.includes(item)) { unsupported.push(item); }
  }
  return sheets.length === 0 ? undefined : { sheets: sheets, active: active, formulas: formulas, unsupported: unsupported };
}
