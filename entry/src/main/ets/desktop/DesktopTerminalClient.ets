import { getArray, getBoolean, getNumber, getRecord, getString, randomUuid } from 'connection';
import type { DuplexStream } from 'connection';
import { DesktopHostActions, desktopHostItems, desktopHostProblem } from './DesktopHostActions';
import { loadTerminalEmulator } from './terminal/TerminalEmulator';
import type { TerminalEmulator, TerminalEmulatorFactory, TerminalPaintFrame } from './terminal/TerminalEmulator';

export interface DesktopShell {
  path: string;
  name: string;
}

export interface DesktopTerminalRow {
  id: string;
  title: string;
  state: string;
  cwd: string;
}

export interface DesktopTerminalState {
  terminals: DesktopTerminalRow[];
  shells: DesktopShell[];
  selected: string;
  writable: boolean;
  loading: boolean;
  busy: boolean;
  error: string;
}

interface TerminalInput {
  type: string;
  data: string;
  typed: boolean;
  cols: number;
  rows: number;
}

const MAX_INPUT_QUEUE: number = 32768;
const ACK_TIMEOUT_MS: number = 10000;
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
  private live: boolean = true;
  private terminals: DesktopTerminalRow[] = [];
  private shells: DesktopShell[] = [];
  private selected: string = '';
  private writable: boolean = false;
  private loading: boolean = true;
  private busy: boolean = false;
  private error: string = '';
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
  private ackTimer: number = -1;
  private paintTimer: number = -1;
  private queueBytes: number = 0;
  private queue: TerminalInput[] = [];
  private stopWatch?: () => void;
  private stream?: DuplexStream;
  private emulator?: TerminalEmulator;
  private createEmulator?: TerminalEmulatorFactory;

  constructor(host: DesktopHostActions, sessionId: string,
    onState: (view: DesktopTerminalState) => void, onDraw: (frame: TerminalPaintFrame | undefined) => void) {
    this.host = host;
    this.sessionId = sessionId;
    this.onState = onState;
    this.onDraw = onDraw;
  }

  async start(preferredId: string): Promise<void> {
    const session: Record<string, Object> = { 'sessionId': this.sessionId };
    const agent: Record<string, Object> = { 'agentId': this.sessionId };
    const engine = loadTerminalEmulator().catch((): undefined => undefined);
    const replies = await Promise.all([
      this.host.call('terminal/list', session),
      this.host.call('terminal/environment', agent),
      this.host.call('terminal/shells', agent)
    ]);
    this.createEmulator = await engine;
    if (!this.live) {
      return;
    }
    this.loading = false;
    if (this.createEmulator === undefined) {
      this.error = '终端显示组件无法加载';
      this.publish();
      return;
    }
    if (!replies[0].ok) {
      this.error = replies[0].error?.httpStatus === 404 ?
        '当前宿主未启用终端。可在插件管理中启用终端插件包。' : desktopHostProblem(replies[0]);
      this.publish();
      return;
    }
    this.maxCols = getNumber(replies[1].value, 'maxCols') ?? this.maxCols;
    this.maxRows = getNumber(replies[1].value, 'maxRows') ?? this.maxRows;
    this.scrollback = getNumber(replies[1].value, 'scrollback') ?? this.scrollback;
    this.maxInputBytes = getNumber(replies[1].value, 'maxInputBytes') ?? this.maxInputBytes;
    if (replies[2].ok) {
      const choices: DesktopShell[] = [];
      for (const item of desktopHostItems(replies[2])) {
        const path = getString(item, 'path') ?? '';
        if (path) {
          choices.push({ path: path, name: getString(item, 'name') ?? path });
        }
      }
      this.shells = choices;
    }
    this.setTerminals(desktopHostItems(replies[0]));
    const preferred = this.terminals.find((row: DesktopTerminalRow): boolean => row.id === preferredId);
    if (preferred !== undefined) {
      this.select(preferred.id);
    } else if (this.terminals.length > 0) {
      this.select(this.terminals[0].id);
    }
    this.stopWatch = this.host.watch('terminal/watch', session, {
      onItem: (value: Object): void => {
        const wrapped: Record<string, Object> = { 'items': value };
        this.setTerminals(getArray(wrapped, 'items') ?? []);
      },
      onError: (_code: string, message: string): void => {
        this.error = message;
        this.publish();
      },
      onEnd: (): void => {}
    });
    this.publish();
  }

  async create(shellPath: string = ''): Promise<void> {
    if (!this.live || this.busy || this.loading || this.createEmulator === undefined) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.publish();
    const id = 'native-' + randomUuid();
    const request: Record<string, Object> = {
      'id': id, 'cols': Math.min(this.maxCols, this.desiredCols), 'rows': Math.min(this.maxRows, this.desiredRows)
    };
    if (shellPath) {
      request['shellPath'] = shellPath;
    }
    const result = await this.host.call('terminal/create', { 'agentId': this.sessionId, 'request': request });
    if (!this.live) {
      return;
    }
    this.busy = false;
    if (!result.ok || result.value === undefined) {
      this.error = desktopHostProblem(result) || '宿主未返回终端';
      this.publish();
      return;
    }
    const row = this.project(result.value);
    if (!this.terminals.some((item: DesktopTerminalRow): boolean => item.id === row.id)) {
      this.terminals = [...this.terminals, row];
    }
    this.select(row.id);
  }

  async rename(id: string, title: string): Promise<void> {
    const result = await this.host.call('terminal/rename', { 'agentId': this.sessionId, 'id': id, 'title': title });
    if (!this.live) {
      return;
    }
    this.error = desktopHostProblem(result);
    if (result.ok) {
      this.terminals = this.terminals.map((row: DesktopTerminalRow): DesktopTerminalRow => {
        return row.id === id ? { id: row.id, title: title, state: row.state, cwd: row.cwd } : row;
      });
    }
    this.publish();
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
      this.terminals = this.terminals.filter((row: DesktopTerminalRow): boolean => row.id !== id);
      this.chooseRemaining();
    }
    this.publish();
  }

  select(id: string): void {
    if (!this.live || !id || (id === this.selected && this.stream !== undefined)) {
      return;
    }
    this.detach();
    this.selected = id;
    this.error = '';
    const generation = this.generation;
    const result = this.host.attach('terminal/attach', { 'agentId': this.sessionId, 'id': id }, {
      onItem: (value: Object): void => {
        if (this.live && this.generation === generation) {
          this.receive(value);
        }
      },
      onError: (_code: string, message: string): void => { this.ended(generation, message); },
      onEnd: (): void => { this.ended(generation, '终端连接已结束'); }
    });
    this.stream = result;
    if (result === undefined) {
      this.error = '宿主连接正在重建，请重连终端';
    }
    this.publish();
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

  visibleText(): string {
    return this.emulator?.visibleText() ?? '';
  }

  applicationCursor(): boolean {
    return this.emulator?.isApplicationCursor() === true;
  }

  dispose(): void {
    this.live = false;
    this.stopWatch?.();
    this.detach();
  }

  private project(value: Object): DesktopTerminalRow {
    const shell = getRecord(value, 'shell');
    return {
      id: getString(value, 'id') ?? '',
      title: getString(value, 'title') || getString(shell, 'name') || '终端',
      state: getString(value, 'state') ?? '',
      cwd: getString(value, 'cwd') ?? ''
    };
  }

  private setTerminals(items: Object[]): void {
    if (!this.live) {
      return;
    }
    this.terminals = items.map((item: Object): DesktopTerminalRow => this.project(item))
      .filter((row: DesktopTerminalRow): boolean => row.id.length > 0);
    this.chooseRemaining();
    this.publish();
  }

  private chooseRemaining(): void {
    if (this.selected.length > 0 && !this.terminals.some((row: DesktopTerminalRow): boolean => row.id === this.selected)) {
      this.selected = '';
      this.detach();
      if (this.terminals.length > 0) {
        this.select(this.terminals[0].id);
      }
    }
  }

  private receive(value: Object): void {
    const kind = getString(value, 'type');
    if (kind === 'snapshot') {
      this.updateSize(getRecord(value, 'info'));
      this.writable = getBoolean(value, 'writable') === true;
      this.maxFrameBytes = getNumber(getRecord(value, 'inputWindow'), 'maxFrameBytes') ?? this.maxFrameBytes;
      this.lastOutput = getNumber(value, 'sequence') ?? 0;
      this.emulator = this.createEmulator?.(this.cols, this.rows, this.scrollback, (reply: string): void => {
        this.write(reply, false);
      });
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
      this.writable = getBoolean(value, 'writable') === true;
      this.updateSize(getRecord(value, 'info'));
      this.requestResize();
      this.publish();
      this.draw();
    } else if (kind === 'ack') {
      if (getNumber(value, 'sequence') !== this.waitAck) {
        return;
      }
      clearTimeout(this.ackTimer);
      this.waitAck = 0;
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

  private ended(generation: number, message: string): void {
    if (this.live && this.generation === generation) {
      this.detach(true);
      this.error = message;
      this.publish();
    }
  }

  private detach(keepScreen: boolean = false): void {
    this.generation++;
    this.stream?.close();
    this.stream = undefined;
    if (!keepScreen) {
      this.emulator?.dispose();
      this.emulator = undefined;
      this.onDraw(undefined);
    }
    this.writable = false;
    this.lastOutput = -1;
    this.lastInput = 0;
    this.waitAck = 0;
    clearTimeout(this.ackTimer);
    clearTimeout(this.paintTimer);
    this.paintTimer = -1;
    this.queue = [];
    this.queueBytes = 0;
  }

  private publish(): void {
    if (this.live) {
      this.onState({
        terminals: this.terminals, shells: this.shells, selected: this.selected,
        writable: this.writable, loading: this.loading, busy: this.busy, error: this.error
      });
    }
  }
}
