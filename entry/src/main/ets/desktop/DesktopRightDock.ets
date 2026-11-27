import type { DesktopChangeTarget } from './DesktopArtifacts';
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
}

export function emptyDesktopDock(): DesktopDockLayout {
  return { panes: [{ tabs: [], active: '' }], focus: 0, expanded: false, fullscreen: false };
}

function copyDock(layout: DesktopDockLayout): DesktopDockLayout {
  return { panes: layout.panes.map((pane: DesktopDockPane): DesktopDockPane =>
    ({ tabs: pane.tabs.slice(), active: pane.active })), focus: layout.focus, expanded: layout.expanded,
    fullscreen: layout.fullscreen };
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
  }
  return next;
}

export function desktopDockSplit(layout: DesktopDockLayout): DesktopDockLayout {
  if (layout.panes.length > 1) { return layout; }
  const next = copyDock(layout);
  next.panes.push({ tabs: [], active: '' });
  next.focus = 1;
  next.expanded = true;
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
  return next;
}

export function desktopDockMoveTab(layout: DesktopDockLayout, from: number, id: string): DesktopDockLayout {
  const index = layout.panes[from]?.tabs.findIndex((tab: DesktopDockTab): boolean => tab.id === id) ?? -1;
  if (layout.panes.length !== 2 || index < 0) { return layout; }
  const next = copyDock(layout);
  const tab = removeTab(next.panes[from], index);
  const other = next.panes[1 - from];
  other.tabs.push(tab);
  other.active = id;
  next.focus = 1 - from;
  return next;
}
