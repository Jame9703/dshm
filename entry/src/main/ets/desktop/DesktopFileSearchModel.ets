import { getArray, getBoolean, getField, getString, isRecord, parseJson, stringifyJson } from 'connection';

export const DESKTOP_FILE_SEARCH_PREFERENCES_KEY: string = 'dsh.sidebar-files.workspace-search.v1';

export interface DesktopFileSearchRule {
  path: string;
  enabled: boolean;
}

export interface DesktopFileSearchPreferences {
  rules: DesktopFileSearchRule[];
  showHidden: boolean;
  respectGitignore: boolean;
}

export interface DesktopFileSearchPreferencePatch {
  rules?: DesktopFileSearchRule[];
  showHidden?: boolean;
  respectGitignore?: boolean;
}

export type DesktopFileSearchRuleInvalidReason = 'empty' | 'nul' | 'absolute' | 'parent' | 'glob';

export interface DesktopFileSearchRulePath {
  kind: 'ok' | 'invalid';
  path: string;
  reason?: DesktopFileSearchRuleInvalidReason;
}

export interface DesktopFileSearchRuleResult {
  kind: 'ok' | 'invalid';
  rules: DesktopFileSearchRule[];
  reason?: DesktopFileSearchRuleInvalidReason;
}

const DEFAULT_EXCLUDED_PATHS: string[] = [
  '.git', '.hg', '.next', '.pnpm-store', '.svn', '.turbo', '.yarn', 'build', 'coverage', 'dist', 'node_modules',
  '.DS_Store', '.Spotlight-V100', '.Trashes', '.fseventsd', 'Thumbs.db', 'desktop.ini', '$RECYCLE.BIN',
  'System Volume Information'
];

export function normalizeDesktopFileSearchRulePath(input: string): DesktopFileSearchRulePath {
  const slashed = input.trim().replace(/\\/g, '/');
  if (slashed === '') { return { kind: 'invalid', path: '', reason: 'empty' }; }
  if (slashed.includes('\0')) { return { kind: 'invalid', path: '', reason: 'nul' }; }
  const relative = slashed.replace(/\/{2,}/g, '/').replace(/^(?:\s|\.\/)+/, '');
  if (slashed.startsWith('/') || /^(?:\/|~|[A-Za-z]:)/.test(relative)) {
    return { kind: 'invalid', path: '', reason: 'absolute' };
  }
  let end = relative.length;
  while (end > 0 && /[\s/]/.test(relative.charAt(end - 1))) { end--; }
  const path = relative.slice(0, end);
  if (/[*?[\]{}!]/.test(path)) { return { kind: 'invalid', path: '', reason: 'glob' }; }
  if (path === '') { return { kind: 'invalid', path: '', reason: 'empty' }; }
  if (path.split('/').some((segment: string): boolean => segment === '.' || segment === '..')) {
    return { kind: 'invalid', path: '', reason: 'parent' };
  }
  return { kind: 'ok', path: path };
}

export function defaultDesktopFileSearchRules(): DesktopFileSearchRule[] {
  return DEFAULT_EXCLUDED_PATHS.map((path: string): DesktopFileSearchRule => ({ path: path, enabled: true }));
}

export function defaultDesktopFileSearchPreferences(): DesktopFileSearchPreferences {
  return { rules: defaultDesktopFileSearchRules(), showHidden: false, respectGitignore: true };
}

export function addDesktopFileSearchRule(rules: DesktopFileSearchRule[], input: string): DesktopFileSearchRuleResult {
  const normalized = normalizeDesktopFileSearchRulePath(input);
  if (normalized.kind === 'invalid') { return { kind: 'invalid', rules: rules, reason: normalized.reason }; }
  const path = normalized.path;
  const added: DesktopFileSearchRule = { path: path, enabled: true };
  return { kind: 'ok', rules: [added, ...rules.filter((rule: DesktopFileSearchRule): boolean => rule.path !== path)] };
}

export function removeDesktopFileSearchRule(rules: DesktopFileSearchRule[], path: string): DesktopFileSearchRule[] {
  return rules.filter((rule: DesktopFileSearchRule): boolean => rule.path !== path);
}

export function setDesktopFileSearchRuleEnabled(rules: DesktopFileSearchRule[], path: string,
  enabled: boolean): DesktopFileSearchRule[] {
  return rules.map((rule: DesktopFileSearchRule): DesktopFileSearchRule =>
    rule.path === path && rule.enabled !== enabled ? { path: path, enabled: enabled } : rule);
}

export function enabledDesktopFileSearchPaths(rules: DesktopFileSearchRule[]): string[] {
  return rules.filter((rule: DesktopFileSearchRule): boolean => rule.enabled)
    .map((rule: DesktopFileSearchRule): string => rule.path);
}

export function isDefaultDesktopFileSearchRules(rules: DesktopFileSearchRule[]): boolean {
  return rules.length === DEFAULT_EXCLUDED_PATHS.length &&
    rules.every((rule: DesktopFileSearchRule, index: number): boolean =>
      rule.path === DEFAULT_EXCLUDED_PATHS[index] && rule.enabled);
}

function readRules(rules: Object[]): DesktopFileSearchRule[] {
  const paths = new Set<string>();
  const parsed: DesktopFileSearchRule[] = [];
  for (const rule of rules) {
    const path = getString(rule, 'path');
    const enabled = getBoolean(rule, 'enabled');
    if (path === undefined || enabled === undefined) { continue; }
    const normalized = normalizeDesktopFileSearchRulePath(path);
    if (normalized.kind === 'invalid' || paths.has(normalized.path)) { continue; }
    paths.add(normalized.path);
    parsed.push({ path: normalized.path, enabled: enabled });
  }
  return parsed;
}

export function readDesktopFileSearchPreferences(value?: Object): DesktopFileSearchPreferences {
  if (value === undefined || !isRecord(value)) { return defaultDesktopFileSearchPreferences(); }
  const fields = Object.keys(value);
  const rules = fields.includes('rules') ? getArray(value, 'rules') : undefined;
  return {
    rules: rules === undefined ? defaultDesktopFileSearchRules() : readRules(rules),
    showHidden: fields.includes('showHidden') && getBoolean(value, 'showHidden') === true,
    respectGitignore: !fields.includes('respectGitignore') || getBoolean(value, 'respectGitignore') !== false
  };
}

export function decodeDesktopFileSearchPreferences(text: string): DesktopFileSearchPreferences {
  return readDesktopFileSearchPreferences(parseJson(text));
}

/** Store only user changes so new defaults can reach fields the user has left alone. */
export function encodeDesktopFileSearchPreferences(value: DesktopFileSearchPreferences): string {
  const changed: DesktopFileSearchPreferencePatch = {};
  if (!isDefaultDesktopFileSearchRules(value.rules)) {
    changed.rules = value.rules.map((rule: DesktopFileSearchRule): DesktopFileSearchRule =>
      ({ path: rule.path, enabled: rule.enabled }));
  }
  if (value.showHidden) { changed.showHidden = true; }
  if (!value.respectGitignore) { changed.respectGitignore = false; }
  return Object.keys(changed).length > 0 ? JSON.stringify(changed) : '';
}

export function desktopFileSearchWorkspaceKey(cwd: string): string {
  const trimmed = cwd.replace(/[/\\]+$/, '');
  if (trimmed === '') { return cwd.slice(0, 1); }
  if (/^[A-Za-z]:$/.test(trimmed) && cwd.length > trimmed.length) { return cwd.slice(0, 3); }
  return trimmed;
}

export function decodeDesktopFileSearchPreferenceBook(text: string): Map<string, Object> {
  const book = new Map<string, Object>();
  const raw = parseJson(text);
  if (raw === undefined || !isRecord(raw)) { return book; }
  for (const key of Object.keys(raw)) {
    const entry = getField(raw, key);
    if (entry !== undefined) { book.set(key, entry); }
  }
  return book;
}

/** Retain other workspaces' raw entries. Quoting each map key also preserves special names such as "__proto__". */
export function encodeDesktopFileSearchPreferenceBook(book: Map<string, Object>): string {
  const entries: string[] = [];
  book.forEach((entry: Object, key: string): void => {
    const json = stringifyJson(entry);
    if (json !== undefined) { entries.push(JSON.stringify(key) + ':' + json); }
  });
  return '{' + entries.join(',') + '}';
}
