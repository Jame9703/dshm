import {
  followSessionAddress, modelSelectionLabel, projectDefaultSelection, projectModelCatalog, projectSessionPage,
  projectSessionPrompt, projectWireRecord, promptPayload, PromptMode, SessionPageValue, sessionCancelPayload,
  sessionFollowPayload, Speaker, textPart, TrajectoryItem, TrajectoryKind
} from 'appstate';
import type { ModelOption, ModelSelection } from 'appstate';
import { Connection, getArray, getBoolean, getNumber, getRecord, getString, randomUuid, toStringArray } from 'connection';
import type { RpcResult, StreamSink } from 'connection';
import {
  argsFor, EVENT_TURN_END, mayChangeSessionTitle, MODEL_CATALOG_ENDPOINT, SESSION_CANCEL_ENDPOINT, SESSION_FOLLOW_ENDPOINT,
  SESSION_PAGE_ENDPOINT, SESSION_PROMPT_ENDPOINT, SESSION_SELECT_MODEL_ENDPOINT
} from 'dshcompat';

const STATE_ENDPOINT: string = 'session/state';
const PROJECTIONS_ENDPOINT: string = 'session/projections';
const PAGE_MESSAGES: number = 50;

export interface DesktopConversationSnapshot {
  sessionId: string;
  messages: TrajectoryItem[];
  partial: string;
  loading: boolean;
  hasEarlier: boolean;
  running: boolean;
  waitingForInput: boolean;
  models: ModelOption[];
  modelLabel: string;
  selection?: ModelSelection;
  error: string;
}

interface DraftRequest {
  text: string;
  id: string;
}

export class DesktopConversation {
  private readonly connection: Connection;
  private readonly listener: (snapshot: DesktopConversationSnapshot) => void;
  private readonly refreshSessions: () => void;
  private sessionId: string = '';
  private generation: number = 0;
  private closed: boolean = false;
  private stopFollow?: () => void;
  private timer: number = -1;
  private messages: TrajectoryItem[] = [];
  private models: ModelOption[] = [];
  private modelsRequested: boolean = false;
  private defaultModel?: ModelSelection;
  private model?: ModelSelection;
  private error: string = '';
  private loading: boolean = false;
  private pageLoading: boolean = false;
  private hasEarlier: boolean = false;
  private cursor: number = -1;
  private earliest: number = -1;
  private running: boolean = false;
  private waitingForInput: boolean = false;
  private attempt: string = '';
  private partial: string = '';
  private readonly pendingRequests: Map<string, DraftRequest> = new Map<string, DraftRequest>();

  constructor(connection: Connection, listener: (snapshot: DesktopConversationSnapshot) => void,
    refreshSessions: () => void) {
    this.connection = connection;
    this.listener = listener;
    this.refreshSessions = refreshSessions;
  }

  private async loadModels(): Promise<void> {
    if (this.modelsRequested) {
      return;
    }
    const empty: Record<string, Object> = {};
    const args = argsFor(MODEL_CATALOG_ENDPOINT, empty);
    if (args === undefined) {
      return;
    }
    this.modelsRequested = true;
    const response = await this.connection.call(MODEL_CATALOG_ENDPOINT, args);
    if (response.ok && !this.closed) {
      this.models = projectModelCatalog(response.value);
      this.defaultModel = projectDefaultSelection(response.value);
      this.publish();
    } else {
      this.modelsRequested = false;
    }
  }

  open(sessionId: string): void {
    if (this.closed || sessionId === this.sessionId) {
      return;
    }
    const generation = ++this.generation;
    this.stopWatching();
    this.sessionId = sessionId;
    this.messages = [];
    this.model = undefined;
    this.cursor = -1;
    this.earliest = -1;
    this.hasEarlier = false;
    this.loading = sessionId.length > 0;
    this.pageLoading = false;
    this.error = '';
    this.running = false;
    this.waitingForInput = false;
    this.attempt = '';
    this.partial = '';
    this.publish();
    if (sessionId.length === 0) {
      return;
    }
    const args = sessionFollowPayload(followSessionAddress(sessionId), PAGE_MESSAGES, true);
    if (args !== undefined) {
      const sink: StreamSink = {
        onItem: (frame: Object): void => {
          if (this.current(generation)) {
            this.onFrame(frame);
          }
        },
        onError: (): void => this.followEnded(generation),
        onEnd: (): void => this.followEnded(generation)
      };
      this.stopFollow = this.connection.openStream(SESSION_FOLLOW_ENDPOINT, args, sink);
    }
    this.loadPage(generation, false);
    this.loadSelection(generation);
    this.loadModels();
    this.pollState(generation);
  }

  close(): void {
    this.closed = true;
    this.stopWatching();
    this.pendingRequests.clear();
  }

  loadEarlier(): void {
    if (this.hasEarlier && !this.pageLoading) {
      this.loadPage(this.generation, true);
    }
  }

  async send(sessionId: string, text: string): Promise<string> {
    let request = this.pendingRequests.get(sessionId);
    if (request === undefined || request.text !== text) {
      request = { text: text, id: 'req-' + randomUuid() };
      this.pendingRequests.set(sessionId, request);
    }
    const args = promptPayload(request.id, sessionId, PromptMode.QUEUE, [textPart(text)], '');
    const response = args === undefined ? undefined : await this.connection.call(SESSION_PROMPT_ENDPOINT, args);
    if (response?.ok && projectSessionPrompt(response.value).accepted) {
      this.pendingRequests.delete(sessionId);
      return '';
    }
    return this.failure(response, '宿主未确认发送');
  }

  async cancel(sessionId: string): Promise<string> {
    const args = sessionCancelPayload(sessionId);
    const response = args === undefined ? undefined : await this.connection.call(SESSION_CANCEL_ENDPOINT, args);
    return response?.ok && getBoolean(response.value, 'accepted') === true ? '' :
      this.failure(response, '宿主未确认停止');
  }

  async selectModel(sessionId: string, selection: ModelSelection): Promise<string> {
    const request: Record<string, Object> = {
      'sessionId': sessionId, 'provider': selection.provider, 'model': selection.modelId
    };
    if (selection.effort.length > 0) {
      request['reasoningEffort'] = selection.effort;
    }
    const args = argsFor(SESSION_SELECT_MODEL_ENDPOINT, request);
    const response = args === undefined ? undefined : await this.connection.call(SESSION_SELECT_MODEL_ENDPOINT, args);
    if (!response?.ok) {
      return this.failure(response, '无法切换模型');
    }
    if (this.sessionId === sessionId && !this.closed) {
      this.model = this.readModel(getRecord(response.value, 'selected')) ?? selection;
      this.publish();
    }
    return '';
  }

  private failure(response: RpcResult | undefined, fallback: string): string {
    return response?.error?.message || fallback;
  }

  private current(generation: number): boolean {
    return !this.closed && generation === this.generation;
  }

  private stopWatching(): void {
    this.stopFollow?.();
    this.stopFollow = undefined;
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private followEnded(generation: number): void {
    if (this.current(generation)) {
      this.stopFollow = undefined;
      this.attempt = '';
      this.partial = '';
      this.publish();
    }
  }

  private async loadPage(generation: number, earlier: boolean): Promise<void> {
    this.pageLoading = true;
    const request: Record<string, Object> = {
      'address': followSessionAddress(this.sessionId), 'maxMessages': PAGE_MESSAGES
    };
    if (earlier && this.earliest >= 0) {
      request['beforeSeq'] = this.earliest;
    }
    const args = argsFor(SESSION_PAGE_ENDPOINT, request);
    const result = args === undefined ? undefined : await this.connection.call(SESSION_PAGE_ENDPOINT, args);
    if (!this.current(generation)) {
      return;
    }
    this.pageLoading = false;
    if (result?.ok) {
      const page: SessionPageValue = projectSessionPage(result.value);
      const cursor = getNumber(result.value, 'cursor') ?? -1;
      if (earlier || cursor >= this.cursor) {
        this.addRecords(page.records, earlier || !this.loading, page.hasMore);
        this.cursor = Math.max(this.cursor, cursor);
      }
      this.error = '';
    } else if (this.loading || earlier) {
      this.error = this.failure(result, '无法读取会话记录');
    }
    this.loading = false;
    this.publish();
  }

  private addRecords(records: Object[], merge: boolean, hasEarlier: boolean): void {
    const result: Map<string, TrajectoryItem> = new Map<string, TrajectoryItem>();
    if (merge) {
      this.messages.forEach((message: TrajectoryItem): void => { result.set(message.id, message); });
    }
    for (const record of records) {
      const seq = getNumber(getRecord(record, 'event'), 'seq') ?? -1;
      if (seq >= 0 && (this.earliest < 0 || seq < this.earliest)) {
        this.earliest = seq;
      }
      const event = getRecord(record, 'event');
      const source = getString(getRecord(getRecord(event, 'data'), 'source'), 'kind');
      if (getString(event, 'type') === 'user/message' && source !== undefined && source !== 'user') {
        continue;
      }
      const message = projectWireRecord(record);
      if (message !== undefined && message.kind === TrajectoryKind.MESSAGE && !message.internal && message.speaker !== Speaker.SYSTEM && message.body.length > 0) {
        result.set(message.id, message);
      }
    }
    this.messages = Array.from(result.values()).sort((a: TrajectoryItem, b: TrajectoryItem): number =>
      Number(a.id.substring(3)) - Number(b.id.substring(3)));
    this.hasEarlier = hasEarlier;
  }

  private async loadSelection(generation: number): Promise<void> {
    const request: Record<string, Object> = { 'sessionId': this.sessionId };
    const args = argsFor(PROJECTIONS_ENDPOINT, request);
    const result = args === undefined ? undefined : await this.connection.call(PROJECTIONS_ENDPOINT, args);
    if (result?.ok && this.current(generation) && this.model === undefined) {
      this.readProjection(result.value);
      this.publish();
    }
  }

  private async pollState(generation: number): Promise<void> {
    const request: Record<string, Object> = { 'sessionId': this.sessionId };
    const args = argsFor(STATE_ENDPOINT, request);
    const response = args === undefined ? undefined : await this.connection.call(STATE_ENDPOINT, args);
    if (!this.current(generation)) {
      return;
    }
    if (response?.ok) {
      const active = getBoolean(response.value, 'running') === true ||
        (getArray(response.value, 'queue')?.length ?? 0) > 0;
      const waiting = (getArray(response.value, 'pendingInput')?.length ?? 0) > 0;
      if (active !== this.running || waiting !== this.waitingForInput) {
        this.running = active;
        this.waitingForInput = waiting;
        this.publish();
      }
      const cursor = getNumber(response.value, 'cursor') ?? -1;
      if (this.stopFollow === undefined && cursor > this.cursor && !this.pageLoading) {
        this.loadPage(generation, false);
      }
    } else if (this.stopFollow === undefined && !this.pageLoading) {
      this.loadPage(generation, false);
    }
    this.timer = setTimeout((): void => { this.pollState(generation); }, this.running ? 1200 : 3500);
  }

  private readModel(value: Object | undefined): ModelSelection | undefined {
    const provider = getString(value, 'provider') ?? '';
    const model = getString(value, 'model') ?? '';
    if (provider.length === 0 || model.length === 0) {
      return undefined;
    }
    return { provider: provider, modelId: model, effort: getString(value, 'reasoningEffort') ?? '' };
  }

  private readProjection(projection: Object | undefined): void {
    const values = getRecord(projection, 'values');
    const model = getRecord(values, 'modelSelection');
    this.model = this.readModel(getRecord(model, 'next')) ?? this.readModel(getRecord(model, 'lastUsed'));
  }

  private onFrame(frame: Object): void {
    const type = getString(frame, 'type');
    if (type === 'snapshot') {
      const cursor = getNumber(frame, 'cursor') ?? -1;
      if (cursor >= this.cursor) {
        this.addRecords(getArray(frame, 'records') ?? [], !this.loading, getBoolean(frame, 'hasMore') === true);
        this.cursor = cursor;
      }
      this.loading = false;
      this.error = '';
      this.readProjection(getRecord(frame, 'projections'));
      const pending = getRecord(getRecord(frame, 'assistantStream'), 'activeAttempt');
      if (pending !== undefined) {
        this.attempt = getString(pending, 'attemptId') ?? '';
        this.partial = '';
        for (const entry of getArray(pending, 'stream') ?? []) {
          if (getString(entry, 'type') === 'text-chunks') {
            this.partial += toStringArray(getArray(entry, 'texts') ?? []).join('');
          }
        }
        this.running = true;
      }
    } else if (type === 'event') {
      const event = getRecord(frame, 'event');
      const eventType = getString(event, 'type');
      this.cursor = Math.max(this.cursor, getNumber(event, 'seq') ?? -1);
      this.addRecords([frame], true, this.hasEarlier);
      if (eventType === EVENT_TURN_END || (eventType !== undefined && mayChangeSessionTitle(eventType))) {
        this.refreshSessions();
      }
      if (eventType === 'turn/start') {
        this.error = '';
        this.running = true;
      } else if (eventType === EVENT_TURN_END) {
        this.running = false;
        this.waitingForInput = false;
        this.partial = '';
        this.attempt = '';
        const reason = getRecord(getRecord(event, 'data'), 'reason');
        this.error = getString(reason, 'kind') === 'error' ?
          getString(getRecord(reason, 'error'), 'message') ?? '本轮未能完成' : '';
      } else if (eventType === 'assistant/message') {
        this.partial = '';
        this.attempt = '';
      }
    } else if (type === 'assistant-stream') {
      const update = getRecord(frame, 'frame');
      const kind = getString(update, 'type');
      if (kind === 'start') {
        this.running = true;
        this.attempt = getString(update, 'attemptId') ?? '';
        this.partial = '';
      } else if (this.attempt.length > 0 && getString(update, 'attemptId') === this.attempt) {
        const chunk = getRecord(update, 'chunk');
        if (kind === 'chunk' && getString(chunk, 'type') === 'text-delta') {
          this.partial += getString(chunk, 'text') ?? '';
        } else if (kind === 'end' && getString(getRecord(update, 'outcome'), 'kind') === 'abandoned') {
          this.partial = '';
          this.attempt = '';
        }
      }
    } else {
      return;
    }
    this.publish();
  }

  private publish(): void {
    if (this.closed) {
      return;
    }
    const selection = this.model ?? this.defaultModel;
    this.listener({
      sessionId: this.sessionId, messages: this.messages, partial: this.partial, loading: this.loading,
      hasEarlier: this.hasEarlier && !this.pageLoading, running: this.running, waitingForInput: this.waitingForInput,
      models: this.models, selection: selection, error: this.error,
      modelLabel: selection === undefined ? '' : modelSelectionLabel(selection, this.models)
    });
  }
}
