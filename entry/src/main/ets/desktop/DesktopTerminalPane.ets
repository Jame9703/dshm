import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { resourceManager } from '@kit.LocalizationKit';
import { dialogMaterial } from 'platform';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopTerminalCloseConfirmation, DesktopTerminalGuide, DesktopTerminalTitle } from './DesktopTerminalChrome';
import { DesktopTerminalClient } from './DesktopTerminalClient';
import { DesktopTerminalSelection } from './DesktopTerminalSelection';
import type { DesktopTerminalSelectionSpan } from './DesktopTerminalSelection';
import type { DesktopShell, DesktopTerminalRetentionObserver, DesktopTerminalRosterObserver, DesktopTerminalRow,
  DesktopTerminalState } from './DesktopTerminalClient';
import type { TerminalCellPaint, TerminalMouseInput, TerminalMouseTracking, TerminalPaintFrame } from './terminal/TerminalEmulator';

const INSET: number = 10;
const INPUT_ID: string = 'desktopNativeTerminalInput';
const MULTI_CLICK_MS: number = 400;
const SCROLL_INTERVAL_MS: number = 70;
const NO_BUTTON: number = -1;
const MOUSE_LEFT: number = 0;
const MOUSE_MIDDLE: number = 1;
const MOUSE_RIGHT: number = 2;
const MOUSE_HOVER: number = 3;
const MOUSE_WHEEL: number = 4;
const MOUSE_RELEASE: number = 0;
const MOUSE_PRESS: number = 1;
const MOUSE_MOVE: number = 32;
const ESC: string = '\x1b';
const CANVAS_FONT_FAMILIES: Set<string> = new Set(['monospace', 'sans-serif', 'serif']);
const FUNCTION_KEYS: string[] = ['OP', 'OQ', 'OR', 'OS', '[15~', '[17~',
  '[18~', '[19~', '[20~', '[21~', '[23~', '[24~'];
let nextTerminalInput: number = 0;

interface TerminalHit {
  column: number;
  row: number;
}

interface TerminalPointer {
  x: number;
  y: number;
  ctrl: boolean;
  alt: boolean;
  shift: boolean;
}

@Component
export struct DesktopTerminalPane {
  host?: DesktopHostActions;
  @Prop @Watch('reloadSession') sessionId: string = '';
  @Prop @Watch('visibilityChanged') shown: boolean = true;
  @Prop @Watch('draw') appearance: string = 'system';
  @Prop @Watch('applyFont') cellFontSize: number = 13;
  @Prop @Watch('applyFontFamily') cellFontFamily: string = 'monospace';
  @Prop @Watch('createFromShortcut') createSession: string = '';
  preferredTerminal: string = '';
  observeRetention?: DesktopTerminalRetentionObserver;
  observeRoster?: DesktopTerminalRosterObserver;
  openInNewTab?: (row: DesktopTerminalRow) => boolean;
  onHidePanel: () => void = (): void => {};
  onCreateShortcut: () => void = () => {};
  onRename: () => void = () => {};
  onTerminalSelected: (sessionId: string, terminalId: string, title: string) => void =
    (_sessionId: string, _terminalId: string, _title: string): void => {};
  onShortcut: (event: KeyEvent) => boolean = (_event: KeyEvent): boolean => false;

  @State private state?: DesktopTerminalState = undefined;
  @State private input: string = '';
  @State private inputFocused: boolean = false;
  @State private visibleScreen: string = '';
  @State private selectionActive: boolean = false;
  @State private selectionMenu: boolean = false;
  @State private selectionMenuAnchor: Position = { x: 0, y: 0 };
  private readonly selection: DesktopTerminalSelection = new DesktopTerminalSelection();
  private readonly inputFocusId: string = `${INPUT_ID}:${nextTerminalInput++}`;
  private mouseSelecting: boolean = false;
  private reportedButton: number = NO_BUTTON;
  private localButton: number = NO_BUTTON;
  private lastPointer?: TerminalPointer;
  private dragX: number = 0;
  private dragY: number = 0;
  private dragRow: number = -1;
  private dragColumn: number = -1;
  private scrollDirection: number = 0;
  private scrollTimer: number = -1;
  private lastClickAt: number = 0;
  private lastClickRow: number = -1;
  private lastClickColumn: number = -1;
  private clickCount: number = 0;
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
  private shiftLeft: boolean = false;
  private shiftRight: boolean = false;
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
    this.resetMouse(true);
    this.active = false;
    this.clearSelection();
    this.dismissCloseDialog();
    this.client?.dispose();
    this.client = undefined;
  }

  private reloadSession(): void {
    this.resetMouse(true);
    this.clearSelection();
    this.dismissCloseDialog();
    this.client?.dispose();
    this.client = undefined;
    this.state = undefined;
    this.frame = undefined;
    this.visibleScreen = '';
    this.draw();
    if (this.host === undefined || !this.active || !this.shown || this.sessionId.length === 0) {
      return;
    }
    const id = this.sessionId;
    this.client = new DesktopTerminalClient(this.host, id, (state: DesktopTerminalState): void => {
      if (!this.active || this.sessionId !== id) {
        return;
      }
      const previous = this.state?.selected ?? '';
      const previousTitle = this.selected()?.title ?? '';
      this.state = state;
      if (state.selected !== previous) { this.resetMouse(false); this.clearSelection(); }
      else if (!state.writable && this.reportedButton !== NO_BUTTON) { this.resetMouse(false); }
      const title = this.selected()?.title ?? '';
      if (state.selected !== previous || title !== previousTitle) {
        this.onTerminalSelected(id, state.selected, title);
      }
      this.createFromShortcut();
    }, (frame: TerminalPaintFrame | undefined): void => {
      if (!this.active || this.sessionId !== id) {
        return;
      }
      this.frame = frame;
      this.selectionActive = frame !== undefined && this.selection.hasSelection(frame);
      this.visibleScreen = this.client?.visibleText() ?? '';
      this.draw();
    }, this.observeRetention, this.openInNewTab, this.observeRoster);
    this.fit();
    this.client.start(this.preferredTerminal);
  }

  private visibilityChanged(): void {
    if (!this.active) { return; }
    if (!this.shown) { this.resetMouse(true); this.clearSelection(); }
    if (this.shown && this.client === undefined) { this.reloadSession(); }
    else { this.client?.setShown(this.shown); }
  }

  private createFromShortcut(): void {
    if (this.createSession.length === 0) { this.createIssued = false; return; }
    if (!this.active || !this.shown || this.createIssued || this.createSession !== this.sessionId || this.client === undefined ||
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
        action: (): void => {
          if (this.openInNewTab?.(row) !== true) { this.client?.select(row.id); }
        }
      });
    }
    return items;
  }

  private async writeClipboard(text: string): Promise<void> {
    if (text.length > 0) {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
    }
  }

  private copyScreen(): Promise<void> { return this.writeClipboard(this.client?.visibleText() ?? ''); }

  private copySelection(): void {
    const frame = this.frame;
    if (frame !== undefined) { this.writeClipboard(this.selection.text(frame)).catch((): void => {}); }
  }

  private async pasteScreen(): Promise<void> {
    const owner = this.client;
    const terminal = this.state?.selected;
    if (!this.active || !this.shown || this.state?.writable !== true || owner === undefined || !terminal) { return; }
    const data = await pasteboard.getSystemPasteboard().getData();
    if (this.active && this.shown && this.client === owner && this.state?.selected === terminal && this.state?.writable) {
      const value = data.getPrimaryText();
      if (value !== undefined) {
        this.pasteInput(value);
      }
    }
  }

  private actions(): MenuElement[] {
    return [
      { value: $r('app.string.desktop_terminal_rename_action'), action: this.onRename },
      { value: '重连终端', action: (): void => { this.client?.reconnect(); } },
      { value: '复制当前屏幕', action: (): void => {
        this.copyScreen().catch((): void => {});
      } },
      { value: '粘贴', action: (): void => {
        this.pasteScreen().catch((): void => {});
      } },
      { value: '发送 Ctrl+C', action: (): void => { this.writeInput('\x03'); } },
      { value: '关闭终端', action: (): void => { this.confirmClose(); } }
    ];
  }

  private retryTerminal(): void {
    const client = this.client;
    if (client === undefined || this.state?.busy) { return; }
    switch (this.state?.issue) {
      case 'discovery': client.start(this.preferredTerminal); break;
      case 'create': client.retryCreate(); break;
      case 'attach': client.reconnect(); break;
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
    if (this.active && this.shown && this.state?.selected) {
      try { this.getUIContext().getFocusController().requestFocus(this.inputFocusId); } catch (_) {}
    }
  }

  private hit(x: number, y: number): TerminalHit {
    const maximum = Math.max(0, (this.frame?.rows.length ?? 1) - 1);
    return { column: Math.max(0, Math.floor((x - INSET) / this.charWidth)),
      row: Math.max(0, Math.min(maximum, Math.floor((y - INSET) / this.lineHeight()))) };
  }

  private updateSelection(): void {
    const frame = this.frame;
    this.selectionActive = frame !== undefined && this.selection.hasSelection(frame);
    this.draw();
  }

  private clearSelection(): void {
    this.endSelectionDrag();
    this.selection.clear();
    const repaint = this.selectionActive;
    this.selectionActive = false;
    this.selectionMenu = false;
    this.clickCount = 0;
    if (repaint) { this.draw(); }
  }

  private startMouseSelection(event: MouseEvent, shift: boolean): void {
    const frame = this.frame;
    if (frame === undefined) { return; }
    const point = this.hit(event.x, event.y);
    const time = Date.now();
    const repeated = time - this.lastClickAt < MULTI_CLICK_MS && point.row === this.lastClickRow &&
      point.column === this.lastClickColumn;
    this.clickCount = repeated ? this.clickCount % 3 + 1 : 1;
    this.lastClickAt = time;
    this.lastClickRow = point.row;
    this.lastClickColumn = point.column;
    if (shift && this.selectionActive) {
      this.selection.extend(frame, point.column, point.row);
    } else if (this.clickCount === 2) {
      this.selection.selectWord(frame, point.column, point.row);
    } else if (this.clickCount === 3) {
      this.selection.selectLine(frame, point.column, point.row);
    } else {
      this.selection.begin(frame, point.column, point.row);
    }
    this.mouseSelecting = true;
    this.dragRow = point.row;
    this.dragColumn = point.column;
    this.updateSelection();
    this.focusInput();
  }

  private moveMouseSelection(x: number, y: number): void {
    const frame = this.frame;
    if (!this.mouseSelecting || frame === undefined) { return; }
    this.dragX = x;
    this.dragY = y;
    const point = this.hit(x, y);
    if (point.row !== this.dragRow || point.column !== this.dragColumn) {
      this.dragRow = point.row;
      this.dragColumn = point.column;
      this.selection.extend(frame, point.column, point.row);
      this.clickCount = 0;
      this.updateSelection();
    }
    const bottom = INSET + frame.rows.length * this.lineHeight();
    this.setSelectionScroll(y < INSET ? -1 : y >= bottom ? 1 : 0);
  }

  private setSelectionScroll(direction: number): void {
    if (this.scrollDirection === direction) { return; }
    clearInterval(this.scrollTimer);
    this.scrollTimer = -1;
    this.scrollDirection = direction;
    if (direction === 0) { return; }
    this.scrollTimer = setInterval((): void => {
      if (!this.active || !this.shown || !this.mouseSelecting) { this.endSelectionDrag(); return; }
      const previous = this.frame?.selection?.viewportTop;
      this.client?.scroll(direction);
      const frame = this.frame;
      if (previous === frame?.selection?.viewportTop) { this.setSelectionScroll(0); return; }
      if (frame !== undefined) {
        const point = this.hit(this.dragX, this.dragY);
        this.selection.extend(frame, point.column, point.row);
        this.updateSelection();
      }
    }, SCROLL_INTERVAL_MS);
  }

  private endSelectionDrag(): void {
    this.mouseSelecting = false;
    this.setSelectionScroll(0);
  }

  private terminalMouseButton(button: MouseButton): number {
    switch (button) {
      case MouseButton.Left: return MOUSE_LEFT;
      case MouseButton.Middle: return MOUSE_MIDDLE;
      case MouseButton.Right: return MOUSE_RIGHT;
      default: return NO_BUTTON;
    }
  }

  private pointer(x: number, y: number, event: BaseEvent): TerminalPointer {
    return { x: x, y: y, ctrl: event.getModifierKeyState?.(['Ctrl']) === true,
      alt: event.getModifierKeyState?.(['Alt']) === true,
      shift: this.shiftLeft || this.shiftRight || event.getModifierKeyState?.(['Shift']) === true };
  }

  private mouseTracking(): TerminalMouseTracking {
    return this.state?.writable === true ? this.client?.mouseModes()?.tracking ?? 'none' : 'none';
  }

  private sendPointer(point: TerminalPointer, button: number, action: number): void {
    const frame = this.frame;
    if (frame === undefined || this.state?.writable !== true) { return; }
    const hit = this.hit(point.x, point.y);
    const x = Math.min(Math.max(0, frame.selection.columns * this.charWidth - 1), Math.max(0, point.x - INSET));
    const y = Math.min(Math.max(0, frame.rows.length * this.lineHeight() - 1), Math.max(0, point.y - INSET));
    const report: TerminalMouseInput = { column: Math.min(frame.selection.columns - 1, hit.column), row: hit.row,
      x: x, y: y, button: button, action: action, ctrl: point.ctrl, alt: point.alt, shift: point.shift };
    this.client?.reportMouse(report);
  }

  private finishReportedMouse(point?: TerminalPointer): void {
    const button = this.reportedButton;
    this.reportedButton = NO_BUTTON;
    const position = point ?? this.lastPointer;
    this.lastPointer = undefined;
    if (button !== NO_BUTTON && position !== undefined) { this.sendPointer(position, button, MOUSE_RELEASE); }
  }

  private resetMouse(release: boolean): void {
    if (release) { this.finishReportedMouse(); }
    else {
      this.reportedButton = NO_BUTTON;
      this.lastPointer = undefined;
    }
    this.localButton = NO_BUTTON;
    this.endSelectionDrag();
  }

  private terminalMouse(event: MouseEvent): void {
    if (!this.active || !this.shown) { return; }
    const button = this.terminalMouseButton(event.button);
    if (event.action === MouseAction.Press && button !== NO_BUTTON) {
      const point = this.pointer(event.x, event.y, event);
      if (!point.shift && this.mouseTracking() !== 'none') {
        this.clearSelection();
        this.localButton = NO_BUTTON;
        this.reportedButton = button;
        this.lastPointer = point;
        this.focusInput();
        this.sendPointer(point, button, MOUSE_PRESS);
      } else {
        this.localButton = button;
        if (button === MOUSE_LEFT) { this.startMouseSelection(event, point.shift); }
      }
    } else if (event.action === MouseAction.Move) {
      if (this.reportedButton !== NO_BUTTON) {
        const point = this.pointer(event.x, event.y, event);
        this.lastPointer = point;
        this.sendPointer(point, this.reportedButton, MOUSE_MOVE);
      } else if (this.localButton === MOUSE_LEFT) {
        this.moveMouseSelection(event.x, event.y);
      } else if (this.localButton === NO_BUTTON && this.mouseTracking() === 'any') {
        this.sendPointer(this.pointer(event.x, event.y, event), MOUSE_HOVER, MOUSE_MOVE);
      }
    } else if (event.action === MouseAction.Release) {
      if (this.reportedButton !== NO_BUTTON && (button === this.reportedButton || button === NO_BUTTON)) {
        this.finishReportedMouse(this.pointer(event.x, event.y, event));
      } else if (button === this.localButton) {
        this.localButton = NO_BUTTON;
        if (button === MOUSE_LEFT) {
          this.moveMouseSelection(event.x, event.y);
          this.endSelectionDrag();
        } else if (button === MOUSE_RIGHT) {
          this.openSelectionMenu(event.x, event.y);
        }
      }
    }
  }

  private terminalMousePan(event: GestureEvent): void {
    const point = event.fingerList[0];
    if (point === undefined) { return; }
    if (this.reportedButton === NO_BUTTON) {
      this.moveMouseSelection(point.localX, point.localY);
      return;
    }
    if (this.lastPointer !== undefined && (point.localX < 0 || point.localX >= this.canvasWidth ||
      point.localY < 0 || point.localY >= this.canvasHeight)) {
      const last = this.lastPointer;
      const current: TerminalPointer = { x: point.localX, y: point.localY, ctrl: last.ctrl,
        alt: last.alt, shift: last.shift };
      this.lastPointer = current;
      this.sendPointer(current, this.reportedButton, MOUSE_MOVE);
    }
  }

  private terminalWheel(event: AxisEvent): void {
    const client = this.client;
    if (client === undefined || !this.shown) { return; }
    const vertical = event.getVerticalAxisValue();
    const horizontal = event.getHorizontalAxisValue();
    const delta = vertical === 0 ? horizontal : vertical;
    const point = this.pointer(event.x, event.y, event);
    if (delta === 0 || point.shift) { return; }
    const modes = client.mouseModes();
    const hasWheelReport = this.state?.writable === true && modes !== undefined &&
      modes.tracking !== 'none' && modes.tracking !== 'x10';
    const discrete = event.sourceTool === SourceTool.MOUSE || (event.scrollStep ?? 0) > 0;
    const units = discrete ? Math.sign(delta) * Math.max(1, Math.min(40, event.scrollStep || 3)) : delta;
    const steps = client.wheelSteps(units, discrete ? 1 : 0, this.lineHeight(), point.ctrl, point.alt, false);
    if (steps === 0) { return; }
    if (hasWheelReport) {
      this.sendPointer(point, MOUSE_WHEEL, (vertical === 0 ? 2 : 0) + (steps > 0 ? 1 : 0));
    } else if (vertical !== 0) {
      if (modes?.alternateWheel && this.state?.writable) {
        const prefix = client.applicationCursor() ? 'O' : '[';
        client.write(ESC + prefix + (steps > 0 ? 'B' : 'A'), false);
      } else {
        client.scroll(steps);
      }
    }
  }

  private openSelectionMenu(x: number, y: number): void {
    this.endSelectionDrag();
    this.selectionMenuAnchor = { x: Math.max(0, Math.min(this.canvasWidth - 1, x)),
      y: Math.max(0, Math.min(this.canvasHeight - 1, y)) };
    this.selectionMenu = true;
  }

  @Builder
  private SelectionMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.desktop_terminal_copy_selection') }).key('desktopTerminalCopySelection')
        .enabled(this.selectionActive).onChange((): void => { this.selectionMenu = false; this.copySelection(); })
      MenuItem({ content: $r('app.string.desktop_terminal_paste') }).key('desktopTerminalPaste')
        .enabled(this.state?.writable === true)
        .onChange((): void => { this.selectionMenu = false; this.pasteScreen().catch((): void => {}); })
      MenuItem({ content: $r('app.string.desktop_terminal_select_all') }).key('desktopTerminalSelectAll')
        .enabled(this.frame !== undefined).onChange((): void => {
          const frame = this.frame;
          this.selectionMenu = false;
          if (frame !== undefined) { this.selection.selectAll(frame); this.updateSelection(); }
          this.focusInput();
        })
    }
  }

  private writeInput(text: string): void {
    if (this.state?.writable !== true || !text) { return; }
    this.clearSelection();
    this.client?.scrollToBottom();
    this.client?.write(text);
  }

  private pasteInput(text: string): void {
    if (this.state?.writable !== true || !text) { return; }
    this.clearSelection();
    this.client?.scrollToBottom();
    this.client?.paste(text);
  }

  private handleTerminalKey(event: KeyEvent): boolean {
    const code = event.keyCode;
    const down = event.type === KeyType.Down;
    if (code === KeyCode.KEYCODE_CTRL_LEFT || code === KeyCode.KEYCODE_CTRL_RIGHT) {
      this.ctrl = down;
      return false;
    }
    if (code === KeyCode.KEYCODE_SHIFT_LEFT || code === KeyCode.KEYCODE_SHIFT_RIGHT) {
      // The focused keyboard can report Shift even when a separate pointer omits it.
      if (code === KeyCode.KEYCODE_SHIFT_LEFT) { this.shiftLeft = down; }
      else { this.shiftRight = down; }
      return false;
    }
    if (this.onShortcut(event)) { return true; }
    if (!down) { return false; }
    const control = event.getModifierKeyState?.(['Ctrl']) ?? this.ctrl;
    const shift = event.getModifierKeyState?.(['Shift']) === true;
    if (control && shift && code === KeyCode.KEYCODE_C) { this.copySelection(); return true; }
    if (control && shift && code === KeyCode.KEYCODE_V) { this.pasteScreen().catch((): void => {}); return true; }
    if (shift && (code === KeyCode.KEYCODE_PAGE_UP || code === KeyCode.KEYCODE_PAGE_DOWN)) {
      const lines = Math.max(1, (this.frame?.rows.length ?? 1) - 1);
      this.client?.scroll(code === KeyCode.KEYCODE_PAGE_UP ? -lines : lines);
      return true;
    }
    if (!this.state?.writable) { return false; }
    let text = '';
    if (control && code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z) {
      if (code === KeyCode.KEYCODE_V) {
        return false;
      }
      text = String.fromCharCode(code - KeyCode.KEYCODE_A + 1);
    } else if (control && code === KeyCode.KEYCODE_SPACE) {
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
        case KeyCode.KEYCODE_TAB: text = shift ? ESC + '[Z' : '\t'; break;
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
    this.writeInput(text);
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
    const ranges: DesktopTerminalSelectionSpan[] = this.selectionActive ? this.selection.spans(frame) : [];
    const highlight = dark ? '#365584' : '#c6defc';
    let rangeIndex = 0;
    let font = '';
    let foreground = '';
    for (let row = 0; row < frame.rows.length; row++) {
      const y = INSET + row * lineHeight;
      if (y >= this.canvasHeight) {
        break;
      }
      const range = ranges[rangeIndex]?.row === row ? ranges[rangeIndex++] : undefined;
      if (range !== undefined) {
        canvas.fillStyle = highlight;
        canvas.fillRect(INSET + range.start * this.charWidth, y, (range.end - range.start) * this.charWidth, lineHeight);
        foreground = '';
      }
      for (const cell of frame.rows[row]) {
        const x = INSET + cell.column * this.charWidth;
        const width = cell.cells * this.charWidth;
        if (cell.background) {
          canvas.fillStyle = cell.background === 'foreground' ? ink : cell.background;
          canvas.fillRect(x, y, width, lineHeight);
          if (range !== undefined) {
            const start = Math.max(range.start, cell.column);
            const end = Math.min(range.end, cell.column + cell.cells);
            if (start < end) {
              canvas.fillStyle = highlight;
              canvas.fillRect(INSET + start * this.charWidth, y, (end - start) * this.charWidth, lineHeight);
            }
          }
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
        .key('desktopNativeTerminalScreen')
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
        .accessibilitySelected(this.selectionActive)
        .onClick((): void => { this.focusInput(); })
        .onMouse((event: MouseEvent): void => { this.terminalMouse(event); })
        .onAxisEvent((event: AxisEvent): void => { this.terminalWheel(event); })
        .gesture(PanGesture({ direction: PanDirection.Vertical }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
          .onActionStart((): void => { this.scrollY = 0; })
          .onActionUpdate((event: GestureEvent): void => {
            const lines = Math.trunc((this.scrollY - event.offsetY) / this.lineHeight());
            if (lines !== 0) {
              this.scrollY -= lines * this.lineHeight();
              this.client?.scroll(lines);
            }
          }))
        .parallelGesture(PanGesture({ direction: PanDirection.All, distance: 3 }).allowedTypes([SourceTool.MOUSE])
          .onActionUpdate((event: GestureEvent): void => { this.terminalMousePan(event); })
          .onActionEnd((): void => { this.resetMouse(true); })
          .onActionCancel((): void => { this.resetMouse(true); }))
        .parallelGesture(LongPressGesture({ duration: 450 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
          .onAction((event: GestureEvent): void => {
            const point = event.fingerList[0];
            if (point !== undefined) {
              const frame = this.frame;
              if (frame !== undefined && !this.selectionActive) {
                const hit = this.hit(point.localX, point.localY);
                this.selection.selectWord(frame, hit.column, hit.row);
                this.updateSelection();
              }
              this.openSelectionMenu(point.localX, point.localY);
            }
          }))
      TextInput({ text: this.input })
        .key(INPUT_ID)
        .id(this.inputFocusId)
        .width(80).height(30).opacity(0.01).backgroundColor(Color.Transparent)
        .caretColor(Color.Transparent).fontColor(Color.Transparent)
        .accessibilityText('终端输入')
        .enabled(this.state?.selected !== undefined)
        .enableKeyboardOnFocus(this.state?.writable === true)
        .hitTestBehavior(HitTestMode.None)
        .enablePreviewText(false)
        .enterKeyType(EnterKeyType.Done)
        .onFocus((): void => { this.inputFocused = true; this.draw(); })
        .onBlur((): void => {
          this.inputFocused = false;
          this.ctrl = false;
          this.shiftLeft = false;
          this.shiftRight = false;
          this.draw();
        })
        .onKeyPreIme((event: KeyEvent): boolean => this.handleTerminalKey(event))
        .onSubmit((): void => { this.writeInput('\r'); })
        .onPaste((value: string, event: PasteEvent): void => {
          event.preventDefault?.();
          this.pasteInput(value);
        })
        .onChange((value: string): void => {
          if (!value) {
            return;
          }
          this.input = value;
          this.writeInput(value);
          setTimeout((): void => { this.input = ''; }, 0);
        })
      Row().width(1).height(1).position(this.selectionMenuAnchor).hitTestBehavior(HitTestMode.None)
        .bindContextMenu(this.selectionMenu, this.SelectionMenu(), {
          placement: Placement.BottomLeft,
          systemMaterial: desktopMenuOptions(Placement.BottomLeft).systemMaterial,
          onDisappear: (): void => { this.selectionMenu = false; }
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
      if (this.state?.selected) {
        if (this.state.canTakeInput) {
          Row({ space: 8 }) {
            Text($r('app.string.desktop_terminal_view_readonly')).fontSize(13)
              .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            Button($r('app.string.desktop_terminal_take_input'), { buttonStyle: ButtonStyleMode.NORMAL })
              .key('desktopTerminalTakeInput').height(28).onClick((): void => { this.client?.reconnect(); })
          }.width('100%').padding(10)
        }
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
