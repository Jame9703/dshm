import { getArray, getBoolean, getString } from 'connection';
import type { SessionListItem } from 'appstate';
import { DesktopArchiveFilter } from './DesktopSessionArchive';
import type { DesktopWorkspaceGroup } from './DesktopSessionOrder';
import { desktopSecretRanges } from './DesktopSecretMask';

export const DESKTOP_WORKSPACE_SEARCH_LIMIT: number = 20;
export const DESKTOP_WORKSPACE_SEARCH_QUERY_LIMIT: number = 500;
const SEARCH_DEBOUNCE_MS: number = 250;
const SERVER_SNIPPET_CODE_POINTS: number = 240;
const MARKS = new RegExp('[\\u0300-\\u036f]', 'gu');
const SPACES = new RegExp('\\s+', 'u');
const WORD = new RegExp('[\\p{L}\\p{N}]', 'u');
const UPPER = new RegExp('\\p{Lu}', 'u');
const LOWER = new RegExp('\\p{Ll}', 'u');
const UNSPACED = new RegExp('[\\p{scx=Han}\\p{scx=Hira}\\p{scx=Kana}\\p{scx=Hang}]', 'u');
const STROKED = new RegExp('[øØłŁđĐðÐıħĦŧŦ]', 'gu');
const STROKED_BASE: Record<string, string> = {
  'ø': 'o', 'Ø': 'O', 'ł': 'l', 'Ł': 'L', 'đ': 'd', 'Đ': 'D', 'ð': 'd', 'Ð': 'D',
  'ı': 'i', 'ħ': 'h', 'Ħ': 'H', 'ŧ': 't', 'Ŧ': 'T'
};
const LEADING_EDGE = new RegExp('^[A-Za-z0-9._:/@%+=\\-]+', 'u');
const TRAILING_EDGE = new RegExp('[A-Za-z0-9._:/@%+=\\-]+$', 'u');
const TOKEN_PUNCTUATION = new RegExp('[_:/@%+=.\\-]', 'u');
const TOKEN_DIGIT = new RegExp('\\d', 'u');
const INCOMPLETE_URI = new RegExp('([a-z][a-z0-9+.-]*://[^\\s/:@?#]{1,256}:)[^\\s/@?#]+$', 'u');

export interface DesktopWorkspaceSearchHit {
  sessionId: string;
  snippet: string;
}

export interface DesktopWorkspaceSearchPage {
  items: DesktopWorkspaceSearchHit[];
  hasMore: boolean;
}

export interface DesktopWorkspaceSearchRow {
  id: string;
  title: string;
  workspace: ResourceStr;
  snippet: string;
  archived: boolean;
  running: boolean;
}

export interface DesktopWorkspaceSearchResult {
  items: DesktopWorkspaceSearchRow[];
  hasMore: boolean;
}

interface SearchName {
  folded: string;
  starts: number[];
}

interface SearchMetadata {
  row: DesktopWorkspaceSearchRow;
  id: string;
  title: SearchName;
  workspace: SearchName;
}

interface RankedSearchRow {
  match: SearchMetadata;
  score: number;
  index: number;
}

/** Keep both the controlled input and its RPC within the upstream wire limit. */
export function desktopWorkspaceSearchQuery(value: string): string {
  const text = value.replaceAll('\0', '');
  if (text.length <= DESKTOP_WORKSPACE_SEARCH_QUERY_LIMIT) { return text; }
  const end = DESKTOP_WORKSPACE_SEARCH_QUERY_LIMIT;
  const lead = text.charCodeAt(end - 1);
  const trail = text.charCodeAt(end);
  const split = lead >= 0xD800 && lead <= 0xDBFF && trail >= 0xDC00 && trail <= 0xDFFF;
  return text.slice(0, split ? end - 1 : end);
}

function maskSecrets(value: string): string {
  let result = '';
  let sourceIndex = 0;
  for (const range of desktopSecretRanges(value)) {
    result += value.slice(sourceIndex, range.start) + range.masked;
    sourceIndex = range.end;
  }
  return result + value.slice(sourceIndex);
}

function possibleClippedToken(token: string): boolean {
  return token.length >= 8 && (token.length >= 20 || TOKEN_DIGIT.test(token) || TOKEN_PUNCTUATION.test(token));
}

/** Redact the snippet before publishing it to a view. The provider can cut credentials across its excerpt boundaries. */
export function desktopWorkspaceSearchSnippet(raw: string): string {
  let end = 0;
  let points = 0;
  for (const character of raw) {
    if (++points > SERVER_SNIPPET_CODE_POINTS) { break; }
    end += character.length;
  }
  const text = maskSecrets(raw.slice(0, end));
  let body = text;
  if (text.startsWith('…')) {
    const prefix = LEADING_EDGE.exec(text.slice(1));
    if (prefix !== null && possibleClippedToken(prefix[0])) {
      body = '…****' + text.slice(1 + prefix[0].length);
    }
  }
  const providerEllipsis = body.endsWith('…');
  const clippedTail = points >= SERVER_SNIPPET_CODE_POINTS || providerEllipsis;
  if (clippedTail) {
    const suffix = providerEllipsis ? '…' : '';
    const shown = providerEllipsis ? body.slice(0, -1) : body;
    const uri = INCOMPLETE_URI.exec(shown);
    if (uri !== null) { return shown.slice(0, uri.index) + uri[1] + '****…'; }
    const tail = TRAILING_EDGE.exec(shown);
    if (tail !== null && possibleClippedToken(tail[0])) {
      return shown.slice(0, tail.index) + '****…';
    }
    return shown + (end < raw.length ? '…' : suffix);
  }
  return body;
}

/** A failed or malformed response must leave the already-visible local matches intact. */
export function desktopWorkspaceSearchPage(value?: Object): DesktopWorkspaceSearchPage | undefined {
  const rows = getArray(value, 'items');
  if (rows === undefined) { return undefined; }
  const items: DesktopWorkspaceSearchHit[] = [];
  const ids = new Set<string>();
  for (const row of rows.slice(0, DESKTOP_WORKSPACE_SEARCH_LIMIT)) {
    const id = getString(row, 'sessionId') ?? '';
    const snippet = getString(row, 'snippet');
    if (!id || snippet === undefined || ids.has(id)) { continue; }
    ids.add(id);
    items.push({ sessionId: id, snippet: desktopWorkspaceSearchSnippet(snippet) });
  }
  return { items: items, hasMore: getBoolean(value, 'hasMore') === true };
}

function stripSearchText(value: string): string {
  return value.normalize('NFKD').replace(MARKS, '').normalize('NFKC')
    .replace(STROKED, (character: string): string => STROKED_BASE[character] ?? character);
}

function searchName(value: string): SearchName {
  const source = stripSearchText(value);
  const starts: number[] = [];
  let index = 0;
  let previous = '';
  for (const character of source) {
    if (!previous || !WORD.test(previous) || UNSPACED.test(character) ||
      (UPPER.test(character) && LOWER.test(previous))) { starts.push(index); }
    index += character.toLowerCase().length;
    previous = character;
  }
  return { folded: source.toLowerCase(), starts: starts };
}

/** Exact key tiers outrank a subsequence, and a subsequence starts at a word boundary. */
function scoreName(term: string, name: SearchName): number {
  const at = name.folded.indexOf(term);
  if (at === 0) { return 4; }
  if (at > 0) { return 3; }
  let best = 0;
  const first = term.charAt(0);
  for (const start of name.starts) {
    if (name.folded.charAt(start) !== first) { continue; }
    let index = start;
    for (const character of term) {
      index = name.folded.indexOf(character, index);
      if (index < 0) { break; }
      index += character.length;
    }
    if (index >= 0) {
      const gaps = index - start - term.length;
      const penalty = gaps * 3 + start * 0.15 + (name.folded.length - index) * 0.02;
      best = Math.max(best, 2 + 0.99 / (1 + penalty));
    }
  }
  return best;
}

function pathLabel(path: string): string {
  const normalized = path.replaceAll('\\', '/');
  const trimmed = normalized.replace(new RegExp('/+$', 'u'), '');
  return trimmed.slice(trimmed.lastIndexOf('/') + 1) || path;
}

/** Prepare metadata once per sidebar snapshot, and merge the bounded host page into local matches. */
export class DesktopWorkspaceSearchIndex {
  private readonly entries: SearchMetadata[] = [];
  private readonly ids = new Map<string, SearchMetadata>();

  constructor(sessions: SessionListItem[], groups: DesktopWorkspaceGroup[], archivedIds: string[],
    archiveFilter: DesktopArchiveFilter) {
    const archived = new Set<string>(archivedIds);
    const labels = new Map<string, ResourceStr>();
    for (const group of groups) {
      const label = typeof group.title === 'string' ? maskSecrets(group.title) : group.title;
      for (const session of group.sessions) {
        if (!labels.has(session.id)) { labels.set(session.id, label); }
      }
    }
    const ordered = sessions.slice().sort((a: SessionListItem, b: SessionListItem): number =>
      b.updatedAt - a.updatedAt || (a.id < b.id ? -1 : Number(a.id !== b.id)));
    for (const session of ordered) {
      const isArchived = archived.has(session.id);
      if (!session.id || this.ids.has(session.id) || session.blank || getString(session.raw, 'origin') === 'subagent' ||
        (archiveFilter !== DesktopArchiveFilter.ALL && isArchived !== (archiveFilter === DesktopArchiveFilter.ONLY))) {
        continue;
      }
      const workspace = labels.get(session.id) ?? maskSecrets(pathLabel(session.cwd));
      const title = maskSecrets(session.title);
      const item: SearchMetadata = {
        row: { id: session.id, title: title, workspace: workspace, snippet: '',
          archived: isArchived, running: session.running },
        id: stripSearchText(session.id).toLowerCase(),
        title: searchName(title),
        workspace: searchName(typeof workspace === 'string' ? workspace : '')
      };
      this.ids.set(session.id, item);
      this.entries.push(item);
    }
  }

  results(query: string, content?: DesktopWorkspaceSearchPage): DesktopWorkspaceSearchResult {
    if (!query.trim()) { return { items: [], hasMore: false }; }
    const terms = stripSearchText(query).trim().toLowerCase().split(SPACES).filter((term: string): boolean => term !== '');
    const snippets = new Map<string, string>();
    for (const hit of content?.items ?? []) {
      if (!snippets.has(hit.sessionId)) { snippets.set(hit.sessionId, hit.snippet); }
    }
    const ranked: RankedSearchRow[] = [];
    this.entries.forEach((match: SearchMetadata, index: number): void => {
      let score = 0;
      for (const term of terms) {
        const best = Math.max(scoreName(term, match.title), scoreName(term, match.workspace),
          match.id.includes(term) ? 1 : 0);
        if (best === 0) { return; }
        score += best;
      }
      ranked.push({ match: match, score: score, index: index });
    });
    ranked.sort((a: RankedSearchRow, b: RankedSearchRow): number => b.score - a.score || a.index - b.index);
    const rows: DesktopWorkspaceSearchRow[] = [];
    const included = new Set<string>();
    let total = 0;
    const include = (entry: SearchMetadata): void => {
      const row = entry.row;
      if (included.has(row.id)) { return; }
      included.add(row.id);
      total++;
      if (rows.length >= DESKTOP_WORKSPACE_SEARCH_LIMIT) { return; }
      rows.push({
        id: row.id, title: row.title, workspace: row.workspace, snippet: snippets.get(row.id) ?? '',
        archived: row.archived, running: row.running
      });
    };
    for (const local of ranked) { include(local.match); }
    for (const hit of content?.items ?? []) {
      const entry = this.ids.get(hit.sessionId);
      if (entry !== undefined) { include(entry); }
    }
    return { items: rows, hasMore: content?.hasMore === true || total > DESKTOP_WORKSPACE_SEARCH_LIMIT };
  }
}

/** A replaced query or unmounted sidebar can never publish its late response. */
export class DesktopWorkspaceSearchRequest {
  private generation: number = 0;
  private timer: number = -1;

  cancel(): void {
    this.generation++;
    clearTimeout(this.timer);
    this.timer = -1;
  }

  start(query: string, load: (query: string) => Promise<Object | undefined>,
    complete: (page?: DesktopWorkspaceSearchPage) => void): void {
    this.cancel();
    if (!query) { return; }
    const generation = this.generation;
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.resolve(generation, query, load, complete);
    }, SEARCH_DEBOUNCE_MS);
  }

  private async resolve(generation: number, query: string, load: (query: string) => Promise<Object | undefined>,
    complete: (page?: DesktopWorkspaceSearchPage) => void): Promise<void> {
    let page: DesktopWorkspaceSearchPage | undefined;
    try {
      const response = await load(query);
      if (generation === this.generation) { page = desktopWorkspaceSearchPage(response); }
    } catch (_) {}
    if (generation === this.generation) { complete(page); }
  }
}
