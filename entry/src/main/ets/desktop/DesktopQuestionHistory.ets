import { getArray, getBoolean, getField, getNumber, getRecord, getString, parseJson } from 'connection';

export interface DesktopQuestionHistoryOption {
  label: string;
  description?: string;
}

export interface DesktopQuestionHistoryQuestion {
  id: string;
  question: string;
  header?: string;
  detail?: string;
  options?: DesktopQuestionHistoryOption[];
  multiSelect?: boolean;
}

export interface DesktopQuestionHistoryAnswer {
  id: string;
  selected: string[];
  custom?: string;
}

export type DesktopQuestionHistoryKind = 'timely' | 'late' | 'queued' | 'settled';

export interface DesktopQuestionHistoryRow {
  id: string;
  sessionId: string;
  callId: string;
  sequence: number;
  time: number;
  turn?: number;
  kind: DesktopQuestionHistoryKind;
  text: string;
  questions: DesktopQuestionHistoryQuestion[];
  answers: DesktopQuestionHistoryAnswer[];
}

interface QuestionCall {
  sequence: number;
  time: number;
  turn?: number;
  questions: DesktopQuestionHistoryQuestion[];
}

interface QuestionResult {
  sequence: number;
  time: number;
  turn?: number;
  text: string;
  answers?: DesktopQuestionHistoryAnswer[];
}

function optionsOf(question: Object): DesktopQuestionHistoryOption[] | undefined {
  const source = getArray(question, 'options');
  if (source === undefined) { return undefined; }
  const options: DesktopQuestionHistoryOption[] = [];
  for (const item of source) {
    const label = getString(item, 'label');
    if (label === undefined) { return undefined; }
    options.push({ label: label, description: getString(item, 'description') });
  }
  return options;
}

function questionsOf(data: Object | undefined, strict: boolean): DesktopQuestionHistoryQuestion[] | undefined {
  const questions = getArray(data, 'questions');
  if (questions === undefined || (strict && questions.length === 0)) { return undefined; }
  const result: DesktopQuestionHistoryQuestion[] = [];
  const ids = new Set<string>();
  for (const item of questions) {
    const id = getString(item, 'id');
    const text = getString(item, 'question');
    if (id === undefined || text === undefined) {
      if (strict) { return undefined; }
      continue;
    }
    if (strict && (ids.has(id) || getString(getRecord(item, 'intent'), 'kind') === 'plan-review')) { return undefined; }
    ids.add(id);
    result.push({ id: id, question: text, header: getString(item, 'header'), detail: getString(item, 'detail'),
      options: optionsOf(item), multiSelect: getBoolean(item, 'multi_select') ?? getBoolean(item, 'multiSelect') });
  }
  return result;
}

function answersOf(data: Object | undefined, strict: boolean): DesktopQuestionHistoryAnswer[] | undefined {
  const answers = getArray(data, 'answers');
  if (answers === undefined) { return undefined; }
  const result: DesktopQuestionHistoryAnswer[] = [];
  for (const item of answers) {
    const id = getString(item, 'id');
    const selected = getArray(item, 'selected');
    const rawCustom = getField(item, 'custom');
    const custom = getString(item, 'custom');
    if (id === undefined || selected === undefined || (strict && rawCustom !== undefined && custom === undefined)) {
      if (strict) { return undefined; }
      continue;
    }
    const labels: string[] = [];
    for (const choice of selected) {
      if (typeof choice === 'string') { labels.push(choice); }
      else if (strict) { return undefined; }
    }
    result.push({ id: id, selected: labels, custom: custom });
  }
  return result;
}

function paired(questions: DesktopQuestionHistoryQuestion[], answers: DesktopQuestionHistoryAnswer[]): boolean {
  if (questions.length === 0 || questions.length !== answers.length) { return false; }
  const unanswered = new Set<string>();
  questions.forEach((question: DesktopQuestionHistoryQuestion): void => { unanswered.add(question.id); });
  return unanswered.size === questions.length &&
    answers.every((answer: DesktopQuestionHistoryAnswer): boolean => unanswered.delete(answer.id));
}

function firstText(message?: Object): string {
  const text = (getArray(message, 'content') ?? []).find((block: Object): boolean => getString(block, 'type') === 'text');
  return getString(text, 'text') ?? '';
}

export function desktopQuestionHistoryAnswerValues(row: DesktopQuestionHistoryRow, id: string): string[] {
  const answer = row.answers.find((item: DesktopQuestionHistoryAnswer): boolean => item.id === id);
  if (answer === undefined) { return []; }
  const custom = answer.custom?.trim() ?? '';
  return custom ? [...answer.selected, custom] : answer.selected.slice();
}

export function desktopQuestionHistoryClipboardText(row: DesktopQuestionHistoryRow, answerLabel: string,
  skippedLabel: string): string {
  if (row.questions.length === 0) { return row.text; }
  return row.questions.map((item: DesktopQuestionHistoryQuestion): string => {
    const heading = item.header && item.header !== item.question ? `${item.header} — ${item.question}` : item.question;
    const values = desktopQuestionHistoryAnswerValues(row, item.id);
    return `${heading}\n${values.length === 0 ? skippedLabel : answerLabel + values.join(', ')}`;
  }).join('\n\n');
}

/** Each selected session has one independent raw transcript and two separately advancing projection faces. */
export class DesktopQuestionHistory {
  private sessionId: string = '';
  private readonly calls = new Map<string, QuestionCall>();
  private readonly results = new Map<string, QuestionResult>();
  private readonly timely = new Map<string, DesktopQuestionHistoryRow>();
  private readonly late = new Map<string, DesktopQuestionHistoryRow>();
  private readonly active = new Set<string>();
  private readonly projectedQuestions = new Map<string, DesktopQuestionHistoryQuestion[]>();
  private readonly settled = new Map<string, DesktopQuestionHistoryAnswer[]>();
  private readonly queued = new Map<string, Object>();
  private questionSequence: number = -1;
  private inboxSequence: number = -1;
  private snapshot: DesktopQuestionHistoryRow[] = [];
  private dirty: boolean = false;

  select(sessionId: string): void {
    if (sessionId === this.sessionId) { return; }
    this.clear();
    this.sessionId = sessionId;
  }

  resetRecords(): void {
    this.calls.clear();
    this.results.clear();
    this.timely.clear();
    this.late.clear();
    if (this.snapshot.length > 0) { this.snapshot = []; }
    this.dirty = false;
  }

  clear(): void {
    this.resetRecords();
    this.active.clear();
    this.projectedQuestions.clear();
    this.settled.clear();
    this.queued.clear();
    this.questionSequence = -1;
    this.inboxSequence = -1;
  }

  /** Only a claimed late reply returns true, including one whose legacy payload falls back to plain text. */
  observe(record: Object, sessionId?: string): boolean {
    if (!this.sessionId || (sessionId !== undefined && sessionId !== this.sessionId)) { return false; }
    const event = getRecord(record, 'event');
    const type = getString(event, 'type');
    if (type !== 'user/message' && type !== 'tool/call' && type !== 'tool/result' && type !== 'tool/ptc-dispatch' &&
        type !== 'tool/ptc-dispatch-start') { return false; }
    const sequence = getNumber(event, 'seq') ?? -1;
    if (!Number.isSafeInteger(sequence) || sequence < 0) { return false; }
    const data = getRecord(event, 'data');
    const append = getString(event, 'surfaceOp') === 'append';
    const time = getNumber(event, 'time') ?? 0;
    const turn = getNumber(data, 'turn');
    if (type === 'user/message') {
      return append && this.observeLate(data, sequence, time, turn);
    }
    if (type === 'tool/call' || type === 'tool/ptc-dispatch-start') {
      if (getString(data, 'name') !== 'ask_user_question') { return false; }
      const callId = getString(data, type === 'tool/call' ? 'callId' : 'subCallId');
      const args = getField(data, 'arguments');
      const questions = questionsOf(typeof args === 'string' ? parseJson(args) : args, true);
      const previous = callId === undefined ? undefined : this.calls.get(callId);
      if (callId && questions !== undefined && (previous === undefined || sequence < previous.sequence)) {
        this.calls.set(callId, { sequence: sequence, time: time, turn: turn, questions: questions });
        this.refreshTimely(callId);
      }
      return false;
    }
    if ((type === 'tool/result' && append) || (type === 'tool/ptc-dispatch' && getString(data, 'name') === 'ask_user_question')) {
      this.observeResult(type, data, sequence, time, turn);
    }
    return false;
  }

  observeProjection(values?: Object, sequence: number = -1, sessionId?: string): boolean {
    if (!this.sessionId || (sessionId !== undefined && sessionId !== this.sessionId)) { return false; }
    let accepted = false;
    const projection = getRecord(values, 'userQuestions');
    if (projection !== undefined && (this.questionSequence < 0 || sequence > this.questionSequence)) {
      accepted = true;
      this.questionSequence = sequence;
      this.active.clear();
      this.settled.clear();
      for (const item of getArray(projection, 'active') ?? []) {
        const callId = getString(item, 'callId');
        if (!callId) { continue; }
        this.active.add(callId);
        const questions = questionsOf(item, true);
        if (questions !== undefined) { this.projectedQuestions.set(callId, questions); }
      }
      for (const item of getArray(projection, 'settled') ?? []) {
        const callId = getString(item, 'callId');
        const answers = answersOf(item, true);
        if (callId && answers !== undefined) { this.settled.set(callId, answers); }
      }
      for (const id of this.projectedQuestions.keys()) {
        if (!this.active.has(id) && !this.settled.has(id)) { this.projectedQuestions.delete(id); }
      }
    }
    const inbox = getRecord(values, 'inbox');
    if (inbox !== undefined && (this.inboxSequence < 0 || sequence > this.inboxSequence)) {
      accepted = true;
      this.inboxSequence = sequence;
      this.queued.clear();
      for (const item of (getArray(inbox, 'next-step') ?? []).concat(getArray(inbox, 'next-turn') ?? [])) {
        const source = getRecord(item, 'source');
        const callId = getString(source, 'callId');
        if (getString(source, 'kind') === 'user-question-reply' && callId && !this.queued.has(callId)) {
          this.queued.set(callId, item);
        }
      }
    }
    return accepted;
  }

  rows(): DesktopQuestionHistoryRow[] {
    if (this.dirty) {
      const rows = Array.from(this.late.values());
      this.timely.forEach((row: DesktopQuestionHistoryRow, callId: string): void => {
        if (!this.late.has(callId)) { rows.push(row); }
      });
      this.snapshot = rows.sort((a: DesktopQuestionHistoryRow, b: DesktopQuestionHistoryRow): number => a.sequence - b.sequence);
      this.dirty = false;
    }
    return this.snapshot;
  }

  /** Return read-only tool-row data. Durable replies already have their own separately anchored bubble. */
  detail(callId: string): DesktopQuestionHistoryRow | undefined {
    const recorded = this.late.get(callId) ?? this.timely.get(callId);
    const call = this.calls.get(callId);
    const questions = call?.questions ?? this.projectedQuestions.get(callId) ?? recorded?.questions;
    const settled = this.settled.get(callId);
    if (settled !== undefined) {
      if (questions === undefined || !paired(questions, settled)) { return undefined; }
      return this.row(callId, 'settled', recorded?.sequence ?? call?.sequence ?? -1, recorded?.time ?? call?.time ?? 0,
        recorded?.turn ?? call?.turn, recorded?.text ?? '', questions, settled);
    }
    const queued = this.queued.get(callId);
    if (recorded !== undefined || !this.active.has(callId) || queued === undefined) { return undefined; }
    const head = getArray(queued, 'content')?.[0];
    const text = getString(head, 'type') === 'text' ? getString(head, 'text') ?? '' : '';
    const content = parseJson(text);
    if (getString(content, 'kind') !== 'answer_to_pending_question' || getString(content, 'callId') !== callId) {
      return undefined;
    }
    const heard = questions ?? questionsOf(content, true);
    const answers = answersOf(content, true);
    if (heard === undefined || answers === undefined || !paired(heard, answers)) { return undefined; }
    return this.row(callId, 'queued', call?.sequence ?? -1, call?.time ?? 0, call?.turn, text, heard, answers);
  }

  private observeLate(data: Object | undefined, sequence: number, time: number, turn?: number): boolean {
    const source = getRecord(data, 'source');
    const callId = getString(source, 'callId');
    if (!callId || getString(source, 'kind') !== 'user-question-reply' || getString(source, 'outcome') !== 'answered') {
      return false;
    }
    const existing = this.late.get(callId);
    if (existing !== undefined && existing.sequence <= sequence) { return true; }
    const text = firstText(data);
    const body = parseJson(text);
    const questions = questionsOf(body, false);
    const answers = questions === undefined ? [] : answersOf(body, false) ?? [];
    this.late.set(callId, this.row(callId, 'late', sequence, time, turn, text, questions ?? [], answers));
    this.dirty = true;
    return true;
  }

  private observeResult(type: string, data: Object | undefined, sequence: number, time: number, turn?: number): void {
    const native = type === 'tool/result';
    const result = native ? getRecord(data, 'message') : data;
    const id = getString(native ? result : data, native ? 'toolCallId' : 'subCallId');
    const sourceId = native ? getString(getRecord(result, 'source'), 'callId') : undefined;
    if (id && sourceId && id !== sourceId) { return; }
    const callId = sourceId || id;
    if (!callId || (this.results.get(callId)?.sequence ?? -1) >= sequence) { return; }
    const blocks = getArray(result, 'content');
    const block = blocks !== undefined && blocks.length === 1 ? blocks[0] : undefined;
    const text = getString(block, 'type') === 'text' ? getString(block, 'text') ?? '' : '';
    const body = getBoolean(result, 'isError') !== true && text.trimStart().startsWith('{') ? parseJson(text) : undefined;
    const answers = body !== undefined && getBoolean(body, 'pending') !== true ? answersOf(body, true) : undefined;
    if (answers === undefined && !this.calls.has(callId) && !this.results.has(callId)) { return; }
    this.results.set(callId, { sequence: sequence, time: time, turn: turn, text: text, answers: answers });
    this.refreshTimely(callId);
  }

  private refreshTimely(callId: string): void {
    const call = this.calls.get(callId);
    const result = this.results.get(callId);
    if (call === undefined || result?.answers === undefined || !paired(call.questions, result.answers)) {
      if (this.timely.delete(callId)) { this.dirty = true; }
      return;
    }
    this.timely.set(callId, this.row(callId, 'timely', result.sequence, result.time, result.turn ?? call.turn,
      result.text, call.questions, result.answers));
    this.dirty = true;
  }

  private row(callId: string, kind: DesktopQuestionHistoryKind, sequence: number, time: number, turn: number | undefined,
    text: string, questions: DesktopQuestionHistoryQuestion[], answers: DesktopQuestionHistoryAnswer[]): DesktopQuestionHistoryRow {
    return { id: `question-history:${this.sessionId}:${callId}`, sessionId: this.sessionId, callId: callId,
      sequence: sequence, time: time, turn: turn, kind: kind, text: text, questions: questions, answers: answers };
  }
}
