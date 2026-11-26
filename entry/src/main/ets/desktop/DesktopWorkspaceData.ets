import { projectSessionCreate, projectSessionList, sessionCreatePayload, sessionListEndpoint, sessionListPayload } from 'appstate';
import type { SessionListItem } from 'appstate';
import { Connection, getArray, getRecord, getString, toStringArray } from 'connection';
import type { EventSink, StreamSink } from 'connection';
import { argsFor, SESSION_CREATE_ENDPOINT, WORKSPACE_FOLLOW_ENDPOINT } from 'dshcompat';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopInteractions } from './DesktopInteractions';
import type { DesktopInteraction } from './DesktopInteractions';
import { DesktopConversation } from './DesktopConversation';
import type { DesktopConversationSnapshot } from './DesktopConversation';

export interface DesktopWorkspaceRow {
  id: string;
  path: string;
  title: string;
  sessionIds: string[];
}

export interface DesktopWorkspaceSnapshot {
  workspaces: DesktopWorkspaceRow[];
  sessions: SessionListItem[];
  archived: SessionListItem[];
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
    onInteractions: (items: DesktopInteraction[]) => void) {
    this.listener = listener;
    this.interactions = new DesktopInteractions(this.connection, this.actions, onInteractions);
    this.conversation = new DesktopConversation(this.connection, onConversation,
      (): void => { this.refreshSessions(); }, this.interactions);
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
      onReady: (): void => { this.openWorkspaceStream(); },
      onEvent: (frame: Object): void => { this.interactions.onEvent(frame); },
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
    }
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
        sessions: this.sessions.filter((row: SessionListItem): boolean => !this.archivedIds.has(row.id)),
        archived: this.sessions.filter((row: SessionListItem): boolean => this.archivedIds.has(row.id)),
        pinned: this.pinnedIds,
        ready: this.workspaceReady && this.sessionsReady,
        error: this.workspaceError || this.sessionError
      });
    }
  }
}
