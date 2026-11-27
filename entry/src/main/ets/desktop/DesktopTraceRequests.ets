import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';
import { desktopTraceAddUsage, desktopTraceUsage } from './DesktopTraceUsage';

export interface DesktopTraceRequest {
  sequence: number;
  number: number;
  turn: number;
  step: number;
  purpose: string;
  started: number;
  firstToken: number;
  completed: number;
  status: string;
  provider: string;
  model: string;
  options?: Object;
  defaults?: Object;
  tools: Object[];
  usage?: Record<string, number>;
  cumulativeUsage?: Record<string, number>;
  result?: string;
  problem?: string;
  retry?: Object;
  toolCalls: number;
  subCalls: number;
  revision: number;
}

export function desktopTraceStepKey(turn: number, step: number): string { return turn + ':' + step; }

function firstTokenTime(message?: Object): number {
  for (const pack of getArray(message, 'stream') ?? []) {
    const type = getString(pack, 'type');
    if (type === 'chunk') {
      const chunk = getRecord(pack, 'chunk');
      const kind = getString(chunk, 'type');
      const token = kind === 'tool-call-delta'
        ? !!(getString(chunk, 'name') || getString(chunk, 'argumentsDelta'))
        : (kind === 'text-delta' || kind === 'reasoning-delta') && !!getString(chunk, 'text');
      if (token) { return getNumber(pack, 'time') ?? 0; }
    } else if (type === 'tool-call-chunks' || type === 'text-chunks' || type === 'reasoning-chunks') {
      let time = getNumber(pack, 'time0') ?? 0;
      if (type === 'tool-call-chunks' && getString(pack, 'name')) { return time; }
      const items = getArray(pack, type === 'tool-call-chunks' ? 'args' : 'texts') ?? [];
      const offsets = getArray(pack, 'dt') ?? [];
      for (let i = 0; i < items.length; i++) {
        const offset = offsets[i - 1];
        if (typeof offset === 'number') { time += offset; }
        if (typeof items[i] === 'string' && items[i] !== '') { return time; }
      }
    }
  }
  return 0;
}

/** Reads one ordered window of durable step, header and Assistant events. */
export class DesktopTraceRequests {
  readonly steps: Map<string, DesktopTraceRequest> = new Map();
  private header?: Object;
  private route?: Object;
  private active?: DesktopTraceRequest;
  private readonly compactions: Map<string, DesktopTraceRequest> = new Map();

  private newRequest(sequence: number, time: number, turn: number, step: number, purpose: string): DesktopTraceRequest {
    return {
      sequence: sequence, number: 0, turn: turn, step: step, purpose: purpose, started: time,
      firstToken: 0, completed: 0, status: 'running', provider: '', model: '', tools: [],
      toolCalls: 0, subCalls: 0, revision: sequence
    };
  }

  observe(type: string, sequence: number, time: number, turn: number, step: number, data?: Object): void {
    switch (type) {
      case 'step/start': {
        this.end('interrupted', sequence);
        const row = this.newRequest(sequence, time, turn, step, 'assistant');
        this.configure(row);
        this.active = row;
        this.steps.set(desktopTraceStepKey(turn, step), row);
        return;
      }
      case 'request/header':
        this.header = getRecord(data, 'header');
        if (this.active !== undefined) { this.configure(this.active); this.active.revision = sequence; }
        return;
      case 'request/context':
        this.route = data;
        if (this.active !== undefined) { this.configure(this.active); this.active.revision = sequence; }
        return;
      case 'assistant/message': {
        if (turn <= 0 || step <= 0) { return; }
        const key = desktopTraceStepKey(turn, step);
        let row = this.steps.get(key);
        if (row === undefined) {
          row = this.newRequest(sequence, 0, turn, step, 'assistant');
          this.configure(row);
          this.steps.set(key, row);
        }
        const source = getRecord(getRecord(data, 'message'), 'source');
        row.provider = getString(source, 'provider') || row.provider;
        row.model = getString(source, 'model') || row.model;
        row.usage = desktopTraceUsage(getField(data, 'usage'));
        const token = firstTokenTime(data);
        row.firstToken = row.started > 0 && token >= row.started && token <= time ? token : 0;
        row.completed = time >= row.started ? time : 0;
        row.result = 'event-' + sequence;
        row.status = getBoolean(data, 'interrupted') === true ? 'interrupted' : 'completed';
        row.revision = sequence;
        return;
      }
      case 'compaction/start':
      case 'compaction/summary':
      case 'compaction/end':
        this.compaction(type, sequence, time, turn, data);
        return;
      case 'llm/retry': {
        const row = this.steps.get(desktopTraceStepKey(turn, step));
        if (row !== undefined) { row.retry = data; row.revision = sequence; }
        return;
      }
      case 'step/end':
        if (this.active?.turn === turn && this.active?.step === step) { this.end('failed', sequence); }
        return;
      case 'turn/end':
        this.end(getString(data, 'reason') === 'failed' ? 'failed' : 'interrupted', sequence);
        return;
      case 'session/end-seed':
        this.end('interrupted', sequence);
        return;
    }
  }

  private compaction(type: string, sequence: number, time: number, turn: number, data?: Object): void {
    const id = getString(data, 'compactionId');
    if (!id) { return; }
    if (type === 'compaction/start') {
      this.compactions.set(id, this.newRequest(sequence, time, turn, 0, 'compaction'));
      return;
    }
    let row = this.compactions.get(id);
    if (type === 'compaction/summary') {
      if (row === undefined) {
        row = this.newRequest(sequence, 0, turn, 0, 'compaction');
        this.compactions.set(id, row);
      }
      row.provider = getString(data, 'provider') ?? '';
      row.model = getString(data, 'model') ?? '';
      const options: Record<string, Object> = { 'provider': row.provider, 'model': row.model };
      const max = getNumber(data, 'maxTokens');
      if (max !== undefined) { options['maxTokens'] = max; }
      row.options = options;
      row.result = 'event-' + sequence;
      row.usage = desktopTraceUsage(getField(data, 'usage'));
      row.revision = sequence;
    } else if (row !== undefined) {
      row.completed = time;
      row.problem = getString(data, 'error');
      row.status = row.problem ? 'failed' : 'completed';
      row.revision = sequence;
    }
  }

  ordered(): DesktopTraceRequest[] {
    const rows = Array.from(this.steps.values()).concat(Array.from(this.compactions.values()));
    rows.sort((a: DesktopTraceRequest, b: DesktopTraceRequest): number => a.sequence - b.sequence);
    let cumulative: Record<string, number> | undefined;
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      cumulative = desktopTraceAddUsage(cumulative, row.usage);
      row.number = i + 1;
      row.cumulativeUsage = cumulative;
    }
    return rows;
  }

  private configure(row: DesktopTraceRequest): void {
    row.options = getRecord(this.header, 'config');
    row.defaults = getRecord(this.header, 'adapterDefaults');
    row.tools = getArray(this.header, 'tools') ?? [];
    row.provider = getString(this.route, 'provider') || getString(row.options, 'provider') || '';
    row.model = getString(this.route, 'model') || getString(row.options, 'model') || '';
  }

  private end(status: string, sequence: number): void {
    if (this.active?.status === 'running') {
      this.active.status = status;
      this.active.revision = sequence;
    }
    this.active = undefined;
  }
}
