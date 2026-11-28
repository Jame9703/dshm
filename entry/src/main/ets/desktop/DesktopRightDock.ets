import type { DesktopChangeLocation, DesktopChangeTarget } from './DesktopArtifacts';
import type { DesktopFileNavigation } from './DesktopFilesPane';
import type { DesktopPlanDocument } from './DesktopPlan';
import type { DesktopSubagentEntry } from './DesktopSubagents';
import type { DesktopAgentTerminalBinding } from './DesktopTerminalRosters';

export enum DesktopDockKind {
  FILES = 'files', TERMINAL = 'terminal', PREVIEW = 'preview', PLAN = 'plan', CHANGES = 'changes', CHAT = 'chat',
  BROWSER = 'browser', COMPACTION = 'compaction', TIMELINE = 'timeline'
}

export interface DesktopDockChatTarget {
  id: string;
  subagent?: DesktopSubagentEntry;
}

export interface DesktopDockTab {
  id: string;
  kind: DesktopDockKind;
  title: string;
  file?: DesktopFileNavigation;
  plan?: DesktopPlanDocument;
  changes?: DesktopChangeTarget;
  changeLocation?: DesktopChangeLocation;
  chat?: DesktopDockChatTarget;
  sourceSessionId?: string;
  browserAddress?: string;
  restoreBrowser?: boolean;
  compactionMarkdown?: string;
  terminalId?: string;
  terminalLaunch?: boolean;
  agentControlled?: boolean;
  terminalSandbox?: string;
}

export function desktopDockChatTab(target: DesktopDockChatTarget, title: string): DesktopDockTab {
  return { id: 'chat:' + target.id, kind: DesktopDockKind.CHAT, title: title || target.id, chat: target };
}

export function desktopDockResourceId(kind: string, resource: string, sourceSessionId?: string): string {
  return kind + ':' + (sourceSessionId ? JSON.stringify([sourceSessionId, resource]) : resource);
}

export function desktopDockTerminalTab(terminalId: string, title: string,
  agentControlled: boolean = false, sandbox: string = ''): DesktopDockTab {
  return { id: desktopDockResourceId(DesktopDockKind.TERMINAL, terminalId), kind: DesktopDockKind.TERMINAL,
    title: title, terminalId: terminalId, agentControlled: agentControlled, terminalSandbox: sandbox };
}

export interface DesktopDockPane {
  id: number;
  tabs: DesktopDockTab[];
  active: string;
}

export interface DesktopDockRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DesktopDockFloat {
  tab: DesktopDockTab;
  rect: DesktopDockRect;
}

export interface DesktopDockLayout {
  panes: DesktopDockPane[];
  focus: number;
  floats: DesktopDockFloat[];
  focusedFloat: string;
  expanded: boolean;
  fullscreen: boolean;
  width: number;
  fraction: number;
}

export function emptyDesktopDock(): DesktopDockLayout {
  return { panes: [{ id: 0, tabs: [], active: '' }], focus: 0, floats: [], focusedFloat: '', expanded: false,
    fullscreen: false, width: 0, fraction: 0.5 };
}

function copyDock(layout: DesktopDockLayout): DesktopDockLayout {
  return { panes: layout.panes.map((pane: DesktopDockPane): DesktopDockPane =>
    ({ id: pane.id, tabs: pane.tabs.slice(), active: pane.active })), focus: layout.focus, floats: layout.floats.slice(),
    focusedFloat: layout.focusedFloat, expanded: layout.expanded,
    fullscreen: layout.fullscreen, width: layout.width, fraction: layout.fraction };
}

export function desktopDockPresentation(layout: DesktopDockLayout, focus: number, expanded: boolean,
  fullscreen: boolean, focusedFloat: string = layout.focusedFloat): DesktopDockLayout {
  return { panes: layout.panes, focus: focus, expanded: expanded, fullscreen: fullscreen,
    floats: layout.floats, focusedFloat: focusedFloat, width: layout.width, fraction: layout.fraction };
}

export function desktopDockResize(layout: DesktopDockLayout, width: number, fraction: number): DesktopDockLayout {
  return { panes: layout.panes, focus: layout.focus, expanded: layout.expanded, fullscreen: layout.fullscreen,
    floats: layout.floats, focusedFloat: '', width: width, fraction: fraction };
}

export function desktopDockSplitFraction(fraction: number): number {
  return Number.isFinite(fraction) ? Math.min(0.8, Math.max(0.2, fraction)) : 0.5;
}

export function desktopDockTab(layout: DesktopDockLayout, index: number = layout.focus): DesktopDockTab | undefined {
  const pane = layout.panes[index];
  return pane?.tabs.find((tab: DesktopDockTab): boolean => tab.id === pane.active);
}

export function desktopDockTerminalIds(layout: DesktopDockLayout): string[] {
  const ids: string[] = [];
  const remember = (tab: DesktopDockTab): void => {
    if (tab.kind === DesktopDockKind.TERMINAL && tab.terminalId) { ids.push(tab.terminalId); }
  };
  layout.panes.forEach((pane: DesktopDockPane): void => pane.tabs.forEach(remember));
  layout.floats.forEach((panel: DesktopDockFloat): void => remember(panel.tab));
  return ids;
}

export function desktopDockBindTerminal(layout: DesktopDockLayout, tabId: string, terminalId: string,
  title: string = '', previousTerminalId?: string): DesktopDockLayout {
  const match = (tab: DesktopDockTab): boolean => tab.kind === DesktopDockKind.TERMINAL && tab.id === tabId;
  const current = layout.panes.flatMap((pane: DesktopDockPane): DesktopDockTab[] => pane.tabs).find(match) ??
    layout.floats.find((panel: DesktopDockFloat): boolean => match(panel.tab))?.tab;
  if (current === undefined || (previousTerminalId !== undefined && current.terminalId !== previousTerminalId)) {
    return layout;
  }
  const nextTitle = terminalId ? title || current.title : '终端';
  if ((current.terminalId ?? '') === terminalId && current.title === nextTitle) { return layout; }
  const next = copyDock(layout);
  const updated: DesktopDockTab = { id: current.id, kind: current.kind, title: nextTitle,
    terminalId: terminalId || undefined, agentControlled: current.terminalId === terminalId && current.agentControlled,
    terminalSandbox: current.terminalId === terminalId ? current.terminalSandbox : undefined };
  next.panes.forEach((pane: DesktopDockPane): void => {
    const index = pane.tabs.findIndex(match);
    if (index >= 0) { pane.tabs[index] = updated; }
  });
  const index = next.floats.findIndex((panel: DesktopDockFloat): boolean => match(panel.tab));
  if (index >= 0) { next.floats[index] = { tab: updated, rect: next.floats[index].rect }; }
  return next;
}

export function desktopDockProjectTerminals(layout: DesktopDockLayout, metadata: Map<string, DesktopAgentTerminalBinding>,
  ended: Set<string>): DesktopDockLayout {
  const tabProjection = (tab: DesktopDockTab): DesktopDockTab => {
    const info = tab.kind === DesktopDockKind.TERMINAL && tab.terminalId ? metadata.get(tab.terminalId) : undefined;
    const title = info?.title || tab.title;
    if (info === undefined || (title === tab.title && info.agentControlled === (tab.agentControlled ?? false) &&
      info.sandboxMode === (tab.terminalSandbox ?? ''))) { return tab; }
    return { id: tab.id, kind: tab.kind, terminalId: tab.terminalId, title: title,
      agentControlled: info.agentControlled, terminalSandbox: info.sandboxMode };
  };
  let projected = layout;
  for (let index = layout.panes.length - 1; index >= 0; index--) {
    for (const tab of layout.panes[index].tabs) {
      if (tab.kind === DesktopDockKind.TERMINAL && tab.terminalId && ended.has(tab.terminalId)) {
        projected = desktopDockCloseTab(projected, index, tab.id);
      }
    }
  }
  for (const panel of layout.floats) {
    if (panel.tab.kind === DesktopDockKind.TERMINAL && panel.tab.terminalId && ended.has(panel.tab.terminalId)) {
      projected = desktopDockCloseFloat(projected, panel.tab.id);
    }
  }
  const updates = new Map<string, DesktopDockTab>();
  const collect = (tab: DesktopDockTab): void => {
    const updated = tabProjection(tab);
    if (updated !== tab) { updates.set(tab.id, updated); }
  };
  projected.panes.forEach((pane: DesktopDockPane): void => pane.tabs.forEach(collect));
  projected.floats.forEach((panel: DesktopDockFloat): void => collect(panel.tab));
  if (updates.size === 0) { return projected; }
  const next = copyDock(projected);
  next.panes.forEach((pane: DesktopDockPane): void => {
    pane.tabs = pane.tabs.map((tab: DesktopDockTab): DesktopDockTab => updates.get(tab.id) ?? tab);
  });
  next.floats = next.floats.map((panel: DesktopDockFloat): DesktopDockFloat => {
    const tab = updates.get(panel.tab.id);
    return tab === undefined ? panel : { tab: tab, rect: panel.rect };
  });
  return next;
}

export function desktopDockOpen(layout: DesktopDockLayout, tab: DesktopDockTab, update: boolean = true,
  destination?: number): DesktopDockLayout {
  if (destination !== undefined && layout.panes[destination] !== undefined) {
    layout = desktopDockSeatFloat(layout, tab.id, destination);
    const existing = layout.panes.findIndex((pane: DesktopDockPane): boolean =>
      pane.tabs.some((item: DesktopDockTab): boolean => item.id === tab.id));
    if (existing >= 0 && existing !== destination) {
      layout = desktopDockMoveTab(layout, existing, tab.id, destination);
    }
    layout = desktopDockPresentation(layout, destination, true, layout.fullscreen, '');
  }
  const floating = layout.floats.findIndex((item: DesktopDockFloat): boolean => item.tab.id === tab.id);
  if (floating >= 0) {
    const next = copyDock(layout);
    const existing = next.floats.splice(floating, 1)[0];
    next.floats.push({ tab: update ? tab : existing.tab, rect: existing.rect });
    next.focusedFloat = tab.id;
    return next;
  }
  const next = copyDock(layout);
  const existing = next.panes.findIndex((pane: DesktopDockPane): boolean =>
    pane.tabs.some((item: DesktopDockTab): boolean => item.id === tab.id));
  if (existing >= 0) {
    const pane = next.panes[existing];
    const index = pane.tabs.findIndex((item: DesktopDockTab): boolean => item.id === tab.id);
    if (update) { pane.tabs[index] = tab; }
    pane.active = tab.id;
    next.focus = existing;
  } else {
    const pane = next.panes[next.focus];
    pane.tabs.push(tab);
    pane.active = tab.id;
  }
  next.expanded = true;
  next.focusedFloat = '';
  return next;
}

export function desktopDockSelect(layout: DesktopDockLayout, pane: number, tab: string): DesktopDockLayout {
  if (!layout.panes[pane]?.tabs.some((item: DesktopDockTab): boolean => item.id === tab)) { return layout; }
  const next = copyDock(layout);
  next.focus = pane;
  next.focusedFloat = '';
  next.panes[pane].active = tab;
  return next;
}

export function desktopDockBrowserAddress(layout: DesktopDockLayout, id: string, href: string,
  title: string): DesktopDockLayout {
  const next = copyDock(layout);
  const owner = next.panes.find((pane: DesktopDockPane): boolean => pane.tabs.some(
    (tab: DesktopDockTab): boolean => tab.kind === DesktopDockKind.BROWSER && tab.id === id));
  const index = owner?.tabs.findIndex((tab: DesktopDockTab): boolean => tab.id === id) ?? -1;
  const floating = next.floats.findIndex((row: DesktopDockFloat): boolean =>
    row.tab.kind === DesktopDockKind.BROWSER && row.tab.id === id);
  const tab = owner?.tabs[index] ?? next.floats[floating]?.tab;
  if (tab === undefined || (tab.browserAddress === href && tab.title === title && !tab.restoreBrowser)) { return layout; }
  const updated: DesktopDockTab = { id: id, kind: DesktopDockKind.BROWSER, title: title, browserAddress: href };
  if (owner !== undefined && index >= 0) {
    owner.tabs[index] = updated;
  } else if (floating >= 0) {
    next.floats[floating] = { tab: updated, rect: next.floats[floating].rect };
  }
  return next;
}

export function desktopDockNavigatePreview(layout: DesktopDockLayout, path: string, name: string,
  sourceSessionId?: string, replaceId?: string): DesktopDockLayout {
  if (!path) { return layout; }
  const tabs = layout.panes.flatMap((pane: DesktopDockPane): DesktopDockTab[] => pane.tabs)
    .concat(layout.floats.map((panel: DesktopDockFloat): DesktopDockTab => panel.tab));
  const existing = tabs.find((tab: DesktopDockTab): boolean => tab.kind === DesktopDockKind.PREVIEW &&
    tab.sourceSessionId === sourceSessionId && tab.file?.path === path);
  if (existing !== undefined) {
    return existing.id === replaceId ? layout : desktopDockOpen(layout, existing, false);
  }
  const replace = tabs.find((tab: DesktopDockTab): boolean =>
    tab.id === replaceId && tab.kind === DesktopDockKind.PREVIEW && tab.sourceSessionId === sourceSessionId);
  const resourceId = desktopDockResourceId('file', path, sourceSessionId);
  let id = replace?.id ?? resourceId;
  if (replace === undefined && tabs.some((tab: DesktopDockTab): boolean => tab.id === id)) {
    const used = new Set<string>(tabs.map((tab: DesktopDockTab): string => tab.id));
    let suffix = 1;
    do {
      id = 'file-slot:' + JSON.stringify([resourceId, suffix++]);
    } while (used.has(id));
  }
  const preview: DesktopDockTab = { id: id, kind: DesktopDockKind.PREVIEW, title: name || path,
    file: { path: path, name: name }, sourceSessionId: sourceSessionId };
  if (replace === undefined) { return desktopDockOpen(layout, preview, false); }
  const next = copyDock(layout);
  for (const pane of next.panes) {
    const index = pane.tabs.findIndex((tab: DesktopDockTab): boolean => tab.id === id);
    if (index >= 0) {
      pane.tabs[index] = preview;
      return next;
    }
  }
  const index = next.floats.findIndex((panel: DesktopDockFloat): boolean => panel.tab.id === id);
  if (index >= 0) { next.floats[index] = { tab: preview, rect: next.floats[index].rect }; }
  return next;
}

function removeTab(pane: DesktopDockPane, index: number): DesktopDockTab {
  const tab = pane.tabs.splice(index, 1)[0];
  if (pane.active === tab.id) { pane.active = pane.tabs[Math.min(index, pane.tabs.length - 1)]?.id ?? ''; }
  return tab;
}

export function desktopDockCloseTab(layout: DesktopDockLayout, pane: number, tab: string): DesktopDockLayout {
  const index = layout.panes[pane]?.tabs.findIndex((item: DesktopDockTab): boolean => item.id === tab) ?? -1;
  if (index < 0) { return layout; }
  const next = copyDock(layout);
  removeTab(next.panes[pane], index);
  settleEmptyPane(next, pane);
  return next;
}

export function desktopDockSplit(layout: DesktopDockLayout, side: number = 1): DesktopDockLayout {
  if (layout.panes.length > 1) { return layout; }
  const next = copyDock(layout);
  next.panes.splice(side, 0, { id: 1 - layout.panes[0].id, tabs: [], active: '' });
  next.focus = side;
  next.focusedFloat = '';
  next.expanded = true;
  next.fraction = 0.5;
  return next;
}

export function desktopDockMerge(layout: DesktopDockLayout, target: number): DesktopDockLayout {
  if (layout.panes.length !== 2 || target < 0 || target > 1) { return layout; }
  const next = copyDock(layout);
  const keep = next.panes[target];
  const from = next.panes[1 - target];
  keep.tabs.push(...from.tabs);
  if (!keep.active) { keep.active = from.active; }
  next.panes = [keep];
  next.focus = 0;
  next.focusedFloat = '';
  next.fraction = 0.5;
  return next;
}

export function desktopDockMoveTab(layout: DesktopDockLayout, from: number, id: string, to: number = 1 - from,
  before: string = ''): DesktopDockLayout {
  const index = layout.panes[from]?.tabs.findIndex((tab: DesktopDockTab): boolean => tab.id === id) ?? -1;
  if (index < 0 || layout.panes[to] === undefined || id === before) { return layout; }
  const next = copyDock(layout);
  const tab = removeTab(next.panes[from], index);
  const target = next.panes[to];
  const insertion = target.tabs.findIndex((item: DesktopDockTab): boolean => item.id === before);
  target.tabs.splice(insertion < 0 ? target.tabs.length : insertion, 0, tab);
  target.active = id;
  next.focus = to;
  next.focusedFloat = '';
  return next;
}

function settleEmptyPane(layout: DesktopDockLayout, pane: number): void {
  if (layout.panes.length > 1 && layout.panes[pane].tabs.length === 0) {
    layout.panes.splice(pane, 1);
    layout.focus = 0;
    layout.fraction = 0.5;
  }
}

export function desktopDockFloat(layout: DesktopDockLayout, pane: number, id: string,
  rect: DesktopDockRect): DesktopDockLayout {
  const index = layout.panes[pane]?.tabs.findIndex((tab: DesktopDockTab): boolean => tab.id === id) ?? -1;
  if (index < 0) { return layout; }
  const next = copyDock(layout);
  next.floats.push({ tab: removeTab(next.panes[pane], index), rect: rect });
  settleEmptyPane(next, pane);
  next.focusedFloat = id;
  return next;
}

export function desktopDockFocusFloat(layout: DesktopDockLayout, id: string): DesktopDockLayout {
  const index = layout.floats.findIndex((item: DesktopDockFloat): boolean => item.tab.id === id);
  if (index < 0 || layout.focusedFloat === id) { return layout; }
  const next = copyDock(layout);
  next.floats.push(next.floats.splice(index, 1)[0]);
  next.focusedFloat = id;
  return next;
}

export function desktopDockFloatPosition(layout: DesktopDockLayout, id: string, rect: DesktopDockRect): DesktopDockLayout {
  const index = layout.floats.findIndex((item: DesktopDockFloat): boolean => item.tab.id === id);
  if (index < 0) { return layout; }
  const next = copyDock(layout);
  next.floats[index] = { tab: next.floats[index].tab, rect: rect };
  return next;
}

export function desktopDockCloseFloat(layout: DesktopDockLayout, id: string): DesktopDockLayout {
  const index = layout.floats.findIndex((item: DesktopDockFloat): boolean => item.tab.id === id);
  if (index < 0) { return layout; }
  const next = copyDock(layout);
  next.floats.splice(index, 1);
  if (next.focusedFloat === id) { next.focusedFloat = next.floats[next.floats.length - 1]?.tab.id ?? ''; }
  return next;
}

export function desktopDockSeatFloat(layout: DesktopDockLayout, id: string, pane: number = layout.focus,
  before: string = ''): DesktopDockLayout {
  const index = layout.floats.findIndex((item: DesktopDockFloat): boolean => item.tab.id === id);
  if (index < 0 || layout.panes[pane] === undefined) { return layout; }
  const next = copyDock(layout);
  const tab = next.floats.splice(index, 1)[0].tab;
  const target = next.panes[pane];
  const insertion = target.tabs.findIndex((item: DesktopDockTab): boolean => item.id === before);
  target.tabs.splice(insertion < 0 ? target.tabs.length : insertion, 0, tab);
  target.active = id;
  next.focus = pane;
  next.focusedFloat = '';
  next.expanded = true;
  return next;
}

export function desktopDockFloatRect(rect: DesktopDockRect, width: number, height: number): DesktopDockRect {
  const maxWidth = Math.max(1, width - 12);
  const maxHeight = Math.max(1, height - 50);
  const panelWidth = Math.min(maxWidth, Math.max(Math.min(240, maxWidth), rect.width));
  const panelHeight = Math.min(maxHeight, Math.max(Math.min(180, maxHeight), rect.height));
  return { x: Math.max(6, Math.min(width - panelWidth - 6, rect.x)),
    y: Math.max(44, Math.min(height - panelHeight - 6, rect.y)), width: panelWidth, height: panelHeight };
}
