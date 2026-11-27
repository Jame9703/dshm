import { KeyCode } from '@kit.InputKit';
import { desktopMenuOptions } from './DesktopMenuOptions';

@Component
export struct DesktopTerminalTitle {
  @Prop title: string = '';
  @Prop agentControlled: boolean = false;
  @Prop sandboxMode: string = '';
  @Prop keyPrefix: string = 'desktopTerminal';
  @Prop compact: boolean = false;

  private sandboxed(): boolean {
    return this.sandboxMode === 'read-only' || this.sandboxMode === 'workspace-write';
  }

  private badgeHint(): Resource {
    if (this.agentControlled) { return $r('app.string.desktop_terminal_chrome_agent_hint'); }
    return this.sandboxMode === 'read-only' ? $r('app.string.desktop_terminal_chrome_read_only_hint') :
      $r('app.string.desktop_terminal_chrome_workspace_hint');
  }

  build() {
    Row({ space: 6 }) {
      Image($r('app.media.dsh_compaction_api_outline')).width(16).height(16)
        .supportSvg2(true).draggable(false).accessibilityLevel('no')
      if (this.agentControlled || this.sandboxed()) {
        Text(this.agentControlled ? $r('app.string.desktop_terminal_chrome_agent') :
          $r('app.string.desktop_terminal_chrome_sandbox')).key(this.keyPrefix + 'TitleBadge')
          .fontSize(11).lineHeight(17)
          .fontColor(this.agentControlled ? $r('app.color.desktop_chat_running_label') : $r('sys.color.font_secondary'))
          .padding({ left: 8, right: 8, top: 1, bottom: 1 }).borderRadius(10)
          .backgroundColor(this.agentControlled ? $r('app.color.desktop_terminal_agent_fill') : $r('app.color.workspace_selection'))
          .accessibilityDescription(this.badgeHint())
      }
      Text(this.title.length > 0 ? this.title : $r('app.string.desktop_terminal_chrome_title'))
        .key(this.keyPrefix + 'TitleLabel').fontSize(this.compact ? 12 : 13).fontColor($r('sys.color.font_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
    }.key(this.keyPrefix + 'Title').width('100%')
  }
}

@Component
export struct DesktopTerminalGuide {
  @Prop canCreate: boolean = true;
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop problem: string = '';
  @Prop shellItems: MenuElement[] = [];
  @Prop shellLoading: boolean = false;
  @Prop shellProblem: string = '';
  @Prop shortcutText: string = '';
  @Prop compact: boolean = false;
  onCreate: () => void = () => {};
  onRetry: () => void = () => {};
  onRetryShells: () => void = () => {};

  private shellChoices(): MenuElement[] {
    if (this.shellLoading) {
      return [{ value: $r('app.string.desktop_terminal_chrome_shell_loading'), enabled: false, action: () => {} }];
    }
    if (this.shellProblem.length > 0) {
      return [
        { value: $r('app.string.desktop_terminal_chrome_failed', this.shellProblem), enabled: false,
          action: () => {} },
        { value: $r('app.string.desktop_terminal_chrome_retry'), action: this.onRetryShells }
      ];
    }
    if (this.shellItems.length > 0) { return this.shellItems; }
    return [{ value: $r('app.string.desktop_terminal_chrome_shell_empty'), enabled: false, action: () => {} }];
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 14 }) {
            Image($r('app.media.dsh_terminal_guide_artwork')).width(this.compact ? 22 : 26)
              .height(this.compact ? 22 : 26).supportSvg2(true).draggable(false).accessibilityLevel('no')
            Column({ space: 3 }) {
              Text($r('app.string.desktop_terminal_chrome_new')).width('100%').fontSize(14).lineHeight(20)
                .fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (!this.compact) {
                Text($r('app.string.desktop_terminal_chrome_description')).width('100%').fontSize(11).lineHeight(15)
                  .fontColor($r('sys.color.font_tertiary')).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%')
        }.key('desktopTerminalGuideCreate').padding(0).borderRadius(6).layoutWeight(1)
          .constraintSize({ minHeight: this.compact ? 28 : 36 }).focusOnTouch(false)
          .enabled(this.canCreate && !this.loading && !this.busy && this.problem.length === 0)
          .accessibilityText($r('app.string.desktop_terminal_chrome_new'))
          .accessibilityDescription($r('app.string.desktop_terminal_chrome_description'))
          .onClick(this.onCreate)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
        }.key('desktopTerminalGuideShell').width(24).height(24).padding(0).borderRadius(4)
          .focusOnTouch(false).enabled(this.canCreate && !this.busy)
          .accessibilityText($r('app.string.desktop_terminal_chrome_shell'))
          .bindMenu(this.shellChoices(), desktopMenuOptions(Placement.BottomRight))
        if (this.shortcutText.length > 0) {
          Text(this.shortcutText).key('desktopTerminalGuideShortcut').fontSize(11)
            .fontColor($r('sys.color.font_tertiary')).padding({ left: 4 }).maxLines(1)
        }
      }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .border({ width: 0.5, radius: 12, color: $r('app.color.workspace_border') })
        .backgroundColor($r('app.color.workspace_canvas'))
      if (this.loading || this.busy) {
        Row({ space: 8 }) {
          LoadingProgress().width(14).height(14).color($r('sys.color.brand')).accessibilityLevel('no')
          Text(this.loading ? $r('app.string.desktop_terminal_chrome_loading') :
            $r('app.string.desktop_terminal_chrome_creating')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
        }.key('desktopTerminalGuideLoading').width('100%').padding({ left: 6, right: 6 })
      } else if (this.problem.length > 0) {
        Row({ space: 8 }) {
          Text($r('app.string.desktop_terminal_chrome_failed', this.problem)).key('desktopTerminalGuideFailure')
            .fontSize(12).fontColor($r('app.color.workspace_status_error')).layoutWeight(1)
          Button($r('app.string.desktop_terminal_chrome_retry'), { type: ButtonType.Normal })
            .key('desktopTerminalGuideRetry').height(28).padding({ left: 10, right: 10 }).fontSize(12)
            .fontColor($r('sys.color.font_primary')).focusOnTouch(false)
            .backgroundColor(Color.Transparent).border({ width: 0.5, radius: 6, color: $r('app.color.workspace_border') })
            .onClick(this.onRetry)
        }.width('100%').padding({ left: 6, right: 6 })
      }
    }.key('desktopTerminalGuide').width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct DesktopTerminalCloseConfirmation {
  @Prop terminalName: string = '';
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  private dismissFromKeyboard(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
    this.onCancel();
    return true;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_terminal_chrome_close')).key('desktopTerminalCloseTitle')
          .fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor($r('sys.color.font_primary'))
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
        }.key('desktopTerminalCloseDismiss').width(28).height(28).padding(0).borderRadius(6)
          .focusOnTouch(false).accessibilityText($r('app.string.desktop_terminal_chrome_dismiss'))
          .onClick(this.onCancel).onKeyEvent((event: KeyEvent): boolean => this.dismissFromKeyboard(event))
      }.width('100%').padding({ top: 22, bottom: 12 })
      Text(this.terminalName).key('desktopTerminalCloseDescription').width('100%')
        .fontSize(14).lineHeight(22).fontColor($r('sys.color.font_primary')).wordBreak(WordBreak.BREAK_ALL)
      Row({ space: 8 }) {
        Button($r('app.string.desktop_terminal_chrome_cancel'), { type: ButtonType.Normal })
          .key('desktopTerminalCloseCancel').height(36).padding({ left: 14, right: 14 })
          .fontSize(14).fontColor($r('sys.color.font_primary')).focusOnTouch(false).defaultFocus(true)
          .backgroundColor(Color.Transparent).border({ width: 0.5, radius: 8, color: $r('app.color.workspace_border') })
          .onClick(this.onCancel).onKeyEvent((event: KeyEvent): boolean => this.dismissFromKeyboard(event))
        Button($r('app.string.desktop_terminal_chrome_close'), {
          type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED
        }).key('desktopTerminalCloseConfirm').height(36).padding({ left: 14, right: 14 })
          .fontSize(14).borderRadius(8).fontColor(Color.White).backgroundColor($r('app.color.workspace_status_error'))
          .focusOnTouch(false).onClick(this.onConfirm)
          .onKeyEvent((event: KeyEvent): boolean => this.dismissFromKeyboard(event))
      }.width('100%').justifyContent(FlexAlign.End).margin({ top: 20 })
    }.key('desktopTerminalCloseConfirmation').width('100%').padding({ left: 24, right: 24, bottom: 24 })
      .alignItems(HorizontalAlign.Start).accessibilityRole(AccessibilityRoleType.ALERT_DIALOG)
  }
}
