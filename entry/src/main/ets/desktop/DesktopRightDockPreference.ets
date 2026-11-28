import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { getArray, getBoolean, getNumber, getRecord, getString, parseJson } from 'connection';
import { desktopDockChatTab, desktopDockResourceId, desktopDockSplitFraction, desktopDockTerminalIds, desktopDockTerminalTab,
  DesktopDockKind, emptyDesktopDock } from './DesktopRightDock';
import type { DesktopDockChatTarget, DesktopDockFloat, DesktopDockLayout, DesktopDockPane, DesktopDockRect, DesktopDockTab } from './DesktopRightDock';
import { desktopBrowserAddress } from './DesktopBrowserAddress';

const PREFS: string = 'dshm_desktop_dock';

interface SavedDockTab {
  kind: string;
  path: string;
  title: string;
  sequence?: number;
  callId?: string;
  index?: number;
  split?: boolean;
  wrap?: boolean;
  chat?: DesktopDockChatTarget;
  sourceSessionId?: string;
  browserId?: string;
  browserAddress?: string;
  compactionId?: string;
  terminalId?: string;
  terminalTabId?: string;
}

interface SavedDockPane {
  tabs: SavedDockTab[];
  active: string;
}

interface SavedDockFloat {
  tab: SavedDockTab;
  rect: DesktopDockRect;
}

interface SavedDock {
  version: number;
  panes: SavedDockPane[];
  focus: number;
  floats: SavedDockFloat[];
  focusedFloat: string;
  expanded: boolean;
  fullscreen: boolean;
  width: number;
  fraction: number;
}

function restorable(tab: DesktopDockTab): boolean {
  return tab.kind === DesktopDockKind.FILES || (tab.kind === DesktopDockKind.TERMINAL && tab.terminalLaunch !== true) ||
    tab.file !== undefined ||
    (tab.plan?.sequence ?? -1) >= 0 || tab.changeLocation !== undefined || tab.chat !== undefined ||
    tab.kind === DesktopDockKind.BROWSER || tab.kind === DesktopDockKind.COMPACTION || tab.kind === DesktopDockKind.TIMELINE;
}

function saveTab(tab: DesktopDockTab): SavedDockTab {
  return { kind: tab.kind, path: tab.file?.path ?? '', title: tab.title,
    sequence: tab.plan?.sequence ?? tab.changeLocation?.sequence, callId: tab.plan?.callId,
    index: tab.changeLocation?.index, split: tab.changeLocation?.split, wrap: tab.changeLocation?.wrap, chat: tab.chat,
    sourceSessionId: tab.sourceSessionId,
    browserId: tab.kind === DesktopDockKind.BROWSER ? tab.id : undefined, browserAddress: tab.browserAddress,
    compactionId: tab.kind === DesktopDockKind.COMPACTION ? tab.id : undefined, terminalId: tab.terminalId,
    terminalTabId: tab.kind === DesktopDockKind.TERMINAL && tab.id !== DesktopDockKind.TERMINAL ? tab.id : undefined };
}

export function encodeDesktopDock(layout: DesktopDockLayout): string {
  const panes: SavedDockPane[] = [];
  let focus = 0;
  layout.panes.forEach((pane: DesktopDockPane, index: number): void => {
    const saved = pane.tabs.filter(restorable);
    if (saved.length === 0 && pane.tabs.length > 0) { return; }
    if (index === layout.focus) { focus = panes.length; }
    panes.push({ tabs: saved.map(saveTab),
      active: saved.some((tab: DesktopDockTab): boolean => tab.id === pane.active) ? pane.active : saved[0]?.id ?? '' });
  });
  const layoutSurvives = panes.length > 0;
  const floats = layout.floats.filter((panel: DesktopDockFloat): boolean => restorable(panel.tab))
    .map((panel: DesktopDockFloat): SavedDockFloat => ({ tab: saveTab(panel.tab), rect: panel.rect }));
  const stored: SavedDock = { version: 1, panes: panes, focus: focus, floats: floats, focusedFloat: layout.focusedFloat,
    expanded: layoutSurvives && layout.expanded,
    fullscreen: layoutSurvives && layout.fullscreen, width: layout.width, fraction: panes.length === 2 ? layout.fraction : 0.5 };
  return JSON.stringify(stored);
}

function restoreTab(row: Object | undefined): DesktopDockTab | undefined {
  const kind = getString(row, 'kind');
  if (kind === DesktopDockKind.FILES) { return { id: kind, kind: kind, title: '工作区文件' }; }
  if (kind === DesktopDockKind.TIMELINE) { return { id: kind, kind: kind, title: getString(row, 'title') || '时间线' }; }
  if (kind === DesktopDockKind.TERMINAL) {
    const id = getString(row, 'terminalId');
    if (id && getString(row, 'terminalTabId')) { return desktopDockTerminalTab(id, getString(row, 'title') || '终端'); }
    return { id: kind, kind: kind, title: id ? getString(row, 'title') || '终端' : '终端', terminalId: id };
  }
  if (kind === DesktopDockKind.COMPACTION) {
    const id = getString(row, 'compactionId') ?? '';
    return id.startsWith('compaction:') ? { id: id, kind: kind, title: getString(row, 'title') ?? '' } : undefined;
  }
  if (kind === DesktopDockKind.BROWSER) {
    const id = getString(row, 'browserId') ?? '';
    if (!new RegExp('^browser:[0-9]+:[0-9]+$').test(id)) { return undefined; }
    const page = desktopBrowserAddress(getString(row, 'browserAddress') ?? '', '', false);
    return { id: id, kind: DesktopDockKind.BROWSER, title: page.title || '浏览器',
      browserAddress: page.href, restoreBrowser: !!page.href };
  }
  if (kind === DesktopDockKind.CHAT) {
    const chat = getRecord(row, 'chat');
    const id = getString(chat, 'id') ?? '';
    if (!id) { return undefined; }
    const title = getString(row, 'title') || id;
    const child = getRecord(chat, 'subagent');
    if (child === undefined) { return desktopDockChatTab({ id: id }, title); }
    const parentId = getString(child, 'parentId') ?? '';
    const mode = getString(child, 'mode');
    if (!parentId || parentId === id || getString(child, 'id') !== id ||
      (mode !== 'continuable' && mode !== 'one-shot' && mode !== 'unknown')) { return undefined; }
    return desktopDockChatTab({ id: id, subagent: { id: id, parentId: parentId, mode: mode,
      name: getString(child, 'name') || id, label: getString(child, 'label') || '',
      createdAt: getNumber(child, 'createdAt') ?? 0 } }, title);
  }
  const path = getString(row, 'path') ?? '';
  const source = getString(row, 'sourceSessionId');
  if (kind === DesktopDockKind.PREVIEW && path) {
    const name = getString(row, 'title') || path;
    return { id: desktopDockResourceId('file', path, source), kind: kind, title: name,
      file: { path: path, name: name }, sourceSessionId: source };
  }
  const sequence = getNumber(row, 'sequence') ?? -1;
  if (!Number.isSafeInteger(sequence) || sequence < 0) { return undefined; }
  if (kind === DesktopDockKind.PLAN) {
    const callId = getString(row, 'callId') ?? '';
    const title = getString(row, 'title') || '计划预览';
    return callId ? { id: desktopDockResourceId('plan', callId, source), kind: kind, title: title,
      plan: { sequence: sequence, callId: callId, title: title, markdown: '' }, sourceSessionId: source } : undefined;
  }
  if (kind === DesktopDockKind.CHANGES) {
    const index = getNumber(row, 'index') ?? 0;
    return { id: desktopDockResourceId('changes', String(sequence), source), kind: kind, title: '改动审阅', sourceSessionId: source,
      changeLocation: { sequence: sequence,
      index: Number.isSafeInteger(index) && index >= 0 ? index : 0, split: getBoolean(row, 'split'),
      wrap: getBoolean(row, 'wrap') } };
  }
  return undefined;
}

function restoreFloat(row: Object): DesktopDockFloat | undefined {
  const tab = restoreTab(getRecord(row, 'tab'));
  const rect = getRecord(row, 'rect');
  const x = getNumber(rect, 'x') ?? NaN;
  const y = getNumber(rect, 'y') ?? NaN;
  const width = getNumber(rect, 'width') ?? 0;
  const height = getNumber(rect, 'height') ?? 0;
  if (tab === undefined || !Number.isFinite(x) || !Number.isFinite(y) ||
    !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return undefined; }
  return { tab: tab, rect: { x: x, y: y, width: width, height: height } };
}

export function decodeDesktopDock(text: string): DesktopDockLayout {
  const state = parseJson(text);
  if (getNumber(state, 'version') !== 1) { return emptyDesktopDock(); }
  const rows = getArray(state, 'panes') ?? [];
  const seen = new Set<string>();
  const layout = emptyDesktopDock();
  if (rows.length > 2) { return layout; }
  if (rows.length > 0) {
    layout.panes = rows.map((row: Object): DesktopDockPane => {
      const tabs: DesktopDockTab[] = [];
      for (const saved of getArray(row, 'tabs') ?? []) {
        const tab = restoreTab(saved);
        if (tab !== undefined && !seen.has(tab.id)) {
          tabs.push(tab);
          seen.add(tab.id);
        }
      }
      const active = getString(row, 'active') ?? '';
      return { tabs: tabs, active: tabs.some((tab: DesktopDockTab): boolean => tab.id === active) ?
        active : tabs[0]?.id ?? '' };
    });
    layout.focus = rows.length === 2 && getNumber(state, 'focus') === 1 ? 1 : 0;
    layout.expanded = getBoolean(state, 'expanded') === true;
    layout.fullscreen = layout.expanded && getBoolean(state, 'fullscreen') === true;
    layout.fraction = rows.length === 2 ? desktopDockSplitFraction(getNumber(state, 'fraction') ?? 0.5) : 0.5;
  }
  for (const row of getArray(state, 'floats') ?? []) {
    const panel = restoreFloat(row);
    if (panel !== undefined && !seen.has(panel.tab.id)) {
      seen.add(panel.tab.id);
      layout.floats.push(panel);
    }
  }
  const focusedFloat = getString(state, 'focusedFloat') ?? '';
  if (layout.floats.some((panel: DesktopDockFloat): boolean => panel.tab.id === focusedFloat)) {
    layout.focusedFloat = focusedFloat;
  }
  const width = getNumber(state, 'width') ?? 0;
  layout.width = Number.isFinite(width) ? Math.max(0, width) : 0;
  return layout;
}

export function readDesktopDock(context: common.Context | undefined, session: string): DesktopDockLayout {
  if (context !== undefined) {
    try {
      const raw = preferences.getPreferencesSync(context, { name: PREFS }).getSync(session, '');
      if (typeof raw === 'string' && raw) { return decodeDesktopDock(raw); }
    } catch (_) {}
  }
  return emptyDesktopDock();
}

export async function readDesktopDockTerminalIds(context: common.Context | undefined): Promise<Map<string, string[]>> {
  const retained = new Map<string, string[]>();
  if (context !== undefined) {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFS });
      const all = await prefs.getAll();
      for (const session of Object.keys(all)) {
        const raw = getString(all, session);
        if (!raw?.includes('"terminalId"')) { continue; }
        const ids = desktopDockTerminalIds(decodeDesktopDock(raw));
        if (ids.length > 0) { retained.set(session, ids); }
      }
    } catch (_) {}
  }
  return retained;
}

export async function saveDesktopDock(context: common.Context | undefined, session: string,
  layout: DesktopDockLayout): Promise<void> {
  if (context === undefined) { return; }
  try {
    const prefs = preferences.getPreferencesSync(context, { name: PREFS });
    const saved = encodeDesktopDock(layout);
    if (prefs.getSync(session, '') !== saved) {
      prefs.putSync(session, saved);
      await prefs.flush();
    }
  } catch (_) {}
}
