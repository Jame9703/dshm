import { KeyCode } from '@kit.InputKit';

export interface DesktopTerminalKey {
  code: number;
  unicode: number;
  ctrl: boolean;
  alt: boolean;
  shift: boolean;
  meta: boolean;
}

const ESC: string = '\x1b';
const CSI: string = ESC + '[';
const SS3: string = ESC + 'O';
const FUNCTION_TILDE: number[] = [15, 17, 18, 19, 20, 21, 23, 24];

function cursorKey(final: string, modifier: number, applicationCursor: boolean): string {
  return modifier > 1 ? `${CSI}1;${modifier}${final}` : (applicationCursor ? SS3 : CSI) + final;
}

function tildeKey(key: number, modifier: number): string {
  return modifier > 1 ? `${CSI}${key};${modifier}~` : `${CSI}${key}~`;
}

function altPrintable(code: number, shift: boolean): string {
  if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) {
    return (shift ? ')!@#$%^&*(' : '0123456789').charAt(code - KeyCode.KEYCODE_0);
  }
  switch (code) {
    case KeyCode.KEYCODE_GRAVE: return shift ? '~' : '`';
    case KeyCode.KEYCODE_MINUS: return shift ? '_' : '-';
    case KeyCode.KEYCODE_EQUALS: return shift ? '+' : '=';
    case KeyCode.KEYCODE_LEFT_BRACKET: return shift ? '{' : '[';
    case KeyCode.KEYCODE_RIGHT_BRACKET: return shift ? '}' : ']';
    case KeyCode.KEYCODE_BACKSLASH: return shift ? '|' : '\\';
    case KeyCode.KEYCODE_SEMICOLON: return shift ? ':' : ';';
    case KeyCode.KEYCODE_APOSTROPHE: return shift ? '"' : "'";
    case KeyCode.KEYCODE_COMMA: return shift ? '<' : ',';
    case KeyCode.KEYCODE_PERIOD: return shift ? '>' : '.';
    case KeyCode.KEYCODE_SLASH: return shift ? '?' : '/';
    default: return '';
  }
}

// Non-macOS xterm 6 key sequences. Empty leaves printable text, IME, and platform shortcuts to ArkUI.
export function desktopTerminalKeySequence(key: DesktopTerminalKey, applicationCursor: boolean): string {
  const code = key.code;
  const modifier = 1 + (key.shift ? 1 : 0) + (key.alt ? 2 : 0) + (key.ctrl ? 4 : 0) + (key.meta ? 8 : 0);
  if (code >= KeyCode.KEYCODE_DPAD_UP && code <= KeyCode.KEYCODE_DPAD_RIGHT) {
    return key.meta ? '' : cursorKey('ABDC'.charAt(code - KeyCode.KEYCODE_DPAD_UP), modifier, applicationCursor);
  }
  if (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) {
    const index = code - KeyCode.KEYCODE_F1;
    return index < 4 ? cursorKey('PQRS'.charAt(index), modifier, true) : tildeKey(FUNCTION_TILDE[index - 4], modifier);
  }
  switch (code) {
    case KeyCode.KEYCODE_MOVE_HOME: return cursorKey('H', modifier, applicationCursor);
    case KeyCode.KEYCODE_MOVE_END: return cursorKey('F', modifier, applicationCursor);
    case KeyCode.KEYCODE_ENTER:
    case KeyCode.KEYCODE_NUMPAD_ENTER: return key.alt ? ESC + '\r' : '\r';
    case KeyCode.KEYCODE_DEL: return (key.alt ? ESC : '') + (key.ctrl ? '\b' : '\x7f');
    case KeyCode.KEYCODE_TAB: return key.shift ? CSI + 'Z' : '\t';
    case KeyCode.KEYCODE_ESCAPE: return key.alt ? ESC + ESC : ESC;
    case KeyCode.KEYCODE_INSERT: return key.ctrl || key.shift ? '' : tildeKey(2, 1);
    case KeyCode.KEYCODE_FORWARD_DEL: return tildeKey(3, modifier);
    case KeyCode.KEYCODE_PAGE_UP: return key.shift ? '' : tildeKey(5, key.ctrl ? modifier : 1);
    case KeyCode.KEYCODE_PAGE_DOWN: return key.shift ? '' : tildeKey(6, key.ctrl ? modifier : 1);
    default: break;
  }

  const letter = code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z;
  if (key.alt && !key.meta) {
    const printable = altPrintable(code, key.shift);
    if (printable) { return ESC + printable; }
    if (letter) { return ESC + String.fromCharCode(code - KeyCode.KEYCODE_A + (key.ctrl ? 1 : key.shift ? 65 : 97)); }
    if (code === KeyCode.KEYCODE_SPACE) { return ESC + (key.ctrl ? '\x00' : ' '); }
    return '';
  }
  if (!key.ctrl) { return ''; }
  if (modifier === 5) {
    if (letter) { return String.fromCharCode(code - KeyCode.KEYCODE_A + 1); }
    if (code === KeyCode.KEYCODE_SPACE) { return '\x00'; }
    if (code >= KeyCode.KEYCODE_3 && code <= KeyCode.KEYCODE_7) {
      return String.fromCharCode(code - KeyCode.KEYCODE_3 + 27);
    }
    if (code === KeyCode.KEYCODE_8) { return '\x7f'; }
    if (code === KeyCode.KEYCODE_LEFT_BRACKET) { return ESC; }
    if (code === KeyCode.KEYCODE_BACKSLASH) { return '\x1c'; }
    if (code === KeyCode.KEYCODE_RIGHT_BRACKET) { return '\x1d'; }
    return '';
  }
  // Some hardware and injected chords report the physical key without a shifted Unicode value.
  if (key.unicode === 64 || (key.shift && code === KeyCode.KEYCODE_2 && (key.unicode === 0 || key.unicode === 50))) {
    return '\x00';
  }
  if (key.unicode === 95 || (key.shift && code === KeyCode.KEYCODE_MINUS && (key.unicode === 0 || key.unicode === 45))) {
    return '\x1f';
  }
  return '';
}
