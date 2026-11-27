import { Connection, EVENTS_RESULT_ENDPOINT, getArray, getBoolean, getRecord, getString } from 'connection';
import { RemoteEventFrameType, WATERFALL_APPROVAL, WATERFALL_QUESTION } from 'dshcompat';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopPlanTitle, DesktopPlanReview } from './DesktopPlan';

export interface DesktopQuestionOption {
  label: string;
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
}

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
        options.push({ label: label, detail: getString(option, 'description') ?? '' });
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
      custom: intent === undefined
    });
  }
  return result;
}

export class DesktopInteractions {
  private readonly connection: Connection;
  private readonly actions: DesktopHostActions;
  private readonly onChange: (items: DesktopInteraction[]) => void;
  private readonly events: Map<string, DesktopInteraction>;
  private readonly owner?: DesktopInteractions;
  private views?: Set<DesktopInteractions>;
  private continued: DesktopInteraction[] = [];
  private selected: string = '';
  private stopClaim?: () => void;
  private claimEvent: string = '';

  constructor(connection: Connection, actions: DesktopHostActions, onChange: (items: DesktopInteraction[]) => void,
    owner?: DesktopInteractions) {
    this.connection = connection;
    this.actions = actions;
    this.onChange = onChange;
    this.owner = owner;
    this.events = owner?.events ?? new Map<string, DesktopInteraction>();
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
    this.stopClaim?.();
    this.stopClaim = undefined;
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
    const error: Record<string, Object> = {
      'name': 'UserQuestionError', 'code': 'ASK_CANCELLED', 'message': 'the user cancelled ask_user_question'
    };
    return this.settle(id, error, 'rejected');
  }

  reopenPlanReview(id: string): void {
    const row = this.events.get(id);
    if (row?.planReview !== undefined && row.sessionId === this.selected && row.reviewHidden) {
      row.reviewHidden = false;
      this.publish();
    }
  }

  async answer(id: string, answers: DesktopQuestionAnswer[]): Promise<string> {
    const event = this.events.get(id) ?? this.continued.find((row: DesktopInteraction): boolean => row.id === id);
    if (event?.kind !== 'question' || event.sessionId !== this.selected) {
      return '这项提问已结束';
    }
    const encoded: Record<string, Object> = { 'answers': answers };
    if (!event.continued) {
      return this.settle(id, encoded);
    }
    const rpc = await this.actions.call('userQuestions/answer', {
      'agentId': event.sessionId, 'callId': event.callId, 'answer': encoded
    });
    if (!rpc.ok || rpc.value !== true) {
      return rpc.error?.message ?? '宿主未接受回答，提问可能已由其他客户端处理';
    }
    this.continued = this.continued.filter((row: DesktopInteraction): boolean => row.id !== id);
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
  }

  private publishView(all: DesktopInteraction[], claimed: Set<string>): void {
    const claim = all.find((row: DesktopInteraction): boolean =>
      row.sessionId === this.selected && row.timed && row.callId.length > 0 && !claimed.has(row.id));
    if (claim !== undefined) { claimed.add(claim.id); }
    if ((claim?.id ?? '') !== this.claimEvent) {
      this.stopClaim?.();
      this.claimEvent = claim?.id ?? '';
      this.stopClaim = claim === undefined ? undefined : this.actions.watch('userQuestions/attachWait', {
        'agentId': claim.sessionId, 'callId': claim.callId
      }, { onItem: (): void => {}, onError: (): void => {}, onEnd: (): void => {} });
    }
    const active = all.filter((row: DesktopInteraction): boolean => row.sessionId === this.selected);
    const continued = this.continued.filter((row: DesktopInteraction): boolean =>
      !active.some((event: DesktopInteraction): boolean => event.callId === row.callId));
    this.onChange([...active, ...continued]);
  }
}
