import { projectWireRecord } from 'appstate';
import { getField, getNumber, getRecord, getString } from 'connection';
import type { DesktopProcessGroup, DesktopToolStep } from './DesktopToolLog';
import { DesktopTraceRequests, desktopTraceStepKey } from './DesktopTraceRequests';
import type { DesktopTraceRequest } from './DesktopTraceRequests';
import { DesktopTracePrompts } from './DesktopTracePrompts';
import type { DesktopTracePromptChange } from './DesktopTracePrompts';

const EVENT_TYPES: string[] = ['turn/start', 'turn/end', 'step/start', 'step/end', 'system/message', 'request/header',
  'request/context', 'user/message', 'developer/message', 'assistant/message', 'llm/retry', 'compaction/start',
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
  request?: DesktopTraceRequest;
  prompt?: DesktopTracePromptChange;
  schema?: Object;
  resultSequence?: number;
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
  surfaceOp?: Object;
  record: Object;
}

function readEvent(record: Object): TraceEvent {
  const event = getRecord(record, 'event');
  const data = getRecord(event, 'data');
  return {
    kind: getString(event, 'type') ?? '',
    sequence: getNumber(event, 'seq') ?? -1, time: getNumber(event, 'time') ?? 0,
    turn: getNumber(data, 'turn') ?? 0, step: getNumber(data, 'step') ?? 0, data: data,
    surfaceOp: getRecord(event, 'surfaceOp'), record: record
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
  private firstSequence: number = Number.MAX_SAFE_INTEGER;

  version(): number { return this.revision; }

  clear(): void {
    this.events.clear();
    this.tools = [];
    this.firstSequence = Number.MAX_SAFE_INTEGER;
    this.revision++;
  }

  observe(record: Object, type: string | undefined, sequence: number): void {
    if (sequence < 0 || type === undefined) { return; }
    const earlier = sequence < this.firstSequence;
    this.firstSequence = Math.min(this.firstSequence, sequence);
    if (EVENT_TYPES.includes(type)) {
      this.events.set(sequence, record);
      this.revision++;
    } else if (TOOL_TYPES.includes(type)) {
      if (type === 'tool/result' && getRecord(getRecord(record, 'event'), 'surfaceOp') !== undefined) {
        this.events.set(sequence, record);
      }
      this.revision++;
    } else if (earlier) {
      this.revision++;
    }
  }

  setProcesses(tools: DesktopProcessGroup[]): void { this.tools = tools; }

  rows(): DesktopTraceRow[] {
    const events = Array.from(this.events.values()).map((record: Object): TraceEvent => readEvent(record));
    events.sort((a: TraceEvent, b: TraceEvent): number => a.sequence - b.sequence);
    const requests = new DesktopTraceRequests();
    const prompts = new DesktopTracePrompts(this.firstSequence);
    const before = new Map<string, TraceEvent>();
    const after = new Map<string, TraceEvent>();
    for (const event of events) {
      requests.observe(event.kind, event.sequence, event.time, event.turn, event.step, event.data);
      if (event.kind === 'step/start') { before.set(stepKey(event, event.turn), event); }
      if (event.kind === 'step/end') { after.set(stepKey(event, event.turn), event); }
    }
    const result: DesktopTraceRow[] = [];
    let turn = 0;
    let step = 0;
    for (const event of events) {
      if (event.kind === 'turn/start') { turn = event.turn; continue; }
      if (event.kind === 'turn/end') { turn = 0; step = 0; continue; }
      if (event.kind === 'step/start') { step = event.step; continue; }
      if (event.kind === 'step/end') { step = 0; continue; }
      if (event.kind === 'compaction/start' || event.kind === 'compaction/end' || event.kind === 'llm/retry') { continue; }
      const kind = messageKind(event);
      const owner = event.turn || turn;
      const prompt = prompts.observe(event.kind, event.sequence, event.data, event.surfaceOp);
      if (kind !== 'system' && prompt?.previous !== undefined) {
        result.push({
          id: 'prompt-' + event.sequence, sequence: event.sequence, turn: owner, step: event.step || step,
          kind: 'system', title: '', started: event.time, duration: 0, content: '', reasoning: '', argumentsText: '',
          prompt: prompt, depth: 0, failed: false, revision: String(event.sequence)
        });
      }
      if (event.kind === 'tool/result') { continue; }
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
        usage: getField(event.data, 'usage'), prompt: kind === 'system' ? prompt : undefined,
        depth: 0, failed: false,
        revision: String(finished?.sequence ?? event.sequence)
      });
    }
    for (const group of this.tools) {
      for (const tool of group.steps) {
        const request = requests.steps.get(desktopTraceStepKey(group.turn, tool.step));
        if (request !== undefined) {
          if (tool.depth === 0) { request.toolCalls++; } else { request.subCalls++; }
        }
        result.push(this.toolRow(group, tool, request));
      }
    }
    requests.ordered().forEach((request: DesktopTraceRequest): void => {
      result.push({
        id: 'request-' + request.sequence, sequence: request.sequence, turn: request.turn, step: request.step,
        kind: 'request', title: request.model, started: request.started,
        duration: duration(request.started, request.completed), content: '', reasoning: '', argumentsText: '',
        request: request, depth: 0, failed: request.status === 'failed',
        revision: `${request.revision}:${request.number}:${request.toolCalls}:${request.subCalls}`
      });
    });
    return result.sort((a: DesktopTraceRow, b: DesktopTraceRow): number => a.sequence - b.sequence);
  }

  private toolRow(group: DesktopProcessGroup, tool: DesktopToolStep, request?: DesktopTraceRequest): DesktopTraceRow {
    const schema = request?.tools.find((item: Object): boolean => getString(item, 'name') === tool.item.toolName);
    return {
      id: 'tool-' + tool.id, sequence: group.sequence, turn: group.turn, step: tool.step,
      kind: tool.depth > 0 ? 'subtool' : 'tool', title: tool.item.toolName, started: tool.item.at,
      duration: tool.item.elapsedMs, content: tool.item.toolOutput || tool.error, reasoning: '',
      argumentsText: tool.item.toolArgs, depth: tool.depth, resultSequence: tool.resultSequence,
      schema: schema,
      failed: tool.item.toolState === 'failed' || tool.item.toolState === 'rejected' || tool.interrupted,
      revision: group.version
    };
  }
}
