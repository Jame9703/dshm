import type { DesktopChangeLocation, DesktopChangeTarget } from './DesktopArtifacts';
import type { DesktopFileNavigation } from './DesktopFilesPane';
import type { DesktopPlanDocument } from './DesktopPlan';

export enum DesktopDockKind { FILES = 'files', TERMINAL = 'terminal', PREVIEW = 'preview', PLAN = 'plan', CHANGES = 'changes' }

export interface DesktopDockTab {
  id: string;
  kind: DesktopDockKind;
  title: string;
  file?: DesktopFileNavigation;
  plan?: DesktopPlanDocument;
  changes?: DesktopChangeTarget;
  changeLocation?: DesktopChangeLocation;
}

export interface DesktopDockPane {
  tabs: DesktopDockTab[];
  active: string;
}

export interface DesktopDockLayout {
  panes: DesktopDockPane[];
  focus: number;
  expanded: boolean;
  fullscreen: boolean;
  width: number;
  fraction: number;
}

export function emptyDesktopDock(): DesktopDockLayout {
  return { panes: [{ tabs: [], active: '' }], focus: 0, expanded: false, fullscreen: false, width: 0, fraction: 0.5 };
}

function copyDock(layout: DesktopDockLayout): DesktopDockLayout {
  return { panes: layout.panes.map((pane: DesktopDockPane): DesktopDockPane =>
    ({ tabs: pane.tabs.slice(), active: pane.active })), focus: layout.focus, expanded: layout.expanded,
    fullscreen: layout.fullscreen, width: layout.width, fraction: layout.fraction };
}

export function desktopDockPresentation(layout: DesktopDockLayout, focus: number, expanded: boolean,
  fullscreen: boolean): DesktopDockLayout {
  return { panes: layout.panes, focus: focus, expanded: expanded, fullscreen: fullscreen,
    width: layout.width, fraction: layout.fraction };
}

export function desktopDockResize(layout: DesktopDockLayout, width: number, fraction: number): DesktopDockLayout {
  return { panes: layout.panes, focus: layout.focus, expanded: layout.expanded, fullscreen: layout.fullscreen,
    width: width, fraction: fraction };
}

export function desktopDockSplitFraction(fraction: number): number {
  return Number.isFinite(fraction) ? Math.min(0.8, Math.max(0.2, fraction)) : 0.5;
}

export function desktopDockTab(layout: DesktopDockLayout, index: number = layout.focus): DesktopDockTab | undefined {
  const pane = layout.panes[index];
  return pane?.tabs.find((tab: DesktopDockTab): boolean => tab.id === pane.active);
}

export function desktopDockOpen(layout: DesktopDockLayout, tab: DesktopDockTab, update: boolean = true): DesktopDockLayout {
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
  return next;
}

export function desktopDockSelect(layout: DesktopDockLayout, pane: number, tab: string): DesktopDockLayout {
  if (!layout.panes[pane]?.tabs.some((item: DesktopDockTab): boolean => item.id === tab)) { return layout; }
  const next = copyDock(layout);
  next.focus = pane;
  next.panes[pane].active = tab;
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
  if (next.panes.length > 1 && next.panes[pane].tabs.length === 0) {
    next.panes.splice(pane, 1);
    next.focus = 0;
    next.fraction = 0.5;
  }
  return next;
}

export function desktopDockSplit(layout: DesktopDockLayout, side: number = 1): DesktopDockLayout {
  if (layout.panes.length > 1) { return layout; }
  const next = copyDock(layout);
  next.panes.splice(side, 0, { tabs: [], active: '' });
  next.focus = side;
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
  return next;
}
