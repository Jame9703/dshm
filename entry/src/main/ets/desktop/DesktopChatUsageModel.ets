import { SessionStatsInput } from 'appstate';
import { getArray, getField, getNumber, getRecord, getString } from 'connection';
import { desktopTraceUsage } from './DesktopTraceUsage';

export interface DesktopChatSessionUsage {
  uncachedInputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

export interface DesktopChatUsageRoute {
  provider: string;
  model: string;
}

export interface DesktopChatTurnUsage {
  uncachedInputTokens: number;
  outputTokens: number;
  totalTokens: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  reasoningTokens?: number;
  routes?: DesktopChatUsageRoute[];
}

export interface DesktopChatUsageSnapshot {
  activity: SessionStatsInput;
  usage?: DesktopChatSessionUsage;
}

interface UsageEvent {
  sequence: number;
  type: string;
  time?: number;
  step?: number;
  turn: number;
  append: boolean;
  body?: Object;
}

interface UsageWindow {
  events: Map<number, UsageEvent>;
  dirty: boolean;
  usage?: DesktopChatTurnUsage;
}

interface AttemptUsage {
  input: number;
  output: number;
  total: number;
  cacheRead?: number;
  cacheWrite?: number;
  reasoning?: number;
  route?: DesktopChatUsageRoute;
}

interface StepTiming {
  start?: number;
  first?: number;
}

const TURN_BOUNDARIES = ['turn/start', 'turn/end', 'step/start', 'step/end', 'assistant/attempt',
  'assistant/message', 'llm/retry', 'llm/retry-started'];

function count(value: number | undefined): number | undefined {
  return value !== undefined && Number.isSafeInteger(value) && value >= 0 ? value : undefined;
}

function duration(value: number | undefined): number | undefined {
  return value !== undefined && Number.isFinite(value) && value >= 0 ? value : undefined;
}

export function emptyDesktopChatUsage(): DesktopChatUsageSnapshot {
  return { activity: { turns: 0, steps: 0, llmMs: 0, toolMs: 0, ttftMs: 0, ttftSteps: 0, decodeMs: 0, decodeTokens: 0 } };
}

function readActivity(value: Object | undefined): SessionStatsInput | undefined {
  const turns = count(getNumber(value, 'turns'));
  const steps = count(getNumber(value, 'steps'));
  const llmMs = duration(getNumber(value, 'llmMs'));
  const toolMs = duration(getNumber(value, 'toolMs'));
  const ttftMs = duration(getNumber(value, 'ttftMs'));
  const ttftSteps = count(getNumber(value, 'ttftSteps'));
  const decodeMs = duration(getNumber(value, 'decodeMs'));
  const decodeTokens = duration(getNumber(value, 'decodeTokens'));
  if (turns === undefined || steps === undefined || llmMs === undefined || toolMs === undefined ||
    ttftMs === undefined || ttftSteps === undefined || decodeMs === undefined || decodeTokens === undefined) {
    return undefined;
  }
  return { turns: turns, steps: steps, llmMs: llmMs, toolMs: toolMs, ttftMs: ttftMs,
    ttftSteps: ttftSteps, decodeMs: decodeMs, decodeTokens: decodeTokens };
}

function readSessionUsage(value: Object | undefined): DesktopChatSessionUsage | undefined {
  const uncached = count(getNumber(value, 'uncachedInputTokens'));
  const output = count(getNumber(value, 'outputTokens'));
  const read = count(getNumber(value, 'cacheReadTokens'));
  const write = count(getNumber(value, 'cacheWriteTokens'));
  if (uncached === undefined || output === undefined || read === undefined || write === undefined ||
    !Number.isSafeInteger(uncached + read + write + output)) { return undefined; }
  return { uncachedInputTokens: uncached, outputTokens: output, cacheReadTokens: read, cacheWriteTokens: write };
}

function bySequence(left: UsageEvent, right: UsageEvent): number { return left.sequence - right.sequence; }

function lastStreamUsage(body: Object | undefined): Object | undefined {
  const packs = getArray(body, 'stream') ?? [];
  for (let i = packs.length - 1; i >= 0; i--) {
    const pack = packs[i];
    if (getString(pack, 'type') !== 'chunk') { continue; }
    const chunk = getRecord(pack, 'chunk');
    if (getString(chunk, 'type') === 'usage') { return getField(chunk, 'usage') ?? undefined; }
  }
  return undefined;
}

function firstTokenTime(body: Object | undefined): number | undefined {
  for (const pack of getArray(body, 'stream') ?? []) {
    const type = getString(pack, 'type');
    if (type === 'chunk') {
      const chunk = getRecord(pack, 'chunk');
      const kind = getString(chunk, 'type');
      const carriesToken = kind === 'tool-call-delta'
        ? (getString(chunk, 'name') !== undefined || !!getString(chunk, 'argumentsDelta'))
        : ((kind === 'text-delta' || kind === 'reasoning-delta') && !!getString(chunk, 'text'));
      const time = duration(getNumber(pack, 'time'));
      if (carriesToken && time !== undefined) { return time; }
    } else if (type === 'text-chunks' || type === 'reasoning-chunks' || type === 'tool-call-chunks') {
      let time = getNumber(pack, 'time0') ?? -1;
      if (time < 0 || !Number.isFinite(time)) { continue; }
      if (type === 'tool-call-chunks' && getString(pack, 'name') !== undefined) { return time; }
      const parts = getArray(pack, type === 'tool-call-chunks' ? 'args' : 'texts') ?? [];
      const offsets = getArray(pack, 'dt') ?? [];
      for (let i = 0; i < parts.length; i++) {
        if (i > 0) {
          const offset = offsets[i - 1];
          if (typeof offset !== 'number' || !Number.isFinite(offset)) { break; }
          time += offset;
        }
        if (typeof parts[i] === 'string' && parts[i] !== '') { return time; }
      }
    }
  }
  return undefined;
}

function normalizeAttempt(value: Object | undefined, route?: DesktopChatUsageRoute): AttemptUsage | undefined {
  const counts = desktopTraceUsage(value);
  const input = count(getNumber(counts, 'inputTokens'));
  const output = count(getNumber(counts, 'outputTokens'));
  const cacheRead = count(getNumber(counts, 'cacheReadTokens'));
  const cacheWrite = count(getNumber(counts, 'cacheWriteTokens'));
  const reasoning = count(getNumber(counts, 'reasoningTokens'));
  if (input === undefined || output === undefined ||
    (getField(value, 'cacheReadTokens') !== undefined && cacheRead === undefined) ||
    (getField(value, 'cacheWriteTokens') !== undefined && cacheWrite === undefined) ||
    (getField(value, 'reasoningTokens') !== undefined && (reasoning === undefined || reasoning > output))) {
    return undefined;
  }
  const knownPrompt = input + (cacheRead ?? 0) + (cacheWrite ?? 0);
  if (!Number.isSafeInteger(knownPrompt)) { return undefined; }
  let total = count(getNumber(value, 'totalTokens'));
  if (getField(value, 'totalTokens') !== undefined) {
    if (total === undefined || total - output < knownPrompt ||
      (cacheRead !== undefined && cacheWrite !== undefined && total - output !== knownPrompt)) { return undefined; }
  } else {
    if (cacheRead === undefined || cacheWrite === undefined || !Number.isSafeInteger(knownPrompt + output)) {
      return undefined;
    }
    total = knownPrompt + output;
  }
  return { input: input, output: output, total: total, cacheRead: cacheRead, cacheWrite: cacheWrite,
    reasoning: reasoning, route: route };
}

function routeOf(body: Object | undefined): DesktopChatUsageRoute | undefined {
  const source = getRecord(getRecord(body, 'message'), 'source');
  const provider = getString(source, 'provider') ?? '';
  const model = getString(source, 'model') ?? '';
  return provider && model ? { provider: provider, model: model } : undefined;
}

/** The disclosure is exact only when the full attempt lifecycle and accounting are known. */
function turnUsageOf(events: UsageEvent[]): DesktopChatTurnUsage | undefined {
  if (events.length < 2 || events[0].type !== 'turn/start' ||
    events[events.length - 1].type !== 'turn/end') { return undefined; }
  let phase = 'idle';
  let step: number | undefined;
  let hasUsage = false;
  let attributed = true;
  let read: number | undefined = 0;
  let write: number | undefined = 0;
  let reasoning: number | undefined = 0;
  let input = 0;
  let output = 0;
  let total = 0;
  const routes = new Map<string, DesktopChatUsageRoute>();

  const settle = (raw: Object | undefined, route?: DesktopChatUsageRoute): boolean => {
    const attempt = normalizeAttempt(raw, route);
    if (attempt === undefined) { return false; }
    hasUsage = true;
    input += attempt.input;
    output += attempt.output;
    total += attempt.total;
    read = read !== undefined && attempt.cacheRead !== undefined ? read + attempt.cacheRead : undefined;
    write = write !== undefined && attempt.cacheWrite !== undefined ? write + attempt.cacheWrite : undefined;
    reasoning = reasoning !== undefined && attempt.reasoning !== undefined ? reasoning + attempt.reasoning : undefined;
    if (attempt.route === undefined) { attributed = false; }
    else { routes.set(attempt.route.provider + '\u0000' + attempt.route.model, attempt.route); }
    return Number.isSafeInteger(input) && Number.isSafeInteger(output) && Number.isSafeInteger(total);
  };

  for (let i = 1; i < events.length - 1; i++) {
    const event = events[i];
    if (event.type === 'turn/start' || event.type === 'turn/end' || count(event.step) === undefined) { return undefined; }
    if (event.type === 'step/start') {
      if (phase !== 'idle') { return undefined; }
      phase = 'open';
      step = event.step;
      continue;
    }
    if (step !== event.step || phase === 'idle') { return undefined; }
    switch (event.type) {
      case 'assistant/attempt':
        if (phase !== 'open' || !settle(lastStreamUsage(event.body))) { return undefined; }
        phase = 'finished-attempt';
        break;
      case 'assistant/message': {
        const usage = getField(event.body, 'usage') ?? lastStreamUsage(event.body);
        if (phase !== 'open' || !settle(usage, routeOf(event.body))) { return undefined; }
        phase = 'message';
        break;
      }
      case 'llm/retry':
        if (phase !== 'finished-attempt') { return undefined; }
        phase = 'retry';
        break;
      case 'llm/retry-started':
        if (phase !== 'retry') { return undefined; }
        phase = 'open';
        break;
      case 'step/end':
        if (phase === 'open') { return undefined; }
        phase = 'idle';
        step = undefined;
        break;
    }
  }
  if (phase !== 'idle' || !hasUsage) { return undefined; }
  return { uncachedInputTokens: input, outputTokens: output, totalTokens: total,
    cacheReadTokens: read, cacheWriteTokens: write, reasoningTokens: reasoning,
    routes: attributed ? Array.from(routes.values()) : undefined };
}

/** Older hosts lack the durable statistics projection. In that case only show loaded observations. */
function deriveWindowActivity(events: UsageEvent[]): SessionStatsInput {
  const stats = emptyDesktopChatUsage().activity;
  const turns = new Set<number>();
  const timings = new Map<string, StepTiming>();
  const callTimes = new Map<string, number>();
  for (const event of events) {
    if (event.type === 'tool/call' || event.type === 'tool/result') {
      const source = getRecord(getRecord(event.body, 'message'), 'source');
      const id = event.type === 'tool/call' ? getString(event.body, 'callId') :
        getString(source, 'callId') ?? getString(event.body, 'callId');
      if (id === undefined || event.time === undefined) { continue; }
      if (event.type === 'tool/call') { callTimes.set(id, event.time); }
      else {
        const started = callTimes.get(id);
        if (started !== undefined && event.append) { stats.toolMs += Math.max(0, event.time - started); }
        callTimes.delete(id);
      }
      continue;
    }
    if (event.type === 'turn/end') {
      callTimes.clear();
      continue;
    }
    const key = event.turn + ':' + (event.step ?? -1);
    if (event.type === 'step/start') {
      timings.set(key, { start: event.time });
    } else if (event.type === 'assistant/attempt') {
      const time = timings.get(key);
      if (time !== undefined && time.first === undefined) { time.first = firstTokenTime(event.body); }
    } else if (event.type === 'assistant/message') {
      if (event.append) {
        if (event.turn >= 0) { turns.add(event.turn); }
        stats.steps++;
        const start = timings.get(key)?.start;
        const first = timings.get(key)?.first ?? firstTokenTime(event.body);
        if (start !== undefined && event.time !== undefined) { stats.llmMs += Math.max(0, event.time - start); }
        if (start !== undefined && first !== undefined) {
          stats.ttftMs += Math.max(0, first - start);
          stats.ttftSteps++;
        }
        const output = duration(getNumber(getRecord(event.body, 'usage'), 'outputTokens'));
        if (first !== undefined && event.time !== undefined && output !== undefined) {
          stats.decodeMs += Math.max(0, event.time - first);
          stats.decodeTokens += output;
        }
      }
      timings.delete(key);
    } else if (event.type === 'step/end') {
      timings.delete(key);
    }
  }
  stats.turns = turns.size;
  return stats;
}

export class DesktopChatUsageState {
  private readonly turns: Map<number, UsageWindow> = new Map();
  private readonly tools: Map<number, UsageEvent> = new Map();
  private projectedActivity?: SessionStatsInput;
  private projectedUsage?: DesktopChatSessionUsage;
  private activitySequence: number = -1;
  private usageSequence: number = -1;
  private cachedWindow?: SessionStatsInput;
  private cachedSnapshot: DesktopChatUsageSnapshot = emptyDesktopChatUsage();

  clear(): void {
    this.activitySequence = -1;
    this.usageSequence = -1;
    this.projectedActivity = undefined;
    this.projectedUsage = undefined;
    this.resetWindow();
    this.cachedSnapshot = emptyDesktopChatUsage();
  }

  resetWindow(): void {
    this.turns.clear();
    this.tools.clear();
    this.cachedWindow = undefined;
  }

  observe(record: Object): void {
    const event = getRecord(record, 'event');
    const type = getString(event, 'type') ?? '';
    const tool = type === 'tool/call' || type === 'tool/result';
    if (!tool && !TURN_BOUNDARIES.includes(type)) { return; }
    const sequence = count(getNumber(event, 'seq'));
    if (sequence === undefined) { return; }
    const body = getRecord(event, 'data');
    const turn = getNumber(body, 'turn') ?? -1;
    if (!tool && count(turn) === undefined) { return; }
    const op = getString(event, 'surfaceOp');
    const value: UsageEvent = { sequence: sequence, type: type,
      time: duration(getNumber(event, 'time')), step: getNumber(body, 'step'), turn: turn,
      append: op === 'append' || op === undefined, body: body };
    this.cachedWindow = undefined;
    if (tool) {
      this.tools.set(sequence, value);
    } else {
      let window = this.turns.get(turn);
      if (window === undefined) {
        window = { events: new Map<number, UsageEvent>(), dirty: true };
        this.turns.set(turn, window);
      }
      window.events.set(sequence, value);
      window.dirty = true;
    }
  }

  readProjection(values?: Object, sequence: number = -1): boolean {
    let changed = false;
    if (getField(values, 'sessionStats') !== undefined &&
      (this.activitySequence < 0 || sequence > this.activitySequence)) {
      this.activitySequence = sequence;
      this.projectedActivity = readActivity(getRecord(values, 'sessionStats'));
      changed = true;
    }
    if (getField(values, 'tokenUsage') !== undefined &&
      (this.usageSequence < 0 || sequence > this.usageSequence)) {
      this.usageSequence = sequence;
      this.projectedUsage = readSessionUsage(getRecord(values, 'tokenUsage'));
      changed = true;
    }
    return changed;
  }

  private windowActivity(): SessionStatsInput {
    if (this.cachedWindow === undefined) {
      const events = Array.from(this.tools.values());
      this.turns.forEach((turn: UsageWindow): void => {
        turn.events.forEach((event: UsageEvent): void => { events.push(event); });
      });
      events.sort(bySequence);
      this.cachedWindow = deriveWindowActivity(events);
    }
    return this.cachedWindow;
  }

  stats(): DesktopChatUsageSnapshot {
    const activity = this.projectedActivity ?? this.windowActivity();
    if (this.cachedSnapshot.activity !== activity || this.cachedSnapshot.usage !== this.projectedUsage) {
      this.cachedSnapshot = { activity: activity, usage: this.projectedUsage };
    }
    return this.cachedSnapshot;
  }

  turnUsage(turn: number): DesktopChatTurnUsage | undefined {
    const window = this.turns.get(turn);
    if (window === undefined) { return undefined; }
    if (window.dirty) {
      const events = Array.from(window.events.values());
      events.sort(bySequence);
      window.usage = turnUsageOf(events);
      window.dirty = false;
    }
    return window.usage;
  }
}
