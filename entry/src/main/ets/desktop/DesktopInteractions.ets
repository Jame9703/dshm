import { Connection, EVENTS_RESULT_ENDPOINT, getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';
import { RemoteEventFrameType, WATERFALL_APPROVAL, WATERFALL_QUESTION } from 'dshcompat';
import { DesktopSidebarPending } from './DesktopSidebarStatus';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopPlanTitle, DesktopPlanReview } from './DesktopPlan';
import type { DesktopQuestionDrafts, DesktopQuestionProgress } from './DesktopQuestionDrafts';

export interface DesktopQuestionOption {
  label: string;
  caption: string;
  recommended: boolean;
  detail: string;
}

export interface DesktopQuestion {
  id: string;
  prompt: string;
  detail: string;
  header: string;
  multi: boolean;
  custom: boolean;
  options: DesktopQuestionOption[];
}

export interface DesktopQuestionAnswer {
  id: string;
  selected: string[];
  custom?: string;
}

interface DesktopQuestionState {
  progress?: DesktopQuestionProgress;
  held: boolean;
  hidden: boolean;
}

interface DesktopContinuedAnswer {
  sending: boolean;
  seenInInbox: boolean;
  inboxSequence: number;
}

export type DesktopQuestionReceiptPhase = 'sending' | 'sent' | 'confirming' | 'resubmit';

interface DesktopQuestionReceipt {
  event: DesktopInteraction;
  phase: DesktopQuestionReceiptPhase;
  carrierEnded: boolean;
  claimEnded: boolean;
  releaseSender: () => void;
}

interface DesktopQuestionProjection {
  sequence: number;
  inboxSequence: number;
  continued: DesktopInteraction[];
  queued: Set<string>;
  active: Set<string>;
  settled: Set<string>;
  submissions: Map<string, DesktopContinuedAnswer>;
}

export interface DesktopInteraction {
  id: string;
  sessionId: string;
  callId: string;
  tool: string;
  reason: string;
  displayReason?: Object;
  approvalSubmitting?: boolean;
  kind: string;
  questions: DesktopQuestion[];
  continued: boolean;
  timed: boolean;
  planReview?: DesktopPlanReview;
  reviewHidden?: boolean;
  questionProgress?: DesktopQuestionProgress;
  questionHidden?: boolean;
  questionHeld?: boolean;
  questionReceipt?: DesktopQuestionReceiptPhase;
  waitDeadline?: number;
  waitPausedMs?: number;
}

const RECOMMENDED = new RegExp('\\s*(?:\\((?:recommended|推荐)\\)|（(?:recommended|推荐)）)\\s*$', 'i');

function planReviewOf(raw: Object, questions: DesktopQuestion[]): DesktopPlanReview | undefined {
  const entry = getArray(raw, 'questions')?.[0];
  const intent = getRecord(entry, 'intent');
  const question = questions[0];
  const markdown = getString(entry, 'detail');
  const approve = getString(intent, 'approve') ?? '';
  if (questions.length !== 1 || getArray(raw, 'questions')?.length !== 1 ||
    getString(intent, 'kind') !== 'plan-review' || markdown === undefined || question.multi ||
    question.options.length > 2 || !approve ||
    !question.options.some((option: DesktopQuestionOption): boolean => option.label === approve)) {
    return undefined;
  }
  return {
    document: { callId: getString(intent, 'callId') ?? '', title: desktopPlanTitle(markdown),
      markdown: markdown, sequence: -1 },
    questionId: question.id,
    approve: approve,
    summary: (markdown.trim().split('\n').slice(1).join('\n').trim()
      .split(new RegExp('\\r?\\n\\s*\\r?\\n'), 1)[0] ?? '').replace(new RegExp('\\s+', 'g'), ' ')
  };
}

function questionsOf(value: Object): DesktopQuestion[] {
  const result: DesktopQuestion[] = [];
  for (const item of getArray(value, 'questions') ?? []) {
    const id = getString(item, 'id') ?? '';
    const prompt = getString(item, 'question') ?? '';
    if (!id || !prompt) {
      continue;
    }
    const options: DesktopQuestionOption[] = [];
    for (const option of getArray(item, 'options') ?? []) {
      const label = getString(option, 'label') ?? '';
      if (label) {
        options.push({ label: label, caption: label.replace(RECOMMENDED, '') || label,
          recommended: RECOMMENDED.test(label), detail: getString(option, 'description') ?? '' });
      }
    }
    const intent = getRecord(item, 'intent');
    const display = getRecord(intent, 'display');
    const localizedPrompt = getRecord(display, 'question');
    const localizedDetail = getRecord(display, 'detail');
    result.push({
      id: id,
      prompt: getString(localizedPrompt, 'zh') ?? getString(localizedPrompt, 'en') ?? prompt,
      detail: getString(localizedDetail, 'zh') ?? getString(localizedDetail, 'en') ?? getString(item, 'detail') ?? '',
      header: getString(item, 'header') ?? '',
      options: options,
      multi: getBoolean(item, 'multiSelect') === true,
      custom: getString(intent, 'kind') !== 'plan-review'
    });
  }
  return result;
}

export class DesktopInteractions {
  private readonly connection: Connection;
  private readonly actions: DesktopHostActions;
  private readonly onChange: (items: DesktopInteraction[]) => void;
  private readonly events: Map<string, DesktopInteraction>;
  private readonly questionStates: Map<string, DesktopQuestionState>;
  private readonly questionProjections: Map<string, DesktopQuestionProjection>;
  private readonly questionReceipts: Map<string, DesktopQuestionReceipt>;
  private readonly retainedClaims: Map<string, () => void>;
  private readonly settling: Set<DesktopInteraction>;
  private readonly owner?: DesktopInteractions;
  private views?: Set<DesktopInteractions>;
  private drafts?: DesktopQuestionDrafts;
  private draftOrigin: string = '';
  private eventClientId: string = '';
  private locale: string = 'zh';
  private selected: string = '';
  private stopClaim?: () => void;
  private claimEvent: string = '';
  private claimDeadline: number = 0;
  private claimTimer: number = -1;
  private claimFocused: boolean = false;
  private claimPausedMs?: number;
  private questionFocus: string = '';
  private onSidebarPending?: (pending: Map<string, DesktopSidebarPending>) => void;
  private sidebarPending: Map<string, DesktopSidebarPending> = new Map<string, DesktopSidebarPending>();

  constructor(connection: Connection, actions: DesktopHostActions, onChange: (items: DesktopInteraction[]) => void,
    owner?: DesktopInteractions) {
    this.connection = connection;
    this.actions = actions;
    this.onChange = onChange;
    this.owner = owner;
    this.events = owner?.events ?? new Map<string, DesktopInteraction>();
    this.questionStates = owner?.questionStates ?? new Map<string, DesktopQuestionState>();
    this.questionProjections = owner?.questionProjections ?? new Map<string, DesktopQuestionProjection>();
    this.questionReceipts = owner?.questionReceipts ?? new Map<string, DesktopQuestionReceipt>();
    this.retainedClaims = owner?.retainedClaims ?? new Map<string, () => void>();
    this.settling = owner?.settling ?? new Set<DesktopInteraction>();
  }

  observeSidebarPending(listener: (pending: Map<string, DesktopSidebarPending>) => void): void {
    this.onSidebarPending = listener;
  }

  bindQuestionDrafts(drafts: DesktopQuestionDrafts, origin: string): void {
    this.drafts = drafts;
    this.draftOrigin = origin;
  }

  setLocale(locale: string): void {
    if (locale === this.locale) { return; }
    this.locale = locale;
    if (Array.from(this.events.values()).some((row: DesktopInteraction): boolean => row.displayReason !== undefined)) {
      this.publish();
    }
  }

  createView(onChange: (items: DesktopInteraction[]) => void): DesktopInteractions {
    const owner = this.owner ?? this;
    const view = new DesktopInteractions(this.connection, this.actions, onChange, owner);
    const views = owner.views ?? new Set<DesktopInteractions>();
    views.add(view);
    owner.views = views;
    return view;
  }

  closeView(): void {
    this.releaseClaim(true);
    this.questionFocus = '';
    this.selected = '';
    if (this.owner?.views?.delete(this)) { this.owner.publish(); }
  }

  select(sessionId: string): void {
    if (sessionId !== this.selected) {
      this.questionFocus = '';
      this.releaseClaim(true);
      this.selected = sessionId;
      this.publish();
    }
  }

  startEvents(clientId: string): void {
    if (this.eventClientId !== clientId) { this.resetEvents(); }
    this.eventClientId = clientId;
  }

  resetEvents(): void {
    this.eventClientId = '';
    this.questionFocus = '';
    this.views?.forEach((view: DesktopInteractions): void => { view.questionFocus = ''; });
    if (this.events.size === 0) { return; }
    this.questionReceipts.forEach((receipt: DesktopQuestionReceipt): void => {
      receipt.phase = 'resubmit';
      receipt.releaseSender();
    });
    this.events.clear();
    this.publish();
  }

  onEvent(frame: Object): void {
    if (!this.eventClientId) { return; }
    const type = getString(frame, 'type');
    const id = getString(frame, 'eventId') ?? '';
    if (!id) {
      return;
    }
    if (type === RemoteEventFrameType.CANCEL) {
      const row = this.events.get(id);
      const receipt = row === undefined ? undefined : this.pendingReceipt(row);
      if (receipt !== undefined) {
        receipt.carrierEnded = true;
        this.publish();
        return;
      }
      if (row?.kind === 'question' && !row.callId) {
        this.forgetQuestion(this.questionKey(row), false);
      }
      if (this.events.delete(id)) {
        this.publish();
      }
      return;
    }
    if (type !== RemoteEventFrameType.WATERFALL) {
      return;
    }
    if (this.events.has(id)) { return; }
    const name = getString(frame, 'event');
    const sessionId = getString(frame, 'agentId') ?? '';
    const request = getRecord(frame, 'request');
    if (!sessionId || request === undefined || (name !== WATERFALL_APPROVAL && name !== WATERFALL_QUESTION)) {
      this.send(id, 'next');
      return;
    }
    const approval = name === WATERFALL_APPROVAL;
    const questions: DesktopQuestion[] = approval ? [] : questionsOf(request);
    if (!approval && questions.length === 0) {
      this.send(id, 'next');
      return;
    }
    const wait = getRecord(request, 'wait');
    const displayReason = getRecord(request, 'displayReason');
    const row: DesktopInteraction = {
      id: id,
      sessionId: sessionId,
      callId: getString(wait, 'callId') ?? getString(request, 'callId') ?? '',
      kind: approval ? 'approval' : 'question',
      tool: getString(request, 'toolName') ?? '',
      reason: getString(request, 'reason') ?? '',
      displayReason: displayReason,
      questions: questions,
      continued: false,
      timed: getBoolean(wait, 'timed') === true,
      planReview: approval ? undefined : planReviewOf(request, questions)
    };
    const projection = this.questionProjections.get(sessionId);
    if (!approval && row.callId && (projection?.settled.has(row.callId) || projection?.queued.has(row.callId))) { return; }
    this.events.set(id, row);
    this.publish();
  }

  observeQuestions(sessionId: string, values: Object | undefined, sequence: number): void {
    if (sessionId !== this.selected) {
      return;
    }
    const projection = getRecord(values, 'userQuestions');
    const inbox = getField(values, 'inbox');
    if (projection === undefined && inbox === undefined) { return; }
    let state = this.questionProjections.get(sessionId);
    if (state === undefined) {
      state = { sequence: -1, inboxSequence: -1, continued: [], queued: new Set<string>(),
        active: new Set<string>(), settled: new Set<string>(),
        submissions: new Map<string, DesktopContinuedAnswer>() };
      this.questionProjections.set(sessionId, state);
    }
    const updateQuestions = projection !== undefined && sequence > state.sequence;
    const updateInbox = (inbox === null || getRecord(values, 'inbox') !== undefined) && sequence > state.inboxSequence;
    if (!updateQuestions && !updateInbox) { return; }
    if (updateQuestions) { this.readQuestionRows(sessionId, state, projection, sequence); }
    if (updateInbox) { this.readQuestionInbox(sessionId, state, inbox, sequence); }
    this.publish();
  }

  private readQuestionRows(sessionId: string, state: DesktopQuestionProjection, projection: Object | undefined,
    sequence: number): void {
    const rows: DesktopInteraction[] = [];
    const active = new Set<string>();
    state.settled = new Set<string>();
    for (const settled of getArray(projection, 'settled') ?? []) {
      const callId = getString(settled, 'callId') ?? '';
      if (callId) {
        state.settled.add(callId);
        this.finishQuestionReceipt(sessionId, callId);
        this.forgetQuestion(sessionId + '\u0000' + callId, true);
        state.submissions.delete(callId);
      }
    }
    for (const item of getArray(projection, 'active') ?? []) {
      const callId = getString(item, 'callId') ?? '';
      if (!callId) { continue; }
      active.add(callId);
      if (getString(item, 'state') !== 'continued') { continue; }
      const questions = questionsOf(item);
      if (questions.length > 0) {
        const receipt = this.questionReceipts.get(sessionId + '\u0000' + callId);
        if (receipt !== undefined && receipt.phase !== 'resubmit') {
          this.removeReceiptEvent(receipt);
          receipt.phase = 'resubmit';
          receipt.releaseSender();
        }
        rows.push({
          id: 'continued/' + callId, sessionId: sessionId, callId: callId, kind: 'question',
          tool: '', reason: '', questions: questions, continued: true, timed: false
        });
      }
    }
    state.active.forEach((callId: string): void => {
      if (!active.has(callId) && !state.settled.has(callId)) {
        this.finishQuestionReceipt(sessionId, callId);
        this.forgetQuestion(sessionId + '\u0000' + callId, true);
      }
    });
    state.active = active;
    state.sequence = sequence;
    state.continued = rows;
    state.submissions.forEach((_submission: DesktopContinuedAnswer, callId: string): void => {
      if (!rows.some((row: DesktopInteraction): boolean => row.callId === callId)) { state.submissions.delete(callId); }
    });
  }

  private readQuestionInbox(sessionId: string, state: DesktopQuestionProjection, inbox: Object | undefined,
    sequence: number): void {
    const queued = new Set<string>();
    for (const lane of ['next-step', 'next-turn']) {
      for (const message of getArray(inbox, lane) ?? []) {
        const source = getRecord(message, 'source');
        const callId = getString(source, 'callId');
        if (callId && getString(source, 'kind') === 'user-question-reply') {
          queued.add(callId);
          this.finishQuestionReceipt(sessionId, callId);
        }
      }
    }
    state.queued = queued;
    state.inboxSequence = sequence;
    state.submissions.forEach((submission: DesktopContinuedAnswer, callId: string): void => {
      if (queued.has(callId)) { submission.seenInInbox = true; }
      if (!submission.sending && (submission.seenInInbox || sequence > submission.inboxSequence)) {
        state.submissions.delete(callId);
      }
    });
  }

  private answerableQuestions(state: DesktopQuestionProjection | undefined): DesktopInteraction[] {
    if (state === undefined) { return []; }
    return state.continued.filter((row: DesktopInteraction): boolean =>
      !state.queued.has(row.callId) && state.submissions.get(row.callId)?.sending !== false);
  }

  async approve(id: string, allow: boolean): Promise<string> {
    const event = this.events.get(id);
    if (event?.kind !== 'approval' || event.sessionId !== this.selected) {
      return '这项审批已结束';
    }
    return this.settle(id, allow ? 'allowed-once' : 'rejected');
  }

  async approvePlanReview(id: string): Promise<string> {
    const row = this.events.get(id);
    const review = row?.planReview;
    if (review === undefined || row?.sessionId !== this.selected) {
      return '这项计划审阅已结束';
    }
    return this.answer(id, [{ id: review.questionId, selected: [review.approve] }]);
  }

  async dismissPlanReview(id: string): Promise<string> {
    const row = this.events.get(id);
    if (row === undefined || row.planReview === undefined || row.sessionId !== this.selected) {
      return '这项计划审阅已结束';
    }
    if (row.callId.length > 0) {
      row.reviewHidden = true;
      this.publish();
      return '';
    }
    return this.rejectQuestion(id, 'ASK_CANCELLED', 'the user cancelled ask_user_question');
  }

  reopenPlanReview(id: string): void {
    const row = this.events.get(id);
    if (row?.planReview !== undefined && row.sessionId === this.selected && row.reviewHidden) {
      row.reviewHidden = false;
      this.publish();
    }
  }

  private questionKey(row: DesktopInteraction): string {
    return row.sessionId + '\u0000' + (row.callId || row.id);
  }

  private pendingReceipt(row: DesktopInteraction): DesktopQuestionReceipt | undefined {
    if (row.kind !== 'question' || !row.callId || row.continued) { return undefined; }
    const receipt = this.questionReceipts.get(this.questionKey(row));
    return receipt?.event === row && receipt.phase !== 'resubmit' ? receipt : undefined;
  }

  private removeReceiptEvent(receipt: DesktopQuestionReceipt): void {
    if (this.events.get(receipt.event.id) === receipt.event) {
      this.events.delete(receipt.event.id);
    }
  }

  private finishQuestionReceipt(sessionId: string, callId: string): void {
    const key = sessionId + '\u0000' + callId;
    const receipt = this.questionReceipts.get(key);
    if (receipt !== undefined) {
      this.removeReceiptEvent(receipt);
      this.questionReceipts.delete(key);
      receipt.releaseSender();
    }
    this.events.forEach((row: DesktopInteraction, id: string): void => {
      if (row.kind === 'question' && row.sessionId === sessionId && row.callId === callId) { this.events.delete(id); }
    });
  }

  private readQuestionState(row: DesktopInteraction): DesktopQuestionState | undefined {
    const key = this.questionKey(row);
    const existing = this.questionStates.get(key);
    if (existing !== undefined || !row.callId) { return existing; }
    const owner = this.owner ?? this;
    const saved = owner.drafts?.get(owner.draftOrigin + '\u0000' + key);
    if (saved === undefined) { return undefined; }
    const state: DesktopQuestionState = { progress: saved.progress, held: saved.held, hidden: false };
    this.questionStates.set(key, state);
    return state;
  }

  private persistQuestion(row: DesktopInteraction, state: DesktopQuestionState): void {
    if (!row.callId) { return; }
    const owner = this.owner ?? this;
    owner.drafts?.put({ key: owner.draftOrigin + '\u0000' + this.questionKey(row),
      progress: state.progress, held: state.held });
  }

  private forgetQuestion(key: string, durable: boolean): void {
    this.questionStates.delete(key);
    const owner = this.owner ?? this;
    if (durable) { owner.drafts?.remove(owner.draftOrigin + '\u0000' + key); }
  }

  private questionRow(id: string): DesktopInteraction | undefined {
    const event = this.events.get(id) ?? this.answerableQuestions(this.questionProjections.get(this.selected))
      .find((row: DesktopInteraction): boolean => row.id === id);
    return event?.kind === 'question' && event.sessionId === this.selected ? event : undefined;
  }

  private questionState(row: DesktopInteraction): DesktopQuestionState {
    const existing = this.readQuestionState(row);
    if (existing !== undefined) { return existing; }
    const state: DesktopQuestionState = { held: false, hidden: false };
    this.questionStates.set(this.questionKey(row), state);
    return state;
  }

  saveQuestion(id: string, progress: DesktopQuestionProgress, engage: boolean): void {
    const row = this.questionRow(id);
    if (row === undefined || this.pendingReceipt(row) !== undefined) { return; }
    const state = this.questionState(row);
    state.progress = progress;
    const startedHold = engage && row.timed && !state.held;
    if (startedHold) { state.held = true; }
    this.persistQuestion(row, state);
    if (startedHold) { this.publish(); }
  }

  holdQuestion(id: string): void {
    const row = this.questionRow(id);
    if (row?.timed !== true) { return; }
    const state = this.questionState(row);
    if (state.held) { return; }
    state.held = true;
    this.persistQuestion(row, state);
    this.publish();
  }

  setQuestionFocus(id: string, focused: boolean): void {
    if (focused) {
      const row = this.events.get(id);
      if (id === this.questionFocus || row?.sessionId !== this.selected || !row.timed || !row.callId ||
        this.pendingReceipt(row) !== undefined) { return; }
      const state = this.readQuestionState(row);
      if (state?.held || state?.hidden) { return; }
      this.questionFocus = id;
    } else {
      if (this.questionFocus !== id) { return; }
      this.questionFocus = '';
    }
    this.publish();
  }

  async closeQuestion(id: string): Promise<string> {
    const row = this.questionRow(id);
    if (row === undefined) { return '这项提问已结束'; }
    if (this.pendingReceipt(row) !== undefined) { return '正在提交这项回答'; }
    if (row.callId) {
      this.questionState(row).hidden = true;
      if (this.questionFocus === id) { this.questionFocus = ''; }
      this.publish();
      return '';
    }
    return this.rejectQuestion(id, 'ASK_CANCELLED', 'the user cancelled ask_user_question', true);
  }

  reopenQuestion(id: string): void {
    const row = this.questionRow(id);
    if (row === undefined) { return; }
    this.questionState(row).hidden = false;
    this.publish();
  }

  private rejectQuestion(id: string, code: string, message: string, clearDraft: boolean = false): Promise<string> {
    const error: Record<string, Object> = { 'name': 'UserQuestionError', 'code': code, 'message': message };
    return this.settle(id, error, 'rejected', clearDraft);
  }

  async answer(id: string, answers: DesktopQuestionAnswer[]): Promise<string> {
    const event = this.questionRow(id);
    if (event === undefined) {
      return '这项提问已结束';
    }
    const encoded: Record<string, Object> = { 'answers': answers };
    if (!event.continued) {
      // Only timed ask_user_question calls publish a correlated host projection.
      if (event.timed && event.callId) { return this.sendNamedAnswer(event, encoded); }
      this.holdQuestion(id);
      return this.settle(id, encoded, 'result', !event.callId);
    }
    const state = this.questionProjections.get(event.sessionId);
    if (state === undefined || state.submissions.has(event.callId)) { return '正在提交这项回答'; }
    const submission: DesktopContinuedAnswer = { sending: true, seenInInbox: false, inboxSequence: state.inboxSequence };
    state.submissions.set(event.callId, submission);
    const rpc = await this.actions.call('userQuestions/answer', {
      'agentId': event.sessionId, 'callId': event.callId, 'answer': encoded
    });
    if (!rpc.ok || rpc.value !== true) {
      if (state.submissions.get(event.callId) === submission) { state.submissions.delete(event.callId); }
      return rpc.error?.message ?? '宿主未接受回答，提问可能已由其他客户端处理';
    }
    if (state.submissions.get(event.callId) === submission) {
      if (submission.seenInInbox) { state.submissions.delete(event.callId); }
      else {
        submission.sending = false;
        submission.inboxSequence = state.inboxSequence;
      }
    }
    this.publish();
    return '';
  }

  private async sendNamedAnswer(event: DesktopInteraction, encoded: Object): Promise<string> {
    if (this.pendingReceipt(event) !== undefined || this.settling.has(event)) { return '正在提交这项回答'; }
    const key = this.questionKey(event);
    let releaseSender: () => void = (): void => {};
    const projected = new Promise<string>((resolve: (value: string) => void): void => {
      releaseSender = (): void => { resolve(''); };
    });
    const receipt: DesktopQuestionReceipt = { event: event, phase: 'sending', carrierEnded: false, claimEnded: false,
      releaseSender: releaseSender };
    this.questionReceipts.set(key, receipt);
    this.holdQuestion(event.id);
    this.publish();
    const error = await Promise.race<Promise<string>[]>([this.send(event.id, 'result', encoded), projected]);
    if (this.questionReceipts.get(key) === receipt && receipt.phase === 'sending') {
      if (error && !receipt.carrierEnded) {
        this.questionReceipts.delete(key);
      } else {
        receipt.phase = error ? 'confirming' : 'sent';
      }
      this.publish();
    }
    return error;
  }

  private async settle(id: string, value: Object, kind: string = 'result', clearDraft: boolean = false): Promise<string> {
    const event = this.events.get(id);
    if (event === undefined) { return '这项请求已结束'; }
    if (this.settling.has(event)) { return '正在提交这项请求'; }
    this.settling.add(event);
    if (event.kind === 'approval') { this.publish(); }
    const error = await this.send(id, kind, value);
    this.settling.delete(event);
    if (error.length === 0 && this.events.get(id) === event && this.events.delete(id)) {
      if (clearDraft) { this.forgetQuestion(this.questionKey(event), false); }
      this.publish();
    } else if (event.kind === 'approval' && this.events.get(id) === event) {
      this.publish();
    }
    return error;
  }

  private async send(id: string, kind: string, value?: Object): Promise<string> {
    const clientId = (this.owner ?? this).eventClientId;
    if (!clientId) {
      return '请求连接已中断，请等待重连';
    }
    const outcome: Record<string, Object> = { 'kind': kind };
    if (value !== undefined) {
      outcome[kind === 'rejected' ? 'error' : 'value'] = value;
    }
    const payload: Record<string, Object> = { 'clientId': clientId, 'eventId': id, 'outcome': outcome };
    const result = await this.connection.call(EVENTS_RESULT_ENDPOINT, payload);
    return result.ok ? '' : result.error?.message ?? '宿主未确认本次操作';
  }

  private publish(): void {
    if (this.owner !== undefined) { this.owner.publish(); return; }
    const all = Array.from(this.events.values());
    this.retainedClaims.forEach((stop: () => void, id: string): void => {
      const row = this.events.get(id);
      const receipt = row === undefined ? undefined : this.pendingReceipt(row);
      if (receipt === undefined || receipt.carrierEnded || receipt.claimEnded) {
        this.retainedClaims.delete(id);
        stop();
      }
    });
    const claims = new Map<string, DesktopInteractions>();
    const focused = new Set<string>();
    this.reserveClaim(claims, focused);
    this.views?.forEach((view: DesktopInteractions): void => { view.reserveClaim(claims, focused); });
    this.syncClaim(all, claims, focused);
    this.views?.forEach((view: DesktopInteractions): void => { view.syncClaim(all, claims, focused); });
    this.publishView(all, claims);
    this.views?.forEach((view: DesktopInteractions): void => { view.publishView(all, claims); });
    this.publishSidebarPending(all);
  }

  private publishSidebarPending(items: DesktopInteraction[]): void {
    if (this.onSidebarPending === undefined) { return; }
    const pending = new Map<string, DesktopSidebarPending>();
    const record = (item: DesktopInteraction): void => {
      const kind = item.planReview !== undefined ? DesktopSidebarPending.PLAN_REVIEW :
        item.kind === 'question' ? DesktopSidebarPending.QUESTION : DesktopSidebarPending.APPROVAL;
      if (kind > (pending.get(item.sessionId) ?? 0)) { pending.set(item.sessionId, kind); }
    };
    items.forEach(record);
    this.questionProjections.forEach((state: DesktopQuestionProjection): void => {
      this.answerableQuestions(state).forEach(record);
    });
    if (this.sidebarPending.size === pending.size && Array.from(pending.keys()).every((id: string): boolean =>
      this.sidebarPending.get(id) === pending.get(id))) { return; }
    this.sidebarPending = pending;
    this.onSidebarPending(pending);
  }

  private reserveClaim(claims: Map<string, DesktopInteractions>, focused: Set<string>): void {
    if (this.questionFocus) { focused.add(this.questionFocus); }
    if (this.claimEvent && this.events.has(this.claimEvent)) { claims.set(this.claimEvent, this); }
  }

  private syncClaim(all: DesktopInteraction[], claims: Map<string, DesktopInteractions>, focused: Set<string>): void {
    const current = this.events.get(this.claimEvent);
    const claim = current !== undefined && this.canKeepClaim(current) ? current :
      all.find((row: DesktopInteraction): boolean =>
        row.sessionId === this.selected && row.timed && row.callId.length > 0 && !claims.has(row.id) &&
        !this.retainedClaims.has(row.id) && this.canKeepClaim(row));
    if ((claim?.id ?? '') !== this.claimEvent) {
      this.releaseClaim();
    }
    if (claim !== undefined) {
      claims.set(claim.id, this);
      const state = this.readQuestionState(claim);
      const shouldPause = !state?.held && !state?.hidden && focused.has(claim.id);
      if (state?.held) { this.clearCountdown(); }
      this.updateCountdownFocus(claim, shouldPause);
      if (!this.claimEvent) { this.attachClaim(claim); }
    }
  }

  private canKeepClaim(row: DesktopInteraction): boolean {
    const receipt = this.pendingReceipt(row);
    return receipt === undefined || (!receipt.carrierEnded && !receipt.claimEnded);
  }

  private publishView(all: DesktopInteraction[], claims: Map<string, DesktopInteractions>): void {
    const active = all.filter((row: DesktopInteraction): boolean => row.sessionId === this.selected);
    const continued = this.answerableQuestions(this.questionProjections.get(this.selected)).filter((row: DesktopInteraction): boolean =>
      !active.some((event: DesktopInteraction): boolean => event.callId === row.callId));
    this.onChange([...active, ...continued].map((row: DesktopInteraction): DesktopInteraction => {
      if (row.kind === 'approval') {
        const locale = (this.owner ?? this).locale;
        const base = locale.split('-')[0].toLowerCase();
        const reason = getString(row.displayReason, locale) ?? getString(row.displayReason, base) ??
          getString(row.displayReason, 'en') ?? row.reason;
        return { id: row.id, sessionId: row.sessionId, callId: row.callId, tool: row.tool, reason: reason,
          kind: 'approval', questions: [], continued: false, timed: false, approvalSubmitting: this.settling.has(row) };
      }
      if (row.kind !== 'question') { return row; }
      const state = this.readQuestionState(row);
      const claim = claims.get(row.id);
      const receipt = this.questionReceipts.get(this.questionKey(row));
      const phase = row.continued ? (receipt?.phase === 'resubmit' ? receipt.phase : undefined) :
        this.pendingReceipt(row)?.phase;
      return { id: row.id, sessionId: row.sessionId, callId: row.callId, tool: row.tool, reason: row.reason,
        kind: row.kind, questions: row.questions, continued: row.continued, timed: row.timed,
        planReview: row.planReview, reviewHidden: row.reviewHidden, questionReceipt: phase,
        questionProgress: state?.progress, questionHidden: state?.hidden, questionHeld: state?.held,
        waitDeadline: claim?.claimDeadline,
        waitPausedMs: claim?.claimPausedMs };
    }));
  }

  private clearCountdown(): void {
    clearTimeout(this.claimTimer);
    this.claimTimer = -1;
    this.claimDeadline = 0;
    this.claimPausedMs = undefined;
  }

  private releaseClaim(retainReceipt: boolean = false): void {
    this.clearCountdown();
    const stop = this.stopClaim;
    const id = this.claimEvent;
    const row = this.events.get(id);
    this.stopClaim = undefined;
    this.claimEvent = '';
    this.claimFocused = false;
    if (retainReceipt && stop !== undefined && row !== undefined && this.pendingReceipt(row) !== undefined &&
      this.canKeepClaim(row)) {
      this.retainedClaims.set(id, stop);
    } else {
      stop?.();
    }
  }

  private updateCountdownFocus(row: DesktopInteraction, focused: boolean): void {
    if (focused === this.claimFocused) { return; }
    this.claimFocused = focused;
    if (focused && this.claimDeadline > 0) {
      const remaining = Math.max(0, this.claimDeadline - Date.now());
      this.setCountdown(row, remaining);
    } else if (!focused && this.claimPausedMs !== undefined) {
      this.setCountdown(row, this.claimPausedMs);
    }
  }

  private setCountdown(row: DesktopInteraction, remaining: number): void {
    this.clearCountdown();
    if (this.claimFocused) {
      this.claimPausedMs = remaining;
      return;
    }
    this.claimDeadline = Date.now() + remaining;
    this.claimTimer = setTimeout((): void => {
      if (this.events.get(row.id) !== row || this.claimEvent !== row.id || this.claimFocused ||
        this.readQuestionState(row)?.held === true) { return; }
      this.rejectQuestion(row.id, 'ASK_TIMED_OUT', 'ask_user_question timed out before the user answered')
        .then((error: string): void => {
          if (error && this.claimEvent === row.id) {
            this.clearCountdown();
            this.stopClaim?.();
            this.stopClaim = undefined;
            this.publish();
          }
        });
    }, remaining);
  }

  private attachClaim(row: DesktopInteraction): void {
    this.claimEvent = row.id;
    this.stopClaim = this.actions.watch('userQuestions/attachWait', { 'agentId': row.sessionId, 'callId': row.callId }, {
      onItem: (frame: Object): void => {
        const remaining = getNumber(frame, 'remainingMs');
        if (this.claimEvent !== row.id || remaining === undefined ||
          this.readQuestionState(row)?.held === true) { return; }
        this.setCountdown(row, Math.max(0, remaining));
        this.publish();
      },
      onError: (): void => { this.endCountdown(row); },
      onEnd: (): void => { this.endCountdown(row); }
    });
  }

  private endCountdown(row: DesktopInteraction): void {
    const retained = this.retainedClaims.delete(row.id);
    if (this.claimEvent !== row.id && !retained) { return; }
    const receipt = this.pendingReceipt(row);
    if (receipt !== undefined) { receipt.claimEnded = true; }
    if (!retained && receipt === undefined && this.claimDeadline === 0 && this.claimPausedMs === undefined) { return; }
    if (this.claimEvent === row.id) { this.clearCountdown(); }
    this.publish();
  }
}
