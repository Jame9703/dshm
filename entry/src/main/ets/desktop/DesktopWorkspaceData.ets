import { projectSessionCreate, projectSessionList, sessionCreatePayload, sessionListEndpoint, sessionListPayload } from 'appstate';
import type { SessionListItem } from 'appstate';
import { Connection, getArray, getRecord, getString, toStringArray } from 'connection';
import type { EventSink, StreamSink } from 'connection';
import { argsFor, EVENT_COMMANDS_CHANGE, EVENT_GOAL_ACTIVATION_CHANGED, EVENT_LLM_ADAPTERS_UPDATED, EVENT_SESSION_STATUS,
  EVENT_SETTINGS_DOCUMENT_UPDATED,
  SESSION_CREATE_ENDPOINT, SESSION_FORK_ENDPOINT, SETTINGS_DESCRIBE_ENDPOINT, WORKSPACE_FOLLOW_ENDPOINT } from 'dshcompat';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopInteractions } from './DesktopInteractions';
import type { DesktopInteraction } from './DesktopInteractions';
import { DesktopConversation } from './DesktopConversation';
import type { DesktopConversationSnapshot } from './DesktopConversation';
import { desktopForkTitle } from './DesktopReplyTimeline';
import { DesktopSessionReading } from './DesktopSessionReading';
import type { DesktopUnreadSession } from './DesktopSessionReading';

export interface DesktopForkResult {
  id: string;
  problem: string;
}

export interface DesktopWorkspaceRow {
  id: string;
  path: string;
  title: string;
  sessionIds: string[];
}

export interface DesktopWorkspaceSnapshot {
  workspaces: DesktopWorkspaceRow[];
  sessions: SessionListItem[];
  archivedIds: string[];
  pinned: string[];
  ready: boolean;
  error: string;
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
    sessionIds: toStringArray(getArray(raw, 'sessionIds') ?? [])
  };
}

export class DesktopWorkspaceData {
  private readonly connection: Connection = new Connection();
  readonly conversation: DesktopConversation;
  readonly interactions: DesktopInteractions;
  readonly actions: DesktopHostActions = new DesktopHostActions(this.connection);
  readonly reading: DesktopSessionReading;
  private readonly listener: (snapshot: DesktopWorkspaceSnapshot) => void;
  private active: boolean = true;
  private workspaceReady: boolean = false;
  private sessionsReady: boolean = false;
  private refreshVersion: number = 0;
  private workspaceError: string = '';
  private sessionError: string = '';
  private workspaces: DesktopWorkspaceRow[] = [];
  private sessions: SessionListItem[] = [];
  private archivedIds: Set<string> = new Set<string>();
  private pinnedIds: string[] = [];
  private stopWorkspace?: () => void;

  constructor(listener: (snapshot: DesktopWorkspaceSnapshot) => void,
    onConversation: (snapshot: DesktopConversationSnapshot) => void,
    onInteractions: (items: DesktopInteraction[]) => void,
    onReading: (items: DesktopUnreadSession[], ready: boolean) => void, afterFrame: (run: () => void) => void) {
    this.listener = listener;
    this.reading = new DesktopSessionReading(this.actions, onReading, afterFrame);
    this.interactions = new DesktopInteractions(this.connection, this.actions, onInteractions);
    this.conversation = new DesktopConversation(this.connection, onConversation,
      (): void => { this.refreshSessions(); }, this.interactions, this.actions);
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
        this.readSubmitPreference();
        this.actions.modelCatalogChanged();
      },
      onEvent: (frame: Object): void => {
        this.interactions.onEvent(frame);
        const event = getString(frame, 'event');
        if (event === EVENT_COMMANDS_CHANGE) { this.conversation.invalidateCommands(); }
        if (event === EVENT_GOAL_ACTIVATION_CHANGED) { this.conversation.observeGoalActivation(frame); }
        if (event === EVENT_LLM_ADAPTERS_UPDATED) { this.actions.modelCatalogChanged(); }
        if (event === EVENT_SESSION_STATUS) { this.observeSessionStatus(frame); }
        if (event === EVENT_SETTINGS_DOCUMENT_UPDATED) {
          const namespace = getArray(frame, 'args')?.[0];
          if (namespace === 'ui-conversation') { this.readSubmitPreference(); }
          if (typeof namespace === 'string' && (namespace.startsWith('llm-') || namespace === 'agent-default-model')) {
            this.actions.modelCatalogChanged();
          }
        }
      },
      onEnd: (): void => { this.interactions.resetEvents(); }
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

  private submitPreferenceVersion: number = 0;

  private async readSubmitPreference(): Promise<void> {
    const version = ++this.submitPreferenceVersion;
    const result = await this.actions.call(SETTINGS_DESCRIBE_ENDPOINT, {});
    if (!result.ok || !this.active || version !== this.submitPreferenceVersion) { return; }
    const settings = getArray(result.value, 'namespaces')?.find((row: Object): boolean =>
      getString(row, 'ns') === 'ui-conversation');
    this.conversation.setBusyEnter(getString(getRecord(settings, 'value'), 'busyEnter') === 'steer');
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

  async createSession(workspaceId: string): Promise<string> {
    const args = sessionCreatePayload(workspaceId, '', '', '');
    if (args === undefined) {
      return '';
    }
    const result = await this.connection.call(SESSION_CREATE_ENDPOINT, args);
    if (!this.active || !result.ok) {
      return '';
    }
    const id = projectSessionCreate(result.value)?.sessionId ?? '';
    if (id.length > 0) {
      await this.refreshSessions();
    }
    return id;
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
    const result = await this.actions.call(endpoint, payload);
    if (!result.ok) {
      return result.error?.message ?? '宿主未能保存修改';
    }
    if (endpoint === 'session/rename') {
      await this.refreshSessions();
    }
    return '';
  }

  stop(): void {
    this.active = false;
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
    const previous = this.sessions.find((row: SessionListItem): boolean => row.id === id);
    if (previous === undefined || previous.running === running) { return; }
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
      const ids = toStringArray(getArray(frame, 'workspaceIds') ?? []);
      const ranks = new Map<string, number>();
      ids.forEach((id: string, index: number): void => { ranks.set(id, index); });
      this.workspaces = this.workspaces.slice().sort((a: DesktopWorkspaceRow, b: DesktopWorkspaceRow): number =>
        (ranks.get(a.id) ?? ids.length) - (ranks.get(b.id) ?? ids.length));
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
      this.listener({
        workspaces: this.workspaces,
        sessions: this.sessions,
        archivedIds: Array.from(this.archivedIds),
        pinned: this.pinnedIds,
        ready: this.workspaceReady && this.sessionsReady,
        error: this.workspaceError || this.sessionError
      });
    }
  }
}
