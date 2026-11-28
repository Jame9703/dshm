import type { ModelSelection, QueueActionBody, SessionListItem } from 'appstate';
import { DesktopConversationPane } from './DesktopConversationPane';
import type { DesktopReplyMedia } from './DesktopReplyMedia';
import { getString } from 'connection';
import { EMPTY_DESKTOP_DRAFT, sameDesktopDraft } from './DesktopDraftReferences';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopReferenceAction } from './DesktopReferenceActions';
import { desktopReferenceText } from './DesktopReferences';
import type { DesktopFileReferenceOffer } from './DesktopReferenceActions';
import type { DesktopConversation, DesktopConversationSnapshot } from './DesktopConversation';
import type { DesktopDockConversation, DesktopWorkspaceData } from './DesktopWorkspaceData';
import type { DesktopDraftAttachment, DesktopMediaAttachment } from './DesktopAttachments';
import type { DesktopComposerDraft } from './DesktopDraftReferences';
import type { DesktopDockChatTarget } from './DesktopRightDock';
import type { DesktopDroppedFiles } from './DesktopAttachmentIntake';
import type { DesktopInteraction, DesktopQuestionAnswer } from './DesktopInteractions';
import type { DesktopQuestionProgress } from './DesktopQuestionDrafts';
import type { DesktopGoalAction, DesktopGoalRef } from './DesktopGoal';
import type { DesktopSubagentEntry } from './DesktopSubagents';
import type { DesktopPlanDocument } from './DesktopPlan';
import type { DesktopChangeTarget } from './DesktopArtifacts';
import type { DesktopRating } from './DesktopFeedback';
import { DEFAULT_DESKTOP_TYPOGRAPHY } from './DesktopTheme';
import type { DesktopTypography } from './DesktopTheme';

export interface DesktopDockChatActions {
  run: (id: string, operation: (id: string) => Promise<string>) => Promise<string>;
  stop: (id: string, conversation: DesktopConversation) => Promise<string>;
  readDraft: (id: string) => DesktopComposerDraft;
  writeDraft: (id: string, draft: DesktopComposerDraft) => void;
  readAttachments: (id: string) => DesktopDraftAttachment[];
  writeAttachments: (id: string, files: DesktopDraftAttachment[]) => void;
  pickAttachments: (id: string, conversation: DesktopConversation) => Promise<string>;
  dropAttachments: (id: string, conversation: DesktopConversation, files: DesktopDroppedFiles) => Promise<string>;
  pasteAttachments: (id: string, conversation: DesktopConversation) => Promise<string>;
  openMain: (target: DesktopDockChatTarget, title: string) => void;
  openTimeline: (target: DesktopDockChatTarget, title: string, tree: string, task: string) => void;
  openChild: (child: DesktopSubagentEntry, parents: DesktopSubagentEntry[], aside: boolean) => void;
  openParent: (child: DesktopSubagentEntry) => void;
  openImage: (id: string, image: DesktopMediaAttachment) => void;
  openFile: (id: string, path: string, name: string) => void;
  openLink: (href: string) => void;
  systemFile: (id: string, path: string, name: string, reveal: boolean) => void;
  referenceFile: (id: string, action: DesktopReferenceAction, path: string, name: string) => void;
  openPlan: (id: string, plan: DesktopPlanDocument) => void;
  openCompaction: (target: DesktopDockChatTarget, sequence: number, isCurrent: () => boolean) => Promise<ResourceStr | undefined>;
  openChanges: (target: DesktopChangeTarget) => void;
  openModels: () => void;
  openPlugin: (name: string, title: string, description: string) => void;
  openWeb: (id: string) => void;
  copy: (id: string) => void;
  exportLog: (id: string) => Promise<string>;
  feedback: (id: string, conversation: DesktopConversation) => Promise<string>;
  rate: (id: string, messageId: string, rating: DesktopRating, conversation: DesktopConversation) => void;
  fork: (id: string, sequence: number, conversation: DesktopConversation) => void;
}

@Component
export struct DesktopDockChatPane {
  data?: DesktopWorkspaceData;
  actions?: DesktopDockChatActions;
  replyMedia?: DesktopReplyMedia;
  @Prop target: DesktopDockChatTarget | undefined = undefined;
  @Prop title: string = '';
  @Prop directory: string = '';
  @Prop appearance: string = 'system';
  @Prop typography: DesktopTypography = DEFAULT_DESKTOP_TYPOGRAPHY;
  @Prop timelineDecimals: number = 2;
  @Prop timelineSegmented: boolean = true;
  @Prop @Watch('syncVisibility') shown: boolean = false;
  @Prop busy: boolean = false;
  @Prop stopping: boolean = false;
  @Prop forking: boolean = false;
  @Prop summaries: SessionListItem[] = [];
  @State private snapshot?: DesktopConversationSnapshot = undefined;
  @State private interactions: DesktopInteraction[] = [];
  @State private draft: DesktopComposerDraft = EMPTY_DESKTOP_DRAFT;
  @State private attachments: DesktopDraftAttachment[] = [];
  @State private problem: string = '';
  @State private referenceOffer?: DesktopFileReferenceOffer = undefined;
  private binding?: DesktopDockConversation;
  private generation: number = 0;

  aboutToAppear(): void { this.syncVisibility(); }
  aboutToDisappear(): void { this.release(); }

  private release(): void {
    this.generation++;
    const binding = this.binding;
    this.binding = undefined;
    binding?.close();
  }

  private syncVisibility(): void {
    const target = this.target;
    if (!this.shown || target === undefined) {
      this.release();
      this.snapshot = undefined;
      this.referenceOffer = undefined;
      return;
    }
    if (this.binding !== undefined) { return; }
    const generation = ++this.generation;
    this.problem = '';
    this.draft = this.actions?.readDraft(target.id) ?? EMPTY_DESKTOP_DRAFT;
    this.attachments = this.actions?.readAttachments(target.id) ?? [];
    this.binding = this.data?.createDockConversation((snapshot: DesktopConversationSnapshot): void => {
      if (generation !== this.generation || snapshot.sessionId !== target.id) { return; }
      const previous = this.snapshot?.timelineCommandOpen ?? 0;
      this.snapshot = snapshot;
      if (snapshot.timelineCommandOpen > previous) { this.actions?.openTimeline(target, this.title, '', ''); }
    }, (items: DesktopInteraction[]): void => {
      if (generation === this.generation) { this.interactions = items; }
    });
    this.binding?.conversation.open(target.id, target.subagent);
  }

  private async run(operation: (binding: DesktopDockConversation, sessionId: string) => Promise<string>): Promise<string> {
    const binding = this.binding;
    const id = this.target?.id ?? '';
    const actions = this.actions;
    if (binding === undefined || !id || actions === undefined) { return '当前会话暂不可操作'; }
    const generation = this.generation;
    this.problem = '';
    const problem = await actions.run(id, (session: string): Promise<string> => operation(binding, session));
    if (generation === this.generation) {
      this.problem = problem;
      this.attachments = actions.readAttachments(id);
    }
    return problem;
  }

  private changeDraft(id: string, draft: DesktopComposerDraft): void {
    if (id !== this.target?.id) { return; }
    this.draft = draft;
    this.actions?.writeDraft(id, draft);
  }

  private async stopMessage(): Promise<void> {
    const binding = this.binding;
    const id = this.target?.id;
    if (binding === undefined || !id) { return; }
    const issue = await this.actions?.stop(id, binding.conversation);
    if (this.binding === binding && issue) { this.problem = issue; }
  }

  private send(alternate: boolean): void {
    const sent = this.draft;
    const files = this.attachments;
    const actions = this.actions;
    if (actions === undefined || (!sent.text.trim() && files.length === 0)) { return; }
    this.run(async (binding: DesktopDockConversation, id: string): Promise<string> => {
      const generation = this.generation;
      const result = await binding.conversation.send(id, sent.text, files, actions.exportLog,
        (session: string): Promise<string> => actions.feedback(session, binding.conversation), alternate);
      if (!result) {
        if (sameDesktopDraft(actions.readDraft(id), sent)) {
          actions.writeDraft(id, EMPTY_DESKTOP_DRAFT);
          if (generation === this.generation) { this.draft = EMPTY_DESKTOP_DRAFT; }
        }
        const sentIds = new Set(files.map((file: DesktopDraftAttachment): string => file.receiptId));
        actions.writeAttachments(id, actions.readAttachments(id)
          .filter((file: DesktopDraftAttachment): boolean => !sentIds.has(file.receiptId)));
      }
      return result;
    });
  }

  private async reference(action: DesktopReferenceAction, path: string, name: string): Promise<void> {
    const id = this.target?.id;
    if (!id || !this.shown) { return; }
    if (action !== DesktopReferenceAction.ADD_TO_CHAT) {
      this.actions?.referenceFile(id, action, path, name);
      return;
    }
    const generation = this.generation;
    const result = await this.data?.actions.call('workspaceFiles/stat', { 'workspaceFileScopeId': id, 'path': path });
    if (generation !== this.generation) { return; }
    const absolute = getString(result?.value, 'absolutePath') ?? '';
    if (result?.ok === true && absolute.startsWith('/') && desktopReferenceText(absolute, false, true)) {
      this.referenceOffer = { sessionId: id, path: absolute };
    } else {
      this.problem = '无法添加此文件引用';
    }
  }

  build() {
    Column() {
      if (this.snapshot !== undefined && this.target !== undefined) {
        DesktopConversationPane({ host: this.data?.actions, cordis: this.data?.cordis, replyMedia: this.replyMedia,
          snapshot: this.snapshot, embedded: true,
          timelineDecimals: this.timelineDecimals, timelineSegmented: this.timelineSegmented,
          onTimelineDockToggle: (owner: string, tree: string): void => {
            const target = this.target;
            if (target !== undefined && owner === target.id) { this.actions?.openTimeline(target, this.title, tree, ''); }
          },
          onTimelineDockRemove: (owner: string, tree: string): Promise<boolean> =>
            this.binding?.conversation.removeTimelineDraft(owner, tree) ?? Promise.resolve(false),
          onTimelineReceipt: (owner: string, tree: string, task: string): void => {
            const target = this.target;
            if (target !== undefined && target.id === owner) { this.actions?.openTimeline(target, this.title, tree, task); }
          },
          title: this.title, sessionDirectory: this.directory, appearance: this.appearance, typography: this.typography,
          sessionSummaries: this.summaries, interactions: this.interactions, busy: this.busy, stopping: this.stopping,
          forking: this.forking,
          referenceOffer: this.referenceOffer,
          draft: this.draft, attachments: this.attachments, commandError: this.problem,
          menuOptions: desktopMenuOptions(Placement.BottomLeft),
          onOpenMain: (): void => { if (this.target !== undefined) { this.actions?.openMain(this.target, this.title); } },
          onSubagent: (child: DesktopSubagentEntry, parents: DesktopSubagentEntry[]): void => {
            this.actions?.openChild(child, parents, false);
          },
          onSubagentAside: (child: DesktopSubagentEntry, parents: DesktopSubagentEntry[]): void => {
            this.actions?.openChild(child, parents, true);
          },
          onSubagentParent: (child: DesktopSubagentEntry): void => { this.actions?.openParent(child); },
          onDraft: (id: string, draft: DesktopComposerDraft): void => this.changeDraft(id, draft),
          onSend: (alternate: boolean): void => this.send(alternate),
          onStop: (): void => { this.stopMessage(); },
          onContinue: (sequence: number): void => {
            if (!this.draft.text.trim() && this.attachments.length === 0) {
              this.run((binding, id): Promise<string> => binding.conversation.continueGeneration(id, sequence));
            }
          },
          onEarlier: (): void => { this.binding?.conversation.loadEarlier(); },
          onAddAttachment: (): void => { this.run((binding, id): Promise<string> =>
            this.actions?.pickAttachments(id, binding.conversation) ?? Promise.resolve('')); },
          onDropAttachments: (files: DesktopDroppedFiles): void => { this.run((binding, id): Promise<string> =>
            this.actions?.dropAttachments(id, binding.conversation, files) ?? Promise.resolve('')); },
          onPasteAttachments: (): void => { this.run((binding, id): Promise<string> =>
            this.actions?.pasteAttachments(id, binding.conversation) ?? Promise.resolve('')); },
          onRemoveAttachment: (receipt: string): void => {
            this.attachments = this.attachments.filter((item: DesktopDraftAttachment): boolean => item.receiptId !== receipt);
            this.actions?.writeAttachments(this.target?.id ?? '', this.attachments);
          },
          onOpenImage: (row: DesktopMediaAttachment): void => { this.actions?.openImage(this.target?.id ?? '', row); },
          onLink: (href: string): void => { this.actions?.openLink(href); },
          onArtifactFile: (path: string, name: string): void => { this.actions?.openFile(this.target?.id ?? '', path, name); },
          onArtifactAction: (path: string, name: string, reveal: boolean): void => {
            this.actions?.systemFile(this.target?.id ?? '', path, name, reveal);
          },
          onReferenceFileAction: (action: DesktopReferenceAction, path: string, name: string): void => {
            this.reference(action, path, name);
          },
          onPlanPreview: (plan: DesktopPlanDocument): void => { this.actions?.openPlan(this.target?.id ?? '', plan); },
          onOpenCompaction: (sequence: number, isCurrent: () => boolean): Promise<ResourceStr | undefined> => {
            const target = this.target;
            return target === undefined ? Promise.resolve(undefined) :
              this.actions?.openCompaction(target, sequence, isCurrent) ?? Promise.resolve(undefined);
          },
          onChanges: (target: DesktopChangeTarget): void => { this.actions?.openChanges(target); },
          onDecision: (request: string, allow: boolean): void => {
            this.run((binding): Promise<string> => binding.interactions.approve(request, allow));
          },
          onAnswer: (request: string, answers: DesktopQuestionAnswer[]): void => {
            this.run((binding): Promise<string> => binding.interactions.answer(request, answers));
          },
          onQuestionProgress: (request: string, progress: DesktopQuestionProgress, engage: boolean): void => {
            this.binding?.interactions.saveQuestion(request, progress, engage);
          },
          onQuestionHold: (request: string): void => { this.binding?.interactions.holdQuestion(request); },
          onQuestionClose: (request: string): void => {
            this.run((binding): Promise<string> => binding.interactions.closeQuestion(request));
          },
          onQuestionResume: (request: string): void => { this.binding?.interactions.reopenQuestion(request); },
          onPlanDecision: (request: string, accept: boolean): void => { this.run((binding): Promise<string> =>
            accept ? binding.interactions.approvePlanReview(request) : binding.interactions.dismissPlanReview(request)); },
          onPlanResume: (request: string): void => { this.binding?.interactions.reopenPlanReview(request); },
          onPlanMode: (enabled: boolean): void => {
            this.run((binding, id): Promise<string> => binding.conversation.togglePlanMode(id, enabled));
          },
          onTeamMode: (id: string, enabled: boolean): Promise<string> =>
            this.binding?.conversation.setTeamMode(id, enabled) ?? Promise.resolve('当前会话暂不可操作'),
          onGoalAction: (action: DesktopGoalAction, ref: DesktopGoalRef, objective: string): Promise<string> =>
            this.run((binding, id): Promise<string> => binding.conversation.mutateGoal(id, action, ref, objective)),
          onQueueAction: (session: string, row: string, action: QueueActionBody): Promise<string> =>
            this.run((binding): Promise<string> => binding.conversation.updateQueue(session, row, action)),
          onSteerQueue: (): void => { this.run((binding, id): Promise<string> => binding.conversation.steerQueue(id)); },
          onLoadModels: (refresh: boolean): void => { this.binding?.conversation.loadModels(refresh); },
          onModelsSettings: (): void => { this.actions?.openModels(); },
          onPluginDetails: (name: string, title: string, description: string): void => {
            this.actions?.openPlugin(name, title, description);
          },
          onWeb: (): void => { if (this.target !== undefined) { this.actions?.openWeb(this.target.id); } },
          onLoadCommands: (): void => { this.binding?.conversation.loadCommands(this.target?.id ?? ''); },
          onCommand: (command: string): Promise<string> => this.run((binding, id): Promise<string> =>
            binding.conversation.runCommandChoice(id, command, (session: string): Promise<string> =>
              this.actions?.exportLog(session) ?? Promise.resolve('当前会话暂不可导出'))),
          onSelectModel: (model: ModelSelection): Promise<string> => this.run((binding, id): Promise<string> => binding.conversation.selectModel(id, model)),
          onPermission: (preset: string): void => { this.run((binding, id): Promise<string> => binding.conversation.selectPermission(id, preset)); },
          onSlashPermission: (preset: string): Promise<string> => this.run((binding, id): Promise<string> => binding.conversation.selectPermission(id, preset)),
          onCopyTranscript: (): void => { this.actions?.copy(this.target?.id ?? ''); },
          onExportLog: (): void => { this.run((_, id): Promise<string> => this.actions?.exportLog(id) ?? Promise.resolve('')); },
          onSessionFeedback: (id: string): Promise<string> => this.run((binding): Promise<string> =>
            this.actions?.feedback(id, binding.conversation) ?? Promise.resolve('当前会话暂不可反馈')),
          onWarmFeedback: (id: string): void => { this.binding?.conversation.feedback.ensure(id); },
          onReplyRating: (id: string, messageId: string, rating: DesktopRating): void => {
            if (this.binding !== undefined) { this.actions?.rate(id, messageId, rating, this.binding.conversation); }
          },
          onFork: (id: string, sequence: number): void => {
            if (this.binding !== undefined) { this.actions?.fork(id, sequence, this.binding.conversation); }
          }
        })
      } else if (this.shown) {
        LoadingProgress().width(24).height(24).color($r('sys.color.brand'))
      }
    }.key('desktopDockChat-' + (this.target?.id ?? '')).width('100%').height('100%')
  }
}
