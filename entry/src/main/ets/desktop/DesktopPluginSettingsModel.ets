import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';
import type { ModelOption } from 'appstate';

export const WEB_PLUGIN_SETTINGS: string = 'web-search';
export const SHELL_PLUGIN_SETTINGS: string = 'shell';
export const WEB_SETTINGS: string = 'web';
export const WEB_API_SETTINGS: string = 'web-deepseek-api';
export const WEB_LEGACY_SETTINGS: string = 'web-search-deepseek';
export const AGENT_LOOP_SETTINGS: string = 'agent-loop';
export const BASH_SETTINGS: string = 'bash-sandbox';
export const PWSH_SETTINGS: string = 'pwsh-sandbox';
export const WORKTREE_SETTINGS: string = 'worktree';
export const DESKTOP_FORGE_BUNDLE: string = '@deepseek-ai/dsh-experimental-forge-bundle';
export const SUBAGENT_SETTINGS: string = 'subagent';
export const SUBAGENT_MODEL_SETTINGS: string = 'subagent-model-selection-settings';
export const WEB_SEARCH_API: string = 'deepseek-search-api';
export const WEB_SEARCH_LEGACY: string = 'deepseek-official';
export const WEB_FETCH_API: string = 'deepseek-fetch-api';

export interface DesktopPluginDocument {
  id: string;
  revision: number;
  value?: Object;
  base?: Object;
  user?: Object;
}

export interface DesktopPluginConfiguration {
  writable: boolean;
  documents: DesktopPluginDocument[];
}

export interface DesktopPluginEdit {
  namespace: string;
  field: string;
  value?: Object;
}

export interface DesktopWebProvider {
  id: string;
  title: string;
}

export interface DesktopSubagentRoute {
  provider: string;
  model: string;
}

export interface DesktopSubagentAuthorization {
  enabled: boolean;
  routes: DesktopSubagentRoute[];
  revision: number;
}

export interface DesktopSubagentModel {
  route: DesktopSubagentRoute;
  name: string;
  providerName: string;
  key: string;
  available: boolean;
}

export interface DesktopSubagentModelGroup {
  key: string;
  title: string;
  models: DesktopSubagentModel[];
}

export function readDesktopPluginConfiguration(value?: Object, scope: string = ''): DesktopPluginConfiguration {
  const names = desktopPluginConfigurationNamespaces(scope);
  const documents: DesktopPluginDocument[] = [];
  for (const item of getArray(value, 'namespaces') ?? []) {
    const document = readDesktopPluginDocument(item);
    if (document !== undefined && names.includes(document.id)) { documents.push(document); }
  }
  return { writable: getBoolean(value, 'writable') === true, documents: documents };
}

function desktopPluginConfigurationNamespaces(scope: string): string[] {
  switch (scope) {
    case WEB_PLUGIN_SETTINGS: return [WEB_SETTINGS, WEB_API_SETTINGS, WEB_LEGACY_SETTINGS];
    case AGENT_LOOP_SETTINGS: return [AGENT_LOOP_SETTINGS];
    case SHELL_PLUGIN_SETTINGS: return [BASH_SETTINGS, PWSH_SETTINGS];
    case WORKTREE_SETTINGS: return [WORKTREE_SETTINGS];
    case SUBAGENT_SETTINGS: return [SUBAGENT_SETTINGS, SUBAGENT_MODEL_SETTINGS];
    case '': return [WEB_SETTINGS, WEB_API_SETTINGS, WEB_LEGACY_SETTINGS, AGENT_LOOP_SETTINGS, BASH_SETTINGS, PWSH_SETTINGS,
      SUBAGENT_SETTINGS, SUBAGENT_MODEL_SETTINGS];
    default: return [];
  }
}

export function desktopPluginConfigurationScopes(documents: DesktopPluginDocument[]): string[] {
  const names = new Set<string>(documents.map((document: DesktopPluginDocument): string => document.id));
  const scopes: string[] = [];
  if (names.has(SUBAGENT_SETTINGS) || names.has(SUBAGENT_MODEL_SETTINGS)) { scopes.push(SUBAGENT_SETTINGS); }
  if (names.has(WEB_SETTINGS)) { scopes.push(WEB_PLUGIN_SETTINGS); }
  if (names.has(AGENT_LOOP_SETTINGS)) { scopes.push(AGENT_LOOP_SETTINGS); }
  if (names.has(BASH_SETTINGS) || names.has(PWSH_SETTINGS)) { scopes.push(SHELL_PLUGIN_SETTINGS); }
  return scopes;
}

export function readDesktopPluginDocument(value?: Object): DesktopPluginDocument | undefined {
  const id = getString(value, 'ns') ?? '';
  const revision = getNumber(value, 'revision') ?? -1;
  if (!id || !Number.isSafeInteger(revision) || revision < 0) { return undefined; }
  return { id: id, revision: revision, value: getRecord(value, 'value'),
    base: getRecord(value, 'base'), user: getRecord(value, 'user') };
}

export function desktopPluginField(document: DesktopPluginDocument | undefined, field: string): string {
  const fieldValue = getField(document?.value, field);
  return typeof fieldValue === 'number' || typeof fieldValue === 'string' ? String(fieldValue) : '';
}

export function desktopPluginPathOps(edits: DesktopPluginEdit[], namespace: string): Object[] {
  return edits.filter((edit: DesktopPluginEdit): boolean => edit.namespace === namespace)
    .map((edit: DesktopPluginEdit): Object => {
      const op: Record<string, Object> = { 'op': edit.value === undefined ? 'unset' : 'set', 'path': [edit.field] };
      if (edit.value !== undefined) { op['value'] = edit.value; }
      return op;
    });
}

export function desktopPluginBillingLocked(document: DesktopPluginDocument | undefined, capability: string): boolean {
  return !!(desktopPluginField(document, capability + 'BaseURL') || desktopPluginField(document, capability + 'ApiKeyEnv'));
}

export function desktopPluginInteger(text: string, maximum: number = Number.MAX_SAFE_INTEGER,
  minimum: number = 1): number | undefined {
  const trimmed = text.trim();
  if (!new RegExp('^\\d+$').test(trimmed)) { return undefined; }
  const value = Number(trimmed);
  return Number.isSafeInteger(value) && value >= minimum && value <= maximum ? value : undefined;
}

export function desktopSubagentRouteKey(route: DesktopSubagentRoute): string {
  return JSON.stringify([route.provider, route.model]);
}

export function desktopSubagentAuthorization(document?: DesktopPluginDocument): DesktopSubagentAuthorization {
  const routes: DesktopSubagentRoute[] = [];
  const keys = new Set<string>();
  for (const item of getArray(document?.value, 'allowedModels') ?? []) {
    const route: DesktopSubagentRoute = { provider: getString(item, 'provider') ?? '', model: getString(item, 'model') ?? '' };
    const key = desktopSubagentRouteKey(route);
    if (route.provider && route.model && !keys.has(key)) {
      keys.add(key);
      routes.push(route);
    }
  }
  return { enabled: getBoolean(document?.value, 'enabled') === true, routes: routes, revision: document?.revision ?? -1 };
}

export function sameDesktopSubagentAuthorization(left: DesktopSubagentAuthorization,
  right: DesktopSubagentAuthorization): boolean {
  if (left.enabled !== right.enabled || left.routes.length !== right.routes.length) { return false; }
  const keys = new Set(right.routes.map(desktopSubagentRouteKey));
  return left.routes.every((route: DesktopSubagentRoute): boolean => keys.has(desktopSubagentRouteKey(route)));
}

export function desktopSubagentModelGroups(catalog: ModelOption[], stored: DesktopSubagentRoute[],
  draft: DesktopSubagentRoute[]): DesktopSubagentModelGroup[] {
  const groups = new Map<string, DesktopSubagentModelGroup>();
  const shown = new Set<string>();
  for (const option of catalog) {
    const route: DesktopSubagentRoute = { provider: option.provider, model: option.modelId };
    const key = desktopSubagentRouteKey(route);
    if (shown.has(key)) { continue; }
    shown.add(key);
    let group = groups.get(route.provider);
    if (group === undefined) {
      group = { key: 'provider:' + route.provider, title: option.providerName, models: [] };
      groups.set(route.provider, group);
    }
    group.models.push({ route: route, name: option.modelName, providerName: option.providerName, key: key, available: true });
  }
  const unavailable: DesktopSubagentModel[] = [];
  for (const route of stored.concat(draft)) {
    const key = desktopSubagentRouteKey(route);
    if (shown.has(key)) { continue; }
    shown.add(key);
    unavailable.push({ route: route, name: route.model, providerName: route.provider, key: key, available: false });
  }
  const result = Array.from(groups.values());
  if (unavailable.length > 0) {
    result.push({ key: 'unavailable', title: '已保存但当前不可用', models: unavailable });
  }
  for (const group of result) {
    // ArkUI retains a keyed group's builder until its id changes. Selection is observed separately.
    const identity = [group.key, group.title];
    for (const model of group.models) { identity.push(model.key, model.name); }
    group.key = JSON.stringify(identity);
  }
  return result;
}

function providerTitle(id: string): string {
  if (id === WEB_SEARCH_API) { return 'DeepSeek Search API'; }
  if (id === WEB_SEARCH_LEGACY) { return 'DeepSeek 服务端搜索'; }
  if (id === WEB_FETCH_API) { return 'DeepSeek Fetch API'; }
  if (id === 'http') { return '本机直接获取'; }
  return '';
}

export function desktopWebProviders(value: Object | undefined, capability: string): DesktopWebProvider[] {
  const order = capability === 'search' ? [WEB_SEARCH_API, WEB_SEARCH_LEGACY] : ['http', WEB_FETCH_API];
  const providers: DesktopWebProvider[] = [];
  for (const row of getArray(value, capability) ?? []) {
    const id = getString(row, 'id') ?? '';
    if (id && !providers.some((provider: DesktopWebProvider): boolean => provider.id === id)) {
      providers.push({ id: id, title: providerTitle(id) || getString(row, 'title') || id });
    }
  }
  const ordered: DesktopWebProvider[] = [];
  order.forEach((id: string): void => {
    const provider = providers.find((row: DesktopWebProvider): boolean => row.id === id);
    if (provider !== undefined) { ordered.push(provider); }
  });
  return ordered.concat(providers.filter((provider: DesktopWebProvider): boolean => !order.includes(provider.id)));
}
