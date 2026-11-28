import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { LengthMetrics } from '@kit.ArkUI';
import { DesktopDelimitedTable, desktopTableColumn } from './DesktopDelimitedTable';
import { desktopMenuOptions } from './DesktopMenuOptions';

const ROW_HEIGHT: number = 24;
const COLUMN_WIDTH: number = 100;
const ROW_HEADER: number = 40;

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
  @Prop format: string = 'CSV';
  @Prop focusScope: string = '';
  @State private selectedRow: number = 0;
  @State private selectedColumn: number = 0;
  @State private columns: number[] = [];
  @State private scrollX: number = 0;
  @State private menuCell: string = '';
  private readonly data = new DesktopTableRows();
  private readonly horizontal = new Scroller();
  private readonly vertical = new Scroller();
  private viewportWidth: number = 360;
  private focusTimer: number = -1;

  aboutToAppear(): void {
    this.data.reset(this.table.rows.length);
    this.measureColumns(0);
  }

  aboutToDisappear(): void { clearTimeout(this.focusTimer); }

  private keyboardId(): string { return 'desktopDelimitedFocus-' + this.focusScope; }

  private cell(row: number, column: number): string { return this.table.rows[row]?.[column] ?? ''; }

  private measuredWidth(): number { return this.table.columns * COLUMN_WIDTH + ROW_HEADER; }

  private measureColumns(offset: number): void {
    const x = Math.max(0, offset);
    if (this.scrollX !== x) { this.scrollX = x; }
    const start = Math.min(this.table.columns - 1, Math.floor(x / COLUMN_WIDTH));
    const end = Math.min(this.table.columns, Math.ceil((x + this.viewportWidth) / COLUMN_WIDTH) + 1);
    if (this.columns.length === end - start && this.columns[0] === start) { return; }
    const next: number[] = [];
    for (let column = start; column < end; column++) { next.push(column); }
    this.columns = next;
  }

  private select(row: number, column: number, focus: boolean): void {
    this.selectedRow = Math.min(this.table.rows.length - 1, Math.max(0, row));
    this.selectedColumn = Math.min(this.table.columns - 1, Math.max(0, column));
    if (focus) { this.focusKeyboard(); }
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
    this.select(row, column, false);
    this.menuCell = String(row) + ':' + String(column);
  }

  private gridKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || event.metaKey === 1 || event.getModifierKeyState?.(['Alt']) === true) {
      return false;
    }
    if (event.getModifierKeyState?.(['Ctrl']) === true) {
      if (event.keyCode !== KeyCode.KEYCODE_C) { return false; }
      this.copy(this.cell(this.selectedRow, this.selectedColumn));
      event.stopPropagation();
      return true;
    }
    const shift = event.getModifierKeyState?.(['Shift']) === true;
    let row = this.selectedRow;
    let column = this.selectedColumn;
    switch (event.keyCode) {
      case KeyCode.KEYCODE_MENU: this.showCellMenu(row, column); return true;
      case KeyCode.KEYCODE_F10:
        if (shift) { this.showCellMenu(row, column); return true; }
        return false;
      case KeyCode.KEYCODE_DPAD_LEFT: column--; break;
      case KeyCode.KEYCODE_DPAD_RIGHT: column++; break;
      case KeyCode.KEYCODE_DPAD_UP: row--; break;
      case KeyCode.KEYCODE_DPAD_DOWN: row++; break;
      default: return false;
    }
    this.select(row, column, false);
    this.vertical.scrollToIndex(this.selectedRow, false, ScrollAlign.AUTO);
    const left = this.selectedColumn * COLUMN_WIDTH + ROW_HEADER;
    const visibleWidth = Math.max(1, this.viewportWidth);
    if (left < this.scrollX + ROW_HEADER || left + COLUMN_WIDTH > this.scrollX + visibleWidth) {
      this.horizontal.scrollTo({ xOffset: Math.max(0, left - ROW_HEADER), yOffset: 0, animation: false });
    }
    event.stopPropagation();
    return true;
  }

  @Builder
  private CopyMenu(row: number, column: number) {
    Menu() {
      MenuItem({ content: $r('app.string.desktop_table_copy'), startIcon: $r('app.media.dsh_session_copy') })
        .key('desktopDelimitedCopyCell').onChange((_selected: boolean): void => { this.copy(this.cell(row, column)); })
    }
  }

  @Builder
  private DataCell(row: number, column: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Text(this.cell(row, column)).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('sys.color.font_primary')).width('100%')
        .key('desktopDelimitedCell-' + (row + 1) + '-' + desktopTableColumn(column))
        .accessibilitySelected(row === this.selectedRow && column === this.selectedColumn)
    }.width(COLUMN_WIDTH).height(ROW_HEIGHT).borderRadius(0).focusOnTouch(false)
      .padding({ left: 5, right: 5 })
      .border({ width: { right: 0.5, bottom: 0.5 }, color: $r('app.color.workspace_border') })
      .backgroundColor(row === this.selectedRow && column === this.selectedColumn ?
        $r('app.color.workspace_selection') : $r('app.color.workspace_canvas'))
      .onClick((): void => { this.select(row, column, true); })
      .onMouse((event: MouseEvent): void => {
        if (event.button === MouseButton.Right) {
          if (event.action === MouseAction.Release) { this.showCellMenu(row, column); }
          event.stopPropagation();
        }
      })
      .priorityGesture(LongPressGesture({ duration: 420 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
        .onAction((): void => { this.showCellMenu(row, column); }))
      .bindContextMenu(this.menuCell === String(row) + ':' + String(column), this.CopyMenu(row, column), {
        placement: Placement.BottomLeft, systemMaterial: desktopMenuOptions(Placement.BottomLeft).systemMaterial,
        onDisappear: (): void => { this.menuCell = ''; }
      })
  }

  @Builder
  private SheetHeader(text: string, width: number, selected: boolean) {
    Text(text).fontColor($r('sys.color.font_secondary')).fontSize(12).textAlign(TextAlign.Center)
      .width(width).height(ROW_HEIGHT)
      .backgroundColor(selected ? $r('app.color.workspace_selection') : $r('app.color.workspace_panel'))
      .border({ width: { right: 0.5, bottom: 0.5 }, color: $r('app.color.workspace_border') })
  }

  @Builder
  private VirtualColumns(row: number) {
    if ((this.columns[0] ?? 0) > 0) {
      Blank().width((this.columns[0] ?? 0) * COLUMN_WIDTH)
    }
    ForEach(this.columns, (column: number): void => {
      if (row < 0) { this.SheetHeader(desktopTableColumn(column), COLUMN_WIDTH, column === this.selectedColumn) }
      else { this.DataCell(row, column) }
    }, (column: number): string => String(column))
  }

  build() {
    Column() {
      Row({ space: 0 }) {
        TextInput({ text: desktopTableColumn(this.selectedColumn) + String(this.selectedRow + 1) })
          .width(58).height(32).padding(0).backgroundColor(Color.Transparent).borderRadius(6)
          .fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
          .caretColor(Color.Transparent).enableKeyboardOnFocus(false).focusable(true)
          .key('desktopDelimitedAddress').id(this.keyboardId())
          .focusBox({ strokeWidth: LengthMetrics.vp(0) })
          .onWillInsert((): boolean => false)
          .onWillDelete((): boolean => false)
          .onKeyPreIme((event: KeyEvent): boolean => this.gridKey(event))
        Text('fx').fontStyle(FontStyle.Italic).fontSize(15).width(32).textAlign(TextAlign.Center)
          .fontColor($r('sys.color.font_secondary'))
        Text(this.cell(this.selectedRow, this.selectedColumn)).fontSize(13).maxLines(3).copyOption(CopyOptions.LocalDevice)
          .padding(6).layoutWeight(1).key('desktopDelimitedFormulaValue')
          .fontColor($r('sys.color.font_primary'))
      }.width('100%').constraintSize({ minHeight: 32 }).backgroundColor($r('app.color.workspace_panel'))
        .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      Scroll(this.horizontal) {
        Column() {
          Row() {
            Stack() { this.SheetHeader('', ROW_HEADER, false) }
              .width(ROW_HEADER).offset({ x: this.scrollX }).zIndex(1)
            this.VirtualColumns(-1)
          }.width(this.measuredWidth()).justifyContent(FlexAlign.Start)
          List({ scroller: this.vertical }) {
            LazyForEach(this.data, (row: number): void => {
              ListItem() {
                Row() {
                  Stack() { this.SheetHeader(String(row + 1), ROW_HEADER, row === this.selectedRow) }
                    .width(ROW_HEADER).offset({ x: this.scrollX }).zIndex(1)
                  this.VirtualColumns(row)
                }.width(this.measuredWidth()).height(ROW_HEIGHT).justifyContent(FlexAlign.Start)
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
      Row() {
        Text(this.format).fontSize(12).fontWeight(FontWeight.Medium).padding({ left: 12, right: 12 })
          .fontColor($r('sys.color.font_primary')).height(28).key('desktopDelimitedSheetName')
          .backgroundColor($r('app.color.workspace_canvas'))
      }.width('100%').height(28).backgroundColor($r('app.color.workspace_panel'))
        .border({ width: { top: 0.5 }, color: $r('app.color.workspace_border') })
    }.width('100%').height('100%').key('desktopDelimitedPreview')
      .backgroundColor($r('app.color.workspace_canvas'))
  }
}
