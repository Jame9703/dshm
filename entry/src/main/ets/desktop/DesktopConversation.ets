import { util } from '@kit.ArkTS';
import {
  commandsListEndpoint, commandsListPayload, filePart, fileUploadEndpoint, fileUploadPayload, followSessionAddress,
  modelSelectionLabel, projectDefaultSelection, projectModelCatalog, projectSessionPage,
  projectFileUpload, projectSessionPrompt, projectWireRecord, promptPayload, PromptMode, queueSteerAction,
  SessionPageValue, sessionCancelPayload,
  sessionFollowPayload, sessionUpdateQueuePayload, Speaker, textPart, TrajectoryItem, TrajectoryKind
} from 'appstate';
import type { FeedbackRow, ModelOption, ModelSelection, PromptContentPart, QueueActionBody } from 'appstate';
import { Connection, getArray, getBoolean, getNumber, getRecord, getString, randomUuid, toStringArray } from 'connection';
import type { RpcResult, StreamSink } from 'connection';
import {
  argsFor, COMMANDS_EXECUTE_ENDPOINT, EVENT_TURN_END, mayChangeSessionTitle, MODEL_CATALOG_ENDPOINT, SESSION_CANCEL_ENDPOINT, SESSION_FOLLOW_ENDPOINT,
  SESSION_PAGE_ENDPOINT, SESSION_PROMPT_ENDPOINT, SESSION_SELECT_MODEL_ENDPOINT, SESSION_UPDATE_QUEUE_ENDPOINT
} from 'dshcompat';

import { DesktopInteractions } from './DesktopInteractions';
import { desktopPlanMode, desktopSubmittedPlan, DesktopPlanDocument } from './DesktopPlan';
import { DesktopTurnArtifacts, observeDesktopArtifacts } from './DesktopArtifacts';
import { DesktopProcessGroup, DesktopToolLog } from './DesktopToolLog';
import { DesktopGoal, DesktopGoalAction, DesktopGoalRef, DesktopGoalState } from './DesktopGoal';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopFeedback } from './DesktopFeedback';
import { DesktopReplyTail, DesktopReplyTimeline } from './DesktopReplyTimeline';
import { DesktopPromptQueue, DesktopQueuedPrompt } from './DesktopPromptQueue';
import { desktopImageMime, desktopMediaAttachment, desktopMessageAttachments } from './DesktopAttachments';
import type { DesktopDraftAttachment, DesktopMediaAttachment } from './DesktopAttachments';
import { commandInvocation, desktopCommandCatalog, DesktopCommand, DesktopCommandRecord, observeDesktopCommand,
  resolveDesktopCommand } from './DesktopCommands';

const STATE_ENDPOINT: string = 'session/state';
const PROJECTIONS_ENDPOINT: string = 'session/projections';
const PAGE_MESSAGES: number = 50;

export interface DesktopPermissionOption {
  value: string;
  title: string;
  detail: string;
}

export interface DesktopTranscriptItem {
  id: string;
  sequence: number;
  message?: TrajectoryItem;
  attachments?: DesktopMediaAttachment[];
  plan?: DesktopPlanDocument;
  artifacts?: DesktopTurnArtifacts;
  process?: DesktopProcessGroup;
  command?: DesktopCommandRecord;
  replyTail?: DesktopReplyTail;
  inheritedHistory?: boolean;
}

export interface DesktopConversationSnapshot {
  sessionId: string;
  transcript: DesktopTranscriptItem[];
  partial: string;
  preparingTool: string;
  loading: boolean;
  hasEarlier: boolean;
  running: boolean;
  historyLoaded: boolean;
  receivedTurn: number;
  waitingForInput: boolean;
  models: ModelOption[];
  modelsLoading: boolean;
  permissions: DesktopPermissionOption[];
  permission: string;
  modelLabel: string;
  planMode?: boolean;
  goal?: DesktopGoal;
  selection?: ModelSelection;
  error: string;
  commands?: DesktopCommand[];
  commandLoading: boolean;
  commandError: string;
  feedbackRows: FeedbackRow[];
  queue: DesktopQueuedPrompt[];
  busyEnterSteers: boolean;
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
  private readonly toolLog: DesktopToolLog = new DesktopToolLog();
  private readonly commandRecords: Map<string, DesktopCommandRecord> = new Map();
  private commands?: DesktopCommand[];
  private commandTask?: Promise<DesktopCommand[] | undefined>;
  private commandError: string = '';
  private commandVersion: number = 0;
  private planMode?: boolean;
  private planAsOf: number = -1;
  private readonly goals: DesktopGoalState = new DesktopGoalState();
  private readonly queue: DesktopPromptQueue = new DesktopPromptQueue();
  private readonly sending: Map<string, DesktopQueuedPrompt> = new Map<string, DesktopQueuedPrompt>();
  private busyEnterSteers: boolean = false;
  private imageBytesLimit?: number;
  private readonly replyTimeline: DesktopReplyTimeline = new DesktopReplyTimeline();
  private inheritedSequence: number = -1;
  readonly feedback: DesktopFeedback;
  private models: ModelOption[] = [];
  private modelsLoading: boolean = false;
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
  private historyLoaded: boolean = false;
  private receivedTurn: number = 0;
  private waitingForInput: boolean = false;
  private attempt: string = '';
  private partial: string = '';
  private preparingTool: string = '';
  private permissions: DesktopPermissionOption[] = [];
  private permission: string = '';
  private permissionsRequested: boolean = false;
  private readonly pendingRequests: Map<string, DraftRequest> = new Map<string, DraftRequest>();

  constructor(connection: Connection, listener: (snapshot: DesktopConversationSnapshot) => void,
    refreshSessions: () => void, interactions: DesktopInteractions, host: DesktopHostActions) {
    this.connection = connection;
    this.interactions = interactions;
    this.listener = listener;
    this.refreshSessions = refreshSessions;
    this.feedback = new DesktopFeedback(host, (): void => this.publish());
  }

  async loadModels(refresh: boolean = false): Promise<void> {
    if (this.modelsLoading || (this.modelsRequested && !refresh)) {
      return;
    }
    const empty: Record<string, Object> = {};
    const args = argsFor(MODEL_CATALOG_ENDPOINT, empty);
    if (args === undefined) {
      return;
    }
    this.modelsLoading = true;
    if (refresh) { this.publish(); }
    const response = await this.connection.call(MODEL_CATALOG_ENDPOINT, args);
    this.modelsLoading = false;
    if (this.closed) { return; }
    if (response.ok) {
      this.modelsRequested = true;
      this.models = projectModelCatalog(response.value);
      this.defaultModel = projectDefaultSelection(response.value);
    }
    this.publish();
  }

  open(sessionId: string): void {
    if (this.closed || sessionId === this.sessionId) {
      return;
    }
    const generation = ++this.generation;
    this.stopWatching();
    this.sessionId = sessionId;
    this.feedback.select(sessionId);
    this.interactions.select(sessionId);
    this.transcript = [];
    this.turnArtifacts.clear();
    this.toolLog.clear();
    this.commandRecords.clear();
    this.replyTimeline.clear();
    this.inheritedSequence = -1;
    this.commandVersion++;
    this.commands = undefined;
    this.commandTask = undefined;
    this.commandError = '';
    this.planMode = undefined;
    this.planAsOf = -1;
    this.goals.reset();
    this.queue.reset();
    this.imageBytesLimit = undefined;
    this.model = undefined;
    this.permission = '';
    this.cursor = -1;
    this.earliest = -1;
    this.hasEarlier = false;
    this.loading = sessionId.length > 0;
    this.pageLoading = false;
    this.error = '';
    this.running = false;
    this.historyLoaded = false;
    this.receivedTurn = 0;
    this.waitingForInput = false;
    this.attempt = '';
    this.partial = '';
    this.preparingTool = '';
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
    this.feedback.select('');
    this.stopWatching();
    this.pendingRequests.clear();
  }

  loadEarlier(): void {
    if (this.hasEarlier && !this.pageLoading) {
      this.loadPage(this.generation, true);
    }
  }

  async upload(sessionId: string, name: string, data: ArrayBuffer,
    mediaType: string): Promise<DesktopDraftAttachment | string> {
    if (desktopImageMime(mediaType)) {
      const response = await this.connection.uploadSessionImage(sessionId, data, mediaType, name);
      if (!response.ok) { return this.failure(response, '图片上传失败'); }
      const receiptId = getString(response.value, 'receiptId') ?? '';
      const row = desktopMediaAttachment(getRecord(response.value, 'image'), true);
      if (!receiptId || row === undefined) { return '宿主没有返回有效的图片回执'; }
      return { receiptId: receiptId, name: row.name, bytes: row.bytes, mediaType: mediaType, picture: row };
    }
    const base64 = await new util.Base64Helper().encodeToString(new Uint8Array(data));
    const args = fileUploadPayload(sessionId, base64, name);
    const result = args === undefined ? undefined : await this.connection.call(fileUploadEndpoint(), args);
    if (!result?.ok) {
      return this.failure(result, '附件上传失败');
    }
    const file = projectFileUpload(result.value);
    if (file === undefined) {
      return '宿主没有返回有效的附件回执';
    }
    const attachment: DesktopDraftAttachment = {
      receiptId: file.receiptId, name: file.file.name || name, bytes: file.file.bytes || data.byteLength, mediaType: mediaType
    };
    return attachment;
  }

  imageLimit(sessionId: string): number | undefined {
    return this.sessionId === sessionId ? this.imageBytesLimit : undefined;
  }

  private readImageLimit(values?: Object): void {
    const limits = getRecord(values, 'imageLimits');
    const individual = getNumber(limits, 'maxImageBytes');
    const combined = getNumber(limits, 'maxMessageImageBytes');
    if (individual !== undefined && combined !== undefined && individual > 0 && combined > 0) {
      this.imageBytesLimit = Math.min(individual, combined);
    }
  }

  async send(sessionId: string, text: string, attachments: DesktopDraftAttachment[],
    onExport: (sessionId: string) => Promise<string>, onFeedback: (sessionId: string) => Promise<string>,
    alternateDelivery: boolean): Promise<string> {
    const invocation = commandInvocation(text);
    if (invocation !== undefined) {
      const commands = await this.loadCommands(sessionId);
      if (commands === undefined) { return this.commandError || '无法读取当前会话的指令'; }
      const command = resolveDesktopCommand(commands, invocation.token);
      if (command !== undefined && (command.hint !== undefined || !invocation.suffix)) {
        if (attachments.length > 0 && !command.attachments) {
          return `/${invocation.token} 不接受附件，请先移除附件`;
        }
        if (command.kind === 'feedback' && !invocation.suffix) { return onFeedback(sessionId); }
        const result = await this.executeCommand(sessionId, '/' + command.name + invocation.suffix, attachments);
        if (result === '' && command.kind === 'export' && !invocation.suffix) {
          return onExport(sessionId);
        }
        return result;
      }
    }
    const ids = attachments.map((file: DesktopDraftAttachment): string => file.receiptId);
    const busy = sessionId === this.sessionId && this.running;
    const mode = busy && (this.busyEnterSteers !== alternateDelivery) ? PromptMode.STEER : PromptMode.QUEUE;
    const signature = JSON.stringify([mode, text, ...ids]);
    const parts: PromptContentPart[] = ids.map((id: string): PromptContentPart => filePart(id));
    if (text.trim().length > 0) {
      parts.unshift(textPart(text));
    }
    let request = this.pendingRequests.get(sessionId);
    if (request === undefined || request.signature !== signature) {
      request = { signature: signature, id: 'req-' + randomUuid() };
      this.pendingRequests.set(sessionId, request);
    }
    const args = promptPayload(request.id, sessionId, mode, parts, '');
    const requestId = request.id;
    if (args !== undefined && busy && mode === PromptMode.QUEUE) {
      const files = attachments.map((attachment: DesktopDraftAttachment): DesktopMediaAttachment => {
        return attachment.picture ?? { id: attachment.receiptId, name: attachment.name, bytes: attachment.bytes, image: false };
      });
      this.sending.set(sessionId, { id: request.id, requestId: request.id, text: text,
        editable: false, attachments: files, sending: true });
      this.publish();
    }
    const generation = this.generation;
    const response = args === undefined ? undefined : await this.connection.call(SESSION_PROMPT_ENDPOINT, args);
    const accepted = response?.ok === true && projectSessionPrompt(response.value).accepted;
    if (this.sending.has(sessionId)) {
      if (accepted && sessionId === this.sessionId && this.current(generation) &&
        !this.queue.rows.some((row: DesktopQueuedPrompt): boolean => row.requestId === requestId)) {
        await this.loadSelection(generation);
      }
      this.sending.delete(sessionId);
      this.publish();
    }
    if (accepted) {
      this.pendingRequests.delete(sessionId);
      return '';
    }
    return this.failure(response, '宿主未确认发送');
  }

  async updateQueue(sessionId: string, itemId: string, action: QueueActionBody): Promise<string> {
    if (this.sessionId !== sessionId || !this.queue.rows.some((row: DesktopQueuedPrompt): boolean => row.id === itemId)) {
      return '这条消息已离开待发送队列';
    }
    const generation = this.generation;
    const args = sessionUpdateQueuePayload(sessionId, itemId, action);
    const response = args === undefined ? undefined : await this.connection.call(SESSION_UPDATE_QUEUE_ENDPOINT, args);
    if (this.current(generation)) { await this.loadSelection(generation); }
    return response?.ok && getBoolean(response.value, 'accepted') === true ? '' :
      this.failure(response, '无法更新排队消息');
  }

  async steerQueue(sessionId: string): Promise<string> {
    if (sessionId !== this.sessionId || !this.running) { return ''; }
    const generation = this.generation;
    const queued = this.queue.rows;
    for (const row of queued) {
      const args = sessionUpdateQueuePayload(sessionId, row.id, queueSteerAction());
      const response = args === undefined ? undefined : await this.connection.call(SESSION_UPDATE_QUEUE_ENDPOINT, args);
      if (!this.current(generation)) { return ''; }
      if (!response?.ok || getBoolean(response.value, 'accepted') !== true) {
        await this.loadSelection(generation);
        const code = response?.error?.code;
        return code === 'session/steer-unavailable' || code === 'session/queue-item-not-found' ?
          '' : this.failure(response, '插话发送失败');
      }
    }
    if (queued.length > 0) { await this.loadSelection(generation); }
    return '';
  }

  setBusyEnter(steers: boolean): void {
    if (this.busyEnterSteers === steers) { return; }
    this.busyEnterSteers = steers;
    this.publish();
  }

  async togglePlanMode(sessionId: string, enabled: boolean): Promise<string> {
    return this.executeCommand(sessionId, enabled ? '/plan' : '/plan off', []);
  }

  async mutateGoal(sessionId: string, action: DesktopGoalAction, expected: DesktopGoalRef,
    objective: string): Promise<string> {
    const goal = this.goals.goal;
    if (sessionId !== this.sessionId || goal?.id !== expected.id || goal.revision !== expected.revision) {
      return '目标已更新，请重新打开编辑';
    }
    const ref: Record<string, Object> = { 'id': expected.id, 'revision': expected.revision };
    const body: Record<string, Object> = { 'agentId': sessionId, 'ref': ref };
    if (action === DesktopGoalAction.EDIT) {
      const changes: Record<string, Object> = { 'objective': objective.trim() };
      body['request'] = changes;
    }
    const endpoint = `goals/${action}`;
    const args = argsFor(endpoint, body);
    const generation = this.generation;
    const result = args === undefined ? undefined : await this.connection.call(endpoint, args);
    if (this.current(generation)) { await this.loadSelection(generation); }
    return result?.ok ? '' : this.failure(result, '宿主未确认目标操作');
  }

  observeGoalActivation(frame: Object): void {
    if (this.goals.observeEvent(frame, this.sessionId)) { this.publish(); }
  }

  async readGoalActivation(): Promise<void> {
    const goal = this.goals.goal;
    if (this.closed || goal?.phase !== 'active') { return; }
    const body: Record<string, Object> = { 'agentId': this.sessionId };
    const args = argsFor('goals/get', body);
    if (args === undefined) { return; }
    const version = this.goals.readVersion();
    const generation = this.generation;
    const reply = await this.connection.call('goals/get', args);
    if (reply.ok && this.current(generation) && this.goals.observeRead(version, goal, reply.value)) {
      this.publish();
    }
  }

  async runCommandChoice(sessionId: string, name: string,
    onExport: (sessionId: string) => Promise<string>): Promise<string> {
    const commands = await this.loadCommands(sessionId);
    const command = commands?.find((item: DesktopCommand): boolean => item.name === name);
    if (command === undefined) { return this.commandError || '此指令已不可用'; }
    const result = await this.executeCommand(sessionId, '/' + command.name, []);
    return result === '' && command.kind === 'export' ? onExport(sessionId) : result;
  }

  downloadLog(sessionId: string, onData: (chunk: ArrayBuffer) => void): Promise<string> {
    return this.connection.downloadSessionArchive(sessionId, onData);
  }

  readMarkdown(sessionId: string): Promise<RpcResult> {
    return this.connection.readSessionMarkdown(sessionId);
  }

  loadCommands(sessionId: string): Promise<DesktopCommand[] | undefined> {
    if (this.closed || !sessionId || sessionId !== this.sessionId) {
      return Promise.resolve(undefined);
    }
    if (this.commands !== undefined) { return Promise.resolve(this.commands); }
    if (this.commandTask !== undefined) { return this.commandTask; }
    const version = this.commandVersion;
    const task = this.fetchCommands(sessionId, version);
    this.commandTask = task;
    this.publish();
    return task;
  }

  invalidateCommands(): void {
    if (this.commands === undefined && this.commandTask === undefined) { return; }
    this.commandVersion++;
    this.commands = undefined;
    this.commandTask = undefined;
    this.loadCommands(this.sessionId);
  }

  private async fetchCommands(sessionId: string, version: number): Promise<DesktopCommand[] | undefined> {
    const args = commandsListPayload(sessionId);
    const reply = await (args === undefined ? Promise.resolve(undefined) : this.connection.call(commandsListEndpoint(), args));
    if (this.closed || this.sessionId !== sessionId || version !== this.commandVersion) {
      return undefined;
    }
    this.commandTask = undefined;
    this.commands = reply?.ok ? desktopCommandCatalog(reply.value) : undefined;
    this.commandError = this.commands === undefined ? this.failure(reply, '无法读取当前会话的指令') : '';
    this.publish();
    return this.commands;
  }

  private async executeCommand(sessionId: string, line: string, files: DesktopDraftAttachment[]): Promise<string> {
    const attachments = files.map((file: DesktopDraftAttachment): PromptContentPart => filePart(file.receiptId));
    const body: Record<string, Object> = {
      'agentId': sessionId, 'line': line, 'submittedAttachments': attachments
    };
    const args = argsFor(COMMANDS_EXECUTE_ENDPOINT, body);
    const generation = this.generation;
    const response = args === undefined ? undefined : await this.connection.call(COMMANDS_EXECUTE_ENDPOINT, args);
    if (!response?.ok) {
      return this.failure(response, '无法提交指令');
    }
    const result = getRecord(response.value, 'result');
    if (getString(result, 'kind') !== 'success') {
      return getString(result, 'text') || '当前宿主未接受该指令';
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
      this.preparingTool = '';
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
      this.historyLoaded = true;
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
        if (item.artifacts === undefined && item.process === undefined && item.command === undefined &&
          item.replyTail === undefined && !item.inheritedHistory) {
          result.set(item.id, item);
        }
      });
    } else {
      this.turnArtifacts.clear();
      this.toolLog.clear();
      this.commandRecords.clear();
      this.replyTimeline.clear();
      this.inheritedSequence = -1;
    }
    for (const record of records) {
      const seq = getNumber(getRecord(record, 'event'), 'seq') ?? -1;
      if (seq >= 0 && (this.earliest < 0 || seq < this.earliest)) {
        this.earliest = seq;
      }
      const event = getRecord(record, 'event');
      const eventType = getString(event, 'type');
      if (eventType === EVENT_TURN_END || eventType === 'turn/start') {
        const turn = getNumber(getRecord(event, 'data'), 'turn') ?? 0;
        this.receivedTurn = Math.max(this.receivedTurn, eventType === EVENT_TURN_END ? turn : turn - 1);
      }
      observeDesktopArtifacts(this.turnArtifacts, event);
      this.toolLog.observe(record);
      observeDesktopCommand(this.commandRecords, event);
      this.replyTimeline.observe(event);
      if (getString(event, 'type') === 'session/end-seed' && getBoolean(getRecord(event, 'data'), 'inherited') === true) {
        this.inheritedSequence = Math.max(this.inheritedSequence, seq);
      }
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
      const attachments = message?.speaker === Speaker.USER ?
        desktopMessageAttachments(getRecord(event, 'data')) : [];
      if (message !== undefined && message.kind === TrajectoryKind.MESSAGE && !message.internal && message.speaker !== Speaker.SYSTEM &&
        (message.body.length > 0 || message.reasoning.length > 0 || attachments.length > 0)) {
        result.set(message.id, { id: message.id, sequence: seq, message: message, attachments: attachments });
        if (message.speaker === Speaker.ASSISTANT) { this.replyTimeline.observe(event, message.body); }
      }
    }
    this.turnArtifacts.forEach((row: DesktopTurnArtifacts): void => {
      if (row.closeSequence >= 0 && (row.files.length > 0 || row.changeSequence >= 0 || row.applied.length > 0)) {
        const id = `artifacts:${this.sessionId}:${row.turn}:${row.changeSequence}:${row.files.length}:${row.applied.length}`;
        result.set(id, { id: id, sequence: row.closeSequence, artifacts: row });
      }
    });
    for (const process of this.toolLog.groups()) {
      const id = `process:${this.sessionId}:${process.id}`;
      result.set(id, { id: id, sequence: process.sequence, process: process });
    }
    this.commandRecords.forEach((command: DesktopCommandRecord): void => {
      if (command.sequence >= 0 && command.name) {
        const id = `command:${this.sessionId}:${command.id}`;
        result.set(id, { id: id, sequence: command.sequence, command: command });
      }
    });
    for (const replyTail of this.replyTimeline.completed()) {
      const id = `reply:${this.sessionId}:${replyTail.turn}:${replyTail.messageId}`;
      result.set(id, { id: id, sequence: replyTail.endSeq, replyTail: replyTail });
    }
    if (this.inheritedSequence >= 0) {
      result.set('inherited-history', { id: 'inherited-history', sequence: this.inheritedSequence, inheritedHistory: true });
    }
    const ordered = Array.from(result.values()).sort((a: DesktopTranscriptItem, b: DesktopTranscriptItem): number =>
      a.sequence - b.sequence);
    const transcript: DesktopTranscriptItem[] = [];
    for (const current of ordered) {
      const previous = transcript[transcript.length - 1]?.process;
      const process = current.process;
      if (previous !== undefined && process !== undefined && previous.turn === process.turn) {
        previous.steps.push(...process.steps);
        previous.version += ':' + process.version;
      } else {
        transcript.push(current);
      }
    }
    this.transcript = transcript;
    this.hasEarlier = hasEarlier;
  }

  canForkAt(endSeq: number): boolean {
    return this.replyTimeline.canFork(endSeq);
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
        this.readImageLimit(getRecord(result.value, 'values'));
        const goalChanged = this.readGoal(result.value);
        const queueChanged = this.readQueue(result.value);
        if (this.readPlan(result.value) || goalChanged || queueChanged) {
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
        options.push({ value: value, title: getString(row, 'name') ?? value, detail: getString(row, 'description') ?? '' });
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
    this.readGoal(projection);
    this.readQueue(projection);
    const values = getRecord(projection, 'values');
    this.readImageLimit(values);
    const model = getRecord(values, 'modelSelection');
    this.model = this.readModel(getRecord(model, 'next')) ?? this.readModel(getRecord(model, 'lastUsed'));
    this.permission = getString(getRecord(values, 'permissions'), 'currentValue') ?? '';
    if (this.permission.length > 0) {
      this.loadPermissions();
    }
  }

  private readGoal(projection?: Object): boolean {
    const changed = this.goals.observeProjection(projection);
    if (changed && !this.goals.goal?.activation) { this.readGoalActivation(); }
    return changed;
  }

  private readQueue(projection?: Object): boolean {
    return this.queue.observe(getRecord(projection, 'values'), getNumber(projection, 'asOfSeq') ?? -1);
  }

  private onFrame(frame: Object): void {
    const type = getString(frame, 'type');
    if (type === 'snapshot') {
      this.historyLoaded = true;
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
    } else if (type === 'projection') {
      const goalChanged = this.goals.observeDelta(frame);
      const changes = getRecord(frame, 'changes');
      this.readImageLimit(changes);
      const queueChanged = this.queue.observe(changes, getNumber(frame, 'seq') ?? -1);
      if (!goalChanged && !queueChanged) { return; }
      if (goalChanged && !this.goals.goal?.activation) { this.readGoalActivation(); }
    } else if (type === 'event') {
      const event = getRecord(frame, 'event');
      const eventType = getString(event, 'type');
      if (eventType === 'tool/call' || eventType === EVENT_TURN_END || eventType === 'assistant/message') {
        this.preparingTool = '';
      }
      if (eventType?.startsWith('user-question/') || eventType === 'tool/result' || eventType === 'user/message' ||
        eventType === 'plan/mode' || eventType === 'command/done' || eventType === 'goal/change') {
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
        this.preparingTool = '';
      } else if (this.attempt.length > 0 && getString(update, 'attemptId') === this.attempt) {
        const chunk = getRecord(update, 'chunk');
        if (kind === 'chunk' && getString(chunk, 'type') === 'text-delta') {
          this.partial += getString(chunk, 'text') ?? '';
        } else if (kind === 'chunk' && getString(chunk, 'type') === 'tool-call-delta') {
          this.preparingTool = getString(chunk, 'name') || this.preparingTool;
        } else if (kind === 'end' && getString(getRecord(update, 'outcome'), 'kind') === 'abandoned') {
          this.partial = '';
          this.attempt = '';
          this.preparingTool = '';
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
    const sending = this.sending.get(this.sessionId);
    const queue = sending !== undefined && !this.queue.rows.some((row: DesktopQueuedPrompt): boolean =>
      row.requestId === sending.requestId) ? [...this.queue.rows, sending] : this.queue.rows;
    this.listener({
      sessionId: this.sessionId, transcript: this.transcript, partial: this.partial, preparingTool: this.preparingTool, loading: this.loading,
      hasEarlier: this.hasEarlier && !this.pageLoading, running: this.running, waitingForInput: this.waitingForInput,
      historyLoaded: this.historyLoaded, receivedTurn: this.receivedTurn,
      models: this.models, modelsLoading: this.modelsLoading, selection: selection, error: this.error,
      permissions: this.permission.length > 0 ? this.permissions : [], permission: this.permission,
      modelLabel: selection === undefined ? '' : modelSelectionLabel(selection, this.models), planMode: this.planMode,
      goal: this.goals.goal,
      commands: this.commands, commandLoading: this.commandTask !== undefined, commandError: this.commandError,
      feedbackRows: this.feedback.rows, queue: queue, busyEnterSteers: this.busyEnterSteers
    });
  }
}
