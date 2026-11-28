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

export type TerminalMouseTracking = 'none' | 'x10' | 'vt200' | 'drag' | 'any';
export type TerminalMouseEncoding = 'default' | 'sgr' | 'sgr-pixels';

export interface TerminalMouseModes {
  tracking: TerminalMouseTracking;
  encoding: TerminalMouseEncoding;
  alternateWheel: boolean;
}

export interface TerminalMouseInput {
  /** Zero-based cells and pixels from the visible terminal content origin. */
  column: number;
  row: number;
  x: number;
  y: number;
  /** Left 0, middle 1, right 2, no button 3, wheel 4. */
  button: number;
  /** Release 0, press 1, move 32. Wheel up 0, down 1, left 2, right 3. */
  action: number;
  ctrl: boolean;
  alt: boolean;
  shift: boolean;
}

export interface TerminalEmulator {
  write(text: string, done: () => void): void;
  resize(cols: number, rows: number): void;
  scroll(lines: number): void;
  scrollToBottom(): boolean;
  viewportTop(): number;
  isApplicationCursor(): boolean;
  setFocused(focused: boolean): void;
  mouseModes(): TerminalMouseModes;
  mouse(event: TerminalMouseInput): boolean;
  /** Signed wheel units. Delta mode 0 is pixels, 1 is lines, 2 is pages. */
  wheelSteps(deltaY: number, deltaMode: number, lineHeight: number, ctrl: boolean, alt: boolean, shift: boolean): number;
  paste(text: string): string;
  visibleText(): string;
  frame(): TerminalPaintFrame;
  dispose(): void;
}

export type TerminalEmulatorFactory =
  (cols: number, rows: number, scrollback: number, onReply: (text: string) => void,
    onMouseReport?: (data: string, binary: boolean, pressed: boolean) => void) => TerminalEmulator;
export function loadTerminalEmulator(): Promise<TerminalEmulatorFactory>;
