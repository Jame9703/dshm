import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { resourceManager } from '@kit.LocalizationKit';
import { dialogMaterial } from 'platform';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopTerminalCloseConfirmation, DesktopTerminalGuide, DesktopTerminalTitle } from './DesktopTerminalChrome';
import { DesktopTerminalClient } from './DesktopTerminalClient';
import type { DesktopShell, DesktopTerminalRow, DesktopTerminalState } from './DesktopTerminalClient';
import type { TerminalCellPaint, TerminalPaintFrame } from './terminal/TerminalEmulator';

const INSET: number = 10;
const INPUT_ID: string = 'desktopNativeTerminalInput';
const ESC: string = '\x1b';
const CANVAS_FONT_FAMILIES: Set<string> = new Set(['monospace', 'sans-serif', 'serif']);
const FUNCTION_KEYS: string[] = ['OP', 'OQ', 'OR', 'OS', '[15~', '[17~',
  '[18~', '[19~', '[20~', '[21~', '[23~', '[24~'];

@Component
export struct DesktopTerminalPane {
  host?: DesktopHostActions;
  @Prop @Watch('reloadSession') sessionId: string = '';
  @Prop @Watch('draw') appearance: string = 'system';
  @Prop @Watch('applyFont') cellFontSize: number = 13;
  @Prop @Watch('applyFontFamily') cellFontFamily: string = 'monospace';
  @Prop @Watch('createFromShortcut') createSession: string = '';
  preferredTerminal: string = '';
  onHidePanel: () => void = (): void => {};
  onCreateShortcut: () => void = () => {};
  onTerminalSelected: (sessionId: string, terminalId: string) => void =
    (_sessionId: string, _terminalId: string): void => {};
  onShortcut: (event: KeyEvent) => boolean = (_event: KeyEvent): boolean => false;

  @State private state?: DesktopTerminalState = undefined;
  @State private input: string = '';
  @State private inputFocused: boolean = false;
  @State private visibleScreen: string = '';
  @State private renameOpen: boolean = false;
  @State private renameTitle: string = '';
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private client?: DesktopTerminalClient;
  private frame?: TerminalPaintFrame;
  private active: boolean = false;
  private measured: boolean = false;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private charWidth: number = 8;
  private canvasFontFamily: string = 'monospace';
  private scrollY: number = 0;
  private ctrl: boolean = false;
  private createIssued: boolean = false;
  private closeDialogId: number = -1;
  private closeDialogOpening: boolean = false;
  private closeDialogVersion: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.canvasFontFamily = this.resolveCanvasFontFamily();
    this.reloadSession();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.dismissCloseDialog();
    this.client?.dispose();
    this.client = undefined;
  }

  private reloadSession(): void {
    this.dismissCloseDialog();
    this.client?.dispose();
    this.client = undefined;
    this.state = undefined;
    this.frame = undefined;
    this.visibleScreen = '';
    this.renameOpen = false;
    this.draw();
    if (this.host === undefined || !this.active || this.sessionId.length === 0) {
      return;
    }
    const id = this.sessionId;
    this.client = new DesktopTerminalClient(this.host, id, (state: DesktopTerminalState): void => {
      if (!this.active || this.sessionId !== id) {
        return;
      }
      this.state = state;
      if (state.selected) {
        this.onTerminalSelected(id, state.selected);
      }
      this.createFromShortcut();
    }, (frame: TerminalPaintFrame | undefined): void => {
      if (!this.active || this.sessionId !== id) {
        return;
      }
      this.frame = frame;
      this.visibleScreen = this.client?.visibleText() ?? '';
      this.draw();
    });
    this.fit();
    this.client.start(this.preferredTerminal);
  }

  private createFromShortcut(): void {
    if (this.createSession.length === 0) { this.createIssued = false; return; }
    if (!this.active || this.createIssued || this.createSession !== this.sessionId || this.client === undefined ||
      this.state?.canCreate !== true) { return; }
    this.createIssued = true;
    this.onCreateShortcut();
    this.client.create();
  }

  private selected(): DesktopTerminalRow | undefined {
    return this.state?.terminals.find((row: DesktopTerminalRow): boolean => row.id === this.state?.selected);
  }

  private shellMenu(): MenuElement[] {
    const items: MenuElement[] = [{ value: '默认 Shell', action: (): void => { this.client?.create(); } }];
    for (const shell of this.state?.shells ?? []) {
      items.push({ value: shell.name, action: (): void => { this.client?.create(shell.path); } });
    }
    return items;
  }

  private toolbarShellMenu(): MenuElement[] {
    const state = this.state;
    if (state?.shellsLoading) {
      return [{ value: $r('app.string.desktop_terminal_chrome_shell_loading'), enabled: false, action: (): void => {} }];
    }
    if (state?.shellProblem) {
      return [{ value: $r('app.string.desktop_terminal_chrome_failed', state.shellProblem), enabled: false, action: (): void => {} },
        { value: $r('app.string.desktop_terminal_chrome_retry'), action: (): void => { this.client?.retryShells(); } }];
    }
    return this.shellMenu();
  }

  private createTerminal(): void {
    if (this.state?.issue === 'create') { this.client?.retryCreate(); }
    else { this.client?.create(); }
  }

  private terminalMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    for (const row of this.state?.terminals ?? []) {
      items.push({
        value: (row.id === this.state?.selected ? '✓ ' : '') + row.title,
        action: (): void => { this.client?.select(row.id); }
      });
    }
    return items;
  }

  private async copyScreen(): Promise<void> {
    const text = this.client?.visibleText() ?? '';
    if (text.length > 0) {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
    }
  }

  private async pasteScreen(): Promise<void> {
    const data = await pasteboard.getSystemPasteboard().getData();
    if (this.active) {
      const value = data.getPrimaryText();
      if (value !== undefined) {
        this.client?.paste(value);
      }
    }
  }

  private actions(): MenuElement[] {
    return [
      { value: '重命名', action: (): void => {
        this.renameTitle = this.selected()?.title ?? '';
        this.renameOpen = true;
      } },
      { value: '重连终端', action: (): void => { this.client?.select(this.state?.selected ?? ''); } },
      { value: '复制当前屏幕', action: (): void => {
        this.copyScreen().catch((): void => {});
      } },
      { value: '粘贴', action: (): void => {
        this.pasteScreen().catch((): void => {});
      } },
      { value: '发送 Ctrl+C', action: (): void => { this.client?.write('\x03'); } },
      { value: '关闭终端', action: (): void => { this.confirmClose(); } }
    ];
  }

  private retryTerminal(): void {
    const client = this.client;
    if (client === undefined || this.state?.busy) { return; }
    switch (this.state?.issue) {
      case 'discovery': client.start(this.preferredTerminal); break;
      case 'create': client.retryCreate(); break;
      case 'attach': client.select(this.state.selected); break;
      default: break;
    }
  }

  @Builder
  private CloseTerminalDialog(row: DesktopTerminalRow, client: DesktopTerminalClient) {
    DesktopTerminalCloseConfirmation({ terminalName: row.title,
      onCancel: (): void => { this.dismissCloseDialog(); },
      onConfirm: (): void => {
        this.dismissCloseDialog();
        if (this.active && this.client === client) { client.closeTerminal(row.id); }
      } })
  }

  private async confirmClose(): Promise<void> {
    const row = this.selected();
    const client = this.client;
    if (row === undefined || client === undefined || this.closeDialogOpening || this.closeDialogId >= 0) { return; }
    const version = ++this.closeDialogVersion;
    this.closeDialogOpening = true;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({ builder: (): void => { this.CloseTerminalDialog(row, client); },
        alignment: DialogAlignment.Center, width: 380, cornerRadius: 16, isModal: true, autoCancel: true,
        systemMaterial: material, backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.closeDialogVersion) {
            this.closeDialogVersion++;
            this.closeDialogId = -1;
            this.closeDialogOpening = false;
          }
        }
      });
      if (this.active && this.client === client && version === this.closeDialogVersion) { this.closeDialogId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.active && version === this.closeDialogVersion) {
        prompt.showToast({ message: $r('app.string.desktop_terminal_dialog_unavailable') });
      }
    } finally {
      if (version === this.closeDialogVersion) { this.closeDialogOpening = false; }
    }
  }

  private dismissCloseDialog(): void {
    const id = this.closeDialogId;
    this.closeDialogVersion++;
    this.closeDialogId = -1;
    this.closeDialogOpening = false;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private focusInput(): void {
    if (this.state?.writable) {
      this.getUIContext().getFocusController().requestFocus(INPUT_ID);
    }
  }

  private handleTerminalKey(event: KeyEvent): boolean {
    const code = event.keyCode;
    const down = event.type === KeyType.Down;
    if (code === KeyCode.KEYCODE_CTRL_LEFT || code === KeyCode.KEYCODE_CTRL_RIGHT) {
      this.ctrl = down;
      return false;
    }
    if (this.onShortcut(event)) { return true; }
    if (!down || !this.state?.writable) {
      return false;
    }
    let text = '';
    if (this.ctrl && code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z) {
      if (code === KeyCode.KEYCODE_V) {
        return false;
      }
      text = String.fromCharCode(code - KeyCode.KEYCODE_A + 1);
    } else if (this.ctrl && code === KeyCode.KEYCODE_SPACE) {
      text = '\x00';
    } else if (code >= KeyCode.KEYCODE_DPAD_UP && code <= KeyCode.KEYCODE_DPAD_RIGHT) {
      const prefix = this.client?.applicationCursor() ? 'O' : '[';
      text = ESC + prefix + 'ABDC'.charAt(code - KeyCode.KEYCODE_DPAD_UP);
    } else if (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) {
      text = ESC + FUNCTION_KEYS[code - KeyCode.KEYCODE_F1];
    } else {
      switch (code) {
        case KeyCode.KEYCODE_ENTER:
        case KeyCode.KEYCODE_NUMPAD_ENTER: text = '\r'; break;
        case KeyCode.KEYCODE_DEL: text = '\x7f'; break;
        case KeyCode.KEYCODE_TAB: text = '\t'; break;
        case KeyCode.KEYCODE_ESCAPE: text = ESC; break;
        case KeyCode.KEYCODE_MOVE_HOME: text = ESC + '[H'; break;
        case KeyCode.KEYCODE_MOVE_END: text = ESC + '[F'; break;
        case KeyCode.KEYCODE_INSERT: text = ESC + '[2~'; break;
        case KeyCode.KEYCODE_FORWARD_DEL: text = ESC + '[3~'; break;
        case KeyCode.KEYCODE_PAGE_UP: text = ESC + '[5~'; break;
        case KeyCode.KEYCODE_PAGE_DOWN: text = ESC + '[6~'; break;
        default: return false;
      }
    }
    this.client?.write(text);
    return true;
  }

  private fit(): void {
    if (!this.measured || this.canvasWidth <= INSET * 2 || this.canvasHeight <= INSET * 2) {
      return;
    }
    this.canvas.font = 'normal normal ' + this.fontSpec();
    this.charWidth = this.canvas.measureText('M').width || this.charWidth;
    this.client?.resize(Math.max(2, Math.floor((this.canvasWidth - INSET * 2) / this.charWidth)),
      Math.max(1, Math.floor((this.canvasHeight - INSET * 2) / this.lineHeight())));
  }

  private resolveCanvasFontFamily(): string {
    for (const part of this.cellFontFamily.split(',')) {
      const family = part.trim();
      const generic = family.toLowerCase();
      if (CANVAS_FONT_FAMILIES.has(generic)) { return generic; }
      if (family) {
        try {
          const font = this.getUIContext().getFont().getFontByName(family);
          if (font?.postScriptName) { return font.postScriptName; }
        } catch (_) {
          // A font saved on another device may be unavailable here.
        }
      }
    }
    return 'monospace';
  }

  private fontSpec(): string { return `${this.cellFontSize}vp ${this.canvasFontFamily}`; }

  private lineHeight(): number { return this.cellFontSize + 6; }

  private applyFont(): void {
    this.scrollY = 0;
    this.fit();
    this.draw();
  }

  private applyFontFamily(): void {
    this.canvasFontFamily = this.resolveCanvasFontFamily();
    this.applyFont();
  }

  private draw(): void {
    if (!this.measured) {
      return;
    }
    const canvas = this.canvas;
    const frame = this.frame;
    canvas.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    if (frame === undefined) {
      return;
    }
    const systemDark = this.getUIContext().getHostContext()?.resourceManager.getConfigurationSync().colorMode ===
      resourceManager.ColorMode.DARK;
    const dark = this.appearance === 'dark' || (this.appearance === 'system' && systemDark);
    const ink = dark ? '#e1e2e5' : '#202124';
    const paper = dark ? '#151517' : '#ffffff';
    canvas.fillStyle = paper;
    canvas.fillRect(0, 0, this.canvasWidth, this.canvasHeight);
    canvas.textBaseline = 'top';
    const lineHeight = this.lineHeight();
    const baseFont = this.fontSpec();
    let font = '';
    let foreground = '';
    for (let row = 0; row < frame.rows.length; row++) {
      const y = INSET + row * lineHeight;
      if (y >= this.canvasHeight) {
        break;
      }
      for (const cell of frame.rows[row]) {
        const x = INSET + cell.column * this.charWidth;
        const width = cell.cells * this.charWidth;
        if (cell.background) {
          canvas.fillStyle = cell.background === 'foreground' ? ink : cell.background;
          canvas.fillRect(x, y, width, lineHeight);
          foreground = '';
        }
        const next = cell.foreground === 'background' ? paper : cell.foreground || ink;
        if (next !== foreground) {
          canvas.fillStyle = next;
          foreground = next;
        }
        if (cell.text) {
          const nextFont = this.fontFor(cell, baseFont);
          if (nextFont !== font) {
            canvas.font = nextFont;
            font = nextFont;
          }
          if (cell.dim) {
            canvas.globalAlpha = 0.65;
          }
          canvas.fillText(cell.text, x, y + 2);
          canvas.globalAlpha = 1.0;
        }
        if (cell.underline || cell.strike) {
          canvas.fillRect(x, y + (cell.underline ? lineHeight - 3 : lineHeight / 2), width, 1);
        }
      }
    }
    if (frame.cursorVisible && this.state?.writable) {
      canvas.fillStyle = ink;
      const x = INSET + frame.cursorColumn * this.charWidth;
      const y = INSET + frame.cursorRow * lineHeight;
      if (this.inputFocused) {
        canvas.fillRect(x, y + 2, 1.5, lineHeight - 4);
      } else {
        canvas.strokeStyle = ink;
        canvas.strokeRect(x, y + 2, this.charWidth, lineHeight - 4);
      }
    }
  }

  private fontFor(cell: TerminalCellPaint, baseFont: string): string {
    return `${cell.italic ? 'italic' : 'normal'} ${cell.bold ? 'bold' : 'normal'} ${baseFont}`;
  }

  @Builder
  private TerminalScreen() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Canvas(this.canvas)
        .width('100%').height('100%')
        .onReady((): void => {
          this.measured = true;
          this.fit();
          this.draw();
        })
        .onAreaChange((_previous: Area, area: Area): void => {
          this.canvasWidth = Number(area.width);
          this.canvasHeight = Number(area.height);
          this.fit();
          this.draw();
        })
        .accessibilityText('终端屏幕')
        .accessibilityDescription(this.visibleScreen)
        .onClick((): void => { this.focusInput(); })
        .onAxisEvent((event: AxisEvent): void => {
          const vertical = event.getVerticalAxisValue();
          if (vertical !== 0) {
            this.client?.scroll(vertical > 0 ? 3 : -3);
          }
        })
        .gesture(PanGesture({ direction: PanDirection.Vertical })
          .onActionStart((): void => { this.scrollY = 0; })
          .onActionUpdate((event: GestureEvent): void => {
            const lines = Math.trunc((this.scrollY - event.offsetY) / this.lineHeight());
            if (lines !== 0) {
              this.scrollY -= lines * this.lineHeight();
              this.client?.scroll(lines);
            }
          }))
      TextInput({ text: this.input })
        .key(INPUT_ID)
        .width(80).height(30).opacity(0.01).backgroundColor(Color.Transparent)
        .caretColor(Color.Transparent).fontColor(Color.Transparent)
        .accessibilityText('终端输入')
        .enabled(this.state?.writable === true)
        .enablePreviewText(false)
        .enterKeyType(EnterKeyType.Done)
        .onFocus((): void => { this.inputFocused = true; this.draw(); })
        .onBlur((): void => { this.inputFocused = false; this.ctrl = false; this.draw(); })
        .onKeyPreIme((event: KeyEvent): boolean => this.handleTerminalKey(event))
        .onSubmit((): void => { this.client?.write('\r'); })
        .onPaste((value: string, event: PasteEvent): void => {
          event.preventDefault?.();
          this.client?.paste(value);
        })
        .onChange((value: string): void => {
          if (!value) {
            return;
          }
          this.input = value;
          this.client?.write(value);
          setTimeout((): void => { this.input = ''; }, 0);
        })
    }
    .width('100%').layoutWeight(1)
  }

  build() {
    Column() {
      Row({ space: 3 }) {
        if (this.state?.selected) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            DesktopTerminalTitle({ title: this.selected()?.title ?? '',
              agentControlled: this.selected()?.origin === 'agent' && this.selected()?.control === 'agent',
              sandboxMode: this.selected()?.origin === 'agent' ? this.selected()?.sandboxMode ?? '' : '' })
          }
            .height(34).layoutWeight(1).bindMenu(this.terminalMenu(), desktopMenuOptions(Placement.BottomLeft))
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Text('⋯').fontSize(20).fontColor($r('sys.color.font_primary'))
          }
            .key('desktopTerminalActions').height(32).width(36).padding(0).accessibilityText('终端操作')
            .bindMenu(this.actions(), desktopMenuOptions(Placement.BottomRight))
        } else {
          Text($r('app.string.desktop_terminal_chrome_title')).fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        }
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_reference_menu_plus')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
        }
          .key('desktopTerminalToolbarCreate').height(32).width(34).padding(0)
          .accessibilityText($r('app.string.desktop_terminal_chrome_new'))
          .enabled(this.state?.canCreate === true).onClick((): void => { this.createTerminal(); })
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(13).height(13).supportSvg2(true).accessibilityLevel('no')
        }
          .height(32).width(30).padding(0).accessibilityText('选择 Shell')
          .enabled(this.state?.canCreate === true)
          .bindMenu(this.toolbarShellMenu(), desktopMenuOptions(Placement.BottomRight))
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }
          .height(32).width(32).padding(0).accessibilityText('收起终端面板')
          .onClick(this.onHidePanel)
      }
      .width('100%').height(42).padding({ left: 10, right: 7 })
      .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      if (this.renameOpen) {
        Row({ space: 6 }) {
          TextInput({ text: this.renameTitle, placeholder: '终端名称' }).layoutWeight(1).maxLength(120)
            .onChange((value: string): void => { this.renameTitle = value; })
          Button('保存').enabled(this.renameTitle.trim().length > 0).onClick((): void => {
            this.client?.rename(this.state?.selected ?? '', this.renameTitle.trim());
            this.renameOpen = false;
          })
          Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.renameOpen = false; })
        }
        .padding(8).width('100%')
      }
      if (this.state?.selected) {
        if (this.state.error) {
          Row({ space: 8 }) {
            Text(this.state.error).fontSize(13).fontColor($r('sys.color.warning')).layoutWeight(1)
            if (this.state.issue !== 'none') {
              Button($r('app.string.desktop_terminal_chrome_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                .key('desktopTerminalRecoveryRetry').height(28).enabled(!this.state.busy)
                .onClick((): void => { this.retryTerminal(); })
            }
          }.width('100%').padding(10)
        }
        this.TerminalScreen()
      } else {
        Column() {
          DesktopTerminalGuide({ canCreate: this.state?.canCreate === true, loading: this.state?.loading ?? true,
            busy: this.state?.busy === true, problem: this.state?.error ?? '', shellItems: this.shellMenu(),
            shellLoading: this.state?.shellsLoading === true, shellProblem: this.state?.shellProblem ?? '',
            onCreate: (): void => { this.createTerminal(); }, onRetry: (): void => { this.retryTerminal(); },
            onRetryShells: (): void => { this.client?.retryShells(); } })
        }
        .layoutWeight(1).width('100%').padding(10).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
    .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }
}
