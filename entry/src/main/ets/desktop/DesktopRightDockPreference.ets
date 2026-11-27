import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { getArray, getBoolean, getNumber, getString, parseJson } from 'connection';
import { desktopDockSplitFraction, DesktopDockKind, emptyDesktopDock } from './DesktopRightDock';
import type { DesktopDockLayout, DesktopDockPane, DesktopDockTab } from './DesktopRightDock';

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
}

interface SavedDockPane {
  tabs: SavedDockTab[];
  active: string;
}

interface SavedDock {
  version: number;
  panes: SavedDockPane[];
  focus: number;
  expanded: boolean;
  fullscreen: boolean;
  width: number;
  fraction: number;
}

function restorable(tab: DesktopDockTab): boolean {
  return tab.kind === DesktopDockKind.FILES || tab.kind === DesktopDockKind.TERMINAL || tab.file !== undefined ||
    (tab.plan?.sequence ?? -1) >= 0 || tab.changeLocation !== undefined;
}

function saveTab(tab: DesktopDockTab): SavedDockTab {
  return { kind: tab.kind, path: tab.file?.path ?? '', title: tab.title,
    sequence: tab.plan?.sequence ?? tab.changeLocation?.sequence, callId: tab.plan?.callId,
    index: tab.changeLocation?.index, split: tab.changeLocation?.split, wrap: tab.changeLocation?.wrap };
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
  const stored: SavedDock = { version: 1, panes: panes, focus: focus, expanded: layoutSurvives && layout.expanded,
    fullscreen: layoutSurvives && layout.fullscreen, width: layout.width, fraction: panes.length === 2 ? layout.fraction : 0.5 };
  return JSON.stringify(stored);
}

function restoreTab(row: Object): DesktopDockTab | undefined {
  const kind = getString(row, 'kind');
  if (kind === DesktopDockKind.FILES) { return { id: kind, kind: kind, title: '工作区文件' }; }
  if (kind === DesktopDockKind.TERMINAL) { return { id: kind, kind: kind, title: '终端' }; }
  const path = getString(row, 'path') ?? '';
  if (kind === DesktopDockKind.PREVIEW && path) {
    const name = getString(row, 'title') || path;
    return { id: 'file:' + path, kind: kind, title: name, file: { path: path, name: name } };
  }
  const sequence = getNumber(row, 'sequence') ?? -1;
  if (!Number.isSafeInteger(sequence) || sequence < 0) { return undefined; }
  if (kind === DesktopDockKind.PLAN) {
    const callId = getString(row, 'callId') ?? '';
    const title = getString(row, 'title') || '计划预览';
    return callId ? { id: 'plan:' + callId, kind: kind, title: title,
      plan: { sequence: sequence, callId: callId, title: title, markdown: '' } } : undefined;
  }
  if (kind === DesktopDockKind.CHANGES) {
    const index = getNumber(row, 'index') ?? 0;
    return { id: 'changes:' + sequence, kind: kind, title: '改动审阅', changeLocation: { sequence: sequence,
      index: Number.isSafeInteger(index) && index >= 0 ? index : 0, split: getBoolean(row, 'split'),
      wrap: getBoolean(row, 'wrap') } };
  }
  return undefined;
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
