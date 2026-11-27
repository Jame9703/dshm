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
  tokens?: number;
  settledMs?: number;
  turnSince?: number;
  turnThrough?: number;
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

export function desktopSubagentRows(entries: DesktopSubagentEntry[], summaries: SessionListItem[],
  loadedProjections?: Map<string, Object>): DesktopSubagentRow[] {
  const byId = new Map<string, SessionListItem>();
  summaries.forEach((summary: SessionListItem): void => { byId.set(summary.id, summary); });
  return entries.map((entry: DesktopSubagentEntry): DesktopSubagentRow => {
    const summary = byId.get(entry.id);
    const listed = getRecord(summary?.raw, 'projections');
    const loaded = loadedProjections?.get(entry.id);
    const latest = (getNumber(loaded, 'asOfSeq') ?? -1) > (getNumber(listed, 'asOfSeq') ?? -1) ? loaded : listed ?? loaded;
    const values = getRecord(latest, 'values');
    const timing = getRecord(values, 'subagentTiming');
    const turn = getRecord(timing, 'active');
    const turnSince = getNumber(turn, 'since');
    const usage = getRecord(values, 'tokenUsage');
    const external = entry.mode === 'external';
    const running = !external && summary?.running === true;
    const status = external ? 'external' : running ? 'running' :
      getBoolean(timing, 'lastTurnCompleted') === true ? 'completed' : 'inactive';
    const activeAt = running ? turnSince ?? entry.createdAt : Math.max(summary?.updatedAt ?? 0, entry.createdAt);
    return { entry: entry, title: entry.label || summary?.title || entry.name, status: status, activeAt: activeAt,
      tokens: desktopSubagentTokenTotal(usage), settledMs: getNumber(timing, 'settledMs'),
      turnSince: turnSince, turnThrough: getNumber(turn, 'through') };
  }).sort((a: DesktopSubagentRow, b: DesktopSubagentRow): number =>
    Number(b.status === 'running') - Number(a.status === 'running') || b.activeAt - a.activeAt);
}

function desktopSubagentTokenTotal(usage?: Object): number | undefined {
  const input = getNumber(usage, 'uncachedInputTokens');
  const output = getNumber(usage, 'outputTokens');
  const read = getNumber(usage, 'cacheReadTokens');
  const written = getNumber(usage, 'cacheWriteTokens');
  if (input === undefined || output === undefined || read === undefined || written === undefined) { return undefined; }
  return input + output + read + written;
}

export function desktopSubagentTokenLabel(count?: number): string {
  if (count === undefined) { return ''; }
  if (count < 1000) { return `${count} tok`; }
  const millions = count >= 1000000;
  const scaled = count / (millions ? 1000000 : 1000);
  const rounded = scaled >= 100 ? Math.round(scaled) : Math.round(scaled * 10) / 10;
  return `${rounded}${millions ? 'M' : 'K'} tok`;
}

export function desktopSubagentDurationLabel(row: DesktopSubagentRow, now: number, exact: boolean = false): string {
  if (row.settledMs === undefined) { return ''; }
  const end = row.status === 'running' ? now : row.turnThrough;
  const activeMs = row.turnSince === undefined || end === undefined ? 0 : Math.max(0, end - row.turnSince);
  const totalSeconds = Math.floor(Math.max(0, row.settledMs + activeMs) / 1000);
  const seconds = totalSeconds % 60;
  const minutes = Math.floor(totalSeconds / 60) % 60;
  const hours = Math.floor(totalSeconds / 3600) % 24;
  const days = Math.floor(totalSeconds / 86400);
  const minutePart = String(minutes).padStart(2, '0');
  const secondPart = String(seconds).padStart(2, '0');
  if (days >= 1 && exact) { return `${days}天${String(hours).padStart(2, '0')}小时${minutePart}分${secondPart}秒`; }
  if (days >= 365) {
    const months = Math.floor((days % 365) / 30);
    return `约${Math.floor(days / 365)}年` + (months > 0 ? `${months}个月` : '');
  }
  if (days >= 30) { return `约${Math.floor(days / 30)}个月` + (days % 30 > 0 ? `${days % 30}天` : ''); }
  if (days > 0) { return `${days}天` + (hours > 0 ? `${hours}小时` : ''); }
  if (hours > 0) { return `${hours}小时${minutePart}分${secondPart}秒`; }
  if (minutes > 0) { return `${minutes}分${secondPart}秒`; }
  return `${seconds}秒`;
}

export function desktopSubagentModeLabel(mode: string): string {
  if (mode === 'continuable') { return '可继续'; }
  if (mode === 'one-shot') { return '一次性'; }
  if (mode === 'external') { return '外部任务'; }
  return '模式未知';
}
