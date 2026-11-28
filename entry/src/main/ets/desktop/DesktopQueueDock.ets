import { KeyCode } from '@kit.InputKit';
import { queueEditAction, queueRemoveAction, queueSteerAction } from 'appstate';
import type { QueueActionBody } from 'appstate';
import { controlMaterial } from 'platform';
import { StartupFrameCallback } from '../common/DesktopStartup';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopQueuedPrompt, desktopQueueFileSize } from './DesktopPromptQueue';
import { DesktopAttachmentThumbnail } from './DesktopAttachments';
import type { DesktopMediaAttachment } from './DesktopAttachments';

@Component
export struct DesktopQueueDock {
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @Prop @Watch('rowsChanged') rows: DesktopQueuedPrompt[] = [];
  @Prop @Watch('rowsChanged') mutable: boolean = true;
  @Prop running: boolean = false;
  @Prop busy: boolean = false;
  @Prop attached: boolean = false;
  host?: DesktopHostActions;
  onAction: (session: string, id: string, action: QueueActionBody) => Promise<string> =
    (_session: string, _id: string, _action: QueueActionBody): Promise<string> => Promise.resolve('');
  @State private expanded: boolean = false;
  @State private editing: string = '';
  @State private draft: string = '';
  @State private working: boolean = false;
  private generation: number = 0;
  private composing: boolean = false;

  aboutToDisappear(): void { this.generation++; }

  private sessionChanged(): void {
    this.generation++;
    this.expanded = false;
    this.cancelEdit();
    this.working = false;
  }

  private rowsChanged(): void {
    if (this.rows.length === 0) { this.expanded = false; }
    if (this.editing && (!this.mutable ||
      !this.rows.some((row: DesktopQueuedPrompt): boolean => row.id === this.editing && row.editable && !row.sending))) {
      this.cancelEdit();
    }
  }

  private cancelEdit(): void {
    this.editing = '';
    this.draft = '';
    this.composing = false;
  }

  private interactionActive(): boolean {
    return this.mutable && (this.editing.length > 0 || this.working);
  }

  private listVisible(): boolean {
    return this.expanded || this.interactionActive() || this.rows.length === 1;
  }

  private draftKey(id: string): string {
    return 'desktopQueueDraft-' + this.sessionId + '-' + id;
  }

  private edit(id: string): void {
    const row = this.rows.find((item: DesktopQueuedPrompt): boolean => item.id === id);
    if (row === undefined || !row.editable || row.sending || !this.mutable || this.busy || this.working) { return; }
    this.composing = false;
    this.draft = row.text;
    this.editing = id;
    const generation = this.generation;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      if (generation === this.generation && this.editing === id) {
        try { this.getUIContext().getFocusController().requestFocus(this.draftKey(id)); } catch (_) {}
      }
    }));
  }

  private async apply(id: string, action: QueueActionBody, failure: Resource): Promise<void> {
    if (this.working || this.busy || !this.mutable || (action.kind === 'steer' && !this.running) ||
      !this.rows.some((row: DesktopQueuedPrompt): boolean => row.id === id && !row.sending)) { return; }
    const generation = this.generation;
    this.working = true;
    let rejected = true;
    try {
      rejected = (await this.onAction(this.sessionId, id, action)).length > 0;
    } catch (_) {
      rejected = true;
    } finally {
      if (generation === this.generation) {
        this.working = false;
        if (rejected) {
          this.getUIContext().getPromptAction().showToast({ message: failure });
        } else if (this.editing === id) {
          this.cancelEdit();
        }
      }
    }
  }

  private save(id: string, value: string): void {
    if (this.editing === id && !this.composing && value.trim()) {
      this.apply(id, queueEditAction([value]), $r('app.string.desktop_queue_edit_failed'));
    }
  }

  private editKey(id: string, event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || this.working) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.cancelEdit(); return true; }
    if (this.composing || (event.keyCode !== KeyCode.KEYCODE_ENTER && event.keyCode !== KeyCode.KEYCODE_NUMPAD_ENTER) ||
      event.getModifierKeyState?.(['Shift']) === true) { return false; }
    this.save(id, this.draft);
    return true;
  }

  @Builder
  private Icon(icon: Resource, size: number = 14) {
    Image(icon).width(size).height(size).supportSvg2(true).draggable(false).accessibilityLevel('no')
  }

  @Builder
  private Action(icon: Resource, label: Resource, key: string, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      this.Icon(icon)
    }.key(key).width(28).height(28).padding(0).focusOnTouch(false)
      .accessibilityText(label).enabled(enabled && !this.busy && !this.working).onClick(action)
  }

  @Builder
  private InlineEdit(id: string) {
    TextArea({ text: this.draft }).key(this.draftKey(id)).layoutWeight(1)
      .fontSize(13).constraintSize({ minHeight: 30, maxHeight: 100 }).padding(5)
      .backgroundColor($r('app.color.workspace_canvas')).borderRadius(6)
      .border({ width: 0.5, color: $r('app.color.workspace_border') })
      .accessibilityText($r('app.string.desktop_queue_edit')).enabled(!this.working).enterKeyType(EnterKeyType.NEW_LINE)
      .onChange((text: string, preview?: PreviewText): void => {
        this.composing = (preview?.value.length ?? 0) > 0;
        if (!this.composing) { this.draft = text; }
      })
      .onKeyPreIme((event: KeyEvent): boolean => this.editKey(id, event))
    Row({ space: 8 }) {
      this.Action($r('app.media.dsh_dock_check'), $r('app.string.desktop_queue_save'), 'desktopQueueSave',
        this.draft.trim().length > 0, (): void => { this.save(id, this.draft); })
      this.Action($r('app.media.dsh_dock_close'), $r('app.string.desktop_queue_cancel'), 'desktopQueueCancel', true,
        (): void => { this.cancelEdit(); })
    }
  }

  @Builder
  private File(file: DesktopMediaAttachment) {
    Row({ space: 4 }) {
      if (file.name.toLowerCase().endsWith('.md') || file.name.toLowerCase().endsWith('.markdown')) {
        this.Icon($r('app.media.dsh_file_markdown'), 16)
      } else {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(16).accessibilityLevel('no')
      }
      Text(file.name).fontSize(13).maxLines(1).flexShrink(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_secondary'))
      Text(desktopQueueFileSize(file.bytes)).fontSize(10).maxLines(1).fontColor($r('sys.color.font_tertiary'))
    }.height(24).constraintSize({ minWidth: 74, maxWidth: 180 }).padding({ left: 6, right: 6 })
      .borderRadius(6).border({ width: 0.5, color: $r('app.color.workspace_border') })
      .backgroundColor($r('app.color.workspace_canvas')).clip(true)
      .accessibilityDescription($r('app.string.desktop_queue_file', file.name))
  }

  @Builder
  private Sending() {
    Text($r('app.string.desktop_queue_sending')).fontSize(13).fontColor($r('sys.color.font_tertiary'))
      .key('desktopQueueSending').maxLines(1)
  }

  @Builder
  private QueueRow(row: DesktopQueuedPrompt, index: number) {
    Row({ space: 10 }) {
      if (this.rows.length === 1) { this.Icon($r('app.media.dsh_queue_queue_outline'), 16) }
      if (this.editing === row.id) {
        this.InlineEdit(row.id)
      } else {
        if (row.attachments.length > 0) {
          Row({ space: 4 }) {
            ForEach(row.attachments, (file: DesktopMediaAttachment, at: number): void => {
              if (file.image) {
                DesktopAttachmentThumbnail({ attachment: file, sessionId: this.sessionId, host: this.host, maxEdge: 24,
                  compactPreview: true, nodeKey: 'desktopQueueImage-' + row.id + '-' + at })
              } else {
                this.File(file)
              }
            }, (file: DesktopMediaAttachment, at: number): string => file.id + ':' + at)
          }.constraintSize({ maxWidth: '55%' }).clip(true)
        }
        Text(row.preview).fontSize(13).maxLines(1).layoutWeight(1).fontColor($r('sys.color.font_secondary'))
          .key('desktopQueuePreview-' + row.id).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (row.sending) { this.Sending() }
        if (this.mutable) {
          Row({ space: 8 }) {
            this.Action($r('app.media.dsh_dock_edit'), !row.sending && !row.editable ?
              $r('app.string.desktop_queue_edit_unsupported') : $r('app.string.desktop_queue_edit'),
              'desktopQueueEdit-' + row.id, row.editable && !row.sending, (): void => { this.edit(row.id); })
            this.Action($r('app.media.dsh_dock_trash'), $r('app.string.desktop_queue_remove'),
              'desktopQueueRemove-' + row.id, !row.sending,
              (): void => { this.apply(row.id, queueRemoveAction(), $r('app.string.desktop_queue_remove_failed')); })
            this.Action($r('app.media.dsh_queue_send_outline'), this.running || row.sending ?
              $r('app.string.desktop_queue_steer') : $r('app.string.desktop_queue_steer_unavailable'),
              'desktopQueueSteer-' + row.id, this.running && !row.sending,
              (): void => { this.apply(row.id, queueSteerAction(), $r('app.string.desktop_queue_steer_failed')); })
          }
        }
      }
    }.width('100%').constraintSize({ minHeight: 36 }).padding({ left: 12, right: 5, top: 4, bottom: 4 })
      .borderWidth({ top: index > 0 ? 0.5 : 0 }).borderColor($r('app.color.workspace_border'))
  }

  build() {
    Column() {
      if (this.rows.length > 1) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 10 }) {
            this.Icon($r('app.media.dsh_queue_queue_outline'), 16)
            Text($r('app.string.desktop_queue_count', this.rows.length)).fontSize(13)
              .fontWeight(FontWeight.Medium).layoutWeight(1)
            if (!this.listVisible() && this.rows.some((row: DesktopQueuedPrompt): boolean => row.sending === true)) {
              this.Sending()
            }
            this.Icon(this.listVisible() ? $r('app.media.dsh_queue_chevron_down_outline') :
              $r('app.media.dsh_queue_chevron_up_outline'))
          }.width('100%')
        }.key('desktopQueueToggle').width('100%').height(36).padding({ left: 12, right: 12 })
          .borderRadius(8).focusOnTouch(false).enabled(!this.interactionActive())
          .accessibilityText($r('app.string.desktop_queue_count', this.rows.length))
          .accessibilityStateDescription(this.listVisible() ? $r('app.string.desktop_queue_expanded') :
            $r('app.string.desktop_queue_collapsed'))
          .onClick((): void => { this.expanded = !this.expanded; })
      }
      if (this.listVisible()) {
        Scroll() {
          Column() {
            ForEach(this.rows, (row: DesktopQueuedPrompt, index: number): void => {
              this.QueueRow(row, index)
            }, (row: DesktopQueuedPrompt, index: number): string =>
              row.id + ':' + row.preview + ':' + String(row.sending === true) + ':' + String(index))
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 180 }).scrollBar(BarState.Auto)
      }
    }.key('desktopQueueDock').width('100%').constraintSize({ maxWidth: 688 })
      .padding({ top: 2, bottom: 2 }).margin({ bottom: this.attached ? -9 : 0 }).clip(true)
      .borderRadius({ topLeft: 12, topRight: 12, bottomLeft: this.attached ? 0 : 12, bottomRight: this.attached ? 0 : 12 })
      .borderWidth({ top: 0.5, right: 0.5, bottom: this.attached ? 0 : 0.5, left: 0.5 })
      .borderColor($r('app.color.workspace_border'))
      .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : Color.Transparent)
      .systemMaterial(controlMaterial())
  }
}
