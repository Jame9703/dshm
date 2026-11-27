import { projectWireRecord } from 'appstate';
import { getField, getNumber, getRecord, getString } from 'connection';
import type { DesktopProcessGroup, DesktopToolStep } from './DesktopToolLog';

const EVENT_TYPES: string[] = ['turn/start', 'turn/end', 'step/start', 'step/end', 'system/message', 'request/header',
  'request/context', 'user/message', 'developer/message', 'assistant/message', 'compaction/start',
  'compaction/summary', 'compaction/end', 'session/end-seed'];
const TOOL_TYPES: string[] = ['tool/call', 'tool/result', 'tool/ptc-dispatch-start', 'tool/ptc-dispatch'];

export interface DesktopTraceRow {
  id: string;
  sequence: number;
  turn: number;
  step: number;
  kind: string;
  title: string;
  started: number;
  duration: number;
  content: string;
  reasoning: string;
  argumentsText: string;
  detail?: Object;
  usage?: Object;
  depth: number;
  failed: boolean;
  revision: string;
}

interface TraceEvent {
  kind: string;
  sequence: number;
  time: number;
  turn: number;
  step: number;
  data?: Object;
  record: Object;
}

function readEvent(record: Object): TraceEvent {
  const event = getRecord(record, 'event');
  const data = getRecord(event, 'data');
  return {
    kind: getString(event, 'type') ?? '',
    sequence: getNumber(event, 'seq') ?? -1, time: getNumber(event, 'time') ?? 0,
    turn: getNumber(data, 'turn') ?? 0, step: getNumber(data, 'step') ?? 0, data: data, record: record
  };
}

function messageKind(event: TraceEvent): string {
  switch (event.kind) {
    case 'user/message': {
      const source = getString(getRecord(event.data, 'source'), 'kind');
      return source === undefined || source === 'user' ? 'user' : 'context';
    }
    case 'assistant/message': return 'assistant';
    case 'system/message':
    case 'request/header': return 'system';
    case 'compaction/summary': return 'compaction';
    case 'session/end-seed': return 'boundary';
    default: return 'context';
  }
}

function stepKey(event: TraceEvent, turn: number): string { return turn + ':' + event.step; }

function duration(started: number, ended: number): number {
  return started > 0 && ended > started ? ended - started : 0;
}

/** Retains existing wire objects and projects inspection data only when the user opens Trajectory. */
export class DesktopTrajectoryLog {
  private readonly events: Map<number, Object> = new Map();
  private tools: DesktopProcessGroup[] = [];
  private revision: number = 0;

  version(): number { return this.revision; }

  clear(): void {
    this.events.clear();
    this.tools = [];
    this.revision++;
  }

  observe(record: Object, type: string | undefined, sequence: number): void {
    if (sequence < 0 || type === undefined) { return; }
    if (EVENT_TYPES.includes(type)) {
      this.events.set(sequence, record);
      this.revision++;
    } else if (TOOL_TYPES.includes(type)) {
      this.revision++;
    }
  }

  setProcesses(tools: DesktopProcessGroup[]): void { this.tools = tools; }

  rows(): DesktopTraceRow[] {
    const events = Array.from(this.events.values()).map((record: Object): TraceEvent => readEvent(record));
    events.sort((a: TraceEvent, b: TraceEvent): number => a.sequence - b.sequence);
    const before = new Map<string, TraceEvent>();
    const after = new Map<string, TraceEvent>();
    for (const event of events) {
      if (event.kind === 'step/start') { before.set(stepKey(event, event.turn), event); }
      if (event.kind === 'step/end') { after.set(stepKey(event, event.turn), event); }
    }
    const result: DesktopTraceRow[] = [];
    let turn = 0;
    for (const event of events) {
      if (event.kind === 'turn/start') { turn = event.turn; continue; }
      if (event.kind === 'turn/end') { turn = 0; continue; }
      if (event.kind === 'step/start' || event.kind === 'step/end' || event.kind === 'compaction/start' ||
        event.kind === 'compaction/end') { continue; }
      const kind = messageKind(event);
      const owner = event.turn || turn;
      const started = kind === 'assistant' ? before.get(stepKey(event, owner))?.time ?? event.time : event.time;
      const finished = kind === 'assistant' ? after.get(stepKey(event, owner)) : undefined;
      const message = projectWireRecord(event.record);
      const content = message?.body || getString(event.data, 'summary') || '';
      const title = kind === 'assistant' ? message?.model || '' :
        kind === 'context' ? getString(getRecord(event.data, 'source'), 'kind') ?? '' : '';
      result.push({
        id: 'event-' + event.sequence, sequence: event.sequence, turn: owner, step: event.step, kind: kind,
        title: title, started: started, duration: duration(started, finished?.time ?? 0), content: content,
        reasoning: message?.reasoning ?? '', argumentsText: '', detail: event.data,
        usage: getField(event.data, 'usage'), depth: 0, failed: false,
        revision: String(finished?.sequence ?? event.sequence)
      });
    }
    for (const group of this.tools) {
      for (const tool of group.steps) {
        result.push(this.toolRow(group, tool));
      }
    }
    return result.sort((a: DesktopTraceRow, b: DesktopTraceRow): number => a.sequence - b.sequence);
  }

  private toolRow(group: DesktopProcessGroup, tool: DesktopToolStep): DesktopTraceRow {
    return {
      id: 'tool-' + tool.id, sequence: group.sequence, turn: group.turn, step: 0,
      kind: tool.depth > 0 ? 'subtool' : 'tool', title: tool.item.toolName, started: tool.item.at,
      duration: tool.item.elapsedMs, content: tool.item.toolOutput || tool.error, reasoning: '',
      argumentsText: tool.item.toolArgs, depth: tool.depth,
      failed: tool.item.toolState === 'failed' || tool.item.toolState === 'rejected' || tool.interrupted,
      revision: group.version
    };
  }
}
