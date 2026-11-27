import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { desktopAttachmentUri, desktopDroppedFiles, packDesktopClipboardPicture } from '../desktop/DesktopAttachmentIntake';
import type { DesktopDroppedFiles } from '../desktop/DesktopAttachmentIntake';
import { StartupFrameCallback } from '../common/DesktopStartup';
import { getString, parseTarget } from 'connection';
import { WORKSPACE_ARCHIVE_SESSION_ENDPOINT } from 'dshcompat';
import type { DesktopInteraction, DesktopQuestionAnswer } from '../desktop/DesktopInteractions';
import { DesktopTerminalPane } from '../desktop/DesktopTerminalPane';
import { DesktopFilesPane } from '../desktop/DesktopFilesPane';
import { DesktopChangesPane } from '../desktop/DesktopChangesPane';
import { DesktopChangeTarget } from '../desktop/DesktopArtifacts';
import { DesktopPlanPreviewPane } from '../desktop/DesktopPlanPreviewPane';
import type { DesktopPlanDocument } from '../desktop/DesktopPlan';
import { exportDesktopLog } from '../desktop/DesktopLogExport';
import { DesktopLogStage, DesktopSessionLogDialog } from '../desktop/DesktopSessionLogDialog';
import { DesktopGoalAction, DesktopGoalRef } from '../desktop/DesktopGoal';
import { DesktopFeedbackTarget, DesktopRating } from '../desktop/DesktopFeedback';
import { DesktopFeedbackDialog } from '../desktop/DesktopFeedbackDialog';
import { desktopHostProblem } from '../desktop/DesktopHostActions';
import { DesktopAccountPane } from '../desktop/DesktopAccountPane';
import { controlMaterial, copyText, dialogMaterial, mimeTypeForName, openFileLocation, openSystemPreview, PickOutcome,
  pickDocumentUris, pickFolder, readDocumentBytes, uriFromPath } from 'platform';
import { desktopMenuOptions } from '../desktop/DesktopMenuOptions';
import { DesktopPluginsPane } from '../desktop/DesktopPluginsPane';
import { DesktopSchedulePane } from '../desktop/DesktopSchedulePane';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { ModelSelection, QueueActionBody, SessionListItem } from 'appstate';
import { DesktopConversationPane } from '../desktop/DesktopConversationPane';
import { EMPTY_DESKTOP_DRAFT } from '../desktop/DesktopDraftReferences';
import type { DesktopComposerDraft } from '../desktop/DesktopDraftReferences';
import { DesktopShortcutDialog } from '../desktop/DesktopShortcutDialog';
import { DesktopShortcut, desktopShortcutEqual, desktopShortcutFromEvent, desktopShortcutModifiers, desktopShortcutRows,
  desktopShortcutValue, readDesktopShortcuts } from '../desktop/DesktopShortcuts';
import type { DesktopShortcutRow } from '../desktop/DesktopShortcuts';
import { desktopDockCloseTab, desktopDockMerge, desktopDockMoveTab, desktopDockOpen, desktopDockSelect,
  desktopDockSplit, desktopDockTab, DesktopDockKind, emptyDesktopDock } from '../desktop/DesktopRightDock';
import type { DesktopDockLayout, DesktopDockPane, DesktopDockTab } from '../desktop/DesktopRightDock';
import { copyDesktopReferenceImage, DesktopReferenceAction, openDesktopReferenceFile, saveDesktopReferenceFile } from '../desktop/DesktopReferenceActions';
import type { DesktopFileReferenceOffer } from '../desktop/DesktopReferenceActions';
import { desktopReferenceText } from '../desktop/DesktopReferences';
import { DesktopAttachmentViewer, desktopDraftGif } from '../desktop/DesktopAttachments';
import type { DesktopDraftAttachment, DesktopMediaAttachment } from '../desktop/DesktopAttachments';
import type { DesktopUnreadSession } from '../desktop/DesktopSessionReading';
import { DesktopArchiveDialog, DesktopArchiveFilter, desktopArchiveActivity } from '../desktop/DesktopSessionArchive';
import type { DesktopArchiveNotice, DesktopArchiveRequest } from '../desktop/DesktopSessionArchive';
import type { DesktopConversationSnapshot } from '../desktop/DesktopConversation';
import { DesktopWorkspaceData } from '../desktop/DesktopWorkspaceData';
import type { DesktopWorkspaceRow, DesktopWorkspaceSnapshot } from '../desktop/DesktopWorkspaceData';
import { desktopWorkspaceAppearance, setDesktopWorkspaceEnabled, WEB_WORKSPACE_PAGE } from '../desktop/DesktopWorkspacePreference';

const DOMAIN: number = 0xD000;
const TAG: string = 'DshDesktopWorkspace';

interface DesktopWorkspaceGroup {
  id: string;
  title: ResourceStr;
  sessions: SessionListItem[];
}

@Entry({ useSharedStorage: true })
@Component
struct DesktopWorkspace {
  @StorageProp('dshHostLaunchUrl') @Watch('onHostChanged') private hostUrl: string = '';
  @StorageProp('dshHostBootError') private hostError: string = '';
  @LocalStorageLink('dshDesktopWorkspaceActive') private active: boolean = false;
  @LocalStorageLink('dshDesktopWorkspaceId') private workspaceId: string = '';
  @LocalStorageLink('dshDesktopSessionId') private sessionId: string = '';
  @LocalStorageLink('dshDesktopWebSessionId') private webSessionId: string = '';
  @LocalStorageLink('dshDesktopWebWorkspaceId') private webWorkspaceId: string = '';

  @LocalStorageLink('dshDesktopWebAction') private webAction: string = '';

  @State private visibleGroups: DesktopWorkspaceGroup[] = [];
  @State private expandedIds: string[] = [];
  @State private sidebarCollapsed: boolean = false;
  @State private sidebarWidth: number = 280;
  @State private rightPaneWidth: number = 340;
  @State private rightDock: DesktopDockLayout = emptyDesktopDock();
  private readonly docks = new Map<string, DesktopDockLayout>();
  private readonly shownPlanReviews: Set<string> = new Set<string>();
  @State private searchOpen: boolean = false;
  @State private query: string = '';
  @State private selectedWorkspaceTitle: ResourceStr = '';
  @State private appearance: string = 'system';
  @State private shortcutsOpen: boolean = false;
  @State private shortcutBindings: DesktopShortcutRow[] = desktopShortcutRows([]);
  @State private terminalCreateSession: string = '';
  @State private selectedTitle: ResourceStr = '';
  @State private selectedSessionDirectory: string = '';
  @State private referenceOffer: DesktopFileReferenceOffer | undefined = undefined;
  @State private ready: boolean = false;
  @State private error: string = '';
  @State private switching: boolean = false;
  @State @Watch('syncReading') private panel: string = 'session';
  @State private workspaceBusy: boolean = false;
  @State private forking: boolean = false;
  private pendingForkId: string = '';
  private pendingForkSource: string = '';
  @State private archivedIds: string[] = [];
  @State private archiveFilter: DesktopArchiveFilter = DesktopArchiveFilter.HIDE;
  @State private archiveRequest: DesktopArchiveRequest | undefined = undefined;
  @State private archiveNotice: DesktopArchiveNotice | undefined = undefined;
  @State private archiveProblem: string = '';
  private archiveDialog: number = -1;
  private archiveDialogVersion: number = 0;
  private archiveNoticeTimer: number = -1;
  @State private pinned: string[] = [];
  @State private unreadSessions: DesktopUnreadSession[] = [];
  @State private readingReady: boolean = false;
  @State private renameOpen: boolean = false;
  @State private renameDraft: string = '';
  private renameDialog: number = -1;
  private renameDialogVersion: number = 0;
  private renameId: string = '';
  private renameWorkspace: boolean = false;
  @State private chat: DesktopConversationSnapshot | undefined = undefined;
  @State private interactions: DesktopInteraction[] = [];
  @State private draft: DesktopComposerDraft = EMPTY_DESKTOP_DRAFT;
  @State private chatError: string = '';
  @State private attachments: DesktopDraftAttachment[] = [];
  private readonly attachmentsBySession: Map<string, DesktopDraftAttachment[]> = new Map<string, DesktopDraftAttachment[]>();
  private imageDialog: number = -1;
  private imageDialogVersion: number = 0;
  private imageDialogOpening: boolean = false;
  @State private creating: boolean = false;
  @State private busySessions: string[] = [];
  @State private copyingTranscript: boolean = false;
  @State private exportingLog: boolean = false;
  @State private logStage: DesktopLogStage = DesktopLogStage.PREPARING;
  @State private logProblem: string = '';
  private logDialog: number = -1;
  private logDialogVersion: number = 0;
  @State private choosingFeedback: boolean = false;
  private feedbackDialog: number = -1;
  private feedbackDialogVersion: number = 0;
  private openingFeedback: boolean = false;
  private readonly drafts: Map<string, DesktopComposerDraft> = new Map<string, DesktopComposerDraft>();

  @State private groups: DesktopWorkspaceGroup[] = [];
  private data?: DesktopWorkspaceData;
  private workbenchWidth: number = 440;
  private workbenchHeight: number = 640;
  private accountOpening: boolean = false;
  private accountDialog: number = -1;
  private pageActive: boolean = false;
  @State private pageVisible: boolean = false;
  private readingWindow?: window.Window;
  private readingFocused: boolean = false;
  private readonly readingWindowEvent = (event: window.WindowEventType): void => {
    this.readingFocused = event === window.WindowEventType.WINDOW_ACTIVE ||
      (event === window.WindowEventType.WINDOW_SHOWN && this.readingWindow?.isFocused() === true);
    this.syncReading();
  };
  private measured: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.pageActive = true;
    this.pageVisible = true;
    this.attachReadingWindow();
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.appearance = desktopWorkspaceAppearance(context);
    }
    this.onHostChanged();
  }

  private attachReadingWindow(): void {
    if (this.readingWindow !== undefined) { return; }
    const name = this.getUIContext().getWindowName();
    if (name !== undefined) {
      try {
        const owner = window.findWindow(name);
        owner.on('windowEvent', this.readingWindowEvent);
        this.readingWindow = owner;
        this.readingFocused = owner.isFocused();
      } catch (_) {}
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.pageActive = false;
    this.pageVisible = false;
    try { this.readingWindow?.off('windowEvent', this.readingWindowEvent); } catch (_) {}
    this.readingWindow = undefined;
    this.closeAccount();
    this.closeLogDialog();
    this.closeFeedback();
    this.closeImagePreview();
    this.closeRename();
    this.closeArchiveConfirmation();
    this.dismissArchiveNotice();
    this.data?.stop();
    this.data = undefined;
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.reloadShortcutBindings();
    this.attachReadingWindow();
    this.syncReading();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.shortcutsOpen = false;
    this.syncReading();
  }

  private syncReading(): void {
    const chat = this.chat?.sessionId === this.sessionId ? this.chat : undefined;
    const visible = this.pageActive && this.pageVisible && this.panel === 'session' && this.readingFocused;
    this.data?.reading.show(this.sessionId, chat?.historyLoaded === true, chat?.receivedTurn ?? 0, visible);
  }

  onBackPress(): boolean {
    if (this.rightDock.expanded && this.sessionId && this.panel === 'session') {
      if (this.rightDock.fullscreen) { this.toggleDockFullscreen(); }
      else { this.toggleRightDock(); }
      return true;
    }
    if (this.panel !== 'session') {
      this.panel = 'session';
      return true;
    }
    return false;
  }

  private onHostChanged(): void {
    if (!this.pageActive) {
      return;
    }
    this.closeFeedback();
    this.closeImagePreview();
    this.closeArchiveConfirmation();
    this.dismissArchiveNotice();
    this.data?.stop();
    this.data = undefined;
    this.attachmentsBySession.clear();
    this.attachments = [];
    this.groups = [];
    this.visibleGroups = [];
    this.selectedWorkspaceTitle = '';
    this.selectedTitle = '';
    this.ready = false;
    this.error = '';
    this.chat = undefined;
    this.interactions = [];
    this.unreadSessions = [];
    this.readingReady = false;
    this.archivedIds = [];
    this.shownPlanReviews.clear();
    this.docks.clear();
    this.rightDock = emptyDesktopDock();
    this.terminalCreateSession = '';
    this.chatError = '';
    this.creating = false;
    this.workspaceBusy = false;
    this.busySessions = [];
    if (this.hostUrl.length === 0) {
      return;
    }
    this.data = new DesktopWorkspaceData((snapshot: DesktopWorkspaceSnapshot): void => {
      this.error = snapshot.error;
      if (!snapshot.ready) {
        return;
      }
      this.archivedIds = snapshot.archivedIds;
      this.pinned = snapshot.pinned;
      this.updateGroups(snapshot.workspaces, snapshot.sessions);
      this.ready = true;
    }, (snapshot: DesktopConversationSnapshot): void => {
      this.chat = snapshot;
      this.syncReading();
    }, (items: DesktopInteraction[]): void => {
      this.interactions = items;
      const review = items.find((row: DesktopInteraction): boolean =>
        row.sessionId === this.sessionId && row.planReview !== undefined && row.reviewHidden !== true);
      if (review?.planReview !== undefined && this.panel === 'session' && !this.shownPlanReviews.has(review.id)) {
        this.shownPlanReviews.add(review.id);
        this.showPlan(review.planReview.document);
      }
    }, (items: DesktopUnreadSession[], ready: boolean): void => {
      this.unreadSessions = items;
      this.readingReady = ready;
    }, (run: () => void): void => {
      this.getUIContext().postFrameCallback(new StartupFrameCallback(run));
    });
    this.data.start(this.hostUrl);
  }

  private updateGroups(workspaces: DesktopWorkspaceRow[], sessions: SessionListItem[]): void {
    const byMember = new Map<string, DesktopWorkspaceGroup>();
    const byPath = new Map<string, DesktopWorkspaceGroup>();
    this.groups = workspaces.map((row: DesktopWorkspaceRow): DesktopWorkspaceGroup => {
      const group: DesktopWorkspaceGroup = { id: row.id, title: row.title || row.path, sessions: [] };
      row.sessionIds.forEach((id: string): void => { byMember.set(id, group); });
      if (row.path.length > 0) {
        byPath.set(row.path, group);
      }
      return group;
    });
    const ungrouped: DesktopWorkspaceGroup = {
      id: '', title: $r('app.string.desktop_experiment_ungrouped'), sessions: []
    };
    for (const session of sessions) {
      const group = byMember.get(session.id) ?? byPath.get(session.cwd) ?? ungrouped;
      group.sessions.push(session);
      if (session.id === this.sessionId && !this.archivedIds.includes(session.id)) {
        this.selectSession(group, session);
      }
    }
    for (const group of [...this.groups, ungrouped]) {
      if (this.pinned.length > 0) {
        group.sessions.sort((a: SessionListItem, b: SessionListItem): number => this.pinRank(a.id) - this.pinRank(b.id));
      }
    }
    if (ungrouped.sessions.length > 0) {
      this.groups.push(ungrouped);
    }
    if (this.archivedIds.includes(this.sessionId) || !sessions.some((session: SessionListItem): boolean =>
      session.id === this.sessionId)) {
      this.clearSession();
      this.selectedWorkspaceTitle =
        this.groups.find((group: DesktopWorkspaceGroup): boolean => group.id === this.workspaceId)?.title ?? '';
    }
    if (!this.ready) {
      const first = this.groups.find((group: DesktopWorkspaceGroup): boolean => group.id === this.workspaceId) ??
        this.groups[0];
      this.expandedIds = first === undefined ? [] : [first.id];
    }
    this.filterGroups(this.query);
    if (this.pendingForkId && (this.sessionId !== this.pendingForkSource || this.panel !== 'session' ||
      this.openSessionById(this.pendingForkId, false))) {
      this.pendingForkId = '';
      this.pendingForkSource = '';
    }
  }

  private pinRank(id: string): number {
    if (this.archivedIds.includes(id)) { return this.pinned.length; }
    const index = this.pinned.indexOf(id);
    return index < 0 ? this.pinned.length : index;
  }

  private showRename(id: string, workspace: boolean, title: ResourceStr): void {
    if (this.renameOpen || this.workspaceBusy) { return; }
    this.renameId = id;
    this.renameWorkspace = workspace;
    this.renameDraft = this.accessibilityLabel(title);
    this.renameOpen = true;
    this.openRename();
  }

  private async openRename(): Promise<void> {
    const version = ++this.renameDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.RenameDialog(); },
        alignment: DialogAlignment.Center, width: Math.max(220, Math.min(440, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.renameDialogVersion) {
            this.renameDialog = -1;
            this.renameOpen = false;
            this.renameDialogVersion++;
          }
        } });
      if (this.pageActive && version === this.renameDialogVersion) { this.renameDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.renameDialogVersion) { this.renameOpen = false; }
    }
  }

  private closeRename(): void {
    const id = this.renameDialog;
    this.renameDialogVersion++;
    this.renameDialog = -1;
    this.renameOpen = false;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private async rename(): Promise<void> {
    const title = this.renameDraft.trim();
    if (!title || this.workspaceBusy) {
      return;
    }
    const id = this.renameId;
    const workspace = this.renameWorkspace;
    const version = this.renameDialogVersion;
    if (await this.manage(workspace ? 'workspace/rename' : 'session/rename', workspace ?
      { 'workspaceId': id, 'title': title } : { 'sessionId': id, 'title': title })) {
      if (version === this.renameDialogVersion) { this.closeRename(); }
    }
  }

  private async manage(endpoint: string, payload: Record<string, Object>): Promise<boolean> {
    const data = this.data;
    if (data === undefined || this.workspaceBusy) {
      return false;
    }
    this.workspaceBusy = true;
    const problem = await data.manage(endpoint, payload);
    if (this.data !== data) {
      return false;
    }
    this.workspaceBusy = false;
    if (problem.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message: problem });
      return false;
    }
    return true;
  }

  private workspaceActions(group: DesktopWorkspaceGroup): MenuElement[] {
    return [
      { value: '重命名工作区', action: (): void => { this.showRename(group.id, true, group.title); } },
      { value: '移除工作区', action: (): void => {
        this.getUIContext().getPromptAction().showDialog({
          title: '移除工作区',
          message: '仅移除工作区登记，会话与目录文件会保留。',
          buttons: [{ text: '取消', color: '#777777' }, { text: '移除', color: '#B73535' }]
        }).then((result): void => {
          if (result.index === 1 && this.pageActive) {
            this.manage('workspace/delete', { 'workspaceId': group.id });
          }
        }).catch((): void => {});
      } }
    ];
  }

  private sessionActions(session: SessionListItem): MenuElement[] {
    if (this.archivedIds.includes(session.id)) {
      return [
        { value: '复制 Session ID', icon: $r('app.media.dsh_session_copy'),
          action: (): void => { this.copySessionId(session.id); } },
        { value: '取消归档', icon: $r('app.media.dsh_session_unarchive_outline'),
          action: (): void => { this.restoreSession(session.id); } }
      ];
    }
    const pinned = this.pinned.includes(session.id);
    const unread = this.unreadSession(session.id) !== undefined;
    return [
      { value: pinned ? '取消置顶' : '置顶会话',
        icon: pinned ? $r('app.media.dsh_session_pin_fill') : $r('app.media.dsh_session_pin_outline'), action: (): void => {
        this.manage(pinned ? 'workspace/unpinSession' : 'workspace/pinSession', { 'sessionId': session.id });
      } },
      { value: '重命名会话', icon: $r('app.media.dsh_dock_edit'),
        action: (): void => { this.showRename(session.id, false, this.sessionLabel(session)); } },
      { value: unread ? '标为已读' : '标为未读', enabled: this.readingReady,
        icon: unread ? $r('app.media.dsh_session_mail_read_outline') : $r('app.media.dsh_session_mail_unread_outline'),
        action: (): void => { this.markReading(session.id); } },
      { value: '分叉会话', icon: $r('app.media.dsh_session_branch_outline'),
        action: (): void => { this.forkFrom(session.id); } },
      { value: '复制 Session ID', icon: $r('app.media.dsh_session_copy'),
        action: (): void => { this.copySessionId(session.id); } },
      { value: '归档会话', icon: $r('app.media.dsh_session_archive_outline'),
        action: (): void => { this.archiveSession(session.id, this.accessibilityLabel(this.sessionLabel(session))); } }
    ];
  }

  private async archiveSession(id: string, title: string, stop: boolean = false): Promise<void> {
    const data = this.data;
    if (data === undefined || this.workspaceBusy || (stop ? this.archiveRequest?.id !== id :
      this.archiveRequest !== undefined)) { return; }
    this.workspaceBusy = true;
    this.archiveProblem = '';
    const body: Record<string, Object> = { 'sessionId': id };
    if (stop) { body['stopActivity'] = true; }
    const result = await data.actions.call(WORKSPACE_ARCHIVE_SESSION_ENDPOINT, body);
    if (this.data !== data || !this.pageActive) { return; }
    this.workspaceBusy = false;
    if (result.ok) {
      this.closeArchiveConfirmation();
      this.showArchiveNotice(id, stop);
    } else if (!stop && result.error?.code === 'workspace/session-active') {
      this.archiveRequest = { id: id, title: title, activity: desktopArchiveActivity(result.error.details, id) };
      this.openArchiveConfirmation();
    } else {
      const problem = result.error?.message || '无法归档会话，请重试';
      if (stop) { this.archiveProblem = problem; }
      else { this.getUIContext().getPromptAction().showToast({ message: problem }); }
    }
  }

  @Builder
  private ArchiveConfirmationContent(request: DesktopArchiveRequest) {
    DesktopArchiveDialog({ title: request.title, activity: request.activity, busy: this.workspaceBusy,
      problem: this.archiveProblem, onClose: (): void => { this.closeArchiveConfirmation(); },
      onConfirm: (): void => { this.archiveSession(request.id, request.title, true); } })
  }

  private async openArchiveConfirmation(): Promise<void> {
    const request = this.archiveRequest;
    if (request === undefined) { return; }
    const version = ++this.archiveDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.ArchiveConfirmationContent(request); },
        alignment: DialogAlignment.Center,
        width: Math.max(220, Math.min(496, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onWillDismiss: (action): void => { if (!this.workspaceBusy) { action.dismiss(); } },
        onDidDisappear: (): void => {
          if (version === this.archiveDialogVersion) {
            this.archiveDialog = -1;
            this.archiveRequest = undefined;
            this.archiveDialogVersion++;
          }
        }
      });
      if (this.pageActive && version === this.archiveDialogVersion) { this.archiveDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.archiveDialogVersion) {
        this.archiveRequest = undefined;
        prompt.showToast({ message: '无法打开归档确认，请重试' });
      }
    }
  }

  private closeArchiveConfirmation(): void {
    const dialog = this.archiveDialog;
    this.archiveDialog = -1;
    this.archiveDialogVersion++;
    this.archiveRequest = undefined;
    this.archiveProblem = '';
    if (dialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(dialog); }
  }

  private async restoreSession(id: string): Promise<void> {
    if (await this.manage('workspace/unarchiveSession', { 'sessionId': id })) {
      if (this.archiveNotice?.id === id) { this.dismissArchiveNotice(); }
    }
  }

  private setArchiveFilter(filter: DesktopArchiveFilter, sessionId: string = ''): void {
    this.sidebarCollapsed = false;
    this.archiveFilter = filter;
    const group = sessionId ? this.groups.find((item: DesktopWorkspaceGroup): boolean =>
      item.sessions.some((row: SessionListItem): boolean => row.id === sessionId)) : undefined;
    if (group !== undefined && !this.expandedIds.includes(group.id)) {
      this.expandedIds = [...this.expandedIds, group.id];
    }
    this.filterGroups(this.query);
  }

  private archiveFilterActions(): MenuElement[] {
    return [
      { value: (this.archiveFilter === DesktopArchiveFilter.HIDE ? '✓ ' : '') + '隐藏已归档',
        icon: $r('app.media.dsh_session_archive_off_outline'),
        action: (): void => { this.setArchiveFilter(DesktopArchiveFilter.HIDE); } },
      { value: (this.archiveFilter === DesktopArchiveFilter.ALL ? '✓ ' : '') + '全部对话（显示已归档）',
        icon: $r('app.media.dsh_queue_queue_outline'),
        action: (): void => { this.setArchiveFilter(DesktopArchiveFilter.ALL); } },
      { value: (this.archiveFilter === DesktopArchiveFilter.ONLY ? '✓ ' : '') + '仅显示已归档',
        icon: $r('app.media.dsh_session_archive_check_outline'),
        action: (): void => { this.setArchiveFilter(DesktopArchiveFilter.ONLY); } }
    ];
  }

  private showArchiveNotice(id: string, stopped: boolean): void {
    this.archiveNotice = { id: id, stopped: stopped };
    this.pauseArchiveNotice(false);
  }

  private pauseArchiveNotice(paused: boolean): void {
    if (this.archiveNoticeTimer !== -1) {
      clearTimeout(this.archiveNoticeTimer);
      this.archiveNoticeTimer = -1;
    }
    if (!paused && this.archiveNotice !== undefined) {
      this.archiveNoticeTimer = setTimeout((): void => { this.dismissArchiveNotice(); }, 6000);
    }
  }

  private dismissArchiveNotice(): void {
    this.pauseArchiveNotice(true);
    this.archiveNotice = undefined;
  }

  @Builder
  private ArchiveNoticeContent(notice: DesktopArchiveNotice) {
    Row({ space: 5 }) {
      Text(notice.stopped ? '已停止并归档，可' : '会话已归档，可')
        .key('desktopArchiveNoticeText').fontSize(13).fontColor($r('sys.color.font_primary'))
      Button('撤销', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopArchiveUndo')
        .height(30).padding({ left: 5, right: 5 }).enabled(!this.workspaceBusy)
        .onFocus((): void => this.pauseArchiveNotice(true)).onBlur((): void => this.pauseArchiveNotice(false))
        .onClick((): void => { this.restoreSession(notice.id); })
      if (this.archiveFilter === DesktopArchiveFilter.HIDE) {
        Text('或').fontSize(13).fontColor($r('sys.color.font_primary'))
        Button('筛选已归档会话', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopArchiveNoticeFilter')
          .height(30).padding({ left: 5, right: 5 })
          .onFocus((): void => this.pauseArchiveNotice(true)).onBlur((): void => this.pauseArchiveNotice(false))
          .onClick((): void => {
            this.setArchiveFilter(DesktopArchiveFilter.ALL, notice.id);
            this.dismissArchiveNotice();
          })
      }
    }.padding({ left: 14, right: 10, top: 4, bottom: 4 }).constraintSize({ maxWidth: '95%' })
      .borderRadius(14).margin({ bottom: 28 })
      .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : undefined)
      .systemMaterial(controlMaterial()).shadow({ radius: 14, color: '#26000000', offsetY: 4 })
      .onHover((hovered: boolean): void => this.pauseArchiveNotice(hovered))
  }

  private unreadSession(sessionId: string): DesktopUnreadSession | undefined {
    return this.unreadSessions.find((item: DesktopUnreadSession): boolean => item.id === sessionId);
  }

  private async markReading(sessionId: string): Promise<void> {
    const data = this.data;
    if (data === undefined) { return; }
    const problem = await data.reading.mark(sessionId);
    if (problem && this.data === data && this.pageActive) {
      this.getUIContext().getPromptAction().showToast({ message: problem });
    }
  }

  private async copySessionId(sessionId: string): Promise<void> {
    const copied = await copyText(sessionId);
    if (this.pageActive) {
      this.getUIContext().getPromptAction().showToast({ message: copied ? 'Session ID 已复制' : '复制失败，请重试' });
    }
  }

  private focusSearch(): void {
    this.sidebarCollapsed = false;
    this.searchOpen = true;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      if (this.pageActive && this.searchOpen) {
        this.getUIContext().getFocusController().requestFocus('desktopWorkspaceSearch');
      }
    }));
  }

  private reloadShortcutBindings(): void {
    const prefs = readDesktopShortcuts(this.getUIContext().getHostContext());
    this.shortcutBindings = desktopShortcutRows(prefs.overrides);
  }

  private workspaceShortcut(key: DesktopShortcut): boolean {
    if (!this.pageActive || !this.pageVisible || this.shortcutsOpen || this.renameOpen || this.accountOpening ||
      this.accountDialog >= 0 || this.openingFeedback || this.feedbackDialog >= 0 || this.logDialog >= 0 ||
      this.archiveRequest !== undefined || this.imageDialog >= 0 || this.imageDialogOpening) { return false; }
    if (key === DesktopShortcut.REFERENCE) { this.shortcutsOpen = true; return true; }
    if (key === DesktopShortcut.NEW_SESSION) { this.newSession(); return true; }
    if (key === DesktopShortcut.LEFT_SIDEBAR) { this.sidebarCollapsed = !this.sidebarCollapsed; return true; }
    if (key === DesktopShortcut.SEARCH) { this.focusSearch(); return true; }
    if (key === DesktopShortcut.ADD_WORKSPACE) { this.addWorkspace(); return true; }
    if (key === DesktopShortcut.SETTINGS) { this.openSettings(); return true; }
    if (this.panel !== 'session' || !this.sessionId) { return false; }
    if (key === DesktopShortcut.RIGHT_SIDEBAR) { this.toggleRightDock(); return true; }
    if (key === DesktopShortcut.SPLIT_DOCK && this.rightDock.expanded && this.canSplitDock()) {
      this.splitDock(); return true;
    }
    if (key === DesktopShortcut.CLOSE_DOCK_TAB && this.rightDock.expanded) {
      const tab = desktopDockTab(this.rightDock);
      if (tab !== undefined) { this.closeDockTab(this.rightDock.focus, tab.id); return true; }
    }
    if (key === DesktopShortcut.FILES) { this.showWorkspaceFiles(); return true; }
    if (key === DesktopShortcut.NEW_TERMINAL) { this.showTerminal(true); return true; }
    const session = this.groups.find((group: DesktopWorkspaceGroup): boolean =>
      group.id === this.workspaceId)?.sessions.find((row: SessionListItem): boolean => row.id === this.sessionId);
    if (session === undefined || this.archivedIds.includes(session.id)) { return false; }
    if (key === DesktopShortcut.ARCHIVE) {
      this.archiveSession(session.id, this.accessibilityLabel(this.sessionLabel(session)));
      return true;
    }
    if (session.blank) { return false; }
    const detailOpen = this.rightDock.expanded;
    if (key === DesktopShortcut.FORK) {
      this.forkFrom(session.id);
    } else if (key === DesktopShortcut.RENAME && !detailOpen) {
      this.showRename(session.id, false, this.sessionLabel(session));
    } else if (key === DesktopShortcut.TOGGLE_READ && !detailOpen && this.readingReady) {
      this.markReading(session.id);
    } else {
      return false;
    }
    return true;
  }

  private terminalShortcut(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    const key = desktopShortcutFromEvent(event);
    if (!key.ctrl && !key.alt) { return false; }
    const row = this.shortcutBindings.find((item: DesktopShortcutRow): boolean => !item.occupiedBy &&
      desktopShortcutEqual(item.binding, key));
    return row !== undefined && [DesktopShortcut.REFERENCE, DesktopShortcut.SETTINGS, DesktopShortcut.FILES,
      DesktopShortcut.NEW_TERMINAL, DesktopShortcut.RIGHT_SIDEBAR, DesktopShortcut.SPLIT_DOCK,
      DesktopShortcut.CLOSE_DOCK_TAB].includes(row.id) && this.workspaceShortcut(row.id);
  }

  private filterGroups(value: string): void {
    this.query = value;
    const needle = value.trim().toLowerCase();
    const archived = new Set<string>(this.archivedIds);
    const matches: DesktopWorkspaceGroup[] = [];
    this.groups.forEach((group: DesktopWorkspaceGroup): void => {
      const sessions = group.sessions.filter((row: SessionListItem): boolean => {
        const isArchived = archived.has(row.id);
        return (this.archiveFilter === DesktopArchiveFilter.ALL ||
          isArchived === (this.archiveFilter === DesktopArchiveFilter.ONLY)) && row.title.toLowerCase().includes(needle);
      });
      if (sessions.length > 0 || (!needle && this.archiveFilter !== DesktopArchiveFilter.ONLY && group.id)) {
        matches.push({ id: group.id, title: group.title, sessions: sessions });
      }
    });
    this.visibleGroups = matches;
  }

  private isExpanded(id: string): boolean {
    return this.query.trim().length > 0 || this.expandedIds.includes(id);
  }

  private toggleWorkspace(id: string): void {
    this.expandedIds = this.expandedIds.includes(id) ? this.expandedIds.filter((item: string): boolean => item !== id) :
      [...this.expandedIds, id];
  }

  private sessionLabel(session: SessionListItem): ResourceStr {
    return session.title || $r('app.string.desktop_experiment_unnamed');
  }

  private selectSession(group: DesktopWorkspaceGroup, session: SessionListItem): void {
    if (this.sessionId !== session.id) {
      this.terminalCreateSession = '';
      this.rightDock = this.docks.get(session.id) ?? emptyDesktopDock();
      this.referenceOffer = undefined;
      this.closeFeedback();
      this.closeImagePreview();
      this.draft = this.drafts.get(session.id) ?? EMPTY_DESKTOP_DRAFT;
      this.attachments = this.attachmentsBySession.get(session.id) ?? [];
      this.chatError = '';
    }
    this.sessionId = session.id;
    this.workspaceId = group.id;
    this.selectedTitle = this.sessionLabel(session);
    this.selectedSessionDirectory = session.cwd;
    this.selectedWorkspaceTitle = group.title;
    this.data?.conversation.open(session.id);
  }

  private changeDraft(session: string, value: DesktopComposerDraft): void {
    if (session && this.sessionId === session) {
      this.draft = value;
      if (value.text.length > 0) {
        this.drafts.set(session, value);
      } else {
        this.drafts.delete(session);
      }
    }
  }

  private clearSession(): void {
    this.closeFeedback();
    this.closeImagePreview();
    this.sessionId = '';
    this.terminalCreateSession = '';
    this.rightDock = emptyDesktopDock();
    this.referenceOffer = undefined;
    this.selectedTitle = '';
    this.draft = EMPTY_DESKTOP_DRAFT;
    this.attachments = [];
    this.chatError = '';
    this.data?.conversation.open('');
  }

  private async newSession(): Promise<void> {
    const data = this.data;
    if (data === undefined || !this.ready || this.creating) {
      return;
    }
    const workspace = this.groups.find((group: DesktopWorkspaceGroup): boolean =>
      group.id.length > 0 && group.id === this.workspaceId) ??
      this.groups.find((group: DesktopWorkspaceGroup): boolean => group.id.length > 0);
    if (workspace === undefined) {
      this.addWorkspace();
      return;
    }
    this.creating = true;
    this.chatError = '';
    const previousWorkspace = this.workspaceId;
    const previousSession = this.sessionId;
    const id = await data.createSession(workspace.id);
    if (!this.pageActive || this.data !== data) {
      return;
    }
    this.creating = false;
    if (id.length === 0) {
      this.chatError = this.accessibilityLabel($r('app.string.desktop_chat_create_failed'));
      return;
    }
    const group = this.groups.find((item: DesktopWorkspaceGroup): boolean => item.id === workspace.id);
    const session = group?.sessions.find((item: SessionListItem): boolean => item.id === id);
    if (group !== undefined && session !== undefined && previousWorkspace === this.workspaceId &&
      previousSession === this.sessionId) {
      this.pickWorkspace(group);
      this.selectSession(group, session);
      this.panel = 'session';
    }
  }

  private async chatAction(run: (id: string) => Promise<string>, sentDraft?: string): Promise<string> {
    const id = this.sessionId;
    const data = this.data;
    if (id.length === 0 || data === undefined || this.busySessions.includes(id)) {
      return '当前会话暂不可操作';
    }
    this.busySessions = [...this.busySessions, id];
    this.chatError = '';
    const error = await run(id);
    if (!this.pageActive || this.data !== data) {
      return error;
    }
    this.busySessions = this.busySessions.filter((other: string): boolean => other !== id);
    if (error.length === 0 && sentDraft !== undefined && this.drafts.get(id)?.text === sentDraft) {
      this.drafts.delete(id);
      if (this.sessionId === id) {
        this.draft = EMPTY_DESKTOP_DRAFT;
      }
    }
    if (this.sessionId === id) {
      this.chatError = error;
    }
    return error;
  }

  private attachDocument(): void {
    const data = this.data;
    const context = this.getUIContext().getHostContext();
    if (data === undefined || context === undefined) {
      return;
    }
    this.chatAction(async (id: string): Promise<string> => {
      try {
        const picked = await pickDocumentUris(context, 500);
        if (picked.outcome === PickOutcome.CANCELLED) {
          return '';
        }
        if (picked.outcome !== PickOutcome.PICKED) {
          return picked.reason;
        }
        return await this.stageDocuments(data, id, picked.uris);
      } catch (_) {
        return '无法读取所选文件';
      }
    });
  }

  private async stageDocuments(data: DesktopWorkspaceData, id: string, uris: string[]): Promise<string> {
    const problems: string[] = [];
    for (const uri of uris) {
      if (this.data !== data) { return ''; }
      const problem = await this.stageDocument(data, id, uri);
      if (problem) { problems.push(problem); }
    }
    return problems.join('\n');
  }

  private attachDroppedFiles(files: DesktopDroppedFiles): void {
    const data = this.data;
    if (data === undefined) { return; }
    this.chatAction(async (id: string): Promise<string> => {
      const problems = await this.stageDocuments(data, id, files.uris);
      if (!files.hasFolder) { return problems; }
      const folderProblem = '请从工作区文件面板添加目录中的文件';
      return problems ? problems + '\n' + folderProblem : folderProblem;
    });
  }

  private attachClipboard(): void {
    const data = this.data;
    if (data === undefined) { return; }
    this.chatAction(async (id: string): Promise<string> => {
      try {
        const board = pasteboard.getSystemPasteboard();
        const clipboard = await board.getData();
        const problems: string[] = [];
        const uris = new Set<string>();
        let pictureCount = 0;
        for (let index = 0; index < clipboard.getRecordCount(); index++) {
          if (this.data !== data) { return ''; }
          const record = clipboard.getRecord(index);
          if (record.mimeType === pasteboard.MIMETYPE_TEXT_URI) {
            const uri = desktopAttachmentUri(record.uri);
            if (uri) { uris.add(uri); }
          } else if (record.mimeType === pasteboard.MIMETYPE_PIXELMAP && record.pixelMap !== undefined) {
            const picture = record.pixelMap;
            pictureCount++;
            const name = pictureCount === 1 ? '剪贴板图片.png' : '剪贴板图片-' + pictureCount + '.png';
            try {
              const bytes = await packDesktopClipboardPicture(picture);
              const problem = await this.stageAttachment(data, id, name, bytes, 'image/png');
              if (problem) { problems.push(problem); }
            } catch (_) {
              problems.push(name + '：无法读取剪贴板图片');
            } finally {
              await picture.release().catch((): void => {});
            }
          }
        }
        if (uris.size === 0 && pictureCount === 0) {
          const files = desktopDroppedFiles(await board.getUnifiedData());
          for (const uri of files.uris) { uris.add(uri); }
          if (files.hasFolder) { problems.push('请从工作区文件面板添加目录中的文件'); }
        }
        const problemsFromFiles = await this.stageDocuments(data, id, Array.from(uris));
        if (problemsFromFiles) { problems.push(problemsFromFiles); }
        if (uris.size === 0 && pictureCount === 0 && problems.length === 0) { return '剪贴板中没有可添加的图片或文件'; }
        return problems.join('\n');
      } catch (_) {
        return '无法读取剪贴板附件';
      }
    });
  }

  private attachWorkspaceFile(path: string, name: string): void {
    const data = this.data;
    if (data === undefined) {
      return;
    }
    this.chatAction(async (id: string): Promise<string> => {
      const response = await data.actions.call('workspaceFiles/stat', {
        'workspaceFileScopeId': id, 'path': path
      });
      if (!response.ok) {
        return desktopHostProblem(response);
      }
      const absolutePath = getString(response.value, 'absolutePath') ?? '';
      const uri = absolutePath.startsWith('/') ? uriFromPath(absolutePath) : '';
      if (!uri) {
        return '无法访问宿主返回的文件';
      }
      return this.stageDocument(data, id, uri, name);
    });
  }

  private async stageDocument(data: DesktopWorkspaceData, id: string, uri: string, name: string = ''): Promise<string> {
    if (this.data !== data) { return ''; }
    const file = await readDocumentBytes(uri, data.conversation.imageLimit(id));
    if (file.outcome !== PickOutcome.PICKED || file.data === undefined) {
      return file.reason || '无法读取所选附件';
    }
    return this.stageAttachment(data, id, name || file.name, file.data, file.mediaType);
  }

  private async stageAttachment(data: DesktopWorkspaceData, id: string, label: string, bytes: ArrayBuffer,
    mediaType: string): Promise<string> {
    if (this.data !== data) { return ''; }
    try {
      const uploaded = await data.conversation.upload(id, label, bytes, mediaType);
      if (typeof uploaded === 'string') { return `${label}：${uploaded}`; }
      if (mediaType === 'image/gif' && uploaded.picture !== undefined && this.data === data) {
        const animation = await desktopDraftGif(bytes).catch((): string => '');
        if (animation) { uploaded.picture.draftAnimation = animation; }
      }
      if (this.data === data) {
        this.setAttachments(id, [...(this.attachmentsBySession.get(id) ?? []), uploaded]);
      }
      return '';
    } catch (_) {
      return `${label}：附件上传失败`;
    }
  }

  private setAttachments(id: string, items: DesktopDraftAttachment[]): void {
    if (items.length === 0) {
      this.attachmentsBySession.delete(id);
    } else {
      this.attachmentsBySession.set(id, items);
    }
    if (id === this.sessionId) {
      this.attachments = items;
    }
  }

  @Builder
  private ImagePreviewContent(sessionId: string, row: DesktopMediaAttachment, height: number) {
    DesktopAttachmentViewer({ sessionId: sessionId, attachment: row, host: this.data?.actions, viewportHeight: height,
      onClose: (): void => { this.closeImagePreview(); } })
  }

  private async openImagePreview(row: DesktopMediaAttachment): Promise<void> {
    if (!this.sessionId || row.reference === undefined || this.imageDialog >= 0 || this.imageDialogOpening) { return; }
    const sessionId = this.sessionId;
    const version = ++this.imageDialogVersion;
    const height = Math.max(120, Math.min(490, this.workbenchHeight - 135));
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    this.imageDialogOpening = true;
    try {
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.ImagePreviewContent(sessionId, row, height); },
        width: Math.max(220, Math.min(760, this.workbenchWidth - 32)),
        alignment: DialogAlignment.Center, autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.imageDialogVersion) {
            this.imageDialog = -1;
            this.imageDialogOpening = false;
            this.imageDialogVersion++;
          }
        }
      });
      if (this.pageActive && this.sessionId === sessionId && version === this.imageDialogVersion) { this.imageDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.imageDialogVersion) { prompt.showToast({ message: '无法打开图片预览' }); }
    } finally {
      if (version === this.imageDialogVersion) { this.imageDialogOpening = false; }
    }
  }

  private closeImagePreview(): void {
    const dialog = this.imageDialog;
    this.imageDialog = -1;
    this.imageDialogOpening = false;
    this.imageDialogVersion++;
    if (dialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(dialog); }
  }

  private sendMessage(alternateDelivery: boolean): void {
    const conversation = this.data?.conversation;
    const text = this.draft.text;
    const files = this.attachments;
    if (conversation !== undefined && (text.trim().length > 0 || files.length > 0)) {
      this.chatAction(async (id: string): Promise<string> => {
        const result = await conversation.send(id, text, files,
          (sessionId: string): Promise<string> => this.exportLog(sessionId),
          (sessionId: string): Promise<string> => this.openSessionFeedback(sessionId), alternateDelivery);
        if (result.length === 0 && conversation === this.data?.conversation) {
          this.setAttachments(id, []);
        }
        return result;
      }, text);
    }
  }

  private openSessionFeedback(sessionId: string): Promise<string> {
    return this.openFeedback({ sessionId: sessionId, messageId: '', version: '' });
  }

  private async chooseReplyRating(sessionId: string, messageId: string, rating: DesktopRating): Promise<void> {
    const feedback = this.data?.conversation.feedback;
    if (feedback === undefined || !messageId || sessionId !== this.sessionId || this.choosingFeedback ||
      this.feedbackDialog >= 0 || this.openingFeedback) { return; }
    this.choosingFeedback = true;
    try {
      const loadProblem = await feedback.ensure(sessionId);
      if (!this.pageActive || this.sessionId !== sessionId || this.data?.conversation.feedback !== feedback) { return; }
      const previous = feedback.current(messageId);
      const target: DesktopFeedbackTarget = { sessionId: sessionId, messageId: messageId,
        rating: rating, version: previous?.version ?? '' };
      const problem = !loadProblem && previous?.rating === rating ?
        await feedback.retract(target) : await this.openFeedback(target);
      if (problem && this.pageActive && this.sessionId === sessionId) {
        this.getUIContext().getPromptAction().showToast({ message: problem });
      }
    } finally {
      this.choosingFeedback = false;
    }
  }

  @Builder
  private FeedbackContent(target: DesktopFeedbackTarget, version: number) {
    DesktopFeedbackDialog({
      onClose: (): void => { this.closeFeedback(); },
      onSubmit: (category: string, note: string): Promise<string> => this.submitFeedback(target, version, category, note)
    })
  }

  private async openFeedback(target: DesktopFeedbackTarget): Promise<string> {
    if (!this.pageActive || !target.sessionId || target.sessionId !== this.sessionId || this.data === undefined) {
      return '当前会话暂不可反馈';
    }
    if (this.feedbackDialog >= 0 || this.openingFeedback) { return ''; }
    this.openingFeedback = true;
    const version = ++this.feedbackDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.FeedbackContent(target, version); },
        alignment: DialogAlignment.Center, width: Math.max(230, Math.min(488, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.feedbackDialogVersion) { this.feedbackDialog = -1; this.feedbackDialogVersion++; }
        } });
      if (this.pageActive && this.sessionId === target.sessionId && version === this.feedbackDialogVersion) {
        this.feedbackDialog = id;
      } else {
        prompt.closeCustomDialog(id);
      }
      return '';
    } catch (_) {
      return '无法打开反馈弹窗';
    } finally {
      this.openingFeedback = false;
    }
  }

  private closeFeedback(): void {
    const id = this.feedbackDialog;
    this.feedbackDialog = -1;
    this.feedbackDialogVersion++;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private async submitFeedback(target: DesktopFeedbackTarget, version: number, category: string,
    note: string): Promise<string> {
    const feedback = this.data?.conversation.feedback;
    if (feedback === undefined || this.sessionId !== target.sessionId || version !== this.feedbackDialogVersion) {
      return '当前会话暂不可反馈';
    }
    const problem = await feedback.record(target, category, note);
    if (!problem && this.pageActive && this.sessionId === target.sessionId && version === this.feedbackDialogVersion) {
      this.closeFeedback();
      this.getUIContext().getPromptAction().showToast({ message: '感谢你的反馈' });
    }
    return problem;
  }

  private async copyTranscript(): Promise<void> {
    const conversation = this.data?.conversation;
    const sessionId = this.sessionId;
    if (conversation === undefined || !sessionId || this.copyingTranscript) { return; }
    this.copyingTranscript = true;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const reply = await conversation.readMarkdown(sessionId);
      if (!this.pageActive || this.data?.conversation !== conversation) { return; }
      if (!reply.ok || typeof reply.value !== 'string' || !reply.value.trim()) {
        prompt.showToast({ message: '无法读取 Session 进行复制，请重试' });
        return;
      }
      const copied = await copyText(reply.value);
      if (this.pageActive) {
        prompt.showToast({ message: copied ? 'Session 已复制为 Markdown' : '无法写入剪贴板，请检查权限后重试' });
      }
    } finally {
      this.copyingTranscript = false;
    }
  }

  private async exportLog(id: string): Promise<string> {
    const conversation = this.data?.conversation;
    const context = this.getUIContext().getHostContext();
    if (conversation === undefined || context === undefined) { return '当前会话暂不可导出'; }
    if (this.exportingLog) { return '当前正在导出会话日志'; }
    this.exportingLog = true;
    this.logStage = DesktopLogStage.PREPARING;
    this.logProblem = '';
    try {
      await this.openLogDialog();
      if (!this.pageActive || this.data?.conversation !== conversation) { return ''; }
      const result = await exportDesktopLog(context, id,
        (onData: (chunk: ArrayBuffer) => void): Promise<string> => conversation.downloadLog(id, onData),
        (): boolean => {
          if (!this.pageActive || this.data?.conversation !== conversation) { return false; }
          this.logStage = DesktopLogStage.CHOOSING;
          return true;
        });
      if (!this.pageActive || this.data?.conversation !== conversation) { return ''; }
      if (result.error) {
        this.logProblem = result.error;
        this.logStage = DesktopLogStage.FAILED;
      } else if (result.saved) {
        this.logStage = DesktopLogStage.SAVED;
      } else {
        this.closeLogDialog();
      }
      return result.error;
    } finally {
      this.exportingLog = false;
    }
  }

  @Builder
  private LogDialogContent() {
    DesktopSessionLogDialog({ stage: this.logStage, problem: this.logProblem,
      onClose: (): void => { this.closeLogDialog(); } })
  }

  private async openLogDialog(): Promise<void> {
    if (this.logDialog >= 0) { return; }
    const version = ++this.logDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.LogDialogContent(); },
        alignment: DialogAlignment.Center, width: Math.max(220, Math.min(448, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.logDialogVersion) { this.logDialog = -1; this.logDialogVersion++; }
        } });
      if (this.pageActive && version === this.logDialogVersion) { this.logDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.pageActive) { prompt.showToast({ message: '正在导出 Session' }); }
    }
  }

  private closeLogDialog(): void {
    const id = this.logDialog;
    this.logDialog = -1;
    this.logDialogVersion++;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private setDock(layout: DesktopDockLayout): void {
    if (!this.sessionId) { return; }
    this.rightDock = layout;
    this.docks.set(this.sessionId, layout);
  }

  private dockShows(kind: DesktopDockKind): boolean {
    return this.rightDock.expanded && this.rightDock.panes.some((pane: DesktopDockPane): boolean =>
      pane.tabs.some((tab: DesktopDockTab): boolean => tab.id === pane.active && tab.kind === kind));
  }

  private focusDockPane(index: number): void {
    if (this.rightDock.focus === index || index >= this.rightDock.panes.length) { return; }
    const next: DesktopDockLayout = { panes: this.rightDock.panes, focus: index,
      expanded: this.rightDock.expanded, fullscreen: this.rightDock.fullscreen };
    this.setDock(next);
  }

  private toggleRightDock(): void {
    const next: DesktopDockLayout = { panes: this.rightDock.panes, focus: this.rightDock.focus,
      expanded: !this.rightDock.expanded, fullscreen: false };
    this.setDock(next);
  }

  private toggleDockFullscreen(): void {
    const next: DesktopDockLayout = { panes: this.rightDock.panes, focus: this.rightDock.focus,
      expanded: true, fullscreen: !this.rightDock.fullscreen };
    this.setDock(next);
  }

  private splitDock(): void {
    if (!this.canSplitDock()) { return; }
    this.setDock(desktopDockSplit(this.rightDock));
  }

  private canSplitDock(): boolean {
    return this.rightDock.panes.length === 1 && this.workbenchWidth >= 540;
  }

  private dockAvailableWidth(): number {
    return this.workbenchWidth - (this.sidebarCollapsed ? 52 : this.sidebarWidth) - 275;
  }

  private dockWidth(): number {
    const ideal = this.rightDock.panes.length === 1 ? this.rightPaneWidth : Math.max(540, this.rightPaneWidth);
    return Math.min(ideal, Math.max(220, this.dockAvailableWidth()));
  }

  private dockFullscreen(): boolean {
    return this.rightDock.expanded && (this.rightDock.fullscreen || this.dockAutoFullscreen());
  }

  private dockAutoFullscreen(): boolean {
    return (this.rightDock.panes.length > 1 && this.dockAvailableWidth() < 540) || this.dockAvailableWidth() < 220;
  }

  private closeDockTab(index: number, id: string): void {
    if (id === DesktopDockKind.TERMINAL) { this.terminalCreateSession = ''; }
    this.setDock(desktopDockCloseTab(this.rightDock, index, id));
  }

  private showPlan(document: DesktopPlanDocument): void {
    const tab: DesktopDockTab = { id: 'plan:' + document.callId, kind: DesktopDockKind.PLAN,
      title: document.title || '计划预览', plan: document };
    this.setDock(desktopDockOpen(this.rightDock, tab));
  }

  private showWorkspaceFiles(toggle: boolean = false): void {
    if (toggle && this.dockShows(DesktopDockKind.FILES)) { this.toggleRightDock(); return; }
    const tab: DesktopDockTab = { id: DesktopDockKind.FILES, kind: DesktopDockKind.FILES, title: '工作区文件' };
    this.setDock(desktopDockOpen(this.rightDock, tab, false));
  }

  private showTerminal(create: boolean = false, toggle: boolean = false): void {
    if (toggle && this.dockShows(DesktopDockKind.TERMINAL)) { this.toggleRightDock(); return; }
    const tab: DesktopDockTab = { id: DesktopDockKind.TERMINAL, kind: DesktopDockKind.TERMINAL, title: '终端' };
    this.setDock(desktopDockOpen(this.rightDock, tab, false));
    if (create) { this.terminalCreateSession = this.sessionId; }
  }

  private showArtifact(path: string, name: string): void {
    if (!path) { return; }
    const tab: DesktopDockTab = { id: 'file:' + path, kind: DesktopDockKind.PREVIEW, title: name || path,
      file: { path: path, name: name } };
    this.setDock(desktopDockOpen(this.rightDock, tab, false));
  }

  private showChanges(target: DesktopChangeTarget): void {
    if (target.sessionId !== this.sessionId) { return; }
    const tab: DesktopDockTab = { id: 'changes:' + target.sequence, kind: DesktopDockKind.CHANGES,
      title: '改动审阅', changes: target };
    this.setDock(desktopDockOpen(this.rightDock, tab));
  }

  private async referenceFileAction(action: DesktopReferenceAction, path: string, name: string): Promise<void> {
    const sessionId = this.sessionId;
    const host = this.data?.actions;
    if (!sessionId || host === undefined) { return; }
    const result = await host.call('workspaceFiles/stat', { 'workspaceFileScopeId': sessionId, 'path': path });
    if (!this.pageActive || this.sessionId !== sessionId || this.data?.actions !== host) { return; }
    const absolute = getString(result.value, 'absolutePath') ?? '';
    const ability = this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
    const toast = this.getUIContext().getPromptAction();
    if (!result.ok || !absolute.startsWith('/')) {
      toast.showToast({ message: '无法访问此文件' });
      return;
    }
    try {
      switch (action) {
        case DesktopReferenceAction.ADD_TO_CHAT:
          if (desktopReferenceText(absolute, false, true) && !this.busySessions.includes(sessionId) &&
            this.chat?.sessionId === sessionId && this.chat?.loading === false) {
            this.referenceOffer = { sessionId: sessionId, path: absolute };
          } else {
            toast.showToast({ message: '无法添加文件，请返回对话后重试' });
          }
          break;
        case DesktopReferenceAction.COPY_PATH:
          toast.showToast({ message: await copyText(absolute) ? '已复制' : '无法复制路径' });
          break;
        case DesktopReferenceAction.COPY_IMAGE:
          await copyDesktopReferenceImage(absolute);
          toast.showToast({ message: '已复制' });
          break;
        case DesktopReferenceAction.DOWNLOAD:
          if (ability === undefined) { throw new Error('Missing context'); }
          if (await saveDesktopReferenceFile(ability, absolute, name)) {
            toast.showToast({ message: '已下载' });
          }
          break;
        case DesktopReferenceAction.OPEN:
          if (ability === undefined || !await openDesktopReferenceFile(ability, absolute, name)) {
            toast.showToast({ message: '系统未能打开此文件' });
          }
          break;
        case DesktopReferenceAction.REVEAL:
          if (ability === undefined || openFileLocation(ability, absolute) !== 'ok') {
            toast.showToast({ message: '无法在系统文件中定位' });
          }
          break;
      }
    } catch (_) {
      toast.showToast({ message: action === DesktopReferenceAction.DOWNLOAD ? '无法保存文件' : '无法复制图片' });
    }
  }

  private async openArtifactAction(path: string, name: string, reveal: boolean): Promise<void> {
    const sessionId = this.sessionId;
    const result = await this.data?.actions.call('workspaceFiles/stat', { 'workspaceFileScopeId': sessionId, 'path': path });
    const ability = this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
    if (!this.pageActive || this.sessionId !== sessionId) {
      return;
    }
    const absolute = getString(result?.value, 'absolutePath') ?? '';
    const ok = result?.ok === true && absolute.startsWith('/') && ability !== undefined && (reveal ?
      openFileLocation(ability, absolute) === 'ok' :
      await openSystemPreview(ability, uriFromPath(absolute), name, mimeTypeForName(name)));
    if (!ok) {
      this.getUIContext().getPromptAction().showToast({ message: reveal ? '无法在系统文件中定位' : '系统未能打开此文件的预览' });
    }
  }

  private stopMessage(): void {
    const conversation = this.data?.conversation;
    if (conversation !== undefined) {
      this.chatAction((id: string): Promise<string> => conversation.cancel(id));
    }
  }

  private chooseModel(selection: ModelSelection): void {
    const conversation = this.data?.conversation;
    if (conversation !== undefined) {
      this.chatAction((id: string): Promise<string> => conversation.selectModel(id, selection));
    }
  }

  private workspaceMenu(): Array<MenuElement> {
    return this.groups.map((group: DesktopWorkspaceGroup): MenuElement => {
      return { value: group.title, action: (): void => this.pickWorkspace(group) };
    });
  }

  private pickWorkspace(group: DesktopWorkspaceGroup): void {
    if (group.id !== this.workspaceId) {
      this.clearSession();
    }
    this.workspaceId = group.id;
    this.selectedWorkspaceTitle = group.title;
    this.sidebarCollapsed = false;
    this.searchOpen = false;
    this.filterGroups('');
    if (!this.expandedIds.includes(group.id)) {
      this.expandedIds = [...this.expandedIds, group.id];
    }
  }

  private async addWorkspace(): Promise<void> {
    const data = this.data;
    const ui = this.getUIContext();
    const context = ui.getHostContext();
    if (data === undefined || !this.ready || context === undefined || this.workspaceBusy) {
      return;
    }
    this.workspaceBusy = true;
    try {
      const picked = await pickFolder(context);
      if (picked.outcome === PickOutcome.CANCELLED || this.data !== data) {
        return;
      }
      if (picked.outcome !== PickOutcome.PICKED || picked.path.length === 0) {
        ui.getPromptAction().showToast({ message: picked.reason || $r('app.string.desktop_experiment_action_failed') });
        return;
      }
      const id = await data.createWorkspace(picked.path);
      if (this.data !== data) {
        return;
      }
      if (id.length === 0) {
        ui.getPromptAction().showToast({ message: $r('app.string.desktop_experiment_action_failed') });
        return;
      }
      this.clearSession();
      this.workspaceId = id;
      this.panel = 'session';
      this.expandedIds = [...this.expandedIds.filter((value: string): boolean => value !== id), id];
      this.selectedWorkspaceTitle = picked.name || picked.path;
      if (picked.reason.length > 0) {
        ui.getPromptAction().showToast({ message: picked.reason });
      }
    } catch (_) {
      ui.getPromptAction().showToast({ message: $r('app.string.desktop_experiment_action_failed') });
    } finally {
      if (this.data === data) {
        this.workspaceBusy = false;
      }
    }
  }

  private async openSettings(section: string = 'settings.general'): Promise<void> {
    if (this.switching) {
      return;
    }
    this.switching = true;
    const ui = this.getUIContext();
    const params: Record<string, Object> = { 'desktopSettings': section };
    try {
      await ui.getRouter().pushUrl({ url: 'pages/Index', params: params });
    } catch (_) {
      ui.getPromptAction().showToast({ message: $r('app.string.desktop_experiment_switch_failed') });
    } finally {
      this.switching = false;
    }
  }

  private async forkFrom(source: string, atSeq?: number): Promise<void> {
    const data = this.data;
    if (data === undefined || this.forking ||
      (atSeq !== undefined && (source !== this.sessionId || !data.conversation.canForkAt(atSeq)))) {
      return;
    }
    this.forking = true;
    try {
      const result = await data.forkSession(source, atSeq);
      if (!this.pageActive || this.data !== data) { return; }
      if (result.problem) {
        this.getUIContext().getPromptAction().showToast({ message: result.problem });
      } else if (atSeq !== undefined && result.id && this.sessionId === source && this.panel === 'session' &&
        !this.openSessionById(result.id, false)) {
        this.pendingForkId = result.id;
        this.pendingForkSource = source;
      }
    } finally {
      this.forking = false;
    }
  }

  private openSessionById(id: string, notifyMissing: boolean = true): boolean {
    if (this.archivedIds.includes(id)) {
      if (notifyMissing) {
        this.getUIContext().getPromptAction().showToast({ message: '已归档对话暂时无法查看，请取消归档后查看' });
      }
      return false;
    }
    for (const group of this.groups) {
      const row = group.sessions.find((session: SessionListItem): boolean => session.id === id);
      if (row !== undefined) {
        this.selectSession(group, row);
        this.panel = 'session';
        if (!this.expandedIds.includes(group.id)) { this.expandedIds = [...this.expandedIds, group.id]; }
        return true;
      }
    }
    if (notifyMissing) { this.getUIContext().getPromptAction().showToast({ message: '会话暂不可用' }); }
    return false;
  }

  @Builder
  private AccountDialog() {
    DesktopAccountPane({
      host: this.data?.actions,
      callbackOrigin: parseTarget(this.hostUrl)?.address.baseUrl ?? '',
      onClose: (): void => { this.closeAccount(); },
      onAddKey: (): void => {
        this.closeAccount();
        this.openSettings('settings.models');
      }
    })
  }

  private async openAccount(): Promise<void> {
    if (this.accountOpening || this.accountDialog >= 0) {
      return;
    }
    this.accountOpening = true;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.AccountDialog(); },
        alignment: DialogAlignment.Center,
        width: Math.max(220, Math.min(440, this.workbenchWidth - 32)),
        autoCancel: false,
        systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => { this.accountDialog = -1; }
      });
      if (this.pageActive) {
        this.accountDialog = id;
      } else {
        prompt.closeCustomDialog(id);
      }
    } catch (_) {
      if (this.pageActive) {
        prompt.showToast({ message: '无法打开账号弹窗' });
      }
    } finally {
      this.accountOpening = false;
    }
  }

  private closeAccount(): void {
    if (this.accountDialog >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.accountDialog);
    }
  }

  private sidebarActions(footer: boolean): Array<MenuElement> {
    if (footer) {
      return [
        { value: '账号', action: (): void => { this.openAccount(); } },
        { value: $r('app.string.desktop_workspace_settings'), action: (): void => { this.openSettings(); } },
        { value: $r('app.string.desktop_experiment_open_web_home'), action: (): void => { this.openWeb(false); } },
        { value: $r('app.string.desktop_experiment_exit'), action: (): void => { this.openWeb(true); } }
      ];
    }
    return [
      { value: $r('app.string.desktop_workspace_settings'), action: (): void => { this.openSettings(); } },
      { value: $r('app.string.desktop_experiment_plugins'), action: (): void => { this.panel = 'plugins'; } },
      { value: $r('app.string.desktop_experiment_schedule'), action: (): void => { this.panel = 'schedule'; } },
      { value: '已归档会话', action: (): void => { this.setArchiveFilter(DesktopArchiveFilter.ONLY); } }
    ];
  }

  private groupKey(group: DesktopWorkspaceGroup): string {
    const title = typeof group.title === 'string' ? group.title : '';
    const rows = group.sessions.map((session: SessionListItem): string =>
      JSON.stringify([session.id, session.title, session.running,
        this.pinned.includes(session.id), this.archivedIds.includes(session.id)]));
    return JSON.stringify([group.id, title, ...rows]);
  }

  private markSidebarVisible(ready: boolean): void {
    if (ready && !this.measured) {
      this.measured = true;
      hilog.warn(DOMAIN, TAG, 'DSHM-TRACE ArkUI 工作区和会话列表可见');
    }
  }

  private async openWeb(leaveExperiment: boolean, action: string = ''): Promise<void> {
    if (this.switching) {
      return;
    }
    this.switching = true;
    const ui = this.getUIContext();
    try {
      if (leaveExperiment) {
        const context = ui.getHostContext();
        if (context === undefined) {
          throw new Error('工作台设置不可用');
        }
        await setDesktopWorkspaceEnabled(context, false);
      }
      this.webAction = leaveExperiment ? '' : action;
      this.webSessionId = leaveExperiment || (action.length > 0 && action !== 'new-session') ? '' : this.sessionId;
      this.webWorkspaceId = this.webSessionId.length > 0 ? this.workspaceId : '';
      hilog.warn(DOMAIN, TAG, 'DSHM-TRACE 从 ArkUI 打开 WebUI');
      await ui.getRouter().replaceUrl({ url: WEB_WORKSPACE_PAGE });
    } catch (_) {
      this.webAction = '';
      this.webSessionId = '';
      this.webWorkspaceId = '';
      this.switching = false;
      ui.getPromptAction().showToast({ message: $r('app.string.desktop_experiment_switch_failed') });
    }
  }

  private accessibilityLabel(label: ResourceStr): string {
    return typeof label === 'string' ? label :
      this.getUIContext().getHostContext()?.resourceManager.getStringSync(label) ?? '';
  }

  @Builder
  private IconButton(icon: Resource, label: ResourceStr, action: () => void) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(icon).fontSize(16).fontColor([$r('sys.color.font_secondary')])
    }
    .width(32).height(32).borderRadius(7).backgroundColor(Color.Transparent)
    .focusOnTouch(false).accessibilityText(this.accessibilityLabel(label)).onClick(action)
  }

  @Builder
  private ShortcutLabel(icon: Resource, label: ResourceStr) {
    Row({ space: 8 }) {
      SymbolGlyph(icon).fontSize(16).fontColor([$r('sys.color.font_primary')])
      if (!this.sidebarCollapsed) {
        Text(label).fontSize(14).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
  }

  @Builder
  private SidebarShortcut(icon: Resource, label: ResourceStr, action: () => void, accent: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      this.ShortcutLabel(icon, label)
    }
    .width('100%').height(accent ? 38 : 34).borderRadius(accent ? 9 : 7)
    .padding({ left: this.sidebarCollapsed ? 0 : 8, right: this.sidebarCollapsed ? 0 : 8 })
    .align(accent || this.sidebarCollapsed ? Alignment.Center : Alignment.Start)
    .backgroundColor(accent ? $r('app.color.workspace_action') : Color.Transparent)
    .focusOnTouch(false).accessibilityText(this.accessibilityLabel(label)).enabled(!this.switching).onClick(action)
  }

  @Builder
  private SidebarMenu(footer: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        this.MenuDots()
        if (!this.sidebarCollapsed) {
          Text($r('app.string.desktop_experiment_more')).fontSize(14).fontColor($r('sys.color.font_primary'))
        }
      }
    }
    .width('100%').height(34).borderRadius(7).backgroundColor(Color.Transparent)
    .padding({ left: this.sidebarCollapsed ? 0 : 8, right: this.sidebarCollapsed ? 0 : 8 })
    .align(this.sidebarCollapsed ? Alignment.Center : Alignment.Start)
    .focusOnTouch(false)
    .accessibilityText(footer ? $r('app.string.desktop_experiment_footer_menu') :
      $r('app.string.desktop_experiment_more'))
    .bindMenu(this.sidebarActions(footer), desktopMenuOptions(footer ? Placement.TopLeft : Placement.BottomLeft))
  }

  @Builder
  private MenuDots() {
    Row({ space: 2.5 }) {
      Circle().width(2.5).height(2.5).fill($r('sys.color.font_primary'))
      Circle().width(2.5).height(2.5).fill($r('sys.color.font_primary'))
      Circle().width(2.5).height(2.5).fill($r('sys.color.font_primary'))
    }
    .width(16).justifyContent(FlexAlign.Center)
  }

  @Builder
  private TopBar() {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.MenuDots()
      }
      .width(28).height(24).borderRadius(5).backgroundColor(Color.Transparent).focusOnTouch(false)
      .accessibilityText($r('app.string.desktop_experiment_title'))
      .bindMenu(this.sidebarActions(true), desktopMenuOptions(Placement.BottomLeft))
      Blank()
    }
    .width('100%').height(38).padding({ left: 10, right: 132 })
  }

  @Builder
  private WorkspaceRow(group: DesktopWorkspaceGroup) {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(16)
            .fontColor([this.isExpanded(group.id) ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
          Text(group.title).fontSize(14).fontColor($r('sys.color.font_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor([$r('sys.color.font_tertiary')])
            .rotate({ angle: this.isExpanded(group.id) ? 90 : 0 })
        }
        .width('100%')
      }
      .layoutWeight(1).height(34).padding({ left: 8, right: 4 }).borderRadius(8)
      .backgroundColor(Color.Transparent).focusOnTouch(false).accessibilityText(this.accessibilityLabel(group.title))
      .onClick((): void => this.toggleWorkspace(group.id))
      if (group.id.length > 0) {
        this.RowMenu('管理工作区 ' + this.accessibilityLabel(group.title), this.workspaceActions(group))
      }
    }
    .width('100%')
  }

  @Builder
  private SessionRow(group: DesktopWorkspaceGroup, session: SessionListItem, archived: boolean) {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Stack() {
            if (session.running && !archived) {
              LoadingProgress().width(13).height(13).color($r('sys.color.brand'))
            } else if (!archived && !session.blank && this.unreadSession(session.id) !== undefined) {
              Circle().width(7).height(7).fill(this.unreadSession(session.id)?.failed === true ?
                $r('sys.color.warning') : $r('sys.color.brand')).key('desktopSessionUnread-' + session.id)
                .accessibilityText(this.unreadSession(session.id)?.failed === true ? '失败' : '未读')
            }
          }.width(14)
          Text(this.sessionLabel(session)).fontSize(14).fontColor(archived ?
            $r('sys.color.font_tertiary') : $r('sys.color.font_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!archived && this.pinned.includes(session.id)) {
            Image($r('app.media.dsh_session_pin_fill')).width(14).height(14).supportSvg2(true)
              .draggable(false).accessibilityText('已置顶')
          }
        }
        .width('100%')
      }
      .layoutWeight(1).height(32).padding({ left: 10, right: 4 }).borderRadius(8)
      .backgroundColor(Color.Transparent).focusOnTouch(false)
      .accessibilityText(this.accessibilityLabel(this.sessionLabel(session)))
      .accessibilityDescription(archived ? '已归档' : '')
      .accessibilitySelected(this.sessionId === session.id)
      .onClick((): void => {
        if (archived) { this.openSessionById(session.id); return; }
        this.selectSession(group, session);
        this.panel = 'session';
      })
      if (archived) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_session_unarchive_outline')).width(14).height(14).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
        }.key('desktopRestoreSession-' + session.id).width(30).height(30).padding(0).borderRadius(7)
          .enabled(!this.workspaceBusy).focusOnTouch(false).accessibilityText('取消归档')
          .onClick((): void => { this.restoreSession(session.id); })
      }
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.MenuDots()
      }
      .width(32).height(32).borderRadius(7).backgroundColor(Color.Transparent)
      .focusOnTouch(false).accessibilityText('管理会话 ' + this.accessibilityLabel(this.sessionLabel(session)))
      .enabled(!this.workspaceBusy).bindMenu(this.sessionActions(session), desktopMenuOptions(Placement.BottomRight))
    }
    .width('100%').borderRadius(8)
    .backgroundColor(this.sessionId === session.id ? $r('app.color.workspace_selection') : Color.Transparent)
  }

  @Builder
  private RowMenu(label: string, actions: MenuElement[]) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      this.MenuDots()
    }
    .width(32).height(32).borderRadius(7).backgroundColor(Color.Transparent)
    .focusOnTouch(false).accessibilityText(label).enabled(!this.workspaceBusy)
    .bindMenu(actions, desktopMenuOptions(Placement.BottomRight))
  }

  @Builder
  private RenameDialog() {
    Column({ space: 12 }) {
      Text(this.renameWorkspace ? '重命名工作区' : '重命名会话').fontSize(20).fontWeight(FontWeight.Medium)
      TextInput({ text: this.renameDraft, placeholder: '名称' }).key('desktopWorkspaceRenameInput').defaultFocus(true)
        .onChange((value: string): void => { this.renameDraft = value; })
        .onSubmit((): void => { this.rename(); })
      Row({ space: 8 }) {
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.workspaceBusy)
          .onClick((): void => { this.closeRename(); })
        Button('保存').enabled(!this.workspaceBusy && this.renameDraft.trim().length > 0)
          .onClick((): void => { this.rename(); })
      }
    }
    .width('100%').padding(22)
  }

  @Builder
  private WorkspaceTree() {
    Row() {
      Text($r('app.string.desktop_experiment_workspaces'))
        .fontSize(14).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_session_sliders_two_outline')).width(16).height(16)
          .supportSvg2(true).accessibilityLevel('no')
      }.key('desktopWorkspaceArchiveFilter').width(32).height(32).padding(0).borderRadius(7)
        .focusOnTouch(false).accessibilityText('视图选项').enabled(this.ready)
        .bindMenu(this.archiveFilterActions(), desktopMenuOptions(Placement.BottomRight))
      this.IconButton($r('sys.symbol.magnifyingglass'), $r('app.string.desktop_experiment_search'),
        (): void => {
          this.searchOpen = !this.searchOpen;
          if (!this.searchOpen) {
            this.filterGroups('');
          }
        })
      this.IconButton($r('sys.symbol.plus'), $r('app.string.desktop_experiment_add_workspace'),
        (): void => { this.addWorkspace(); })
    }
    .width('100%').padding({ left: 8 }).margin({ top: 14 })
    if (this.searchOpen) {
      TextInput({ text: this.query, placeholder: $r('app.string.desktop_experiment_search') })
        .key('desktopWorkspaceSearch')
        .height(32).borderRadius(8).fontSize(14).backgroundColor($r('app.color.workspace_selection'))
        .onChange((value: string): void => this.filterGroups(value))
    }
    if (this.ready) {
      List({ space: 2 }) {
        ForEach(this.visibleGroups, (group: DesktopWorkspaceGroup) => {
          ListItem() {
            this.WorkspaceRow(group)
          }
          if (this.isExpanded(group.id)) {
            ForEach(group.sessions, (session: SessionListItem): void => {
              ListItem() {
                this.SessionRow(group, session, this.archivedIds.includes(session.id))
              }
            }, (session: SessionListItem): string => session.id)
          }
        }, (group: DesktopWorkspaceGroup): string => this.groupKey(group))
        if (this.visibleGroups.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([$r('sys.color.font_tertiary')])
              if (!this.query && this.archiveFilter === DesktopArchiveFilter.ONLY) {
                Text('暂无已归档会话').fontSize(14).fontColor($r('sys.color.font_secondary'))
                Button('查看其他会话', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .onClick((): void => { this.setArchiveFilter(DesktopArchiveFilter.HIDE); })
              } else {
                Text(this.query.length > 0 ? $r('app.string.desktop_experiment_search_empty') :
                  $r('app.string.desktop_experiment_empty')).fontSize(14).fontColor($r('sys.color.font_secondary'))
              }
            }
            .width('100%').padding({ top: 36, bottom: 24 })
          }
        }
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      .onVisibleAreaChange([0], (visible: boolean): void => this.markSidebarVisible(visible))
    } else {
      Text(this.error || this.hostError || $r('app.string.desktop_experiment_loading'))
        .width('100%').padding({ left: 8, right: 8, top: 12 })
        .fontSize(13).fontColor($r('sys.color.font_secondary'))
      if (this.error.length > 0 && this.hostUrl.length > 0) {
        this.SidebarShortcut($r('sys.symbol.arrow_clockwise'), $r('app.string.desktop_experiment_retry'),
          (): void => this.onHostChanged(), false)
      }
      Blank()
    }
  }

  @Builder
  private Sidebar() {
    Column({ space: 2 }) {
      Row({ space: 9 }) {
        if (!this.sidebarCollapsed) {
          Image($r('app.media.logo_dark')).width(24).height(24).objectFit(ImageFit.Contain)
          Text($r('app.string.app_name')).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        }
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.sidebar_toggle')).width(16).height(16).fillColor($r('sys.color.font_secondary'))
        }
        .width(32).height(32).borderRadius(7).backgroundColor(Color.Transparent).focusOnTouch(false)
        .accessibilityText(this.sidebarCollapsed ? $r('app.string.desktop_experiment_expand_sidebar') :
          $r('app.string.desktop_experiment_collapse_sidebar'))
        .onClick((): void => { this.sidebarCollapsed = !this.sidebarCollapsed; })
      }
      .width('100%').height(64).padding({ left: this.sidebarCollapsed ? 0 : 6 })
      .justifyContent(this.sidebarCollapsed ? FlexAlign.Center : FlexAlign.Start)
      this.SidebarShortcut($r('sys.symbol.plus_circle'), $r('app.string.action_new_session'),
        (): void => { this.newSession(); }, true)
      Blank().height(12)
      this.SidebarShortcut($r('sys.symbol.square_grid_2x2'), $r('app.string.desktop_experiment_plugins'),
        (): void => { this.panel = 'plugins'; }, false)
      this.SidebarShortcut($r('sys.symbol.clock'), $r('app.string.desktop_experiment_schedule'),
        (): void => { this.panel = 'schedule'; }, false)
      this.SidebarShortcut($r('sys.symbol.gearshape'), $r('app.string.desktop_workspace_settings'),
        (): void => { this.openSettings(); }, false)
      this.SidebarMenu(false)
      if (!this.sidebarCollapsed) {
        this.WorkspaceTree()
      } else {
        Blank()
      }
      this.SidebarMenu(true)
    }
    .width(this.sidebarCollapsed ? 52 : this.sidebarWidth)
    .height('100%')
    .padding({ left: this.sidebarCollapsed ? 8 : 10, right: this.sidebarCollapsed ? 8 : 10, bottom: 8 })
    .backgroundColor($r('app.color.workspace_sidebar'))
    .border({ width: { right: 1 }, color: $r('app.color.workspace_border') })
  }

  @Builder
  private SessionContent() {
    Row() {
      if (this.sessionId.length > 0) {
        DesktopConversationPane({
          host: this.data?.actions,
          snapshot: this.chat,
          interactions: this.interactions,
          onDecision: (id: string, allow: boolean): void => {
            const interactions = this.data?.interactions;
            if (interactions !== undefined) {
              this.chatAction((): Promise<string> => interactions.approve(id, allow));
            }
          },
          onAnswer: (id: string, answers: DesktopQuestionAnswer[]): void => {
            const interactions = this.data?.interactions;
            if (interactions !== undefined) {
              this.chatAction((): Promise<string> => interactions.answer(id, answers));
            }
          },
          onPlanDecision: (id: string, approve: boolean): void => {
            const interactions = this.data?.interactions;
            if (interactions !== undefined) {
              this.chatAction((): Promise<string> => approve ?
                interactions.approvePlanReview(id) : interactions.dismissPlanReview(id));
            }
          },
          onPlanMode: (enabled: boolean): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined) {
              this.chatAction((id: string): Promise<string> => conversation.togglePlanMode(id, enabled));
            }
          },
          onGoalAction: (action: DesktopGoalAction, ref: DesktopGoalRef, objective: string): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.mutateGoal(id, action, ref, objective));
          },
          onPlanPreview: (plan: DesktopPlanDocument): void => { this.showPlan(plan); },
          onPlanResume: (id: string): void => { this.data?.interactions.reopenPlanReview(id); },
          onArtifactFile: (path: string, name: string): void => { this.showArtifact(path, name); },
          onReferenceFileAction: (action: DesktopReferenceAction, path: string, name: string): void => {
            this.referenceFileAction(action, path, name);
          },
          onArtifactAction: (path: string, name: string, reveal: boolean): void => { this.openArtifactAction(path, name, reveal); },
          onChanges: (target: DesktopChangeTarget): void => { this.showChanges(target); },
          title: this.selectedTitle,
          workspaceTitle: this.selectedWorkspaceTitle,
          sessionDirectory: this.selectedSessionDirectory,
          draft: this.draft,
          appearance: this.appearance,
          referenceOffer: this.referenceOffer,
          attachments: this.attachments,
          onAddAttachment: (): void => this.attachDocument(),
          onDropAttachments: (files: DesktopDroppedFiles): void => { this.attachDroppedFiles(files); },
          onPasteAttachments: (): void => { this.attachClipboard(); },
          onOpenImage: (row: DesktopMediaAttachment): void => { this.openImagePreview(row); },
          onRemoveAttachment: (receiptId: string): void => {
            this.setAttachments(this.sessionId, this.attachments.filter((file: DesktopDraftAttachment): boolean =>
              file.receiptId !== receiptId));
          },
          busy: this.busySessions.includes(this.sessionId),
          commandError: this.chatError,
          menuOptions: desktopMenuOptions(Placement.TopLeft),
          onDraft: (session: string, value: DesktopComposerDraft): void => this.changeDraft(session, value),
          onSend: (alternateDelivery: boolean): void => this.sendMessage(alternateDelivery),
          onQueueAction: (session: string, id: string, action: QueueActionBody): Promise<string> =>
            this.data?.conversation.updateQueue(session, id, action) ?? Promise.resolve('当前会话暂不可操作'),
          onSteerQueue: (): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined) { this.chatAction((id: string): Promise<string> => conversation.steerQueue(id)); }
          },
          onLoadModels: (): void => { this.data?.conversation.loadModels(true); },
          onModelsSettings: (): void => { this.openSettings('settings.models'); },
          onLoadCommands: (): void => { this.data?.conversation.loadCommands(this.sessionId); },
          onCommand: (name: string): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.runCommandChoice(id, name,
                (sessionId: string): Promise<string> => this.exportLog(sessionId)));
          },
          onSlashModel: (selection: ModelSelection): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.selectModel(id, selection));
          },
          onSlashPermission: (preset: string): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.selectPermission(id, preset));
          },
          onStop: (): void => this.stopMessage(),
          onEarlier: (): void => this.data?.conversation.loadEarlier(),
          onWeb: (): void => { this.openWeb(false); },
          copyingTranscript: this.copyingTranscript,
          exportingLog: this.exportingLog,
          choosingFeedback: this.choosingFeedback,
          forking: this.forking,
          onFork: (id: string, atSeq: number): void => { this.forkFrom(id, atSeq); },
          onSessionFeedback: (sessionId: string): Promise<string> => this.openSessionFeedback(sessionId),
          onWarmFeedback: (sessionId: string): void => { this.data?.conversation.feedback.ensure(sessionId); },
          onReplyRating: (sessionId: string, messageId: string, rating: DesktopRating): void => {
            this.chooseReplyRating(sessionId, messageId, rating);
          },
          onCopyTranscript: (): void => { this.copyTranscript(); },
          onExportLog: (): void => {
            this.chatAction((id: string): Promise<string> => this.exportLog(id));
          },
          filesOpen: this.dockShows(DesktopDockKind.FILES),
          rightDockOpen: this.rightDock.expanded,
          onRightDock: (): void => this.toggleRightDock(),
          onFiles: (): void => this.showWorkspaceFiles(true),
          terminalOpen: this.dockShows(DesktopDockKind.TERMINAL),
          onTerminal: (): void => this.showTerminal(false, true),
          onModel: (selection: ModelSelection): void => this.chooseModel(selection),
          onPermission: (preset: string): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined) {
              this.chatAction((id: string): Promise<string> => conversation.selectPermission(id, preset));
            }
          }
        })
        .layoutWeight(1).visibility(this.dockFullscreen() ? Visibility.None : Visibility.Visible)
        if (this.data !== undefined && (this.rightDock.expanded || this.rightDock.panes[0].tabs.length > 0 ||
          this.rightDock.panes.length > 1)) {
          Column() { this.RightDock() }
            .width(this.dockFullscreen() ? '100%' : this.dockWidth()).height('100%')
            .visibility(this.rightDock.expanded ? Visibility.Visible : Visibility.None)
        }
      } else {
        this.SessionPane()
      }
    }
    .height('100%').layoutWeight(1)
  }

  private dockMenu(index: number): MenuElement[] {
    const items: MenuElement[] = [
      { value: '工作区文件', action: (): void => this.openDockTool(index, DesktopDockKind.FILES) },
      { value: '新建终端', action: (): void => this.openDockTool(index, DesktopDockKind.TERMINAL) }
    ];
    if (this.canSplitDock()) {
      items.push({ value: '向右分屏', action: (): void => { this.splitDock(); } });
    } else if (this.rightDock.panes.length === 2) {
      items.push({ value: '合并分屏', action: (): void => { this.setDock(desktopDockMerge(this.rightDock, index)); } });
    }
    return items;
  }

  private openDockTool(index: number, kind: DesktopDockKind): void {
    if (!this.rightDock.panes[index]) { return; }
    const owner = this.rightDock.panes.findIndex((pane: DesktopDockPane): boolean =>
      pane.tabs.some((tab: DesktopDockTab): boolean => tab.kind === kind));
    if (owner >= 0 && owner !== index) {
      this.setDock(desktopDockMoveTab(this.rightDock, owner, kind));
    }
    this.focusDockPane(index);
    if (kind === DesktopDockKind.FILES) { this.showWorkspaceFiles(); }
    else if (kind === DesktopDockKind.TERMINAL) { this.showTerminal(true); }
  }

  private dockTabMenu(index: number, tab: DesktopDockTab): MenuElement[] {
    const items: MenuElement[] = [];
    if (this.rightDock.panes.length === 2) {
      items.push({ value: '移到另一侧', action: (): void => {
        this.setDock(desktopDockMoveTab(this.rightDock, index, tab.id));
      } });
    } else if (this.canSplitDock()) {
      items.push({ value: '向右分屏', action: (): void => {
        const next = desktopDockMoveTab(desktopDockSplit(this.rightDock), index, tab.id);
        this.setDock(next);
      } });
    }
    items.push({ value: '关闭标签', action: (): void => this.closeDockTab(index, tab.id) });
    return items;
  }

  private dockStoredTab(index: number, id: string): DesktopDockTab | undefined {
    return this.rightDock.panes[index]?.tabs.find((tab: DesktopDockTab): boolean => tab.id === id);
  }

  @Builder
  private DockBody(index: number, tab: DesktopDockTab) {
    if (tab.kind === DesktopDockKind.FILES || tab.kind === DesktopDockKind.PREVIEW) {
      DesktopFilesPane({ host: this.data?.actions,
        ability: this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext'),
        sessionId: this.sessionId, requested: tab.file, previewOnly: tab.kind === DesktopDockKind.PREVIEW,
        onHide: (): void => this.closeDockTab(index, tab.id),
        onOpenFile: (path: string, name: string): void => { this.focusDockPane(index); this.showArtifact(path, name); },
        onAttachWorkspaceFile: (path: string, name: string): void => { this.attachWorkspaceFile(path, name); },
        onReferenceWorkspaceFile: (path: string, name: string): void => {
          this.referenceFileAction(DesktopReferenceAction.ADD_TO_CHAT, path, name);
        } })
    } else if (tab.kind === DesktopDockKind.TERMINAL) {
      DesktopTerminalPane({ host: this.data?.actions, sessionId: this.sessionId, appearance: this.appearance,
        createSession: this.terminalCreateSession, onCreateShortcut: (): void => { this.terminalCreateSession = ''; },
        onShortcut: (event: KeyEvent): boolean => {
          if (event.type === KeyType.Down) { this.focusDockPane(index); }
          return this.terminalShortcut(event);
        }, onHidePanel: (): void => this.toggleRightDock() })
    } else if (tab.kind === DesktopDockKind.PLAN) {
      DesktopPlanPreviewPane({ markdown: this.dockStoredTab(index, tab.id)?.plan?.markdown ?? '',
        onClosePreview: (): void => this.closeDockTab(index, tab.id) })
    } else {
      DesktopChangesPane({ host: this.data?.actions, target: this.dockStoredTab(index, tab.id)?.changes,
        onClose: (): void => this.closeDockTab(index, tab.id),
        onFile: (path: string, name: string, target: DesktopChangeTarget): void => {
          this.showChanges(target);
          this.focusDockPane(index);
          this.showArtifact(path, name);
        } })
    }
  }

  @Builder
  private DockTab(index: number, tab: DesktopDockTab) {
    Row({ space: 2 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Text(tab.title).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
      }.key('desktopDockTab-' + index + '-' + tab.id).height(28).padding({ left: 7, right: 2 })
        .constraintSize({ maxWidth: 126 }).accessibilitySelected(this.rightDock.panes[index]?.active === tab.id)
        .onClick((): void => { this.setDock(desktopDockSelect(this.rightDock, index, tab.id)); })
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_dock_close')).width(11).height(11).accessibilityLevel('no')
      }.key('desktopDockClose-' + index + '-' + tab.id).width(21).height(24).padding(0)
        .accessibilityText('关闭标签 ' + tab.title).onClick((): void => this.closeDockTab(index, tab.id))
      if (this.rightDock.panes[index]?.active === tab.id) {
        Button('···', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(22).height(24).padding(0)
          .key('desktopDockTabMenu-' + index + '-' + tab.id).accessibilityText('标签操作 ' + tab.title)
          .bindMenu(this.dockTabMenu(index, tab), desktopMenuOptions(Placement.BottomLeft))
      }
    }.height(30).borderRadius(7)
      .backgroundColor(this.rightDock.panes[index]?.active === tab.id ? $r('app.color.workspace_selection') : Color.Transparent)
  }

  @Builder
  private DockGuide(index: number) {
    Column({ space: 8 }) {
      Button('工作区文件', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopDockGuideFiles-' + index)
        .onClick((): void => this.openDockTool(index, DesktopDockKind.FILES))
      Button('新建终端', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopDockGuideTerminal-' + index)
        .onClick((): void => this.openDockTool(index, DesktopDockKind.TERMINAL))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  private DockPane(index: number) {
    Column() {
      Row({ space: 4 }) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.rightDock.panes[index]?.tabs ?? [], (tab: DesktopDockTab): void => {
              this.DockTab(index, tab)
            }, (tab: DesktopDockTab): string => tab.id + ':' + tab.title)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
        Button('＋', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopDockAdd-' + index)
          .height(30).width(28).padding(0).accessibilityText('新建标签页')
          .bindMenu(this.dockMenu(index), desktopMenuOptions(Placement.BottomRight))
        if (index === this.rightDock.panes.length - 1) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image(this.dockFullscreen() ? $r('app.media.dsh_right_restore') : $r('app.media.dsh_right_fullscreen'))
              .width(16).height(16).fillColor($r('sys.color.font_primary')).accessibilityLevel('no')
          }.key('desktopDockFullscreen').width(28).height(30).padding(0)
            .accessibilityText(this.dockFullscreen() ? '退出全屏' : '全屏').enabled(!this.dockAutoFullscreen())
            .onClick((): void => this.toggleDockFullscreen())
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.sidebar_toggle')).width(16).height(16).rotate({ angle: 180 })
              .fillColor($r('sys.color.font_primary')).accessibilityLevel('no')
          }.key('desktopDockCollapse').width(28).height(30).padding(0).accessibilityText('收起右侧栏')
            .onClick((): void => this.toggleRightDock())
        }
      }.width('100%').height(39).padding({ left: 5, right: 5 })
        .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      Stack() {
        if (!this.rightDock.panes[index]?.tabs.length) {
          this.DockGuide(index)
        } else {
          ForEach(this.rightDock.panes[index]?.tabs ?? [], (tab: DesktopDockTab): void => {
            Column() { this.DockBody(index, tab) }
              .width('100%').height('100%')
              .visibility(this.rightDock.panes[index]?.active === tab.id ? Visibility.Visible : Visibility.None)
          }, (tab: DesktopDockTab): string => this.sessionId + ':' + tab.id)
        }
      }.width('100%').layoutWeight(1)
    }.key('desktopDockPane-' + index).layoutWeight(1).height('100%')
      .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) { this.focusDockPane(index); } })
  }

  @Builder
  private RightDock() {
    Row() {
      this.DockPane(0)
      if (this.rightDock.panes.length === 2) {
        Divider().vertical(true).color($r('app.color.workspace_border')).height('100%')
        this.DockPane(1)
      }
    }.key('desktopRightDock').width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
      .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }

  @Builder
  private SessionPane() {
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        Image($r('app.media.logo_dark')).width(32).height(28).objectFit(ImageFit.Contain)
        Text(this.selectedTitle || $r('app.string.desktop_experiment_welcome'))
          .fontSize(26).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '83%' })
      }
      .justifyContent(FlexAlign.Center)
      Column({ space: 8 }) {
        Row() {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([$r('sys.color.font_secondary')])
              Text(this.selectedWorkspaceTitle || $r('app.string.desktop_experiment_choose_workspace'))
                .fontSize(14).fontColor($r('sys.color.font_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11)
                .fontColor([$r('sys.color.font_secondary')]).rotate({ angle: 90 })
            }
          }
          .constraintSize({ maxWidth: '80%' }).height(30).padding({ left: 8, right: 8 })
          .borderRadius(7).backgroundColor(Color.Transparent).focusOnTouch(false)
          .enabled(this.ready && this.groups.length > 0)
          .bindMenu(this.workspaceMenu(), desktopMenuOptions(Placement.BottomLeft))
        }
        .width('100%').padding({ left: 4 })
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 12 }) {
            Text($r('app.string.action_new_session'))
              .fontSize(15).fontColor($r('sys.color.font_primary')).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.plus')).fontSize(17).fontColor([$r('sys.color.font_primary')])
          }
          .width('100%')
        }
        .width('100%').constraintSize({ minHeight: 76 }).padding({ left: 16, right: 16 }).borderRadius(21)
        .backgroundColor($r('app.color.workspace_panel')).focusOnTouch(false).enabled(this.ready && !this.creating)
        .onClick((): void => { this.newSession(); })
      }
      .width('100%').constraintSize({ maxWidth: 712 })
      if (this.chatError.length > 0) {
        Text(this.chatError).fontSize(13).fontColor($r('sys.color.warning'))
      }
    }
    .width('100%').height('100%').padding({ left: 26, right: 26 }).justifyContent(FlexAlign.Center)
  }

  build() {
    WithTheme({
      colorMode: this.appearance === 'dark' ? ThemeColorMode.DARK :
        this.appearance === 'light' ? ThemeColorMode.LIGHT : ThemeColorMode.SYSTEM
    }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          this.TopBar()
          Row() {
            if (this.panel !== 'session' || !this.dockFullscreen()) { this.Sidebar() }
            if (this.panel === 'plugins' && this.ready && this.data !== undefined) {
              DesktopPluginsPane({
                host: this.data.actions,
                onWeb: (): void => { this.openWeb(false, 'plugins'); }
              })
            } else if (this.panel === 'schedule' && this.ready && this.data !== undefined) {
              DesktopSchedulePane({
                host: this.data.actions,
                sessionId: this.sessionId,
                workspacePath: this.data.workspacePath(this.workspaceId),
                onOpenSession: (id: string): void => { this.openSessionById(id); },
                onWeb: (): void => { this.openWeb(false, 'schedule'); }
              })
            } else if (this.panel !== 'session') {
              Column() {
                Text(this.error || this.hostError || $r('app.string.desktop_experiment_loading'))
                  .fontColor($r('sys.color.font_secondary'))
              }
              .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
            } else {
              this.SessionContent()
            }
          }
          .width('100%').layoutWeight(1)
        }
        .width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
        if (this.pageVisible && !this.shortcutsOpen) {
          Row() {
            ForEach(this.shortcutBindings, (row: DesktopShortcutRow): void => {
              if (!row.occupiedBy && row.binding.code !== 0) {
                Button().width(0).height(0).focusable(false).accessibilityLevel('no')
                  .keyboardShortcut(desktopShortcutValue(row.binding), desktopShortcutModifiers(row.binding),
                    (): void => { this.workspaceShortcut(row.id); })
              }
            }, (row: DesktopShortcutRow): string => row.id + row.occupiedBy + JSON.stringify(row.binding))
          }.width(0).height(0).visibility(Visibility.Hidden).accessibilityLevel('no')
        }
        DesktopShortcutDialog({ show: this.shortcutsOpen, panelWidth: Math.max(250, Math.min(480, this.workbenchWidth - 32)),
          onClose: (): void => { this.shortcutsOpen = false; }, onChanged: (): void => this.reloadShortcutBindings() })
        if (this.archiveNotice !== undefined) {
          this.ArchiveNoticeContent(this.archiveNotice)
        }
      }
      .width('100%').height('100%')
      .onAreaChange((_, area: Area): void => {
        this.workbenchWidth = Number(area.width);
        this.workbenchHeight = Number(area.height);
        this.sidebarWidth = Math.max(160, Math.min(280, Number(area.width) * 0.48));
        this.rightPaneWidth = Math.max(220, Math.min(520, (Number(area.width) - this.sidebarWidth) * 0.46));
      })
    }
  }
}
