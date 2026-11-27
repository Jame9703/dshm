import { getArray, getBoolean, getField, getNumber, getString, isRecord } from 'connection';
import type { DesktopContextMessage } from './DesktopContextMessageModel';

export const DESKTOP_CONTEXT_MAX_CHARS: number = 20000;
const MAX_CATALOG_ENTRIES: number = 200;

export interface DesktopContextTextRun {
  key: string;
  text: string;
  block?: Object;
  unknown: boolean;
}

export interface DesktopContextField {
  name: string;
  value: string;
}

export interface DesktopContextInstruction {
  path: string;
  action: string;
  digest?: string;
}

export interface DesktopContextCatalogEntry {
  name: string;
  description: string;
}

export interface DesktopContextCatalog {
  featured: DesktopContextCatalogEntry[];
  replacement: boolean;
  remaining: number;
}

export interface DesktopContextSnapshotSection {
  name: string;
  text: string;
}

export interface DesktopContextRecall {
  name: string;
  retained: number;
  omitted: number;
  truncated: boolean;
}

export interface DesktopContextBodyData {
  runs: DesktopContextTextRun[];
  fields: DesktopContextField[];
  instructions?: DesktopContextInstruction[];
  catalog?: DesktopContextCatalog;
  sections?: DesktopContextSnapshotSection[];
  recalled?: DesktopContextRecall[];
  relaySender?: string;
}

export function desktopContextNoticeSummary(row: DesktopContextMessage): string {
  return row.form === 'notice' ? getString(row.source, 'summary') ?? '' : '';
}

/** Keep separate unknown blocks at their position among verbatim, adjacent text runs. */
export function desktopContextTextRuns(content: Object[], includeText: boolean): DesktopContextTextRun[] {
  const rows: DesktopContextTextRun[] = [];
  let parts: string[] = [];
  for (let index: number = 0; index < content.length; index++) {
    const block: Object = content[index];
    const text: string | undefined = getString(block, 'type') === 'text' ? getString(block, 'text') : undefined;
    if (text !== undefined) {
      if (includeText && text.length > 0) { parts.push(text); }
      continue;
    }
    if (parts.length > 0) {
      rows.push({ key: 'text-' + index, text: parts.join(''), unknown: false });
      parts = [];
    }
    rows.push({ key: 'block-' + index, text: '', block: block, unknown: true });
  }
  if (parts.length > 0) {
    rows.push({ key: 'text-tail', text: parts.join(''), unknown: false });
  }
  return rows;
}

export function desktopContextJsonText(block: Object | undefined, pretty: boolean): string {
  if (typeof block === 'string' && !pretty) { return String(block); }
  return (pretty ? JSON.stringify(block, null, 2) : JSON.stringify(block)) ?? String(block);
}

function sourceFields(source: Object | undefined): DesktopContextField[] {
  if (source === undefined || !isRecord(source)) { return []; }
  return Object.keys(source).filter((name: string): boolean => name !== 'kind')
    .map((name: string): DesktopContextField => {
      return { name: name, value: desktopContextJsonText(getField(source, name), false) };
    });
}

function instructionsOf(source: Object | undefined): DesktopContextInstruction[] | undefined {
  const list: Object[] | undefined = getArray(source, 'changes');
  if (list === undefined || list.length === 0) { return undefined; }
  const used: Set<string> = new Set<string>();
  const out: DesktopContextInstruction[] = [];
  const baseline: boolean = getBoolean(source, 'baseline') === true;
  for (const entry of list) {
    const path: string | undefined = getString(entry, 'path');
    const action: string | undefined = getString(entry, 'action');
    if (!path || (action !== 'set' && action !== 'replace' && action !== 'remove')) { return undefined; }
    if (used.has(path)) { continue; }
    used.add(path);
    out.push({
      path: path,
      action: action === 'remove' ? 'removed' : baseline ? 'loaded' : action === 'set' ? 'added' : 'updated',
      digest: getString(entry, 'digest')
    });
  }
  return out;
}

function catalogOf(source: Object | undefined): DesktopContextCatalog | undefined {
  const list: Object[] | undefined = getArray(source, 'entries');
  if (list === undefined) { return undefined; }
  const featured: DesktopContextCatalogEntry[] = [];
  for (let index: number = 0; index < list.length; index++) {
    const entry: Object = list[index];
    const name: string | undefined = getString(entry, 'name');
    const description: string | undefined = getString(entry, 'description');
    if (!name || description === undefined) { return undefined; }
    if (index < MAX_CATALOG_ENTRIES) { featured.push({ name: name, description: description }); }
  }
  return { featured: featured, replacement: getBoolean(source, 'update') === true,
    remaining: list.length - featured.length };
}

function snapshotOf(source: Object | undefined): DesktopContextSnapshotSection[] | undefined {
  const list: Object[] | undefined = getArray(source, 'sections');
  if (list === undefined || list.length === 0) { return undefined; }
  const sections: DesktopContextSnapshotSection[] = [];
  for (const entry of list) {
    const name: string | undefined = getString(entry, 'name');
    const text: string | undefined = getString(entry, 'text');
    if (!name || text === undefined) { return undefined; }
    sections.push({ name: name, text: text });
  }
  return sections;
}

function recallsOf(source: Object | undefined): DesktopContextRecall[] | undefined {
  const list: Object[] | undefined = getArray(source, 'references');
  if (list === undefined || list.length === 0) { return undefined; }
  const out: DesktopContextRecall[] = [];
  for (const entry of list) {
    const label: string | undefined = getString(entry, 'label');
    const retained: number | undefined = getNumber(entry, 'retainedMessages');
    const omitted: number | undefined = getNumber(entry, 'omittedMessages');
    const truncated: boolean | undefined = getBoolean(entry, 'truncated');
    if (!label || retained === undefined || omitted === undefined || truncated === undefined) { return undefined; }
    out.push({ name: label, retained: retained, omitted: omitted, truncated: truncated });
  }
  return out;
}

/** A malformed declared form falls back to the same content and source fields as an opaque row. */
export function desktopContextBodyData(row: DesktopContextMessage, forceNotice: boolean): DesktopContextBodyData {
  const body: DesktopContextBodyData = { runs: [], fields: [] };
  if (!forceNotice) {
    switch (row.form) {
      case 'instructions': body.instructions = instructionsOf(row.source); break;
      case 'catalog': body.catalog = catalogOf(row.source); break;
      case 'snapshot': body.sections = snapshotOf(row.source); break;
      case 'recall': body.recalled = recallsOf(row.source); break;
      case 'relay': body.relaySender = getString(row.source, 'senderSessionId') || undefined; break;
      default: break;
    }
    if (body.instructions === undefined && body.catalog === undefined && body.sections === undefined &&
      body.recalled === undefined && body.relaySender === undefined && !desktopContextNoticeSummary(row)) {
      body.fields = sourceFields(row.source);
    }
  }
  if (body.sections === undefined) {
    body.runs = desktopContextTextRuns(row.content, body.catalog === undefined);
  }
  return body;
}
