export interface TerminalCellPaint {
  column: number;
  cells: number;
  text: string;
  foreground: string;
  background: string;
  bold: boolean;
  italic: boolean;
  dim: boolean;
  underline: boolean;
  strike: boolean;
}

export interface TerminalPaintFrame {
  rows: TerminalCellPaint[][];
  cursorColumn: number;
  cursorRow: number;
  cursorVisible: boolean;
}

export interface TerminalEmulator {
  write(text: string, done: () => void): void;
  resize(cols: number, rows: number): void;
  scroll(lines: number): void;
  isApplicationCursor(): boolean;
  paste(text: string): string;
  visibleText(): string;
  frame(): TerminalPaintFrame;
  dispose(): void;
}

export type TerminalEmulatorFactory =
  (cols: number, rows: number, scrollback: number, onReply: (text: string) => void) => TerminalEmulator;
export function loadTerminalEmulator(): Promise<TerminalEmulatorFactory>;
