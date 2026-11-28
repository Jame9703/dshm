import { util } from '@kit.ArkTS';
import { getBoolean, getField, getNumber, getRecord, getString } from 'connection';
import type { DesktopHostActions } from './DesktopHostActions';

export const DESKTOP_HTML_PACKAGE_BYTES: number = 32 * 1024 * 1024;
export const DESKTOP_HTML_ASSET_BYTES: number = 4 * 1024 * 1024;
export const DESKTOP_HTML_ASSET_COUNT: number = 64;

export interface DesktopHtmlFile {
  path: string;
  version: string;
  bytes: number;
  content: string;
}

export function desktopIsHtmlFile(name: string): boolean { return /\.html?$/i.test(name); }

export async function readDesktopHtmlFile(host: DesktopHostActions, sessionId: string, path: string,
  limit: number): Promise<DesktopHtmlFile | undefined> {
  const response = await host.readWorkspaceBytes(sessionId, path, limit);
  const metadata = response.ok ? getRecord(response.value, 'metadata') : undefined;
  const attachment = response.ok ? getField(response.value, 'data') : undefined;
  const absolute = getString(metadata, 'absolutePath');
  const version = getString(metadata, 'version');
  const length = getNumber(metadata, 'bytes');
  if (!(attachment instanceof ArrayBuffer) || absolute === undefined || version === undefined ||
    getBoolean(metadata, 'eof') !== true || getNumber(metadata, 'offset') !== 0 ||
    attachment.byteLength > limit || (length !== undefined && length !== attachment.byteLength)) { return undefined; }
  const content = await new util.Base64Helper().encodeToString(new Uint8Array(attachment));
  return { path: absolute, version: version, bytes: attachment.byteLength, content: content };
}

/** Only workspace paths can be considered for automatic dependencies. The Host must confirm identity before and after reading. */
export function desktopHtmlDependencyPath(workspaceRoot: string, documentPath: string, reference: string): string {
  const root = canonicalPath(workspaceRoot);
  const document = canonicalPath(documentPath);
  if (!inside(root, document)) { return ''; }
  try {
    const suffix = reference.search(/[?#]/);
    const relative = decodeURIComponent(suffix < 0 ? reference : reference.slice(0, suffix));
    if (!relative || /^(?:[a-z][a-z\d+.-]*:|\/)/i.test(relative) || /[\\\x00-\x1f\x7f]/.test(relative)) { return ''; }
    const path = canonicalPath(document.slice(0, document.lastIndexOf('/') + 1) + relative);
    return inside(root, path) ? path : '';
  } catch (_) { return ''; }
}

export function desktopHtmlCanonicalDependency(workspaceRoot: string, requested: string, absolute: string): boolean {
  const normalized = canonicalPath(absolute);
  return normalized === requested && inside(canonicalPath(workspaceRoot), normalized);
}

function canonicalPath(value: string): string {
  if (/[\x00-\x1f\x7f]/.test(value)) { return ''; }
  const normalized = value.replace(/\\/g, '/');
  const drive = /^[a-z]:\//i.exec(normalized)?.[0];
  const prefix = drive === undefined ? '/' : drive[0].toLowerCase() + ':/';
  if (drive === undefined && (!normalized.startsWith('/') || normalized.startsWith('//'))) { return ''; }
  const parts: string[] = [];
  for (const part of normalized.slice(prefix.length).split('/')) {
    if (!part || part === '.') { continue; }
    if (part === '..') {
      if (parts.length === 0) { return ''; }
      parts.pop();
    } else { parts.push(part); }
  }
  return prefix + parts.join('/');
}

function inside(root: string, path: string): boolean {
  return root.length > 1 && !root.endsWith('/') && path.startsWith(root + '/');
}
