import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';

export const WEB_SETTINGS: string = 'web';
export const WEB_API_SETTINGS: string = 'web-deepseek-api';
export const WEB_LEGACY_SETTINGS: string = 'web-search-deepseek';
export const AGENT_LOOP_SETTINGS: string = 'agent-loop';
export const BASH_SETTINGS: string = 'bash-sandbox';
export const PWSH_SETTINGS: string = 'pwsh-sandbox';
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

export function readDesktopPluginConfiguration(value?: Object): DesktopPluginConfiguration {
  const names = [WEB_SETTINGS, WEB_API_SETTINGS, WEB_LEGACY_SETTINGS, AGENT_LOOP_SETTINGS, BASH_SETTINGS, PWSH_SETTINGS];
  const documents: DesktopPluginDocument[] = [];
  for (const item of getArray(value, 'namespaces') ?? []) {
    const document = readDesktopPluginDocument(item);
    if (document !== undefined && names.includes(document.id)) { documents.push(document); }
  }
  return { writable: getBoolean(value, 'writable') === true, documents: documents };
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

export function desktopPluginPositiveInteger(text: string, maximum: number = Number.MAX_SAFE_INTEGER): number | undefined {
  const trimmed = text.trim();
  if (!new RegExp('^\\d+$').test(trimmed)) { return undefined; }
  const value = Number(trimmed);
  return Number.isSafeInteger(value) && value >= 1 && value <= maximum ? value : undefined;
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
