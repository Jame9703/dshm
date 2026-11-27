import { DEFAULT_DESKTOP_TRANSCRIPT_POLICY, readDesktopTranscriptPolicy } from './DesktopTranscriptPresentation';
import type { DesktopTranscriptPolicy } from './DesktopTranscriptPresentation';
import { projectSessionCreate, projectSessionList, sessionCreatePayload, sessionListEndpoint, sessionListPayload } from 'appstate';
import type { SessionListItem } from 'appstate';
import { Connection, getArray, getRecord, getString, toStringArray } from 'connection';
import type { EventSink, StreamSink } from 'connection';
import { argsFor, EVENT_COMMANDS_CHANGE, EVENT_GOAL_ACTIVATION_CHANGED, EVENT_LLM_ADAPTERS_UPDATED, EVENT_SESSION_STATUS,
  EVENT_SETTINGS_DOCUMENT_UPDATED,
  PROJECTION_AGENT_PRESET, SESSION_CREATE_ENDPOINT, SESSION_FORK_ENDPOINT, SETTINGS_DESCRIBE_ENDPOINT,
  WORKSPACE_FOLLOW_ENDPOINT } from 'dshcompat';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { DesktopPluginInstall } from './DesktopPluginInstall';
import { DesktopConnectorAccounts } from './DesktopConnectorAccounts';
import { DesktopCordisRuntime } from './DesktopCordisRuntime';
import { DESKTOP_THEME_NS, desktopThemeFrom } from './DesktopTheme';
import type { DesktopTheme } from './DesktopTheme';
import { DesktopAccountNotices } from './DesktopAccountNotices';
import type { DesktopAccountNotice } from './DesktopAccountNotices';
import { DesktopInteractions } from './DesktopInteractions';
import type { DesktopInteraction } from './DesktopInteractions';
import { DesktopConversation } from './DesktopConversation';
import type { DesktopConversationSnapshot } from './DesktopConversation';
import { desktopForkTitle } from './DesktopReplyTimeline';
import { DesktopSessionReading } from './DesktopSessionReading';
import type { DesktopUnreadSession } from './DesktopSessionReading';
import { desktopInsertWorkspaceBefore } from './DesktopSessionOrder';
import type { DesktopSidebarPending } from './DesktopSidebarStatus';

export interface DesktopForkResult {
  id: string;
  problem: string;
}

export interface DesktopSessionCreation {
  id: string;
  problem: string;
}

export interface DesktopWorkspaceRow {
  id: string;
  path: string;
  title: string;
  createdAt: string;
  sessionIds: string[];
}

export interface DesktopWorkspaceSnapshot {
  workspaces: DesktopWorkspaceRow[];
  sessions: SessionListItem[];
  unlistedRunning: string[];
  archivedIds: string[];
  pinned: string[];
  ready: boolean;
  error: string;
}

export interface DesktopDockConversation {
  conversation: DesktopConversation;
  interactions: DesktopInteractions;
  close: () => void;
}

function workspaceFromHost(raw: Object): DesktopWorkspaceRow | undefined {
  const id: string = getString(raw, 'workspaceId') ?? '';
  if (id.length === 0) {
    return undefined;
  }
  return {
    id: id,
    path: getString(raw, 'path') ?? '',
    title: getString(raw, 'title') ?? '',
    createdAt: getString(raw, 'createdAt') ?? '',
    sessionIds: toStringArray(getArray(raw, 'sessionIds') ?? [])
  };
}

export class DesktopWorkspaceData {
  private readonly connection: Connection = new Connection();
  readonly conversation: DesktopConversation;
  readonly interactions: DesktopInteractions;
  readonly actions: DesktopHostActions = new DesktopHostActions(this.connection);
  readonly pluginInstall: DesktopPluginInstall = new DesktopPluginInstall(this.actions);
  readonly cordis: DesktopCordisRuntime = new DesktopCordisRuntime(this.actions);
  readonly connectorAccounts: DesktopConnectorAccounts;
  readonly reading: DesktopSessionReading;
  readonly accountNotices: DesktopAccountNotices;
  private readonly listener: (snapshot: DesktopWorkspaceSnapshot) => void;
  private readonly afterFrame: (run: () => void) => void;
  private readonly onTheme: (theme: DesktopTheme) => void;
  private accountWatchScheduled: boolean = false;
  private accountWatchEnabled: boolean = false;
  private active: boolean = true;
  private workspaceReady: boolean = false;
  private sessionsReady: boolean = false;
  private refreshVersion: number = 0;
  private workspaceError: string = '';
  private sessionError: string = '';
  private workspaces: DesktopWorkspaceRow[] = [];
  private workspaceOrderRevision: number = 0;
  private sessions: SessionListItem[] = [];
  private readonly unlistedRunning: Set<string> = new Set<string>();
  private archivedIds: Set<string> = new Set<string>();
  private pinnedIds: string[] = [];
  private stopWorkspace?: () => void;
  private dockConversations?: Set<DesktopDockConversation>;
  private busyEnterSteers: boolean = false;
  private compactUsage: boolean = false;
  private transcriptPolicy: DesktopTranscriptPolicy = DEFAULT_DESKTOP_TRANSCRIPT_POLICY;
  private browserInDock: boolean = true;

  opensLinksInDock(): boolean { return this.browserInDock; }

  constructor(listener: (snapshot: DesktopWorkspaceSnapshot) => void,
    onConversation: (snapshot: DesktopConversationSnapshot) => void,
    onInteractions: (items: DesktopInteraction[]) => void,
    onReading: (items: DesktopUnreadSession[], ready: boolean) => void, afterFrame: (run: () => void) => void,
    onSidebarPending: (pending: Map<string, DesktopSidebarPending>) => void,
    onAccountNotices: (notices: DesktopAccountNotice[]) => void, onTheme: (theme: DesktopTheme) => void,
    openConnectorLink: (link: string) => Promise<boolean>, onConnectorNotice: (message: ResourceStr) => void) {
    this.listener = listener;
    this.afterFrame = afterFrame;
    this.onTheme = onTheme;
    this.connectorAccounts = new DesktopConnectorAccounts(this.actions, openConnectorLink, onConnectorNotice);
    this.accountNotices = new DesktopAccountNotices(this.actions, onAccountNotices);
    this.reading = new DesktopSessionReading(this.actions, onReading, afterFrame);
    this.interactions = new DesktopInteractions(this.connection, this.actions, onInteractions);
    this.interactions.observeSidebarPending(onSidebarPending);
    this.conversation = new DesktopConversation(this.connection, onConversation,
      (): void => { this.refreshSessions(); }, this.interactions, this.actions, this.cordis);
  }

  createDockConversation(onConversation: (snapshot: DesktopConversationSnapshot) => void,
    onInteractions: (items: DesktopInteraction[]) => void): DesktopDockConversation | undefined {
    if (!this.active) { return undefined; }
    const conversations = this.dockConversations ?? new Set<DesktopDockConversation>();
    this.dockConversations = conversations;
    const interactions = this.interactions.createView(onInteractions);
    const conversation = new DesktopConversation(this.connection, onConversation,
      (): void => { this.refreshSessions(); }, interactions, this.actions, this.cordis);
    const binding: DesktopDockConversation = { conversation: conversation, interactions: interactions,
      close: (): void => {
        if (!conversations.delete(binding)) { return; }
        conversation.close();
        interactions.closeView();
      } };
    conversations.add(binding);
    conversation.setPreferences(this.busyEnterSteers, this.compactUsage, this.transcriptPolicy);
    return binding;
  }

  async start(url: string): Promise<void> {
    if (this.connection.configure(url) === undefined || !(await this.connection.authenticate()).ok) {
      this.workspaceError = '无法连接工作区宿主';
      this.publish();
      return;
    }
    if (!this.active) {
      return;
    }
    const eventSink: EventSink = {
      onReady: (): void => {
        this.openWorkspaceStream();
        this.reading.connect();
        this.conversation.invalidateCommands();
        this.conversation.feedback.resync();
        this.conversation.readGoalActivation();
        this.dockConversations?.forEach((binding: DesktopDockConversation): void => {
          binding.conversation.invalidateCommands();
          binding.conversation.feedback.resync();
          binding.conversation.readGoalActivation();
        });
        this.readConversationPreferences();
        this.actions.modelCatalogChanged();
        this.pluginInstall.reconnect();
        this.connectorAccounts.reconnect();
        this.cordis.reconnect();
        if (this.accountWatchEnabled) { this.accountNotices.connect(); }
      },
      onEvent: (frame: Object): void => {
        this.interactions.onEvent(frame);
        this.pluginInstall.observe(frame);
        const event = getString(frame, 'event');
        this.cordis.observe(event);
        if (event === EVENT_COMMANDS_CHANGE) {
          this.conversation.invalidateCommands();
          this.dockConversations?.forEach((binding: DesktopDockConversation): void => binding.conversation.invalidateCommands());
        }
        if (event === EVENT_GOAL_ACTIVATION_CHANGED) {
          this.conversation.observeGoalActivation(frame);
          this.dockConversations?.forEach((binding: DesktopDockConversation): void => binding.conversation.observeGoalActivation(frame));
        }
        if (event === EVENT_LLM_ADAPTERS_UPDATED) { this.actions.modelCatalogChanged(); }
        if (event === EVENT_SESSION_STATUS) { this.observeSessionStatus(frame); }
        if (event === EVENT_SETTINGS_DOCUMENT_UPDATED) {
          const namespace = getArray(frame, 'args')?.[0];
          if (namespace === 'ui-conversation' || namespace === 'ui-chat' || namespace === 'locale' ||
            namespace === DESKTOP_THEME_NS) {
            this.readConversationPreferences();
          }
          if (typeof namespace === 'string' && (namespace.startsWith('llm-') || namespace === 'agent-default-model')) {
            this.actions.modelCatalogChanged();
          }
        }
      },
      onEnd: (): void => {
        this.interactions.resetEvents();
        if (this.unlistedRunning.size > 0) {
          this.unlistedRunning.clear();
          this.publish();
        }
      }
    };
    const opening: Promise<boolean> = this.connection.start(eventSink);
    this.refreshSessions();
    const opened: boolean = await opening;
    if (!this.active) {
      await this.connection.stop();
      return;
    }
    if (opened) {
      this.openWorkspaceStream();
      this.reading.connect();
    }
  }

  private conversationPreferencesVersion: number = 0;

  private async readConversationPreferences(): Promise<void> {
    const version = ++this.conversationPreferencesVersion;
    const result = await this.actions.call(SETTINGS_DESCRIBE_ENDPOINT, {});
    if (!result.ok || !this.active || version !== this.conversationPreferencesVersion) { return; }
    const namespaces = getArray(result.value, 'namespaces');
    const settings = namespaces?.find((row: Object): boolean =>
      getString(row, 'ns') === 'ui-conversation');
    const chat = namespaces?.find((row: Object): boolean => getString(row, 'ns') === 'ui-chat');
    const chatValue = getRecord(chat, 'value');
    this.browserInDock = getString(chatValue, 'linkOpening') !== 'new-tab';
    this.compactUsage = getString(chatValue, 'performanceUsage') === 'compact';
    this.transcriptPolicy = readDesktopTranscriptPolicy(chatValue);
    const locale = namespaces?.find((row: Object): boolean => getString(row, 'ns') === 'locale');
    const theme = namespaces?.find((row: Object): boolean => getString(row, 'ns') === DESKTOP_THEME_NS);
    const appearance = getRecord(theme, 'value');
    if (appearance !== undefined) { this.onTheme(desktopThemeFrom(appearance)); }
    const language = getString(getRecord(locale, 'value'), 'preference') ?? 'system';
    this.accountNotices.setLocale(language);
    this.connectorAccounts.setLocale(language);
    this.busyEnterSteers = getString(getRecord(settings, 'value'), 'busyEnter') === 'steer';
    this.conversation.setPreferences(this.busyEnterSteers, this.compactUsage, this.transcriptPolicy);
    this.dockConversations?.forEach((binding: DesktopDockConversation): void => {
      binding.conversation.setPreferences(this.busyEnterSteers, this.compactUsage, this.transcriptPolicy);
    });
  }

  private openWorkspaceStream(): void {
    if (!this.active || this.stopWorkspace !== undefined) {
      return;
    }
    const empty: Record<string, Object> = {};
    const args: Object | undefined = argsFor(WORKSPACE_FOLLOW_ENDPOINT, empty);
    if (args !== undefined) {
      const sink: StreamSink = {
        onItem: (frame: Object): void => this.onWorkspaceFrame(frame),
        onError: (): void => this.workspaceStreamEnded(),
        onEnd: (): void => this.workspaceStreamEnded()
      };
      this.stopWorkspace = this.connection.openStream(WORKSPACE_FOLLOW_ENDPOINT, args, sink);
    }
    if (this.stopWorkspace === undefined) {
      this.workspaceStreamEnded();
    }
  }

  workspacePath(workspaceId: string): string {
    return this.workspaces.find((row: DesktopWorkspaceRow): boolean => row.id === workspaceId)?.path ?? '';
  }

  async createWorkspace(path: string): Promise<string> {
    const result = await this.actions.call('workspace/create', { 'path': path });
    if (!this.active || !result.ok) {
      return '';
    }
    const workspace = getRecord(result.value, 'workspace');
    return getString(workspace, 'workspaceId') ?? '';
  }

  creatorWorkspace(sessionId: string): string {
    const owner = this.workspaces.find((row: DesktopWorkspaceRow): boolean => row.sessionIds.includes(sessionId));
    if (owner !== undefined) { return owner.id; }
    const activity: Map<string, number> = new Map();
    for (const session of this.sessions) { activity.set(session.id, session.updatedAt); }
    let chosen = '';
    let newest = Number.NEGATIVE_INFINITY;
    for (const workspace of this.workspaces) {
      let last = Number.NEGATIVE_INFINITY;
      for (const id of workspace.sessionIds) { last = Math.max(last, activity.get(id) ?? Number.NEGATIVE_INFINITY); }
      if (last === Number.NEGATIVE_INFINITY) {
        const created = Date.parse(workspace.createdAt);
        if (Number.isFinite(created)) { last = created; }
      }
      if (!chosen || last > newest) { chosen = workspace.id; newest = last; }
    }
    return chosen;
  }

  private reusableBlank(workspaceId: string, preset: string): string {
    const workspace = this.workspaces.find((row: DesktopWorkspaceRow): boolean => row.id === workspaceId);
    if (workspace === undefined) { return ''; }
    const blank = this.sessions.find((session: SessionListItem): boolean => {
      if (!session.blank || session.cwd !== workspace.path || !workspace.sessionIds.includes(session.id) ||
        this.archivedIds.has(session.id)) { return false; }
      const values = getRecord(getRecord(session.raw, 'projections'), 'values');
      const current = getString(values, PROJECTION_AGENT_PRESET);
      return current === undefined || current === preset;
    });
    return blank?.id ?? '';
  }

  async createSession(workspaceId: string, preset: string = ''): Promise<DesktopSessionCreation> {
    const args = sessionCreatePayload(workspaceId, '', preset ? this.reusableBlank(workspaceId, preset) : '', preset);
    if (args === undefined) {
      return { id: '', problem: '' };
    }
    const result = await this.connection.call(SESSION_CREATE_ENDPOINT, args);
    if (!this.active || !result.ok) {
      return { id: '', problem: desktopHostProblem(result) };
    }
    const created = projectSessionCreate(result.value);
    const id = created?.sessionId ?? '';
    if (id.length > 0) {
      await this.refreshSessions();
    }
    if (preset && created?.agentPreset !== undefined && created.agentPreset !== preset) {
      return { id: '', problem: '' };
    }
    return { id: id, problem: '' };
  }

  async forkSession(sessionId: string, atSeq?: number): Promise<DesktopForkResult> {
    const source = this.sessions.find((session: SessionListItem): boolean => session.id === sessionId);
    const request: Record<string, Object> = { 'sessionId': sessionId, 'allowMigration': atSeq !== undefined };
    if (atSeq !== undefined) { request['atSeq'] = atSeq; }
    const result = await this.actions.call(SESSION_FORK_ENDPOINT, request);
    if (!this.active) { return { id: '', problem: '' }; }
    if (!result.ok) {
      if (result.error?.code === 'session/workspace-attach-failed') { await this.refreshSessions(); }
      const code = result.error?.code;
      return { id: '', problem: code === 'session/migration-required' ? '请先打开会话完成迁移，再分叉' :
        (code === 'session/fork-unavailable' ? '会话没有可分叉的已完成回合' : result.error?.message || '分叉会话失败') };
    }
    const id = getString(result.value, 'sessionId') ?? '';
    if (!id) { return { id: '', problem: '宿主未返回分叉会话' }; }
    let problem = '';
    if (source?.title) {
      const taken = new Set<string>(this.sessions.map((session: SessionListItem): string => session.title));
      const renamed = await this.actions.call('session/rename', { 'sessionId': id, 'title': desktopForkTitle(source.title, taken) });
      if (!renamed.ok) { problem = '会话已分叉，但重命名失败'; }
    }
    await this.refreshSessions();
    return { id: id, problem: problem };
  }

  async manage(endpoint: string, payload: Record<string, Object>): Promise<string> {
    if (endpoint === 'workspace/insertBefore') { return this.reorderWorkspace(payload); }
    const result = await this.actions.call(endpoint, payload);
    if (!result.ok) {
      return result.error?.message ?? '宿主未能保存修改';
    }
    if (endpoint === 'session/rename') {
      await this.refreshSessions();
    }
    return '';
  }

  private applyWorkspaceOrder(ids: string[]): void {
    const ranks = new Map<string, number>();
    ids.forEach((id: string, index: number): void => { ranks.set(id, index); });
    this.workspaces = this.workspaces.slice().sort((a: DesktopWorkspaceRow, b: DesktopWorkspaceRow): number =>
      (ranks.get(a.id) ?? ids.length) - (ranks.get(b.id) ?? ids.length));
  }

  private async reorderWorkspace(payload: Record<string, Object>): Promise<string> {
    const previous = this.workspaces.map((row: DesktopWorkspaceRow): string => row.id);
    const id = getString(payload, 'workspaceId') ?? '';
    const optimistic = desktopInsertWorkspaceBefore(previous, id, getString(payload, 'beforeWorkspaceId'));
    if (optimistic === undefined) { return ''; }
    const revision = this.workspaceOrderRevision;
    this.applyWorkspaceOrder(optimistic);
    this.publish();
    const result = await this.actions.call('workspace/insertBefore', payload);
    if (!this.active) { return ''; }
    const returned = getArray(result.value, 'workspaceIds');
    const confirmed = returned === undefined ? [] : toStringArray(returned);
    const accepted = result.ok && confirmed.includes(id) && new Set<string>(confirmed).size === confirmed.length;
    // A follow frame can carry a newer complete order while this request is still returning.
    if (revision === this.workspaceOrderRevision) {
      this.applyWorkspaceOrder(accepted ? confirmed : previous);
      this.publish();
    }
    return accepted ? '' : (result.error?.message ?? '宿主未能保存工作区顺序');
  }

  stop(): void {
    this.active = false;
    this.pluginInstall.dispose();
    this.connectorAccounts.dispose();
    this.cordis.dispose();
    this.accountNotices.stop();
    this.dockConversations?.forEach((binding: DesktopDockConversation): void => binding.close());
    this.reading.close();
    this.conversation.close();
    this.interactions.select('');
    this.interactions.resetEvents();
    this.stopWorkspace?.();
    this.connection.stop();
  }

  private async refreshSessions(): Promise<void> {
    const version: number = ++this.refreshVersion;
    const empty: Record<string, Object> = {};
    const args: Object | undefined = sessionListPayload(empty);
    if (args === undefined) {
      this.sessionError = '当前宿主协议无法读取会话列表';
      this.publish();
      return;
    }
    const result = await this.connection.call(sessionListEndpoint(), args);
    if (!this.active || version !== this.refreshVersion) {
      return;
    }
    if (result.ok) {
      this.sessions = projectSessionList(result.value).items;
      this.sessions.forEach((row: SessionListItem): void => { this.unlistedRunning.delete(row.id); });
      this.sessionsReady = true;
      this.sessionError = '';
    } else {
      this.sessionError = '无法读取会话列表';
    }
    this.publish();
  }

  private observeSessionStatus(frame: Object): void {
    const args = getArray(frame, 'args');
    const id = args?.[0];
    const running = args?.[1];
    if (typeof id !== 'string' || typeof running !== 'boolean' || !this.active) { return; }
    // Defining or removing a stopped plugin may finish without a Cordis broadcast.
    if (!running) { this.cordis.refresh(); }
    const previous = this.sessions.find((row: SessionListItem): boolean => row.id === id);
    if (previous === undefined) {
      if (this.unlistedRunning.has(id) === running) { return; }
      if (running) { this.unlistedRunning.add(id); }
      else { this.unlistedRunning.delete(id); }
      this.publish();
      return;
    }
    if (previous.running === running) { return; }
    const updated: SessionListItem = { id: previous.id, title: previous.title, cwd: previous.cwd, blank: previous.blank,
      raw: previous.raw, running: running, createdAt: previous.createdAt, updatedAt: previous.updatedAt };
    this.sessions = this.sessions.map((row: SessionListItem): SessionListItem => row.id === id ? updated : row);
    this.publish();
  }

  private onWorkspaceFrame(frame: Object): void {
    if (!this.active) {
      return;
    }
    const type = getString(frame, 'type');
    if (type === 'baseline' || type === 'replace') {
      const value = getRecord(frame, 'value');
      if (value === undefined) {
        return;
      }
      const rows: DesktopWorkspaceRow[] = [];
      for (const item of getArray(value, 'items') ?? []) {
        const row = workspaceFromHost(item);
        if (row !== undefined) {
          rows.push(row);
        }
      }
      this.workspaceOrderRevision++;
      this.workspaces = rows;
      this.archivedIds = new Set<string>(toStringArray(getArray(value, 'archivedSessionIds') ?? []));
      this.pinnedIds = toStringArray(getArray(value, 'pinnedSessionIds') ?? []);
      this.workspaceReady = true;
      this.workspaceError = '';
    } else if (type === 'upsert') {
      const workspace = getRecord(frame, 'workspace');
      const row = workspace === undefined ? undefined : workspaceFromHost(workspace);
      if (row !== undefined) {
        const index = this.workspaces.findIndex((current: DesktopWorkspaceRow): boolean => current.id === row.id);
        this.workspaces = this.workspaces.slice();
        if (index < 0) {
          this.workspaces.push(row);
        } else {
          this.workspaces[index] = row;
        }
      }
    } else if (type === 'remove') {
      const id = getString(frame, 'workspaceId');
      this.workspaces = this.workspaces.filter((row: DesktopWorkspaceRow): boolean => row.id !== id);
    } else if (type === 'order') {
      this.workspaceOrderRevision++;
      this.applyWorkspaceOrder(toStringArray(getArray(frame, 'workspaceIds') ?? []));
    } else if (type === 'pinned') {
      this.pinnedIds = toStringArray(getArray(frame, 'pinnedSessionIds') ?? []);
    } else if (type === 'archived') {
      this.archivedIds = new Set<string>(toStringArray(getArray(frame, 'archivedSessionIds') ?? []));
    }
    this.publish();
    if (type === 'upsert' || type === 'replace' || type === 'archived') {
      this.refreshSessions();
    }
  }

  private workspaceStreamEnded(): void {
    this.stopWorkspace = undefined;
    this.workspaceError = '工作区列表连接已中断';
    this.publish();
  }

  private publish(): void {
    if (this.active) {
      const ready = this.workspaceReady && this.sessionsReady;
      this.listener({
        workspaces: this.workspaces,
        sessions: this.sessions,
        unlistedRunning: Array.from(this.unlistedRunning),
        archivedIds: Array.from(this.archivedIds),
        pinned: this.pinnedIds,
        ready: ready,
        error: this.workspaceError || this.sessionError
      });
      if (ready && !this.accountWatchScheduled) {
        this.accountWatchScheduled = true;
        this.afterFrame((): void => {
          if (this.active) {
            this.accountWatchEnabled = true;
            this.accountNotices.connect();
            this.cordis.start();
          }
        });
      }
    }
  }
}
