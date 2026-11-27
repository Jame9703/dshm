import type { SessionListItem } from 'appstate';
import { getArray, getRecord, getString } from 'connection';

export enum DesktopSidebarPending {
  APPROVAL = 1,
  QUESTION = 2,
  PLAN_REVIEW = 3
}

export enum DesktopSidebarAgeUnit {
  NOW = 0,
  MINUTES = 1,
  HOURS = 2,
  DAYS = 3,
  MONTHS = 4,
  YEARS = 5
}

export interface DesktopSidebarAge {
  unit: DesktopSidebarAgeUnit;
  count: number;
}

export const SIDEBAR_SESSION_PAGE: number = 5;
const SIDEBAR_ATTENTION_LIMIT: number = 50;

export function desktopSidebarAge(updatedAt: number, now: number): DesktopSidebarAge {
  const diff = Math.max(0, now - updatedAt);
  const day = 86400000;
  if (diff < 60000) { return { unit: DesktopSidebarAgeUnit.NOW, count: 0 }; }
  if (diff < 3600000) { return { unit: DesktopSidebarAgeUnit.MINUTES, count: Math.floor(diff / 60000) }; }
  if (diff < day) { return { unit: DesktopSidebarAgeUnit.HOURS, count: Math.floor(diff / 3600000) }; }
  if (diff < 30 * day) { return { unit: DesktopSidebarAgeUnit.DAYS, count: Math.floor(diff / day) }; }
  if (diff < 365 * day) { return { unit: DesktopSidebarAgeUnit.MONTHS, count: Math.floor(diff / (30 * day)) }; }
  return { unit: DesktopSidebarAgeUnit.YEARS, count: Math.floor(diff / (365 * day)) };
}

export function desktopRunningSidebarChildren(sessions: SessionListItem[], unlisted: string[]): Map<string, number> {
  const running = new Set<string>(unlisted);
  for (const session of sessions) {
    if (session.running) { running.add(session.id); }
  }
  const counts = new Map<string, number>();
  if (running.size === 0) { return counts; }
  for (const session of sessions) {
    const values = getRecord(getRecord(session.raw, 'projections'), 'values');
    const entries = getArray(values, 'subagentCatalog');
    if (entries === undefined) { continue; }
    const children = new Set<string>();
    for (const entry of entries) {
      const id = getString(entry, 'id') ?? '';
      if (id !== session.id && getString(entry, 'mode') !== 'external' && running.has(id)) { children.add(id); }
    }
    if (children.size > 0) { counts.set(session.id, children.size); }
  }
  return counts;
}

export function desktopSidebarRequired(sessions: SessionListItem[], current: string, attention: Set<string>): number {
  let index = 0;
  let required = SIDEBAR_SESSION_PAGE;
  for (const session of sessions) {
    if (session.blank) { continue; }
    if (++index > SIDEBAR_ATTENTION_LIMIT) { break; }
    if (session.running || session.id === current || attention.has(session.id)) { required = Math.max(required, index); }
  }
  return required;
}

export function desktopSidebarRevealDepth(sessions: SessionListItem[], id: string): number {
  let index = 0;
  for (const session of sessions) {
    if (!session.blank) { index++; }
    if (session.id === id) { return index; }
  }
  return 0;
}

export function desktopSidebarRows(sessions: SessionListItem[], limit: number): SessionListItem[] {
  if (limit >= sessions.length) { return sessions; }
  let index = 0;
  return sessions.filter((session: SessionListItem): boolean => session.blank || ++index <= limit);
}
