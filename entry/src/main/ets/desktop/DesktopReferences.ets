import { fileReferencesEndpoint, projectFileReferences, projectSessionReferences, sessionReferencesEndpoint } from 'appstate';
import { getArray, getString } from 'connection';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';

export function desktopRecallLabels(source?: Object): string[] {
  if (getString(source, 'kind') !== 'session-reference') { return []; }
  const labels = new Set<string>();
  for (const item of getArray(source, 'references') ?? []) {
    const label = getString(item, 'label');
    if (label) { labels.add(label); }
  }
  return Array.from(labels);
}

export interface DesktopReferenceToken {
  start: number;
  end: number;
  query: string;
  quoted: boolean;
}

export interface DesktopReferenceChoice {
  id: string;
  kind: string;
  path: string;
  label: string;
  detail: string;
  mention: string;
}

export interface DesktopReferenceResults {
  rows: DesktopReferenceChoice[];
  error: string;
}

export interface DesktopReferenceCrumb {
  label: string;
  text: string;
}

export function activeDesktopReference(draft: string, caret: number): DesktopReferenceToken | undefined {
  const end = Math.max(0, Math.min(caret, draft.length));
  const before = draft.slice(0, end);
  const quoted = /(?:^|\s)(@"([^"\r\n]*))$/u.exec(before);
  const match = quoted ?? /(?:^|\s)(@([^"\s]*))$/u.exec(before);
  if (match === null || match.index + match[0].length !== before.length ||
    (quoted === null && match[2].startsWith('['))) { return undefined; }
  return { start: end - match[1].length, end: end, query: match[2], quoted: quoted !== null };
}

export function desktopReferenceText(path: string, quoted: boolean, settling: boolean): string {
  if (/[\u0000-\u001f\u007f-\u009f"]/u.test(path)) { return ''; }
  return quoted || /\s/u.test(path) ? '@"' + path + (settling ? '"' : '') : '@' + path;
}

export function desktopSettledReference(row: DesktopReferenceChoice, cwd: string, quoted: boolean): string {
  if (row.kind === 'session') { return row.mention; }
  const suffix = row.kind === 'directory' ? '/' : '';
  const relative = !row.path.startsWith('/') && !row.path.startsWith('~/');
  const absolute = relative && cwd.startsWith('/') ? cwd.replace(/\/+$/u, '') + '/' + row.path : row.path;
  return desktopReferenceText(absolute + suffix, quoted, true) || desktopReferenceText(row.path + suffix, quoted, true);
}

export function desktopReferenceCrumbs(token?: DesktopReferenceToken): DesktopReferenceCrumb[] {
  if (token === undefined) { return []; }
  const slash = token.query.lastIndexOf('/');
  if (slash < 0) { return []; }
  const result: DesktopReferenceCrumb[] = [{ label: '工作区', text: token.quoted ? '@"' : '@' }];
  const parts = token.query.slice(0, slash).split('/').filter((part: string): boolean => part !== '');
  let path = token.query.startsWith('/') ? '/' : '';
  for (const part of parts) {
    path += part + '/';
    const text = desktopReferenceText(path, token.quoted, false);
    if (!text) { return []; }
    result.push({ label: part, text: text });
  }
  return result;
}

export async function desktopReferenceChoices(host: DesktopHostActions, sessionId: string,
  token: DesktopReferenceToken): Promise<DesktopReferenceResults> {
  const parameters: Record<string, Object> = { 'agentId': sessionId, 'query': token.query };
  const fileTask = host.call(fileReferencesEndpoint(), parameters, 6000);
  const sessionTask = token.quoted ? undefined : host.call(sessionReferencesEndpoint(), parameters, 6000);
  const fileReply = await fileTask;
  const sessionReply = await sessionTask;
  const files = fileReply.ok ? projectFileReferences(fileReply.value) : [];
  const sessions = sessionReply?.ok ? projectSessionReferences(sessionReply.value) : [];
  const rows: DesktopReferenceChoice[] = [];
  for (const row of files) {
    const path = row.label;
    if (!desktopReferenceText(path, token.quoted, true)) { continue; }
    const slash = path.lastIndexOf('/');
    rows.push({ id: row.kind + ':' + path, kind: row.kind, path: path, label: path.slice(slash + 1),
      detail: slash < 0 ? '' : path.slice(0, slash), mention: '' });
  }
  for (const row of sessions) {
    rows.push({ id: row.insert, kind: row.kind, path: '', label: row.label || '未命名会话',
      detail: row.detail, mention: row.insert });
  }
  const error = fileReply.ok || sessionReply?.ok ? '' : desktopHostProblem(fileReply);
  return { rows: rows, error: error };
}
