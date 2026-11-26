import { common } from '@kit.AbilityKit';
import { getString, parseTarget } from 'connection';
import type { DesktopInteraction, DesktopQuestionAnswer } from '../desktop/DesktopInteractions';
import { DesktopTerminalPane } from '../desktop/DesktopTerminalPane';
import { DesktopFilesPane } from '../desktop/DesktopFilesPane';
import { desktopHostProblem } from '../desktop/DesktopHostActions';
import { DesktopAccountPane } from '../desktop/DesktopAccountPane';
import { dialogMaterial, PickOutcome, pickDocument, pickFolder, readDocumentUri, uriFromPath } from 'platform';
import { harmonySheetOptions } from '../view/NativePrimitives';
import { desktopMenuOptions } from '../desktop/DesktopMenuOptions';
import { DesktopPluginsPane } from '../desktop/DesktopPluginsPane';
import { DesktopSchedulePane } from '../desktop/DesktopSchedulePane';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { ModelSelection, PendingAttachment, SessionListItem } from 'appstate';
import { DesktopConversationPane } from '../desktop/DesktopConversationPane';
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
  @State private terminalSession: string = '';
  @State private filesSession: string = '';
  @State private searchOpen: boolean = false;
  @State private query: string = '';
  @State private selectedWorkspaceTitle: ResourceStr = '';
  @State private appearance: string = 'system';
  @State private selectedTitle: ResourceStr = '';
  @State private ready: boolean = false;
  @State private error: string = '';
  @State private switching: boolean = false;
  @State private panel: string = 'session';
  @State private workspaceBusy: boolean = false;
  @State private archived: SessionListItem[] = [];
  @State private pinned: string[] = [];
  @State private archiveOpen: boolean = false;
  @State private renameOpen: boolean = false;
  @State private renameDraft: string = '';
  private renameId: string = '';
  private renameWorkspace: boolean = false;
  @State private chat: DesktopConversationSnapshot | undefined = undefined;
  @State private interactions: DesktopInteraction[] = [];
  @State private draft: string = '';
  @State private chatError: string = '';
  @State private attachments: PendingAttachment[] = [];
  private readonly attachmentsBySession: Map<string, PendingAttachment[]> = new Map<string, PendingAttachment[]>();
  @State private creating: boolean = false;
  @State private busySessions: string[] = [];
  private readonly drafts: Map<string, string> = new Map<string, string>();

  @State private groups: DesktopWorkspaceGroup[] = [];
  private data?: DesktopWorkspaceData;
  private workbenchWidth: number = 440;
  private accountOpening: boolean = false;
  private accountDialog: number = -1;
  private pageActive: boolean = false;
  private measured: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.pageActive = true;
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.appearance = desktopWorkspaceAppearance(context);
    }
    this.onHostChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.pageActive = false;
    this.closeAccount();
    this.data?.stop();
    this.data = undefined;
  }

  onBackPress(): boolean {
    if (this.filesSession.length > 0 && this.filesSession === this.sessionId && this.panel === 'session') {
      this.filesSession = '';
      return true;
    }
    if (this.terminalSession.length > 0 && this.terminalSession === this.sessionId && this.panel === 'session') {
      this.terminalSession = '';
      return true;
    }
    if (this.archiveOpen) {
      this.archiveOpen = false;
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
      this.archived = snapshot.archived;
      this.pinned = snapshot.pinned;
      this.updateGroups(snapshot.workspaces, snapshot.sessions);
      this.ready = true;
    }, (snapshot: DesktopConversationSnapshot): void => {
      this.chat = snapshot;
    }, (items: DesktopInteraction[]): void => {
      this.interactions = items;
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
      if (session.id === this.sessionId) {
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
    if (!sessions.some((session: SessionListItem): boolean => session.id === this.sessionId)) {
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
  }

  private pinRank(id: string): number {
    const index = this.pinned.indexOf(id);
    return index < 0 ? this.pinned.length : index;
  }

  private showRename(id: string, workspace: boolean, title: ResourceStr): void {
    this.renameId = id;
    this.renameWorkspace = workspace;
    this.renameDraft = this.accessibilityLabel(title);
    this.renameOpen = true;
  }

  private async rename(): Promise<void> {
    const title = this.renameDraft.trim();
    if (!title || this.workspaceBusy) {
      return;
    }
    const id = this.renameId;
    const workspace = this.renameWorkspace;
    if (await this.manage(workspace ? 'workspace/rename' : 'session/rename', workspace ?
      { 'workspaceId': id, 'title': title } : { 'sessionId': id, 'title': title })) {
      this.renameOpen = false;
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
    const pinned = this.pinned.includes(session.id);
    return [
      { value: '重命名会话', action: (): void => { this.showRename(session.id, false, this.sessionLabel(session)); } },
      { value: pinned ? '取消置顶' : '置顶会话', action: (): void => {
        this.manage(pinned ? 'workspace/unpinSession' : 'workspace/pinSession', { 'sessionId': session.id });
      } },
      { value: '归档会话', action: (): void => {
        this.manage('workspace/archiveSession', { 'sessionId': session.id });
      } }
    ];
  }

  private filterGroups(value: string): void {
    this.query = value;
    const needle = value.trim().toLowerCase();
    if (needle.length === 0) {
      this.visibleGroups = this.groups;
      return;
    }
    const matches: DesktopWorkspaceGroup[] = [];
    this.groups.forEach((group: DesktopWorkspaceGroup): void => {
      const sessions = group.sessions.filter((row: SessionListItem): boolean => row.title.toLowerCase().includes(needle));
      if (sessions.length > 0) {
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
      this.draft = this.drafts.get(session.id) ?? '';
      this.attachments = this.attachmentsBySession.get(session.id) ?? [];
      this.chatError = '';
    }
    this.sessionId = session.id;
    this.workspaceId = group.id;
    this.selectedTitle = this.sessionLabel(session);
    this.selectedWorkspaceTitle = group.title;
    this.data?.conversation.open(session.id);
  }

  private changeDraft(value: string): void {
    if (this.sessionId.length > 0) {
      this.draft = value;
      if (value.length > 0) {
        this.drafts.set(this.sessionId, value);
      } else {
        this.drafts.delete(this.sessionId);
      }
    }
  }

  private clearSession(): void {
    this.sessionId = '';
    this.selectedTitle = '';
    this.draft = '';
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

  private async chatAction(run: (id: string) => Promise<string>, sentDraft?: string): Promise<void> {
    const id = this.sessionId;
    const data = this.data;
    if (id.length === 0 || data === undefined || this.busySessions.includes(id)) {
      return;
    }
    this.busySessions = [...this.busySessions, id];
    this.chatError = '';
    const error = await run(id);
    if (!this.pageActive || this.data !== data) {
      return;
    }
    this.busySessions = this.busySessions.filter((other: string): boolean => other !== id);
    if (error.length === 0 && sentDraft !== undefined && this.drafts.get(id) === sentDraft) {
      this.drafts.delete(id);
      if (this.sessionId === id) {
        this.draft = '';
      }
    }
    if (this.sessionId === id) {
      this.chatError = error;
    }
  }

  private attachDocument(): void {
    const conversation = this.data?.conversation;
    const context = this.getUIContext().getHostContext();
    if (conversation === undefined || context === undefined) {
      return;
    }
    this.chatAction(async (id: string): Promise<string> => {
      try {
        const picked = await pickDocument(context);
        if (picked.outcome === PickOutcome.CANCELLED) {
          return '';
        }
        if (picked.outcome !== PickOutcome.PICKED) {
          return picked.reason;
        }
        if (conversation !== this.data?.conversation) {
          return '';
        }
        const result = await conversation.upload(id, picked.name, picked.base64, picked.bytes, picked.mediaType);
        if (typeof result === 'string') {
          return result;
        }
        if (conversation === this.data?.conversation) {
          this.setAttachments(id, [...(this.attachmentsBySession.get(id) ?? []), result]);
        }
        return '';
      } catch (_) {
        return '无法读取所选文件';
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
      const file = await readDocumentUri(uri);
      if (file.outcome !== PickOutcome.PICKED) {
        return file.reason;
      }
      if (data !== this.data) {
        return '';
      }
      const uploaded = await data.conversation.upload(id, name, file.base64, file.bytes, file.mediaType);
      if (typeof uploaded === 'string') {
        return uploaded;
      }
      if (data === this.data) {
        this.setAttachments(id, [...(this.attachmentsBySession.get(id) ?? []), uploaded]);
      }
      return '';
    });
  }

  private setAttachments(id: string, items: PendingAttachment[]): void {
    if (items.length === 0) {
      this.attachmentsBySession.delete(id);
    } else {
      this.attachmentsBySession.set(id, items);
    }
    if (id === this.sessionId) {
      this.attachments = items;
    }
  }

  private sendMessage(): void {
    const conversation = this.data?.conversation;
    const text = this.draft;
    const files = this.attachments;
    if (conversation !== undefined && (text.trim().length > 0 || files.length > 0)) {
      this.chatAction(async (id: string): Promise<string> => {
        const result = await conversation.send(id, text, files);
        if (result.length === 0 && conversation === this.data?.conversation) {
          this.setAttachments(id, []);
        }
        return result;
      }, text);
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

  private openSessionById(id: string): void {
    for (const group of this.groups) {
      const row = group.sessions.find((session: SessionListItem): boolean => session.id === id);
      if (row !== undefined) {
        this.selectSession(group, row);
        this.panel = 'session';
        return;
      }
    }
    this.getUIContext().getPromptAction().showToast({ message: '会话暂不可用' });
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
      { value: '已归档会话', action: (): void => { this.archiveOpen = true; } }
    ];
  }

  private groupKey(group: DesktopWorkspaceGroup): string {
    const title = typeof group.title === 'string' ? group.title : '';
    const rows = group.sessions.map((session: SessionListItem): string =>
      JSON.stringify([session.id, session.title, session.running, this.pinned.includes(session.id)]));
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
  private SessionRow(group: DesktopWorkspaceGroup, session: SessionListItem) {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Text(this.sessionLabel(session)).fontSize(14).fontColor($r('sys.color.font_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (session.running) {
            LoadingProgress().width(13).height(13).color($r('sys.color.brand'))
          }
        }
        .width('100%')
      }
      .layoutWeight(1).height(32).padding({ left: 30, right: 4 }).borderRadius(8)
      .backgroundColor(Color.Transparent).focusOnTouch(false)
      .accessibilityText(this.accessibilityLabel(this.sessionLabel(session)))
      .accessibilitySelected(this.sessionId === session.id)
      .onClick((): void => {
        this.selectSession(group, session);
        this.panel = 'session';
        this.archiveOpen = false;
      })
      this.RowMenu('管理会话 ' + this.accessibilityLabel(this.sessionLabel(session)), this.sessionActions(session))
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
  private RenameSheet() {
    Column({ space: 12 }) {
      Text(this.renameWorkspace ? '重命名工作区' : '重命名会话').fontSize(20).fontWeight(FontWeight.Medium)
      TextInput({ text: this.renameDraft, placeholder: '名称' })
        .onChange((value: string): void => { this.renameDraft = value; })
        .onSubmit((): void => { this.rename(); })
      Row({ space: 8 }) {
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.workspaceBusy)
          .onClick((): void => { this.renameOpen = false; })
        Button('保存').enabled(!this.workspaceBusy && this.renameDraft.trim().length > 0)
          .onClick((): void => { this.rename(); })
      }
    }
    .width('100%').padding(18)
  }

  @Builder
  private Archive() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('已归档会话').fontSize(24).layoutWeight(1)
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.archiveOpen = false; })
      }
      .width('100%')
      if (this.archived.length === 0) {
        Text('暂无已归档会话').fontColor($r('sys.color.font_secondary'))
      }
      List({ space: 6 }) {
        ForEach(this.archived, (session: SessionListItem) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(this.sessionLabel(session)).fontSize(15).layoutWeight(1).maxLines(1)
              Button('恢复会话', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.workspaceBusy)
                .onClick((): void => { this.manage('workspace/unarchiveSession', { 'sessionId': session.id }); })
            }
            .width('100%').padding(8).borderRadius(8).backgroundColor($r('app.color.workspace_panel'))
          }
        }, (session: SessionListItem): string => session.id)
      }
      .layoutWeight(1).width('100%')
    }
    .layoutWeight(1).height('100%').padding(20).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private WorkspaceTree() {
    Row() {
      Text($r('app.string.desktop_experiment_workspaces'))
        .fontSize(14).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
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
                this.SessionRow(group, session)
              }
            }, (session: SessionListItem): string => session.id)
          }
        }, (group: DesktopWorkspaceGroup): string => this.groupKey(group))
        if (this.visibleGroups.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([$r('sys.color.font_tertiary')])
              Text(this.query.length > 0 ? $r('app.string.desktop_experiment_search_empty') :
                $r('app.string.desktop_experiment_empty')).fontSize(14).fontColor($r('sys.color.font_secondary'))
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
          title: this.selectedTitle,
          workspaceTitle: this.selectedWorkspaceTitle,
          draft: this.draft,
          attachments: this.attachments,
          onAddAttachment: (): void => this.attachDocument(),
          onRemoveAttachment: (receiptId: string): void => {
            this.setAttachments(this.sessionId, this.attachments.filter((file: PendingAttachment): boolean =>
              file.receiptId !== receiptId));
          },
          busy: this.busySessions.includes(this.sessionId),
          commandError: this.chatError,
          menuOptions: desktopMenuOptions(Placement.TopLeft),
          onDraft: (value: string): void => this.changeDraft(value),
          onSend: (): void => this.sendMessage(),
          onStop: (): void => this.stopMessage(),
          onEarlier: (): void => this.data?.conversation.loadEarlier(),
          onWeb: (): void => { this.openWeb(false); },
          filesOpen: this.filesSession === this.sessionId,
          onFiles: (): void => {
            this.filesSession = this.filesSession === this.sessionId ? '' : this.sessionId;
            this.terminalSession = '';
          },
          terminalOpen: this.terminalSession === this.sessionId,
          onTerminal: (): void => {
            this.terminalSession = this.terminalSession === this.sessionId ? '' : this.sessionId;
            this.filesSession = '';
          },
          onModel: (selection: ModelSelection): void => this.chooseModel(selection),
          onPermission: (preset: string): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined) {
              this.chatAction((id: string): Promise<string> => conversation.selectPermission(id, preset));
            }
          }
        })
        .layoutWeight(1)
        if (this.filesSession === this.sessionId && this.data !== undefined) {
          Column() {
            DesktopFilesPane({
              host: this.data.actions,
              ability: this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext'),
              sessionId: this.sessionId,
              onHide: (): void => { this.filesSession = ''; },
              onAttachWorkspaceFile: (path: string, name: string): void => { this.attachWorkspaceFile(path, name); }
            })
          }
          .width(this.rightPaneWidth).height('100%')
        } else if (this.terminalSession === this.sessionId && this.data !== undefined) {
          Column() {
            DesktopTerminalPane({
              host: this.data.actions,
              sessionId: this.sessionId,
              appearance: this.appearance,
              onHidePanel: (): void => { this.terminalSession = ''; }
            })
          }
          .width(this.rightPaneWidth).height('100%')
        }
      } else {
        this.SessionPane()
      }
    }
    .height('100%').layoutWeight(1)
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
      Column() {
        this.TopBar()
        Row() {
          this.Sidebar()
          if (this.archiveOpen) {
            this.Archive()
          } else if (this.panel === 'plugins' && this.ready && this.data !== undefined) {
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
      .onAreaChange((_, area: Area): void => {
        this.workbenchWidth = Number(area.width);
        this.sidebarWidth = Math.max(160, Math.min(280, Number(area.width) * 0.48));
        this.rightPaneWidth = Math.max(220, Math.min(520, (Number(area.width) - this.sidebarWidth) * 0.46));
      })
      .bindSheet(this.renameOpen, this.RenameSheet(), harmonySheetOptions((): void => {
        this.renameOpen = false;
      }, SheetSize.MEDIUM))
    }
  }
}
