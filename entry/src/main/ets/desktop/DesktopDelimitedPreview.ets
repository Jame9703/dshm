import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { LengthMetrics } from '@kit.ArkUI';
import { DesktopDelimitedTable, desktopTableColumn } from './DesktopDelimitedTable';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopWorkbookBorder, DesktopWorkbookCell, DesktopWorkbookMerge, DesktopWorkbookRun, DesktopWorkbookSheet,
  DesktopWorkbookTextStyle } from './DesktopWorkbookModel';

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

function spreadsheetHtmlText(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll('\r\n', '\n').replaceAll('\n', '<br>');
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
  @State private columns: number[] = [];
  @State private scrollX: number = 0;
  @State private menuCell: string = '';
  @State private formulaNoticeVisible: boolean = false;
  private readonly data = new DesktopTableRows();
  private readonly horizontal = new Scroller();
  private readonly vertical = new Scroller();
  private viewportWidth: number = 360;
  private focusTimer: number = -1;
  private restoreTimer: number = -1;

  aboutToAppear(): void {
    this.data.reset(this.rowCount());
    this.measureColumns(0);
    const saved = this.initialSelection;
    if (saved !== undefined) {
      this.select(saved.row, saved.column, false);
      this.anchorRow = Math.max(0, Math.min(this.rowCount() - 1, saved.anchorRow));
      this.anchorColumn = Math.max(0, Math.min(this.columnCount() - 1, saved.anchorColumn));
      this.restoreTimer = setTimeout((): void => {
        this.horizontal.scrollTo({ xOffset: saved.scrollX ?? 0, yOffset: 0, animation: false });
        this.vertical.scrollTo({ xOffset: 0, yOffset: saved.scrollY ?? 0, animation: false });
      }, 0);
    }
  }

  aboutToDisappear(): void {
    clearTimeout(this.focusTimer);
    clearTimeout(this.restoreTimer);
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
    const style = this.cellStyle(this.selectedRow, this.selectedColumn);
    const formula = style?.formula ?? '';
    if (formula) { return formula.startsWith('=') ? formula : '=' + formula; }
    return style?.display.endsWith('%') ? style.display : style?.value ?? this.cell(this.selectedRow, this.selectedColumn);
  }

  private address(row: number, column: number): string {
    return desktopTableColumn(this.columnNumber(column)) + String(this.rowNumber(row) + 1);
  }

  private rangeAddress(): string {
    const current = this.address(this.selectedRow, this.selectedColumn);
    if (this.anchorRow === this.selectedRow && this.anchorColumn === this.selectedColumn) { return current; }
    return this.address(Math.min(this.anchorRow, this.selectedRow), Math.min(this.anchorColumn, this.selectedColumn)) +
      ':' + this.address(Math.max(this.anchorRow, this.selectedRow), Math.max(this.anchorColumn, this.selectedColumn));
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
    if (focus) { this.focusKeyboard(); }
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
    return row >= Math.min(this.anchorRow, this.selectedRow) && row <= Math.max(this.anchorRow, this.selectedRow) &&
      column >= Math.min(this.anchorColumn, this.selectedColumn) && column <= Math.max(this.anchorColumn, this.selectedColumn);
  }

  private async copySelection(): Promise<void> {
    const sheet = this.sheet;
    if (sheet === undefined) {
      await this.copy(this.cell(this.selectedRow, this.selectedColumn));
      return;
    }
    const lines: string[] = [];
    const html: string[] = ['<table><tbody>'];
    const firstRow = Math.min(this.anchorRow, this.selectedRow);
    const lastRow = Math.max(this.anchorRow, this.selectedRow);
    const firstColumn = Math.min(this.anchorColumn, this.selectedColumn);
    const lastColumn = Math.max(this.anchorColumn, this.selectedColumn);
    const single = firstRow === lastRow && firstColumn === lastColumn;
    for (let row = firstRow; row <= lastRow; row++) {
      const fields: string[] = [];
      html.push('<tr>');
      for (let column = firstColumn; column <= lastColumn; column++) {
        const merge = this.cellMerge(row, column);
        if (merge !== undefined && (row > Math.max(firstRow, sheet.rows.position(merge.row)) ||
          column > Math.max(firstColumn, sheet.columns.position(merge.column)))) {
          fields.push('');
          continue;
        }
        const value = this.cell(row, column);
        fields.push(!single && (value.includes('\t') || value.includes('\n') || value.includes('\r') || value.includes('"')) ?
          '"' + value.replaceAll('"', '""') + '"' : value);
        const rows = merge === undefined ? 1 : Math.min(lastRow + 1, sheet.rows.position(merge.row + merge.rows)) - row;
        const columns = merge === undefined ? 1 :
          Math.min(lastColumn + 1, sheet.columns.position(merge.column + merge.columns)) - column;
        html.push('<td rowspan="' + rows + '" colspan="' + columns + '">' + spreadsheetHtmlText(value) + '</td>');
      }
      lines.push(fields.join('\t'));
      html.push('</tr>');
    }
    html.push('</tbody></table>');
    const plain = lines.join('\n');
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, plain);
      data.addRecord(pasteboard.MIMETYPE_TEXT_HTML, html.join(''));
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
    this.select(row, column, false, shift && this.sheet !== undefined);
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
      .backgroundColor(this.partSelected(row, part) ? $r('app.color.workspace_selection') :
        style?.background ?? $r('app.color.workspace_canvas'))
      .onClick((event: ClickEvent): void => {
        this.select(row, part.column, true, this.sheet !== undefined && event.getModifierKeyState?.(['Shift']) === true);
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
  private SheetHeader(text: string, width: number, height: number, selected: boolean) {
    Text(text).fontColor($r('sys.color.font_secondary')).fontSize(12 * this.ratio()).textAlign(TextAlign.Center)
      .width(width).height(height)
      .backgroundColor(selected ? $r('app.color.workspace_selection') : $r('app.color.workspace_panel'))
      .border({ width: { right: 0.5, bottom: 0.5 }, color: $r('app.color.workspace_border') })
  }

  @Builder
  private VirtualColumns(row: number) {
    if ((this.columns[0] ?? 0) > 0) {
      Blank().width(this.columnOffset(this.columns[0] ?? 0))
    }
    if (row < 0) {
      ForEach(this.columns, (column: number): void => {
        this.SheetHeader(desktopTableColumn(this.columnNumber(column)),
          this.columnOffset(column + 1) - this.columnOffset(column), this.headerHeight(), column === this.selectedColumn)
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
            Stack() { this.SheetHeader('', this.rowHeaderWidth(), this.headerHeight(), false) }
              .width(this.rowHeaderWidth()).offset({ x: this.scrollX }).zIndex(1)
            this.VirtualColumns(-1)
          }.width(this.measuredWidth()).justifyContent(FlexAlign.Start)
          List({ scroller: this.vertical }) {
            LazyForEach(this.data, (row: number): void => {
              ListItem() {
                Row() {
                  Stack() {
                    this.SheetHeader(String(this.rowNumber(row) + 1), this.rowHeaderWidth(), this.rowHeight(row),
                      row >= Math.min(this.anchorRow, this.selectedRow) && row <= Math.max(this.anchorRow, this.selectedRow))
                  }.width(this.rowHeaderWidth()).offset({ x: this.scrollX }).zIndex(1)
                  this.VirtualColumns(row)
                }.width(this.measuredWidth()).height(this.rowHeight(row)).justifyContent(FlexAlign.Start)
              }
            }, (row: number): string => String(row))
          }.width('100%').layoutWeight(1).cachedCount(3).scrollBar(BarState.Off)
        }.width(this.measuredWidth()).height('100%')
      }.width('100%').layoutWeight(1).scrollable(ScrollDirection.Horizontal).align(Alignment.TopStart)
        .onDidScroll((_offset: number, _state: ScrollState): void => { this.measureColumns(this.horizontal.currentOffset().xOffset); })
        .onAreaChange((_old: Area, area: Area): void => {
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
