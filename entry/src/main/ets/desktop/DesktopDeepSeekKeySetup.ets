import { deriveKeyRef } from 'appstate';
import { getArray, getNumber, getRecord, getString } from 'connection';
import { DEEPSEEK_API_ROUTE, DEEPSEEK_SETTINGS_NS } from './DesktopDeepSeekProviderModel';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopModelProviderReadinessRow, readDesktopModelProviderReadiness } from './DesktopModelProviderReadiness';

export interface DesktopDeepSeekKeyTarget {
  reference: string;
  helpReference: string;
}

export async function readDesktopDeepSeekKeyTarget(host: DesktopHostActions): Promise<DesktopDeepSeekKeyTarget | undefined> {
  const readiness = await readDesktopModelProviderReadiness(host);
  if (readiness === undefined) { return undefined; }
  const official = readiness.rows.find((row: DesktopModelProviderReadinessRow): boolean =>
    row.provider === DEEPSEEK_API_ROUTE && row.namespace === DEEPSEEK_SETTINGS_NS && row.path.length === 0);
  if (official === undefined || !official.configured) { return undefined; }
  const document = getArray(readiness.describe, 'namespaces')?.find((value: Object): boolean =>
    getString(value, 'ns') === DEEPSEEK_SETTINGS_NS);
  const schema = getRecord(document, 'schema');
  if (getRecord(getRecord(schema, 'refs'), String(getNumber(schema, 'uid') ?? -1)) === undefined) { return undefined; }

  if (!readiness.anyUsable && (!official.active || readiness.credentialReadFailed ||
    !readiness.writable || official.credential?.writable !== true)) { return undefined; }
  const named = official.credentialRef;
  return {
    reference: named || deriveKeyRef(DEEPSEEK_API_ROUTE),
    helpReference: named.toLowerCase().includes('oauth') ? '' : named
  };
}
