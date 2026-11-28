import { projectPiAiModels } from 'appstate';
import type { PiAiModelRow } from 'appstate';
import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';
import { desktopDeepSeekCatalogPayload } from './DesktopDeepSeekCatalog';

export const DEEPSEEK_API_ROUTE: string = 'deepseek-official';
export const DEEPSEEK_ACCOUNT_ROUTE: string = 'deepseek-account';
export const DEEPSEEK_SETTINGS_NS: string = 'llm-deepseek';

export interface DesktopDeepSeekProviderDocument {
  revision: number;
  writable: boolean;
  credentialRef: string;
  userEndpoint: string;
  inheritedEndpoint: string;
  contextCapacity: number;
  outputCapacity: number;
  inheritedModels: PiAiModelRow[];
  userModels?: PiAiModelRow[];
}

export interface DesktopDeepSeekCredential {
  configured: boolean;
  writable: boolean;
  source: string;
  masked: string;
}

export function readDesktopDeepSeekProvider(describe: Object | undefined): DesktopDeepSeekProviderDocument | undefined {
  const view = getArray(describe, 'namespaces')?.find((entry: Object): boolean =>
    getString(entry, 'ns') === DEEPSEEK_SETTINGS_NS);
  const revision = getNumber(view, 'revision');
  if (revision === undefined) { return undefined; }
  const schema = getRecord(view, 'schema');
  const refs = getRecord(schema, 'refs');
  const root = getRecord(refs, String(getNumber(schema, 'uid') ?? -1));
  const fields = getRecord(root, 'dict');
  const modelSchema = getRecord(refs, String(getNumber(fields, 'models') ?? -1));
  if (getString(modelSchema, 'type') !== 'array') { return undefined; }
  const base = getRecord(view, 'base');
  const user = getRecord(view, 'user');
  const value = getRecord(view, 'value');
  const modelDefault = getField(getRecord(modelSchema, 'meta'), 'default');
  const userModels = getArray(user, 'models');
  const referenceSchema = getRecord(refs, String(getNumber(fields, 'apiKeyEnv') ?? -1));
  return {
    revision: revision, writable: getBoolean(describe, 'writable') === true,
    credentialRef: getString(value, 'apiKeyEnv') || getString(getRecord(referenceSchema, 'meta'), 'default') ||
      'DEEPSEEK_API_KEY',
    userEndpoint: getString(user, 'baseURL') ?? '', inheritedEndpoint: getString(base, 'baseURL') ?? '',
    contextCapacity: getNumber(value, 'defaultContextWindow') ?? 0, outputCapacity: getNumber(value, 'maxTokens') ?? 0,
    inheritedModels: projectPiAiModels(getArray(base, 'models') ?? modelDefault),
    userModels: userModels === undefined ? undefined : projectPiAiModels(userModels)
  };
}

export function readDesktopDeepSeekCredential(value: Object | undefined, ref: string): DesktopDeepSeekCredential | undefined {
  const entry = getRecord(value, ref);
  if (entry === undefined) { return undefined; }
  return { configured: getBoolean(entry, 'configured') === true, writable: getBoolean(entry, 'writable') === true,
    source: getString(entry, 'source') ?? '', masked: getString(entry, 'masked') ?? '' };
}

export function deepSeekCatalogEqual(left: PiAiModelRow[], right: PiAiModelRow[]): boolean {
  return JSON.stringify(desktopDeepSeekCatalogPayload(left)) === JSON.stringify(desktopDeepSeekCatalogPayload(right));
}

export function deepSeekProviderOperations(original: DesktopDeepSeekProviderDocument, endpoint: string, overridden: boolean,
  models: PiAiModelRow[], retryOperations: Record<string, Object>[]): Record<string, Object>[] {
  const operations = retryOperations.slice();
  if (endpoint !== original.userEndpoint) {
    if (endpoint) { operations.push({ 'op': 'set', 'path': ['baseURL'], 'value': endpoint }); }
    else { operations.push({ 'op': 'unset', 'path': ['baseURL'] }); }
  }
  if (!overridden && original.userModels !== undefined) {
    operations.push({ 'op': 'unset', 'path': ['models'] });
  } else if (overridden && (original.userModels === undefined || !deepSeekCatalogEqual(original.userModels, models))) {
    operations.push({ 'op': 'set', 'path': ['models'], 'value': desktopDeepSeekCatalogPayload(models) });
  }
  return operations;
}

const API_KEY_CHARACTERS: RegExp = new RegExp('^[\\x21-\\x7E]+$');
const API_KEY_ASSIGNMENT: RegExp = new RegExp('^[A-Z][A-Z0-9_]*=[^=]');

export function deepSeekApiKeyProblem(draft: string): string {
  if (!draft.length) { return ''; }
  const value = draft.trim();
  if (!value) { return 'blank'; }
  const first = value[0];
  const quoted = value.length > 1 && (first === '"' || first === "'" || first === '`') && value.endsWith(first);
  return quoted || !API_KEY_CHARACTERS.test(value) || API_KEY_ASSIGNMENT.test(value) ? 'format' : '';
}
