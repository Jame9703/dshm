import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { getArray, getBoolean, getNumber, getString } from 'connection';

export enum DesktopShortcut {
  REFERENCE = 'shortcuts.open', NEW_SESSION = 'session.new', LEFT_SIDEBAR = 'sidebar.left.toggle',
  SEARCH = 'session.search', ADD_WORKSPACE = 'workspace.add', RENAME = 'session.rename', FORK = 'session.fork',
  ARCHIVE = 'session.archive', SETTINGS = 'settings.open', FILES = 'workspace.files',
  NEW_TERMINAL = 'terminal.new', TOGGLE_READ = 'session.toggleRead'
}

export interface DesktopShortcutKey {
  code: number;
  ctrl: boolean;
  alt: boolean;
  shift: boolean;
}

interface ShortcutDefinition {
  id: DesktopShortcut;
  label: string;
  alias: string;
  binding: DesktopShortcutKey;
}

export interface DesktopShortcutOverride {
  id: string;
  binding: DesktopShortcutKey;
}

export interface DesktopShortcutRow {
  id: DesktopShortcut;
  label: string;
  alias: string;
  binding: DesktopShortcutKey;
  modified: boolean;
  occupiedBy: string;
}

export interface DesktopShortcutSettings {
  overrides: DesktopShortcutOverride[];
  raw: string;
  problem: string;
}

export const EMPTY_DESKTOP_SHORTCUT: DesktopShortcutKey = { code: 0, ctrl: false, alt: false, shift: false };
const PREFS = 'dshm_desktop_shortcuts';
const BINDINGS = 'bindings_v1';
let saving: boolean = false;

function command(id: DesktopShortcut, label: string, alias: string, code: number,
  alt: boolean = false, shift: boolean = false): ShortcutDefinition {
  return { id: id, label: label, alias: alias, binding: { code: code, ctrl: true, alt: alt, shift: shift } };
}

const COMMANDS: ShortcutDefinition[] = [
  command(DesktopShortcut.REFERENCE, '快捷键速查', 'keyboard shortcuts', KeyCode.KEYCODE_SLASH),
  command(DesktopShortcut.NEW_SESSION, '新会话', 'new session chat', KeyCode.KEYCODE_N),
  command(DesktopShortcut.LEFT_SIDEBAR, '切换左侧栏', 'left sidebar', KeyCode.KEYCODE_B),
  command(DesktopShortcut.SEARCH, '搜索会话', 'search sessions', KeyCode.KEYCODE_K),
  command(DesktopShortcut.ADD_WORKSPACE, '添加工作区', 'add workspace open folder', KeyCode.KEYCODE_O),
  command(DesktopShortcut.RENAME, '重命名会话', 'rename session', KeyCode.KEYCODE_G, true),
  command(DesktopShortcut.FORK, '分叉会话', 'fork session', KeyCode.KEYCODE_F, true),
  command(DesktopShortcut.ARCHIVE, '归档会话', 'archive session', KeyCode.KEYCODE_A, false, true),
  command(DesktopShortcut.SETTINGS, '打开设置', 'settings preferences', KeyCode.KEYCODE_COMMA),
  command(DesktopShortcut.FILES, '工作区文件', 'workspace files', KeyCode.KEYCODE_P),
  command(DesktopShortcut.NEW_TERMINAL, '新建终端', 'new terminal shell', KeyCode.KEYCODE_GRAVE),
  command(DesktopShortcut.TOGGLE_READ, '切换会话已读状态', 'toggle read unread', KeyCode.KEYCODE_U, false, true)
];
const COMMAND_IDS = new Set<string>(COMMANDS.map((row: ShortcutDefinition): string => row.id));

const FUNCTIONS: FunctionKey[] = [FunctionKey.F1, FunctionKey.F2, FunctionKey.F3, FunctionKey.F4, FunctionKey.F5,
  FunctionKey.F6, FunctionKey.F7, FunctionKey.F8, FunctionKey.F9, FunctionKey.F10, FunctionKey.F11, FunctionKey.F12];
const SYMBOLS = new Map<number, string>([
  [KeyCode.KEYCODE_SLASH, '/'], [KeyCode.KEYCODE_COMMA, ','], [KeyCode.KEYCODE_PERIOD, '.'],
  [KeyCode.KEYCODE_GRAVE, '`'], [KeyCode.KEYCODE_MINUS, '-'], [KeyCode.KEYCODE_EQUALS, '='],
  [KeyCode.KEYCODE_LEFT_BRACKET, '['], [KeyCode.KEYCODE_RIGHT_BRACKET, ']'], [KeyCode.KEYCODE_BACKSLASH, '\\'],
  [KeyCode.KEYCODE_SEMICOLON, ';'], [KeyCode.KEYCODE_APOSTROPHE, "'"]
]);

function keyLabel(code: number): string {
  if (code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z) {
    return String.fromCharCode(65 + code - KeyCode.KEYCODE_A);
  }
  if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) { return String(code - KeyCode.KEYCODE_0); }
  if (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) { return `F${1 + code - KeyCode.KEYCODE_F1}`; }
  return SYMBOLS.get(code) ?? '';
}

export function desktopShortcutValue(key: DesktopShortcutKey): string | FunctionKey {
  return key.code >= KeyCode.KEYCODE_F1 && key.code <= KeyCode.KEYCODE_F12 ?
    FUNCTIONS[key.code - KeyCode.KEYCODE_F1] : keyLabel(key.code);
}

export function desktopShortcutModifiers(key: DesktopShortcutKey): ModifierKey[] {
  const result: ModifierKey[] = [];
  if (key.ctrl) { result.push(ModifierKey.CTRL); }
  if (key.alt) { result.push(ModifierKey.ALT); }
  if (key.shift) { result.push(ModifierKey.SHIFT); }
  return result;
}

export function desktopShortcutLabels(key: DesktopShortcutKey): string[] {
  const main = keyLabel(key.code);
  return main ? [...(key.ctrl ? ['Ctrl'] : []), ...(key.alt ? ['Alt'] : []), ...(key.shift ? ['Shift'] : []), main] : [];
}

export function desktopShortcutFromEvent(event: KeyEvent): DesktopShortcutKey {
  return { code: event.keyCode, ctrl: event.getModifierKeyState?.(['Ctrl']) === true,
    alt: event.getModifierKeyState?.(['Alt']) === true, shift: event.getModifierKeyState?.(['Shift']) === true };
}

export function desktopShortcutEqual(left: DesktopShortcutKey, right: DesktopShortcutKey): boolean {
  return left.code === right.code && left.ctrl === right.ctrl && left.alt === right.alt && left.shift === right.shift;
}

export function desktopShortcutIssue(key: DesktopShortcutKey): string {
  if (!key.ctrl && !key.alt) { return '请同时按下 Ctrl 或 Alt 修饰键。'; }
  if ((key.ctrl && !key.alt && ((!key.shift && key.code === KeyCode.KEYCODE_A) ||
    [KeyCode.KEYCODE_C, KeyCode.KEYCODE_V, KeyCode.KEYCODE_X, KeyCode.KEYCODE_Z, KeyCode.KEYCODE_Y,
      KeyCode.KEYCODE_Q].includes(key.code))) ||
    (key.alt && !key.ctrl && [KeyCode.KEYCODE_F4, KeyCode.KEYCODE_F2].includes(key.code))) {
    return '此组合由系统或文本编辑操作保留。';
  }
  return keyLabel(key.code) ? '' : '暂不支持这个按键。';
}

export function desktopShortcutRows(overrides: DesktopShortcutOverride[]): DesktopShortcutRow[] {
  return COMMANDS.map((definition: ShortcutDefinition): DesktopShortcutRow => {
    const changed = overrides.find((row: DesktopShortcutOverride): boolean => row.id === definition.id);
    const binding = changed?.binding ?? definition.binding;
    const occupied = binding.code ? overrides.find((item: DesktopShortcutOverride): boolean =>
      item.id !== definition.id && COMMAND_IDS.has(item.id) && desktopShortcutEqual(item.binding, binding)) : undefined;
    const owner = COMMANDS.find((row: ShortcutDefinition): boolean => row.id === occupied?.id);
    return { id: definition.id, label: definition.label, alias: definition.alias, binding: binding,
      modified: changed !== undefined, occupiedBy: owner?.label ?? '' };
  });
}

function parseShortcuts(raw: string): DesktopShortcutOverride[] {
  const document: Object = JSON.parse(raw);
  const values = getArray(document, 'overrides');
  if (getNumber(document, 'version') !== 1 || values === undefined) { throw new Error('Invalid shortcut document'); }
  const result: DesktopShortcutOverride[] = [];
  const ids = new Set<string>();
  for (const value of values) {
    const id = getString(value, 'id');
    const code = getNumber(value, 'code');
    const ctrl = getBoolean(value, 'ctrl');
    const alt = getBoolean(value, 'alt');
    const shift = getBoolean(value, 'shift');
    if (!id || ids.has(id) || code === undefined || !Number.isInteger(code) ||
      ctrl === undefined || alt === undefined || shift === undefined) { throw new Error('Invalid shortcut entry'); }
    const binding: DesktopShortcutKey = { code: code, ctrl: ctrl, alt: alt, shift: shift };
    if (code !== 0 && desktopShortcutIssue(binding) !== '') { throw new Error('Invalid shortcut key'); }
    ids.add(id);
    result.push({ id: id, binding: binding });
  }
  return result;
}

function store(context: common.Context): preferences.Preferences {
  return preferences.getPreferencesSync(context, { name: PREFS });
}

export function readDesktopShortcuts(context: common.Context | undefined): DesktopShortcutSettings {
  try {
    if (context === undefined) { throw new Error('Missing shortcut preferences'); }
    const raw = store(context).getSync(BINDINGS, '');
    if (typeof raw !== 'string') { throw new Error('Invalid shortcut preferences'); }
    return { overrides: raw ? parseShortcuts(raw) : [], raw: raw, problem: '' };
  } catch (_) {
    return { overrides: [], raw: '', problem: '无法读取快捷键配置，当前使用默认键位。' };
  }
}

interface StoredShortcut {
  id: string;
  code: number;
  ctrl: boolean;
  alt: boolean;
  shift: boolean;
}

interface StoredShortcuts {
  version: number;
  overrides: StoredShortcut[];
}

export async function saveDesktopShortcuts(context: common.Context | undefined, previous: DesktopShortcutSettings,
  overrides: DesktopShortcutOverride[]): Promise<string> {
  if (context === undefined || previous.problem) { return '快捷键尚未准备好，请稍后重试。'; }
  if (saving) { return '快捷键配置正在保存，请稍后重试。'; }
  const data: StoredShortcuts = { version: 1, overrides: overrides.map((entry: DesktopShortcutOverride): StoredShortcut =>
    ({ id: entry.id, code: entry.binding.code, ctrl: entry.binding.ctrl, alt: entry.binding.alt, shift: entry.binding.shift })) };
  saving = true;
  try {
    const prefs = store(context);
    if (prefs.getSync(BINDINGS, '') !== previous.raw) { return '快捷键配置已更新。请核对最新键位后再保存。'; }
    try {
      await prefs.put(BINDINGS, JSON.stringify(data));
      await prefs.flush();
    } catch (_) {
      prefs.putSync(BINDINGS, previous.raw);
      return '保存失败。原快捷键已保留，请重试。';
    }
    return '';
  } catch (_) {
    return '无法保存快捷键配置，请重试。';
  } finally {
    saving = false;
  }
}
