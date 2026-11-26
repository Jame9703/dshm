import { makeItem, projectWireRecord, ToolState, TrajectoryItem, TrajectoryKind } from 'appstate';
import { getArray, getBoolean, getNumber, getRecord, getString, stringifyJson } from 'connection';

interface ToolEntry {
  id: string;
  parentId: string;
  turn: number;
  start: number;
  end: number;
  call?: TrajectoryItem;
  result?: TrajectoryItem;
  error: string;
}

export interface DesktopToolStep {
  id: string;
  item: TrajectoryItem;
  depth: number;
  interrupted: boolean;
  error: string;
}

export interface DesktopProcessGroup {
  id: string;
  sequence: number;
  turn: number;
  version: string;
  steps: DesktopToolStep[];
}

function renderContent(data?: Object): string {
  return (getArray(data, 'content') ?? []).map((block: Object): string => getString(block, 'text') ?? '')
    .filter((text: string): boolean => text.length > 0).join('\n');
}

function timestamp(row: ToolEntry): number { return row.start >= 0 ? row.start : row.end; }

export class DesktopToolLog {
  private readonly entries: Map<string, ToolEntry> = new Map();
  private readonly closed: Set<number> = new Set();

  clear(): void { this.entries.clear(); this.closed.clear(); }

  observe(record: Object): void {
    const event = getRecord(record, 'event');
    const data = getRecord(event, 'data');
    const type = getString(event, 'type');
    const turn = getNumber(data, 'turn') ?? 0;
    if (type === 'turn/end' && turn > 0) { this.closed.add(turn); return; }
    const child = type === 'tool/ptc-dispatch' || type === 'tool/ptc-dispatch-start';
    const done = type === 'tool/result' || type === 'tool/ptc-dispatch';
    if (!child && type !== 'tool/call' && type !== 'tool/result') { return; }
    const seq = getNumber(event, 'seq') ?? -1;
    const resultMessage = getRecord(data, 'message');
    const id = child ? getString(data, 'subCallId') : done ?
      getString(getRecord(resultMessage, 'source'), 'callId') : getString(data, 'callId');
    if (!id || seq < 0) { return; }
    const entry: ToolEntry = this.entries.get(id) ?? { id: id, parentId: '', turn: 0, start: -1, end: -1, error: '' };
    const name = getString(data, 'name') ?? '';
    const parentId = child ? getString(data, 'parentCallId') ?? '' : '';
    if (parentId && parentId !== id) { entry.parentId = parentId; }
    if (turn > 0) { entry.turn = turn; }
    const args = getRecord(data, 'arguments');
    const item = (child ? undefined : projectWireRecord(record)) ??
      makeItem(id, TrajectoryKind.TOOL, getNumber(event, 'time') ?? 0);
    if (name) { item.toolName = name; }
    if (child && args !== undefined) { item.toolArgs = stringifyJson(args) ?? ''; }
    item.callId = id;
    if (done) {
      if (entry.end > seq) { return; }
      const error = getRecord(data, 'error');
      const code = getString(error, 'code') ?? '';
      entry.error = getString(error, 'reason') || getString(error, 'message') || code;
      const failed = getBoolean(child ? data : resultMessage, 'isError') === true || error !== undefined;
      if (item.toolState !== ToolState.REJECTED) {
        item.toolState = failed ? ToolState.FAILED : ToolState.SUCCESS;
      }
      item.toolOutput = renderContent(child ? data : resultMessage) || item.toolOutput;
      entry.result = item;
      entry.end = seq;
    } else if (entry.start < 0 || seq < entry.start) {
      item.toolState = ToolState.RUNNING;
      entry.call = item;
      entry.start = seq;
    }
    this.entries.set(id, entry);
  }

  private step(entry: ToolEntry, depth: number, turn: number): DesktopToolStep {
    const call = entry.call;
    const result = entry.result;
    const item = makeItem(entry.id, TrajectoryKind.TOOL, call?.at ?? result?.at ?? 0);
    item.toolName = call?.toolName || result?.toolName || '工具调用';
    item.toolArgs = call?.toolArgs || result?.toolArgs || '';
    item.toolOutput = result?.toolOutput ?? '';
    item.toolState = result?.toolState ?? ToolState.RUNNING;
    item.elapsedMs = result === undefined ? 0 : Math.max(0, result.at - (call?.at ?? result.at));
    return { id: entry.id, item: item, depth: depth, interrupted: result === undefined && this.closed.has(turn),
      error: entry.error };
  }

  groups(): DesktopProcessGroup[] {
    const rows = Array.from(this.entries.values()).sort((a: ToolEntry, b: ToolEntry): number => timestamp(a) - timestamp(b));
    const children: Map<string, ToolEntry[]> = new Map();
    for (const entry of rows) {
      const group = children.get(entry.parentId) ?? [];
      group.push(entry);
      children.set(entry.parentId, group);
    }
    const groups: DesktopProcessGroup[] = [];
    const seen: Set<string> = new Set();
    for (const root of rows) {
      if (root.parentId && this.entries.has(root.parentId)) { continue; }
      const steps: DesktopToolStep[] = [];
      const stamps: string[] = [];
      this.attach(root, 0, root.turn, children, seen, steps, stamps);
      if (steps.length > 0) {
        groups.push({ id: root.id, sequence: timestamp(root), turn: root.turn, version: stamps.join('|'), steps: steps });
      }
    }
    return groups;
  }

  private attach(row: ToolEntry, depth: number, turn: number, children: Map<string, ToolEntry[]>, seen: Set<string>,
    steps: DesktopToolStep[], stamps: string[]): void {
    if (seen.has(row.id) || depth > 24) { return; }
    seen.add(row.id);
    const step = this.step(row, depth, turn);
    steps.push(step);
    stamps.push(`${row.id}:${row.start}:${row.end}:${step.interrupted}`);
    for (const child of children.get(row.id) ?? []) {
      this.attach(child, depth + 1, turn, children, seen, steps, stamps);
    }
  }
}
