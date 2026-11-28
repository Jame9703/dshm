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
  selection: TerminalSelectionBuffer;
}

export interface TerminalSelectionMarker {
  readonly line: number;
  readonly isDisposed: boolean;
  dispose(): void;
}

export interface TerminalSelectionCell {
  width: number;
  text: string;
}

export interface TerminalSelectionLine {
  wrapped: boolean;
  cellAt(column: number): TerminalSelectionCell | undefined;
  text(start: number, end: number): string;
}

export interface TerminalSelectionBuffer {
  epoch: number;
  columns: number;
  viewportTop: number;
  length: number;
  lineAt(row: number): TerminalSelectionLine | undefined;
  markerAt(row: number): TerminalSelectionMarker | undefined;
}

export interface TerminalEmulator {
  write(text: string, done: () => void): void;
  resize(cols: number, rows: number): void;
  scroll(lines: number): void;
  scrollToBottom(): boolean;
  isApplicationCursor(): boolean;
  paste(text: string): string;
  visibleText(): string;
  frame(): TerminalPaintFrame;
  dispose(): void;
}

export type TerminalEmulatorFactory =
  (cols: number, rows: number, scrollback: number, onReply: (text: string) => void) => TerminalEmulator;
export function loadTerminalEmulator(): Promise<TerminalEmulatorFactory>;
