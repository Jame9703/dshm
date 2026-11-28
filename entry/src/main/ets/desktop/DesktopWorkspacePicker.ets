import { KeyCode } from '@kit.InputKit';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { desktopWorkspacePickerEntries, filterDesktopWorkspacePicker } from './DesktopWorkspacePickerModel';
import type { DesktopWorkspacePickerEntry, DesktopWorkspacePickerRow } from './DesktopWorkspacePickerModel';

const VISIBLE_WORKSPACE_ROWS = 6;
const ROW_HEIGHT = 36;

@Component
export struct DesktopWorkspacePicker {
  @Prop @Watch('rowsChanged') rows: DesktopWorkspacePickerRow[] = [];
  @Prop selectedId: string = '';
  @Prop caption: ResourceStr = '';
  @Prop ready: boolean = false;
  onPick: (id: string) => void = (_id: string): void => {};
  onAdd: () => void = (): void => {};

  @State private opened: boolean = false;
  @State private query: string = '';
  @State private visibleRows: DesktopWorkspacePickerEntry[] = [];
  @State private highlighted: number = -1;
  private entries: DesktopWorkspacePickerEntry[] = [];
  private keyboard: boolean = false;
  private focusTimer: number = -1;
  private readonly scroller: ListScroller = new ListScroller();

  aboutToDisappear(): void { clearTimeout(this.focusTimer); }

  private rowsChanged(): void {
    if (!this.opened) { return; }
    if (!this.rows.length || !this.ready) { this.close(); return; }
    this.entries = desktopWorkspacePickerEntries(this.rows);
    this.updateResults(this.query);
  }

  private updateResults(query: string): void {
    this.query = this.rows.length > 1 ? query : '';
    this.visibleRows = filterDesktopWorkspacePicker(this.entries, this.query);
    const selected = this.visibleRows.findIndex((item: DesktopWorkspacePickerEntry): boolean =>
      item.row.id === this.selectedId);
    this.highlighted = this.visibleRows.length === 0 ? -1 : !this.query && selected >= 0 ? selected : 0;
  }

  private toggle(keyboard: boolean): void {
    if (!this.ready) { return; }
    if (this.opened) { this.close(keyboard); return; }
    if (!this.rows.length) { this.onAdd(); return; }
    this.keyboard = keyboard;
    this.entries = desktopWorkspacePickerEntries(this.rows);
    this.updateResults('');
    this.opened = true;
  }

  private close(restoreFocus: boolean = false): void {
    clearTimeout(this.focusTimer);
    this.opened = false;
    if (restoreFocus) { this.focus('desktopWorkspaceLandingPicker'); }
  }

  private focus(key: string): void {
    clearTimeout(this.focusTimer);
    this.focusTimer = setTimeout((): void => { this.getUIContext().getFocusController().requestFocus(key); }, 30);
  }

  private choose(id: string): void {
    if (!this.ready || !this.rows.some((row: DesktopWorkspacePickerRow): boolean => row.id === id)) { return; }
    this.close();
    this.onPick(id);
  }

  private add(): void {
    if (!this.ready) { return; }
    this.close();
    this.onAdd();
  }

  private popupKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || !this.opened) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.close(this.keyboard); return true; }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN || event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      this.keyboard = true;
      const next = this.highlighted + (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN ? 1 : -1);
      const count = this.visibleRows.length + 1;
      this.highlighted = (next + count) % count;
      if (this.highlighted < this.visibleRows.length) {
        this.scroller.scrollToIndex(this.highlighted, false, ScrollAlign.AUTO);
      }
      if (this.rows.length <= 1) { this.focusHighlighted(); }
      return true;
    }
    return false;
  }

  private submit(): void {
    if (this.highlighted < 0) { return; }
    const row = this.visibleRows[this.highlighted];
    if (row === undefined) { this.add(); }
    else { this.choose(row.row.id); }
  }

  private focusHighlighted(): void {
    const row = this.visibleRows[this.highlighted];
    this.focus(row === undefined ? 'desktopWorkspacePickerAdd' : 'desktopWorkspacePickerRow-' + row.row.id);
  }

  @Builder
  private WorkspaceRow(entry: DesktopWorkspacePickerEntry, index: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 6 }) {
        Image($r('app.media.dsh_reference_folder')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
        Text(entry.row.title).fontSize(14).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (entry.suffix) {
          Text(entry.suffix).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('sys.color.font_secondary')).constraintSize({ maxWidth: 130 })
        }
        if (entry.row.id === this.selectedId) {
          Image($r('app.media.dsh_dock_check')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }
      }.width('100%')
    }.key('desktopWorkspacePickerRow-' + entry.row.id).id('desktopWorkspacePickerRow-' + entry.row.id)
      .width('100%').height(ROW_HEIGHT).borderRadius(7)
      .padding({ left: 8, right: 8 }).focusOnTouch(false).enabled(this.ready)
      .backgroundColor(this.keyboard && this.highlighted === index ? $r('app.color.workspace_selection') : Color.Transparent)
      .accessibilityDescription(entry.row.path).accessibilitySelected(entry.row.id === this.selectedId)
      .onClick((): void => { this.choose(entry.row.id); })
  }

  @Builder
  private Popup() {
    Column({ space: 4 }) {
      if (this.rows.length > 1) {
        TextInput({ text: this.query, placeholder: $r('app.string.desktop_workspace_picker_search') })
          .key('desktopWorkspacePickerSearch').id('desktopWorkspacePickerSearch').height(32).width('100%').fontSize(13)
          .onChange((query: string): void => { this.updateResults(query); })
          .onKeyPreIme((event: KeyEvent): boolean => this.popupKey(event))
          .onSubmit((): void => { this.submit(); })
      }
      if (this.visibleRows.length > 0) {
        List({ scroller: this.scroller }) {
          ForEach(this.visibleRows, (entry: DesktopWorkspacePickerEntry, index: number): void => {
            ListItem() { this.WorkspaceRow(entry, index) }
          }, (entry: DesktopWorkspacePickerEntry): string => entry.row.id + '|' + entry.row.title + '|' + entry.suffix)
        }.width('100%').height(Math.min(VISIBLE_WORKSPACE_ROWS, this.visibleRows.length) * ROW_HEIGHT)
          .scrollBar(BarState.Auto)
      } else {
        Text($r('app.string.desktop_workspace_picker_empty')).key('desktopWorkspacePickerEmpty')
          .fontSize(13).padding(8).fontColor($r('sys.color.font_secondary'))
      }
      Divider().color($r('app.color.workspace_border'))
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Image($r('app.media.dsh_reference_menu_plus')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
          Text($r('app.string.desktop_experiment_add_workspace')).fontSize(14).layoutWeight(1)
        }.width('100%')
      }.key('desktopWorkspacePickerAdd').id('desktopWorkspacePickerAdd')
        .height(ROW_HEIGHT).width('100%').padding({ left: 8, right: 8 }).focusOnTouch(false)
        .backgroundColor(this.keyboard && this.highlighted === this.visibleRows.length ?
          $r('app.color.workspace_selection') : Color.Transparent)
        .enabled(this.ready).onClick((): void => { this.add(); })
    }.key('desktopWorkspacePickerPopup').width(312).padding(6).alignItems(HorizontalAlign.Start)
      .onAppear((): void => {
        if (this.keyboard) {
          if (this.rows.length > 1) { this.focus('desktopWorkspacePickerSearch'); }
          else { this.focusHighlighted(); }
        }
      })
      .onKeyEvent((event: KeyEvent): boolean => this.popupKey(event))
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 7 }) {
        Image($r('app.media.dsh_reference_folder')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
        Text(this.caption).fontSize(14).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true)
          .rotate({ angle: this.opened ? 180 : 0 }).accessibilityLevel('no')
      }
    }.key('desktopWorkspaceLandingPicker').id('desktopWorkspaceLandingPicker').constraintSize({ maxWidth: '80%' })
      .height(30).padding({ left: 8, right: 8 }).borderRadius(7).focusOnTouch(false)
      .backgroundColor(this.opened ? $r('app.color.workspace_selection') : Color.Transparent)
      .enabled(this.ready).accessibilitySelected(this.opened).onClick((): void => { this.toggle(false); })
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type === KeyType.Down && (event.keyCode === KeyCode.KEYCODE_ENTER ||
          event.keyCode === KeyCode.KEYCODE_SPACE || event.keyCode === KeyCode.KEYCODE_DPAD_DOWN)) {
          this.toggle(true);
          return true;
        }
        return false;
      })
      .bindPopup(this.opened, { builder: this.Popup(), placement: Placement.BottomLeft,
        focusable: true, mask: false, enableArrow: false, systemMaterial: desktopMenuOptions(Placement.BottomLeft).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible) { this.opened = false; } } })
  }
}
