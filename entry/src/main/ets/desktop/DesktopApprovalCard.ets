import { KeyCode } from '@kit.InputKit';

type DesktopApprovalFocus = 'detail' | 'reject' | 'allow';

@Component
export struct DesktopApprovalCard {
  @Prop @Watch('invalidateKey') requestId: string = '';
  @Prop tool: string = '';
  @Prop reason: string = '';
  @Prop commandText: string = '';
  @Prop codeFamily: string = 'monospace';
  @Prop @Watch('invalidateKey') submitting: boolean = false;
  onDecision: (id: string, allow: boolean) => void = (_id: string, _allow: boolean): void => {};

  private armedKey: number = -1;
  private armedRequest: string = '';
  private armedFocus?: DesktopApprovalFocus;

  private canAnswer(): boolean {
    return this.requestId.length > 0 && !this.submitting;
  }

  private decide(allow: boolean): void {
    if (this.canAnswer()) { this.onDecision(this.requestId, allow); }
  }

  private handleApprovalClick(event: ClickEvent, allow: boolean): void {
    // Native keyboard activation also emits onClick. Key handlers above the button own those decisions.
    if (event.source !== SourceType.KEY) { this.decide(allow); }
  }

  private plainKey(event: KeyEvent): boolean {
    if (event.metaKey !== 0 || event.getModifierKeyState === undefined) { return false; }
    try {
      return !event.getModifierKeyState(['Ctrl']) && !event.getModifierKeyState(['Alt']) &&
        !event.getModifierKeyState(['Shift']);
    } catch (_) {
      return false;
    }
  }

  private invalidateKey(): void {
    this.armedRequest = '';
    this.armedFocus = undefined;
  }

  private handleApprovalKey(event: KeyEvent, focus: DesktopApprovalFocus): boolean {
    const code: number = event.keyCode;
    const escape: boolean = code === KeyCode.KEYCODE_ESCAPE;
    const enter: boolean = code === KeyCode.KEYCODE_ENTER || code === KeyCode.KEYCODE_NUMPAD_ENTER;
    const buttonSpace: boolean = code === KeyCode.KEYCODE_SPACE && focus !== 'detail';
    if (!escape && !enter && !buttonSpace) { return false; }

    if (event.type === KeyType.Down) {
      if (this.armedKey === -1) {
        this.armedKey = code;
        if (this.canAnswer() && this.plainKey(event)) {
          this.armedRequest = this.requestId;
          this.armedFocus = focus;
        }
      } else if (this.armedKey !== code || !this.plainKey(event)) {
        this.invalidateKey();
      }
    } else if (event.type === KeyType.Up && this.armedKey === code) {
      const accepted: boolean = this.armedFocus === focus && this.armedRequest === this.requestId &&
        this.canAnswer() && this.plainKey(event);
      this.armedKey = -1;
      this.invalidateKey();
      if (accepted) { this.decide(!escape && focus !== 'reject'); }
    }
    return true;
  }

  @Builder
  private Status() {
    Row({ space: 8 }) {
      if (this.submitting) {
        LoadingProgress().key('desktopApprovalSending').width(14).height(14)
          .color($r('sys.color.font_tertiary')).accessibilityLevel('no')
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 6, height: 6 }).fill($r('app.color.desktop_approval_warning_ink')).accessibilityLevel('no')
        }.width(10).height(10).accessibilityLevel('no')
      }
      Text($r('app.string.desktop_approval_pending')).fontSize(13).lineHeight(18)
        .fontColor($r('app.color.desktop_approval_warning_ink'))
    }.key('desktopApprovalStatus').width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.desktop_approval_warning_background'))
      .accessibilityStateDescription(this.submitting ? $r('app.string.desktop_approval_submitting') : undefined)
  }

  @Builder
  private Details() {
    Scroll() {
      Column({ space: 6 }) {
        Text(this.reason || $r('app.string.desktop_approval_tool', this.tool))
          .key('desktopApprovalReason').width('100%').fontSize(15).lineHeight(24).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.InApp)
        if (this.commandText.length > 0) {
          Text(this.commandText).key('desktopApprovalCommand').width('100%').fontSize(13).lineHeight(20)
            .fontFamily(this.codeFamily).fontColor($r('sys.color.font_tertiary')).wordBreak(WordBreak.BREAK_ALL)
            .copyOption(CopyOptions.InApp)
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.key('desktopApprovalDetails').width('100%').constraintSize({ maxHeight: 180 })
      .padding({ left: 16, right: 16, top: 12 }).align(Alignment.TopStart)
      .focusable(true).accessibilityDescription($r('app.string.desktop_approval_details'))
      .onBlur((): void => { this.invalidateKey(); })
      .onKeyEvent((event: KeyEvent): boolean => this.handleApprovalKey(event, 'detail'))
  }

  @Builder
  private Actions() {
    Row({ space: 8 }) {
      Button($r('app.string.desktop_approval_reject'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopApprovalReject').height(36).padding({ left: 14, right: 14 }).fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .border({ width: 0.5, radius: 8, color: $r('app.color.workspace_border') })
        .enabled(this.canAnswer()).focusOnTouch(false)
        .onBlur((): void => { this.invalidateKey(); })
        .onKeyEvent((event: KeyEvent): boolean => this.handleApprovalKey(event, 'reject'))
        .onClick((event: ClickEvent): void => { this.handleApprovalClick(event, false); })
      Button($r('app.string.desktop_approval_allow'), {
        type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED
      }).key('desktopApprovalAllow').height(36).padding({ left: 14, right: 14 }).fontSize(14).borderRadius(8)
        .enabled(this.canAnswer()).focusOnTouch(false)
        .onBlur((): void => { this.invalidateKey(); })
        .onKeyEvent((event: KeyEvent): boolean => this.handleApprovalKey(event, 'allow'))
        .onClick((event: ClickEvent): void => { this.handleApprovalClick(event, true); })
    }.width('100%').justifyContent(FlexAlign.End).padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  build() {
    Column() {
      this.Status()
      this.Details()
      this.Actions()
    }.key('desktopApprovalCard').width('100%').constraintSize({ maxWidth: 712 })
      .alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.workspace_panel'))
      .border({ width: 1, radius: 16, color: $r('app.color.desktop_approval_warning_border') }).clip(true)
  }
}
