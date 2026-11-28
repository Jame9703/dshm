import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { LengthMetrics } from '@kit.ArkUI';
import { DesktopDelimitedTable, desktopTableColumn } from './DesktopDelimitedTable';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopWorkbookBorder, DesktopWorkbookCell, DesktopWorkbookMerge, DesktopWorkbookRun, DesktopWorkbookSheet,
  DesktopWorkbookTextStyle } from './DesktopWorkbookModel';
import { desktopSpreadsheetLogicalRange, desktopSpreadsheetRange, DesktopSpreadsheetRange } from './DesktopSpreadsheetSelection';
import { desktopWorkbookClipboardValue, desktopWorkbookRangeToHtml } from './DesktopWorkbookClipboard';

const ROW_HEIGHT: number = 24;
const COLUMN_WIDTH: number = 100;
const ROW_HEADER: number = 40;

export interface DesktopSheetSelection {
  row: number;
  column: number;
  anchorRow: number;
  anchorColumn: number;
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
}

class DesktopTableRows implements IDataSource {
  private count: number = 0;
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.count; }
  getData(index: number): number { return index; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((other: DataChangeListener): boolean => other !== listener);
  }
  reset(count: number): void {
    this.count = count;
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
  @State private columns: number[] = [];
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
  private focusTimer: number = -1;
  private restoreTimer: number = -1;

  aboutToAppear(): void {
    this.data.reset(this.rowCount());
    this.measureColumns(0);
    this.updateRange();
    const saved = this.initialSelection;
    if (saved !== undefined) {
      this.select(saved.row, saved.column, false);
      this.anchorRow = Math.max(0, Math.min(this.rowCount() - 1, saved.anchorRow));
      this.anchorColumn = Math.max(0, Math.min(this.columnCount() - 1, saved.anchorColumn));
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
    this.finishDrag();
    this.onSelection({ row: this.selectedRow, column: this.selectedColumn, anchorRow: this.anchorRow,
      anchorColumn: this.anchorColumn,
      scrollX: this.horizontal.currentOffset().xOffset, scrollY: this.vertical.currentOffset().yOffset });
  }

  private keyboardId(): string { return 'desktopDelimitedFocus-' + this.focusScope; }

  private rowCount(): number { return this.sheet?.rows.count ?? this.table.rows.length; }
  private columnCount(): number { return this.sheet?.columns.count ?? this.table.columns; }
  private rowNumber(row: number): number { return this.sheet?.rows.logical(row) ?? row; }
  private columnNumber(column: number): number { return this.sheet?.columns.logical(column) ?? column; }
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
    const style = this.cellStyle(this.anchorRow, this.anchorColumn);
    const formula = style?.formula ?? '';
    if (formula) { return formula.startsWith('=') ? formula : '=' + formula; }
    return style?.display.endsWith('%') ? style.display : style?.value ?? this.cell(this.anchorRow, this.anchorColumn);
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

  private measureZoom(): void {
    this.measureColumns(this.horizontal.currentOffset().xOffset);
    this.revealSelection();
  }

  private measureColumns(offset: number): void {
    const x = Math.max(0, offset);
    if (this.scrollX !== x) { this.scrollX = x; }
    const start = this.columnAt(x);
    const end = Math.min(this.columnCount(), this.columnAt(x + this.viewportWidth) + 2);
    if (this.columns.length === end - start && this.columns[0] === start) { return; }
    const next: number[] = [];
    for (let column = start; column < end; column++) { next.push(column); }
    this.columns = next;
  }

  private select(row: number, column: number, focus: boolean, extend: boolean = false): void {
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

  private selectHeaders(row: number, column: number, extend: boolean = false): void {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    if (row < 0) { this.anchorRow = 0; }
    else if (!extend) { this.anchorRow = row; }
    if (column < 0) { this.anchorColumn = 0; }
    else if (!extend) { this.anchorColumn = column; }
    this.selectedRow = row < 0 ? this.rowCount() - 1 : row;
    this.selectedColumn = column < 0 ? this.columnCount() - 1 : column;
    this.updateRange();
  }

  private rememberPointer(event: MouseEvent): void {
    if (event.button !== MouseButton.Left) { return; }
    if (event.action === MouseAction.Press) {
      const area = this.viewportArea;
      this.pointerDown = {
        x: area === undefined ? event.x : event.windowX - Number(area.globalPosition.x),
        y: area === undefined ? event.y : event.windowY - Number(area.globalPosition.y),
        extend: event.getModifierKeyState?.(['Shift']) === true
      };
    } else if (event.action === MouseAction.Release) {
      this.pointerDown = undefined;
    }
  }

  private beginDrag(event: GestureEvent): void {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    const pointer = event.fingerInfos?.[0] ?? event.fingerList[0];
    if (pointer === undefined) { return; }
    const origin: DesktopGridPoint = this.pointerDown ??
      { x: this.dragLocalX(pointer) - event.offsetX, y: this.dragLocalY(pointer) - event.offsetY,
        extend: event.getModifierKeyState?.(['Shift']) === true };
    const headerX = origin.x < this.rowHeaderWidth();
    const headerY = origin.y < this.headerHeight();
    const row = this.rowAt(origin.y - this.headerHeight() + this.vertical.currentOffset().yOffset - 0.000001);
    const column = this.columnAt(origin.x - this.rowHeaderWidth() + this.horizontal.currentOffset().xOffset - 0.000001);
    if (headerX && headerY) {
      this.selectHeaders(-1, -1);
      this.dragMode = 'all';
    } else if (headerX || headerY) {
      this.selectHeaders(headerY ? -1 : row, headerX ? -1 : column, origin.extend);
      this.dragMode = headerX ? 'rows' : 'columns';
    } else {
      this.select(row, column, false, origin.extend);
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
    const nextX = mode === 'rows' ? scrollX :
      Math.max(0, Math.min(this.columnOffset(this.columnCount()) - width, scrollX + this.edgeDelta(x, width, 60 * this.ratio())));
    const nextY = mode === 'columns' ? scrollY :
      Math.max(0, Math.min(this.rowsHeight() - height, scrollY + this.edgeDelta(y, height, 20 * this.ratio())));
    if (nextX !== scrollX) { this.horizontal.scrollTo({ xOffset: nextX, yOffset: 0, animation: false }); }
    if (nextY !== scrollY) { this.vertical.scrollTo({ xOffset: 0, yOffset: nextY, animation: false }); }
    const row = mode === 'columns' ? this.rowCount() - 1 : this.rowAt(nextY + Math.max(0, Math.min(height, y)) - 0.000001);
    const column = mode === 'rows' ? this.columnCount() - 1 :
      this.columnAt(nextX + Math.max(0, Math.min(width, x)) - 0.000001);
    this.extendTo(row, column);
  }

  private finishDrag(): void {
    this.dragMode = '';
    this.pointerDown = undefined;
  }

  private revealSelection(): void {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    this.vertical.scrollToIndex(this.selectedRow, false, ScrollAlign.AUTO);
    const x = this.columnOffset(this.selectedColumn);
    const end = this.columnOffset(this.selectedColumn + 1) + this.rowHeaderWidth();
    if (x < this.scrollX || end > this.scrollX + this.viewportWidth) {
      this.horizontal.scrollTo({ xOffset: x, yOffset: 0, animation: false });
    }
  }

  private selected(row: number, column: number): boolean {
    const range = this.selectedRange;
    return row >= range.firstRow && row <= range.lastRow && column >= range.firstColumn && column <= range.lastColumn;
  }

  private plainRange(range: DesktopSpreadsheetRange, sheet?: DesktopWorkbookSheet): string {
    const lines: string[] = [];
    const single = range.firstRow === range.lastRow && range.firstColumn === range.lastColumn;
    for (let row = range.firstRow; row <= range.lastRow; row++) {
      const fields: string[] = [];
      for (let column = range.firstColumn; column <= range.lastColumn; column++) {
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

  private async copySelection(): Promise<void> {
    if (this.rowCount() === 0 || this.columnCount() === 0) { return; }
    const sheet = this.sheet;
    if (sheet === undefined) {
      await this.copy(this.plainRange(this.selectedRange));
      return;
    }
    const range = desktopSpreadsheetLogicalRange(sheet, this.selectedRange);
    const plain = this.plainRange(range, sheet);
    const html = desktopWorkbookRangeToHtml(sheet, range.firstRow, range.firstColumn, range.lastRow, range.lastColumn);
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

  private parts(row: number): DesktopGridPart[] {
    const parts: DesktopGridPart[] = [];
    const end = (this.columns[this.columns.length - 1] ?? -1) + 1;
    for (let start = this.columns[0] ?? end; start < end;) {
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
    if (event.type !== KeyType.Down || event.metaKey === 1 || event.getModifierKeyState?.(['Alt']) === true) {
      return false;
    }
    if (event.getModifierKeyState?.(['Ctrl']) === true) {
      if (event.keyCode !== KeyCode.KEYCODE_C) { return false; }
      this.copySelection();
      event.stopPropagation();
      return true;
    }
    const shift = event.getModifierKeyState?.(['Shift']) === true;
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
        .key('desktopDelimitedCopyCell').onChange((_selected: boolean): void => { this.copySelection(); })
    }
  }

  @Builder
  private CellText(row: number, part: DesktopGridPart, cell?: DesktopWorkbookCell) {
    Text() {
      if (cell !== undefined && cell.runs.length > 0 && !cell.verticalText &&
        this.alignsCell(row, part.merge, cell.vertical)) {
        ForEach(cell.runs, (run: DesktopWorkbookRun) => {
          Span(run.text).fontSize(this.textSize(run.decoration.fontSize === undefined ? cell.decoration : run.decoration))
            .fontFamily(run.decoration.fontFamily ?? cell.decoration.fontFamily ?? '')
            .fontColor(run.decoration.foreground ?? cell.decoration.foreground ?? $r('sys.color.font_primary'))
            .fontWeight((run.decoration.bold ?? cell.decoration.bold) ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle((run.decoration.italic ?? cell.decoration.italic) ? FontStyle.Italic : FontStyle.Normal)
            .decoration({ type: this.textDecoration(run.decoration) })
        }, (_run: DesktopWorkbookRun, index: number): string => String(index))
      } else {
        Span(this.cellText(row, part, cell))
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
      .onClick((event: ClickEvent): void => {
        this.select(row, part.column, true, event.getModifierKeyState?.(['Shift']) === true);
      })
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
      .onClick((event: ClickEvent): void => {
        this.selectHeaders(row, column, event.getModifierKeyState?.(['Shift']) === true);
        this.focusKeyboard();
      })
  }

  @Builder
  private VirtualColumns(row: number) {
    if ((this.columns[0] ?? 0) > 0) {
      Blank().width(this.columnOffset(this.columns[0] ?? 0))
    }
    if (row < 0) {
      ForEach(this.columns, (column: number): void => {
        this.SheetHeader(desktopTableColumn(this.columnNumber(column)),
          this.columnOffset(column + 1) - this.columnOffset(column), this.headerHeight(),
          column >= this.selectedRange.firstColumn && column <= this.selectedRange.lastColumn, -1, column)
      }, (column: number): string => String(column))
    } else {
      ForEach(this.parts(row), (part: DesktopGridPart): void => {
        this.DataCell(row, part, this.cellStyle(row, part.column))
      }, (part: DesktopGridPart): string => String(part.column) + ':' + String(part.end))
    }
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
          Row() {
            Stack() { this.SheetHeader('', this.rowHeaderWidth(), this.headerHeight(), false, -1, -1) }
              .width(this.rowHeaderWidth()).offset({ x: this.scrollX }).zIndex(1)
            this.VirtualColumns(-1)
          }.width(this.measuredWidth()).justifyContent(FlexAlign.Start)
          List({ scroller: this.vertical }) {
            LazyForEach(this.data, (row: number): void => {
              ListItem() {
                Row() {
                  Stack() {
                    this.SheetHeader(String(this.rowNumber(row) + 1), this.rowHeaderWidth(), this.rowHeight(row),
                      row >= this.selectedRange.firstRow && row <= this.selectedRange.lastRow, row, -1)
                  }.width(this.rowHeaderWidth()).offset({ x: this.scrollX }).zIndex(1)
                  this.VirtualColumns(row)
                }.width(this.measuredWidth()).height(this.rowHeight(row)).justifyContent(FlexAlign.Start)
              }
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
