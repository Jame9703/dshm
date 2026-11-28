import { deriveKeyRef } from 'appstate';
import { getArray, getBoolean, getField, getNumber, getRecord, getString, isStringArray, RpcResult, toStringArray } from 'connection';
import { CREDENTIALS_DESCRIBE_ENDPOINT, LLM_LIST_CONFIGURABLE_PROVIDERS_ENDPOINT,
  LLM_LIST_PROVIDERS_ENDPOINT, SETTINGS_DESCRIBE_ENDPOINT } from 'dshcompat';
import { DEEPSEEK_ACCOUNT_ROUTE, DEEPSEEK_API_ROUTE, DesktopDeepSeekCredential,
  readDesktopDeepSeekCredential } from './DesktopDeepSeekProviderModel';
import { DesktopHostActions } from './DesktopHostActions';

export interface DesktopModelProviderReadinessRow {
  provider: string;
  displayName: string;
  namespace: string;
  path: string[];
  configured: boolean;
  active: boolean;
  declared: boolean;
  removable: boolean;
  revision: number;
  /** An empty string means the effective profile does not name a credential. */
  credentialRef: string;
  credential?: DesktopDeepSeekCredential;
  nativeAuthEnv: string[];
  accountAvailable: boolean;
  error: string;
}

export interface DesktopModelProviderReadiness {
  describe: Object | undefined;
  directory: Object[];
  registered: Object[];
  rows: DesktopModelProviderReadinessRow[];
  anyUsable: boolean;
  writable: boolean;
  credentialReadFailed: boolean;
}

export interface DesktopModelProviderAccess {
  read: () => Promise<DesktopModelProviderReadiness | undefined>;
  observe: (listener: () => void) => () => void;
}

function providerList(value: Object | undefined): Object[] {
  if (value === undefined) { return []; }
  const wrapped: Record<string, Object> = { 'items': value };
  return getArray(value, 'providers') ?? getArray(value, 'items') ?? getArray(wrapped, 'items') ?? [];
}

function providerProfile(document: Object | undefined, path: string[], layer: string): Object | undefined {
  let value = getField(document, layer);
  for (const part of path) {
    if (value !== undefined && Array.isArray(value)) {
      const wrapped: Record<string, Object> = { 'items': value };
      value = getArray(wrapped, 'items')?.[Number(part)];
    } else {
      value = getField(value, part);
    }
  }
  return value;
}

function providerOrder(provider: string): number {
  if (provider === DEEPSEEK_ACCOUNT_ROUTE) { return 0; }
  return provider === DEEPSEEK_API_ROUTE ? 1 : 2;
}

function providerUsable(row: DesktopModelProviderReadinessRow): boolean {
  if (!row.active) { return false; }
  if (row.provider === DEEPSEEK_ACCOUNT_ROUTE) { return row.accountAvailable; }
  return row.credentialRef === '' || row.credential?.configured === true;
}

export function desktopProviderNeedsSetup(row: DesktopModelProviderReadinessRow, anyUsable: boolean): boolean {
  return row.configured && !anyUsable && row.provider !== DEEPSEEK_ACCOUNT_ROUTE && row.path.length === 0 &&
    row.credential?.configured !== true;
}

/** Read the Models page's shared directory facts only when a caller needs them. */
export async function readDesktopModelProviderReadiness(
  host: DesktopHostActions
): Promise<DesktopModelProviderReadiness | undefined> {
  const replies = await Promise.all([host.call(SETTINGS_DESCRIBE_ENDPOINT), host.call(LLM_LIST_PROVIDERS_ENDPOINT),
    host.call(LLM_LIST_CONFIGURABLE_PROVIDERS_ENDPOINT)]);
  if (replies.some((reply: RpcResult): boolean => !reply.ok)) { return undefined; }
  const describe = replies[0].value;
  const registered = providerList(replies[1].value);
  const directory = providerList(replies[2].value);
  const documents = new Map<string, Object>();
  for (const document of getArray(describe, 'namespaces') ?? []) {
    const name = getString(document, 'ns') ?? '';
    if (name) { documents.set(name, document); }
  }
  const active = new Map<string, Object>();
  for (const entry of registered) {
    const id = getString(entry, 'id') ?? getString(entry, 'provider') ?? '';
    if (id) { active.set(id, entry); }
  }
  const rows: DesktopModelProviderReadinessRow[] = [];
  const joined = new Set<string>();
  for (const entry of directory) {
    const provider = getString(entry, 'provider') ?? '';
    const rawPath = getArray(entry, 'settingsPath');
    if (!provider || joined.has(provider) || rawPath === undefined || !isStringArray(rawPath)) { continue; }
    const namespace = getString(entry, 'settingsNs') ?? '';
    const path = toStringArray(rawPath);
    const document = documents.get(namespace);
    const profile = providerProfile(document, path, 'value');
    const credentialRef = provider === DEEPSEEK_ACCOUNT_ROUTE ? '' : getString(profile, 'apiKeyEnv') ?? '';
    const env = getArray(getRecord(entry, 'nativeAuth'), 'env');
    rows.push({
      provider: provider, displayName: getString(entry, 'displayName') || provider, namespace: namespace, path: path,
      configured: document !== undefined && (path.length === 0 || profile !== undefined), active: active.has(provider),
      declared: getBoolean(entry, 'declared') === true, revision: getNumber(document, 'revision') ?? -1,
      removable: path.length > 0 && providerProfile(document, path, 'user') !== undefined &&
        providerProfile(document, path, 'base') === undefined,
      credentialRef: credentialRef, nativeAuthEnv: env !== undefined && isStringArray(env) ? toStringArray(env) : [],
      accountAvailable: false, error: getString(entry, 'error') ?? ''
    });
    joined.add(provider);
  }
  for (const provider of active.keys()) {
    if (joined.has(provider)) { continue; }
    rows.push({
      provider: provider, displayName: getString(active.get(provider), 'name') || provider, namespace: '', path: [],
      configured: false, active: true, declared: false, removable: false, revision: -1,
      credentialRef: '', nativeAuthEnv: [], accountAvailable: false, error: ''
    });
  }
  rows.sort((a: DesktopModelProviderReadinessRow, b: DesktopModelProviderReadinessRow): number =>
    providerOrder(a.provider) - providerOrder(b.provider));

  const account = rows.find((row: DesktopModelProviderReadinessRow): boolean => row.provider === DEEPSEEK_ACCOUNT_ROUTE);
  if (account !== undefined) {
    const catalog = await host.modelCatalog();
    account.accountAvailable = (catalog.catalog?.byProvider.get(DEEPSEEK_ACCOUNT_ROUTE)?.size ?? 0) > 0;
  }
  const refs = new Set<string>();
  for (const row of rows) {
    if (row.provider === DEEPSEEK_ACCOUNT_ROUTE) { continue; }
    refs.add(row.credentialRef || deriveKeyRef(row.provider));
    if (!row.credentialRef) {
      for (const ref of row.nativeAuthEnv) { refs.add(ref); }
    }
  }
  let credentialReadFailed = false;
  const credentials = new Map<string, DesktopDeepSeekCredential>();
  const names = Array.from(refs);
  for (let offset = 0; offset < names.length; offset += 64) {
    const batch = names.slice(offset, offset + 64);
    const result = await host.call(CREDENTIALS_DESCRIBE_ENDPOINT, { 'refs': batch });
    if (!result.ok) {
      credentialReadFailed = true;
      break;
    }
    for (const ref of batch) {
      const credential = readDesktopDeepSeekCredential(result.value, ref);
      if (credential !== undefined) { credentials.set(ref, credential); }
    }
  }
  for (const row of rows) {
    if (row.credentialRef) { row.credential = credentials.get(row.credentialRef); }
  }
  return {
    describe: describe, directory: directory, registered: registered,
    rows: rows.filter((row: DesktopModelProviderReadinessRow): boolean =>
      row.provider !== DEEPSEEK_ACCOUNT_ROUTE || row.accountAvailable),
    anyUsable: rows.some(providerUsable),
    writable: getBoolean(describe, 'writable') === true, credentialReadFailed: credentialReadFailed
  };
}
