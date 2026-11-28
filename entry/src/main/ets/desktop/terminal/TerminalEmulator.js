let selectionEpoch = 0;

export async function loadTerminalEmulator() {
  const { Terminal } = await import('./xterm-headless.js');
  return (cols, rows, scrollback, onReply) => new TerminalEmulator(Terminal, cols, rows, scrollback, onReply);
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
  constructor(Terminal, cols, rows, scrollback, onReply) {
    this.terminal = new Terminal({ cols, rows, scrollback, allowProposedApi: true });
    this.terminal.onData(onReply);
    this.selectionEpoch = ++selectionEpoch;
    this.selectionActive = true;
    this.terminal.buffer.onBufferChange(() => {
      this.selectionEpoch = ++selectionEpoch;
    });
    this.cursorVisible = true;
    for (const final of ['h', 'l']) {
      this.terminal.parser.registerCsiHandler({ prefix: '?', final }, params => {
        if (params.includes(25)) this.cursorVisible = final === 'h';
        return false;
      });
    }
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

  isApplicationCursor() {
    return this.terminal.modes.applicationCursorKeysMode;
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
      cursorVisible: this.cursorVisible && buffer.viewportY === buffer.baseY,
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
