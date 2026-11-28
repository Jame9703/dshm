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
import { Connection, ConnectionState, getArray, getBoolean, getField, getNumber, getRecord, getString, randomUuid,
  stringifyJson, toStringArray } from 'connection';
import type { RpcResult, StreamSink } from 'connection';
import {
  argsFor, COMMANDS_EXECUTE_ENDPOINT, EVENT_TURN_END, mayChangeSessionTitle, SESSION_CANCEL_ENDPOINT, SESSION_FOLLOW_ENDPOINT,
  SESSION_PAGE_ENDPOINT, SESSION_PROMPT_ENDPOINT, SESSION_SELECT_MODEL_ENDPOINT, SESSION_UPDATE_QUEUE_ENDPOINT
} from 'dshcompat';

import { desktopRecallLabels } from './DesktopReferences';
import type { DesktopSkill } from './DesktopSkills';
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
import { DesktopQuestionHistory } from './DesktopQuestionHistory';
import type { DesktopQuestionHistoryRow } from './DesktopQuestionHistory';
import type { DesktopChatTurnUsage, DesktopChatUsageSnapshot } from './DesktopChatUsageModel';
import { readDesktopTurnOutline } from './DesktopTurnOutlineModel';
import type { DesktopTurnOutlineEntry } from './DesktopTurnOutlineModel';
import type { DesktopTraceRow } from './DesktopTrajectoryLog';
import { DesktopGoal, DesktopGoalAction, DesktopGoalRef, DesktopGoalState } from './DesktopGoal';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopTimelineValue, readDesktopTimelineActiveTree } from './DesktopTimelineModel';
import type { DesktopTimelineSource, DesktopTimelineTree } from './DesktopTimelineModel';
import { DesktopFeedback } from './DesktopFeedback';
import { DesktopActionCardState, desktopHideActionCardFences } from './DesktopActionCards';
import type { DesktopActionCard } from './DesktopActionCards';
import { DesktopTeamState } from './DesktopTeam';
import type { DesktopTeam } from './DesktopTeam';
import type { DesktopModelCatalog, DesktopModelCatalogResult } from './DesktopModelCatalog';
import { DesktopReplyTail, DesktopReplyTimeline } from './DesktopReplyTimeline';
import { DesktopWorkflowTimeline } from './DesktopWorkflowTimeline';
import type { DesktopWorkflowRun } from './DesktopWorkflowTimeline';
import { DesktopPromptQueue, DesktopQueuedPrompt, desktopQueuedPromptPreview, desktopVisiblePromptQueue } from './DesktopPromptQueue';
import { DesktopSubmissionEchoes } from './DesktopSubmissionEcho';
import type { DesktopSubmissionEcho } from './DesktopSubmissionEcho';
import { desktopImageMime, desktopMediaAttachment, desktopMessageAttachments } from './DesktopAttachments';
import type { DesktopDraftAttachment, DesktopMediaAttachment } from './DesktopAttachments';
import { commandInvocation, desktopCommandCatalog, DesktopCommand, DesktopCommandRecord, observeDesktopCommand,
  resolveDesktopCommand } from './DesktopCommands';

const STATE_ENDPOINT: string = 'session/state';
const PROJECTIONS_ENDPOINT: string = 'session/projections';
const PAGE_MESSAGES: number = 50;
const FOLLOW_OPENING_GRACE_MS: number = 180;
const STREAM_PRESENTATION_INTERVAL_MS: number = 16;

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
  interrupted?: boolean;
  userCopyText?: string;
  humanPrompt?: boolean;
  notice?: DesktopTranscriptNotice;
  compaction?: DesktopCompactionRow;
  contextMessage?: DesktopContextMessage;
  questionReply?: DesktopQuestionHistoryRow;
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
  readApprovalCommand?: (callId: string) => string | undefined;
  readQuestionHistory?: (callId: string) => DesktopQuestionHistoryRow | undefined;
  trajectoryRevision: number;
  trajectoryHasEarlier: boolean;
  wasPartialHistory: boolean;
  historyPaging: boolean;
  historyError: string;
  historyRepair?: 'loading' | 'failed';
  retryHistoryRepair?: () => void;
  partial: string;
  preparingTool: string;
  loading: boolean;
  hasEarlier: boolean;
  running: boolean;
  runningPaused: boolean;
  runningHolding: boolean;
  runningStartedAt?: number;
  continuationSequence: number;
  historyLoaded: boolean;
  timeline?: DesktopTimelineSource;
  timelineTree?: DesktopTimelineTree;
  timelineLinkLost: boolean;
  timelineCommandOpen: number;
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
  skills?: DesktopSkill[];
  skillsLoading: boolean;
  skillError: boolean;
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

interface DesktopOpeningWindow {
  cursor: number;
  hasMore: boolean;
  records: Object[];
}

interface DesktopHistoryGap {
  first: number;
  before: number;
  failed: boolean;
}

interface DesktopHistoryGapPage {
  records: Object[];
  before: number;
  hasMore: boolean;
}

export class DesktopConversation {
  private readonly cordis?: DesktopCordisRuntime;
  private readonly connection: Connection;
  private readonly host: DesktopHostActions;
  private readonly interactions: DesktopInteractions;
  private readonly listener: (snapshot: DesktopConversationSnapshot) => void;
  private readonly refreshSessions: () => void;
  private readonly onLiveTurnEnd: (sessionId: string, frame: Object) => void;
  private sessionId: string = '';
  private subagent?: DesktopSubagentEntry;
  private subagents: DesktopSubagentEntry[] = [];
  private subagentCatalogSequence: number = -1;
  private generation: number = 0;
  private closed: boolean = false;
  private stopFollow?: () => void;
  private followVersion: number = 0;
  private openingTimer: number = -1;
  private openingHistoryPending: boolean = false;
  private openingProjectionPending: boolean = false;
  private waitingForFollowSnapshot: boolean = false;
  private openingWindow?: DesktopOpeningWindow;
  private latestPageLoading: boolean = false;
  private fullProjectionCursor: number = -1;
  private timer: number = -1;
  private transcript: DesktopTranscriptItem[] = [];
  private readonly recallLabels: Map<number, string[]> = new Map();
  private readonly turnArtifacts: Map<number, DesktopTurnArtifacts> = new Map();
  private readonly toolLog: DesktopToolLog = new DesktopToolLog();
  private readApprovalCommand?: (callId: string) => string | undefined;
  private readonly trajectory: DesktopTrajectoryLog = new DesktopTrajectoryLog();
  private readonly chatUsage = new DesktopChatUsageState();
  private compactUsage: boolean = false;
  private transcriptPolicy: DesktopTranscriptPolicy = DEFAULT_DESKTOP_TRANSCRIPT_POLICY;
  private readonly transcriptTimeline = new DesktopTranscriptTurnTimeline();
  private readonly transcriptNotices = new DesktopTranscriptNoticeTimeline();
  private readonly compactions = new DesktopCompactionTimeline();
  private readonly contextMessages = new DesktopContextMessageTimeline();
  private readonly questionHistory = new DesktopQuestionHistory();
  private readQuestionHistory?: (callId: string) => DesktopQuestionHistoryRow | undefined;
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
  private skills?: DesktopSkill[];
  private skillsTask?: Promise<DesktopSkill[] | undefined>;
  private skillError: boolean = false;
  private planMode?: boolean;
  private planAsOf: number = -1;
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
  private latestRecord: number = -1;
  private readonly historyGaps: DesktopHistoryGap[] = [];
  private historyGapTask?: Promise<void>;
  private historyGapFollowVersion: number = -1;
  private readonly retryHistoryRepair = (): void => {
    if (this.clearFailedHistoryGaps()) { this.publish(); }
    this.repairHistoryGaps(this.generation);
  };
  private cursor: number = -1;
  private followCursor: number = -1;
  private earliest: number = -1;
  private running: boolean = false;
  private runningPaused: boolean = false;
  private streamPresentationTimer: number = -1;
  private continuationSequence: number = -1;
  private continuationAsOf: number = -1;
  private nextStepHuman: boolean = false;
  private nextStepAsOf: number = -1;
  private historyLoaded: boolean = false;
  private timeline?: DesktopTimelineSource;
  private timelineSequence: number = -2;
  private timelineTree?: DesktopTimelineTree;
  private timelineLinkLost: boolean = false;
  private stopTimeline?: () => void;
  private timelineRetryTimer: number = -1;
  private timelineRetries: number = 0;
  private timelineWatchVersion: number = 0;
  private timelineCommandOpen: number = 0;
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
    cordis?: DesktopCordisRuntime,
    onLiveTurnEnd: (sessionId: string, frame: Object) => void = (_sessionId: string, _frame: Object): void => {}) {
    this.connection = connection;
    this.host = host;
    this.cordis = cordis;
    this.interactions = interactions;
    this.listener = listener;
    this.refreshSessions = refreshSessions;
    this.onLiveTurnEnd = onLiveTurnEnd;
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
    this.readApprovalCommand = (callId: string): string | undefined =>
      this.current(generation) ? this.toolLog.approvalCommand(callId) : undefined;
    this.questionHistory.clear();
    this.questionHistory.select(sessionId);
    this.readQuestionHistory = (callId: string): DesktopQuestionHistoryRow | undefined =>
      this.current(generation) ? this.questionHistory.detail(callId) : undefined;
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
    this.skills = undefined;
    this.skillsTask = undefined;
    this.skillError = false;
    this.planMode = undefined;
    this.planAsOf = -1;
    this.goals.reset();
    this.queue.reset();
    this.imageBytesLimit = undefined;
    this.model = undefined;
    this.modelSequence = -1;
    this.permission = '';
    this.cursor = -1;
    this.followCursor = -1;
    this.earliest = -1;
    this.hasEarlier = false;
    this.wasPartialHistory = false;
    this.historyError = '';
    this.latestRecord = -1;
    this.historyGaps.length = 0;
    this.historyGapTask = undefined;
    this.historyGapFollowVersion = -1;
    this.loading = sessionId.length > 0;
    this.pageLoading = false;
    this.latestPageLoading = false;
    this.fullProjectionCursor = -1;
    this.error = '';
    this.running = false;
    this.runningPaused = false;
    this.continuationSequence = -1;
    this.continuationAsOf = -1;
    this.nextStepHuman = false;
    this.nextStepAsOf = -1;
    this.historyLoaded = false;
    this.timeline = undefined;
    this.timelineTree = undefined;
    this.timelineLinkLost = false;
    this.timelineRetries = 0;
    this.timelineSequence = -2;
    this.timelineCommandOpen = 0;
    this.receivedTurn = 0;
    this.waitingForInput = false;
    this.attempt = '';
    this.partial = '';
    this.preparingTool = '';
    this.publish();
    if (sessionId.length === 0) {
      return;
    }
    this.openFollow(generation);
    this.loadModels();
    this.pollState(generation);
  }

  reconnect(): void {
    if (!this.closed && this.sessionId && this.stopFollow === undefined) {
      this.openFollow(this.generation);
    }
    if (!this.closed && this.timeline !== undefined && this.stopTimeline === undefined) { this.retryTimeline(); }
  }

  private openFollow(generation: number): void {
    this.openingHistoryPending = true;
    this.openingProjectionPending = true;
    this.openingWindow = undefined;
    const args = sessionFollowPayload(this.address(), PAGE_MESSAGES, true);
    if (args !== undefined) {
      this.waitingForFollowSnapshot = true;
      const version = ++this.followVersion;
      const sink: StreamSink = {
        onItem: (frame: Object): void => {
          if (version === this.followVersion && this.current(generation)) {
            this.onFrame(frame);
          }
        },
        onError: (): void => { if (version === this.followVersion) { this.followEnded(generation); } },
        onEnd: (): void => { if (version === this.followVersion) { this.followEnded(generation); } }
      };
      this.stopFollow = this.connection.openStream(SESSION_FOLLOW_ENDPOINT, args, sink);
    }
    if (this.stopFollow === undefined) {
      this.waitingForFollowSnapshot = false;
      this.readOpeningFallback(generation);
    } else if (this.waitingForFollowSnapshot) {
      this.openingTimer = setTimeout((): void => {
        this.openingTimer = -1;
        this.readOpeningFallback(generation);
      }, FOLLOW_OPENING_GRACE_MS);
    }
  }

  private clearOpeningTimer(): void {
    clearTimeout(this.openingTimer);
    this.openingTimer = -1;
  }

  private readOpeningFallback(generation: number): void {
    if (!this.current(generation) || this.openingTimer >= 0) { return; }
    if (this.openingHistoryPending && !this.pageLoading) {
      this.openingHistoryPending = false;
      this.loadPage(generation, false);
    }
    if (this.openingProjectionPending) {
      this.openingProjectionPending = false;
      this.loadSelection(generation);
    }
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
    if (sequence < 0 || !this.current(generation) || !requested()) { return false; }
    const gap = this.historyGaps.find((range: DesktopHistoryGap): boolean => sequence >= range.first && sequence < range.before);
    if (gap !== undefined) {
      this.retryHistoryRepair();
      await this.historyGapTask;
      if (!this.current(generation) || (this.historyGaps.includes(gap) && sequence < gap.before)) { return false; }
    }
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
    const generation = this.generation;
    if ((args !== undefined || child !== undefined) && busy && mode === PromptMode.QUEUE) {
      this.sending.set(sessionId, { id: requestId, requestId: requestId, text: text, preview: desktopQueuedPromptPreview(text),
        editable: false, attachments: files, sending: true });
      this.publish();
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
        if (this.current(generation) && !this.sending.has(sessionId)) { this.loadSelection(generation); }
        return '';
      } finally {
        this.settleSubmission(sessionId, requestId, accepted);
        await this.finishQueuedSubmission(sessionId, requestId, generation, accepted);
      }
    }
    let response: RpcResult | undefined;
    let accepted = false;
    try {
      response = args === undefined ? undefined : await this.connection.call(SESSION_PROMPT_ENDPOINT, args);
      accepted = response?.ok === true && projectSessionPrompt(response.value).accepted;
    } finally {
      this.settleSubmission(sessionId, requestId, accepted);
      await this.finishQueuedSubmission(sessionId, requestId, generation, accepted);
    }
    if (accepted) {
      this.pendingRequests.delete(sessionId);
      return '';
    }
    return this.failure(response, '宿主未确认发送');
  }

  private async finishQueuedSubmission(sessionId: string, requestId: string, generation: number,
    accepted: boolean): Promise<void> {
    if (this.sending.get(sessionId)?.requestId !== requestId) { return; }
    try {
      if (accepted && this.current(generation) &&
        !this.queue.rows.some((row: DesktopQueuedPrompt): boolean => row.requestId === requestId)) {
        await this.loadSelection(generation);
      }
    } finally {
      if (this.sending.get(sessionId)?.requestId === requestId) {
        this.sending.delete(sessionId);
        if (this.sessionId === sessionId) { this.publish(); }
      }
    }
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

  async loadSkills(sessionId: string): Promise<void> {
    if (this.closed || this.sessionId !== sessionId || this.subagent !== undefined || !this.historyLoaded ||
      this.skills !== undefined || this.skillsTask !== undefined) { return; }
    const generation = this.generation;
    const task = this.host.sessionSkills(sessionId);
    this.skillsTask = task;
    this.skillError = false;
    this.publish();
    const skills = await task;
    if (!this.current(generation) || this.skillsTask !== task) { return; }
    this.skillsTask = undefined;
    this.skills = skills;
    this.skillError = skills === undefined;
    this.publish();
  }

  invalidateSkills(sessionId?: string): void {
    if (sessionId !== undefined && sessionId !== this.sessionId) { return; }
    if (this.skills === undefined && this.skillsTask === undefined && !this.skillError) { return; }
    this.skills = undefined;
    this.skillsTask = undefined;
    this.skillError = false;
    this.loadSkills(this.sessionId);
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
      if (commandInvocation(line)?.token === 'timeline' && this.current(generation) && this.sessionId === sessionId) {
        this.timelineCommandOpen++;
        this.publish();
      }
    }
    return '';
  }

  async cancel(sessionId: string): Promise<string> {
    if (this.closed || sessionId !== this.sessionId) { return '当前会话已切换'; }
    const child = this.subagent;
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

  private canContinue(): boolean {
    return !this.running && this.historyLoaded && this.subagent === undefined && this.continuationSequence >= 0 &&
      this.queue.rows.length === 0 && !this.nextStepHuman && this.echoes.forSession(this.sessionId).length === 0;
  }

  async continueGeneration(sessionId: string, sequence: number): Promise<string> {
    if (this.closed || sessionId !== this.sessionId || sequence !== this.continuationSequence || !this.canContinue()) {
      return '本轮已无法继续生成';
    }
    const generation = this.generation;
    const signature = 'continue:' + sequence;
    let request = this.pendingRequests.get(sessionId);
    if (request?.signature !== signature) {
      request = { signature: signature, id: 'req-' + randomUuid() };
      this.pendingRequests.set(sessionId, request);
    }
    const args = promptPayload(request.id, sessionId, PromptMode.QUEUE, [], '');
    const response = args === undefined ? undefined : await this.connection.call(SESSION_PROMPT_ENDPOINT, args);
    if (response?.ok !== true || !projectSessionPrompt(response.value).accepted) {
      return this.failure(response, '宿主未确认继续生成');
    }
    this.pendingRequests.delete(sessionId);
    if (this.current(generation) && this.continuationSequence === sequence) {
      this.continuationSequence = -1;
      this.publish();
    }
    return '';
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
    this.stopTimelineWatch();
    this.stopFollow?.();
    this.stopFollow = undefined;
    this.clearOpeningTimer();
    this.openingHistoryPending = false;
    this.openingProjectionPending = false;
    this.waitingForFollowSnapshot = false;
    this.openingWindow = undefined;
    clearTimeout(this.streamPresentationTimer);
    this.streamPresentationTimer = -1;
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private followEnded(generation: number): void {
    if (this.current(generation)) {
      this.stopFollow = undefined;
      this.waitingForFollowSnapshot = false;
      this.clearOpeningTimer();
      if (!this.latestPageLoading) { this.openingWindow = undefined; }
      this.attempt = '';
      this.preparingTool = '';
      this.runningPaused = true;
      this.readOpeningFallback(generation);
      this.publish();
    }
  }

  private async loadPage(generation: number, earlier: boolean): Promise<void> {
    if (!this.current(generation) || this.pageLoading) { return; }
    this.pageLoading = true;
    this.latestPageLoading = !earlier;
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
    this.latestPageLoading = false;
    if (result?.ok) {
      const page: SessionPageValue = projectSessionPage(result.value);
      this.historyLoaded = true;
      const cursor = getNumber(result.value, 'cursor') ?? -1;
      if (earlier || cursor >= this.cursor) {
        if (!earlier && this.stopFollow === undefined && this.partial && page.records.some((record: Object): boolean => {
          const event = getRecord(record, 'event');
          const type = getString(event, 'type');
          return (getNumber(event, 'seq') ?? -1) > this.cursor &&
            (type === 'assistant/message' || type === 'turn/start' || type === EVENT_TURN_END);
        })) {
          this.partial = '';
        }
        if (earlier) {
          this.addRecords(page.records, true, page.hasMore);
        } else {
          this.applyLatestWindow(cursor, page.records, page.hasMore, this.waitingForFollowSnapshot);
        }
      }
      this.error = '';
    } else if (this.loading || earlier) {
      this.error = this.failure(result, '无法读取会话记录');
      if (earlier) { this.historyError = this.error; }
    }
    this.loading = false;
    if (!this.waitingForFollowSnapshot) { this.openingWindow = undefined; }
    this.publish();
    this.readOpeningFallback(generation);
  }

  private applyLatestWindow(cursor: number, records: Object[], hasMore: boolean, awaitingCounterpart: boolean): void {
    const prior = this.openingWindow;
    this.openingWindow = awaitingCounterpart ? { cursor: cursor, hasMore: hasMore, records: records } : undefined;
    if (prior !== undefined && prior.cursor === cursor && prior.hasMore === hasMore &&
      this.sameHistoryRecords(prior.records, records)) {
      // A submission receipt can arrive after the first copy of a record.
      for (const record of records) { this.echoes.observe(this.sessionId, getRecord(record, 'event')); }
      return;
    }
    const first = getNumber(getRecord(records[0], 'event'), 'seq') ?? -1;
    if (this.latestRecord >= 0 && first > this.latestRecord + 1) {
      this.historyGaps.push({ first: this.latestRecord + 1, before: first, failed: false });
    }
    this.latestRecord = Math.max(this.latestRecord, getNumber(getRecord(records[records.length - 1], 'event'), 'seq') ?? -1);
    const retainEarlier = this.earliest >= 0 && (first < 0 || first > this.earliest ||
      (first === this.earliest && !this.hasEarlier));
    this.addRecords(records, !this.loading, retainEarlier ? this.hasEarlier : hasMore);
    this.cursor = Math.max(this.cursor, cursor);
    this.repairHistoryGaps(this.generation);
  }

  private clearFailedHistoryGaps(): boolean {
    let changed = false;
    for (const gap of this.historyGaps) {
      if (gap.failed) {
        gap.failed = false;
        changed = true;
      }
    }
    return changed;
  }

  private repairHistoryGaps(generation: number): void {
    if (this.historyGapTask !== undefined || !this.current(generation) ||
      !this.historyGaps.some((gap: DesktopHistoryGap): boolean => !gap.failed)) { return; }
    const task = this.fillHistoryGaps(generation);
    this.historyGapTask = task;
    task.then((): void => {
      if (this.historyGapTask === task) { this.historyGapTask = undefined; }
    });
  }

  private async fillHistoryGaps(generation: number): Promise<void> {
    while (this.current(generation)) {
      const gap = this.historyGaps.find((range: DesktopHistoryGap): boolean => !range.failed);
      if (gap === undefined) { return; }
      const followVersion = this.historyGapFollowVersion;
      const request: Record<string, Object> = {
        'address': this.address(), 'maxMessages': PAGE_MESSAGES, 'beforeSeq': gap.before
      };
      const args = argsFor(SESSION_PAGE_ENDPOINT, request);
      const result = args === undefined ? undefined : await this.connection.call(SESSION_PAGE_ENDPOINT, args);
      if (!this.current(generation)) { return; }
      const page = result?.ok ? this.boundedHistoryPage(result.value, gap) : undefined;
      if (page === undefined) {
        // A healthy replacement stream can arrive while the failed request is in flight.
        if (followVersion !== this.historyGapFollowVersion) { continue; }
        gap.failed = true;
      } else {
        if (this.addRecords(page.records, true, this.hasEarlier)) { this.cordis?.refresh(); }
        gap.before = page.before;
        if (gap.before === gap.first) {
          this.historyGaps.splice(this.historyGaps.indexOf(gap), 1);
        } else if (!page.hasMore) {
          gap.failed = true;
        }
      }
      this.publish();
    }
  }

  private boundedHistoryPage(value: Object | undefined, gap: DesktopHistoryGap): DesktopHistoryGapPage | undefined {
    const records = getArray(value, 'records');
    const hasMore = getBoolean(value, 'hasMore');
    if (records === undefined || hasMore === undefined) { return undefined; }
    let expected = gap.before - 1;
    let start = records.length;
    // Bounded page cursors can point past the page. Check the events themselves.
    while (start > 0 && expected >= gap.first) {
      const sequence = getNumber(getRecord(records[start - 1], 'event'), 'seq');
      if (sequence !== expected) { return undefined; }
      start--;
      expected--;
    }
    if (start === records.length) { return undefined; }
    return { records: records.slice(start), before: expected + 1, hasMore: hasMore };
  }

  private sameHistoryRecords(prior: Object[], records: Object[]): boolean {
    if (prior.length !== records.length) { return false; }
    for (let index = 0; index < records.length; index++) {
      if (prior[index] === records[index]) { continue; }
      const encoded = stringifyJson(prior[index]);
      if (encoded === undefined || encoded !== stringifyJson(records[index])) { return false; }
    }
    return true;
  }

  private addRecords(records: Object[], merge: boolean, hasEarlier: boolean): boolean {
    const result: Map<string, DesktopTranscriptItem> = new Map<string, DesktopTranscriptItem>();
    let cordisResult = false;
    if (merge) {
      this.transcript.forEach((item: DesktopTranscriptItem): void => {
        if (item.artifacts === undefined && item.process === undefined && item.command === undefined && item.notice === undefined &&
          item.compaction === undefined && item.contextMessage === undefined && item.questionReply === undefined &&
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
      this.questionHistory.resetRecords();
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
      if (!this.questionHistory.observe(record)) { this.contextMessages.observe(record); }
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
      let humanPrompt = false;
      if (eventType === 'user/message') {
        const source = getRecord(getRecord(event, 'data'), 'source');
        const kind = getString(source, 'kind');
        if (kind !== undefined && kind !== 'user') {
          const labels = desktopRecallLabels(source);
          if (seq > 0 && labels.length > 0) { this.recallLabels.set(seq - 1, labels); }
          continue;
        }
        humanPrompt = kind === 'user';
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
            interrupted: message.speaker === Speaker.ASSISTANT && getBoolean(getRecord(event, 'data'), 'interrupted') === true,
            humanPrompt: humanPrompt,
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
    for (const reply of this.questionHistory.rows()) {
      result.set(reply.id, { id: reply.id, sequence: reply.sequence, turn: reply.turn, questionReply: reply });
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
        // Both groups were created by this transcript rebuild and have not been published yet.
        previous.version += ':' + process.version;
        for (const step of process.steps) { previous.steps.push(step); }
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
      const projectionCursor = getNumber(result.value, 'asOfSeq');
      if (projectionCursor !== undefined && projectionCursor < this.fullProjectionCursor) { return; }
      if (this.model === undefined) {
        this.readProjection(result.value);
        this.publish();
      } else {
        const values = getRecord(result.value, 'values');
        const sequence = projectionCursor ?? -1;
        if (values !== undefined) { this.fullProjectionCursor = Math.max(this.fullProjectionCursor, sequence); }
        const timelineChanged = this.readTimeline(values, sequence);
        const continuationChanged = this.readContinuation(values, sequence);
        const subagentsChanged = this.readSubagents(values, sequence);
        const questionsChanged = this.readQuestions(values, sequence);
        this.readImageLimit(getRecord(result.value, 'values'));
        const goalChanged = this.readGoal(result.value);
        const queueChanged = this.readQueue(result.value);
        const cardsChanged = this.actionCards.observe(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? 0);
        const teamChanged = this.team.observe(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? 0);
        const modelChanged = this.observeModel(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? 0);
        const outlineChanged = this.readTurnOutline(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? -1);
        const usageChanged = this.chatUsage.readProjection(getRecord(result.value, 'values'), getNumber(result.value, 'asOfSeq') ?? -1);
        if (this.readPlan(result.value) || goalChanged || queueChanged || questionsChanged || subagentsChanged || cardsChanged || teamChanged ||
          modelChanged || outlineChanged || usageChanged || continuationChanged || timelineChanged) {
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
      const cursor = getNumber(response.value, 'cursor') ?? -1;
      const currentState = cursor < 0 || cursor >= this.followCursor;
      const resumed = this.stopFollow === undefined && this.runningPaused;
      if (resumed) { this.runningPaused = false; }
      if (currentState && (resumed || active !== this.running || waiting !== this.waitingForInput)) {
        this.running = active;
        this.waitingForInput = waiting;
        this.publish();
      }
      if (this.stopFollow === undefined && cursor > this.cursor && !this.pageLoading) {
        this.loadPage(generation, false);
        this.loadSelection(generation);
      }
    } else if (this.stopFollow === undefined) {
      if (!this.runningPaused) {
        this.runningPaused = true;
        this.publish();
      }
      if (!this.pageLoading) { this.loadPage(generation, false); }
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

  private readQuestions(values: Object | undefined, sequence: number): boolean {
    this.interactions.observeQuestions(this.sessionId, values, sequence);
    const previous = this.questionHistory.rows();
    if (!this.questionHistory.observeProjection(values, sequence)) { return false; }
    const rows = this.questionHistory.rows();
    if (rows !== previous) {
      const transcript = this.transcript.filter((item: DesktopTranscriptItem): boolean => item.questionReply === undefined);
      for (const row of rows) {
        transcript.push({ id: row.id, sequence: row.sequence, turn: row.turn, questionReply: row });
      }
      this.transcript = transcript.sort((a: DesktopTranscriptItem, b: DesktopTranscriptItem): number =>
        a.sequence - b.sequence);
    }
    return true;
  }

  private readTurnOutline(values: Object | undefined, sequence: number): boolean {
    if (this.turnOutlineSequence >= 0 && sequence <= this.turnOutlineSequence) { return false; }
    const outline = readDesktopTurnOutline(values);
    if (outline === undefined) { return false; }
    this.turnOutlineSequence = sequence;
    this.turnOutline = outline;
    return true;
  }

  private readTimeline(values: Object | undefined, sequence: number): boolean {
    if (values === undefined || !Number.isSafeInteger(sequence) || sequence <= this.timelineSequence) { return false; }
    return this.acceptTimeline(getRecord(values, 'timeline'), sequence);
  }

  private acceptTimeline(view: Object | undefined, sequence: number): boolean {
    if (sequence <= this.timelineSequence) { return false; }
    this.timelineSequence = sequence;
    if (this.timeline?.value === view) { return false; }
    this.timeline = view === undefined ? undefined : { sequence: sequence, value: view };
    this.timelineTree = readDesktopTimelineActiveTree(view);
    if (view === undefined) { this.stopTimelineWatch(); }
    else { this.watchTimeline(this.generation); }
    return true;
  }

  async removeTimelineDraft(owner: string, id: string): Promise<boolean> {
    if (this.closed || owner !== this.sessionId || this.timelineTree?.id !== id || this.running ||
        this.sending.has(owner) || this.queue.rows.length > 0 || this.latestTurn > 0) { return false; }
    const generation = this.generation;
    const payload: Record<string, Object> = { 'action': 'remove', 'sessionId': owner, 'tree': id, 'draft': true };
    const reply = await this.host.editTimeline(payload);
    if (!this.current(generation)) { return false; }
    const ok = reply.ok && getString(reply.value, 'action') === 'remove' && getBoolean(reply.value, 'draft') === true;
    if (reply.ok) { await this.loadSelection(generation); }
    return ok;
  }

  retryTimeline(): void {
    this.stopTimelineWatch();
    this.timelineRetries = 0;
    this.watchTimeline(this.generation);
  }

  private stopTimelineWatch(): void {
    this.timelineWatchVersion++;
    const stop = this.stopTimeline;
    this.stopTimeline = undefined;
    stop?.();
    if (this.timelineRetryTimer >= 0) { clearTimeout(this.timelineRetryTimer); this.timelineRetryTimer = -1; }
  }

  private watchTimeline(generation: number): void {
    if (!this.current(generation) || this.timeline === undefined || this.stopTimeline !== undefined ||
        this.timelineRetryTimer >= 0 || this.timelineRetries > 3) { return; }
    const owner = this.sessionId;
    const version = ++this.timelineWatchVersion;
    const current = (): boolean => this.current(generation) && version === this.timelineWatchVersion;
    const ended = (): void => {
      if (!current()) { return; }
      this.stopTimelineWatch();
      this.timelineLinkLost = true;
      this.timelineRetries++;
      if (this.timelineRetries <= 3) {
        this.timelineRetryTimer = setTimeout((): void => {
          this.timelineRetryTimer = -1;
          this.watchTimeline(generation);
        }, 1200 * this.timelineRetries);
      }
      this.publish();
    };
    const address: Record<string, Object> = { 'sessionId': owner };
    const sink: StreamSink = {
      onItem: (frame: Object): void => {
        if (!current()) { return; }
        if (getString(frame, 'type') === 'ready') {
          this.timelineRetries = 0;
          if (this.timelineLinkLost) { this.timelineLinkLost = false; this.publish(); }
          // The projection stream starts after the opening snapshot. This read covers the intervening events.
          this.loadSelection(generation);
        } else {
          const update = desktopTimelineValue(frame);
          if (update !== undefined && this.acceptTimeline(update.value, update.sequence)) { this.publish(); }
        }
      },
      onError: ended,
      onEnd: ended
    };
    this.stopTimeline = this.host.watch('session/observeProjections', address, sink);
    if (this.stopTimeline === undefined) { ended(); }
  }

  private readProjection(projection: Object | undefined): void {
    const values = getRecord(projection, 'values');
    const sequence = getNumber(projection, 'asOfSeq');
    if (sequence !== undefined && sequence < this.fullProjectionCursor) { return; }
    if (values !== undefined && sequence !== undefined) {
      this.fullProjectionCursor = Math.max(this.fullProjectionCursor, sequence);
    }
    if (sequence !== undefined) { this.readTimeline(values, sequence); }
    this.readQuestions(values, getNumber(projection, 'asOfSeq') ?? -1);
    this.readTurnOutline(values, getNumber(projection, 'asOfSeq') ?? -1);
    this.chatUsage.readProjection(values, getNumber(projection, 'asOfSeq') ?? -1);
    this.readContinuation(values, getNumber(projection, 'asOfSeq') ?? -1);
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
    const inbox = getField(values, 'inbox');
    let nextStepChanged = false;
    if (inbox !== undefined && sequence >= this.nextStepAsOf) {
      this.nextStepAsOf = sequence;
      const human = getArray(inbox, 'next-step')?.some((message: Object): boolean =>
        getString(getRecord(message, 'source'), 'kind') === 'user') ?? false;
      nextStepChanged = this.nextStepHuman !== human;
      this.nextStepHuman = human;
    }
    return this.queue.observe(values, sequence) || echoesChanged || nextStepChanged;
  }

  private readContinuation(values: Object | undefined, sequence: number): boolean {
    const value = getField(values, 'conversationContinuation');
    if (value === undefined || sequence <= this.continuationAsOf) { return false; }
    this.continuationAsOf = sequence;
    const eligible = typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : -1;
    const changed = eligible !== this.continuationSequence;
    this.continuationSequence = eligible;
    return changed;
  }

  private onFrame(frame: Object): void {
    const type = getString(frame, 'type');
    if (type === 'snapshot') {
      if (!this.readFollowSnapshot(frame)) { return; }
    } else if (type === 'projection') {
      const goalChanged = this.goals.observeDelta(frame);
      const changes = getRecord(frame, 'changes');
      const continuationChanged = this.readContinuation(changes, getNumber(frame, 'seq') ?? -1);
      const questionsChanged = this.readQuestions(changes, getNumber(frame, 'seq') ?? -1);
      this.readImageLimit(changes);
      const queueChanged = this.readInbox(changes, getNumber(frame, 'seq') ?? -1);
      const subagentsChanged = this.readSubagents(changes, getNumber(frame, 'seq') ?? -1);
      const cardsChanged = this.actionCards.observe(changes, getNumber(frame, 'seq') ?? 0);
      const teamChanged = this.team.observe(changes, getNumber(frame, 'seq') ?? 0);
      const modelChanged = this.observeModel(changes, getNumber(frame, 'seq') ?? 0);
      const outlineChanged = this.readTurnOutline(changes, getNumber(frame, 'seq') ?? -1);
      const usageChanged = this.chatUsage.readProjection(changes, getNumber(frame, 'seq') ?? -1);
      if (!goalChanged && !queueChanged && !questionsChanged && !subagentsChanged && !cardsChanged && !teamChanged && !modelChanged &&
        !outlineChanged && !usageChanged && !continuationChanged) { return; }
      if (goalChanged && !this.goals.goal?.activation) { this.readGoalActivation(); }
    } else if (type === 'event') {
      const event = getRecord(frame, 'event');
      const eventType = getString(event, 'type');
      const sequence = getNumber(event, 'seq') ?? -1;
      const appended = sequence > this.followCursor;
      if (!appended) {
        // Late records can enrich history without replaying their live side effects.
        if (this.addRecords([frame], true, this.hasEarlier)) { this.cordis?.refresh(); }
        this.publish();
        return;
      }
      this.runningPaused = false;
      this.followCursor = Math.max(this.followCursor, sequence);
      if (eventType === 'tool/call' || eventType === EVENT_TURN_END || eventType === 'assistant/message') {
        this.preparingTool = '';
      }
      if (eventType?.startsWith('user-question/') || eventType === 'tool/result' || eventType === 'user/message' ||
        eventType === 'plan/mode' || eventType === 'command/done' || eventType === 'goal/change') {
        this.loadSelection(this.generation);
      }
      this.latestRecord = Math.max(this.latestRecord, sequence);
      this.cursor = Math.max(this.cursor, sequence);
      if (this.addRecords([frame], true, this.hasEarlier)) { this.cordis?.refresh(); }
      if (eventType === EVENT_TURN_END || (eventType !== undefined && mayChangeSessionTitle(eventType))) {
        this.refreshSessions();
      }
      if (eventType === 'turn/start') {
        this.error = '';
        this.running = true;
        if (sequence >= this.continuationAsOf) {
          this.continuationAsOf = sequence;
          this.continuationSequence = -1;
        }
      } else if (eventType === EVENT_TURN_END) {
        this.running = false;
        this.waitingForInput = false;
        this.partial = '';
        this.attempt = '';
        this.error = '';
        this.onLiveTurnEnd(this.sessionId, frame);
      } else if (eventType === 'assistant/message') {
        this.partial = '';
        this.attempt = '';
      }
    } else if (type === 'assistant-stream') {
      const update = getRecord(frame, 'frame');
      const kind = getString(update, 'type');
      if (kind === 'start') {
        this.runningPaused = false;
        this.running = true;
        this.attempt = getString(update, 'attemptId') ?? '';
        this.partial = '';
        this.preparingTool = '';
      } else if (this.attempt.length > 0 && getString(update, 'attemptId') === this.attempt) {
        const chunk = getRecord(update, 'chunk');
        if (kind === 'chunk') {
          const chunkType = getString(chunk, 'type');
          const delta = getString(chunk, 'text') ?? '';
          const name = getString(chunk, 'name') ?? '';
          if (chunkType === 'text-delta' && delta) { this.partial += delta; }
          else if (chunkType === 'tool-call-delta' && name && name !== this.preparingTool) { this.preparingTool = name; }
          else { return; }
          if (this.streamPresentationTimer < 0) {
            this.streamPresentationTimer = setTimeout((): void => { this.publish(); }, STREAM_PRESENTATION_INTERVAL_MS);
          }
          return;
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

  private readFollowSnapshot(frame: Object): boolean {
    const session = getString(getRecord(frame, 'header'), 'id');
    if (session && session !== this.sessionId) { return false; }
    this.waitingForFollowSnapshot = false;
    this.clearOpeningTimer();
    const cursor = getNumber(frame, 'cursor');
    const validCursor = cursor !== undefined && Number.isSafeInteger(cursor) && cursor >= -1;
    const liveCursor = validCursor && cursor >= this.followCursor && cursor >= this.cursor;
    const records = getArray(frame, 'records');
    const hasMore = getBoolean(frame, 'hasMore');
    if (validCursor && records !== undefined && hasMore !== undefined) {
      if (cursor >= this.cursor) {
        if (this.historyGapFollowVersion !== this.followVersion) {
          this.historyGapFollowVersion = this.followVersion;
          this.clearFailedHistoryGaps();
        }
        this.applyLatestWindow(cursor, records, hasMore, this.latestPageLoading);
        this.repairHistoryGaps(this.generation);
        this.historyLoaded = true;
        this.loading = false;
        this.error = '';
      }
      if (this.historyLoaded) { this.openingHistoryPending = false; }
      this.followCursor = Math.max(this.followCursor, cursor);
    }
    const projection = getRecord(frame, 'projections');
    const asOf = getNumber(projection, 'asOfSeq');
    if (getRecord(projection, 'values') !== undefined && asOf !== undefined && Number.isSafeInteger(asOf) && asOf >= -1) {
      this.openingProjectionPending = false;
      this.readProjection(projection);
    }
    if (liveCursor) {
      this.runningPaused = false;
      const stream = getRecord(frame, 'assistantStream');
      if (stream !== undefined) { this.readAssistantBaseline(stream); }
    }
    if (!this.latestPageLoading) { this.openingWindow = undefined; }
    this.readOpeningFallback(this.generation);
    return true;
  }

  private readAssistantBaseline(stream: Object): void {
    const pending = getRecord(stream, 'activeAttempt');
    this.attempt = getString(pending, 'attemptId') ?? '';
    this.partial = '';
    this.preparingTool = '';
    if (pending === undefined) { return; }
    for (const entry of getArray(pending, 'stream') ?? []) {
      if (getString(entry, 'type') === 'text-chunks') {
        this.partial += toStringArray(getArray(entry, 'texts') ?? []).join('');
      }
    }
    this.running = true;
  }

  private publish(): void {
    clearTimeout(this.streamPresentationTimer);
    this.streamPresentationTimer = -1;
    if (this.closed) {
      return;
    }
    const selection = this.model ?? this.modelCatalog?.defaultModel;
    const sending = this.sending.get(this.sessionId);
    const submissionEchoes = this.echoes.forSession(this.sessionId);
    const queue = desktopVisiblePromptQueue(this.queue.rows, submissionEchoes, sending);
    const transcriptTurns = this.transcriptTimeline.turns();
    const latestTurn = transcriptTurns[transcriptTurns.length - 1];
    const openTurn = latestTurn !== undefined && latestTurn.startSequence >= 0 && latestTurn.endSequence < 0;
    const connectionState = this.connection.getState();
    this.listener({
      sessionId: this.sessionId, transcript: this.transcript, partial: desktopHideActionCardFences(this.partial),
      turnOutline: this.turnOutline, loadTurnHistory: this.loadTurnHistory,
      chatUsage: this.chatUsage.stats(), compactUsage: this.compactUsage,
      transcriptPolicy: this.transcriptPolicy, transcriptTurns: transcriptTurns,
      submissionEchoes: submissionEchoes,
      readTrajectory: this.readTrajectory, trajectoryRevision: this.trajectory.version(),
      readApprovalCommand: this.readApprovalCommand,
      readQuestionHistory: this.readQuestionHistory,
      trajectoryHasEarlier: this.hasEarlier, wasPartialHistory: this.wasPartialHistory,
      historyPaging: this.pageLoading && !this.loading, historyError: this.historyError,
      historyRepair: this.historyGaps.length === 0 ? undefined :
        (this.historyGaps.some((gap: DesktopHistoryGap): boolean => !gap.failed) ? 'loading' : 'failed'),
      retryHistoryRepair: this.retryHistoryRepair,
      preparingTool: this.preparingTool, loading: this.loading,
      hasEarlier: this.hasEarlier && !this.pageLoading, running: this.running, waitingForInput: this.waitingForInput,
      runningPaused: this.runningPaused || connectionState === ConnectionState.CONNECTING ||
        connectionState === ConnectionState.DISCONNECTED,
      runningStartedAt: openTurn && latestTurn.startTime > 0 ? latestTurn.startTime : undefined,
      runningHolding: !this.running && openTurn,
      continuationSequence: this.canContinue() && sending === undefined ? this.continuationSequence : -1,
      historyLoaded: this.historyLoaded, timeline: this.timeline, timelineTree: this.timelineTree,
      timelineLinkLost: this.timelineLinkLost, timelineCommandOpen: this.timelineCommandOpen,
      receivedTurn: this.receivedTurn,
      models: this.modelCatalog?.models ?? [], modelsLoading: this.modelsLoading, modelCatalog: this.modelCatalog,
      modelError: this.modelError, selection: selection, error: this.error,
      permissions: this.permission.length > 0 ? this.permissions : [], permission: this.permission,
      planMode: this.planMode,
      goal: this.goals.goal,
      commands: this.commands, commandLoading: this.commandTask !== undefined, commandError: this.commandError,
      skills: this.skills, skillsLoading: this.skillsTask !== undefined, skillError: this.skillError,
      feedbackRows: this.feedback.rows, actionCards: this.actionCards.cards, queue: queue, busyEnterSteers: this.busyEnterSteers,
      team: this.team.view, teamModelReady: this.team.modelReady, teamModelUsed: this.team.lastModelUsed,
      subagent: this.subagent, subagents: this.subagents
    });
  }
}
