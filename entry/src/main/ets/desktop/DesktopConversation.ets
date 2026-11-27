import { util } from '@kit.ArkTS';
import {
  commandsListEndpoint, commandsListPayload, filePart, fileUploadEndpoint, fileUploadPayload, followSessionAddress,
  followSubagentAddress, imagePart, makeItem,
  projectSessionPage,
  projectFileUpload, projectSessionPrompt, projectWireRecord, promptPayload, PromptMode, queueSteerAction,
  SessionPageValue, sessionCancelPayload,
  sessionFollowPayload, sessionUpdateQueuePayload, Speaker, textPart, TrajectoryItem, TrajectoryKind
} from 'appstate';
import type { FeedbackRow, ModelOption, ModelSelection, PromptContentPart, QueueActionBody } from 'appstate';
import { Connection, getArray, getBoolean, getNumber, getRecord, getString, randomUuid, toStringArray } from 'connection';
import type { RpcResult, StreamSink } from 'connection';
import {
  argsFor, COMMANDS_EXECUTE_ENDPOINT, EVENT_TURN_END, mayChangeSessionTitle, SESSION_CANCEL_ENDPOINT, SESSION_FOLLOW_ENDPOINT,
  SESSION_PAGE_ENDPOINT, SESSION_PROMPT_ENDPOINT, SESSION_SELECT_MODEL_ENDPOINT, SESSION_UPDATE_QUEUE_ENDPOINT
} from 'dshcompat';

import { desktopRecallLabels } from './DesktopReferences';
import { desktopSubagentCatalog, desktopSubagentMode } from './DesktopSubagents';
import type { DesktopSubagentEntry } from './DesktopSubagents';
import { DesktopInteractions } from './DesktopInteractions';
import { desktopPlanMode, desktopSubmittedPlan, DesktopPlanDocument } from './DesktopPlan';
import { DesktopTurnArtifacts, observeDesktopArtifacts } from './DesktopArtifacts';
import { DesktopProcessGroup, DesktopToolLog } from './DesktopToolLog';
import type { DesktopToolStep } from './DesktopToolLog';
import type { DesktopCordisCard } from './DesktopCordisCards';
import type { DesktopCordisRuntime } from './DesktopCordisRuntime';
import { DesktopTrajectoryLog } from './DesktopTrajectoryLog';
import { DesktopChatUsageState } from './DesktopChatUsageModel';
import { DEFAULT_DESKTOP_TRANSCRIPT_POLICY, DesktopTranscriptTurnTimeline } from './DesktopTranscriptPresentation';
import type { DesktopTranscriptPolicy, DesktopTranscriptTurn } from './DesktopTranscriptPresentation';
import { desktopTranscriptNoticeSequence, DesktopTranscriptNoticeTimeline } from './DesktopTranscriptNoticesModel';
import type { DesktopTranscriptNotice } from './DesktopTranscriptNoticesModel';
import { desktopUserMessageCopyText } from './DesktopUserMessageActionsModel';
import { DesktopCompactionTimeline } from './DesktopCompactionModel';
import type { DesktopCompactionRow } from './DesktopCompactionModel';
import { DesktopContextMessageTimeline } from './DesktopContextMessageModel';
import type { DesktopContextMessage } from './DesktopContextMessageModel';
import type { DesktopChatTurnUsage, DesktopChatUsageSnapshot } from './DesktopChatUsageModel';
import { readDesktopTurnOutline } from './DesktopTurnOutlineModel';
import type { DesktopTurnOutlineEntry } from './DesktopTurnOutlineModel';
import type { DesktopTraceRow } from './DesktopTrajectoryLog';
import { DesktopGoal, DesktopGoalAction, DesktopGoalRef, DesktopGoalState } from './DesktopGoal';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopFeedback } from './DesktopFeedback';
import { DesktopActionCardState, desktopHideActionCardFences } from './DesktopActionCards';
import type { DesktopActionCard } from './DesktopActionCards';
import { DesktopTeamState } from './DesktopTeam';
import type { DesktopTeam } from './DesktopTeam';
import type { DesktopModelCatalog, DesktopModelCatalogResult } from './DesktopModelCatalog';
import { DesktopReplyTail, DesktopReplyTimeline } from './DesktopReplyTimeline';
import { DesktopWorkflowTimeline } from './DesktopWorkflowTimeline';
import type { DesktopWorkflowRun } from './DesktopWorkflowTimeline';
import { DesktopPromptQueue, DesktopQueuedPrompt } from './DesktopPromptQueue';
import { DesktopSubmissionEchoes } from './DesktopSubmissionEcho';
import type { DesktopSubmissionEcho } from './DesktopSubmissionEcho';
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
  turn?: number;
  message?: TrajectoryItem;
  userCopyText?: string;
  notice?: DesktopTranscriptNotice;
  compaction?: DesktopCompactionRow;
  contextMessage?: DesktopContextMessage;
  attachments?: DesktopMediaAttachment[];
  referenceLabels?: string[];
  plan?: DesktopPlanDocument;
  artifacts?: DesktopTurnArtifacts;
  process?: DesktopProcessGroup;
  cordis?: DesktopCordisCard;
  command?: DesktopCommandRecord;
  replyTail?: DesktopReplyTail;
  turnUsage?: DesktopChatTurnUsage;
  workflow?: DesktopWorkflowRun;
  inheritedHistory?: boolean;
}

export interface DesktopConversationSnapshot {
  sessionId: string;
  transcript: DesktopTranscriptItem[];
  turnOutline: DesktopTurnOutlineEntry[];
  chatUsage: DesktopChatUsageSnapshot;
  compactUsage: boolean;
  transcriptPolicy: DesktopTranscriptPolicy;
  transcriptTurns: DesktopTranscriptTurn[];
  submissionEchoes: DesktopSubmissionEcho[];
  loadTurnHistory: (sequence: number, requested: () => boolean) => Promise<boolean>;
  readTrajectory: () => DesktopTraceRow[];
  trajectoryRevision: number;
  trajectoryHasEarlier: boolean;
  wasPartialHistory: boolean;
  historyPaging: boolean;
  historyError: string;
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
  modelCatalog?: DesktopModelCatalog;
  modelError: string;
  permissions: DesktopPermissionOption[];
  permission: string;
  planMode?: boolean;
  goal?: DesktopGoal;
  selection?: ModelSelection;
  error: string;
  commands?: DesktopCommand[];
  commandLoading: boolean;
  commandError: string;
  feedbackRows: FeedbackRow[];
  actionCards: Map<number, DesktopActionCard>;
  team?: DesktopTeam;
  teamModelReady: boolean;
  teamModelUsed: boolean;
  queue: DesktopQueuedPrompt[];
  busyEnterSteers: boolean;
  subagent?: DesktopSubagentEntry;
  subagents: DesktopSubagentEntry[];
}

interface DraftRequest {
  signature: string;
  id: string;
}

export class DesktopConversation {
  private readonly cordis?: DesktopCordisRuntime;
  private readonly connection: Connection;
  private readonly host: DesktopHostActions;
  private readonly interactions: DesktopInteractions;
  private readonly listener: (snapshot: DesktopConversationSnapshot) => void;
  private readonly refreshSessions: () => void;
  private sessionId: string = '';
  private subagent?: DesktopSubagentEntry;
  private subagents: DesktopSubagentEntry[] = [];
  private subagentCatalogSequence: number = -1;
  private generation: number = 0;
  private closed: boolean = false;
  private stopFollow?: () => void;
  private timer: number = -1;
  private transcript: DesktopTranscriptItem[] = [];
  private readonly recallLabels: Map<number, string[]> = new Map();
  private readonly turnArtifacts: Map<number, DesktopTurnArtifacts> = new Map();
  private readonly toolLog: DesktopToolLog = new DesktopToolLog();
  private readonly trajectory: DesktopTrajectoryLog = new DesktopTrajectoryLog();
  private readonly chatUsage = new DesktopChatUsageState();
  private compactUsage: boolean = false;
  private transcriptPolicy: DesktopTranscriptPolicy = DEFAULT_DESKTOP_TRANSCRIPT_POLICY;
  private readonly transcriptTimeline = new DesktopTranscriptTurnTimeline();
  private readonly transcriptNotices = new DesktopTranscriptNoticeTimeline();
  private readonly compactions = new DesktopCompactionTimeline();
  private readonly contextMessages = new DesktopContextMessageTimeline();
  private turnOutline: DesktopTurnOutlineEntry[] = [];
  private turnOutlineSequence: number = -1;
  private latestTurn: number = 0;
  private latestTurnEvent: number = -1;
  private readonly loadTurnHistory = (sequence: number, requested: () => boolean): Promise<boolean> =>
    this.loadEarlierThrough(sequence, requested);
  private readonly readTrajectory: () => DesktopTraceRow[] = (): DesktopTraceRow[] => this.trajectory.rows();
  private readonly commandRecords: Map<string, DesktopCommandRecord> = new Map();
  private commands?: DesktopCommand[];
  private commandTask?: Promise<DesktopCommand[] | undefined>;
  private commandError: string = '';
  private commandVersion: number = 0;
  private planMode?: boolean;
  private planAsOf: number = -1;
  private questionsAsOf: number = -1;
  private readonly goals: DesktopGoalState = new DesktopGoalState();
  private readonly queue: DesktopPromptQueue = new DesktopPromptQueue();
  private readonly sending: Map<string, DesktopQueuedPrompt> = new Map<string, DesktopQueuedPrompt>();
  private readonly echoes = new DesktopSubmissionEchoes();
  private busyEnterSteers: boolean = false;
  private imageBytesLimit?: number;
  private readonly replyTimeline: DesktopReplyTimeline = new DesktopReplyTimeline();
  private readonly workflows: DesktopWorkflowTimeline = new DesktopWorkflowTimeline();
  private readonly actionCards: DesktopActionCardState = new DesktopActionCardState();
  private readonly team: DesktopTeamState = new DesktopTeamState();
  private inheritedSequence: number = -1;
  readonly feedback: DesktopFeedback;
  private modelCatalog?: DesktopModelCatalog;
  private modelRequest?: Promise<DesktopModelCatalogResult>;
  private modelError: string = '';
  private modelsLoading: boolean = false;
  private model?: ModelSelection;
  private modelSequence: number = -1;
  private readonly stopModelCatalogWatch: () => void;
  private error: string = '';
  private loading: boolean = false;
  private pageLoading: boolean = false;
  private hasEarlier: boolean = false;
  private wasPartialHistory: boolean = false;
  private historyError: string = '';
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
    refreshSessions: () => void, interactions: DesktopInteractions, host: DesktopHostActions,
    cordis?: DesktopCordisRuntime) {
    this.connection = connection;
    this.host = host;
    this.cordis = cordis;
    this.interactions = interactions;
    this.listener = listener;
    this.refreshSessions = refreshSessions;
    this.feedback = new DesktopFeedback(host, (): void => this.publish());
    this.stopModelCatalogWatch = host.watchModelCatalog((): void => {
      if (this.sessionId && !this.closed) { this.loadModels(); }
    });
  }

  async loadModels(refresh: boolean = false): Promise<void> {
    if (this.closed) { return; }
    const request = this.host.modelCatalog(refresh);
    if (request === this.modelRequest) { return; }
    const notify = refresh || this.modelRequest !== undefined;
    this.modelRequest = request;
    this.modelsLoading = true;
    this.modelError = '';
    if (notify) { this.publish(); }
    const response = await request;
    if (this.closed || this.modelRequest !== request) { return; }
    this.modelsLoading = false;
    this.modelError = response.problem;
    if (response.catalog !== undefined) { this.modelCatalog = response.catalog; }
    this.publish();
  }

  open(sessionId: string, subagent?: DesktopSubagentEntry): void {
    if (this.closed || sessionId === this.sessionId) {
      return;
    }
    const generation = ++this.generation;
    this.stopWatching();
    this.sessionId = sessionId;
    this.subagent = subagent;
    this.subagents = [];
    this.subagentCatalogSequence = -1;
    this.feedback.select(sessionId);
    this.actionCards.clear();
    this.team.clear();
    this.interactions.select(sessionId);
    this.transcript = [];
    this.turnOutline = [];
    this.turnOutlineSequence = -1;
    this.chatUsage.clear();
    this.transcriptTimeline.clear();
    this.transcriptNotices.clear();
    this.compactions.clear();
    this.contextMessages.clear();
    this.latestTurn = 0;
    this.latestTurnEvent = -1;
    this.trajectory.clear();
    this.recallLabels.clear();
    this.turnArtifacts.clear();
    this.toolLog.clear();
    this.commandRecords.clear();
    this.replyTimeline.clear();
    this.workflows.clear();
    this.inheritedSequence = -1;
    this.commandVersion++;
    this.commands = undefined;
    this.commandTask = undefined;
    this.commandError = '';
    this.planMode = undefined;
    this.planAsOf = -1;
    this.questionsAsOf = -1;
    this.goals.reset();
    this.queue.reset();
    this.imageBytesLimit = undefined;
    this.model = undefined;
    this.modelSequence = -1;
    this.permission = '';
    this.cursor = -1;
    this.earliest = -1;
    this.hasEarlier = false;
    this.wasPartialHistory = false;
    this.historyError = '';
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
    const args = sessionFollowPayload(this.address(), PAGE_MESSAGES, true);
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

  private address(): Object {
    const child = this.subagent;
    return child === undefined ? followSessionAddress(this.sessionId) : followSubagentAddress(child.parentId, child.id, child.mode);
  }

  close(): void {
    this.closed = true;
    this.stopModelCatalogWatch();
    this.feedback.select('');
    this.stopWatching();
    this.pendingRequests.clear();
    this.echoes.clear();
  }

  loadEarlier(): void {
    if (this.hasEarlier && !this.pageLoading) {
      this.loadPage(this.generation, true);
    }
  }

  private async loadEarlierThrough(sequence: number, requested: () => boolean): Promise<boolean> {
    const generation = this.generation;
    if (sequence < 0 || !this.current(generation)) { return false; }
    while (this.current(generation) && requested() && this.hasEarlier && !this.pageLoading && this.earliest > sequence) {
      const before = this.earliest;
      await this.loadPage(generation, true);
      if (this.earliest >= before) { break; }
    }
    return this.current(generation) && requested() && this.earliest >= 0 && this.earliest <= sequence;
  }

  async upload(sessionId: string, name: string, data: ArrayBuffer,
    mediaType: string, addressedChild?: DesktopSubagentEntry): Promise<DesktopDraftAttachment | string> {
    const current = sessionId === this.sessionId;
    const child = current ? this.subagent : addressedChild;
    if (child?.id === sessionId) {
      if (child.mode !== 'continuable' || (current && !this.historyLoaded)) { return '该子智能体会话为只读'; }
      if (!desktopImageMime(mediaType)) { return '子智能体会话支持图片附件'; }
      const id = 'child-image-' + randomUuid();
      const base64 = await new util.Base64Helper().encodeToString(new Uint8Array(data));
      return { receiptId: id, name: name, bytes: data.byteLength, mediaType: mediaType,
        picture: { id: id, name: name, bytes: data.byteLength, image: true,
          draftImageSource: `data:${mediaType};base64,${base64}` } };
    }
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
    if (sessionId !== this.sessionId) { return '当前会话已切换'; }
    const child = this.subagent;
    if (child !== undefined && (child.mode !== 'continuable' || !this.historyLoaded)) { return '该子智能体会话为只读'; }
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
    const parts: PromptContentPart[] = [];
    for (const file of attachments) {
      if (child === undefined) {
        parts.push(filePart(file.receiptId));
      } else {
        const prefix = `data:${file.mediaType};base64,`;
        const source = file.picture?.draftImageSource;
        if (!source?.startsWith(prefix) || source.length <= prefix.length) { return '无法读取子智能体图片附件'; }
        parts.push(imagePart(file.mediaType, source.slice(prefix.length), file.name));
      }
    }
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
    const files = attachments.map((attachment: DesktopDraftAttachment): DesktopMediaAttachment =>
      attachment.picture ?? { id: attachment.receiptId, name: attachment.name, bytes: attachment.bytes, image: false });
    if ((args !== undefined || child !== undefined) && (!busy || mode === PromptMode.STEER)) {
      const message = makeItem('submit-' + requestId, TrajectoryKind.MESSAGE, Date.now());
      message.speaker = Speaker.USER;
      message.body = text;
      this.echoes.begin({ sessionId: sessionId, requestId: requestId,
        placement: busy ? 'steering' : 'transcript', message: message, attachments: files });
    }
    if (child !== undefined) {
      let accepted = false;
      try {
        const result = await this.host.call('subagents/prompt', {
          'childSessionId': child.id, 'requestId': requestId, 'delivery': mode, 'content': parts
        });
        if (!result.ok || !getString(result.value, 'messageId')) { return this.failure(result, '宿主未确认发送'); }
        accepted = true;
        this.pendingRequests.delete(sessionId);
        if (sessionId === this.sessionId && !this.closed) { this.loadSelection(this.generation); }
        return '';
      } finally {
        this.settleSubmission(sessionId, requestId, accepted);
      }
    }
    if (args !== undefined && busy && mode === PromptMode.QUEUE) {
      this.sending.set(sessionId, { id: request.id, requestId: request.id, text: text,
        editable: false, attachments: files, sending: true });
      this.publish();
    }
    const generation = this.generation;
    let response: RpcResult | undefined;
    let accepted = false;
    try {
      response = args === undefined ? undefined : await this.connection.call(SESSION_PROMPT_ENDPOINT, args);
      accepted = response?.ok === true && projectSessionPrompt(response.value).accepted;
    } finally {
      this.settleSubmission(sessionId, requestId, accepted);
    }
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

  private settleSubmission(sessionId: string, requestId: string, accepted: boolean): void {
    const changed = accepted ? this.echoes.accept(requestId) : this.echoes.retire(requestId);
    if (changed && sessionId === this.sessionId && !this.closed) { this.publish(); }
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

  setPreferences(steers: boolean, compactUsage: boolean, transcriptPolicy: DesktopTranscriptPolicy): void {
    const previous = this.transcriptPolicy;
    if (this.busyEnterSteers === steers && this.compactUsage === compactUsage &&
      previous.displayMode === transcriptPolicy.displayMode && previous.collapseTiming === transcriptPolicy.collapseTiming &&
      previous.foldedReplies === transcriptPolicy.foldedReplies) { return; }
    this.busyEnterSteers = steers;
    this.compactUsage = compactUsage;
    this.transcriptPolicy = transcriptPolicy;
    this.publish();
  }

  async togglePlanMode(sessionId: string, enabled: boolean): Promise<string> {
    return this.executeCommand(sessionId, enabled ? '/plan' : '/plan off', []);
  }

  async setTeamMode(sessionId: string, enabled: boolean): Promise<string> {
    if (!sessionId || sessionId !== this.sessionId || this.subagent !== undefined || this.team.view === undefined ||
      !this.team.modelReady || this.closed) { return '当前会话暂不能更改团队协作设置'; }
    const generation = this.generation;
    const result = await this.host.call('agentTeams/setEnabled', { 'agentId': sessionId, 'enabled': enabled });
    if (this.current(generation)) { await this.loadSelection(generation); }
    return result.ok ? '' : this.failure(result, '宿主未确认团队协作设置');
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
    const child = sessionId === this.sessionId ? this.subagent : undefined;
    if (child !== undefined) {
      if (child.mode !== 'continuable' || !this.historyLoaded) { return '该子智能体会话为只读'; }
      const result = await this.host.call('subagents/interruptByUser', { 'childSessionId': child.id });
      return result.ok && getBoolean(result.value, 'accepted') === true ? '' : this.failure(result, '宿主未确认停止');
    }
    const args = sessionCancelPayload(sessionId);
    const response = args === undefined ? undefined : await this.connection.call(SESSION_CANCEL_ENDPOINT, args);
    return response?.ok && getBoolean(response.value, 'accepted') === true ? '' :
      this.failure(response, '宿主未确认停止');
  }

  async selectModel(sessionId: string, selection: ModelSelection): Promise<string> {
    if (!sessionId || this.sessionId !== sessionId || this.closed) { return '当前会话暂不可操作'; }
    const generation = this.generation;
    const modelSequence = this.modelSequence;
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
    if (this.current(generation) && this.modelSequence === modelSequence) {
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
    if (earlier) {
      this.historyError = '';
      this.publish();
    }
    const request: Record<string, Object> = {
      'address': this.address(), 'maxMessages': PAGE_MESSAGES
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
      if (earlier) { this.historyError = this.error; }
    }
    this.loading = false;
    this.publish();
  }

  private addRecords(records: Object[], merge: boolean, hasEarlier: boolean): boolean {
    const result: Map<string, DesktopTranscriptItem> = new Map<string, DesktopTranscriptItem>();
    let cordisResult = false;
    if (merge) {
      this.transcript.forEach((item: DesktopTranscriptItem): void => {
        if (item.artifacts === undefined && item.process === undefined && item.command === undefined && item.notice === undefined &&
          item.compaction === undefined && item.contextMessage === undefined &&
          item.replyTail === undefined && item.workflow === undefined && item.cordis === undefined && !item.inheritedHistory) {
          result.set(item.id, item);
        }
      });
    } else {
      this.recallLabels.clear();
      this.turnArtifacts.clear();
      this.toolLog.clear();
      this.trajectory.clear();
      this.chatUsage.resetWindow();
      this.transcriptTimeline.clear();
      this.transcriptNotices.clear();
      this.compactions.clear();
      this.contextMessages.clear();
      this.commandRecords.clear();
      this.replyTimeline.clear();
      this.latestTurn = 0;
      this.latestTurnEvent = -1;
      this.workflows.clear();
      this.inheritedSequence = -1;
    }
    const firstSequence = getNumber(getRecord(records[0], 'event'), 'seq') ?? -1;
    let loadedTurn = firstSequence > this.latestTurnEvent ? this.latestTurn : 0;
    for (const record of records) {
      const seq = getNumber(getRecord(record, 'event'), 'seq') ?? -1;
      if (seq >= 0 && (this.earliest < 0 || seq < this.earliest)) {
        this.earliest = seq;
      }
      const event = getRecord(record, 'event');
      this.echoes.observe(this.sessionId, event);
      const eventType = getString(event, 'type');
      const eventTurn = getNumber(getRecord(event, 'data'), 'turn') ?? 0;
      if (eventType === 'turn/start' && eventTurn > 0) { loadedTurn = eventTurn; }
      if (eventType === EVENT_TURN_END) { loadedTurn = 0; }
      if (seq > this.latestTurnEvent) {
        this.latestTurnEvent = seq;
        this.latestTurn = loadedTurn;
      }
      this.trajectory.observe(record, eventType, seq);
      this.chatUsage.observe(record);
      this.transcriptTimeline.observe(record);
      this.transcriptNotices.observe(record);
      this.compactions.observe(record);
      this.contextMessages.observe(record);
      if (eventType === EVENT_TURN_END || eventType === 'turn/start') {
        const turn = getNumber(getRecord(event, 'data'), 'turn') ?? 0;
        this.receivedTurn = Math.max(this.receivedTurn, eventType === EVENT_TURN_END ? turn : turn - 1);
      }
      observeDesktopArtifacts(this.turnArtifacts, event);
      cordisResult = this.toolLog.observe(record) || cordisResult;
      observeDesktopCommand(this.commandRecords, event);
      this.replyTimeline.observe(event);
      this.workflows.observe(event);
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
      if (eventType === 'user/message') {
        const source = getRecord(getRecord(event, 'data'), 'source');
        const kind = getString(source, 'kind');
        if (kind !== undefined && kind !== 'user') {
          const labels = desktopRecallLabels(source);
          if (seq > 0 && labels.length > 0) { this.recallLabels.set(seq - 1, labels); }
          continue;
        }
      }
      const message = projectWireRecord(record);
      const attachments = message?.speaker === Speaker.USER ?
        desktopMessageAttachments(getRecord(event, 'data')) : [];
      if (message !== undefined && message.kind === TrajectoryKind.MESSAGE && !message.internal && message.speaker !== Speaker.SYSTEM &&
        (message.body.length > 0 || message.reasoning.length > 0 || attachments.length > 0)) {
        if (message.speaker === Speaker.ASSISTANT) {
          this.replyTimeline.observe(event, message.body);
          message.body = desktopHideActionCardFences(message.body);
        }
        if (message.body.trim() || message.reasoning || attachments.length > 0) {
          result.set(message.id, { id: message.id, sequence: seq,
            turn: eventTurn || loadedTurn || undefined, message: message, attachments: attachments,
            userCopyText: message.speaker === Speaker.USER ? desktopUserMessageCopyText(getRecord(event, 'data')) : undefined });
        }
      }
    }
    this.turnArtifacts.forEach((row: DesktopTurnArtifacts): void => {
      if (row.closeSequence >= 0 && (row.files.length > 0 || row.changeSequence >= 0 || row.applied.length > 0)) {
        const id = `artifacts:${this.sessionId}:${row.turn}:${row.changeSequence}:${row.files.length}:${row.applied.length}`;
        result.set(id, { id: id, sequence: row.closeSequence, artifacts: row });
      }
    });
    const processes = this.toolLog.groups();
    this.trajectory.setProcesses(processes);
    for (const process of processes) {
      let pending: DesktopToolStep[] = [];
      for (const step of process.steps) {
        if (step.cordis === undefined) { pending.push(step); continue; }
        this.addProcess(result, process, pending);
        pending = [];
        const id = 'cordis:' + this.sessionId + ':' + step.id;
        result.set(id, { id: id, sequence: step.cordis.sequence, cordis: step.cordis });
      }
      this.addProcess(result, process, pending);
    }
    this.commandRecords.forEach((command: DesktopCommandRecord): void => {
      if (command.sequence >= 0 && command.name && !this.compactions.hasManualCheckpoint(command.id)) {
        const id = `command:${this.sessionId}:${command.id}`;
        result.set(id, { id: id, sequence: command.sequence, command: command });
      }
    });
    for (const checkpoint of this.compactions.rows()) {
      const id = `compaction:${this.sessionId}:${checkpoint.id}`;
      result.set(id, { id: id, sequence: checkpoint.sequence, compaction: checkpoint, turn: checkpoint.turn });
    }
    for (const context of this.contextMessages.rows()) {
      const id = `context:${this.sessionId}:${context.id}`;
      result.set(id, { id: id, sequence: context.sequence, contextMessage: context, turn: context.turn });
    }
    const closingMessages: Map<number, number> = new Map();
    for (const replyTail of this.replyTimeline.completed()) {
      const id = `reply:${this.sessionId}:${replyTail.turn}:${replyTail.messageId}`;
      result.set(id, { id: id, sequence: replyTail.endSeq, replyTail: replyTail,
        turnUsage: this.chatUsage.turnUsage(replyTail.turn) });
      closingMessages.set(replyTail.turn, replyTail.messageSeq);
    }
    for (const notice of this.transcriptNotices.notices()) {
      const id = `notice:${this.sessionId}:${notice.id}`;
      result.set(id, { id: id, sequence: desktopTranscriptNoticeSequence(notice, closingMessages.get(notice.turn)),
        turn: notice.turn, notice: notice });
    }
    for (const workflow of this.workflows.runs()) {
      const id = 'workflow:' + workflow.id;
      result.set(id, { id: id, sequence: workflow.sequence, workflow: workflow });
    }
    if (this.inheritedSequence >= 0) {
      result.set('inherited-history', { id: 'inherited-history', sequence: this.inheritedSequence, inheritedHistory: true });
    }
    const ordered = Array.from(result.values()).sort((a: DesktopTranscriptItem, b: DesktopTranscriptItem): number =>
      a.sequence - b.sequence);
    const transcript: DesktopTranscriptItem[] = [];
    for (const current of ordered) {
      const tail = transcript[transcript.length - 1];
      const previous = tail?.process;
      const process = current.process;
      if (tail !== undefined && previous !== undefined && process !== undefined && previous.turn === process.turn) {
        tail.process = { id: previous.id, sequence: previous.sequence, turn: previous.turn,
          version: previous.version + ':' + process.version, steps: [...previous.steps, ...process.steps] };
      } else {
        current.referenceLabels = current.message?.speaker === Speaker.USER ? this.recallLabels.get(current.sequence) : undefined;
        transcript.push(current);
      }
    }
    this.transcript = transcript;
    this.hasEarlier = hasEarlier;
    this.wasPartialHistory = this.wasPartialHistory || hasEarlier;
    return cordisResult;
  }

  private addProcess(result: Map<string, DesktopTranscriptItem>, group: DesktopProcessGroup,
    steps: DesktopToolStep[]): void {
    if (steps.length === 0) { return; }
    const id = `process:${this.sessionId}:${steps[0].id}`;
    result.set(id, { id: id, sequence: steps[0].sequence, process: {
      id: steps[0].id, sequence: steps[0].sequence, turn: group.turn, version: group.version, steps: steps
    } });
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
        const subagentsChanged = this.readSubagents(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? -1);
        this.readQuestions(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? -1);
        this.readImageLimit(getRecord(result.value, 'values'));
        const goalChanged = this.readGoal(result.value);
        const queueChanged = this.readQueue(result.value);
        const cardsChanged = this.actionCards.observe(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? 0);
        const teamChanged = this.team.observe(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? 0);
        const modelChanged = this.observeModel(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? 0);
        const outlineChanged = this.readTurnOutline(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? -1);
        const usageChanged = this.chatUsage.readProjection(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? -1);
        if (this.readPlan(result.value) || goalChanged || queueChanged || subagentsChanged || cardsChanged || teamChanged ||
          modelChanged || outlineChanged || usageChanged) {
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

  private readQuestions(values: Object | undefined, sequence: number): void {
    const questions = getRecord(values, 'userQuestions');
    if (questions === undefined || sequence <= this.questionsAsOf) { return; }
    this.questionsAsOf = sequence;
    this.interactions.observeQuestions(this.sessionId, questions);
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

  private readTurnOutline(values: Object | undefined, sequence: number): boolean {
    if (this.turnOutlineSequence >= 0 && sequence <= this.turnOutlineSequence) { return false; }
    const outline = readDesktopTurnOutline(values);
    if (outline === undefined) { return false; }
    this.turnOutlineSequence = sequence;
    this.turnOutline = outline;
    return true;
  }

  private readProjection(projection: Object | undefined): void {
    const values = getRecord(projection, 'values');
    this.readQuestions(values, getNumber(projection, 'asOfSeq') ?? -1);
    this.readTurnOutline(values, getNumber(projection, 'asOfSeq') ?? -1);
    this.chatUsage.readProjection(values, getNumber(projection, 'asOfSeq') ?? -1);
    this.readPlan(projection);
    this.readGoal(projection);
    this.readQueue(projection);
    this.actionCards.observe(values, getNumber(projection, 'asOfSeq') ?? 0);
    this.team.observe(values, getNumber(projection, 'asOfSeq') ?? 0);
    this.readSubagents(values, getNumber(projection, 'asOfSeq') ?? -1);
    this.readImageLimit(values);
    this.observeModel(values, getNumber(projection, 'asOfSeq') ?? 0);
    this.permission = getString(getRecord(values, 'permissions'), 'currentValue') ?? '';
    if (this.permission.length > 0) {
      this.loadPermissions();
    }
  }

  private observeModel(values: Object | undefined, sequence: number): boolean {
    const projection = getRecord(values, 'modelSelection');
    if (projection === undefined || sequence <= this.modelSequence) { return false; }
    this.modelSequence = sequence;
    this.model = this.readModel(getRecord(projection, Object.keys(projection).includes('next') ? 'next' : 'lastUsed'));
    return true;
  }

  private readSubagents(values: Object | undefined, sequence: number): boolean {
    let changed = false;
    const child = this.subagent;
    const identity = getRecord(values, 'subagent');
    const mode = desktopSubagentMode(getString(identity, 'mode'));
    if (child?.mode === 'unknown' && (mode === 'one-shot' || mode === 'continuable')) {
      this.subagent = { id: child.id, parentId: child.parentId, mode: mode,
        label: child.label || getString(identity, 'label') || '', name: child.name, createdAt: child.createdAt };
      changed = true;
    }
    if (sequence >= 0 && sequence <= this.subagentCatalogSequence) { return changed; }
    const catalog = desktopSubagentCatalog(this.sessionId, values);
    if (catalog === undefined) { return changed; }
    this.subagentCatalogSequence = sequence;
    this.subagents = catalog;
    return true;
  }

  private readGoal(projection?: Object): boolean {
    const changed = this.goals.observeProjection(projection);
    if (changed && !this.goals.goal?.activation) { this.readGoalActivation(); }
    return changed;
  }

  private readQueue(projection?: Object): boolean {
    return this.readInbox(getRecord(projection, 'values'), getNumber(projection, 'asOfSeq') ?? -1);
  }

  private readInbox(values: Object | undefined, sequence: number): boolean {
    const echoesChanged = this.echoes.observeInbox(this.sessionId, values, sequence);
    return this.queue.observe(values, sequence) || echoesChanged;
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
      this.readQuestions(changes, getNumber(frame, 'seq') ?? -1);
      this.readImageLimit(changes);
      const queueChanged = this.readInbox(changes, getNumber(frame, 'seq') ?? -1);
      const subagentsChanged = this.readSubagents(changes, getNumber(frame, 'seq') ?? -1);
      const cardsChanged = this.actionCards.observe(changes, getNumber(frame, 'seq') ?? 0);
      const teamChanged = this.team.observe(changes, getNumber(frame, 'seq') ?? 0);
      const modelChanged = this.observeModel(changes, getNumber(frame, 'seq') ?? 0);
      const outlineChanged = this.readTurnOutline(changes, getNumber(frame, 'seq') ?? -1);
      const usageChanged = this.chatUsage.readProjection(changes, getNumber(frame, 'seq') ?? -1);
      if (!goalChanged && !queueChanged && !subagentsChanged && !cardsChanged && !teamChanged && !modelChanged &&
        !outlineChanged && !usageChanged) { return; }
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
      if (this.addRecords([frame], true, this.hasEarlier)) { this.cordis?.refresh(); }
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
        this.error = '';
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
    const selection = this.model ?? this.modelCatalog?.defaultModel;
    const sending = this.sending.get(this.sessionId);
    const queue = sending !== undefined && !this.queue.rows.some((row: DesktopQueuedPrompt): boolean =>
      row.requestId === sending.requestId) ? [...this.queue.rows, sending] : this.queue.rows;
    this.listener({
      sessionId: this.sessionId, transcript: this.transcript, partial: desktopHideActionCardFences(this.partial),
      turnOutline: this.turnOutline, loadTurnHistory: this.loadTurnHistory,
      chatUsage: this.chatUsage.stats(), compactUsage: this.compactUsage,
      transcriptPolicy: this.transcriptPolicy, transcriptTurns: this.transcriptTimeline.turns(),
      submissionEchoes: this.echoes.forSession(this.sessionId),
      readTrajectory: this.readTrajectory, trajectoryRevision: this.trajectory.version(),
      trajectoryHasEarlier: this.hasEarlier, wasPartialHistory: this.wasPartialHistory,
      historyPaging: this.pageLoading && !this.loading, historyError: this.historyError,
      preparingTool: this.preparingTool, loading: this.loading,
      hasEarlier: this.hasEarlier && !this.pageLoading, running: this.running, waitingForInput: this.waitingForInput,
      historyLoaded: this.historyLoaded, receivedTurn: this.receivedTurn,
      models: this.modelCatalog?.models ?? [], modelsLoading: this.modelsLoading, modelCatalog: this.modelCatalog,
      modelError: this.modelError, selection: selection, error: this.error,
      permissions: this.permission.length > 0 ? this.permissions : [], permission: this.permission,
      planMode: this.planMode,
      goal: this.goals.goal,
      commands: this.commands, commandLoading: this.commandTask !== undefined, commandError: this.commandError,
      feedbackRows: this.feedback.rows, actionCards: this.actionCards.cards, queue: queue, busyEnterSteers: this.busyEnterSteers,
      team: this.team.view, teamModelReady: this.team.modelReady, teamModelUsed: this.team.lastModelUsed,
      subagent: this.subagent, subagents: this.subagents
    });
  }
}
