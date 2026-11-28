import { makeItem, projectWireRecord, ToolState, TrajectoryItem, TrajectoryKind } from 'appstate';
import { getArray, getBoolean, getNumber, getRecord, getString, parseJson, stringifyJson } from 'connection';
import { desktopCordisAction, desktopCordisCard, desktopCordisRunKey } from './DesktopCordisCards';
import type { DesktopCordisCard } from './DesktopCordisCards';
import { readDesktopTimelineReceipt } from './DesktopTimelineReceipt';
import type { DesktopTimelineReceipt } from './DesktopTimelineReceipt';
import { readDesktopProcessDiffMeta } from './DesktopProcessDiffModel';
import type { DesktopProcessDiffMeta } from './DesktopProcessDiffModel';

interface ToolEntry {
  id: string;
  parentId: string;
  turn: number;
  step: number;
  start: number;
  end: number;
  call?: TrajectoryItem;
  result?: TrajectoryItem;
  cordisArgs?: string;
  cordisResult?: Object;
  timeline?: DesktopTimelineReceipt;
  timelineStamp?: string;
  timelineRevision?: number;
  diffMeta?: DesktopProcessDiffMeta;
  diffStamp?: string;
  diffRevision?: number;
  error: string;
}

export interface DesktopToolStep {
  id: string;
  sequence: number;
  item: TrajectoryItem;
  depth: number;
  step: number;
  resultSequence: number;
  cordis?: DesktopCordisCard;
  timeline?: DesktopTimelineReceipt;
  timelineRevision: number;
  diffMeta?: DesktopProcessDiffMeta;
  diffRevision?: number;
  nested?: boolean;
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
  private readonly pendingGroupTurns: Set<number> = new Set();
  private cachedGroups?: DesktopProcessGroup[];

  clear(): void {
    this.entries.clear();
    this.closed.clear();
    this.pendingGroupTurns.clear();
    this.cachedGroups = undefined;
  }

  approvalCommand(callId: string): string | undefined {
    const entry = this.entries.get(callId);
    const call = entry?.call;
    if (entry === undefined || entry.parentId || call === undefined) { return undefined; }
    const argumentsValue = parseJson(call.toolArgs);
    const command = getString(argumentsValue, call.toolName === 'terminal_send' ? 'text' : 'command');
    return command || undefined;
  }

  observe(record: Object): boolean {
    const event = getRecord(record, 'event');
    const data = getRecord(event, 'data');
    const type = getString(event, 'type');
    const turn = getNumber(data, 'turn') ?? 0;
    const step = getNumber(data, 'step') ?? 0;
    if (type === 'turn/end' && turn > 0) {
      if (!this.closed.has(turn)) {
        this.closed.add(turn);
        if (this.pendingGroupTurns.has(turn)) { this.cachedGroups = undefined; }
      }
      return false;
    }
    const child = type === 'tool/ptc-dispatch' || type === 'tool/ptc-dispatch-start';
    const done = type === 'tool/result' || type === 'tool/ptc-dispatch';
    if (!child && type !== 'tool/call' && type !== 'tool/result') { return false; }
    const seq = getNumber(event, 'seq') ?? -1;
    const resultMessage = getRecord(data, 'message');
    const id = child ? getString(data, 'subCallId') : done ?
      getString(resultMessage, 'toolCallId') || getString(getRecord(resultMessage, 'source'), 'callId') :
      getString(data, 'callId');
    if (!id || seq < 0) { return false; }
    const entry: ToolEntry = this.entries.get(id) ??
      { id: id, parentId: '', turn: 0, step: 0, start: -1, end: -1, error: '' };
    const name = getString(data, 'name') ?? '';
    const parentId = child ? getString(data, 'parentCallId') ?? '' : '';
    if (parentId && parentId !== id && parentId !== entry.parentId) {
      entry.parentId = parentId;
      this.cachedGroups = undefined;
    }
    if (turn > 0 && turn !== entry.turn) {
      entry.turn = turn;
      this.cachedGroups = undefined;
    }
    if (step > 0 && step !== entry.step) {
      entry.step = step;
      this.cachedGroups = undefined;
    }
    // Even an older frame can supply placement facts, but its call or result does not replace newer evidence.
    if (done ? entry.end > seq : entry.start >= 0 && seq >= entry.start) { return false; }
    const args = getRecord(data, 'arguments');
    const item = (child ? undefined : projectWireRecord(record)) ??
      makeItem(id, TrajectoryKind.TOOL, getNumber(event, 'time') ?? 0);
    if (name) { item.toolName = name; }
    if (child && args !== undefined) { item.toolArgs = stringifyJson(args) ?? ''; }
    item.callId = id;
    if (done) {
      const error = getRecord(data, 'error');
      const code = getString(error, 'code') ?? '';
      const problem = getString(error, 'reason') || getString(error, 'message') || code;
      const failed = getBoolean(child ? data : resultMessage, 'isError') === true || error !== undefined;
      if (item.toolState !== ToolState.REJECTED) {
        item.toolState = failed ? ToolState.FAILED : ToolState.SUCCESS;
      }
      item.toolOutput = renderContent(child ? data : resultMessage) || item.toolOutput;
      const meta = !child && item.toolState === ToolState.SUCCESS ? getRecord(data, 'meta') : undefined;
      const timeline = readDesktopTimelineReceipt(getRecord(meta, 'timeline'));
      const timelineStamp = timeline === undefined ? undefined : stringifyJson(timeline);
      const diffMeta = readDesktopProcessDiffMeta(meta);
      const diffStamp = diffMeta === undefined ? undefined : stringifyJson(diffMeta);
      const previous = entry.result;
      const changed = seq !== entry.end || problem !== entry.error || previous?.at !== item.at ||
        previous?.toolName !== item.toolName || previous?.toolState !== item.toolState ||
        previous?.toolOutput !== item.toolOutput || timelineStamp !== entry.timelineStamp || diffStamp !== entry.diffStamp;
      if (changed) { this.cachedGroups = undefined; }
      entry.error = problem;
      entry.result = item;
      entry.timeline = timeline;
      if (timelineStamp !== entry.timelineStamp) { entry.timelineRevision = (entry.timelineRevision ?? 0) + 1; }
      entry.timelineStamp = timelineStamp;
      entry.diffMeta = diffMeta;
      if (diffStamp !== entry.diffStamp) { entry.diffRevision = (entry.diffRevision ?? 0) + 1; }
      entry.diffStamp = diffStamp;
      entry.end = seq;
      if (desktopCordisAction(entry.call?.toolName || name) || getString(getRecord(data, 'meta'), 'pluginId')) {
        const previousData = entry.cordisResult;
        if (!changed && previousData !== data && (previousData === undefined || data === undefined ||
            stringifyJson(previousData) !== stringifyJson(data))) {
          this.cachedGroups = undefined;
        }
        entry.cordisResult = data;
      }
    } else {
      this.cachedGroups = undefined;
      item.toolState = ToolState.RUNNING;
      entry.call = item;
      entry.start = seq;
      if (desktopCordisAction(name)) { entry.cordisArgs = getString(data, 'arguments') ?? item.toolArgs; }
    }
    this.entries.set(id, entry);
    return done && !!desktopCordisAction(entry.call?.toolName || name);
  }

  private step(entry: ToolEntry, depth: number, turn: number, parentStep: number): DesktopToolStep {
    const call = entry.call;
    const result = entry.result;
    const item = makeItem(entry.id, TrajectoryKind.TOOL, call?.at ?? result?.at ?? 0);
    item.toolName = call?.toolName || result?.toolName || '工具调用';
    item.toolArgs = call?.toolArgs || result?.toolArgs || '';
    item.toolOutput = result?.toolOutput ?? '';
    item.toolState = result?.toolState ?? ToolState.RUNNING;
    item.elapsedMs = result === undefined ? 0 : Math.max(0, result.at - (call?.at ?? result.at));
    const interrupted = result === undefined && this.closed.has(turn);
    const action = desktopCordisAction(item.toolName);
    const cordis = action ? desktopCordisCard(action, entry.id, timestamp(entry), entry.end,
      entry.cordisArgs ?? item.toolArgs, entry.cordisResult, item.toolState, item.toolOutput || entry.error,
      interrupted || getString(getRecord(entry.cordisResult, 'error'), 'code') === 'interrupted') : undefined;
    return { id: entry.id, sequence: timestamp(entry), item: item, depth: depth, step: entry.step || parentStep,
      resultSequence: entry.end,
      interrupted: interrupted, error: entry.error, cordis: cordis,
      timeline: item.toolName === 'timeline_tasks' ? entry.timeline : undefined,
      timelineRevision: entry.timelineRevision ?? 0,
      diffMeta: entry.diffMeta, diffRevision: entry.diffRevision, nested: !!entry.parentId };
  }

  groups(): DesktopProcessGroup[] {
    if (this.cachedGroups !== undefined) { return this.cachedGroups; }
    this.pendingGroupTurns.clear();
    const rows = Array.from(this.entries.values()).sort((a: ToolEntry, b: ToolEntry): number => timestamp(a) - timestamp(b));
    const children: Map<string, ToolEntry[]> = new Map();
    for (const entry of rows) {
      const group = children.get(entry.parentId) ?? [];
      group.push(entry);
      children.set(entry.parentId, group);
    }
    const groups: DesktopProcessGroup[] = [];
    const seen: Set<string> = new Set();
    const runCards: DesktopCordisCard[] = [];
    const latestRuns = new Map<string, number>();
    for (const root of rows) {
      if (root.parentId && this.entries.has(root.parentId)) { continue; }
      const steps: DesktopToolStep[] = [];
      const stamps: string[] = [];
      this.attach(root, 0, root.turn, root.step, children, seen, steps, stamps);
      if (steps.length > 0) {
        groups.push({ id: root.id, sequence: timestamp(root), turn: root.turn, version: stamps.join('|'), steps: steps });
        for (const step of steps) {
          if (step.resultSequence < 0 && !step.interrupted) { this.pendingGroupTurns.add(root.turn); }
          if (step.cordis === undefined) { continue; }
          const key = desktopCordisRunKey(step.cordis);
          if (key) {
            runCards.push(step.cordis);
            latestRuns.set(key, Math.max(latestRuns.get(key) ?? -1, step.resultSequence));
          }
        }
      }
    }
    for (const card of runCards) {
      card.superseded = (latestRuns.get(desktopCordisRunKey(card)) ?? -1) > card.resultSequence;
    }
    this.cachedGroups = groups;
    return groups;
  }

  private attach(row: ToolEntry, depth: number, turn: number, parentStep: number,
    children: Map<string, ToolEntry[]>, seen: Set<string>,
    steps: DesktopToolStep[], stamps: string[]): void {
    if (seen.has(row.id) || depth > 24) { return; }
    seen.add(row.id);
    const step = this.step(row, depth, turn, parentStep);
    steps.push(step);
    stamps.push(`${row.id}:${row.start}:${row.end}:${step.interrupted}`);
    if (step.timelineRevision > 0) { stamps.push(String(step.timelineRevision)); }
    if (step.diffRevision !== undefined && step.diffRevision > 0) { stamps.push('diff:' + step.diffRevision); }
    for (const child of children.get(row.id) ?? []) {
      this.attach(child, depth + 1, turn, step.step, children, seen, steps, stamps);
    }
  }
}
