import { KeyCode } from '@kit.InputKit';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopTerminalShellPreference, desktopTerminalLaunchShell, readDesktopTerminalShells } from './DesktopTerminalShells';
import type { DesktopShell } from './DesktopTerminalShells';

@Component
export struct DesktopTerminalTitle {
  @Prop title: string = '';
  @Prop agentControlled: boolean = false;
  @Prop sandboxMode: string = '';
  @Prop keyPrefix: string = 'desktopTerminal';
  @Prop compact: boolean = false;
  @Prop editVersion: number = -1;
  onRenameFinished: (version: number, value: string, save: boolean) => void =
    (_version: number, _value: string, _save: boolean): void => {};

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
      if (this.editVersion >= 0) {
        DesktopTerminalNameInput({ initialTitle: this.title, version: this.editVersion,
          compact: this.compact, onFinished: this.onRenameFinished })
      } else {
        Text(this.title.length > 0 ? this.title : $r('app.string.desktop_terminal_chrome_title'))
          .key(this.keyPrefix + 'TitleLabel').fontSize(this.compact ? 12 : 13).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
      }
    }.key(this.keyPrefix + 'Title').width('100%')
  }
}

@Component
struct DesktopTerminalNameInput {
  @Prop initialTitle: string = '';
  @Prop version: number = -1;
  @Prop compact: boolean = false;
  onFinished: (version: number, value: string, save: boolean) => void =
    (_version: number, _value: string, _save: boolean): void => {};
  private draft: string = '';
  private composing: boolean = false;
  private controller = new TextInputController();
  private hasFocused: boolean = false;
  private finished: boolean = false;
  private ownedVersion: number = -1;
  private focusTimer: number = -1;

  aboutToAppear(): void {
    this.draft = this.initialTitle;
    this.ownedVersion = this.version;
    this.focusTimer = setTimeout((): void => {
      if (!this.finished && !this.hasFocused) {
        try { this.getUIContext().getFocusController().requestFocus('desktopTerminalRenameInput'); } catch (_) {}
      }
    }, 30);
  }

  aboutToDisappear(): void {
    clearTimeout(this.focusTimer);
    this.finished = true;
  }

  private finish(save: boolean, value: string): void {
    if (this.finished) { return; }
    this.finished = true;
    this.onFinished(this.ownedVersion, value, save);
  }

  build() {
    TextInput({ text: this.initialTitle, controller: this.controller })
      .key('desktopTerminalRenameInput').accessibilityText($r('app.string.desktop_terminal_chrome_name'))
      .width(120).constraintSize({ minWidth: 48 }).flexShrink(1).height(23).borderRadius(4)
      .padding({ left: 4, right: 4, top: 0, bottom: 0 }).fontSize(this.compact ? 12 : 13)
      .backgroundColor($r('app.color.workspace_canvas')).border({ width: 0.5, color: $r('app.color.workspace_border') })
      .maxLength(120).enterKeyType(EnterKeyType.Done)
      .onChange((value: string, preview?: PreviewText): void => {
        this.composing = (preview?.value.length ?? 0) > 0;
        if (!this.composing) { this.draft = value; }
      })
      .onFocus((): void => {
        if (this.hasFocused || this.finished) { return; }
        this.hasFocused = true;
        this.controller.setTextSelection(0, this.draft.length, { menuPolicy: MenuPolicy.HIDE });
      })
      .onBlur((): void => { if (this.hasFocused) { this.finish(true, this.draft); } })
      .onSubmit((_enter: EnterKeyType, event: SubmitEvent): void => {
        if (this.composing) { event.keepEditableState(); }
        else { this.finish(true, event.text); }
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        if (this.composing || event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
        this.finish(false, this.draft);
        return true;
      })
  }
}

@Component
export struct DesktopTerminalShellPicker {
  host?: DesktopHostActions;
  @Prop @Watch('invalidate') sessionId: string = '';
  @Prop @Watch('invalidate') origin: string = '';
  @Prop @Watch('checkEnabled') pickerEnabled: boolean = true;
  @Prop controlKey: string = '';
  @Prop buttonWidth: number = 24;
  @Prop buttonHeight: number = 24;
  onLaunch: (shellPath: string) => void = (_shellPath: string): void => {};

  @State private open: boolean = false;
  @State private loading: boolean = false;
  @State private choices: DesktopShell[] = [];
  @State private preferred: string = '';
  @State private problem: string = '';
  private generation: number = 0;
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; }

  aboutToDisappear(): void {
    this.active = false;
    this.invalidate();
  }

  private invalidate(): void {
    this.generation++;
    this.open = false;
    this.loading = false;
  }

  private checkEnabled(): void {
    if (!this.pickerEnabled) { this.invalidate(); }
  }

  private menuOptions(): MenuOptions {
    const options = desktopMenuOptions(Placement.BottomRight);
    options.onDisappear = (): void => { if (this.open) { this.invalidate(); } };
    return options;
  }

  private async load(): Promise<void> {
    const host = this.host;
    if (host === undefined) { return; }
    const generation = ++this.generation;
    const session = this.sessionId;
    this.loading = true;
    this.problem = '';
    this.choices = [];
    try {
      const catalog = await readDesktopTerminalShells(host, session);
      if (!this.active || !this.open || this.generation !== generation || this.host !== host) { return; }
      const preference = new DesktopTerminalShellPreference(this.getUIContext().getHostContext(), this.origin);
      this.choices = catalog.choices;
      this.problem = catalog.problem;
      this.preferred = desktopTerminalLaunchShell(catalog.choices, preference.read());
    } catch (_) {
      if (this.active && this.open && this.generation === generation && this.host === host) {
        this.problem = 'terminal/shells';
      }
    } finally {
      if (this.generation === generation) { this.loading = false; }
    }
  }

  private launch(path: string): void {
    if (!this.active || !this.open || this.loading || this.problem ||
      !this.choices.some((choice: DesktopShell): boolean => choice.path === path)) { return; }
    const preference = new DesktopTerminalShellPreference(this.getUIContext().getHostContext(), this.origin);
    preference.remember(path);
    this.invalidate();
    this.onLaunch(path);
  }

  @Builder
  private ShellMenu() {
    Menu() {
      if (this.loading) {
        MenuItem({ content: $r('app.string.desktop_terminal_chrome_shell_loading') }).enabled(false)
      } else if (this.problem) {
        MenuItem({ content: $r('app.string.desktop_terminal_chrome_failed', this.problem) }).enabled(false)
        MenuItem({ content: $r('app.string.desktop_terminal_chrome_retry') })
          .key(this.controlKey + 'Retry').onChange((): void => { this.load(); })
      } else if (this.choices.length === 0) {
        MenuItem({ content: $r('app.string.desktop_terminal_chrome_shell_empty') }).enabled(false)
      } else {
        ForEach(this.choices, (choice: DesktopShell): void => {
          MenuItem({ content: choice.name })
            .key(this.controlKey + '-' + choice.path).selectIcon(true).selected(this.preferred === choice.path)
            .accessibilitySelected(this.preferred === choice.path)
            .onChange((): void => { this.launch(choice.path); })
        }, (choice: DesktopShell): string => choice.path)
      }
    }
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image($r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14)
        .supportSvg2(true).draggable(false).accessibilityLevel('no')
    }.key(this.controlKey).width(this.buttonWidth).height(this.buttonHeight).padding(0).borderRadius(4)
      .focusOnTouch(false).enabled(this.pickerEnabled && this.host !== undefined && this.sessionId.length > 0)
      .accessibilityText($r('app.string.desktop_terminal_chrome_shell')).accessibilitySelected(this.open)
      .onClick((): void => {
        if (this.open) { this.invalidate(); }
        else {
          this.open = true;
          this.load();
        }
      })
      .bindMenu(this.open, this.ShellMenu, this.menuOptions())
  }
}

@Component
export struct DesktopTerminalGuide {
  host?: DesktopHostActions;
  @Prop sessionId: string = '';
  @Prop origin: string = '';
  @Prop createKey: string = 'desktopTerminalGuideCreate';
  @Prop shellKey: string = 'desktopTerminalGuideShell';
  @Prop canCreate: boolean = true;
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop problem: string = '';
  @Prop shortcutText: string = '';
  @Prop compact: boolean = false;
  onCreate: () => void = () => {};
  onRetry: () => void = () => {};
  onShellCreate: (shellPath: string) => void = (_shellPath: string): void => {};

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
        }.key(this.createKey).padding(0).borderRadius(6).layoutWeight(1)
          .constraintSize({ minHeight: this.compact ? 28 : 36 }).focusOnTouch(false)
          .enabled(this.canCreate && !this.loading && !this.busy && this.problem.length === 0)
          .accessibilityText($r('app.string.desktop_terminal_chrome_new'))
          .accessibilityDescription($r('app.string.desktop_terminal_chrome_description'))
          .onClick(this.onCreate)
        DesktopTerminalShellPicker({ host: this.host, sessionId: this.sessionId, origin: this.origin,
          pickerEnabled: this.canCreate && !this.busy, controlKey: this.shellKey, onLaunch: this.onShellCreate })
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
