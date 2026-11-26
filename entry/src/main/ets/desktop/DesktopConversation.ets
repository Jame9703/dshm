import {
  filePart, fileUploadEndpoint, fileUploadPayload, followSessionAddress, modelSelectionLabel, projectDefaultSelection, projectModelCatalog, projectSessionPage,
  projectFileUpload, projectSessionPrompt, projectWireRecord, promptPayload, PromptMode, SessionPageValue, sessionCancelPayload,
  sessionFollowPayload, Speaker, textPart, TrajectoryItem, TrajectoryKind
} from 'appstate';
import type { ModelOption, ModelSelection, PendingAttachment, PromptContentPart } from 'appstate';
import { Connection, getArray, getBoolean, getNumber, getRecord, getString, randomUuid, toStringArray } from 'connection';
import type { RpcResult, StreamSink } from 'connection';
import {
  argsFor, COMMANDS_EXECUTE_ENDPOINT, EVENT_TURN_END, mayChangeSessionTitle, MODEL_CATALOG_ENDPOINT, SESSION_CANCEL_ENDPOINT, SESSION_FOLLOW_ENDPOINT,
  SESSION_PAGE_ENDPOINT, SESSION_PROMPT_ENDPOINT, SESSION_SELECT_MODEL_ENDPOINT
} from 'dshcompat';

import { DesktopInteractions } from './DesktopInteractions';
import { desktopPlanMode, desktopSubmittedPlan, DesktopPlanDocument, isDesktopPlanCommand } from './DesktopPlan';
import { DesktopTurnArtifacts, observeDesktopArtifacts } from './DesktopArtifacts';

const STATE_ENDPOINT: string = 'session/state';
const PROJECTIONS_ENDPOINT: string = 'session/projections';
const PAGE_MESSAGES: number = 50;

export interface DesktopPermissionOption {
  value: string;
  title: string;
}

export interface DesktopTranscriptItem {
  id: string;
  sequence: number;
  message?: TrajectoryItem;
  plan?: DesktopPlanDocument;
  artifacts?: DesktopTurnArtifacts;
}

export interface DesktopConversationSnapshot {
  sessionId: string;
  transcript: DesktopTranscriptItem[];
  partial: string;
  loading: boolean;
  hasEarlier: boolean;
  running: boolean;
  waitingForInput: boolean;
  models: ModelOption[];
  permissions: DesktopPermissionOption[];
  permission: string;
  modelLabel: string;
  planMode?: boolean;
  selection?: ModelSelection;
  error: string;
}

interface DraftRequest {
  signature: string;
  id: string;
}

export class DesktopConversation {
  private readonly connection: Connection;
  private readonly interactions: DesktopInteractions;
  private readonly listener: (snapshot: DesktopConversationSnapshot) => void;
  private readonly refreshSessions: () => void;
  private sessionId: string = '';
  private generation: number = 0;
  private closed: boolean = false;
  private stopFollow?: () => void;
  private timer: number = -1;
  private transcript: DesktopTranscriptItem[] = [];
  private readonly turnArtifacts: Map<number, DesktopTurnArtifacts> = new Map();
  private planMode?: boolean;
  private planAsOf: number = -1;
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
  private permissions: DesktopPermissionOption[] = [];
  private permission: string = '';
  private permissionsRequested: boolean = false;
  private readonly pendingRequests: Map<string, DraftRequest> = new Map<string, DraftRequest>();

  constructor(connection: Connection, listener: (snapshot: DesktopConversationSnapshot) => void,
    refreshSessions: () => void, interactions: DesktopInteractions) {
    this.connection = connection;
    this.interactions = interactions;
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
    this.interactions.select(sessionId);
    this.transcript = [];
    this.turnArtifacts.clear();
    this.planMode = undefined;
    this.planAsOf = -1;
    this.model = undefined;
    this.permission = '';
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

  async upload(sessionId: string, name: string, base64: string, bytes: number,
    mediaType: string): Promise<PendingAttachment | string> {
    const args = fileUploadPayload(sessionId, base64, name);
    const result = args === undefined ? undefined : await this.connection.call(fileUploadEndpoint(), args);
    if (!result?.ok) {
      return this.failure(result, '附件上传失败');
    }
    const file = projectFileUpload(result.value);
    if (file === undefined) {
      return '宿主没有返回有效的附件回执';
    }
    const attachment: PendingAttachment = {
      receiptId: file.receiptId, name: file.file.name || name, bytes: file.file.bytes || bytes, mediaType: mediaType
    };
    return attachment;
  }

  async send(sessionId: string, text: string, attachments: PendingAttachment[]): Promise<string> {
    if (isDesktopPlanCommand(text)) {
      return this.executePlan(sessionId, text, attachments);
    }
    const ids = attachments.map((file: PendingAttachment): string => file.receiptId);
    const signature = JSON.stringify([text, ...ids]);
    const parts: PromptContentPart[] = ids.map((id: string): PromptContentPart => filePart(id));
    if (text.trim().length > 0) {
      parts.unshift(textPart(text));
    }
    let request = this.pendingRequests.get(sessionId);
    if (request === undefined || request.signature !== signature) {
      request = { signature: signature, id: 'req-' + randomUuid() };
      this.pendingRequests.set(sessionId, request);
    }
    const args = promptPayload(request.id, sessionId, PromptMode.QUEUE, parts, '');
    const response = args === undefined ? undefined : await this.connection.call(SESSION_PROMPT_ENDPOINT, args);
    if (response?.ok && projectSessionPrompt(response.value).accepted) {
      this.pendingRequests.delete(sessionId);
      return '';
    }
    return this.failure(response, '宿主未确认发送');
  }

  async togglePlanMode(sessionId: string, enabled: boolean): Promise<string> {
    return this.executePlan(sessionId, enabled ? '/plan' : '/plan off', []);
  }

  private async executePlan(sessionId: string, line: string, files: PendingAttachment[]): Promise<string> {
    const attachments = files.map((file: PendingAttachment): PromptContentPart => filePart(file.receiptId));
    const body: Record<string, Object> = {
      'agentId': sessionId, 'line': line, 'submittedAttachments': attachments
    };
    const args = argsFor(COMMANDS_EXECUTE_ENDPOINT, body);
    const generation = this.generation;
    const response = args === undefined ? undefined : await this.connection.call(COMMANDS_EXECUTE_ENDPOINT, args);
    if (!response?.ok) {
      return this.failure(response, '无法提交计划模式命令');
    }
    const result = getRecord(response.value, 'result');
    if (getString(result, 'kind') !== 'success') {
      return getString(result, 'text') || '当前宿主未接受计划模式命令';
    }
    if (this.current(generation) && this.sessionId === sessionId) {
      await this.loadSelection(generation);
    }
    return '';
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
    const result: Map<string, DesktopTranscriptItem> = new Map<string, DesktopTranscriptItem>();
    if (merge) {
      this.transcript.forEach((item: DesktopTranscriptItem): void => {
        if (item.artifacts === undefined) {
          result.set(item.id, item);
        }
      });
    } else {
      this.turnArtifacts.clear();
    }
    for (const record of records) {
      const seq = getNumber(getRecord(record, 'event'), 'seq') ?? -1;
      if (seq >= 0 && (this.earliest < 0 || seq < this.earliest)) {
        this.earliest = seq;
      }
      const event = getRecord(record, 'event');
      observeDesktopArtifacts(this.turnArtifacts, event);
      const plan = desktopSubmittedPlan(event);
      if (plan !== undefined) {
        const id = 'plan:' + plan.callId;
        const previous = result.get(id);
        if (previous === undefined || plan.sequence < previous.sequence) {
          result.set(id, { id: id, sequence: plan.sequence, plan: plan });
        }
        continue;
      }
      const source = getString(getRecord(getRecord(event, 'data'), 'source'), 'kind');
      if (getString(event, 'type') === 'user/message' && source !== undefined && source !== 'user') {
        continue;
      }
      const message = projectWireRecord(record);
      if (message !== undefined && message.kind === TrajectoryKind.MESSAGE && !message.internal && message.speaker !== Speaker.SYSTEM && message.body.length > 0) {
        result.set(message.id, { id: message.id, sequence: seq, message: message });
      }
    }
    this.turnArtifacts.forEach((row: DesktopTurnArtifacts): void => {
      if (row.closeSequence >= 0 && (row.files.length > 0 || row.changeSequence >= 0 || row.applied.length > 0)) {
        const id = `artifacts:${this.sessionId}:${row.turn}:${row.changeSequence}:${row.files.length}:${row.applied.length}`;
        result.set(id, { id: id, sequence: row.closeSequence, artifacts: row });
      }
    });
    this.transcript = Array.from(result.values()).sort((a: DesktopTranscriptItem, b: DesktopTranscriptItem): number =>
      a.sequence - b.sequence);
    this.hasEarlier = hasEarlier;
  }

  private async loadSelection(generation: number): Promise<void> {
    const request: Record<string, Object> = { 'sessionId': this.sessionId };
    const args = argsFor(PROJECTIONS_ENDPOINT, request);
    const result = args === undefined ? undefined : await this.connection.call(PROJECTIONS_ENDPOINT, args);
    if (result?.ok && this.current(generation)) {
      if (this.model === undefined) {
        this.readProjection(result.value);
        this.publish();
      } else {
        this.readQuestions(result.value);
        if (this.readPlan(result.value)) {
          this.publish();
        }
      }
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
      // A mode command can leave internal messages queued while the agent is idle.
      const active = getBoolean(response.value, 'running') === true;
      const waiting = (getArray(response.value, 'pendingInput')?.length ?? 0) > 0;
      if (active !== this.running || waiting !== this.waitingForInput) {
        this.running = active;
        this.waitingForInput = waiting;
        this.publish();
      }
      const cursor = getNumber(response.value, 'cursor') ?? -1;
      if (this.stopFollow === undefined && cursor > this.cursor && !this.pageLoading) {
        this.loadPage(generation, false);
        this.loadSelection(generation);
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

  async selectPermission(sessionId: string, preset: string): Promise<string> {
    const body: Record<string, Object> = { 'sessionId': sessionId, 'preset': preset };
    const args = argsFor('permissionPresets/set', body);
    if (args === undefined) {
      return '当前宿主不支持切换访问模式';
    }
    const result = await this.connection.call('permissionPresets/set', args);
    if (!result.ok) {
      return result.error?.message ?? '无法切换访问模式';
    }
    if (!this.closed && sessionId === this.sessionId) {
      this.permission = getString(result.value, 'currentValue') ?? preset;
      this.publish();
    }
    return '';
  }

  private async loadPermissions(): Promise<void> {
    const body: Record<string, Object> = {};
    const args = argsFor('permissionPresets/catalog', body);
    if (this.permissionsRequested || args === undefined) {
      return;
    }
    this.permissionsRequested = true;
    const result = await this.connection.call('permissionPresets/catalog', args);
    if (this.closed || !result.ok) {
      this.permissionsRequested = false;
      return;
    }
    const options: DesktopPermissionOption[] = [];
    for (const row of getArray(result.value, 'options') ?? []) {
      const value = getString(row, 'value') ?? '';
      if (value.length > 0) {
        options.push({ value: value, title: getString(row, 'name') ?? value });
      }
    }
    this.permissions = options;
    this.publish();
  }

  private readQuestions(projection?: Object): void {
    this.interactions.observeQuestions(this.sessionId, getRecord(getRecord(projection, 'values'), 'userQuestions'));
  }

  private readPlan(projection?: Object): boolean {
    const asOf = getNumber(projection, 'asOfSeq') ?? -1;
    if (asOf < this.planAsOf) {
      return false;
    }
    this.planAsOf = asOf;
    const mode = desktopPlanMode(projection);
    const changed = this.planMode !== mode;
    this.planMode = mode;
    return changed;
  }

  private readProjection(projection: Object | undefined): void {
    this.readQuestions(projection);
    this.readPlan(projection);
    const values = getRecord(projection, 'values');
    const model = getRecord(values, 'modelSelection');
    this.model = this.readModel(getRecord(model, 'next')) ?? this.readModel(getRecord(model, 'lastUsed'));
    this.permission = getString(getRecord(values, 'permissions'), 'currentValue') ?? '';
    if (this.permission.length > 0) {
      this.loadPermissions();
    }
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
      if (eventType?.startsWith('user-question/') || eventType === 'tool/result' || eventType === 'user/message' ||
        eventType === 'plan/mode' || eventType === 'command/done') {
        this.loadSelection(this.generation);
      }
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
      sessionId: this.sessionId, transcript: this.transcript, partial: this.partial, loading: this.loading,
      hasEarlier: this.hasEarlier && !this.pageLoading, running: this.running, waitingForInput: this.waitingForInput,
      models: this.models, selection: selection, error: this.error,
      permissions: this.permission.length > 0 ? this.permissions : [], permission: this.permission,
      modelLabel: selection === undefined ? '' : modelSelectionLabel(selection, this.models), planMode: this.planMode
    });
  }
}
