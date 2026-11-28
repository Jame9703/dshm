import { changedScalarFields, deriveKeyRef, modelsDiffer, modelsPayload, PIAI_SETTINGS_NS, piAiSchemaDefaultModels,
  projectPiAiProviders, scalarFieldValue } from 'appstate';
import type { PiAiProviderView } from 'appstate';
import { getArray, getBoolean, getField, getNumber, getRecord, getString } from 'connection';
import type { DesktopModelProviderReadiness, DesktopModelProviderReadinessRow } from './DesktopModelProviderReadiness';
import { isDesktopPiAiCatalogRoute } from './DesktopPiAiInheritance';

export interface DesktopPiAiExistingProfile {
  row: DesktopModelProviderReadinessRow;
  original: PiAiProviderView;
  user?: Object;
  catalog: boolean;
  hasNativeAuth: boolean;
  keyless: boolean;
  endpointPlaceholder: string;
  namePlaceholder: string;
}

export function desktopPiAiExistingProfile(facts: DesktopModelProviderReadiness,
  row: DesktopModelProviderReadinessRow): DesktopPiAiExistingProfile | undefined {
  if (row.namespace !== PIAI_SETTINGS_NS || row.path.length !== 2 || row.path[0] !== 'providers' ||
      row.path[1] !== row.provider || row.revision < 0) { return undefined; }
  const ns = getArray(facts.describe, 'namespaces')?.find((entry: Object): boolean => getString(entry, 'ns') === row.namespace);
  const schema = getRecord(ns, 'schema');
  const baseProviders = getRecord(getRecord(ns, 'base'), 'providers');
  const userProviders = getRecord(getRecord(ns, 'user'), 'providers');
  const providers = getRecord(getRecord(ns, 'value'), 'providers');
  const original = projectPiAiProviders(providers, {
    baseProviders: baseProviders, userProviders: userProviders,
    schemaDefaultModels: piAiSchemaDefaultModels(getRecord(schema, 'refs'), getNumber(schema, 'uid') ?? 0)
  }).find((candidate: PiAiProviderView): boolean => candidate.route === row.provider);
  if (original === undefined) { return undefined; }
  const entry = facts.directory.find((candidate: Object): boolean => getString(candidate, 'provider') === row.provider);
  const nativeAuth = getRecord(entry, 'nativeAuth');
  const inherited = getRecord(baseProviders, row.provider);
  return {
    row: row, original: original, user: getRecord(userProviders, row.provider),
    catalog: isDesktopPiAiCatalogRoute(facts.directory, row.provider), hasNativeAuth: nativeAuth !== undefined,
    keyless: row.credentialRef === '' && getBoolean(nativeAuth, 'oauth') === true && getArray(nativeAuth, 'env')?.length === 0,
    endpointPlaceholder: getString(inherited, 'baseURL') || getString(entry, 'defaultBaseURL') || '',
    namePlaceholder: getString(inherited, 'displayName') || row.provider
  };
}

export function desktopPiAiEditOperations(existing: DesktopPiAiExistingProfile, draft: PiAiProviderView,
  modelsOverridden: boolean, storesKey: boolean, clearsKey: boolean, retry: Record<string, Object>[]): Record<string, Object>[] {
  const operations = retry.slice();
  const row = existing.row;
  for (const field of changedScalarFields(existing.original, draft)) {
    if (field !== 'baseURL' && !row.declared) { continue; }
    const value = scalarFieldValue(draft, field);
    if (value !== '') { operations.push({ 'op': 'set', 'path': [...row.path, field], 'value': value }); }
    else if (getField(existing.user, field) !== undefined) { operations.push({ 'op': 'unset', 'path': [...row.path, field] }); }
  }
  const storedOverride = existing.original.modelLayer?.userOverride === true;
  if (!modelsOverridden && storedOverride) {
    operations.push({ 'op': 'unset', 'path': [...row.path, 'models'] });
  } else if (modelsOverridden && (!storedOverride || modelsDiffer(existing.original.models, draft.models))) {
    operations.push({ 'op': 'set', 'path': [...row.path, 'models'], 'value': modelsPayload(draft.models) });
  }
  const ref = deriveKeyRef(row.provider);
  if (clearsKey && existing.hasNativeAuth && row.credentialRef === ref && getField(existing.user, 'apiKeyEnv') !== undefined) {
    operations.push({ 'op': 'unset', 'path': [...row.path, 'apiKeyEnv'] });
  } else if (storesKey && !row.credentialRef) {
    operations.push({ 'op': 'set', 'path': [...row.path, 'apiKeyEnv'], 'value': ref });
  }
  return operations;
}
