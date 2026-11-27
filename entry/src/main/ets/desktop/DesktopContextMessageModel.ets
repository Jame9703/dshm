import { getArray, getField, getNumber, getRecord, getString } from 'connection';

export type DesktopContextForm = 'instructions' | 'catalog' | 'snapshot' | 'notice' | 'relay' | 'recall';

export interface DesktopContextToolMutations {
  added: string[];
  removed: string[];
}

export interface DesktopContextMessage {
  id: string;
  sequence: number;
  time: number;
  turn?: number;
  kind: 'context' | 'turn-trigger';
  sourceKind: string;
  source: Object | undefined;
  content: Object[];
  form?: DesktopContextForm;
  producerRole: 'inject' | 'recall';
  producerLabel: string;
  mutations?: DesktopContextToolMutations;
}

interface ContextInboxMessage {
  id: string;
  human: boolean;
}

interface ContextInboxSplice {
  target: 'next-turn' | 'next-step';
  start: number;
  removedCount: number;
  inserted: ContextInboxMessage[];
  cancelled: boolean;
}

interface ContextFact {
  sequence: number;
  type: string;
  turn?: number;
  step?: number;
  messageId?: string;
  row?: DesktopContextMessage;
  inbox?: ContextInboxSplice;
}

function distinctSourceFields(source: Object | undefined, array: string, field: string): string {
  const values = new Set<string>();
  for (const item of getArray(source, array) ?? []) {
    const label = getString(item, field);
    if (label) { values.add(label); }
  }
  return Array.from(values).join(', ');
}

function producerLabel(source: Object | undefined, kind: string): string {
  switch (kind) {
    case 'session-reference': return distinctSourceFields(source, 'references', 'label') || kind;
    case 'agent-instructions': return distinctSourceFields(source, 'changes', 'path') || kind;
    case 'skill-invocation': return getString(source, 'name') || kind;
    default: return kind;
  }
}

function contextForm(source?: Object): DesktopContextForm | undefined {
  const form = getString(source, 'form');
  switch (form) {
    case 'instructions':
    case 'catalog':
    case 'snapshot':
    case 'notice':
    case 'relay':
    case 'recall': return form;
    default: return undefined;
  }
}

function toolMutations(content: Object[]): DesktopContextToolMutations | undefined {
  if (content.length === 0) { return undefined; }
  const mutations: DesktopContextToolMutations = { added: [], removed: [] };
  for (const block of content) {
    const type = getString(block, 'type');
    const name = getString(block, 'toolName');
    if (!name || (type !== 'tool-addition' && type !== 'tool-removal')) { return undefined; }
    if (type === 'tool-addition') { mutations.added.push(name); }
    else { mutations.removed.push(name); }
  }
  return mutations;
}

function messageFact(event: Object | undefined, data: Object | undefined, type: string, sequence: number):
  ContextFact | undefined {
  const user = type === 'user/message';
  const surface = getField(event, 'surfaceOp');
  if (surface !== 'append' && (user || surface !== undefined)) { return undefined; }
  const message = user ? data : getRecord(data, 'message');
  const messageId = getString(message, 'id');
  const source = getRecord(message, 'source');
  const sourceKind = getString(source, 'kind') ?? '';
  const role = getString(message, 'role');
  const content = getArray(message, 'content');
  if (!messageId || content === undefined || (role !== undefined && role !== (user ? 'user' : 'developer'))) {
    return undefined;
  }
  if (user && (source === undefined || sourceKind === 'user' || sourceKind === 'compact-checkpoint')) {
    return undefined;
  }
  const row: DesktopContextMessage = {
    id: `${user ? 'context-user' : 'context-developer'}:${messageId}`,
    sequence: sequence, time: getNumber(event, 'time') ?? 0, turn: getNumber(data, 'turn'),
    kind: user && sourceKind === 'retry' && content.length === 0 ? 'turn-trigger' : 'context',
    sourceKind: sourceKind, source: source, content: content, form: contextForm(source),
    producerRole: sourceKind === 'session-reference' ? 'recall' : 'inject',
    producerLabel: producerLabel(source, sourceKind), mutations: toolMutations(content)
  };
  return { sequence: sequence, type: type, messageId: messageId, row: row };
}

function inboxSplice(data?: Object): ContextInboxSplice | undefined {
  const target = getString(data, 'target');
  const start = getNumber(data, 'start') ?? -1;
  const removedCount = getNumber(data, 'removedCount') ?? 0;
  const inserted = getArray(data, 'inserted');
  if ((target !== 'next-turn' && target !== 'next-step') || !Number.isSafeInteger(start) || start < 0 ||
      !Number.isSafeInteger(removedCount) || removedCount < 0 || inserted === undefined) { return undefined; }
  return {
    target: target, start: start, removedCount: removedCount, cancelled: getString(data, 'outcome') === 'canceled',
    inserted: inserted.map((item: Object): ContextInboxMessage => {
      return { id: getString(item, 'id') ?? '', human: getString(getRecord(item, 'source'), 'kind') === 'user' };
    })
  };
}

function projectFact(record: Object): ContextFact | undefined {
  const event = getRecord(record, 'event');
  const type = getString(event, 'type');
  if (type !== 'user/message' && type !== 'developer/message' && type !== 'agent/inbox/spliced' &&
      type !== 'turn/start' && type !== 'turn/end' && type !== 'step/start' && type !== 'step/end') {
    return undefined;
  }
  const sequence = getNumber(event, 'seq') ?? -1;
  if (!Number.isSafeInteger(sequence) || sequence < 0) { return undefined; }
  const data = getRecord(event, 'data');
  if (type === 'user/message' || type === 'developer/message') { return messageFact(event, data, type, sequence); }
  if (type === 'agent/inbox/spliced') {
    const inbox = inboxSplice(data);
    return inbox === undefined ? undefined : { sequence: sequence, type: type, inbox: inbox };
  }
  const turn = getNumber(data, 'turn');
  const step = getNumber(data, 'step');
  return turn === undefined ? undefined : { sequence: sequence, type: type, turn: turn, step: step };
}

class ContextInboxState {
  private readonly pending: ContextInboxMessage[] = [];
  readonly claimed: Set<string> = new Set<string>();
  claimSequence: number = -1;
  firstHuman: string = '';

  apply(change: ContextInboxSplice, sequence: number): void {
    const removed = this.pending.splice(change.start, change.removedCount, ...change.inserted);
    if (change.removedCount > 0 && !change.cancelled) {
      this.claimed.clear();
      for (const item of removed) {
        if (item.id) { this.claimed.add(item.id); }
      }
      this.claimSequence = sequence;
      this.firstHuman = removed.find((item: ContextInboxMessage): boolean => item.human)?.id ?? '';
    } else {
      for (const item of change.inserted) { this.claimed.delete(item.id); }
    }
  }
}

/** Inbox claims determine whether an injected message woke the turn. Replay prepended history when needed. */
export class DesktopContextMessageTimeline {
  private readonly facts: Map<number, ContextFact> = new Map<number, ContextFact>();
  private readonly visible: Map<string, DesktopContextMessage> = new Map<string, DesktopContextMessage>();
  private nextTurn: ContextInboxState = new ContextInboxState();
  private nextStep: ContextInboxState = new ContextInboxState();
  private currentTurn: number | undefined = undefined;
  private turnStart: number = -1;
  private currentStep: number = -1;
  private lastSequence: number = -1;
  private replayRequired: boolean = false;
  private dirty: boolean = false;
  private snapshot: DesktopContextMessage[] = [];

  clear(): void {
    this.facts.clear();
    this.resetProjection();
    if (this.snapshot.length > 0) { this.snapshot = []; }
    this.dirty = false;
    this.replayRequired = false;
  }

  observe(record: Object): void {
    const fact = projectFact(record);
    if (fact === undefined || this.facts.has(fact.sequence)) { return; }
    this.facts.set(fact.sequence, fact);
    if (fact.sequence < this.lastSequence) { this.replayRequired = true; }
    if (!this.replayRequired) { this.apply(fact); }
  }

  rows(): DesktopContextMessage[] {
    if (this.replayRequired) {
      this.resetProjection();
      const facts = Array.from(this.facts.values()).sort((a: ContextFact, b: ContextFact): number =>
        a.sequence - b.sequence);
      for (const fact of facts) { this.apply(fact); }
      this.replayRequired = false;
    }
    if (this.dirty) {
      this.snapshot = Array.from(this.visible.values()).sort((a: DesktopContextMessage, b: DesktopContextMessage):
        number => a.sequence - b.sequence);
      this.dirty = false;
    }
    return this.snapshot;
  }

  private resetProjection(): void {
    this.visible.clear();
    this.nextTurn = new ContextInboxState();
    this.nextStep = new ContextInboxState();
    this.currentTurn = undefined;
    this.turnStart = -1;
    this.currentStep = -1;
    this.lastSequence = -1;
  }

  private apply(fact: ContextFact): void {
    this.lastSequence = fact.sequence;
    if (fact.inbox !== undefined) {
      const inbox = fact.inbox.target === 'next-turn' ? this.nextTurn : this.nextStep;
      inbox.apply(fact.inbox, fact.sequence);
    } else if (fact.row !== undefined) {
      this.publishMessage(fact);
    } else if (fact.type === 'turn/start') {
      this.currentTurn = fact.turn;
      this.turnStart = fact.sequence;
      this.currentStep = -1;
    } else if (fact.type === 'step/start') {
      if (this.currentTurn !== fact.turn) { this.turnStart = -1; }
      this.currentTurn = fact.turn;
      this.currentStep = fact.step ?? -1;
    } else if (fact.type === 'step/end') {
      this.currentStep = -1;
    } else if (fact.type === 'turn/end' && this.currentTurn === fact.turn) {
      this.currentTurn = undefined;
      this.turnStart = -1;
      this.currentStep = -1;
    }
  }

  private publishMessage(fact: ContextFact): void {
    const row = fact.row;
    if (row === undefined || this.visible.has(row.id)) { return; }
    const messageId = fact.messageId ?? '';
    const claimedByNextTurn = this.nextTurn.claimed.has(messageId);
    const idleSteer = this.currentStep === 1 && this.turnStart >= 0 && this.nextStep.claimSequence > this.turnStart &&
      this.nextTurn.claimSequence < this.turnStart && !this.nextStep.firstHuman && this.nextStep.claimed.has(messageId);
    const waking = fact.type === 'user/message' && (claimedByNextTurn || idleSteer);
    const projected: DesktopContextMessage = {
      id: row.id, sequence: row.sequence, time: row.time, turn: row.turn ?? this.currentTurn,
      kind: waking ? 'turn-trigger' : row.kind, sourceKind: row.sourceKind, source: row.source, content: row.content,
      form: row.form, producerRole: row.producerRole, producerLabel: row.producerLabel, mutations: row.mutations
    };
    this.visible.set(row.id, projected);
    this.dirty = true;
  }
}
