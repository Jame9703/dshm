import { Connection, EVENTS_RESULT_ENDPOINT, getArray, getBoolean, getNumber, getRecord, getString } from 'connection';
import { RemoteEventFrameType, WATERFALL_APPROVAL, WATERFALL_QUESTION } from 'dshcompat';
import { DesktopSidebarPending } from './DesktopSidebarStatus';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopPlanTitle, DesktopPlanReview } from './DesktopPlan';

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

export interface DesktopQuestionDraft {
  id: string;
  selected: string[];
  custom: string;
  skipped: boolean;
}

export interface DesktopQuestionProgress {
  index: number;
  drafts: DesktopQuestionDraft[];
}

interface DesktopQuestionState {
  progress?: DesktopQuestionProgress;
  held: boolean;
  hidden: boolean;
}

export interface DesktopInteraction {
  id: string;
  sessionId: string;
  callId: string;
  tool: string;
  reason: string;
  kind: string;
  questions: DesktopQuestion[];
  continued: boolean;
  timed: boolean;
  planReview?: DesktopPlanReview;
  reviewHidden?: boolean;
  questionProgress?: DesktopQuestionProgress;
  questionHidden?: boolean;
  questionHeld?: boolean;
  waitDeadline?: number;
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
  private readonly owner?: DesktopInteractions;
  private views?: Set<DesktopInteractions>;
  private continued: DesktopInteraction[] = [];
  private selected: string = '';
  private stopClaim?: () => void;
  private claimEvent: string = '';
  private claimDeadline: number = 0;
  private claimTimer: number = -1;
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
  }

  observeSidebarPending(listener: (pending: Map<string, DesktopSidebarPending>) => void): void {
    this.onSidebarPending = listener;
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
    this.releaseClaim();
    this.claimEvent = '';
    this.selected = '';
    this.continued = [];
    if (this.owner?.views?.delete(this)) { this.owner.publish(); }
  }

  select(sessionId: string): void {
    if (sessionId !== this.selected) {
      this.selected = sessionId;
      this.continued = [];
      this.publish();
    }
  }

  resetEvents(): void {
    this.events.clear();
    this.publish();
  }

  onEvent(frame: Object): void {
    const type = getString(frame, 'type');
    const id = getString(frame, 'eventId') ?? '';
    if (!id) {
      return;
    }
    if (type === RemoteEventFrameType.CANCEL) {
      const row = this.events.get(id);
      if (row?.kind === 'question' && (!row.timed || !row.callId)) {
        this.questionStates.delete(this.questionKey(row));
      }
      if (this.events.delete(id)) {
        this.publish();
      }
      return;
    }
    if (type !== RemoteEventFrameType.WATERFALL) {
      return;
    }
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
      reason: getString(displayReason, 'zh') ?? getString(displayReason, 'en') ?? getString(request, 'reason') ?? '',
      questions: questions,
      continued: false,
      timed: getBoolean(wait, 'timed') === true,
      planReview: approval ? undefined : planReviewOf(request, questions)
    };
    this.events.set(id, row);
    this.publish();
  }

  observeQuestions(sessionId: string, projection?: Object): void {
    if (sessionId !== this.selected) {
      return;
    }
    const rows: DesktopInteraction[] = [];
    for (const settled of getArray(projection, 'settled') ?? []) {
      const callId = getString(settled, 'callId') ?? '';
      if (callId) { this.questionStates.delete(sessionId + '\u0000' + callId); }
    }
    for (const item of getArray(projection, 'active') ?? []) {
      const callId = getString(item, 'callId') ?? '';
      if (!callId || getString(item, 'state') !== 'continued') {
        continue;
      }
      const questions = questionsOf(item);
      if (questions.length > 0) {
        rows.push({
          id: 'continued/' + callId, sessionId: sessionId, callId: callId, kind: 'question',
          tool: '', reason: '', questions: questions, continued: true, timed: false
        });
      }
    }
    this.continued = rows;
    this.publish();
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

  private questionRow(id: string): DesktopInteraction | undefined {
    const event = this.events.get(id) ?? this.continued.find((row: DesktopInteraction): boolean => row.id === id);
    return event?.kind === 'question' && event.sessionId === this.selected ? event : undefined;
  }

  private questionState(row: DesktopInteraction): DesktopQuestionState {
    const key = this.questionKey(row);
    const existing = this.questionStates.get(key);
    if (existing !== undefined) { return existing; }
    const state: DesktopQuestionState = { held: false, hidden: false };
    this.questionStates.set(key, state);
    return state;
  }

  saveQuestion(id: string, progress: DesktopQuestionProgress, engage: boolean): void {
    const row = this.questionRow(id);
    if (row === undefined) { return; }
    this.questionState(row).progress = progress;
    if (engage) { this.holdQuestion(id); }
  }

  holdQuestion(id: string): void {
    const row = this.questionRow(id);
    if (row?.timed !== true) { return; }
    const state = this.questionState(row);
    if (state.held) { return; }
    state.held = true;
    this.publish();
  }

  async closeQuestion(id: string): Promise<string> {
    const row = this.questionRow(id);
    if (row === undefined) { return '这项提问已结束'; }
    if (row.callId) {
      this.questionState(row).hidden = true;
      this.publish();
      return '';
    }
    const error = await this.rejectQuestion(id, 'ASK_CANCELLED', 'the user cancelled ask_user_question');
    if (!error) { this.questionStates.delete(this.questionKey(row)); }
    return error;
  }

  reopenQuestion(id: string): void {
    const row = this.questionRow(id);
    if (row === undefined) { return; }
    this.questionState(row).hidden = false;
    this.publish();
  }

  private rejectQuestion(id: string, code: string, message: string): Promise<string> {
    const error: Record<string, Object> = { 'name': 'UserQuestionError', 'code': code, 'message': message };
    return this.settle(id, error, 'rejected');
  }

  async answer(id: string, answers: DesktopQuestionAnswer[]): Promise<string> {
    const event = this.questionRow(id);
    if (event === undefined) {
      return '这项提问已结束';
    }
    const encoded: Record<string, Object> = { 'answers': answers };
    if (!event.continued) {
      this.holdQuestion(id);
      const error = await this.settle(id, encoded);
      if (!error) { this.questionStates.delete(this.questionKey(event)); }
      return error;
    }
    const rpc = await this.actions.call('userQuestions/answer', {
      'agentId': event.sessionId, 'callId': event.callId, 'answer': encoded
    });
    if (!rpc.ok || rpc.value !== true) {
      return rpc.error?.message ?? '宿主未接受回答，提问可能已由其他客户端处理';
    }
    this.continued = this.continued.filter((row: DesktopInteraction): boolean => row.id !== id);
    this.questionStates.delete(this.questionKey(event));
    this.publish();
    return '';
  }

  private async settle(id: string, value: Object, kind: string = 'result'): Promise<string> {
    const error = await this.send(id, kind, value);
    if (error.length === 0 && this.events.delete(id)) {
      this.publish();
    }
    return error;
  }

  private async send(id: string, kind: string, value?: Object): Promise<string> {
    const clientId = this.connection.getHostFactsClientId() ?? '';
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
    const claimed = new Set<string>();
    this.publishView(all, claimed);
    this.views?.forEach((view: DesktopInteractions): void => { view.publishView(all, claimed); });
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
    this.continued.forEach(record);
    this.views?.forEach((view: DesktopInteractions): void => { view.continued.forEach(record); });
    if (this.sidebarPending.size === pending.size && Array.from(pending.keys()).every((id: string): boolean =>
      this.sidebarPending.get(id) === pending.get(id))) { return; }
    this.sidebarPending = pending;
    this.onSidebarPending(pending);
  }

  private publishView(all: DesktopInteraction[], claimed: Set<string>): void {
    const claim = all.find((row: DesktopInteraction): boolean =>
      row.sessionId === this.selected && row.timed && row.callId.length > 0 && !claimed.has(row.id));
    if (claim !== undefined) { claimed.add(claim.id); }
    if ((claim?.id ?? '') !== this.claimEvent) {
      this.releaseClaim();
      if (claim !== undefined) { this.attachClaim(claim); }
    }
    if (claim !== undefined && this.questionStates.get(this.questionKey(claim))?.held === true) {
      this.clearCountdown();
    }
    const active = all.filter((row: DesktopInteraction): boolean => row.sessionId === this.selected);
    const continued = this.continued.filter((row: DesktopInteraction): boolean =>
      !active.some((event: DesktopInteraction): boolean => event.callId === row.callId));
    this.onChange([...active, ...continued].map((row: DesktopInteraction): DesktopInteraction => {
      if (row.kind !== 'question' || row.planReview !== undefined) { return row; }
      const state = this.questionStates.get(this.questionKey(row));
      return { id: row.id, sessionId: row.sessionId, callId: row.callId, tool: row.tool, reason: row.reason,
        kind: row.kind, questions: row.questions, continued: row.continued, timed: row.timed,
        questionProgress: state?.progress, questionHidden: state?.hidden, questionHeld: state?.held,
        waitDeadline: row.id === this.claimEvent ? this.claimDeadline : undefined };
    }));
  }

  private clearCountdown(): void {
    clearTimeout(this.claimTimer);
    this.claimTimer = -1;
    this.claimDeadline = 0;
  }

  private releaseClaim(): void {
    this.clearCountdown();
    const stop = this.stopClaim;
    this.stopClaim = undefined;
    this.claimEvent = '';
    stop?.();
  }

  private attachClaim(row: DesktopInteraction): void {
    this.claimEvent = row.id;
    this.stopClaim = this.actions.watch('userQuestions/attachWait', { 'agentId': row.sessionId, 'callId': row.callId }, {
      onItem: (frame: Object): void => {
        const remaining = getNumber(frame, 'remainingMs');
        if (this.claimEvent !== row.id || remaining === undefined ||
          this.questionStates.get(this.questionKey(row))?.held === true) { return; }
        this.clearCountdown();
        this.claimDeadline = Date.now() + remaining;
        this.claimTimer = setTimeout((): void => {
          this.rejectQuestion(row.id, 'ASK_TIMED_OUT', 'ask_user_question timed out before the user answered')
            .then((error: string): void => {
              if (error && this.claimEvent === row.id) {
                this.clearCountdown();
                this.stopClaim?.();
                this.stopClaim = undefined;
                this.publish();
              }
            });
        }, Math.max(0, remaining));
        this.publish();
      },
      onError: (): void => { this.endCountdown(row.id); },
      onEnd: (): void => { this.endCountdown(row.id); }
    });
  }

  private endCountdown(id: string): void {
    if (this.claimEvent !== id || this.claimDeadline === 0) { return; }
    this.clearCountdown();
    this.publish();
  }
}
