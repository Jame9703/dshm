import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { LengthMetrics } from '@kit.ArkUI';
import { DesktopDelimitedTable, desktopTableColumn } from './DesktopDelimitedTable';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopWorkbookBorder, DesktopWorkbookCell, DesktopWorkbookMerge, DesktopWorkbookRun, DesktopWorkbookSheet,
  DesktopWorkbookTextStyle } from './DesktopWorkbookModel';
import { desktopRangeContains, desktopSpreadsheetCopyGrid, desktopSpreadsheetLogicalRange,
  desktopSpreadsheetRange } from './DesktopSpreadsheetSelection';
import type { DesktopSpreadsheetCopyGrid, DesktopSpreadsheetRange, DesktopSpreadsheetSelectionArea }
  from './DesktopSpreadsheetSelection';
import { desktopWorkbookClipboardValue, desktopWorkbookGridToHtml } from './DesktopWorkbookClipboard';

const ROW_HEIGHT: number = 24;
const COLUMN_WIDTH: number = 100;
const ROW_HEADER: number = 40;

export interface DesktopSheetSelection {
  row: number;
  column: number;
  anchorRow: number;
  anchorColumn: number;
  earlier?: DesktopSpreadsheetSelectionArea[];
  scrollX?: number;
  scrollY?: number;
}

interface DesktopGridPart {
  column: number;
  end: number;
  merge?: DesktopWorkbookMerge;
}

interface DesktopGridPoint {
  x: number;
  y: number;
  extend: boolean;
  append: boolean;
}

class DesktopTableRows implements IDataSource {
  private count: number = 0;
  private first: number = 0;
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.count; }
  getData(index: number): number { return this.first + index; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((other: DataChangeListener): boolean => other !== listener);
  }
  reset(count: number, first: number): void {
    this.count = count;
    this.first = first;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }
}

@Component
export struct DesktopDelimitedPreview {
  table: DesktopDelimitedTable = { rows: [['']], columns: 1 };
  sheet?: DesktopWorkbookSheet;
  initialSelection?: DesktopSheetSelection;
  onSelection: (selection: DesktopSheetSelection) => void = (): void => {};
  @Prop format: string = 'CSV';
  @Prop focusScope: string = '';
  @Prop @Watch('measureZoom') zoom: number = 100;
  @Prop formulas: boolean = false;
  @State private selectedRow: number = 0;
  @State private selectedColumn: number = 0;
  @State private anchorRow: number = 0;
  @State private anchorColumn: number = 0;
  @State private selectedRange: DesktopSpreadsheetRange = { firstRow: 0, lastRow: 0, firstColumn: 0, lastColumn: 0 };
  @State private earlierRanges: DesktopSpreadsheetSelectionArea[] = [];
  @State private columns: number[] = [];
  @State private pinnedColumns: number[] = [];
  @State private pinnedRows: number[] = [];
  @State private pinnedHeight: number = 0;
  @State private scrollX: number = 0;
  @State private menuCell: string = '';
  @State private formulaNoticeVisible: boolean = false;
  private readonly data = new DesktopTableRows();
  private readonly horizontal = new Scroller();
  private readonly vertical = new Scroller();
  private viewportWidth: number = 360;
  private viewportHeight: number = 0;
  private viewportArea?: Area;
  private pointerDown?: DesktopGridPoint;
  private dragMode: string = '';
  private readonly heldSelectionKeys = new Set<number>();
  private readonly heldShiftKeys = new Set<number>();
  private focusTimer: number = -1;
  private restoreTimer: number = -1;

  aboutToAppear(): void {
    this.data.reset(this.rowCount() - this.frozenRows(), this.frozenRows());
    this.measureColumns(0);
    this.measureFrozen();
    this.updateRange();
    const saved = this.initialSelection;
    if (saved !== undefined) {
      this.selectedRow = Math.max(0, Math.min(this.rowCount() - 1, saved.row));
      this.selectedColumn = Math.max(0, Math.min(this.columnCount() - 1, saved.column));
      this.anchorRow = Math.max(0, Math.min(this.rowCount() - 1, saved.anchorRow));
      this.anchorColumn = Math.max(0, Math.min(this.columnCount() - 1, saved.anchorColumn));
      this.earlierRanges = saved.earlier?.slice() ?? [];
      this.updateRange();
      this.restoreTimer = setTimeout((): void => {
        this.horizontal.scrollTo({ xOffset: saved.scrollX ?? 0, yOffset: 0, animation: false });
        this.vertical.scrollTo({ xOffset: 0, yOffset: saved.scrollY ?? 0, animation: false });
      }, 0);
    }
  }

  aboutToDisappear(): void {
    clearTimeout(this.focusTimer);
    clearTimeout(this.restoreTimer);
    this.clearModifiers();
    this.finishDrag();
    this.onSelection({ row: this.selectedRow, column: this.selectedColumn, anchorRow: this.anchorRow,
      anchorColumn: this.anchorColumn, earlier: this.earlierRanges,
      scrollX: this.horizontal.currentOffset().xOffset, scrollY: this.vertical.currentOffset().yOffset });
  }

  private keyboardId(): string { return 'desktopDelimitedFocus-' + this.focusScope; }

  private rowCount(): number { return this.sheet?.rows.count ?? this.table.rows.length; }
  private columnCount(): number { return this.sheet?.columns.count ?? this.table.columns; }
  private rowNumber(row: number): number { return this.sheet?.rows.logical(row) ?? row; }
  private columnNumber(column: number): number { return this.sheet?.columns.logical(column) ?? column; }
  private frozenRows(): number { return this.sheet?.frozenRows ?? 0; }
  private frozenColumns(): number { return this.sheet?.frozenColumns ?? 0; }
  private cellStyle(row: number, column: number): DesktopWorkbookCell | undefined {
    return this.sheet?.cell(this.rowNumber(row), this.columnNumber(column));
  }
  private cellMerge(row: number, column: number): DesktopWorkbookMerge | undefined {
    return this.sheet?.merge(this.rowNumber(row), this.columnNumber(column));
  }

  private cell(row: number, column: number): string {
    return this.cellStyle(row, column)?.display ?? this.table.rows[row]?.[column] ?? '';
  }
  private formulaValue(): string {
    const first = this.earlierRanges[0];
    const row = first?.anchorRow ?? this.anchorRow;
    const column = first?.anchorColumn ?? this.anchorColumn;
    const style = this.cellStyle(row, column);
    const formula = style?.formula ?? '';
    if (formula) { return formula.startsWith('=') ? formula : '=' + formula; }
    return style?.display.endsWith('%') ? style.display : style?.value ?? this.cell(row, column);
  }

  private address(row: number, column: number): string {
    return desktopTableColumn(this.columnNumber(column)) + String(this.rowNumber(row) + 1);
  }

  private rangeAddress(): string {
    const current = this.address(this.selectedRow, this.selectedColumn);
    if (this.anchorRow === this.selectedRow && this.anchorColumn === this.selectedColumn) { return current; }
    const range = this.selectedRange;
    return this.address(range.firstRow, range.firstColumn) + ':' + this.address(range.lastRow, range.lastColumn);
  }

  private ratio(): number { return this.zoom / 100; }
  private rowHeaderWidth(): number { return (this.sheet === undefined ? ROW_HEADER : 46) * this.ratio(); }

  private columnOffset(position: number): number {
    return (this.sheet?.columns.offset(position) ?? position * COLUMN_WIDTH) * this.ratio();
  }

  private rowHeight(position: number): number {
    const rows = this.sheet?.rows;
    return (rows === undefined ? ROW_HEIGHT : rows.offset(position + 1) - rows.offset(position)) * this.ratio();
  }

  private cellText(row: number, part: DesktopGridPart, style?: DesktopWorkbookCell): string {
    if (!this.alignsCell(row, part.merge, style?.vertical)) { return ''; }
    const value = this.cell(row, part.column);
    return style?.verticalText ? Array.from(value).join('\n') : value;
  }

  private headerHeight(): number { return (this.sheet === undefined ? ROW_HEIGHT : 20) * this.ratio(); }

  private measuredWidth(): number {
    return this.columnOffset(this.columnCount()) + this.rowHeaderWidth();
  }

  private columnAt(offset: number): number {
    const unscaled = offset / this.ratio();
    return this.sheet?.columns.atOffset(unscaled) ??
      Math.max(0, Math.min(this.columnCount() - 1, Math.floor(unscaled / COLUMN_WIDTH)));
  }

  private rowAt(offset: number): number {
    const unscaled = offset / this.ratio();
    return this.sheet?.rows.atOffset(unscaled) ??
      Math.max(0, Math.min(this.rowCount() - 1, Math.floor(unscaled / ROW_HEIGHT)));
  }

  private rowsHeight(): number {
    return (this.sheet?.rows.offset(this.rowCount()) ?? this.rowCount() * ROW_HEIGHT) * this.ratio();
  }

  private frozenHeight(): number {
    return (this.sheet?.rows.offset(this.frozenRows()) ?? 0) * this.ratio();
  }

  private frozenWidth(): number { return this.columnOffset(this.frozenColumns()); }

  private hitRow(y: number, scroll: number): number {
    const at = y - 0.000001;
    return this.rowAt(at < this.frozenHeight() ? at : at + scroll);
  }

  private hitColumn(x: number, scroll: number): number {
    const at = x - 0.000001;
    return this.columnAt(at < this.frozenWidth() ? at : at + scroll);
  }

  private prefix(count: number): number[] {
    const result: number[] = [];
    for (let index = 0; index < count; index++) { result.push(index); }
    return result;
  }

  private measureFrozen(): void {
    const width = Math.max(0, this.viewportWidth - this.rowHeaderWidth());
    const height = Math.max(0, this.viewportHeight - this.headerHeight());
    const columns = Math.min(this.frozenColumns(), this.columnAt(width) + 1);
    const rows = Math.min(this.frozenRows(), this.rowAt(height) + 1);
    if (columns !== this.pinnedColumns.length) { this.pinnedColumns = this.prefix(columns); }
    if (rows !== this.pinnedRows.length) { this.pinnedRows = this.prefix(rows); }
    const pinnedHeight = Math.min(height, this.frozenHeight());
    if (this.pinnedHeight !== pinnedHeight) { this.pinnedHeight = pinnedHeight; }
  }

  private measureZoom(): void {
    this.measureFrozen();
    this.measureColumns(this.horizontal.currentOffset().xOffset);
    this.revealSelection();
  }

  private measureColumns(offset: number): void {
    const x = Math.max(0, offset);
    if (this.scrollX !== x) { this.scrollX = x; }
    const start = Math.max(this.frozenColumns(), this.columnAt(x + this.frozenWidth()));
    const width = Math.max(0, this.viewportWidth - this.rowHeaderWidth());
    const end = this.frozenWidth() >= width ? start : Math.min(this.columnCount(), this.columnAt(x + width) + 2);
    if (this.columns.length === end - start && this.columns[0] === start) { return; }
    const next: number[] = [];
    for (let column = start; column < end; column++) { next.push(column); }
    this.columns = next;
  }

  private beginSelection(extend: boolean, append: boolean): void {
    if (extend) { return; }
    if (append) {
      const area: DesktopSpreadsheetSelectionArea = {
        anchorRow: this.anchorRow, anchorColumn: this.anchorColumn, range: this.selectedRange
      };
      this.earlierRanges = [...this.earlierRanges, area];
    } else if (this.earlierRanges.length !== 0) {
      this.earlierRanges = [];
    }
  }

  private select(row: number, column: number, focus: boolean, extend: boolean = false, append: boolean = false): void {
    this.beginSelection(extend, append);
    this.selectedRow = Math.max(0, Math.min(this.rowCount() - 1, row));
    this.selectedColumn = Math.max(0, Math.min(this.columnCount() - 1, column));
    const merge = this.cellMerge(this.selectedRow, this.selectedColumn);
    const sheet = this.sheet;
    if (merge !== undefined && sheet !== undefined) {
      this.selectedRow = sheet.rows.position(merge.row);
      this.selectedColumn = sheet.columns.position(merge.column);
    }
    if (!extend) {
      this.anchorRow = this.selectedRow;
      this.anchorColumn = this.selectedColumn;
    }
    this.updateRange();
    if (focus) { this.focusKeyboard(); }
  }

  private updateRange(): void {
    this.selectedRange = desktopSpreadsheetRange(this.sheet, this.anchorRow, this.anchorColumn,
      this.selectedRow, this.selectedColumn);
  }

  private extendTo(row: number, column: number): void {
    if (this.selectedRow === row && this.selectedColumn === column) { return; }
    this.selectedRow = row;
    this.selectedColumn = column;
    this.updateRange();
  }

  private selectHeaders(row: number, column: number, extend: boolean = false, append: boolean = false): void {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    if (extend && (row >= 0 || column >= 0)) {
      this.extendTo(row >= 0 ? row : this.selectedRow, column >= 0 ? column : this.selectedColumn);
      return;
    }
    this.beginSelection(false, append && (row >= 0 || column >= 0));
    if (row < 0) { this.anchorRow = 0; }
    else if (!extend) { this.anchorRow = row; }
    if (column < 0) { this.anchorColumn = 0; }
    else if (!extend) { this.anchorColumn = column; }
    this.selectedRow = row < 0 ? this.rowCount() - 1 : row;
    this.selectedColumn = column < 0 ? this.columnCount() - 1 : column;
    this.updateRange();
  }

  private rememberPointer(event: MouseEvent): void {
    if (event.button !== MouseButton.Left || event.action !== MouseAction.Press) { return; }
    const area = this.viewportArea;
    this.pointerDown = {
      x: area === undefined ? event.x : event.windowX - Number(area.globalPosition.x),
      y: area === undefined ? event.y : event.windowY - Number(area.globalPosition.y),
      extend: this.shiftPressed(event),
      append: event.getModifierKeyState?.(['Ctrl']) === true || this.heldSelectionKeys.size > 0
    };
  }

  private shiftPressed(event: BaseEvent): boolean {
    return event.getModifierKeyState?.(['Shift']) === true || this.heldShiftKeys.size > 0;
  }

  private clearModifiers(): void {
    this.heldSelectionKeys.clear();
    this.heldShiftKeys.clear();
  }

  private chooseClickedCell(event: ClickEvent, row: number, column: number, header: boolean): void {
    const mouse = event.source === SourceType.Mouse || event.sourceTool === SourceTool.MOUSE ||
      event.sourceTool === SourceTool.TOUCHPAD;
    const pressed = mouse ? this.pointerDown : undefined;
    this.pointerDown = undefined;
    const extend = pressed?.extend ?? this.shiftPressed(event);
    const append = pressed?.append ?? (event.getModifierKeyState?.(['Ctrl']) === true || this.heldSelectionKeys.size > 0);
    if (header) {
      this.selectHeaders(row, column, extend, append);
      this.focusKeyboard();
    } else {
      this.select(row, column, true, extend, append);
    }
  }

  private beginDrag(event: GestureEvent): void {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    const pointer = event.fingerInfos?.[0] ?? event.fingerList[0];
    if (pointer === undefined) { return; }
    const origin: DesktopGridPoint = this.pointerDown ??
      { x: this.dragLocalX(pointer) - event.offsetX, y: this.dragLocalY(pointer) - event.offsetY,
        extend: this.shiftPressed(event),
        append: event.getModifierKeyState?.(['Ctrl']) === true || this.heldSelectionKeys.size > 0 };
    const headerX = origin.x < this.rowHeaderWidth();
    const headerY = origin.y < this.headerHeight();
    const row = this.hitRow(origin.y - this.headerHeight(), this.vertical.currentOffset().yOffset);
    const column = this.hitColumn(origin.x - this.rowHeaderWidth(), this.horizontal.currentOffset().xOffset);
    if (headerX && headerY) {
      this.selectHeaders(-1, -1);
      this.dragMode = 'all';
    } else if (headerX || headerY) {
      this.selectHeaders(headerY ? -1 : row, headerX ? -1 : column, origin.extend, origin.append);
      this.dragMode = headerX ? origin.extend ? 'row-extend' : 'rows' :
        origin.extend ? 'column-extend' : 'columns';
    } else {
      this.select(row, column, false, origin.extend, origin.append);
      this.dragMode = 'cells';
    }
    this.updateDrag(event);
  }

  private edgeDelta(point: number, length: number, margin: number): number {
    if (point < 0) { return point / 2; }
    const edge = Math.max(1, length - margin);
    return point > edge ? (point - edge) / 2 : 0;
  }

  private dragLocalX(pointer: FingerInfo): number {
    return this.viewportArea === undefined ? pointer.localX : pointer.globalX - Number(this.viewportArea.globalPosition.x);
  }

  private dragLocalY(pointer: FingerInfo): number {
    return this.viewportArea === undefined ? pointer.localY : pointer.globalY - Number(this.viewportArea.globalPosition.y);
  }

  private updateDrag(event: GestureEvent): void {
    const mode = this.dragMode;
    if (!mode || mode === 'all') { return; }
    const pointer = event.fingerInfos?.[0] ?? event.fingerList[0];
    if (pointer === undefined) { return; }
    const x = this.dragLocalX(pointer) - this.rowHeaderWidth();
    const y = this.dragLocalY(pointer) - this.headerHeight();
    const width = Math.max(1, this.viewportWidth - this.rowHeaderWidth());
    const height = Math.max(1, this.viewportHeight - this.headerHeight());
    const scrollX = this.horizontal.currentOffset().xOffset;
    const scrollY = this.vertical.currentOffset().yOffset;
    const nextX = mode === 'rows' || mode === 'row-extend' || this.frozenWidth() >= width ? scrollX :
      Math.max(0, Math.min(this.columnOffset(this.columnCount()) - width, scrollX + this.edgeDelta(x, width, 60 * this.ratio())));
    const nextY = mode === 'columns' || mode === 'column-extend' || this.frozenHeight() >= height ? scrollY :
      Math.max(0, Math.min(this.rowsHeight() - height, scrollY + this.edgeDelta(y, height, 20 * this.ratio())));
    if (nextX !== scrollX) { this.horizontal.scrollTo({ xOffset: nextX, yOffset: 0, animation: false }); }
    if (nextY !== scrollY) { this.vertical.scrollTo({ xOffset: 0, yOffset: nextY, animation: false }); }
    const row = mode === 'columns' ? this.rowCount() - 1 : mode === 'column-extend' ? this.selectedRow :
      this.hitRow(Math.max(0, Math.min(height, y)), nextY);
    const column = mode === 'rows' ? this.columnCount() - 1 : mode === 'row-extend' ? this.selectedColumn :
      this.hitColumn(Math.max(0, Math.min(width, x)), nextX);
    this.extendTo(row, column);
  }

  private finishDrag(): void {
    this.dragMode = '';
    this.pointerDown = undefined;
  }

  private revealSelection(): void {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    if (this.selectedRow >= this.frozenRows()) {
      this.vertical.scrollToIndex(this.selectedRow - this.frozenRows(), false, ScrollAlign.AUTO);
    }
    if (this.selectedColumn < this.frozenColumns()) { return; }
    const x = this.columnOffset(this.selectedColumn);
    const end = this.columnOffset(this.selectedColumn + 1) + this.rowHeaderWidth();
    if (x < this.scrollX + this.frozenWidth() || end > this.scrollX + this.viewportWidth) {
      this.horizontal.scrollTo({ xOffset: Math.max(0, x - this.frozenWidth()), yOffset: 0, animation: false });
    }
  }

  private selected(row: number, column: number): boolean {
    return desktopRangeContains(this.selectedRange, row, column) ||
      this.earlierRanges.some((area: DesktopSpreadsheetSelectionArea): boolean => desktopRangeContains(area.range, row, column));
  }

  private bandSelected(position: number, row: boolean): boolean {
    const contains = (range: DesktopSpreadsheetRange): boolean => row ?
      position >= range.firstRow && position <= range.lastRow :
      position >= range.firstColumn && position <= range.lastColumn;
    return contains(this.selectedRange) ||
      this.earlierRanges.some((area: DesktopSpreadsheetSelectionArea): boolean => contains(area.range));
  }

  private plainGrid(grid: DesktopSpreadsheetCopyGrid, sheet?: DesktopWorkbookSheet): string {
    const lines: string[] = [];
    const single = grid.rows.length === 1 && grid.columns.length === 1;
    for (const row of grid.rows) {
      const fields: string[] = [];
      for (const column of grid.columns) {
        const merge = sheet?.merge(row, column);
        if (merge !== undefined && (row !== merge.row || column !== merge.column)) {
          fields.push('');
          continue;
        }
        const value = sheet === undefined ? this.cell(row, column) : desktopWorkbookClipboardValue(sheet.cell(row, column));
        fields.push(!single && (value.includes('\t') || value.includes('\n') || value.includes('\r') || value.includes('"')) ?
          '"' + value.replaceAll('"', '""') + '"' : value);
      }
      lines.push(fields.join('\t'));
    }
    return lines.join('\n');
  }

  private async copySelection(fromMenu: boolean = false): Promise<void> {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    const sheet = this.sheet;
    const ranges = this.earlierRanges.map((area: DesktopSpreadsheetSelectionArea): DesktopSpreadsheetRange => area.range);
    ranges.push(this.selectedRange);
    const grid = desktopSpreadsheetCopyGrid(sheet === undefined ? ranges :
      ranges.map((range: DesktopSpreadsheetRange): DesktopSpreadsheetRange => desktopSpreadsheetLogicalRange(sheet, range)));
    if (grid === undefined) {
      if (fromMenu) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_table_disjoint_copy') });
      }
      return;
    }
    const plain = this.plainGrid(grid, sheet);
    if (sheet === undefined) {
      await this.copy(plain);
      return;
    }
    const html = desktopWorkbookGridToHtml(sheet, grid);
    if (html === undefined) {
      await this.copy(plain);
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, plain);
      data.addRecord(pasteboard.MIMETYPE_TEXT_HTML, html);
      await pasteboard.getSystemPasteboard().setData(data);
    } catch (_) { await this.copy(plain); }
  }

  private parts(row: number, columns: number[]): DesktopGridPart[] {
    const parts: DesktopGridPart[] = [];
    const end = (columns[columns.length - 1] ?? -1) + 1;
    for (let start = columns[0] ?? end; start < end;) {
      const merge = this.cellMerge(row, start);
      const next = merge === undefined ? start + 1 :
        Math.min(end, this.sheet?.columns.position(merge.column + merge.columns) ?? start + 1);
      parts.push({ column: start, end: next, merge: merge });
      start = next;
    }
    return parts;
  }

  private alignsCell(row: number, merge: DesktopWorkbookMerge | undefined, vertical?: string): boolean {
    const axis = this.sheet?.rows;
    if (merge === undefined || axis === undefined) { return true; }
    const start = axis.position(merge.row);
    const end = axis.position(merge.row + merge.rows);
    if (vertical === 'top') { return row === start; }
    if (vertical === 'bottom') { return row === end - 1; }
    return row === axis.atOffset((axis.offset(start) + axis.offset(end)) / 2);
  }

  private drawsCellText(row: number, part: DesktopGridPart, style?: DesktopWorkbookCell): boolean {
    const merge = part.merge;
    const sheet = this.sheet;
    if (merge !== undefined && sheet !== undefined && part.column >= this.frozenColumns() &&
      sheet.columns.position(merge.column) < this.frozenColumns()) { return false; }
    return this.alignsCell(row, merge, style?.vertical);
  }

  private partSelected(row: number, part: DesktopGridPart): boolean {
    const merge = part.merge;
    if (merge === undefined || this.sheet === undefined) { return this.selected(row, part.column); }
    return this.selected(this.sheet.rows.position(merge.row), this.sheet.columns.position(merge.column));
  }

  private textAlign(style: DesktopWorkbookCell | undefined): TextAlign {
    if (style?.horizontal === 'center') { return TextAlign.Center; }
    if (style?.horizontal === 'right') { return TextAlign.End; }
    return TextAlign.Start;
  }

  private cellAlign(style: DesktopWorkbookCell | undefined): Alignment {
    if (style?.vertical === 'top') { return Alignment.TopStart; }
    if (style?.vertical === 'bottom') { return Alignment.BottomStart; }
    return Alignment.Start;
  }

  private textSize(style: DesktopWorkbookTextStyle | undefined): number {
    return (style?.fontSize ?? 13) * this.ratio();
  }

  private textDecoration(style: DesktopWorkbookTextStyle | undefined): TextDecorationType {
    if (style?.strike) { return TextDecorationType.LineThrough; }
    return style?.underline ? TextDecorationType.Underline : TextDecorationType.None;
  }

  private sheetBorderWidth(edge: DesktopWorkbookBorder | undefined, visible: boolean): number {
    if (!visible) { return 0; }
    if (edge === undefined) { return 0.5; }
    return (edge.style === 5 || edge.style === 6 ? 2 : edge.style === 1 ? 0.5 : 1) * this.ratio();
  }

  private sheetBorderStyle(edge: DesktopWorkbookBorder | undefined): BorderStyle {
    if (edge?.style === 3) { return BorderStyle.Dashed; }
    return edge?.style === 4 ? BorderStyle.Dotted : BorderStyle.Solid;
  }

  private partEdge(row: number, part: DesktopGridPart, top: boolean): boolean {
    const merge = part.merge;
    const axis = this.sheet?.rows;
    return merge === undefined || axis === undefined ||
      row === (top ? axis.position(merge.row) : axis.position(merge.row + merge.rows) - 1);
  }

  private focusKeyboard(): void {
    clearTimeout(this.focusTimer);
    // Wait for the dock to settle its focus after the cell's pointer event.
    this.focusTimer = setTimeout((): void => {
      try { this.getUIContext().getFocusController().requestFocus(this.keyboardId()); } catch (_) {}
    }, 16);
  }

  private async copy(value: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
    } catch (_) {}
  }

  private showCellMenu(row: number, column: number): void {
    if (!this.selected(row, column)) { this.select(row, column, false); }
    this.menuCell = String(row) + ':' + String(column);
  }

  private gridKey(event: KeyEvent): boolean {
    // Keep the keyboard modifier when a pointer event does not carry it.
    const shiftKey = event.keyCode === KeyCode.KEYCODE_SHIFT_LEFT || event.keyCode === KeyCode.KEYCODE_SHIFT_RIGHT;
    if (shiftKey || event.keyCode === KeyCode.KEYCODE_META_LEFT || event.keyCode === KeyCode.KEYCODE_META_RIGHT ||
      event.keyCode === KeyCode.KEYCODE_CTRL_LEFT || event.keyCode === KeyCode.KEYCODE_CTRL_RIGHT) {
      const held = shiftKey ? this.heldShiftKeys : this.heldSelectionKeys;
      if (event.type === KeyType.Down) { held.add(event.keyCode); }
      else { held.delete(event.keyCode); }
      return false;
    }
    if (event.type !== KeyType.Down || event.getModifierKeyState?.(['Alt']) === true) {
      return false;
    }
    if (event.getModifierKeyState?.(['Ctrl']) === true || event.metaKey === 1 || this.heldSelectionKeys.size > 0) {
      if (event.keyCode !== KeyCode.KEYCODE_C) { return false; }
      this.copySelection();
      event.stopPropagation();
      return true;
    }
    const shift = event.getModifierKeyState?.(['Shift']) === true || this.heldShiftKeys.size > 0;
    let row = this.selectedRow;
    let column = this.selectedColumn;
    const merge = this.cellMerge(row, column);
    switch (event.keyCode) {
      case KeyCode.KEYCODE_MENU: this.showCellMenu(row, column); return true;
      case KeyCode.KEYCODE_F10:
        if (shift) { this.showCellMenu(row, column); return true; }
        return false;
      case KeyCode.KEYCODE_DPAD_LEFT: column--; break;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        column = merge === undefined ? column + 1 : this.sheet?.columns.position(merge.column + merge.columns) ?? column + 1;
        break;
      case KeyCode.KEYCODE_DPAD_UP: row--; break;
      case KeyCode.KEYCODE_DPAD_DOWN:
        row = merge === undefined ? row + 1 : this.sheet?.rows.position(merge.row + merge.rows) ?? row + 1;
        break;
      default: return false;
    }
    this.select(row, column, false, shift);
    this.revealSelection();
    event.stopPropagation();
    return true;
  }

  @Builder
  private CopyMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.desktop_table_copy'), startIcon: $r('app.media.dsh_session_copy') })
        .key('desktopDelimitedCopyCell').onChange((_selected: boolean): void => { this.copySelection(true); })
    }
  }

  @Builder
  private CellText(row: number, part: DesktopGridPart, cell?: DesktopWorkbookCell) {
    Text() {
      if (cell !== undefined && cell.runs.length > 0 && !cell.verticalText && this.drawsCellText(row, part, cell)) {
        ForEach(cell.runs, (run: DesktopWorkbookRun) => {
          Span(run.text).fontSize(this.textSize(run.decoration.fontSize === undefined ? cell.decoration : run.decoration))
            .fontFamily(run.decoration.fontFamily ?? cell.decoration.fontFamily ?? '')
            .fontColor(run.decoration.foreground ?? cell.decoration.foreground ?? $r('sys.color.font_primary'))
            .fontWeight((run.decoration.bold ?? cell.decoration.bold) ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle((run.decoration.italic ?? cell.decoration.italic) ? FontStyle.Italic : FontStyle.Normal)
            .decoration({ type: this.textDecoration(run.decoration) })
        }, (_run: DesktopWorkbookRun, index: number): string => String(index))
      } else {
        Span(this.drawsCellText(row, part, cell) ? this.cellText(row, part, cell) : '')
      }
    }.fontSize(this.textSize(cell?.decoration)).maxLines(cell?.wrap || cell?.verticalText ? 12 : 1)
      .fontFamily(cell?.decoration.fontFamily ?? '')
      .fontWeight(cell?.decoration.bold ? FontWeight.Bold : FontWeight.Normal)
      .fontStyle(cell?.decoration.italic ? FontStyle.Italic : FontStyle.Normal)
      .decoration({ type: this.textDecoration(cell?.decoration) })
      .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(this.textAlign(cell))
      .fontColor(cell?.decoration.foreground ?? $r('sys.color.font_primary')).width('100%')
      .rotate({ angle: -(cell?.rotation ?? 0) })
      .key('desktopDelimitedCell-' + (this.rowNumber(row) + 1) + '-' + desktopTableColumn(this.columnNumber(part.column)))
      .accessibilitySelected(this.partSelected(row, part))
  }

  @Builder
  private DataCell(row: number, part: DesktopGridPart, style?: DesktopWorkbookCell) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      if (this.sheet === undefined) {
        Text(this.cell(row, part.column)).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary')).width('100%')
          .key('desktopDelimitedCell-' + (row + 1) + '-' + desktopTableColumn(part.column))
          .accessibilitySelected(this.selected(row, part.column))
      } else {
        this.CellText(row, part, style)
      }
    }.width(this.columnOffset(part.end) - this.columnOffset(part.column)).height(this.rowHeight(row))
      .align(this.cellAlign(style)).clip(true).borderRadius(0).focusOnTouch(false)
      .padding({ left: 5, right: 5 })
      .border({
        width: { top: this.sheetBorderWidth(style?.top, style?.top !== undefined && this.partEdge(row, part, true)),
          left: this.sheetBorderWidth(style?.left, style?.left !== undefined), right: this.sheetBorderWidth(style?.right, true),
          bottom: this.sheetBorderWidth(style?.bottom, this.partEdge(row, part, false)) },
        color: { top: style?.top?.color ?? $r('app.color.workspace_border'),
          left: style?.left?.color ?? $r('app.color.workspace_border'),
          right: style?.right?.color ?? $r('app.color.workspace_border'),
          bottom: style?.bottom?.color ?? $r('app.color.workspace_border') },
        style: { top: this.sheetBorderStyle(style?.top), left: this.sheetBorderStyle(style?.left),
          right: this.sheetBorderStyle(style?.right), bottom: this.sheetBorderStyle(style?.bottom) }
      })
      .backgroundColor(this.partSelected(row, part) && style?.background === undefined ?
        $r('app.color.workspace_selection') : style?.background ?? $r('app.color.workspace_canvas'))
      .overlay(this.CellSelectionOverlay(row, part, style))
      .onClick((event: ClickEvent): void => { this.chooseClickedCell(event, row, part.column, false); })
      .onMouse((event: MouseEvent): void => {
        if (event.button === MouseButton.Right) {
          if (event.action === MouseAction.Release) { this.showCellMenu(row, part.column); }
          event.stopPropagation();
        }
      })
      .priorityGesture(LongPressGesture({ duration: 420 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
        .onAction((): void => { this.showCellMenu(row, part.column); }))
      .bindContextMenu(this.menuCell === String(row) + ':' + String(part.column), this.CopyMenu(), {
        placement: Placement.BottomLeft, systemMaterial: desktopMenuOptions(Placement.BottomLeft).systemMaterial,
        onDisappear: (): void => { this.menuCell = ''; }
      })
  }

  @Builder
  private CellSelectionOverlay(row: number, part: DesktopGridPart, style?: DesktopWorkbookCell) {
    if (style?.background !== undefined && this.partSelected(row, part)) {
      Column().width('100%').height('100%').backgroundColor(0x24468BEA)
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
    }
  }

  @Builder
  private SheetHeader(text: string, width: number, height: number, selected: boolean, row: number, column: number) {
    Text(text).fontColor($r('sys.color.font_secondary')).fontSize(12 * this.ratio()).textAlign(TextAlign.Center)
      .width(width).height(height)
      .backgroundColor(selected ? $r('app.color.workspace_selection') : $r('app.color.workspace_panel'))
      .border({ width: { right: 0.5, bottom: 0.5 }, color: $r('app.color.workspace_border') })
      .key(row >= 0 ? 'desktopSpreadsheetRow-' + text : column >= 0 ? 'desktopSpreadsheetColumn-' + text :
        'desktopSpreadsheetSelectAll')
      .onClick((event: ClickEvent): void => { this.chooseClickedCell(event, row, column, true); })
      .onMouse((event: MouseEvent): void => {
        if (event.button === MouseButton.Right && event.action === MouseAction.Release && (row >= 0 || column >= 0)) {
          if (!this.fullBandSelected(row, column)) { this.selectHeaders(row, column); }
          event.stopPropagation();
        }
      })
  }

  private fullBandSelected(row: number, column: number): boolean {
    const contains = (range: DesktopSpreadsheetRange): boolean => row >= 0 ?
      row >= range.firstRow && row <= range.lastRow && range.firstColumn === 0 && range.lastColumn === this.columnCount() - 1 :
      column >= range.firstColumn && column <= range.lastColumn && range.firstRow === 0 && range.lastRow === this.rowCount() - 1;
    return contains(this.selectedRange) ||
      this.earlierRanges.some((area: DesktopSpreadsheetSelectionArea): boolean => contains(area.range));
  }

  @Builder
  private VirtualColumns(row: number, columns: number[], pinned: boolean) {
    if (!pinned && (columns[0] ?? 0) > 0) {
      Blank().width(this.columnOffset(columns[0] ?? 0))
    }
    if (row < 0) {
      ForEach(columns, (column: number): void => {
        this.SheetHeader(desktopTableColumn(this.columnNumber(column)),
          this.columnOffset(column + 1) - this.columnOffset(column), this.headerHeight(),
          this.bandSelected(column, false), -1, column)
      }, (column: number): string => String(column))
    } else {
      ForEach(this.parts(row, columns), (part: DesktopGridPart): void => {
        this.DataCell(row, part, this.cellStyle(row, part.column))
      }, (part: DesktopGridPart): string => String(part.column) + ':' + String(part.end))
    }
  }

  private bandHeight(row: number): number { return row < 0 ? this.headerHeight() : this.rowHeight(row); }

  @Builder
  private GridBand(row: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        Blank().width(this.rowHeaderWidth())
        this.VirtualColumns(row, this.columns, false)
      }.width(this.measuredWidth()).height(this.bandHeight(row)).justifyContent(FlexAlign.Start)
      Row() {
        if (row < 0) {
          this.SheetHeader('', this.rowHeaderWidth(), this.headerHeight(), false, -1, -1)
        } else {
          this.SheetHeader(String(this.rowNumber(row) + 1), this.rowHeaderWidth(), this.rowHeight(row),
            this.bandSelected(row, true), row, -1)
        }
        this.VirtualColumns(row, this.pinnedColumns, true)
      }.width(this.rowHeaderWidth() + this.columnOffset(this.pinnedColumns.length)).height(this.bandHeight(row))
        .justifyContent(FlexAlign.Start).offset({ x: this.scrollX }).zIndex(1)
        .border({ width: { right: this.pinnedColumns.length > 0 ? 1 : 0 }, color: '#b5b5b5' })
    }.width(this.measuredWidth()).height(this.bandHeight(row))
  }

  @Builder
  private FormulaNotice() {
    Text($r('app.string.desktop_table_formula_warning')).fontSize(12).padding(8).constraintSize({ maxWidth: 250 })
      .fontColor($r('sys.color.font_primary')).key('desktopWorkbookFormulaNotice')
  }

  build() {
    Column() {
      Row({ space: 0 }) {
        TextInput({ text: this.rangeAddress() })
          .width(this.sheet === undefined ? 58 : 99).height(this.sheet === undefined ? 32 : 28)
          .padding(0).backgroundColor(Color.Transparent).borderRadius(6)
          .fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
          .caretColor(Color.Transparent).enableKeyboardOnFocus(false).focusable(true)
          .key('desktopDelimitedAddress').id(this.keyboardId())
          .focusBox({ strokeWidth: LengthMetrics.vp(0) })
          .onWillInsert((): boolean => false)
          .onWillDelete((): boolean => false)
          .onBlur((): void => { this.clearModifiers(); })
          .onKeyPreIme((event: KeyEvent): boolean => this.gridKey(event))
        if (this.sheet === undefined) {
          Text('fx').fontStyle(FontStyle.Italic).fontSize(15).width(32).textAlign(TextAlign.Center)
            .fontColor($r('sys.color.font_secondary'))
        } else {
          Image($r('app.media.dsh_spreadsheet_fx')).width(18).height(18).supportSvg2(true)
            .margin({ left: 12, right: 12 }).accessibilityLevel('no')
        }
        if (this.formulas && this.sheet !== undefined) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_quota_warning_outline')).width(14).height(14).supportSvg2(true)
          }.width(20).height(20).padding(0).borderRadius(4).focusOnTouch(false).key('desktopWorkbookFormulaWarning')
            .accessibilityText($r('app.string.desktop_table_formula_warning'))
            .onClick((): void => { this.formulaNoticeVisible = !this.formulaNoticeVisible; })
            .bindPopup(this.formulaNoticeVisible, { builder: this.FormulaNotice(), placement: Placement.Bottom,
              enableArrow: false, autoCancel: true,
              onStateChange: (event: PopupStateChangeParam): void => {
                if (!event.isVisible) { this.formulaNoticeVisible = false; }
              } })
        }
        Text(this.formulaValue()).fontSize(13).maxLines(this.sheet === undefined ? 3 : 1).copyOption(CopyOptions.LocalDevice)
          .padding(6).layoutWeight(1).key('desktopDelimitedFormulaValue').textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
      }.width('100%').constraintSize({ minHeight: this.sheet === undefined ? 32 : 28 })
        .backgroundColor($r('app.color.workspace_panel'))
        .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      Scroll(this.horizontal) {
        Column() {
          this.GridBand(-1)
          if (this.pinnedRows.length > 0 && this.pinnedHeight > 0) {
            Column() {
              ForEach(this.pinnedRows, (row: number): void => {
                this.GridBand(row)
              }, (row: number): string => String(row))
            }.width(this.measuredWidth()).height(this.pinnedHeight).clip(true)
              .border({ width: { bottom: 1 }, color: '#b5b5b5' })
          }
          List({ scroller: this.vertical }) {
            LazyForEach(this.data, (row: number): void => {
              ListItem() { this.GridBand(row) }
            }, (row: number): string => String(row))
          }.width('100%').layoutWeight(1).cachedCount(3).scrollBar(BarState.Off)
        }.width(this.measuredWidth()).height('100%')
      }.width('100%').layoutWeight(1).scrollable(ScrollDirection.Horizontal).align(Alignment.TopStart)
        .onMouse((event: MouseEvent): void => { this.rememberPointer(event); })
        .priorityGesture(PanGesture({ direction: PanDirection.All, distance: 4 })
          .allowedTypes([SourceTool.MOUSE, SourceTool.TOUCHPAD])
          .onActionStart((event: GestureEvent): void => { this.beginDrag(event); })
          .onActionUpdate((event: GestureEvent): void => { this.updateDrag(event); })
          .onActionEnd((): void => {
            if (this.dragMode) { this.focusKeyboard(); }
            this.finishDrag();
          })
          .onActionCancel((): void => { this.finishDrag(); }))
        .onDidScroll((_offset: number, _state: ScrollState): void => { this.measureColumns(this.horizontal.currentOffset().xOffset); })
        .onAreaChange((_old: Area, area: Area): void => {
          this.viewportArea = area;
          this.viewportHeight = Number(area.height);
          const width = Number(area.width);
          if (width > 0) { this.viewportWidth = width; this.measureColumns(this.scrollX); }
          this.measureFrozen();
        })
      if (this.sheet === undefined) {
        Row() {
          Text(this.format).fontSize(12).fontWeight(FontWeight.Medium).padding({ left: 12, right: 12 })
            .fontColor($r('sys.color.font_primary')).height(28).key('desktopDelimitedSheetName')
            .backgroundColor($r('app.color.workspace_canvas'))
        }.width('100%').height(28).backgroundColor($r('app.color.workspace_panel'))
          .border({ width: { top: 0.5 }, color: $r('app.color.workspace_border') })
      }
    }.width('100%').height('100%').key('desktopDelimitedPreview')
      .backgroundColor($r('app.color.workspace_canvas'))
  }
}
