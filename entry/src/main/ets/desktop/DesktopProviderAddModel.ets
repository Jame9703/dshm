import { deriveKeyRef, modelsPayload, PIAI_SETTINGS_NS, piAiProtocolChoices, piAiReasoningLevelChoices } from 'appstate';
import type { PiAiModelRow } from 'appstate';
import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';

export interface DesktopCatalogCandidate {
  provider: string;
  displayName: string;
  path: string[];
  namespace: string;
  revision: number;
  editable: boolean;
  endpoint: string;
  endpointEnv: string[];
  nativeEnv: string[];
  keyless: boolean;
}

export interface DesktopAddProviderDocument {
  describe?: Object;
  writable: boolean;
  catalogOffered: boolean;
  customOffered: boolean;
  customRevision: number;
  protocols: string[];
  reasoningLevels: string[];
  taken: string[];
  candidates: DesktopCatalogCandidate[];
}

function providerStrings(owner: Object | undefined, name: string): string[] | undefined {
  const list = getArray(owner, name);
  if (list === undefined) { return undefined; }
  const result: string[] = [];
  for (const item of list) {
    if (typeof item !== 'string' || !item.length) { return undefined; }
    result.push(item);
  }
  return result;
}

function providerAt(root: Object | undefined, path: string[]): Object | undefined {
  let value = root;
  for (const part of path) { value = getField(value, part); }
  return value;
}

function providerSchemaAt(namespace: Object, path: string[]): Object | undefined {
  const schema = getRecord(namespace, 'schema');
  const refs = getRecord(schema, 'refs');
  let node = getRecord(refs, String(getNumber(schema, 'uid') ?? -1));
  for (const part of path) {
    const child = getString(node, 'type') === 'dict' ? getNumber(node, 'inner') : getNumber(getRecord(node, 'dict'), part);
    node = getRecord(refs, String(child ?? -1));
  }
  return node;
}

export function desktopAddProviderDocument(describe: Object | undefined, entries: Object[],
  registered: Object[] = []): DesktopAddProviderDocument {
  const namespaces = getArray(describe, 'namespaces') ?? [];
  const piAi = namespaces.find((view: Object): boolean => getString(view, 'ns') === PIAI_SETTINGS_NS);
  const schema = getRecord(piAi, 'schema');
  const refs = getRecord(schema, 'refs');
  const uid = getNumber(schema, 'uid') ?? 0;
  const configuredPiAi = getRecord(getRecord(piAi, 'value'), 'providers');
  const taken = new Set<string>(configuredPiAi === undefined ? [] : Object.keys(configuredPiAi));
  for (const entry of registered) {
    const provider = typeof entry === 'string' ? entry : getString(entry, 'id') ?? getString(entry, 'provider') ?? '';
    if (provider) { taken.add(provider); }
  }
  const candidates: DesktopCatalogCandidate[] = [];
  const seen = new Set<string>();
  let catalogOffered = false;
  for (const entry of entries) {
    const provider = getString(entry, 'provider') ?? '';
    if (!provider || seen.has(provider)) { continue; }
    seen.add(provider);
    taken.add(provider);
    const namespace = getString(entry, 'settingsNs');
    const path = providerStrings(entry, 'settingsPath');
    const view = namespaces.find((item: Object): boolean => getString(item, 'ns') === namespace);
    if (view === undefined || path === undefined || namespace === undefined || provider === 'deepseek-account') { continue; }
    catalogOffered = true;
    if (!path.length || providerAt(getRecord(view, 'value'), path) !== undefined) { continue; }
    const auth = getRecord(entry, 'nativeAuth');
    const endpointEnv = providerStrings(entry, 'baseURLEnv') ?? [];
    const env = providerStrings(auth, 'env') ?? [];
    const revision = getNumber(view, 'revision') ?? -1;
    candidates.push({ provider: provider, displayName: getString(entry, 'displayName') || provider,
      namespace: namespace, revision: revision, path: path,
      editable: revision >= 0 && namespace === PIAI_SETTINGS_NS && path.length === 2 && path[0] === 'providers' &&
        path[1] === provider && provider !== '__proto__' && provider !== 'constructor' && provider !== 'prototype' &&
        getBoolean(entry, 'declared') === false && getString(providerSchemaAt(view, path), 'type') === 'object',
      endpoint: getString(entry, 'defaultBaseURL') ?? '', endpointEnv: endpointEnv,
      nativeEnv: env.filter(ref => !endpointEnv.includes(ref) && !ref.toLowerCase().includes('oauth')),
      keyless: getBoolean(auth, 'oauth') === true && env.length === 0 });
  }
  return { describe: describe, writable: getBoolean(describe, 'writable') === true, catalogOffered: catalogOffered,
    customOffered: piAi !== undefined, customRevision: getNumber(piAi, 'revision') ?? -1,
    protocols: piAiProtocolChoices(refs, uid), reasoningLevels: piAiReasoningLevelChoices(refs, uid),
    taken: Array.from(taken), candidates: candidates };
}

export function desktopCatalogActivationOperations(candidate: DesktopCatalogCandidate, endpoint: string,
  key: string, overrideModels: boolean, models: PiAiModelRow[], retry: Record<string, Object>[]): Record<string, Object>[] {
  const operations = retry.slice();
  if (endpoint) { operations.push({ 'op': 'set', 'path': [...candidate.path, 'baseURL'], 'value': endpoint }); }
  if (key) { operations.push({ 'op': 'set', 'path': [...candidate.path, 'apiKeyEnv'], 'value': deriveKeyRef(candidate.provider) }); }
  if (overrideModels) { operations.push({ 'op': 'set', 'path': [...candidate.path, 'models'], 'value': modelsPayload(models) }); }
  if (operations.length === 0) {
    const profile: Record<string, Object> = {};
    operations.push({ 'op': 'set', 'path': candidate.path, 'value': profile });
  }
  return operations;
}
