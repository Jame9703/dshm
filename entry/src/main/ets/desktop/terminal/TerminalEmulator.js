let selectionEpoch = 0;

export async function loadTerminalEmulator() {
  const { Terminal } = await import('./xterm-headless.js');
  return (cols, rows, scrollback, onReply, onMouseReport) =>
    new TerminalEmulator(Terminal, cols, rows, scrollback, onReply, onMouseReport);
}

const ANSI = [
  '#24272b', '#d2474d', '#2a9a61', '#ad801f', '#457ada', '#a85ebf', '#1d8c9a', '#d5d8dd',
  '#6e7681', '#f16568', '#45bd79', '#d2a548', '#72a5ff', '#cc83e4', '#4bb8c1', '#f6f7f8',
];
const CUBE = [0, 95, 135, 175, 215, 255];

function rgb(value) {
  return '#' + value.toString(16).padStart(6, '0');
}

function palette(index) {
  if (index < ANSI.length) return ANSI[index];
  if (index >= 232) {
    const shade = 8 + (index - 232) * 10;
    return rgb(shade * 0x010101);
  }
  const cube = index - 16;
  return rgb(CUBE[Math.floor(cube / 36)] * 0x010000 +
    CUBE[Math.floor(cube / 6) % 6] * 0x0100 + CUBE[cube % 6]);
}

function colors(cell) {
  let foreground = cell.isFgRGB() ? rgb(cell.getFgColor()) :
    cell.isFgPalette() ? palette(cell.getFgColor()) : '';
  let background = cell.isBgRGB() ? rgb(cell.getBgColor()) :
    cell.isBgPalette() ? palette(cell.getBgColor()) : '';
  if (cell.isInverse()) {
    [foreground, background] = [background || 'background', foreground || 'foreground'];
  }
  return [foreground, background];
}

class TerminalEmulator {
  constructor(Terminal, cols, rows, scrollback, onReply, onMouseReport) {
    this.terminal = new Terminal({ cols, rows, scrollback, cursorBlink: true, allowProposedApi: true });
    // Headless xterm uses the same mouse service as the browser but exposes no DOM event adapter.
    this.mouseService = this.terminal._core.coreMouseService;
    this.reportingMouse = undefined;
    this.partialWheel = 0;
    this.focused = false;
    this.reportFocus = () => onReply(this.focused ? '\x1b[I' : '\x1b[O');
    // Browser xterm also answers the parser's immediate focus request on DECSET 1004.
    this.terminal._core._inputHandler.onRequestSendFocus(this.reportFocus);
    this.terminal.onData(data => {
      if (this.reportingMouse) onMouseReport?.(data, false,
        this.reportingMouse.button < 4 && this.reportingMouse.action === 1);
      else onReply(data);
    });
    this.terminal.onBinary(data => {
      if (this.reportingMouse) onMouseReport?.(data, true,
        this.reportingMouse.button < 4 && this.reportingMouse.action === 1);
    });
    this.selectionEpoch = ++selectionEpoch;
    this.selectionActive = true;
    this.terminal.buffer.onBufferChange(() => {
      this.selectionEpoch = ++selectionEpoch;
    });
    this.cursorColor = '';
    this.terminal._core._inputHandler.onColor(changes => {
      for (const change of changes) {
        if (change.index !== 258) continue;
        if (change.type === 1) {
          const [red, green, blue] = change.color;
          this.cursorColor = rgb(red * 0x10000 + green * 0x100 + blue);
        } else if (change.type === 2) {
          this.cursorColor = '';
        }
      }
    });
  }

  write(data, done) {
    this.terminal.write(data, () => {
      // xterm only registers stable markers on its normal buffer.
      if (this.terminal.buffer.active.type === 'alternate') this.selectionEpoch = ++selectionEpoch;
      done();
    });
  }

  resize(cols, rows) {
    if (cols !== this.terminal.cols ||
        (rows !== this.terminal.rows && this.terminal.buffer.active.type === 'alternate')) {
      this.selectionEpoch = ++selectionEpoch;
    }
    this.terminal.resize(cols, rows);
  }

  scroll(lines) {
    this.terminal.scrollLines(lines);
  }

  scrollToBottom() {
    const buffer = this.terminal.buffer.active;
    if (buffer.viewportY === buffer.baseY) return false;
    this.terminal.scrollToBottom();
    return true;
  }

  viewportTop() { return this.terminal.buffer.active.viewportY; }

  isApplicationCursor() {
    return this.terminal.modes.applicationCursorKeysMode;
  }

  setFocused(focused) {
    if (this.focused === focused) return;
    this.focused = focused;
    if (this.terminal.modes.sendFocusMode) this.reportFocus();
  }

  mouseModes() {
    const encoding = this.mouseService.activeEncoding;
    return {
      tracking: this.terminal.modes.mouseTrackingMode,
      encoding: encoding === 'SGR' ? 'sgr' : encoding === 'SGR_PIXELS' ? 'sgr-pixels' : 'default',
      alternateWheel: !this.terminal._core.buffer.hasScrollback,
    };
  }

  mouse(event) {
    if (!Number.isInteger(event.column) || !Number.isInteger(event.row) ||
        !Number.isFinite(event.x) || !Number.isFinite(event.y) ||
        !Number.isInteger(event.button) || event.button < 0 || event.button > 4 ||
        ![0, 1, 2, 3, 32].includes(event.action)) return false;
    const reporting = this.reportingMouse;
    this.reportingMouse = event;
    try {
      return this.mouseService.triggerMouseEvent({
        col: event.column,
        row: event.row,
        x: Math.max(0, Math.floor(event.x)),
        y: Math.max(0, Math.floor(event.y)),
        button: event.button,
        action: event.action,
        ctrl: event.ctrl === true,
        alt: event.alt === true,
        shift: event.shift === true,
      });
    } finally {
      this.reportingMouse = reporting;
    }
  }

  wheelSteps(deltaY, deltaMode, lineHeight, ctrl, alt, shift) {
    if (!Number.isFinite(deltaY) || deltaY === 0 || shift) return 0;
    const options = this.terminal.options;
    const amount = deltaY * options.scrollSensitivity * (ctrl || alt ? options.fastScrollSensitivity : 1);
    if (deltaMode === 1) return amount;
    if (deltaMode === 2) return amount * this.terminal.rows;
    if (deltaMode !== 0 || !Number.isFinite(lineHeight) || lineHeight <= 0) return 0;
    // Mirror consumeWheelEvent without its DOM WheelEvent constants in this headless runtime.
    this.partialWheel += (amount / lineHeight) * (Math.abs(deltaY) < 50 ? 0.3 : 1);
    const steps = Math.trunc(this.partialWheel);
    this.partialWheel %= 1;
    return steps;
  }

  paste(value) {
    const input = value.replace(/\r?\n/g, '\r');
    return this.terminal.modes.bracketedPasteMode ? '\x1b[200~' + input + '\x1b[201~' : input;
  }

  visibleText() {
    const buffer = this.terminal.buffer.active;
    const lines = [];
    for (let y = 0; y < this.terminal.rows; y++) {
      lines.push(buffer.getLine(buffer.viewportY + y)?.translateToString(true) ?? '');
    }
    return lines.join('\n').trimEnd();
  }

  frame() {
    const terminal = this.terminal;
    const cursor = terminal._core.coreService;
    const buffer = terminal.buffer.active;
    const cell = buffer.getNullCell();
    const rows = [];
    for (let y = 0; y < terminal.rows; y++) {
      const line = buffer.getLine(buffer.viewportY + y);
      const runs = [];
      if (line) {
        for (let column = 0; column < terminal.cols; column++) {
          if (!line.getCell(column, cell) || cell.getWidth() === 0) continue;
          const [foreground, background] = colors(cell);
          const text = cell.isInvisible() ? '' : cell.getChars();
          const cells = cell.getWidth();
          const underline = cell.isUnderline() !== 0;
          const strike = cell.isStrikethrough() !== 0;
          if (!text && !background && !underline && !strike) continue;
          runs.push({ column, cells, text, foreground, background, underline, strike,
            bold: cell.isBold() !== 0, italic: cell.isItalic() !== 0, dim: cell.isDim() !== 0 });
        }
      }
      rows.push(runs);
    }
    return {
      rows,
      cursorColumn: Math.min(terminal.cols - 1, buffer.cursorX),
      cursorRow: buffer.baseY - buffer.viewportY + buffer.cursorY,
      cursorVisible: !cursor.isCursorHidden && buffer.viewportY === buffer.baseY,
      cursorStyle: cursor.decPrivateModes.cursorStyle ?? terminal.options.cursorStyle,
      cursorBlink: cursor.decPrivateModes.cursorBlink ?? terminal.options.cursorBlink,
      cursorColor: this.cursorColor,
      selection: this.selectionBuffer(buffer),
    };
  }

  selectionBuffer(buffer) {
    const terminal = this.terminal;
    const epoch = this.selectionEpoch;
    const current = () => this.selectionActive && this.selectionEpoch === epoch;
    const scratch = buffer.getNullCell();
    return {
      epoch,
      columns: terminal.cols,
      viewportTop: buffer.viewportY,
      length: buffer.length,
      lineAt(row) {
        if (!current() || row < 0 || row >= buffer.length) return undefined;
        const line = buffer.getLine(row);
        if (!line) return undefined;
        return {
          wrapped: line.isWrapped,
          cellAt(column) {
            const cell = line.getCell(column, scratch);
            return cell ? { width: cell.getWidth(), text: cell.getChars() } : undefined;
          },
          text(start, end) {
            return line.translateToString(true, start, end);
          },
        };
      },
      markerAt(row) {
        if (!current() || !Number.isInteger(row) || row < 0 || row >= buffer.length) return undefined;
        if (buffer.type === 'normal') return terminal.registerMarker(row - buffer.baseY - buffer.cursorY);
        let disposed = false;
        return {
          get line() { return disposed || !current() ? -1 : row; },
          get isDisposed() { return disposed || !current(); },
          dispose() { disposed = true; },
        };
      },
    };
  }

  dispose() {
    this.selectionActive = false;
    this.terminal.dispose();
  }
}
