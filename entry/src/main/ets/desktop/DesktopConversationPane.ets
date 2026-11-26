import { Speaker, TrajectoryItem } from 'appstate';
import type { ModelOption, ModelSelection, PendingAttachment } from 'appstate';
import type { DesktopConversationSnapshot, DesktopPermissionOption } from './DesktopConversation';
import { MarkdownRenderer } from '../view/MarkdownRenderer';

@Component
export struct DesktopConversationPane {
  @Prop @Watch('onSnapshotChanged') snapshot: DesktopConversationSnapshot | undefined = undefined;
  @Prop title: ResourceStr = '';
  @Prop workspaceTitle: ResourceStr = '';
  @Prop draft: string = '';
  @Prop attachments: PendingAttachment[] = [];
  @Prop busy: boolean = false;
  @Prop commandError: string = '';
  @Prop menuOptions: MenuOptions | undefined = undefined;
  onDraft: (value: string) => void = () => {};
  onAddAttachment: () => void = () => {};
  onRemoveAttachment: (receiptId: string) => void = () => {};
  onSend: () => void = () => {};
  onStop: () => void = () => {};
  onEarlier: () => void = () => {};
  onWeb: () => void = () => {};
  onModel: (selection: ModelSelection) => void = () => {};
  onPermission: (preset: string) => void = () => {};

  private readonly scroller: Scroller = new Scroller();
  private following: boolean = true;
  private sessionId: string = '';
  private messageCount: number = 0;
  private partial: string = '';
  private scrollTimer: number = -1;

  aboutToDisappear(): void {
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  private onSnapshotChanged(): void {
    const id = this.snapshot?.sessionId ?? '';
    const count = this.snapshot?.messages.length ?? 0;
    const partial = this.snapshot?.partial ?? '';
    if (id !== this.sessionId) {
      this.sessionId = id;
      this.following = true;
    } else if (count === this.messageCount && partial === this.partial) {
      return;
    }
    this.messageCount = count;
    this.partial = partial;
    if (this.following && this.scrollTimer === -1) {
      this.scrollTimer = setTimeout((): void => {
        this.scrollTimer = -1;
        if (this.following && this.snapshot?.sessionId === this.sessionId) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 30);
    }
  }

  private modelMenu(): Array<MenuElement> {
    if ((this.snapshot?.models.length ?? 0) === 0) {
      return [{ value: $r('app.string.desktop_chat_model_settings'), action: this.onWeb }];
    }
    return (this.snapshot?.models ?? []).map((option: ModelOption): MenuElement => {
      return {
        value: option.modelName + ' · ' + option.providerName,
        action: (): void => this.onModel({
          provider: option.provider, modelId: option.modelId, effort: option.defaultEffort
        })
      };
    });
  }

  private effortMenu(): Array<MenuElement> {
    const selection = this.snapshot?.selection;
    if (selection === undefined) {
      return [];
    }
    const option = this.snapshot?.models.find((item: ModelOption): boolean =>
      item.provider === selection.provider && item.modelId === selection.modelId);
    return (option?.efforts ?? []).map((effort: string): MenuElement => {
      return {
        value: effort,
        action: (): void => this.onModel({
          provider: selection.provider, modelId: selection.modelId, effort: effort
        })
      };
    });
  }

  @Builder
  private Message(item: TrajectoryItem) {
    Column() {
      if (item.speaker === Speaker.USER) {
        Text(item.body)
          .fontSize(15).fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .constraintSize({ maxWidth: '82%' }).borderRadius(16)
          .backgroundColor($r('app.color.workspace_panel'))
      } else {
        MarkdownRenderer({ text: item.body })
      }
    }
    .width('100%').constraintSize({ maxWidth: 712 })
    .alignItems(item.speaker === Speaker.USER ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  @Builder
  private ModelChip(effort: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 5 }) {
        Text(effort ? this.snapshot?.selection?.effort || $r('app.string.desktop_chat_effort') :
          this.snapshot?.modelLabel || $r('app.string.desktop_chat_select_model'))
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10)
          .fontColor([$r('sys.color.font_tertiary')]).rotate({ angle: 90 })
      }
    }
    .height(32).padding({ left: 8, right: 8 }).constraintSize({ maxWidth: '60%' })
    .borderRadius(8).backgroundColor(Color.Transparent).focusOnTouch(false)
    .enabled(!this.busy).bindMenu(effort ? this.effortMenu() : this.modelMenu(), this.menuOptions)
  }

  @Builder
  private Composer() {
    Column({ space: 6 }) {
      if (this.attachments.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.attachments, (item: PendingAttachment, index: number) => {
              Button(item.name + ' ×', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .enabled(!this.busy).accessibilityText('移除附件 ' + item.name)
                .onClick((): void => { this.onRemoveAttachment(item.receiptId); })
            }, (item: PendingAttachment, index: number): string => item.receiptId + index)
          }
        }
        .scrollable(ScrollDirection.Horizontal).width('100%').padding({ left: 8, right: 8 })
      }
      TextArea({ text: this.draft, placeholder: $r('app.string.desktop_chat_placeholder') })
        .width('100%').height(66).fontSize(15).borderRadius(16).padding({ left: 12, right: 12, top: 10 })
        .fontColor($r('sys.color.font_primary')).backgroundColor(Color.Transparent)
        .onChange(this.onDraft)
      Row({ space: 4 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.paperclip')).fontSize(16)
        }
        .width(32).height(32).focusOnTouch(false)
        .enabled(!this.busy && this.snapshot?.loading === false)
        .accessibilityText('添加附件').onClick(this.onAddAttachment)
        if ((this.snapshot?.permissions.length ?? 0) > 0) {
          Button(this.snapshot?.permissions.find((row: DesktopPermissionOption): boolean =>
            row.value === this.snapshot?.permission)?.title || '访问模式', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(31).borderRadius(8).enabled(!this.busy).focusOnTouch(false)
            .bindMenu(this.snapshot?.permissions.map((row: DesktopPermissionOption): MenuElement => {
              return { value: (row.value === this.snapshot?.permission ? '✓ ' : '') + row.title,
                action: (): void => { this.onPermission(row.value); } };
            }) ?? [], this.menuOptions)
        }
        Blank()
        this.ModelChip(false)
        if (this.effortMenu().length > 0) {
          this.ModelChip(true)
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.snapshot?.running ? $r('sys.symbol.xmark') : $r('sys.symbol.arrow_up'))
            .fontSize(17).fontColor([Color.White])
        }
        .width(34).height(34)
        .backgroundColor($r('sys.color.brand')).focusOnTouch(false)
        .accessibilityText(this.snapshot?.running ? $r('app.string.desktop_chat_stop') :
          $r('app.string.desktop_chat_send'))
        .enabled(!this.busy && (this.snapshot?.running === true ||
          ((this.draft.trim().length > 0 || this.attachments.length > 0) &&
            this.snapshot?.loading === false)))
        .onClick((): void => {
          if (this.snapshot?.running) {
            this.onStop();
          } else {
            this.following = true;
            this.onSend();
          }
        })
      }
      .width('100%').padding({ left: 8, right: 8, bottom: 7 })
    }
    .width('100%').constraintSize({ maxWidth: 712 })
    .borderRadius(20).backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.workspaceTitle !== '') {
            Text(this.workspaceTitle).fontSize(12).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button($r('app.string.desktop_experiment_open_web'),
          { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(34).focusOnTouch(false).onClick(this.onWeb)
      }
      .width('100%').height(50).padding({ left: 20, right: 16 })
      if (this.snapshot?.loading) {
        LoadingProgress().width(22).height(22).color($r('sys.color.brand'))
      }
      if (this.snapshot?.hasEarlier) {
        Button($r('app.string.desktop_chat_earlier'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => {
            this.following = false;
            this.onEarlier();
          })
      }
      List({ space: 16, scroller: this.scroller }) {
        ForEach(this.snapshot?.messages ?? [], (item: TrajectoryItem): void => {
          ListItem() {
            Row() { this.Message(item) }
              .width('100%').justifyContent(FlexAlign.Center)
          }
        }, (item: TrajectoryItem): string => item.id)
        if ((this.snapshot?.partial.length ?? 0) > 0) {
          ListItem() {
            Row() {
              Text(this.snapshot?.partial ?? '').fontSize(15).fontColor($r('sys.color.font_primary'))
                .width('100%').constraintSize({ maxWidth: 712 })
            }
            .width('100%').justifyContent(FlexAlign.Center)
          }
        }
      }
      .layoutWeight(1).width('100%').padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .scrollBar(BarState.Auto)
      .onScrollIndex((_first: number, last: number): void => {
        this.following = last >= this.messageCount - 1;
      })
      if (this.snapshot?.waitingForInput) {
        Button($r('app.string.desktop_chat_pending'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(this.onWeb)
      }
      if (this.commandError.length > 0 || (this.snapshot?.error.length ?? 0) > 0) {
        Text(this.commandError || this.snapshot?.error || '')
          .fontSize(13).fontColor($r('sys.color.warning'))
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 16, right: 16, bottom: 6 })
      }
      Row() { this.Composer() }
        .width('100%').padding({ left: 20, right: 20, bottom: 16 }).justifyContent(FlexAlign.Center)
    }
    .width('100%').height('100%')
  }
}
