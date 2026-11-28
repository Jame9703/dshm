import { getRecord, getString } from 'connection';
import { desktopLocalizedText } from './DesktopHostActions';

export const DESKTOP_MARKET_PAGE_SIZE: number = 50;

export interface DesktopMarketDeclaration {
  id: string;
  title: string;
  direction: 'asc' | 'desc';
}

export interface DesktopMarketDeclarations {
  categories: DesktopMarketDeclaration[];
  labels: DesktopMarketDeclaration[];
  sortKeys: DesktopMarketDeclaration[];
}

export interface DesktopMarketSort {
  kind: 'index' | 'relevance' | 'published' | 'key';
  id?: string;
  direction?: 'asc' | 'desc';
}

export interface DesktopMarketQuery {
  text: string;
  category: string;
  labels: string[];
  sort: DesktopMarketSort;
}

export function emptyDesktopMarketQuery(): DesktopMarketQuery {
  return { text: '', category: '', labels: [], sort: { kind: 'index' } };
}

function declarations(group: Object | undefined, locale: string): DesktopMarketDeclaration[] {
  const values: DesktopMarketDeclaration[] = [];
  if (group === undefined) { return values; }
  for (const id of Object.keys(group)) {
    const declaration = getRecord(group, id);
    if (!id || declaration === undefined) { continue; }
    values.push({ id: id, title: desktopLocalizedText(declaration, 'title', locale) || id,
      direction: getString(declaration, 'order') === 'asc' ? 'asc' : 'desc' });
  }
  return values.sort((left: DesktopMarketDeclaration, right: DesktopMarketDeclaration): number =>
    left.title.localeCompare(right.title, locale || undefined) || (left.id < right.id ? -1 : 1));
}

export function readDesktopMarketDeclarations(metadata?: Object, locale: string = ''): DesktopMarketDeclarations {
  return {
    categories: declarations(getRecord(metadata, 'categories'), locale),
    labels: declarations(getRecord(metadata, 'labels'), locale),
    sortKeys: declarations(getRecord(metadata, 'sortKeys'), locale)
  };
}

export function desktopMarketQueryWithText(query: DesktopMarketQuery, text: string): DesktopMarketQuery {
  let sort = query.sort;
  if (!text.trim() && sort.kind === 'relevance') { sort = { kind: 'index' }; }
  else if (text.trim() && !query.text.trim() && sort.kind === 'index') { sort = { kind: 'relevance' }; }
  return { text: text, category: query.category, labels: query.labels, sort: sort };
}

export function desktopMarketDeclaredQuery(query: DesktopMarketQuery,
  metadata: DesktopMarketDeclarations): DesktopMarketQuery {
  const category = metadata.categories.some((row: DesktopMarketDeclaration): boolean => row.id === query.category) ?
    query.category : '';
  const available = new Set<string>(metadata.labels.map((row: DesktopMarketDeclaration): string => row.id));
  const labels = query.labels.filter((id: string): boolean => available.has(id));
  const sort: DesktopMarketSort = query.sort.kind === 'key' &&
    !metadata.sortKeys.some((row: DesktopMarketDeclaration): boolean => row.id === query.sort.id) ?
    { kind: 'index' } : query.sort;
  if (category === query.category && labels.length === query.labels.length && sort === query.sort) { return query; }
  return { text: query.text, category: category, labels: labels, sort: sort };
}

export function desktopMarketQueryPayload(query: DesktopMarketQuery, offset: number, limit: number,
  fetchedAt: number, refresh: boolean): Record<string, Object> {
  const sort: Record<string, Object> = { 'kind': query.sort.kind };
  if (query.sort.id) { sort['id'] = query.sort.id; }
  if (query.sort.direction) { sort['direction'] = query.sort.direction; }
  const payload: Record<string, Object> = { 'sort': sort, 'offset': offset, 'limit': limit };
  if (query.text.trim()) { payload['text'] = query.text; }
  if (query.category) { payload['category'] = query.category; }
  if (query.labels.length > 0) { payload['labels'] = query.labels; }
  if (offset > 0 && fetchedAt > 0) { payload['fetchedAt'] = fetchedAt; }
  if (refresh) { payload['refresh'] = true; }
  return payload;
}

export function desktopMarketUnfiltered(query: DesktopMarketQuery): boolean {
  return !query.text.trim() && !query.category && query.labels.length === 0;
}
