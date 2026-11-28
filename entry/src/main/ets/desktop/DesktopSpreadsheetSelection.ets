import { DesktopWorkbookSheet } from './DesktopWorkbookModel';

export interface DesktopSpreadsheetRange {
  firstRow: number;
  lastRow: number;
  firstColumn: number;
  lastColumn: number;
}

function includeMerge(sheet: DesktopWorkbookSheet, range: DesktopSpreadsheetRange, row: number, column: number,
  logical: boolean): void {
  const merge = logical ? sheet.merge(row, column) : sheet.merge(sheet.rows.logical(row), sheet.columns.logical(column));
  if (merge === undefined) { return; }
  range.firstRow = Math.min(range.firstRow, logical ? merge.row : sheet.rows.position(merge.row));
  range.lastRow = Math.max(range.lastRow, (logical ? merge.row + merge.rows : sheet.rows.position(merge.row + merge.rows)) - 1);
  range.firstColumn = Math.min(range.firstColumn, logical ? merge.column : sheet.columns.position(merge.column));
  range.lastColumn = Math.max(range.lastColumn,
    (logical ? merge.column + merge.columns : sheet.columns.position(merge.column + merge.columns)) - 1);
}

function scanRow(sheet: DesktopWorkbookSheet, range: DesktopSpreadsheetRange, row: number, from: number, to: number,
  logical: boolean): void {
  for (let column = from; column <= to; column++) { includeMerge(sheet, range, row, column, logical); }
}

function scanColumn(sheet: DesktopWorkbookSheet, range: DesktopSpreadsheetRange, column: number, from: number, to: number,
  logical: boolean): void {
  for (let row = from; row <= to; row++) { includeMerge(sheet, range, row, column, logical); }
}

/** Expand across every merge touching an edge, including merges reached by a previous expansion. */
export function desktopSpreadsheetRange(sheet: DesktopWorkbookSheet | undefined, anchorRow: number, anchorColumn: number,
  row: number, column: number): DesktopSpreadsheetRange {
  const range: DesktopSpreadsheetRange = {
    firstRow: Math.min(anchorRow, row), lastRow: Math.max(anchorRow, row),
    firstColumn: Math.min(anchorColumn, column), lastColumn: Math.max(anchorColumn, column)
  };
  if (sheet !== undefined && sheet.merges.size > 0) { expandEdges(sheet, range, false); }
  return range;
}

export function desktopSpreadsheetLogicalRange(sheet: DesktopWorkbookSheet, visible: DesktopSpreadsheetRange):
  DesktopSpreadsheetRange {
  const fullRows = visible.firstRow === 0 && visible.lastRow === sheet.rows.count - 1;
  const fullColumns = visible.firstColumn === 0 && visible.lastColumn === sheet.columns.count - 1;
  const range: DesktopSpreadsheetRange = {
    firstRow: fullRows ? 0 : sheet.rows.logical(visible.firstRow),
    lastRow: fullRows ? sheet.rows.logicalCount - 1 : sheet.rows.logical(visible.lastRow),
    firstColumn: fullColumns ? 0 : sheet.columns.logical(visible.firstColumn),
    lastColumn: fullColumns ? sheet.columns.logicalCount - 1 : sheet.columns.logical(visible.lastColumn)
  };
  if (sheet.merges.size > 0) { expandEdges(sheet, range, true); }
  return range;
}

function expandEdges(sheet: DesktopWorkbookSheet, range: DesktopSpreadsheetRange, logical: boolean): void {
  let previous: DesktopSpreadsheetRange | undefined;
  while (previous === undefined || previous.firstRow !== range.firstRow || previous.lastRow !== range.lastRow ||
    previous.firstColumn !== range.firstColumn || previous.lastColumn !== range.lastColumn) {
    const top = range.firstRow;
    const bottom = range.lastRow;
    const left = range.firstColumn;
    const right = range.lastColumn;
    if (previous === undefined || previous.firstRow !== top) { scanRow(sheet, range, top, left, right, logical); }
    else {
      scanRow(sheet, range, top, left, previous.firstColumn - 1, logical);
      scanRow(sheet, range, top, previous.lastColumn + 1, right, logical);
    }
    if (top !== bottom) {
      if (previous === undefined || previous.lastRow !== bottom) { scanRow(sheet, range, bottom, left, right, logical); }
      else {
        scanRow(sheet, range, bottom, left, previous.firstColumn - 1, logical);
        scanRow(sheet, range, bottom, previous.lastColumn + 1, right, logical);
      }
    }
    if (previous === undefined || previous.firstColumn !== left) {
      scanColumn(sheet, range, left, top + 1, bottom - 1, logical);
    }
    else {
      scanColumn(sheet, range, left, top + 1, previous.firstRow, logical);
      scanColumn(sheet, range, left, previous.lastRow, bottom - 1, logical);
    }
    if (left !== right) {
      if (previous === undefined || previous.lastColumn !== right) {
        scanColumn(sheet, range, right, top + 1, bottom - 1, logical);
      }
      else {
        scanColumn(sheet, range, right, top + 1, previous.firstRow, logical);
        scanColumn(sheet, range, right, previous.lastRow, bottom - 1, logical);
      }
    }
    previous = { firstRow: top, lastRow: bottom, firstColumn: left, lastColumn: right };
  }
}
