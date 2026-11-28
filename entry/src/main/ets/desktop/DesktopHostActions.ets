import { Connection, getArray, getRecord, getString, RemoteFailure, rpcFail } from 'connection';
import type { DuplexStream, RpcResult, StreamSink } from 'connection';
import { argsFor, MODEL_CATALOG_ENDPOINT, SKILLS_LIST_ENDPOINT, TIMELINE_EDIT_ROUTE } from 'dshcompat';
import { desktopChangeSummary, DesktopChangeSummary } from './DesktopArtifacts';
import { desktopModelCatalog } from './DesktopModelCatalog';
import type { DesktopModelCatalogResult } from './DesktopModelCatalog';
import { DesktopSkill, readDesktopSkills } from './DesktopSkills';

export class DesktopHostActions {
  private readonly connection: Connection;
  private readonly referencePaths: Map<string, Promise<boolean>> = new Map();
  private readonly skillCatalogs: Map<string, Promise<DesktopSkill[] | undefined>> = new Map();
  private readonly changes: Map<string, Promise<DesktopChangeSummary | undefined>> = new Map();
  private modelCatalogWatchers?: Set<() => void>;
  private modelProviderWatchers?: Set<() => void>;
  private modelCatalogRequest?: Promise<DesktopModelCatalogResult>;
  private modelCatalogSettled: boolean = false;

  constructor(connection: Connection) {
    this.connection = connection;
  }

  sessionSkills(sessionId: string): Promise<DesktopSkill[] | undefined> {
    const cached = this.skillCatalogs.get(sessionId);
    if (cached !== undefined) { return cached; }
    if (this.skillCatalogs.size >= 64) {
      const oldest = this.skillCatalogs.keys().next();
      if (!oldest.done) { this.skillCatalogs.delete(oldest.value); }
    }
    const task = this.call(SKILLS_LIST_ENDPOINT, { 'sessionId': sessionId })
      .then((result: RpcResult): DesktopSkill[] | undefined => {
        const skills = result.ok ? readDesktopSkills(result.value) : undefined;
        if (skills === undefined && this.skillCatalogs.get(sessionId) === task) { this.skillCatalogs.delete(sessionId); }
        return skills;
      });
    this.skillCatalogs.set(sessionId, task);
    return task;
  }

  clearSkillCatalog(sessionId?: string): void {
    if (sessionId === undefined) { this.skillCatalogs.clear(); }
    else { this.skillCatalogs.delete(sessionId); }
  }

  watchModelCatalog(listener: () => void): () => void {
    const watchers = this.modelCatalogWatchers ?? new Set<() => void>();
    this.modelCatalogWatchers = watchers;
    watchers.add(listener);
    return (): void => { watchers.delete(listener); };
  }

  modelCatalogChanged(): void {
    this.modelCatalogRequest = undefined;
    this.modelCatalogSettled = false;
    this.modelCatalogWatchers?.forEach((listener: () => void): void => { listener(); });
    this.modelProvidersChanged();
  }

  watchModelProviders(listener: () => void): () => void {
    const watchers = this.modelProviderWatchers ?? new Set<() => void>();
    this.modelProviderWatchers = watchers;
    watchers.add(listener);
    return (): void => { watchers.delete(listener); };
  }

  modelProvidersChanged(): void {
    this.modelProviderWatchers?.forEach((listener: () => void): void => { listener(); });
  }

  modelCatalog(refresh: boolean = false): Promise<DesktopModelCatalogResult> {
    const previous = this.modelCatalogRequest;
    if (previous !== undefined && (!refresh || !this.modelCatalogSettled)) { return previous; }
    this.modelCatalogSettled = false;
    const request = this.call(MODEL_CATALOG_ENDPOINT).then((result: RpcResult): DesktopModelCatalogResult => {
      if (this.modelCatalogRequest === request) {
        this.modelCatalogSettled = true;
        if (!result.ok) { this.modelCatalogRequest = undefined; }
      }
      return result.ok ? { catalog: desktopModelCatalog(result.value), problem: '' } :
        { problem: result.error?.message || '无法读取模型目录' };
    });
    this.modelCatalogRequest = request;
    return request;
  }

  watch(endpoint: string, body: Record<string, Object>, sink: StreamSink): (() => void) | undefined {
    const args = argsFor(endpoint, body);
    return args === undefined ? undefined : this.connection.openStream(endpoint, args, sink);
  }

  attach(endpoint: string, body: Record<string, Object>, sink: StreamSink): DuplexStream | undefined {
    const args = argsFor(endpoint, body);
    return args === undefined ? undefined : this.connection.openDuplexStream(endpoint, args, sink);
  }

  async call(endpoint: string, body: Record<string, Object | null> = {},
    optionsTimeoutMs: number = 15000, responseLimit?: number, sensitiveBody?: boolean): Promise<RpcResult> {
    const args = argsFor(endpoint, body);
    if (args === undefined) {
      return rpcFail(new RemoteFailure('unsupported', '当前宿主协议不提供此操作', ''));
    }
    return this.connection.call(endpoint, args,
      { timeoutMs: optionsTimeoutMs, responseLimit: responseLimit, sensitiveBody: sensitiveBody });
  }

  readWorkspaceBytes(sessionId: string, path: string, limit: number): Promise<RpcResult> {
    const endpoint = 'workspaceFiles/readBytes';
    const options: Record<string, Object> = {};
    const body: Record<string, Object> = { 'workspaceFileScopeId': sessionId, 'path': path, 'options': options };
    const args = argsFor(endpoint, body);
    if (args === undefined) {
      return Promise.resolve(rpcFail(new RemoteFailure('unsupported', '当前宿主协议不支持文件字节读取', '')));
    }
    return this.connection.call(endpoint, args, { byteAttachment: true, responseLimit: limit + 64 * 1024,
      sensitiveBody: true });
  }

  editTimeline(payload: Object): Promise<RpcResult> {
    return this.connection.editTimeline(TIMELINE_EDIT_ROUTE, payload);
  }

  referencePathExists(sessionId: string, path: string): Promise<boolean> {
    const key = JSON.stringify([sessionId, path]);
    const cached = this.referencePaths.get(key);
    if (cached !== undefined) { return cached; }
    if (this.referencePaths.size >= 256) {
      const oldest = this.referencePaths.keys().next();
      if (!oldest.done) { this.referencePaths.delete(oldest.value); }
    }
    const request = this.call('workspaceFiles/stat', { 'workspaceFileScopeId': sessionId, 'path': path }, 5000)
      .then((result: RpcResult): boolean => {
        const code = result.error?.code;
        if (result.ok || code === 'workspace-file/not-regular-file') { return true; }
        if (code !== 'workspace-file/not-found' && this.referencePaths.get(key) === request) {
          this.referencePaths.delete(key);
        }
        return false;
      });
    this.referencePaths.set(key, request);
    return request;
  }

  changeSummary(sessionId: string, sequence: number): Promise<DesktopChangeSummary | undefined> {
    const key = `${sessionId}:${sequence}`;
    const cached = this.changes.get(key);
    if (cached !== undefined) {
      return cached;
    }
    if (this.changes.size >= 64) {
      const oldest = this.changes.keys().next();
      if (!oldest.done) {
        this.changes.delete(oldest.value);
      }
    }
    const task = this.connection.readApiDocument('changes.summary', {
      'sessionId': sessionId, 'seq': String(sequence)
    }).then((result: RpcResult): DesktopChangeSummary | undefined => {
      if (!result.ok && result.error?.httpStatus !== 404) {
        this.changes.delete(key);
      }
      return desktopChangeSummary(result.value);
    });
    this.changes.set(key, task);
    return task;
  }

  changeDiff(sessionId: string, sequence: number, index: number): Promise<RpcResult> {
    return this.connection.readApiDocument('changes.diff', {
      'sessionId': sessionId, 'seq': String(sequence), 'index': String(index)
    });
  }

  accountContactDocument(): Promise<RpcResult> {
    return this.connection.readApiDocument('dshm.account.contact', {});
  }
}

export function desktopHostProblem(result: RpcResult): string {
  if (!result.ok) {
    return result.error?.message || '宿主请求失败';
  }
  const value = result.value;
  const code = getString(value, 'code');
  if (code === 'schedule_conflict') {
    return '任务已在其他窗口修改，请刷新后重试';
  }
  if (code === 'schedule_execution_pending') {
    return '任务已在排队或运行';
  }
  if (code === 'schedule_not_found' || code === 'delivery_cursor_not_found') {
    return '任务或投递记录已变化，请刷新后重试';
  }
  const outcome = getString(value, 'application');
  if (outcome === 'failed' || outcome === 'overridden' || outcome === 'cancelled') {
    const error = getRecord(value, 'error');
    return getString(error, 'message') || getString(error, 'code') || (
      outcome === 'overridden' ? '当前配置覆盖了本次操作' :
        outcome === 'cancelled' ? '操作已取消' : '宿主未能应用修改'
    );
  }
  return '';
}

export function desktopHostItems(result: RpcResult): Object[] {
  const wrapped: Record<string, Object> = { 'items': result.value ?? '' };
  return getArray(wrapped, 'items') ?? [];
}

export function desktopLocalizedText(value: Object | undefined, field: string, locale: string = ''): string {
  const map = getRecord(value, field);
  const language = locale.split('-')[0];
  return getString(value, field) || (locale ? getString(map, locale) || getString(map, language) ||
    (language === 'en' ? getString(map, 'en-US') : '') : '') || getString(map, 'zh-CN') || getString(map, 'zh') ||
    getString(map, 'en-US') || getString(map, 'en') || '';
}
