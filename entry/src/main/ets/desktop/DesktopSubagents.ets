import type { SessionListItem } from 'appstate';
import { getArray, getBoolean, getNumber, getRecord, getString } from 'connection';

export interface DesktopSubagentEntry {
  parentId: string;
  id: string;
  mode: string;
  name: string;
  label: string;
  createdAt: number;
}

export interface DesktopSubagentRow {
  entry: DesktopSubagentEntry;
  title: string;
  status: string;
  activeAt: number;
}

export function desktopSubagentMode(mode?: string): string {
  return mode === 'continuable' || mode === 'one-shot' || mode === 'external' ? mode : 'unknown';
}

export function desktopSubagentCatalog(parentId: string, values?: Object): DesktopSubagentEntry[] | undefined {
  const catalog = getArray(values, 'subagentCatalog');
  if (catalog === undefined) { return undefined; }
  const children: DesktopSubagentEntry[] = [];
  const seen = new Set<string>();
  for (const item of catalog) {
    const id = getString(item, 'id') ?? '';
    if (!id || id === parentId || seen.has(id)) { continue; }
    seen.add(id);
    children.push({ id: id, parentId: parentId, mode: desktopSubagentMode(getString(item, 'mode')),
      name: getString(item, 'name') || id, label: getString(item, 'label') ?? '', createdAt: getNumber(item, 'createdAt') ?? 0 });
  }
  return children;
}

export function desktopSubagentFromSummary(item: SessionListItem): DesktopSubagentEntry | undefined {
  const parentId = getString(item.raw, 'parentSessionId') ?? '';
  if (!parentId || parentId === item.id || getString(item.raw, 'origin') !== 'subagent') { return undefined; }
  const values = getRecord(getRecord(item.raw, 'projections'), 'values');
  const child = getRecord(values, 'subagent');
  const mode = desktopSubagentMode(getString(child, 'mode'));
  return { parentId: parentId, id: item.id, mode: mode === 'external' ? 'unknown' : mode,
    label: getString(child, 'label') || item.title, name: item.id, createdAt: item.createdAt };
}

export function desktopSubagentRows(entries: DesktopSubagentEntry[], summaries: SessionListItem[]): DesktopSubagentRow[] {
  const byId = new Map<string, SessionListItem>();
  summaries.forEach((summary: SessionListItem): void => { byId.set(summary.id, summary); });
  return entries.map((entry: DesktopSubagentEntry): DesktopSubagentRow => {
    const summary = byId.get(entry.id);
    const timing = getRecord(getRecord(getRecord(summary?.raw, 'projections'), 'values'), 'subagentTiming');
    const external = entry.mode === 'external';
    const running = !external && summary?.running === true;
    const status = external ? 'external' : running ? 'running' :
      getBoolean(timing, 'lastTurnCompleted') === true ? 'completed' : 'inactive';
    const activeAt = running ? getNumber(getRecord(timing, 'active'), 'since') ?? entry.createdAt :
      Math.max(summary?.updatedAt ?? 0, entry.createdAt);
    return { entry: entry, title: entry.label || summary?.title || entry.name, status: status, activeAt: activeAt };
  }).sort((a: DesktopSubagentRow, b: DesktopSubagentRow): number =>
    Number(b.status === 'running') - Number(a.status === 'running') || b.activeAt - a.activeAt);
}

export function desktopSubagentModeLabel(mode: string): string {
  if (mode === 'continuable') { return '可继续'; }
  if (mode === 'one-shot') { return '一次性'; }
  if (mode === 'external') { return '外部任务'; }
  return '模式未知';
}
