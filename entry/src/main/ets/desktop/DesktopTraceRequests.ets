import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';

export interface DesktopTraceRequest {
  sequence: number;
  number: number;
  turn: number;
  step: number;
  started: number;
  firstToken: number;
  completed: number;
  status: string;
  provider: string;
  model: string;
  options?: Object;
  defaults?: Object;
  tools: Object[];
  usage?: Object;
  assistant?: string;
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

  observe(type: string, sequence: number, time: number, turn: number, step: number, data?: Object): void {
    switch (type) {
      case 'step/start': {
        this.end('interrupted', sequence);
        const row: DesktopTraceRequest = {
          sequence: sequence, number: this.steps.size + 1, turn: turn, step: step, started: time,
          firstToken: 0, completed: 0, status: 'running', provider: '', model: '', tools: [],
          toolCalls: 0, subCalls: 0, revision: sequence
        };
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
        const row = this.steps.get(desktopTraceStepKey(turn, step));
        if (row === undefined) { return; }
        const source = getRecord(getRecord(data, 'message'), 'source');
        row.provider = getString(source, 'provider') || row.provider;
        row.model = getString(source, 'model') || row.model;
        row.usage = getField(data, 'usage');
        const token = firstTokenTime(data);
        row.firstToken = token >= row.started && token <= time ? token : 0;
        row.completed = time >= row.started ? time : 0;
        row.assistant = 'event-' + sequence;
        row.status = getBoolean(data, 'interrupted') === true ? 'interrupted' : 'completed';
        row.revision = sequence;
        return;
      }
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
