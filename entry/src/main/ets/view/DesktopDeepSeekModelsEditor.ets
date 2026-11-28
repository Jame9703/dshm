import { image } from '@kit.ImageKit';
import { emptyModelRow, Fs, Sp } from 'appstate';
import type { PiAiModelRow } from 'appstate';
import { desktopDeepSeekCatalogProblem } from '../desktop/DesktopDeepSeekCatalog';
import { desktopPiAiModelDrop, desktopPiAiModelInsertionIndex } from '../desktop/DesktopPiAiModelOrder';
import type { DesktopPiAiModelBand, DesktopPiAiModelInsertion } from '../desktop/DesktopPiAiModelOrder';
import { PiAiModelSettingsRow } from './PiAiModelSettingsRow';

@Component
export struct DesktopDeepSeekModelsEditor {
  @Prop @Watch('syncModels') models: PiAiModelRow[] = [];
  @Prop overridden: boolean = false;
  @Prop disabled: boolean = false;
  @Prop @Watch('resetRows') draftVersion: number = 0;
  @Prop defaultContextWindow: number = 0;
  @Prop defaultMaxTokens: number = 0;
  onChange: (models: PiAiModelRow[]) => void = (): void => {};
  onReset: () => void = (): void => {};
  @State private rows: PiAiModelRow[] = [];
  @State private keys: number[] = [];
  @State private dragged: number = -1;
  @State private insertion?: DesktopPiAiModelInsertion = undefined;
  @State private preview?: image.PixelMap = undefined;
  @State private previewLeft: number = 0;
  @State private previewTop: number = 0;
  private nextKey: number = 1;
  private rowBands: Map<number, DesktopPiAiModelBand> = new Map();
  private editorArea?: Area;
  private previewWidth: number = 0;
  private previewHeight: number = 0;
  private previewOffsetX: number = 0;
  private previewOffsetY: number = 0;
  private windowOffsetX: number = 0;
  private windowOffsetY: number = 0;
  private dragVersion: number = 0;
  private focusTimer: number = -1;

  aboutToAppear(): void { this.syncModels(); }

  aboutToDisappear(): void {
    clearTimeout(this.focusTimer);
    this.cancelDrag();
  }

  private syncModels(): void {
    this.rows = this.models;
    if (this.keys.length !== this.rows.length) { this.resetRows(); }
  }

  private resetRows(): void {
    this.cancelDrag();
    this.rowBands.clear();
    this.keys = this.models.map((): number => this.nextKey++);
  }

  private emit(rows: PiAiModelRow[]): void {
    this.rows = rows;
    this.onChange(rows);
  }

  private restore(): void {
    if (this.disabled) { return; }
    this.resetRows();
    this.onReset();
  }

  private add(): void {
    if (this.disabled) { return; }
    this.keys = [...this.keys, this.nextKey++];
    this.emit([...this.rows, emptyModelRow()]);
  }

  private update(key: number, row: PiAiModelRow): void {
    const index = this.keys.indexOf(key);
    if (this.disabled || index < 0) { return; }
    const next = this.rows.slice();
    next[index] = row;
    this.emit(next);
  }

  private remove(key: number): void {
    const index = this.keys.indexOf(key);
    if (this.disabled || index < 0) { return; }
    this.cancelDrag();
    this.rowBands.delete(key);
    this.keys = this.keys.filter((value: number): boolean => value !== key);
    this.emit(this.rows.filter((_row: PiAiModelRow, position: number): boolean => position !== index));
  }

  private handleId(key: number): string { return 'desktopDeepSeekModelReorder-' + key; }

  private rowId(key: number): string { return 'desktopDeepSeekModelBody-' + key; }

  private move(key: number, target: number, after: boolean): boolean {
    const to = desktopPiAiModelInsertionIndex(this.keys, key, target, after);
    if (this.disabled || to < 0) { return false; }
    const from = this.keys.indexOf(key);
    const keys = this.keys.slice();
    const rows = this.rows.slice();
    keys.splice(from, 1);
    rows.splice(from, 1);
    keys.splice(to, 0, key);
    rows.splice(to, 0, this.rows[from]);
    this.keys = keys;
    this.emit(rows);
    return true;
  }

  private step(key: number, direction: number): void {
    if (this.dragged >= 0) { return; }
    const target = this.keys[this.keys.indexOf(key) + direction];
    if (target === undefined || !this.move(key, target, direction > 0)) { return; }
    clearTimeout(this.focusTimer);
    this.focusTimer = setTimeout((): void => {
      try { this.getUIContext().getFocusController().requestFocus(this.handleId(key)); } catch (_) {}
    }, 16);
  }

  private beginDrag(key: number, event: GestureEvent, handle: Area): void {
    const band = this.rowBands.get(key);
    const point = event.fingerInfos?.[0] ?? event.fingerList[0];
    if (this.disabled || this.dragged >= 0 || this.keys.length < 2 || band === undefined || point === undefined) { return; }
    const x = Number(handle.globalPosition.x) + point.localX;
    const y = Number(handle.globalPosition.y) + point.localY;
    this.windowOffsetX = point.globalX - x;
    this.windowOffsetY = point.globalY - y;
    this.previewOffsetX = x - event.offsetX - band.left;
    this.previewOffsetY = y - event.offsetY - band.top;
    this.previewWidth = band.width;
    this.previewHeight = band.height;
    const version = ++this.dragVersion;
    this.getUIContext().getComponentSnapshot().get(this.rowId(key)).then((preview: image.PixelMap): void => {
      if (version === this.dragVersion && this.dragged === key) { this.preview = preview; }
      else { preview.release().catch((): void => {}); }
    }).catch((): void => {});
    this.dragged = key;
    this.drag(event);
  }

  private drag(event: GestureEvent): void {
    const point = event.fingerInfos?.[0] ?? event.fingerList[0];
    const area = this.editorArea;
    if (this.dragged < 0 || area === undefined || point === undefined) { return; }
    const x = point.globalX - this.windowOffsetX;
    const y = point.globalY - this.windowOffsetY;
    this.previewLeft = x - Number(area.globalPosition.x) - this.previewOffsetX;
    this.previewTop = y - Number(area.globalPosition.y) - this.previewOffsetY;
    this.insertion = desktopPiAiModelDrop(Array.from(this.rowBands.values()), x, y, this.dragged);
  }

  private finishDrag(event: GestureEvent): void {
    this.drag(event);
    const from = this.dragged;
    const target = this.insertion;
    this.cancelDrag();
    if (target !== undefined) { this.move(from, target.key, target.after); }
  }

  private cancelDrag(): void {
    this.dragVersion++;
    this.dragged = -1;
    this.insertion = undefined;
    const preview = this.preview;
    this.preview = undefined;
    preview?.release().catch((): void => {});
  }

  @Builder
  private ModelRow(key: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        PiAiModelSettingsRow({
          initialModel: this.rows[this.keys.indexOf(key)] ?? emptyModelRow(),
          rowIndex: this.keys.indexOf(key),
          reorderHandleId: this.handleId(key),
          deepSeekMode: true,
          defaultContextWindow: this.defaultContextWindow,
          defaultMaxTokens: this.defaultMaxTokens,
          removable: true,
          editingEnabled: !this.disabled,
          onChange: (row: PiAiModelRow): void => { this.update(key, row); },
          onRemove: (): void => { this.remove(key); },
          onOrderStep: (step: number): void => { this.step(key, step); },
          onOrderBegin: (event: GestureEvent, handle: Area): void => { this.beginDrag(key, event, handle); },
          onOrderUpdate: (event: GestureEvent): void => { this.drag(event); },
          onOrderEnd: (event: GestureEvent): void => { this.finishDrag(event); },
          onOrderCancel: (): void => { this.cancelDrag(); }
        })
      }.width('100%').id(this.rowId(key)).opacity(this.dragged === key ? 0.5 : 1)
      if (this.insertion?.key === key) {
        Row({ space: 0 }) {
          Image($r('app.media.dsh_model_drop_wedge')).width(6).height(8).supportSvg2(true).draggable(false)
          Column().height(2).layoutWeight(1).backgroundColor('#4084DB')
        }.width('100%').height(8).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
          .position({ x: 0, y: this.insertion?.after ? (this.rowBands.get(key)?.height ?? 0) : -8 }).zIndex(1)
      }
    }.width('100%').onAreaChange((_before: Area, area: Area): void => {
      this.rowBands.set(key, { key: key, left: Number(area.globalPosition.x), top: Number(area.globalPosition.y),
        width: Number(area.width), height: Number(area.height) });
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: Sp.XS }) {
        Row({ space: Sp.S }) {
          Column({ space: 2 }) {
            Text($r('app.string.desktop_deepseek_catalog_title')).fontSize(Fs.SECONDARY).fontWeight(FontWeight.Medium)
            Text(this.overridden ? $r('app.string.desktop_model_catalog_customized') :
              $r('app.string.desktop_model_catalog_inherited')).key('desktopDeepSeekModelsLayer')
              .fontSize(Fs.CAPTION).fontColor($r('sys.color.font_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.overridden) {
            Button($r('app.string.desktop_model_catalog_restore'),
              { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopDeepSeekModelsRestore').fontSize(Fs.CAPTION).height(32).borderRadius(8)
              .enabled(!this.disabled).onClick((): void => { this.restore(); })
          }
        }.width('100%')
        if (this.rows.length === 0) {
          Text($r('app.string.desktop_model_catalog_empty')).key('desktopDeepSeekModelsEmpty').width('100%')
            .fontSize(Fs.CAPTION).fontColor($r('sys.color.font_secondary'))
        }
        ForEach(this.keys, (key: number): void => { this.ModelRow(key); }, (key: number): string => key.toString())
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Image($r('app.media.dsh_reference_menu_plus')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
            Text($r('app.string.desktop_deepseek_catalog_add')).fontSize(Fs.CAPTION)
          }
        }.key('desktopDeepSeekModelAdd').height(34).borderRadius(8).enabled(!this.disabled)
          .onClick((): void => { this.add(); })
        if (this.overridden && desktopDeepSeekCatalogProblem(this.rows) !== '') {
          Text(desktopDeepSeekCatalogProblem(this.rows)).key('desktopDeepSeekModelsError').width('100%')
            .fontSize(Fs.CAPTION).fontColor($r('app.color.workspace_status_error'))
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
      if (this.preview !== undefined) {
        Image(this.preview).width(this.previewWidth).height(this.previewHeight).objectFit(ImageFit.Fill)
          .position({ x: this.previewLeft, y: this.previewTop }).zIndex(2).draggable(false)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }
    }.key('desktopDeepSeekModelsEditor').width('100%')
      .onAreaChange((_before: Area, area: Area): void => { this.editorArea = area; })
  }
}
