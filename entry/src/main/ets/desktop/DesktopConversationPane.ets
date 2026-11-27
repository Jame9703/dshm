import { Speaker, TrajectoryItem } from 'appstate';
import { KeyCode } from '@kit.InputKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { DESKTOP_ATTACHMENT_DROP_TYPES, desktopClipboardHasAttachments, desktopClipboardHasText,
  desktopDroppedFiles } from './DesktopAttachmentIntake';
import type { DesktopDroppedFiles } from './DesktopAttachmentIntake';
import type { ModelOption, ModelSelection } from 'appstate';
import type { DesktopConversationSnapshot, DesktopPermissionOption, DesktopTranscriptItem } from './DesktopConversation';
import { DesktopInteractionPane } from './DesktopInteractionPane';
import type { DesktopInteraction, DesktopQuestionAnswer } from './DesktopInteractions';
import type { DesktopPlanDocument } from './DesktopPlan';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopArtifactsPane } from './DesktopArtifactsPane';
import { DesktopChangeTarget } from './DesktopArtifacts';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopJobsControl } from './DesktopJobsControl';
import { DesktopSubagentsControl } from './DesktopSubagentsControl';
import type { DesktopSubagentEntry } from './DesktopSubagents';
import type { SessionListItem } from 'appstate';
import { DesktopProcessPane } from './DesktopProcessPane';
import { DesktopCommandPalette, DesktopPaletteRow } from './DesktopCommandPalette';
import { activeDesktopSlash, commandCandidates, commandInvocation, resolveDesktopCommand } from './DesktopCommands';
import type { DesktopCommand, DesktopCommandRecord, DesktopSlashToken } from './DesktopCommands';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { activeDesktopReference, desktopReferenceChoices, desktopReferenceCrumbs, desktopReferenceText,
  desktopFileReferenceInsertion, desktopSettledReference } from './DesktopReferences';
import type { DesktopReferenceChoice, DesktopReferenceCrumb, DesktopReferenceToken } from './DesktopReferences';
import { DesktopGoalBar } from './DesktopGoalBar';
import { DesktopGoalAction, DesktopGoalRef } from './DesktopGoal';
import { DesktopRating } from './DesktopFeedback';
import { DesktopReferenceMessage } from './DesktopReferenceMessage';
import { DesktopReferenceAction } from './DesktopReferenceActions';
import type { DesktopFileReferenceOffer } from './DesktopReferenceActions';
import { DesktopReplyActions } from './DesktopReplyActions';
import { DesktopQueueDock } from './DesktopQueueDock';
import { DesktopAttachmentFile, DesktopAttachmentThumbnail } from './DesktopAttachments';
import type { DesktopDraftAttachment, DesktopMediaAttachment } from './DesktopAttachments';
import type { QueueActionBody } from 'appstate';
import { DesktopDraftEditor } from './DesktopDraftEditor';
import { desktopDraftEditorOffset, desktopDraftTriggerText, desktopDraftWireOffset, EMPTY_DESKTOP_DRAFT,
  replaceDesktopDraftRange, sameDesktopDraft } from './DesktopDraftReferences';
import type { DesktopComposerDraft, DesktopDraftReference } from './DesktopDraftReferences';

@Component
export struct DesktopConversationPane {
  host?: DesktopHostActions;
  @Prop @Watch('onSnapshotChanged') snapshot: DesktopConversationSnapshot | undefined = undefined;
  @Prop sessionSummaries: SessionListItem[] = [];
  @Prop embedded: boolean = false;
  onSubagent: (entry: DesktopSubagentEntry, parents: DesktopSubagentEntry[]) => void = (): void => {};
  onSubagentAside: (entry: DesktopSubagentEntry, parents: DesktopSubagentEntry[]) => void = (): void => {};
  onSubagentParent: (child: DesktopSubagentEntry) => void = (): void => {};
  onOpenMain: () => void = (): void => {};
  @Prop title: ResourceStr = '';
  @Prop workspaceTitle: ResourceStr = '';
  @Prop sessionDirectory: string = '';
  @Prop @Watch('scheduleComposerSync') draft: DesktopComposerDraft = EMPTY_DESKTOP_DRAFT;
  @Prop @Watch('scheduleComposerSync') appearance: string = 'system';
  @Prop @Watch('insertFileReference') referenceOffer: DesktopFileReferenceOffer | undefined = undefined;
  @Prop interactions: DesktopInteraction[] = [];
  @Prop attachments: DesktopDraftAttachment[] = [];
  @Prop busy: boolean = false;
  @Prop terminalOpen: boolean = false;
  @Prop filesOpen: boolean = false;
  @Prop rightDockOpen: boolean = false;
  @Prop commandError: string = '';
  @Prop menuOptions: MenuOptions | undefined = undefined;
  @Prop copyingTranscript: boolean = false;
  @Prop exportingLog: boolean = false;
  @Prop choosingFeedback: boolean = false;
  @Prop forking: boolean = false;
  onFork: (sessionId: string, atSeq: number) => void = (_sessionId: string, _atSeq: number): void => {};
  onDraft: (session: string, value: DesktopComposerDraft) => void = () => {};
  onAddAttachment: () => void = () => {};
  onDropAttachments: (files: DesktopDroppedFiles) => void = (_files: DesktopDroppedFiles): void => {};
  onPasteAttachments: () => void = (): void => {};
  onOpenImage: (row: DesktopMediaAttachment) => void = (_row: DesktopMediaAttachment): void => {};
  onLink?: (href: string) => void;
  onRemoveAttachment: (receiptId: string) => void = () => {};
  onSend: (alternateDelivery: boolean) => void = (_alternateDelivery: boolean): void => {};
  onQueueAction: (session: string, id: string, action: QueueActionBody) => Promise<string> =
    (_session: string, _id: string, _action: QueueActionBody): Promise<string> => Promise.resolve('');
  onSteerQueue: () => void = (): void => {};
  onLoadModels: () => void = () => {};
  onModelsSettings: () => void = () => {};
  onLoadCommands: () => void = () => {};
  onCommand: (name: string) => Promise<string> = (_name: string): Promise<string> => Promise.resolve('');
  onSlashModel: (selection: ModelSelection) => Promise<string> =
    (_selection: ModelSelection): Promise<string> => Promise.resolve('');
  onSlashPermission: (preset: string) => Promise<string> = (_preset: string): Promise<string> => Promise.resolve('');
  onStop: () => void = () => {};
  onEarlier: () => void = () => {};
  onWeb: () => void = () => {};
  onCopyTranscript: () => void = () => {};
  onExportLog: () => void = () => {};
  onSessionFeedback: (sessionId: string) => Promise<string> = (_sessionId: string): Promise<string> => Promise.resolve('');
  onWarmFeedback: (sessionId: string) => void = (_sessionId: string): void => {};
  onReplyRating: (sessionId: string, messageId: string, rating: DesktopRating) => void =
    (_sessionId: string, _messageId: string, _rating: DesktopRating): void => {};
  onTerminal: () => void = () => {};
  onFiles: () => void = () => {};
  onRightDock: () => void = () => {};
  onModel: (selection: ModelSelection) => void = () => {};
  onPermission: (preset: string) => void = () => {};
  onDecision: (id: string, allow: boolean) => void = (_id: string, _allow: boolean): void => {};
  onAnswer: (id: string, answers: DesktopQuestionAnswer[]) => void =
    (_id: string, _answers: DesktopQuestionAnswer[]): void => {};
  onPlanMode: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onGoalAction: (action: DesktopGoalAction, ref: DesktopGoalRef, objective: string) => Promise<string> =
    (_action: DesktopGoalAction, _ref: DesktopGoalRef, _objective: string): Promise<string> => Promise.resolve('');
  onPlanPreview: (plan: DesktopPlanDocument) => void = (_plan: DesktopPlanDocument): void => {};
  onPlanDecision: (id: string, approve: boolean) => void = (_id: string, _approve: boolean): void => {};
  onPlanResume: (id: string) => void = (_id: string): void => {};
  onReferenceFileAction: (action: DesktopReferenceAction, path: string, name: string) => void =
    (_action: DesktopReferenceAction, _path: string, _name: string): void => {};
  onArtifactFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  onArtifactAction: (path: string, name: string, reveal: boolean) => void =
    (_path: string, _name: string, _reveal: boolean): void => {};
  onChanges: (target: DesktopChangeTarget) => void = (_target: DesktopChangeTarget): void => {};

  private readonly scroller: Scroller = new Scroller();
  private following: boolean = true;
  private sessionId: string = '';
  private messageCount: number = 0;
  private partial: string = '';
  private scrollTimer: number = -1;
  @State private attachmentOver: boolean = false;
  @State private compactHeader: boolean = true;
  @State private expandedProcesses: string[] = [];
  @State private expandedReasoning: string[] = [];
  @State private inspectedTool: string = '';
  private readonly composer = new DesktopDraftEditor();
  private composerReady: boolean = false;
  private composerSession: string = '';
  private composerDraft: DesktopComposerDraft = EMPTY_DESKTOP_DRAFT;
  private composerDark: boolean = false;
  private composerSyncTimer: number = -1;
  private composerSelectionEnd: number = -1;
  private readonly paletteScroller: Scroller = new Scroller();
  private slashFrame: number = -1;
  private slashToken?: DesktopSlashToken;
  private referenceToken?: DesktopReferenceToken;
  private referenceTimer: number = -1;
  private referenceVersion: number = 0;
  @State private referenceRows: DesktopReferenceChoice[] = [];
  @State private referenceTrail: DesktopReferenceCrumb[] = [];
  @State private referenceLoading: boolean = false;
  @State private referenceError: string = '';
  private paletteDraft: string = '';
  private dismissedDraft?: string;
  @State private palette: string = '';
  @State private query: string = '';
  @State private leading: boolean = true;
  @State private paletteFilter: string = '';
  @State private highlight: number = 0;
  @State private riskPreset: string = '';
  @State private agreed: boolean = false;
  @State private paletteNotice: string = '';

  private subagentCanSend(): boolean {
    return this.snapshot?.subagent === undefined ||
      (this.snapshot.subagent.mode === 'continuable' && this.snapshot.historyLoaded);
  }

  private subagentParentTitle(): string {
    const id = this.snapshot?.subagent?.parentId;
    return this.sessionSummaries.find((row: SessionListItem): boolean => row.id === id)?.title || '父会话';
  }

  aboutToDisappear(): void {
    this.composerReady = false;
    if (this.composerSyncTimer !== -1) { clearTimeout(this.composerSyncTimer); this.composerSyncTimer = -1; }
    this.cancelSlashRefresh();
    this.cancelReferenceLookup();
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  private onSnapshotChanged(): void {
    const id = this.snapshot?.sessionId ?? '';
    const count = this.snapshot?.transcript.length ?? 0;
    const partial = this.snapshot?.partial ?? '';
    if (id !== this.sessionId) {
      this.sessionId = id;
      this.composerSelectionEnd = -1;
      this.scheduleComposerSync();
      this.following = true;
      this.expandedProcesses = [];
      this.expandedReasoning = [];
      this.inspectedTool = '';
      this.dismissedDraft = undefined;
      this.closePalette();
    } else if (count === this.messageCount && partial === this.partial) {
      return;
    }
    this.messageCount = count;
    this.partial = partial;
    if (this.following && this.scrollTimer === -1) {
      this.scrollTimer = setTimeout((): void => {
        this.scrollTimer = -1;
        if (this.following && this.snapshot?.sessionId === this.sessionId) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 30);
    }
  }

  private closePalette(): void {
    this.cancelSlashRefresh();
    this.palette = '';
    this.slashToken = undefined;
    this.closeReferences();
    this.riskPreset = '';
    this.agreed = false;
  }

  private cancelReferenceLookup(): void {
    this.referenceVersion++;
    if (this.referenceTimer !== -1) {
      clearTimeout(this.referenceTimer);
      this.referenceTimer = -1;
    }
  }

  private closeReferences(): void {
    if (this.referenceToken === undefined) { return; }
    this.cancelReferenceLookup();
    this.referenceToken = undefined;
    this.referenceRows = [];
    this.referenceTrail = [];
    this.referenceLoading = false;
    this.referenceError = '';
  }

  private showReferences(text: string, token: DesktopReferenceToken): void {
    const previous = this.referenceToken;
    const changed = this.palette !== 'reference' || previous?.query !== token.query || previous?.quoted !== token.quoted;
    if (previous?.start !== token.start) { this.referenceTrail = []; }
    this.referenceToken = token;
    this.slashToken = undefined;
    this.paletteDraft = text;
    this.palette = 'reference';
    if (changed) {
      this.queryReferences(token);
    }
  }

  private queryReferences(token: DesktopReferenceToken): void {
    const host = this.host;
    const session = this.sessionId;
    if (host === undefined || !session) { return; }
    this.cancelReferenceLookup();
    const version = this.referenceVersion;
    this.highlight = 0;
    this.referenceRows = [];
    this.referenceError = '';
    this.referenceLoading = true;
    this.referenceTimer = setTimeout(async (): Promise<void> => {
      this.referenceTimer = -1;
      const result = await desktopReferenceChoices(host, session, token);
      if (version === this.referenceVersion && session === this.sessionId && this.palette === 'reference') {
        this.referenceRows = result.rows;
        this.referenceError = result.error;
        this.referenceLoading = false;
      }
    }, 100);
  }

  private referenceInDraft(): DesktopReferenceToken | undefined {
    const previous = this.referenceToken;
    if (previous === undefined || this.paletteDraft === this.draft.text) { return previous; }
    const current = activeDesktopReference(desktopDraftTriggerText(this.composerDraft), this.composerCaret());
    return current?.start === previous.start ? current : undefined;
  }

  private pickReference(id: string, drill: boolean = false): void {
    const row = this.referenceRows.find((item: DesktopReferenceChoice): boolean => item.id === id);
    const token = this.referenceInDraft();
    if (row === undefined || token === undefined || this.busy) { return; }
    if (drill && row.kind === 'directory') {
      this.drillReference(desktopReferenceText(row.path + '/', token.quoted, false));
      return;
    }
    const mention = desktopSettledReference(row, this.sessionDirectory, token.quoted);
    if (!mention) { return; }
    const original = this.draft.text;
    const spacer = /^\s/u.test(original.slice(token.end)) ? '' : ' ';
    this.closePalette();
    const reference: DesktopDraftReference = { start: token.start, end: token.start + mention.length,
      kind: row.kind, label: row.label };
    this.replaceComposerRange(original, token.start, token.end, mention + spacer, true, false, reference);
  }

  private drillReference(replacement: string): void {
    const token = this.referenceInDraft();
    const original = this.draft.text;
    if (!replacement || token === undefined || this.busy) { return; }
    const next = original.slice(0, token.start) + replacement + original.slice(token.end);
    const nextToken = activeDesktopReference(next, token.start + replacement.length);
    if (nextToken === undefined) { return; }
    this.showReferences(next, nextToken);
    this.referenceTrail = desktopReferenceCrumbs(nextToken);
    this.replaceComposerRange(original, token.start, token.end, replacement, true, true);
  }

  private cancelSlashRefresh(): void {
    if (this.slashFrame !== -1) { clearTimeout(this.slashFrame); this.slashFrame = -1; }
  }

  private refreshSlash(): void {
    if (this.palette === 'model' || this.palette === 'permission') { return; }
    if (this.slashFrame !== -1) { return; }
    this.slashFrame = setTimeout((): void => {
      this.slashFrame = -1;
      if (!this.composerReady || this.composerSession !== this.sessionId) { return; }
      const selection = this.composer.controller.getSelection();
      if (selection?.start === selection?.end) {
        this.detectTrigger(this.composerDraft.text, this.composerCaret());
      }
    }, 16);
  }

  private detectTrigger(text: string, caret: number): void {
    if (this.palette === 'model' || this.palette === 'permission') { return; }
    if (text === this.dismissedDraft || this.busy || this.snapshot?.loading !== false) {
      this.closePalette();
      return;
    }
    const triggerText = desktopDraftTriggerText(this.composerDraft);
    const reference = activeDesktopReference(triggerText, caret);
    if (reference !== undefined) {
      this.showReferences(text, reference);
      return;
    }
    this.closeReferences();
    const token = activeDesktopSlash(triggerText, caret);
    if (token === undefined) { this.closePalette(); return; }
    const refresh = this.palette !== 'commands' || this.query !== token.query || this.leading !== token.leading;
    this.slashToken = token;
    this.paletteDraft = text;
    this.query = token.query;
    this.leading = token.leading;
    if (refresh) { this.highlight = 0; }
    this.palette = 'commands';
    if (!this.snapshot.commands && !this.snapshot.commandLoading && !this.snapshot.commandError) {
      this.onLoadCommands();
    }
  }

  private paletteCommands(): DesktopCommand[] {
    return commandCandidates(this.snapshot?.commands ?? [], this.query, this.leading);
  }

  private modelKey(option: ModelOption): string {
    return JSON.stringify([option.provider, option.modelId]);
  }

  private paletteRows(): DesktopPaletteRow[] {
    if (this.palette === 'reference') {
      return this.referenceRows.map((row: DesktopReferenceChoice): DesktopPaletteRow => ({
        id: row.id, title: row.label + (row.kind === 'directory' ? '/' : ''),
        detail: this.referenceTrail.length && row.kind !== 'session' ? '' : row.detail,
        section: row.kind === 'session' ? '会话' : '文件', token: '', drill: row.kind === 'directory',
        icon: row.kind === 'session' ? $r('app.media.dsh_reference_session') :
          row.kind === 'directory' ? $r('app.media.dsh_reference_folder') : $r('app.media.dsh_reference_file')
      }));
    }
    if (this.palette === 'commands') {
      return this.paletteCommands().map((row: DesktopCommand): DesktopPaletteRow => {
        return { id: row.name, title: row.label, detail: row.description, token: `/${row.alias}`,
          section: ['file', 'goal', 'plan', 'feedback'].includes(row.kind) ? '添加' : '指令' };
      });
    }
    const needle = this.paletteFilter.trim().toLowerCase();
    if (this.palette === 'model') {
      return (this.snapshot?.models ?? []).filter((row: ModelOption): boolean =>
        `${row.modelName} ${row.providerName} ${row.modelId}`.toLowerCase().includes(needle))
        .map((row: ModelOption): DesktopPaletteRow => {
          const current = this.snapshot?.selection;
          return { id: this.modelKey(row), title: row.modelName, detail: row.providerName, section: '',
            token: current?.provider === row.provider && current?.modelId === row.modelId ? '✓' : '' };
        });
    }
    return (this.snapshot?.permissions ?? []).filter((row: DesktopPermissionOption): boolean =>
      `${row.title} ${row.detail} ${row.value}`.toLowerCase().includes(needle))
      .map((row: DesktopPermissionOption): DesktopPaletteRow => ({ id: row.value, title: row.title, detail: row.detail,
        section: '', token: this.snapshot?.permission === row.value ? '✓' : '' }));
  }

  private insertFileReference(): void {
    const offer = this.referenceOffer;
    if (offer === undefined) { return; }
    setTimeout((): void => {
      if (offer.sessionId !== this.sessionId || !this.acceptsAttachments()) { return; }
      const original = this.draft.text;
      const insert = desktopFileReferenceInsertion(original, this.composerSelectionEnd, offer.path);
      if (insert === undefined) { return; }
      const start = insert.position + insert.text.indexOf('@');
      const end = insert.position + insert.text.trimEnd().length;
      const reference: DesktopDraftReference = { start: start, end: end, kind: 'file',
        label: offer.path.slice(offer.path.lastIndexOf('/') + 1) };
      this.closePalette();
      this.replaceComposerRange(original, insert.position, insert.position, insert.text, true, false, reference);
    }, 0);
  }

  private replaceSlash(original: string, token: DesktopSlashToken, replacement: string, refocus: boolean = true): void {
    this.replaceComposerRange(original, token.start, token.end, replacement, refocus);
  }

  private replaceComposerRange(original: string, start: number, end: number, replacement: string, refocus: boolean,
    keepOpen: boolean = false, reference?: DesktopDraftReference): void {
    if (!this.composerReady || this.composerSession !== this.sessionId || this.composerDraft.text !== original) { return; }
    const draft = replaceDesktopDraftRange(this.composerDraft, start, end, replacement, reference);
    this.dismissedDraft = keepOpen ? undefined : draft.text;
    this.renderComposer(draft);
    this.onDraft(this.composerSession, draft);
    this.composerSelectionEnd = start + replacement.length;
    const caret = desktopDraftEditorOffset(draft, this.composerSelectionEnd);
    this.composer.controller.setCaretOffset(caret);
    if (!refocus) { return; }
    const session = this.sessionId;
    this.getUIContext().getFocusController().requestFocus('desktopSlashComposer');
    setTimeout((): void => {
      if (this.composerReady && session === this.sessionId && sameDesktopDraft(this.composerDraft, draft)) {
        this.composer.controller.setCaretOffset(caret);
      }
    }, 0);
  }

  private composerCaret(): number {
    const offset = this.composer.controller.getCaretOffset();
    return offset < 0 ? this.composerDraft.text.length : desktopDraftWireOffset(this.composerDraft, offset);
  }

  private scheduleComposerSync(): void {
    if (!this.composerReady || this.composerSyncTimer !== -1) { return; }
    this.composerSyncTimer = setTimeout((): void => {
      this.composerSyncTimer = -1;
      this.syncComposer();
    }, 0);
  }

  private syncComposer(): void {
    const dark = this.appearance === 'dark' || (this.appearance === 'system' &&
      this.getUIContext().getHostContext()?.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK);
    if (this.composerSession === this.sessionId && this.composerDark === dark &&
      sameDesktopDraft(this.composerDraft, this.draft)) { return; }
    const sampleCaret = this.composerSession === this.sessionId && sameDesktopDraft(this.composerDraft, this.draft);
    const caret = sampleCaret ? this.composerCaret() : this.draft.text.length;
    this.composerSession = this.sessionId;
    this.composerDark = dark;
    this.renderComposer(this.draft);
    this.composerSelectionEnd = caret;
    this.composer.controller.setCaretOffset(desktopDraftEditorOffset(this.draft, caret));
  }

  private renderComposer(draft: DesktopComposerDraft): void {
    this.composerDraft = draft;
    this.composer.controller.setStyledString(this.composer.format(draft, this.getUIContext(), this.composerDark));
  }

  private prepareComposer(): void {
    this.composerReady = true;
    this.syncComposer();
    this.composer.controller.onContentChanged({ onDidChange: (): void => {
      if (this.composerSession !== this.sessionId) { return; }
      const draft = this.composer.read();
      if (sameDesktopDraft(this.composerDraft, draft)) { return; }
      this.composerDraft = draft;
      this.composerSelectionEnd = this.composerCaret();
      this.paletteNotice = '';
      if (draft.text !== this.dismissedDraft) { this.dismissedDraft = undefined; }
      this.onDraft(this.composerSession, draft);
      this.refreshSlash();
    } });
  }

  private composerSelectionChanged(range: RichEditorRange): void {
    if (range.end === undefined || range.end < 0 || !this.composerReady || this.composerSession !== this.sessionId) { return; }
    this.composerSelectionEnd = desktopDraftWireOffset(this.composerDraft, range.end);
    if (range.start === range.end) { this.refreshSlash(); }
    else if (this.palette === 'reference') { this.closePalette(); }
  }

  private copyComposerSelection(event: CopyEvent, cut: boolean): void {
    if (this.composerDraft.references.length === 0 || event.preventDefault === undefined) { return; }
    const range = this.composer.controller.getSelection();
    if (range?.start === undefined || range.end === undefined || range.start === range.end) { return; }
    const start = desktopDraftWireOffset(this.composerDraft, Math.min(range.start, range.end));
    const end = desktopDraftWireOffset(this.composerDraft, Math.max(range.start, range.end));
    if (!this.composerDraft.references.some((reference: DesktopDraftReference): boolean =>
      reference.start >= start && reference.end <= end)) { return; }
    try {
      pasteboard.getSystemPasteboard().setDataSync(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        this.composerDraft.text.slice(start, end)));
    } catch (_) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    if (cut) { this.replaceComposerRange(this.composerDraft.text, start, end, '', false); }
  }

  private openChoice(kind: string): void {
    this.paletteFilter = '';
    this.highlight = 0;
    this.riskPreset = '';
    this.agreed = false;
    this.palette = kind;
    if (kind === 'model') { this.onLoadModels(); }
  }

  private async pickPalette(id: string): Promise<void> {
    if (this.palette === 'reference') { this.pickReference(id); return; }
    const token = this.slashToken;
    const original = this.paletteDraft;
    if (token === undefined || original !== this.draft.text || this.busy) { return; }
    const session = this.sessionId;
    const view = this.palette;
    let problem = '';
    if (view === 'commands') {
      const row = this.paletteCommands().find((item: DesktopCommand): boolean => item.name === id);
      if (row === undefined) { return; }
      if (row.kind === 'file') {
        this.closePalette();
        this.replaceSlash(original, token, '');
        this.onAddAttachment();
        return;
      }
      if (row.kind === 'model' || (row.kind === 'permission' && (this.snapshot?.permissions.length ?? 0) > 0)) {
        this.openChoice(row.kind);
        return;
      }
      this.closePalette();
      if (row.kind === 'feedback') {
        problem = await this.onSessionFeedback(session);
        if (session === this.sessionId) {
          this.paletteNotice = problem;
          if (!problem) { this.replaceSlash(original, token, '', false); }
        }
        return;
      } else if (row.hint !== undefined) {
        this.replaceSlash(original, token, `/${row.alias} `);
        return;
      } else {
        this.following = true;
        problem = await this.onCommand(row.name);
      }
    } else if (view === 'model') {
      const option = this.snapshot?.models.find((row: ModelOption): boolean => this.modelKey(row) === id);
      if (option === undefined) { return; }
      this.closePalette();
      problem = await this.onSlashModel({ provider: option.provider, modelId: option.modelId,
        effort: option.defaultEffort });
    } else if (view === 'permission') {
      const preset = this.riskPreset || id;
      if (id === 'confirm' && (!this.riskPreset || !this.agreed)) { return; }
      if (id !== 'confirm' && this.snapshot?.permission !== preset &&
        (preset === 'danger-full-access' || preset === 'auto')) {
        this.riskPreset = preset;
        this.agreed = false;
        return;
      }
      this.closePalette();
      problem = await this.onSlashPermission(preset);
    }
    if (session === this.sessionId && !problem) { this.replaceSlash(original, token, ''); }
  }

  private hasDraft(): boolean {
    return this.draft.text.trim().length > 0 || this.attachments.length > 0;
  }

  private primaryStops(): boolean {
    return this.snapshot?.running === true && !this.hasDraft();
  }

  private canSteerQueue(): boolean {
    return this.primaryStops() && !this.busy && (this.snapshot?.queue.length ?? 0) > 0;
  }

  private handleSend(alternateDelivery: boolean = false): void {
    if (this.busy || this.snapshot?.loading !== false) { return; }
    const command = commandInvocation(this.draft.text);
    if (command !== undefined && !command.suffix) {
      const choices = commandCandidates(this.snapshot.commands ?? [], '', true);
      const row = resolveDesktopCommand(choices, command.token);
      if (row?.kind === 'file' || row?.kind === 'model' ||
        (row?.kind === 'permission' && this.snapshot.permissions.length > 0)) {
        if (row.kind !== 'file' && this.attachments.length > 0) {
          this.paletteNotice = `/${command.token} 不接受附件，请先移除附件`;
          return;
        }
        this.slashToken = activeDesktopSlash(this.draft.text, this.draft.text.trimEnd().length);
        this.paletteDraft = this.draft.text;
        this.query = command.token;
        this.leading = true;
        this.palette = 'commands';
        this.pickPalette(row.name);
        return;
      }
    }
    this.dismissedDraft = this.draft.text;
    this.closePalette();
    this.following = true;
    this.onSend(alternateDelivery);
  }

  private acceptsAttachments(): boolean {
    return !this.busy && this.snapshot?.loading === false;
  }

  private composerKey(event: KeyEvent): boolean {
    if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ENTER &&
      event.getModifierKeyState?.(['Shift']) === true) {
      const range = this.composer.controller.getSelection();
      const caret = this.composerCaret();
      const start = range?.start !== undefined && range.start >= 0 ?
        desktopDraftWireOffset(this.composerDraft, range.start) : caret;
      const end = range?.end !== undefined && range.end >= 0 ?
        desktopDraftWireOffset(this.composerDraft, range.end) : caret;
      this.closePalette();
      this.replaceComposerRange(this.composerDraft.text, Math.min(start, end), Math.max(start, end), '\n', true);
      return true;
    }
    if (this.acceptsAttachments() && event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_V &&
      event.getModifierKeyState?.(['Ctrl']) === true && desktopClipboardHasAttachments()) {
      this.onPasteAttachments();
      return !desktopClipboardHasText();
    }
    return this.paletteKey(event);
  }

  private dropAttachments(event: DragEvent): void {
    this.attachmentOver = false;
    if (this.acceptsAttachments()) {
      try {
        const files = desktopDroppedFiles(event.getData());
        if (files.uris.length > 0 || files.hasFolder) {
          this.onDropAttachments(files);
          event.setResult(DragResult.DRAG_SUCCESSFUL);
          return;
        }
      } catch (_) {
        event.setResult(DragResult.DRAG_FAILED);
        return;
      }
    }
    event.setResult(DragResult.DRAG_FAILED);
  }

  private scrollToReference(rows: DesktopPaletteRow[]): void {
    let offset = 0;
    for (let index = 0; index <= this.highlight; index++) {
      if (index === 0 || rows[index - 1].section !== rows[index].section) { offset += 24; }
      if (index < this.highlight) { offset += 34; }
    }
    const top = this.paletteScroller.currentOffset().yOffset;
    if (offset < top || offset + 34 > top + 244) {
      this.paletteScroller.scrollTo({ xOffset: 0, yOffset: offset < top ? offset : offset + 34 - 244 });
    }
  }

  private paletteKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    if (this.palette && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (this.riskPreset) { this.riskPreset = ''; this.agreed = false; }
      else { this.dismissedDraft = this.draft.text; this.closePalette(); }
      return true;
    }
    if (this.riskPreset) { return false; }
    const rows = this.palette ? this.paletteRows() : [];
    const up = event.keyCode === KeyCode.KEYCODE_DPAD_UP;
    if (rows.length > 0 && (up || event.keyCode === KeyCode.KEYCODE_DPAD_DOWN)) {
      this.highlight = (this.highlight + (up ? -1 : 1) + rows.length) % rows.length;
      if (this.palette === 'reference') { this.scrollToReference(rows); }
      else { this.paletteScroller.scrollToIndex(this.highlight, false, ScrollAlign.AUTO); }
      return true;
    }
    const item = rows[this.highlight] ?? rows[0];
    if (this.palette === 'reference' && event.keyCode === KeyCode.KEYCODE_TAB) {
      if (event.getModifierKeyState?.(['Shift']) === true) {
        this.dismissedDraft = this.draft.text;
        this.closePalette();
        return true;
      }
      if (item !== undefined) {
        this.pickReference(item.id, item.drill === true);
        return true;
      }
    }
    if (event.keyCode !== KeyCode.KEYCODE_ENTER || event.getModifierKeyState?.(['Shift'])) {
      return false;
    }
    if (this.palette === 'reference' && this.referenceLoading) { return true; }
    const accelerated = event.getModifierKeyState?.(['Ctrl']) === true;
    if (item !== undefined) { this.pickPalette(item.id); }
    else if (accelerated && this.canSteerQueue() && !this.palette) { this.onSteerQueue(); }
    else if (this.hasDraft()) { this.handleSend(accelerated); }
    return true;
  }

  @Builder
  private CommandPopup() {
    DesktopCommandPalette({ rows: this.paletteRows(), viewMode: this.palette, filter: this.paletteFilter,
      highlight: this.highlight, scroller: this.paletteScroller, agreed: this.agreed,
      riskName: this.snapshot?.permissions.find((row: DesktopPermissionOption): boolean =>
        row.value === this.riskPreset)?.title ?? '', loading: this.palette === 'reference' ? this.referenceLoading :
        this.palette === 'commands' ? this.snapshot?.commandLoading === true :
          (this.palette === 'model' && this.snapshot?.modelsLoading === true),
      error: this.palette === 'reference' ? this.referenceError : this.palette === 'commands' ?
        this.snapshot?.commandError ?? '' : '',
      crumbs: this.referenceTrail,
      onPick: (id: string): void => { this.pickPalette(id); },
      onDrill: (id: string): void => { this.pickReference(id, true); },
      onCrumb: (text: string): void => { this.drillReference(text); },
      onAgree: (value: boolean): void => { this.agreed = value; },
      onFilter: (value: string): void => { this.paletteFilter = value; this.highlight = 0; },
      onRetry: (): void => {
        if (this.palette === 'reference' && this.referenceToken !== undefined) { this.queryReferences(this.referenceToken); }
        else { this.onLoadCommands(); }
      },
      onModelsSettings: (): void => { this.closePalette(); this.onModelsSettings(); },
      onBack: (): void => { this.riskPreset = ''; this.agreed = false; },
      onKey: (event: KeyEvent): boolean => this.paletteKey(event) })
  }

  @Builder
  private CommandCard(row: DesktopCommandRecord) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(`/${row.name}${row.args.trim() ? ' ' + row.args.trimStart() : ''}`).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1).copyOption(CopyOptions.LocalDevice)
        Text(row.completed < 0 ? '执行中' : (row.outcome === 'success' ? '完成' : '失败'))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      if (row.text) { MarkdownRenderer({ text: row.text, onLink: this.onLink }) }
    }.width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start).padding(12)
      .borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
  }

  private visibleInteraction(): DesktopInteraction[] {
    const visible = this.interactions.filter((row: DesktopInteraction): boolean => !row.reviewHidden);
    const row = visible.find((item: DesktopInteraction): boolean => item.planReview !== undefined) ?? visible[0];
    return row === undefined ? [] : [row];
  }

  @Builder
  private PlanCard(plan: DesktopPlanDocument) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(20).fontColor([$r('sys.color.font_secondary')])
        Column({ space: 3 }) {
          Text(plan.title).fontSize(15).fontColor($r('sys.color.font_primary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('计划文档').fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('打开').fontSize(13).fontColor($r('sys.color.brand'))
      }.width('100%')
    }
    .width('100%').constraintSize({ maxWidth: 712 }).padding(12).borderRadius(12)
    .backgroundColor($r('app.color.workspace_panel')).onClick((): void => { this.onPlanPreview(plan); })
  }

  private modelMenu(): Array<MenuElement> {
    if ((this.snapshot?.models.length ?? 0) === 0) {
      return [{ value: $r('app.string.desktop_chat_model_settings'), action: this.onModelsSettings }];
    }
    return (this.snapshot?.models ?? []).map((option: ModelOption): MenuElement => {
      return {
        value: option.modelName + ' · ' + option.providerName,
        action: (): void => this.onModel({
          provider: option.provider, modelId: option.modelId, effort: option.defaultEffort
        })
      };
    });
  }

  private sessionMenu(): MenuElement[] {
    return [
      { value: '复制会话为 Markdown', icon: $r('app.media.dsh_session_copy'),
        enabled: !this.copyingTranscript, action: this.onCopyTranscript },
      { value: '下载 Session 日志', icon: $r('app.media.dsh_session_download'),
        enabled: !this.exportingLog && !this.busy, action: this.onExportLog },
      { value: '反馈', icon: $r('app.media.dsh_feedback_paper_plane_outline'), enabled: !this.choosingFeedback,
        action: (): void => { this.onSessionFeedback(this.snapshot?.sessionId ?? ''); } }
    ];
  }

  private effortMenu(): Array<MenuElement> {
    const selection = this.snapshot?.selection;
    if (selection === undefined) {
      return [];
    }
    const option = this.snapshot?.models.find((item: ModelOption): boolean =>
      item.provider === selection.provider && item.modelId === selection.modelId);
    return (option?.efforts ?? []).map((effort: string): MenuElement => {
      return {
        value: effort,
        action: (): void => this.onModel({
          provider: selection.provider, modelId: selection.modelId, effort: effort
        })
      };
    });
  }

  @Builder
  private Message(item: TrajectoryItem, attachments: DesktopMediaAttachment[], referenceLabels: string[]) {
    Column({ space: 7 }) {
      if (item.speaker === Speaker.USER) {
        if (attachments.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
            ForEach(attachments, (row: DesktopMediaAttachment, index: number): void => {
              Row() {
                if (row.image) {
                  DesktopAttachmentThumbnail({ attachment: row, sessionId: this.sessionId, host: this.host,
                    maxEdge: 150, nodeKey: 'desktopHistoryImage-' + item.id + '-' + index, onOpen: this.onOpenImage })
                } else {
                  DesktopAttachmentFile({ filename: row.name, bytes: row.bytes })
                }
              }.margin({ left: 6, top: 4 })
            }, (row: DesktopMediaAttachment, index: number): string => row.id + ':' + index)
          }.width('100%').constraintSize({ maxWidth: '82%' })
        }
        if (item.body.includes('@') || referenceLabels.length > 0) {
          DesktopReferenceMessage({ text: item.body, referenceLabels: referenceLabels,
            sessionId: this.sessionId, host: this.host, nodeKey: 'desktopInlineReferences-' + item.id,
            canAddReference: this.acceptsAttachments(), onFile: this.onArtifactFile, onAction: this.onReferenceFileAction })
        } else if (item.body) {
          Text(item.body)
            .fontSize(15).fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .constraintSize({ maxWidth: '82%' }).borderRadius(16)
            .backgroundColor($r('app.color.workspace_panel'))
        }
      } else {
        if (item.reasoning) {
          Button(this.expandedReasoning.includes(item.id) ? '收起思考过程' : '思考过程',
            { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(30).onClick((): void => {
              this.expandedReasoning = this.expandedReasoning.includes(item.id) ?
                this.expandedReasoning.filter((id: string): boolean => id !== item.id) : [...this.expandedReasoning, item.id];
            })
          if (this.expandedReasoning.includes(item.id)) {
            MarkdownRenderer({ text: item.reasoning, onLink: this.onLink })
          }
        }
        if (item.body) { MarkdownRenderer({ text: item.body, onLink: this.onLink }) }
      }
    }
    .width('100%').constraintSize({ maxWidth: 712 })
    .alignItems(item.speaker === Speaker.USER ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  @Builder
  private ModelChip(effort: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 5 }) {
        Text(effort ? this.snapshot?.selection?.effort || $r('app.string.desktop_chat_effort') :
          this.snapshot?.modelLabel || $r('app.string.desktop_chat_select_model'))
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10)
          .fontColor([$r('sys.color.font_tertiary')]).rotate({ angle: 90 })
      }
    }
    .height(32).padding({ left: 8, right: 8 }).constraintSize({ maxWidth: effort ? 95 : 160 })
    .borderRadius(8).backgroundColor(Color.Transparent).focusOnTouch(false)
    .enabled(!this.busy).bindMenu(effort ? this.effortMenu() : this.modelMenu(), this.menuOptions)
  }

  @Builder
  private ComposerControls() {
    Scroll() {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.paperclip')).fontSize(16)
        }
        .width(32).height(32).focusOnTouch(false)
        .enabled(!this.busy && this.snapshot?.loading === false)
        .key('desktopComposerAddAttachment').accessibilityText('添加附件').onClick(this.onAddAttachment)
        if (this.snapshot?.planMode !== undefined) {
          Button(this.snapshot?.planMode ? '计划模式 ×' : '计划模式', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(31).borderRadius(8).focusOnTouch(false).enabled(!this.busy)
            .accessibilitySelected(this.snapshot?.planMode === true)
            .onClick((): void => { this.onPlanMode(this.snapshot?.planMode !== true); })
        }
        if ((this.snapshot?.permissions.length ?? 0) > 0) {
          Button(this.snapshot?.permissions.find((row: DesktopPermissionOption): boolean =>
            row.value === this.snapshot?.permission)?.title || '访问模式', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(31).borderRadius(8).enabled(!this.busy).focusOnTouch(false)
            .bindMenu(this.snapshot?.permissions.map((row: DesktopPermissionOption): MenuElement => {
              return { value: (row.value === this.snapshot?.permission ? '✓ ' : '') + row.title,
                action: (): void => { this.onPermission(row.value); } };
            }) ?? [], this.menuOptions)
        }
        this.ModelChip(false)
        if (this.effortMenu().length > 0) {
          this.ModelChip(true)
        }
      }
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
    .layoutWeight(1).height(36)
  }

  @Builder
  private Composer() {
    Column({ space: 6 }) {
      if (this.attachments.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.attachments, (item: DesktopDraftAttachment, index: number) => {
              Row({ space: 3 }) {
                if (item.picture !== undefined) {
                  DesktopAttachmentThumbnail({ attachment: item.picture, sessionId: this.sessionId, host: this.host,
                    maxEdge: 68, nodeKey: 'desktopDraftImage-' + item.receiptId, onOpen: this.onOpenImage })
                } else {
                  DesktopAttachmentFile({ filename: item.name, bytes: item.bytes })
                }
                Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  Image($r('app.media.dsh_dock_close')).width(13).height(13).supportSvg2(true).accessibilityLevel('no')
                }.key('desktopRemoveAttachment-' + item.receiptId).width(26).height(26).padding(0).borderRadius(6)
                  .enabled(!this.busy).accessibilityText('移除附件 ' + item.name)
                  .onClick((): void => { this.onRemoveAttachment(item.receiptId); })
              }
            }, (item: DesktopDraftAttachment, index: number): string => item.receiptId + index)
          }
        }
        .scrollable(ScrollDirection.Horizontal).width('100%').padding({ left: 8, right: 8 })
      }
      RichEditor({ controller: this.composer.controller })
        .placeholder(this.snapshot?.planMode === true ?
        '描述你的任务以生成计划' : (this.canSteerQueue() ? '按 Ctrl+Enter 插话发送排队消息' :
          $r('app.string.desktop_chat_placeholder')), { font: { size: 15 } })
        .key('desktopSlashComposer').enterKeyType(EnterKeyType.Send)
        .width('100%').height(66).borderRadius(16).padding({ left: 12, right: 12, top: 10 })
        .backgroundColor(Color.Transparent)
        .allowDrop(null)
        .accessibilityDescription(this.draft.references.map((item: DesktopDraftReference): string => item.label).join('、'))
        .onReady((): void => this.prepareComposer())
        .onSelectionChange((range: RichEditorRange): void => this.composerSelectionChanged(range))
        .onCopy((event: CopyEvent): void => this.copyComposerSelection(event, false))
        .onCut((event: CutEvent): void => this.copyComposerSelection(event, true))
        .onKeyPreIme((event: KeyEvent): boolean => this.composerKey(event))
        .onSubmit((_key: EnterKeyType, event: SubmitEvent): void => {
          event.keepEditableState();
          if (this.hasDraft()) { this.handleSend(); }
        })
        .bindPopup(this.palette !== '', { builder: this.CommandPopup(), placement: Placement.TopLeft,
          enableArrow: false, mask: false, focusable: this.palette === 'model' || this.palette === 'permission',
          systemMaterial: desktopMenuOptions(Placement.TopLeft).systemMaterial,
          onStateChange: (event): void => {
            if (!event.isVisible && this.palette) { this.dismissedDraft = this.draft.text; this.closePalette(); }
          } })
      Row({ space: 4 }) {
        this.ComposerControls()
        if (this.snapshot?.running && !this.primaryStops()) {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(15)
          }.key('desktopComposerStop').width(34).height(34).focusOnTouch(false)
            .enabled(!this.busy).accessibilityText($r('app.string.desktop_chat_stop')).onClick(this.onStop)
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.primaryStops() ? $r('sys.symbol.xmark') : $r('sys.symbol.arrow_up'))
            .fontSize(17).fontColor([Color.White])
        }
        .key('desktopComposerSubmit').width(34).height(34)
        .backgroundColor($r('sys.color.brand')).focusOnTouch(false)
        .accessibilityText(this.primaryStops() ? $r('app.string.desktop_chat_stop') :
          (this.snapshot?.running ? (this.snapshot.busyEnterSteers ? $r('app.string.desktop_chat_steer') :
            $r('app.string.desktop_chat_queue')) :
            $r('app.string.desktop_chat_send')))
        .enabled(!this.busy && (this.snapshot?.running === true ||
          ((this.draft.text.trim().length > 0 || this.attachments.length > 0) &&
            this.snapshot?.loading === false)))
        .onClick((): void => {
          if (this.primaryStops()) {
            this.onStop();
          } else {
            this.handleSend();
          }
        })
      }
      .width('100%').padding({ left: 8, right: 8, bottom: 7 })
    }
    .width('100%').constraintSize({ maxWidth: 712 })
    .border({ width: 1, radius: 20, color: this.attachmentOver ? $r('sys.color.brand') : Color.Transparent })
    .backgroundColor($r('app.color.workspace_panel'))
    .allowDrop(DESKTOP_ATTACHMENT_DROP_TYPES)
    .onDragEnter((): void => { this.attachmentOver = this.acceptsAttachments(); })
    .onDragMove((event: DragEvent): void => {
      event.setResult(this.acceptsAttachments() ? DragResult.DROP_ENABLED : DragResult.DROP_DISABLED);
    })
    .onDragLeave((): void => { this.attachmentOver = false; })
    .onDrop((event: DragEvent): void => { this.dropAttachments(event); })
  }

  build() {
    Column() {
      Row({ space: this.compactHeader ? 4 : 8 }) {
        if (this.snapshot?.subagent !== undefined) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(12).accessibilityLevel('no')
              if (!this.compactHeader) {
                Text(this.subagentParentTitle()).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
          }.key('desktopSubagentParent').height(34).constraintSize({ maxWidth: 140 }).focusOnTouch(false)
            .accessibilityText('返回父会话 ' + this.subagentParentTitle()).onClick((): void => {
              const child = this.snapshot?.subagent;
              if (child !== undefined) { this.onSubagentParent(child); }
            })
        }
        Column({ space: 2 }) {
          Text(this.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.workspaceTitle !== '') {
            Text(this.workspaceTitle).fontSize(12).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        if ((this.snapshot?.subagents.length ?? 0) > 0 || this.snapshot?.subagent !== undefined) {
          DesktopSubagentsControl({ host: this.host, sessionId: this.snapshot?.sessionId ?? '',
            child: this.snapshot?.subagent, entries: this.snapshot?.subagents ?? [],
            summaries: this.sessionSummaries, onOpen: this.onSubagent, onOpenAside: this.onSubagentAside })
        }
        if (this.snapshot?.sessionId) {
          DesktopJobsControl({ host: this.host, sessionId: this.snapshot?.sessionId ?? '' })
        }
        if (this.embedded) {
          Button('主区域', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).height(34).focusOnTouch(false)
            .key('desktopDockChatPromote').accessibilityText('在主区域打开').onClick(this.onOpenMain)
        } else {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.folder')).fontSize(18).fontColor([$r('sys.color.font_primary')])
          }
            .key('desktopWorkspaceFiles').width(34).height(34).padding(0).focusOnTouch(false)
            .accessibilityText('工作区文件').accessibilitySelected(this.filesOpen).onClick(this.onFiles)
          Button('终端', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
            .width(44).height(34).padding(0).focusOnTouch(false)
            .accessibilitySelected(this.terminalOpen)
            .onClick(this.onTerminal)
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.sidebar_toggle')).width(16).height(16).rotate({ angle: 180 })
              .fillColor($r('sys.color.font_primary')).accessibilityLevel('no')
          }.key('desktopToggleRightDock').width(34).height(34).padding(0).focusOnTouch(false)
            .accessibilityText(this.rightDockOpen ? '收起右侧栏' : '展开右侧栏')
            .accessibilitySelected(this.rightDockOpen).onClick(this.onRightDock)
          if (this.compactHeader) {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              SymbolGlyph($r('sys.symbol.link')).fontSize(16).fontColor([$r('sys.color.font_primary')])
                .accessibilityLevel('no')
            }.key('desktopOpenCompatSession').width(34).height(34).padding(0).focusOnTouch(false)
              .accessibilityText($r('app.string.desktop_experiment_open_web')).onClick(this.onWeb)
          } else {
            Button($r('app.string.desktop_experiment_open_web'),
              { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopOpenCompatSession').height(34).focusOnTouch(false).onClick(this.onWeb)
          }
        }
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_session_ellipsis')).width(18).height(18).supportSvg2(true).draggable(false)
            .accessibilityLevel('no')
        }.key('desktopSessionMore').width(34).height(34).padding(0).focusOnTouch(false)
          .accessibilityText('会话菜单').enabled(this.snapshot?.loading === false)
          .bindMenu(this.sessionMenu(), desktopMenuOptions(Placement.BottomRight))
      }
      .width('100%').height(50).padding({ left: this.compactHeader ? 8 : 20, right: this.compactHeader ? 8 : 16 })
      .onAreaChange((_, area: Area): void => { this.compactHeader = Number(area.width) < 500; })
      if (this.snapshot?.loading) {
        LoadingProgress().width(22).height(22).color($r('sys.color.brand'))
      }
      if (this.snapshot?.hasEarlier) {
        Button($r('app.string.desktop_chat_earlier'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => {
            this.following = false;
            this.onEarlier();
          })
      }
      List({ space: 16, scroller: this.scroller }) {
        ForEach(this.snapshot?.transcript ?? [], (item: DesktopTranscriptItem): void => {
          ListItem() {
            Row() {
              if (item.plan !== undefined) {
                this.PlanCard(item.plan)
              } else if (item.command !== undefined) {
                this.CommandCard(item.command)
              } else if (item.replyTail !== undefined) {
                DesktopReplyActions({ messageId: item.replyTail.messageId, text: item.replyTail.text,
                  timestamp: item.replyTail.responseTime, feedbackRows: this.snapshot?.feedbackRows ?? [],
                  canFork: item.replyTail.lastContentSeq === item.replyTail.messageSeq, forking: this.forking,
                  onFork: (): void => { this.onFork(this.sessionId, item.replyTail?.endSeq ?? -1); },
                  choosing: this.choosingFeedback, onWarm: (): void => { this.onWarmFeedback(this.sessionId); },
                  onRating: (messageId: string, rating: DesktopRating): void => {
                    this.onReplyRating(this.sessionId, messageId, rating);
                  } })
              } else if (item.inheritedHistory === true) {
                Row({ space: 8 }) {
                  Divider().layoutWeight(1).color($r('app.color.workspace_border'))
                  Image($r('app.media.dsh_session_branch_outline')).width(14).height(14)
                    .supportSvg2(true).draggable(false).accessibilityLevel('no')
                  Text('以上为继承的历史消息').key('desktopInheritedHistory')
                    .fontSize(12).fontColor($r('sys.color.font_tertiary'))
                  Divider().layoutWeight(1).color($r('app.color.workspace_border'))
                }.width('100%').constraintSize({ maxWidth: 712 })
              } else if (item.message !== undefined) {
                this.Message(item.message, item.attachments ?? [], item.referenceLabels ?? [])
              } else if (item.artifacts !== undefined) {
                DesktopArtifactsPane({ host: this.host, sessionId: this.snapshot?.sessionId ?? '',
                  artifacts: item.artifacts, onFile: this.onArtifactFile, onFileAction: this.onArtifactAction,
                  onReview: this.onChanges })
              } else if (item.process !== undefined) {
                DesktopProcessPane({ group: item.process, expanded: this.expandedProcesses.includes(item.id),
                  inspected: this.inspectedTool, onFile: this.onArtifactFile,
                  onToggle: (): void => {
                    this.expandedProcesses = this.expandedProcesses.includes(item.id) ?
                      this.expandedProcesses.filter((id: string): boolean => id !== item.id) : [...this.expandedProcesses, item.id];
                  },
                  onInspect: (id: string): void => { this.inspectedTool = this.inspectedTool === id ? '' : id; } })
              }
            }
            .width('100%').justifyContent(FlexAlign.Center)
          }
        }, (item: DesktopTranscriptItem): string => this.sessionId + ':' + item.id +
          (item.process?.version ?? '') + (item.command?.completed ?? '') +
          (item.referenceLabels === undefined ? '' : JSON.stringify(item.referenceLabels)))
        if ((this.snapshot?.partial.length ?? 0) > 0) {
          ListItem() {
            Row() {
              Text(this.snapshot?.partial ?? '').fontSize(15).fontColor($r('sys.color.font_primary'))
                .width('100%').constraintSize({ maxWidth: 712 })
            }
            .width('100%').justifyContent(FlexAlign.Center)
          }
        }
        if (this.snapshot?.preparingTool) {
          ListItem() {
            Row({ space: 7 }) {
              LoadingProgress().width(16).height(16)
              Text(`正在准备 ${this.snapshot?.preparingTool ?? ''}`).fontSize(13)
            }.width('100%').constraintSize({ maxWidth: 712 }).padding({ left: 7 })
          }
        }
      }
      .layoutWeight(1).width('100%').padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .scrollBar(BarState.Auto)
      .onScrollIndex((_first: number, last: number): void => {
        this.following = last >= this.messageCount - 1;
      })
      if (this.visibleInteraction().length > 0) {
        Row() {
          ForEach(this.visibleInteraction(), (row: DesktopInteraction) => {
            DesktopInteractionPane({
              request: row, busy: this.busy, onDecision: this.onDecision, onAnswer: this.onAnswer,
              onPlanDecision: this.onPlanDecision, onPlanPreview: this.onPlanPreview
            })
          }, (row: DesktopInteraction): string => row.id)
        }
        .width('100%').padding({ left: 20, right: 20, bottom: 8 }).justifyContent(FlexAlign.Center)
      } else if (this.interactions.some((row: DesktopInteraction): boolean => row.reviewHidden === true)) {
        Button('继续审阅计划', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
          const review = this.interactions.find((row: DesktopInteraction): boolean => row.reviewHidden === true);
          if (review !== undefined) {
            this.onPlanResume(review.id);
          }
        })
      } else if (this.snapshot?.waitingForInput) {
        Text('正在读取待处理请求…').fontSize(13).fontColor($r('sys.color.font_secondary')).padding(8)
      }
      if (this.paletteNotice || this.commandError || this.snapshot?.error) {
        Text(this.paletteNotice || this.commandError || this.snapshot?.error || '')
          .fontSize(13).fontColor($r('sys.color.warning'))
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 16, right: 16, bottom: 6 })
      }
      Column({ space: 6 }) {
        if (this.subagentCanSend()) {
          if ((this.snapshot?.queue.length ?? 0) > 0) {
            DesktopQueueDock({ sessionId: this.sessionId, rows: this.snapshot?.queue ?? [],
              running: this.snapshot?.running === true, busy: this.busy, host: this.host,
              onAction: this.onQueueAction, onOpenImage: this.onOpenImage })
          }
          if (this.snapshot?.goal !== undefined && this.snapshot.goal.phase !== 'complete') {
            DesktopGoalBar({ goal: this.snapshot.goal, busy: this.busy, onAction: this.onGoalAction })
          }
          this.Composer()
        } else {
          Column({ space: 4 }) {
            Text(this.snapshot?.subagent?.mode === 'one-shot' ? '一次性子智能体会话' : '子智能体会话为只读')
              .fontSize(14).fontWeight(FontWeight.Medium)
            Text(this.snapshot?.subagent?.mode === 'one-shot' ? '可以阅读此会话的记录。一次性子智能体无法继续对话。' :
              '读取子会话记录后可确定是否能继续对话。').fontSize(12).fontColor($r('sys.color.font_secondary'))
          }.key('desktopSubagentReadOnly').width('100%').constraintSize({ maxWidth: 712 }).padding(12)
            .alignItems(HorizontalAlign.Start).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
        }
      }.width('100%').padding({ left: 20, right: 20, bottom: 16 }).alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
  }
}
