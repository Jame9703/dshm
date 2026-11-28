import { deriveKeyRef } from 'appstate';
import { getArray, getBoolean, getNumber, getRecord, getString, isStringArray, toStringArray } from 'connection';
import { CREDENTIALS_DESCRIBE_ENDPOINT, LLM_LIST_CONFIGURABLE_PROVIDERS_ENDPOINT,
  LLM_LIST_PROVIDERS_ENDPOINT, SETTINGS_DESCRIBE_ENDPOINT } from 'dshcompat';
import { DEEPSEEK_ACCOUNT_ROUTE, DEEPSEEK_API_ROUTE, DEEPSEEK_SETTINGS_NS } from './DesktopDeepSeekProviderModel';
import type { DesktopHostActions } from './DesktopHostActions';

export interface DesktopDeepSeekKeyTarget {
  reference: string;
  helpReference: string;
}

function providerList(value: Object | undefined): Object[] {
  if (value === undefined) { return []; }
  const rows: Record<string, Object> = { 'items': value };
  return getArray(value, 'providers') ?? getArray(value, 'items') ?? getArray(rows, 'items') ?? [];
}

function configuredReference(provider: Object, documents: Map<string, Object>): string {
  const document = documents.get(getString(provider, 'settingsNs') ?? '');
  const path = getArray(provider, 'settingsPath');
  if (path === undefined || !isStringArray(path)) { return ''; }
  let profile = getRecord(document, 'value');
  for (const segment of toStringArray(path)) {
    profile = getRecord(profile, segment);
  }
  return getString(profile, 'apiKeyEnv') ?? '';
}

export async function readDesktopDeepSeekKeyTarget(host: DesktopHostActions): Promise<DesktopDeepSeekKeyTarget | undefined> {
  const replies = await Promise.all([host.call(SETTINGS_DESCRIBE_ENDPOINT), host.call(LLM_LIST_PROVIDERS_ENDPOINT),
    host.call(LLM_LIST_CONFIGURABLE_PROVIDERS_ENDPOINT)]);
  if (replies.some(reply => !reply.ok)) { return undefined; }
  const describe = replies[0].value;
  const registered = providerList(replies[1].value);
  const directory = providerList(replies[2].value);
  const official = directory.find((entry: Object): boolean => getString(entry, 'provider') === DEEPSEEK_API_ROUTE &&
    getString(entry, 'settingsNs') === DEEPSEEK_SETTINGS_NS && getArray(entry, 'settingsPath')?.length === 0);
  if (official === undefined) { return undefined; }

  const documents = new Map<string, Object>();
  for (const document of getArray(describe, 'namespaces') ?? []) {
    documents.set(getString(document, 'ns') ?? '', document);
  }
  const schema = getRecord(documents.get(DEEPSEEK_SETTINGS_NS), 'schema');
  if (getRecord(getRecord(schema, 'refs'), String(getNumber(schema, 'uid') ?? -1)) === undefined) { return undefined; }

  const named = configuredReference(official, documents);
  const target: DesktopDeepSeekKeyTarget = {
    reference: named || deriveKeyRef(DEEPSEEK_API_ROUTE),
    helpReference: named.toLowerCase().includes('oauth') ? '' : named
  };
  const refs = new Set<string>();
  let officialActive = false;
  let accountActive = false;
  for (const row of registered) {
    const id = getString(row, 'id') ?? getString(row, 'provider') ?? '';
    if (!id) { continue; }
    if (id === DEEPSEEK_ACCOUNT_ROUTE) { accountActive = true; continue; }
    if (id === DEEPSEEK_API_ROUTE) { officialActive = true; }
    const entry = directory.find((candidate: Object): boolean => getString(candidate, 'provider') === id);
    const ref = entry === undefined ? '' : configuredReference(entry, documents);
    // A registered keyless provider already makes the explicit setup available.
    if (!ref) { return target; }
    refs.add(ref);
  }

  if (accountActive && (await host.modelCatalog()).catalog?.byProvider.has(DEEPSEEK_ACCOUNT_ROUTE) === true) {
    return target;
  }
  let officialWritable = false;
  const names = Array.from(refs);
  for (let offset = 0; offset < names.length; offset += 64) {
    const batch = names.slice(offset, offset + 64);
    const response = await host.call(CREDENTIALS_DESCRIBE_ENDPOINT, { 'refs': batch });
    if (!response.ok) { return undefined; }
    if (batch.some((ref: string): boolean => getBoolean(getRecord(response.value, ref), 'configured') === true)) {
      return target;
    }
    if (batch.includes(named)) { officialWritable = getBoolean(getRecord(response.value, named), 'writable') === true; }
  }
  return officialActive && officialWritable && getBoolean(describe, 'writable') === true ? target : undefined;
}
