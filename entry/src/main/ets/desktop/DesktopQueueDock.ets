import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { KeyCode } from '@kit.InputKit';
import { formatBytes, queueEditAction, queueRemoveAction, queueSteerAction } from 'appstate';
import type { QueueActionBody } from 'appstate';
import { getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopQueueAttachment, DesktopQueuedPrompt } from './DesktopPromptQueue';

@Component
struct DesktopQueueThumbnail {
  @Prop sessionId: string = '';
  @Prop attachment?: DesktopQueueAttachment;
  host?: DesktopHostActions;
  @State private picture: image.PixelMap | undefined = undefined;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.picture?.release().catch((): void => {});
  }

  private async load(): Promise<void> {
    const reference = this.attachment?.reference;
    if (this.host === undefined || reference === undefined) { return; }
    const result = await this.host.call('session/attachment', { 'sessionId': this.sessionId, 'attachment': reference });
    const data = result.ok ? getString(result.value, 'data') : undefined;
    if (!data || !this.active) { return; }
    try {
      const bytes = await new util.Base64Helper().decode(data);
      const buffer = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(buffer).set(bytes);
      const source = image.createImageSource(buffer);
      try {
        const picture = await source.createPixelMap({ desiredSize: { width: 96, height: 96 } });
        if (this.active) { this.picture = picture; }
        else { await picture.release(); }
      } finally {
        await source.release();
      }
    } catch (_) {}
  }

  build() {
    if (this.picture !== undefined) {
      Image(this.picture).width(36).height(32).borderRadius(5).objectFit(ImageFit.Cover).draggable(false)
        .accessibilityText(this.attachment?.name ?? '图片')
    } else {
      Text(this.attachment?.name ?? '图片').fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 136 }).padding({ left: 5, right: 5 })
    }
  }
}

@Component
export struct DesktopQueueDock {
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @Prop @Watch('rowsChanged') rows: DesktopQueuedPrompt[] = [];
  @Prop running: boolean = false;
  @Prop busy: boolean = false;
  host?: DesktopHostActions;
  onAction: (session: string, id: string, action: QueueActionBody) => Promise<string> =
    (_session: string, _id: string, _action: QueueActionBody): Promise<string> => Promise.resolve('');
  @State private expanded: boolean = false;
  @State private editing: string = '';
  @State private draft: string = '';
  @State private working: boolean = false;
  @State private notice: string = '';

  private sessionChanged(): void {
    this.expanded = false;
    this.editing = '';
    this.draft = '';
    this.notice = '';
    this.working = false;
  }

  private rowsChanged(): void {
    if (this.rows.length === 0) { this.expanded = false; }
    if (this.editing && !this.rows.some((row: DesktopQueuedPrompt): boolean => row.id === this.editing)) {
      this.editing = '';
      this.draft = '';
    }
  }

  private async apply(id: string, action: QueueActionBody): Promise<void> {
    if (this.working || this.busy) { return; }
    const session = this.sessionId;
    this.working = true;
    this.notice = '';
    try {
      const problem = await this.onAction(session, id, action);
      if (session !== this.sessionId) { return; }
      this.notice = problem;
      if (!problem && this.editing === id) { this.editing = ''; this.draft = ''; }
    } finally {
      if (session === this.sessionId) { this.working = false; }
    }
  }

  private save(id: string): void {
    if (this.draft.trim()) { this.apply(id, queueEditAction([this.draft.trim()])); }
  }

  @Builder
  private Icon(icon: Resource) {
    Image(icon).width(14).height(14).supportSvg2(true).draggable(false).accessibilityLevel('no')
  }

  @Builder
  private Action(icon: Resource, label: string, key: string, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      this.Icon(icon)
    }.key(key).width(28).height(28).padding(0).borderRadius(7).focusOnTouch(false)
      .accessibilityText(label).enabled(enabled && !this.busy && !this.working).onClick(action)
  }

  @Builder
  private InlineEdit(id: string) {
    TextArea({ text: this.draft, placeholder: '排队消息' }).key('desktopQueueDraft').layoutWeight(1)
      .fontSize(13).constraintSize({ minHeight: 34, maxHeight: 100 }).padding(5)
      .backgroundColor(Color.Transparent).defaultFocus(true).enabled(!this.working).enterKeyType(EnterKeyType.Done)
      .onChange((text: string): void => { this.draft = text; })
      .onSubmit((): void => { this.save(id); })
      .onKeyPreIme((event: KeyEvent): boolean => {
        if (event.type !== KeyType.Down || this.working) { return false; }
        if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.editing = ''; return true; }
        if (event.keyCode !== KeyCode.KEYCODE_ENTER || event.getModifierKeyState?.(['Shift'])) { return false; }
        this.save(id);
        return true;
      })
    this.Action($r('app.media.dsh_dock_check'), '保存', 'desktopQueueSave', this.draft.trim().length > 0,
      (): void => { this.save(id); })
    this.Action($r('app.media.dsh_dock_close'), '取消编辑', 'desktopQueueCancel', true,
      (): void => { this.editing = ''; })
  }

  @Builder
  private Preview(row: DesktopQueuedPrompt) {
    Row({ space: 6 }) {
      if (row.text) {
        Text(row.text.replace(/\s+/g, ' ')).fontSize(13).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }
      ForEach(row.attachments, (file: DesktopQueueAttachment): void => {
        if (file.image) {
          DesktopQueueThumbnail({ attachment: file, sessionId: this.sessionId, host: this.host })
        } else {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_text')).fontSize(14).accessibilityLevel('no')
            Text(file.name).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 120 })
            Text(formatBytes(file.bytes)).fontSize(11).fontColor($r('sys.color.font_tertiary'))
          }.padding(4).borderRadius(6).border({ width: 1, color: $r('app.color.workspace_border') })
        }
      }, (file: DesktopQueueAttachment, index: number): string => file.id + ':' + index)
    }.layoutWeight(1)
  }

  @Builder
  private QueueRow(row: DesktopQueuedPrompt) {
    Row({ space: 4 }) {
      if (this.rows.length === 1) { this.Icon($r('app.media.dsh_queue_queue_outline')) }
      if (this.editing === row.id) {
        this.InlineEdit(row.id)
      } else {
        this.Preview(row)
        if (row.sending) {
          Text('发送中…').fontSize(12).fontColor($r('sys.color.font_tertiary'))
        } else {
          this.Action($r('app.media.dsh_dock_edit'), row.editable ? '编辑排队消息' : '含附件的消息暂不支持编辑',
            'desktopQueueEdit-' + row.id, row.editable, (): void => {
              this.draft = row.text;
              this.editing = row.id;
              this.notice = '';
            })
          this.Action($r('app.media.dsh_dock_trash'), '删除排队消息', 'desktopQueueRemove-' + row.id, true,
            (): void => { this.apply(row.id, queueRemoveAction()); })
          this.Action($r('app.media.dsh_queue_send_outline'), '插话发送', 'desktopQueueSteer-' + row.id, this.running,
            (): void => { this.apply(row.id, queueSteerAction()); })
        }
      }
    }.width('100%').constraintSize({ minHeight: 34 }).padding({ left: 7, right: 4 })
  }

  build() {
    Column({ space: 1 }) {
      if (this.rows.length > 1) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 7 }) {
            this.Icon($r('app.media.dsh_queue_queue_outline'))
            Text(`${this.rows.length} 条排队消息`).fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
            this.Icon(this.expanded ? $r('app.media.dsh_queue_chevron_up_outline') :
              $r('app.media.dsh_queue_chevron_down_outline'))
          }.width('100%')
        }.key('desktopQueueToggle').width('100%').height(34).padding({ left: 7, right: 7 })
          .borderRadius(8).focusOnTouch(false).accessibilityText(this.expanded ? '收起排队消息' : '展开排队消息')
          .onClick((): void => { this.expanded = !this.expanded; })
      }
      if (this.expanded || this.rows.length === 1) {
        Scroll() {
          Column({ space: 1 }) {
            ForEach(this.rows, (row: DesktopQueuedPrompt): void => {
              this.QueueRow(row)
            }, (row: DesktopQueuedPrompt): string => row.id + ':' + row.text)
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 148 }).scrollBar(BarState.Auto)
      }
      if (this.notice) {
        Text(this.notice).fontSize(12).fontColor($r('sys.color.warning')).maxLines(2)
          .padding({ left: 7, right: 7, bottom: 4 }).width('100%')
      }
    }.key('desktopQueueDock').width('100%').constraintSize({ maxWidth: 688 })
      .borderRadius(12).padding(3).clip(true)
      .backgroundColor($r('app.color.workspace_panel')).border({ width: 1, color: $r('app.color.workspace_border') })
  }
}
