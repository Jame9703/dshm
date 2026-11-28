import { getArray, getBoolean, getNumber, getRecord, getString, randomUuid } from 'connection';
import type { DuplexStream } from 'connection';
import { DesktopHostActions, desktopHostItems, desktopHostProblem } from './DesktopHostActions';
import { desktopTerminalLaunchShell, readDesktopTerminalShells } from './DesktopTerminalShells';
import type { DesktopShellCatalog, DesktopTerminalShellPreference } from './DesktopTerminalShells';
import { loadTerminalEmulator } from './terminal/TerminalEmulator';
import type { TerminalEmulator, TerminalEmulatorFactory, TerminalPaintFrame } from './terminal/TerminalEmulator';
import type { TerminalMouseInput, TerminalMouseModes } from './terminal/TerminalEmulator';
import type { DesktopTerminalRosterSink } from './DesktopTerminalRosters';

export interface DesktopTerminalRow {
  id: string;
  title: string;
  state: string;
  exitCode?: number;
  cwd: string;
  origin?: string;
  control?: string;
  sandboxMode?: string;
}

export type DesktopTerminalIssue = 'none' | 'discovery' | 'create' | 'attach';

export interface DesktopTerminalState {
  terminals: DesktopTerminalRow[];
  selected: string;
  writable: boolean;
  canTakeInput: boolean;
  loading: boolean;
  busy: boolean;
  error: string;
  issue: DesktopTerminalIssue;
  outcome?: 'exited' | 'missing';
  exitCode?: number;
  canCreate: boolean;
}

interface DesktopTerminalCreateAttempt {
  id: string;
  shellPath: string;
  replacement: string;
  request: Record<string, Object>;
}

interface TerminalInput {
  type: string;
  data: string;
  typed: boolean;
  cols: number;
  rows: number;
}

interface ClosingTerminalFocus {
  stream: DuplexStream;
  waitAck: number;
  focusSequence: number;
  timer: number;
}

export type DesktopTerminalRetentionObserver = (id: string, listener: (problem: string, code?: string) => void) => () => void;
export type DesktopTerminalRosterObserver = (sink: DesktopTerminalRosterSink) => () => void;
export type DesktopTerminalReplacement = (sessionId: string, oldId: string, row: DesktopTerminalRow) => boolean;

const MAX_INPUT_QUEUE: number = 32768;
const ACK_TIMEOUT_MS: number = 10000;
const FOCUS_CLOSE_TIMEOUT_MS: number = 1000;
const FOCUS_OUT: string = '\x1b[O';
const DEFAULT_COLS: number = 80;
const DEFAULT_ROWS: number = 24;

function utf8Bytes(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index++) {
    const code = value.codePointAt(index) ?? 0;
    if (code > 0xFFFF) {
      bytes += 4;
      index++;
    } else {
      bytes += code > 0x7FF ? 3 : code > 0x7F ? 2 : 1;
    }
  }
  return bytes;
}

export class DesktopTerminalClient {
  private readonly host: DesktopHostActions;
  private readonly sessionId: string;
  private readonly onState: (view: DesktopTerminalState) => void;
  private readonly onDraw: (frame: TerminalPaintFrame | undefined) => void;
  private readonly observeRetention?: DesktopTerminalRetentionObserver;
  private readonly openInNewTab?: (row: DesktopTerminalRow) => boolean;
  private readonly observeRoster?: DesktopTerminalRosterObserver;
  private readonly replaceInPlace?: DesktopTerminalReplacement;
  private readonly shellPreference?: DesktopTerminalShellPreference;
  private live: boolean = true;
  private shown: boolean = true;
  private terminals: DesktopTerminalRow[] = [];
  private selected: string = '';
  private exited?: DesktopTerminalRow;
  private missing: string = '';
  private writable: boolean = false;
  private focused: boolean = false;
  private loading: boolean = true;
  private busy: boolean = false;
  private error: string = '';
  private issue: DesktopTerminalIssue = 'none';
  private discovering: boolean = false;
  private discovered: boolean = false;
  private createAttempt?: DesktopTerminalCreateAttempt;
  private unseenCreation?: DesktopTerminalRow;
  private checkingRosterId: string = '';
  private lastShellPath: string = '';
  private lastReplacement: string = '';
  private cols: number = DEFAULT_COLS;
  private rows: number = DEFAULT_ROWS;
  private desiredCols: number = DEFAULT_COLS;
  private desiredRows: number = DEFAULT_ROWS;
  private maxCols: number = 400;
  private maxRows: number = 160;
  private scrollback: number = 1000;
  private maxInputBytes: number = 16384;
  private maxFrameBytes: number = 32768;
  private generation: number = 0;
  private lastOutput: number = -1;
  private lastInput: number = 0;
  private waitAck: number = 0;
  private waitingFocusOut: boolean = false;
  private ackTimer: number = -1;
  private paintTimer: number = -1;
  private queueBytes: number = 0;
  private queue: TerminalInput[] = [];
  private stopWatch?: () => void;
  private stopRetentionObservation?: () => void;
  private stream?: DuplexStream;
  private readonly closingFocus: Map<number, ClosingTerminalFocus> = new Map();
  private emulator?: TerminalEmulator;
  private createEmulator?: TerminalEmulatorFactory;

  constructor(host: DesktopHostActions, sessionId: string,
    onState: (view: DesktopTerminalState) => void, onDraw: (frame: TerminalPaintFrame | undefined) => void,
    observeRetention?: DesktopTerminalRetentionObserver, openInNewTab?: (row: DesktopTerminalRow) => boolean,
    observeRoster?: DesktopTerminalRosterObserver, replaceInPlace?: DesktopTerminalReplacement,
    shellPreference?: DesktopTerminalShellPreference) {
    this.host = host;
    this.sessionId = sessionId;
    this.onState = onState;
    this.onDraw = onDraw;
    this.observeRetention = observeRetention;
    this.openInNewTab = openInNewTab;
    this.observeRoster = observeRoster;
    this.replaceInPlace = replaceInPlace;
    this.shellPreference = shellPreference;
  }

  async start(preferredId: string, pendingOccurrence: boolean = false): Promise<void> {
    if (!this.live || this.discovering || this.discovered) { return; }
    this.discovering = true;
    this.loading = true;
    this.error = '';
    this.issue = 'none';
    this.publish();
    const session: Record<string, Object> = { 'sessionId': this.sessionId };
    const agent: Record<string, Object> = { 'agentId': this.sessionId };
    const engine = loadTerminalEmulator().catch((): undefined => undefined);
    const replies = await Promise.all([
      this.host.call('terminal/list', session),
      this.host.call('terminal/environment', agent)
    ]);
    this.createEmulator = await engine;
    this.discovering = false;
    if (!this.live) {
      return;
    }
    this.loading = false;
    if (this.createEmulator === undefined) {
      this.error = '终端显示组件无法加载';
      this.issue = 'discovery';
      this.publish();
      return;
    }
    if (!replies[0].ok) {
      this.error = replies[0].error?.httpStatus === 404 ?
        '当前宿主未启用终端。可在插件管理中启用终端插件包。' : desktopHostProblem(replies[0]);
      this.issue = 'discovery';
      this.publish();
      return;
    }
    this.discovered = true;
    this.maxCols = getNumber(replies[1].value, 'maxCols') ?? this.maxCols;
    this.maxRows = getNumber(replies[1].value, 'maxRows') ?? this.maxRows;
    this.scrollback = getNumber(replies[1].value, 'scrollback') ?? this.scrollback;
    this.maxInputBytes = getNumber(replies[1].value, 'maxInputBytes') ?? this.maxInputBytes;
    this.setTerminals(desktopHostItems(replies[0]));
    const preferred = this.terminals.find((row: DesktopTerminalRow): boolean => row.id === preferredId);
    if (preferred !== undefined || (preferredId && this.openInNewTab !== undefined)) {
      this.select(preferredId);
    } else if (!pendingOccurrence && this.terminals.length > 0 && (!preferredId || this.openInNewTab === undefined)) {
      this.select(this.terminals[0].id);
    }
    this.openWatch();
    this.publish();
  }

  private openWatch(): void {
    if (!this.live || !this.shown || !this.discovered || this.stopWatch !== undefined) { return; }
    if (this.observeRoster !== undefined) {
      let receiving = true;
      this.stopWatch = (): void => { receiving = false; };
      const stop = this.observeRoster({
        items: (items: Object[]): void => { if (receiving) { this.setTerminals(items); } },
        problem: (message: string): void => { if (receiving) { this.error = message; this.publish(); } }
      });
      if (!receiving) { stop(); }
      else { this.stopWatch = stop; }
      return;
    }
    this.stopWatch = this.host.watch('terminal/watch', { 'sessionId': this.sessionId }, {
      onItem: (value: Object): void => {
        const wrapped: Record<string, Object> = { 'items': value };
        this.setTerminals(getArray(wrapped, 'items') ?? []);
      },
      onError: (_code: string, message: string): void => {
        this.stopWatch = undefined;
        this.error = message;
        this.publish();
      },
      onEnd: (): void => { this.stopWatch = undefined; }
    });
  }

  setShown(shown: boolean): void {
    if (this.shown === shown) { return; }
    this.shown = shown;
    if (shown) {
      this.openWatch();
      if (this.selected && (this.exited === undefined || this.emulator === undefined)) { this.select(this.selected); }
    } else {
      this.stopWatch?.();
      this.stopWatch = undefined;
      this.stopObservingRetention();
      this.detach(this.selectedRow()?.state === 'exited', true);
    }
  }

  replace(): Promise<void> {
    const id = this.selected;
    return id && (this.missing === id || this.selectedRow()?.state === 'exited') ?
      this.create('', id) : Promise.resolve();
  }

  async create(shellPath: string = '', replacement: string = ''): Promise<void> {
    if (!this.live || this.busy || !this.discovered || (replacement && replacement !== this.selected)) {
      return;
    }
    this.busy = true;
    this.lastShellPath = shellPath;
    this.lastReplacement = replacement;
    this.error = '';
    this.issue = 'none';
    this.publish();
    let attempt = this.createAttempt;
    if (attempt === undefined || attempt.shellPath !== shellPath || attempt.replacement !== replacement) {
      this.createAttempt = undefined;
      let selectedShell = shellPath;
      if (!selectedShell) {
        const catalog: DesktopShellCatalog = await readDesktopTerminalShells(this.host, this.sessionId)
          .catch((): DesktopShellCatalog => ({ choices: [], problem: 'terminal/shells' }));
        if (!this.live) { return; }
        if (catalog.problem) {
          this.busy = false;
          this.error = catalog.problem;
          this.issue = 'create';
          this.publish();
          return;
        }
        selectedShell = desktopTerminalLaunchShell(catalog.choices, this.shellPreference?.read() ?? '');
      }
      if (selectedShell) { this.shellPreference?.remember(selectedShell); }
      const id = 'native-' + randomUuid();
      const request: Record<string, Object> = {
        'id': id, 'cols': Math.min(this.maxCols, this.desiredCols), 'rows': Math.min(this.maxRows, this.desiredRows)
      };
      if (selectedShell) { request['shellPath'] = selectedShell; }
      attempt = { id: id, shellPath: shellPath, replacement: replacement, request: request };
      this.createAttempt = attempt;
    }
    const result = await this.host.call('terminal/create', { 'agentId': this.sessionId, 'request': attempt.request });
    if (!this.live) {
      return;
    }
    this.busy = false;
    const row = result.ok && result.value !== undefined ? this.project(result.value) : undefined;
    if (row?.id !== attempt.id) {
      const retained = this.retainedAttempt();
      if (retained !== undefined) { this.adopt(retained); return; }
      if (result.error?.code === 'terminal/unavailable') { this.createAttempt = undefined; }
      this.error = desktopHostProblem(result) || '宿主未返回终端';
      this.issue = 'create';
      this.publish();
      return;
    }
    if (!this.terminals.some((terminal: DesktopTerminalRow): boolean => terminal.id === row.id)) {
      this.unseenCreation = row;
    }
    this.adopt(row);
  }

  retryCreate(): void { this.create(this.lastShellPath, this.lastReplacement); }

  private retainedAttempt(): DesktopTerminalRow | undefined {
    const id = this.createAttempt?.id;
    return id === undefined ? undefined : this.terminals.find((row: DesktopTerminalRow): boolean =>
      row.id === id && (row.state === 'running' || row.state === 'exited'));
  }

  private adopt(row: DesktopTerminalRow): void {
    const replacement = this.createAttempt?.replacement ?? '';
    this.createAttempt = undefined;
    this.issue = 'none';
    this.error = '';
    if (!this.terminals.some((item: DesktopTerminalRow): boolean => item.id === row.id)) {
      this.terminals = [...this.terminals, row];
    }
    if (replacement) {
      if (this.selected !== replacement || this.replaceInPlace?.(this.sessionId, replacement, row) === false) {
        this.publish();
        return;
      }
      const ended = this.selectedRow()?.state === 'exited' && this.missing !== replacement;
      this.select(row.id);
      if (ended) {
        // Closing the replaced occurrence releases its finished Host screen, never the new terminal.
        this.host.call('terminal/close', { 'agentId': this.sessionId, 'id': replacement }).catch((): void => {});
      }
      return;
    }
    if (this.openInNewTab?.(row) === true) { this.publish(); return; }
    if (row.id === this.selected && this.stream !== undefined) { this.publish(); }
    else { this.select(row.id); }
  }

  async closeTerminal(id: string): Promise<void> {
    if (this.busy || !id) {
      return;
    }
    this.busy = true;
    this.publish();
    const result = await this.host.call('terminal/close', { 'agentId': this.sessionId, 'id': id });
    if (!this.live) {
      return;
    }
    this.busy = false;
    this.error = desktopHostProblem(result);
    if (result.ok) {
      if (this.unseenCreation?.id === id) { this.unseenCreation = undefined; }
      this.terminals = this.terminals.filter((row: DesktopTerminalRow): boolean => row.id !== id);
      if (this.selected === id && this.openInNewTab !== undefined) { this.forgetSelection(); }
      this.chooseRemaining();
    }
    this.publish();
  }

  select(id: string, force: boolean = false): void {
    if (!this.live || !id || (!force && id === this.selected && this.stream !== undefined)) {
      return;
    }
    const same = id === this.selected;
    if (same && (this.missing === id || (this.exited !== undefined && this.emulator !== undefined))) { return; }
    this.stopObservingRetention();
    this.detach(same && (force || this.selectedRow()?.state === 'exited'), !same);
    this.selected = id;
    if (!same) {
      this.missing = '';
      this.exited = undefined;
      this.recordExit(this.selectedRow());
    }
    this.error = '';
    this.issue = 'none';
    this.publish();
    if (!this.shown) { return; }
    if (this.observeRetention === undefined) { this.attachSelected(id); return; }
    this.stopRetentionObservation = this.observeRetention(id, (problem: string, code?: string): void => {
      if (!this.live || this.selected !== id || this.missing === id) { return; }
      if (problem) { this.ended(this.generation, problem, code); }
      else if (this.stream === undefined) { this.attachSelected(id); }
    });
  }

  reconnect(): void { this.select(this.selected, true); }

  private attachSelected(id: string): void {
    this.openWatch();
    this.error = '';
    this.issue = 'none';
    const generation = this.generation;
    const result = this.host.attach('terminal/attach', { 'agentId': this.sessionId, 'id': id }, {
      onItem: (value: Object): void => {
        if (this.live && this.generation === generation) {
          this.receive(value);
        } else {
          this.receiveClosingFocus(generation, value);
        }
      },
      onError: (code: string, message: string): void => { this.ended(generation, message, code); },
      onEnd: (): void => { this.ended(generation, '终端连接已结束'); }
    });
    this.stream = result;
    if (result === undefined) {
      this.error = '宿主连接正在重建，请重连终端';
      this.issue = 'attach';
    }
    this.publish();
  }

  private stopObservingRetention(): void {
    this.stopRetentionObservation?.();
    this.stopRetentionObservation = undefined;
  }

  resize(cols: number, rows: number): void {
    this.desiredCols = cols;
    this.desiredRows = rows;
    this.requestResize();
  }

  write(text: string, typed: boolean = true): void {
    if (!this.writable || this.stream === undefined || text.length === 0) {
      return;
    }
    const bytes = utf8Bytes(text);
    if (this.queueBytes + bytes > MAX_INPUT_QUEUE) {
      this.error = '待发送输入已满';
      this.publish();
      return;
    }
    const maximum = Math.min(this.maxInputBytes, Math.floor((this.maxFrameBytes - 100) / 6));
    if (maximum < 4) {
      this.error = '宿主的终端输入限制过小';
      this.publish();
      return;
    }
    let from = 0;
    let size = 0;
    for (let index = 0; index < text.length;) {
      const code = text.codePointAt(index) ?? 0;
      const count = code > 0xFFFF ? 2 : 1;
      const cost = count === 2 ? 4 : code > 0x7FF ? 3 : code > 0x7F ? 2 : 1;
      if (size + cost > maximum) {
        this.enqueueText(text.slice(from, index), size, typed);
        from = index;
        size = 0;
      }
      size += cost;
      index += count;
    }
    this.enqueueText(text.slice(from), size, typed);
    this.sendNext();
  }

  paste(text: string): void {
    this.write(this.emulator?.paste(text) ?? text);
  }

  scroll(lines: number): void {
    this.emulator?.scroll(lines);
    this.draw();
  }

  scrollToBottom(): void {
    if (this.emulator?.scrollToBottom()) { this.draw(); }
  }

  visibleText(): string {
    return this.emulator?.visibleText() ?? '';
  }

  applicationCursor(): boolean {
    return this.emulator?.isApplicationCursor() === true;
  }

  setFocused(focused: boolean): void {
    this.focused = focused;
    this.emulator?.setFocused(focused);
  }

  mouseModes(): TerminalMouseModes | undefined { return this.emulator?.mouseModes(); }

  reportMouse(event: TerminalMouseInput): void {
    const emulator = this.emulator;
    if (!this.writable || emulator === undefined) { return; }
    const top = emulator.viewportTop();
    emulator.mouse(event);
    if (top !== emulator.viewportTop()) { this.draw(); }
  }

  wheelSteps(delta: number, mode: number, lineHeight: number, ctrl: boolean, alt: boolean, shift: boolean): number {
    return this.emulator?.wheelSteps(delta, mode, lineHeight, ctrl, alt, shift) ?? 0;
  }

  dispose(): void {
    this.live = false;
    this.stopObservingRetention();
    this.stopWatch?.();
    this.detach(false, true);
  }

  private project(value: Object): DesktopTerminalRow {
    const shell = getRecord(value, 'shell');
    return {
      id: getString(value, 'id') ?? '',
      title: getString(value, 'title') || getString(shell, 'name') || '终端',
      state: getString(value, 'state') ?? '',
      exitCode: getNumber(value, 'exitCode'),
      cwd: getString(value, 'cwd') ?? '', origin: getString(value, 'origin'),
      control: getString(value, 'control'), sandboxMode: getString(value, 'sandboxMode')
    };
  }

  private selectedRow(): DesktopTerminalRow | undefined {
    if (this.exited !== undefined) { return this.exited; }
    return this.terminals.find((row: DesktopTerminalRow): boolean => row.id === this.selected);
  }

  private recordExit(row?: DesktopTerminalRow): void {
    if (row?.state !== 'exited' || row.id !== this.selected) { return; }
    if (this.exited === undefined || this.exited.exitCode === undefined || row.exitCode !== undefined) {
      this.exited = row;
    }
    this.writable = false;
    if (this.issue === 'attach') {
      this.error = '';
      this.issue = 'none';
    }
  }

  private setTerminals(items: Object[]): void {
    if (!this.live) {
      return;
    }
    const rows = items.map((item: Object): DesktopTerminalRow => this.project(item))
      .filter((row: DesktopTerminalRow): boolean => row.id.length > 0);
    const created = this.unseenCreation;
    if (created !== undefined && !rows.some((row: DesktopTerminalRow): boolean => row.id === created.id)) {
      this.terminals = [...rows, created];
      this.confirmCreatedRoster(created.id);
    } else {
      this.unseenCreation = undefined;
      this.terminals = rows;
    }
    this.recordExit(rows.find((row: DesktopTerminalRow): boolean => row.id === this.selected));
    if (!this.busy && this.issue === 'create') {
      const retained = this.retainedAttempt();
      if (retained !== undefined) { this.adopt(retained); return; }
    }
    this.chooseRemaining();
    this.publish();
  }

  // A watch snapshot received after create may have been captured before it committed.
  private async confirmCreatedRoster(id: string): Promise<void> {
    if (this.checkingRosterId === id) { return; }
    this.checkingRosterId = id;
    const result = await this.host.call('terminal/list', { 'sessionId': this.sessionId });
    if (this.checkingRosterId === id) { this.checkingRosterId = ''; }
    if (!this.live || this.unseenCreation?.id !== id || !result.ok) { return; }
    const items = desktopHostItems(result);
    if (!items.some((item: Object): boolean => getString(item, 'id') === id)) {
      this.unseenCreation = undefined;
      this.setTerminals(items);
    }
  }

  private chooseRemaining(): void {
    if (this.selected.length > 0 && !this.terminals.some((row: DesktopTerminalRow): boolean => row.id === this.selected)) {
      if (this.openInNewTab !== undefined) { return; }
      this.forgetSelection();
      if (this.terminals.length > 0) {
        this.select(this.terminals[0].id);
      }
    }
  }

  private forgetSelection(): void {
    this.stopObservingRetention();
    this.selected = '';
    this.exited = undefined;
    this.missing = '';
    this.detach(false, true);
  }

  private updateTerminalInfo(value: Object | undefined): void {
    this.updateSize(value);
    if (value === undefined) { return; }
    const update = this.project(value);
    if (!update.id || update.id !== this.selected) { return; }
    this.recordExit(update);
    this.terminals = this.terminals.some((row: DesktopTerminalRow): boolean => row.id === update.id) ?
      this.terminals.map((row: DesktopTerminalRow): DesktopTerminalRow => row.id === update.id ? update : row) :
      [...this.terminals, update];
  }

  private receive(value: Object): void {
    const kind = getString(value, 'type');
    if (kind === 'snapshot') {
      this.updateTerminalInfo(getRecord(value, 'info'));
      this.writable = getBoolean(value, 'writable') === true && this.selectedRow()?.state !== 'exited';
      this.maxFrameBytes = getNumber(getRecord(value, 'inputWindow'), 'maxFrameBytes') ?? this.maxFrameBytes;
      this.lastOutput = getNumber(value, 'sequence') ?? 0;
      this.emulator?.dispose();
      const generation = this.generation;
      this.emulator = this.createEmulator?.(this.cols, this.rows, this.scrollback, (reply: string): void => {
        if (this.generation === generation) { this.write(reply, false); }
      }, (report: string, binary: boolean, pressed: boolean): void => {
        // The Web client sends onData only, and this Host protocol carries UTF-8 text.
        if (!binary && this.generation === generation) { this.write(report, pressed); }
      });
      this.emulator?.setFocused(this.focused && this.shown);
      this.paintText(getString(value, 'screen') ?? '', true);
      this.publish();
    } else if (kind === 'output') {
      const sequence = getNumber(value, 'sequence') ?? -1;
      if (sequence !== this.lastOutput + 1) {
        this.ended(this.generation, '终端输出不连续，请重连以恢复画面');
        return;
      }
      this.lastOutput = sequence;
      this.paintText(getString(value, 'data') ?? '');
    } else if (kind === 'state') {
      this.updateTerminalInfo(getRecord(value, 'info'));
      this.writable = getBoolean(value, 'writable') === true && this.selectedRow()?.state !== 'exited';
      this.requestResize();
      this.publish();
      this.draw();
    } else if (kind === 'ack') {
      if (getNumber(value, 'sequence') !== this.waitAck) {
        return;
      }
      clearTimeout(this.ackTimer);
      this.waitAck = 0;
      this.waitingFocusOut = false;
      const refusal = getString(value, 'refusal');
      if (refusal) {
        this.writable = false;
        this.queue = [];
        this.queueBytes = 0;
        this.error = refusal === 'read-only' ? '另一窗口持有输入控制' : '终端已停止运行';
        this.publish();
      } else {
        this.sendNext();
      }
    }
  }

  private updateSize(info?: Object): void {
    const cols = getNumber(info, 'cols') ?? this.cols;
    const rows = getNumber(info, 'rows') ?? this.rows;
    if (cols !== this.cols || rows !== this.rows) {
      this.cols = cols;
      this.rows = rows;
      this.emulator?.resize(cols, rows);
    }
  }

  private requestResize(): void {
    const cols = Math.max(2, Math.min(this.maxCols, this.desiredCols));
    const rows = Math.max(1, Math.min(this.maxRows, this.desiredRows));
    if (!this.writable || (cols === this.cols && rows === this.rows)) {
      return;
    }
    const last = this.queue[this.queue.length - 1];
    if (last?.type === 'resize') {
      last.cols = cols;
      last.rows = rows;
    } else {
      this.queue.push({ type: 'resize', data: '', typed: false, cols: cols, rows: rows });
    }
    this.sendNext();
  }

  private enqueueText(text: string, bytes: number, typed: boolean): void {
    if (bytes > 0) {
      this.queue.push({ type: 'write', data: text, typed: typed, cols: 0, rows: 0 });
      this.queueBytes += bytes;
    }
  }

  private async sendNext(): Promise<void> {
    const stream = this.stream;
    if (!this.writable || stream === undefined || this.waitAck > 0 || this.queue.length === 0) {
      return;
    }
    const next = this.queue.shift();
    if (next === undefined) {
      return;
    }
    const sequence = ++this.lastInput;
    this.waitAck = sequence;
    this.waitingFocusOut = next.type === 'write' && !next.typed && next.data === FOCUS_OUT;
    const generation = this.generation;
    const payload: Record<string, Object> = { 'type': next.type, 'sequence': sequence };
    if (next.type === 'write') {
      payload['data'] = next.data;
      payload['typed'] = next.typed;
      this.queueBytes -= utf8Bytes(next.data);
    } else {
      payload['cols'] = next.cols;
      payload['rows'] = next.rows;
    }
    this.ackTimer = setTimeout((): void => {
      this.ended(generation, '终端未确认输入，请重连');
    }, ACK_TIMEOUT_MS);
    if (!(await stream.send(payload))) {
      this.ended(generation, '终端输入发送失败，请重连');
    }
  }

  private paintText(text: string, initial: boolean = false): void {
    const emulator = this.emulator;
    emulator?.write(text, (): void => {
      if (this.live && emulator === this.emulator) {
        if (initial) {
          this.requestResize();
        }
        this.draw();
      }
    });
  }

  private draw(): void {
    if (this.paintTimer >= 0) {
      return;
    }
    this.paintTimer = setTimeout((): void => {
      this.paintTimer = -1;
      this.onDraw(this.emulator?.frame());
    }, 16);
  }

  private ended(generation: number, message: string, code?: string): void {
    if (this.closeFocusStream(generation)) { return; }
    if (this.live && this.generation === generation) {
      if (code === 'terminal/unavailable') { this.missing = this.selected; }
      const missing = this.missing.length > 0 && this.missing === this.selected;
      const exited = this.selectedRow()?.state === 'exited';
      this.detach(!missing);
      if (exited && !missing) { this.draw(); }
      if (this.issue !== 'create') {
        this.error = missing || exited ? '' : message;
        this.issue = missing || exited ? 'none' : 'attach';
      }
      this.publish();
    }
  }

  private holdStreamForFocus(stream: DuplexStream, generation: number): boolean {
    if (!this.writable || this.waitAck === 0 || (!this.waitingFocusOut &&
      !this.queue.some((item: TerminalInput): boolean => item.type === 'write' && !item.typed && item.data === FOCUS_OUT))) {
      return false;
    }
    // Keep the old attachment until the final focus-out is acknowledged. Unsent typing is discarded as on regular detach.
    const closing: ClosingTerminalFocus = { stream: stream, waitAck: this.waitAck,
      focusSequence: this.waitingFocusOut ? this.waitAck : this.lastInput + 1,
      timer: setTimeout((): void => { this.closeFocusStream(generation); }, FOCUS_CLOSE_TIMEOUT_MS) };
    this.closingFocus.set(generation, closing);
    return true;
  }

  private receiveClosingFocus(generation: number, value: Object): void {
    const closing = this.closingFocus.get(generation);
    if (closing === undefined || getString(value, 'type') !== 'ack' ||
      getNumber(value, 'sequence') !== closing.waitAck) { return; }
    if (closing.waitAck === closing.focusSequence || getString(value, 'refusal')) {
      this.closeFocusStream(generation);
      return;
    }
    closing.waitAck = closing.focusSequence;
    const focusOut: Record<string, Object> = { 'type': 'write', 'sequence': closing.focusSequence,
      'data': FOCUS_OUT, 'typed': false };
    closing.stream.send(focusOut).then((sent: boolean): void => {
      if (!sent) { this.closeFocusStream(generation); }
    }).catch((): void => { this.closeFocusStream(generation); });
  }

  private closeFocusStream(generation: number): boolean {
    const closing = this.closingFocus.get(generation);
    if (closing === undefined) { return false; }
    this.closingFocus.delete(generation);
    clearTimeout(closing.timer);
    closing.stream.close();
    return true;
  }

  private detach(keepScreen: boolean = false, reportBlur: boolean = false): void {
    if (reportBlur) { this.emulator?.setFocused(false); }
    const stream = this.stream;
    const generation = this.generation;
    this.generation++;
    this.stream = undefined;
    if (stream !== undefined && (!reportBlur || !this.holdStreamForFocus(stream, generation))) { stream.close(); }
    if (!keepScreen) {
      this.emulator?.dispose();
      this.emulator = undefined;
      this.onDraw(undefined);
    }
    this.writable = false;
    this.lastOutput = -1;
    this.lastInput = 0;
    this.waitAck = 0;
    this.waitingFocusOut = false;
    clearTimeout(this.ackTimer);
    clearTimeout(this.paintTimer);
    this.paintTimer = -1;
    this.queue = [];
    this.queueBytes = 0;
  }

  private publish(): void {
    if (this.live) {
      const selected = this.selectedRow();
      const outcome = this.missing.length > 0 && this.missing === this.selected ? 'missing' :
        selected?.state === 'exited' ? 'exited' : undefined;
      this.onState({
        terminals: this.terminals, selected: this.selected,
        writable: this.writable, canTakeInput: !this.writable && this.lastOutput >= 0 && selected?.state === 'running',
        loading: this.loading, busy: this.busy, error: this.error,
        issue: this.issue, canCreate: this.discovered && !this.loading && !this.busy,
        outcome: outcome, exitCode: selected?.exitCode
      });
    }
  }
}
