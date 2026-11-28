import { getArray, getNumber, getString } from 'connection';
import { checkBaseURL, PIAI_SETTINGS_NS } from 'appstate';
import type { PiAiModelRow } from 'appstate';

export type DesktopPiAiProbeProblem = '' | 'needs-endpoint' | 'invalid-endpoint' | 'required-key' | 'blank-key' | 'invalid-key';

export function desktopPiAiProbeProblem(provider: string, baseURL: string, api: string, keyRef: string,
  keyDraft: string): DesktopPiAiProbeProblem {
  const key = keyDraft.trim();
  if (!provider && !baseURL.trim()) { return 'needs-endpoint'; }
  if (baseURL.length > 0 && !checkBaseURL(baseURL).ok) { return 'invalid-endpoint'; }
  if (api === 'google-generative-ai' && !keyRef && !key) { return 'required-key'; }
  if (!keyDraft) { return ''; }
  if (!key) { return 'blank-key'; }
  const first = key.charAt(0);
  const quoted = key.length > 1 && (first === '"' || first === "'" || first === '`') && key.endsWith(first);
  return quoted || !new RegExp('^[\\x21-\\x7E]+$').test(key) || new RegExp('^[A-Z][A-Z0-9_]*=[^=]').test(key) ?
    'invalid-key' : '';
}

export function desktopPiAiProbeRequest(provider: string, baseURL: string, api: string, key: string):
  Record<string, Object> {
  const request: Record<string, Object> = {};
  if (provider) { request['provider'] = provider; }
  if (baseURL) { request['baseURL'] = baseURL; }
  if (api) { request['api'] = api; }
  if (key) { request['apiKey'] = key; }
  return { 'settingsNs': PIAI_SETTINGS_NS, 'request': request };
}

export function readDesktopDiscoveredPiAiModels(value?: Object): PiAiModelRow[] {
  if (value === undefined) { return []; }
  const response: Record<string, Object> = { 'models': value };
  const byId = new Map<string, PiAiModelRow>();
  for (const raw of getArray(response, 'models') ?? []) {
    const id = getString(raw, 'id') ?? '';
    if (!id) { continue; }
    const candidate: PiAiModelRow = { id: id, name: getString(raw, 'name') ?? '',
      contextWindow: getNumber(raw, 'contextWindow') ?? 0, maxTokens: getNumber(raw, 'maxTokens') ?? 0 };
    const modes = getArray(raw, 'inputModalities');
    if (modes !== undefined) {
      const input: string[] = [];
      for (const mode of modes) { if (typeof mode === 'string') { input.push(mode); } }
      candidate.extraFields = { 'input': input };
    }
    byId.set(id, candidate);
  }
  return Array.from(byId.values());
}

export function desktopInitialDiscoveredModelIds(models: PiAiModelRow[], candidates: PiAiModelRow[]): string[] {
  const configured = new Set<string>(models.map((model: PiAiModelRow): string => model.id.trim())
    .filter((id: string): boolean => id.length > 0));
  return candidates.filter((candidate: PiAiModelRow): boolean => configured.size === 0 || configured.has(candidate.id))
    .map((candidate: PiAiModelRow): string => candidate.id);
}

export function desktopAdoptDiscoveredModels(models: PiAiModelRow[], candidates: PiAiModelRow[], selected: string[]):
  PiAiModelRow[] {
  const listed = new Set<string>(candidates.map((candidate: PiAiModelRow): string => candidate.id));
  const picked = new Set<string>(selected);
  const kept = models.filter((model: PiAiModelRow): boolean => !listed.has(model.id.trim()) || picked.has(model.id.trim()));
  const ids = new Set<string>(kept.map((model: PiAiModelRow): string => model.id.trim()));
  const added = candidates.filter((candidate: PiAiModelRow): boolean => picked.has(candidate.id) && !ids.has(candidate.id));
  // The native creation form starts with a placeholder. Replace that starter row when adopting real models.
  if (models.length === 1 && kept.length === 1 && added.length > 0 && kept[0].id === '' && kept[0].name === '' &&
      kept[0].contextWindow === 0 && kept[0].maxTokens === 0 && kept[0].extraFields === undefined) { return added; }
  return [...kept, ...added];
}

function matchesModelTerm(term: string, text: string): boolean {
  let position = 0;
  for (const char of term) {
    const index = text.indexOf(char, position);
    if (index < 0) { return false; }
    position = index + 1;
  }
  return true;
}

export function desktopFilterDiscoveredModels(candidates: PiAiModelRow[], query: string): PiAiModelRow[] {
  const terms = query.trim().toLowerCase().split(new RegExp('\\s+'));
  if (terms.length === 1 && terms[0] === '') { return candidates; }
  return candidates.filter((candidate: PiAiModelRow): boolean => {
    const id = candidate.id.toLowerCase();
    const name = candidate.name.toLowerCase();
    return terms.every((term: string): boolean => matchesModelTerm(term, id) || matchesModelTerm(term, name));
  });
}
