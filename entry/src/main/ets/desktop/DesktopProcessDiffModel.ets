import { collapseContext, diffLines, diffStatOf, intendedDiffOf } from 'appstate';
import type { DiffLine, ToolDiff } from 'appstate';
import { getArray, getField, getString, parseJson, stringifyJson } from 'connection';

const PREVIEW_LINES: number = 9;
const MAX_FILES: number = 12;
const MAX_PATH: number = 2048;
const MAX_ARGS: number = 128 * 1024;
const MAX_TEXT: number = 4096;
const MAX_SOURCE_LINES: number = 384;
const CRLF = new RegExp('\\r?\\n');
const ABSOLUTE_DRIVE = new RegExp('^[A-Za-z]:[/\\\\]');

export type DesktopProcessDiffStage = 'planned' | 'applied' | 'written' | 'planned-files';
export type DesktopProcessPatchKind = 'add' | 'update' | 'delete';

interface DesktopProcessDiffText {
  path: string;
  oldText: string | null;
  newText: string;
  truncated: boolean;
}

export interface DesktopProcessDiffMeta {
  absolutePath: string;
  files: DesktopProcessDiffText[];
  truncated: boolean;
}

export interface DesktopProcessDiffFile {
  path: string;
  moveTo?: string;
  action?: DesktopProcessPatchKind;
  lines: DiffLine[];
  added: number;
  removed: number;
  truncated: boolean;
}

export interface DesktopProcessDiffPreview {
  stage: DesktopProcessDiffStage;
  files: DesktopProcessDiffFile[];
  truncated: boolean;
}

interface DesktopPatchTarget {
  path: string;
  kind: DesktopProcessPatchKind;
  moveTo?: string;
}

function usablePath(path?: string): boolean {
  return path !== undefined && path.trim().length > 0 && path.length <= MAX_PATH;
}

function boundText(text: string): string {
  const prefix = text.slice(0, MAX_TEXT);
  let end = -1;
  for (let lines = 1; lines < MAX_SOURCE_LINES; lines++) {
    end = prefix.indexOf('\n', end + 1);
    if (end < 0) { return prefix; }
  }
  return prefix.slice(0, end);
}

function fileText(path: string, oldText: string | null, newText: string): DesktopProcessDiffText {
  const before = oldText === null ? null : boundText(oldText);
  const after = boundText(newText);
  return { path: path, oldText: before, newText: after, truncated: before !== oldText || after !== newText };
}

/** Keep only the file result metadata the tool preview can render. */
export function readDesktopProcessDiffMeta(meta?: Object): DesktopProcessDiffMeta | undefined {
  const diffs = getArray(meta, 'diffs');
  if (diffs === undefined || diffs.length === 0) { return undefined; }
  const files: DesktopProcessDiffText[] = [];
  for (const value of diffs.slice(0, MAX_FILES)) {
    const path = getString(value, 'path');
    const before = getField(value, 'oldText');
    const after = getString(value, 'newText');
    if (path === undefined || !usablePath(path) || (before !== null && typeof before !== 'string') ||
        after === undefined) { return undefined; }
    files.push(fileText(path, typeof before === 'string' ? before : null, after));
  }
  const path = getString(meta, 'path') ?? '';
  const absolute = path.startsWith('/') || path.startsWith('\\\\') || ABSOLUTE_DRIVE.test(path);
  return { absolutePath: absolute && usablePath(path) ? path : '', files: files, truncated: diffs.length > files.length };
}

function plan(tool: string, raw: string, args?: Object): ToolDiff | null {
  if ((tool !== 'write' && tool !== 'edit' && tool !== 'str_replace_editor') || args === undefined ||
      raw.length > MAX_ARGS) { return null; }
  let accepted = raw;
  if (tool === 'write' || tool === 'edit') {
    // Current bundled WebUI does not make file preview contingent on optional escalation fields.
    if (getField(args, 'sandbox_permissions') !== undefined || getField(args, 'justification') !== undefined) {
      const selected: Record<string, Object | null> = {};
      for (const name of ['file_path', 'content', 'old_string', 'new_string', 'replace_all']) {
        const value = getField(args, name);
        if (value !== undefined) { selected[name] = value; }
      }
      accepted = stringifyJson(selected) ?? '';
    }
  }
  const diff = intendedDiffOf(tool, accepted);
  if (diff === null || !usablePath(diff.path)) { return null; }
  if (tool === 'str_replace_editor' && getString(args, 'command') === 'str_replace' && getString(args, 'old_str') === '') {
    return { path: diff.path, oldText: '', newText: diff.newText };
  }
  return diff;
}

function patchHeader(line: string): DesktopPatchTarget | undefined {
  if (line.startsWith('*** Add File: ')) { return { path: line.slice(14), kind: 'add' }; }
  if (line.startsWith('*** Update File: ')) { return { path: line.slice(17), kind: 'update' }; }
  if (line.startsWith('*** Delete File: ')) { return { path: line.slice(17), kind: 'delete' }; }
  return undefined;
}

/** Read the addresses of syntactically complete patch operations without deriving old file contents. */
function plannedPatch(input: string): DesktopProcessDiffPreview | undefined {
  if (input.length > MAX_ARGS) { return undefined; }
  let lines = input.trim().split(CRLF);
  if (['<<EOF', "<<'EOF'", '<<"EOF"'].includes(lines[0]) && lines.length >= 4 &&
      lines[lines.length - 1].endsWith('EOF')) { lines = lines.slice(1, -1); }
  if (lines.length < 3 || lines[0].trim() !== '*** Begin Patch' ||
      lines[lines.length - 1].trim() !== '*** End Patch') { return undefined; }

  const targets: DesktopPatchTarget[] = [];
  let current: DesktopPatchTarget | undefined;
  let inHunk = false;
  let hasContent = false;
  let eof = false;
  let omitted = false;
  for (let index = 1; index < lines.length - 1; index++) {
    const line = lines[index];
    const header = current?.kind === 'update' ? line.trimEnd() : line.trim();
    const operation = patchHeader(header);
    if (operation !== undefined) {
      if ((current?.kind === 'update' && !hasContent) || !usablePath(operation.path)) { return undefined; }
      current = operation;
      inHunk = false;
      hasContent = false;
      eof = false;
      if (targets.length < MAX_FILES) { targets.push(operation); }
      else { omitted = true; }
    } else if (current?.kind === 'add' && line.startsWith('+')) {
      continue;
    } else if (current?.kind === 'update') {
      if (header === '@@' || header.startsWith('@@ ')) {
        if (inHunk && !hasContent) { return undefined; }
        inHunk = true;
        hasContent = false;
        eof = false;
      } else if (eof) {
        if (header !== '') { return undefined; }
      } else if (!inHunk && current.moveTo === undefined && header.startsWith('*** Move to: ')) {
        current.moveTo = header.slice(13);
        if (!usablePath(current.moveTo)) { return undefined; }
      } else if (header === '*** End of File') {
        if (inHunk && !hasContent) { return undefined; }
        eof = inHunk;
      } else if (line === '' || line.startsWith(' ') || line.startsWith('+') || line.startsWith('-')) {
        inHunk = true;
        hasContent = true;
      } else { return undefined; }
    } else { return undefined; }
  }
  if (targets.length === 0 || (current?.kind === 'update' && !hasContent)) { return undefined; }
  const files = targets.map((target: DesktopPatchTarget): DesktopProcessDiffFile => ({
    path: target.path, moveTo: target.moveTo, action: target.kind, lines: [], added: 0, removed: 0, truncated: false
  }));
  return { stage: 'planned-files', files: files, truncated: omitted };
}

function diffCard(stage: DesktopProcessDiffStage, input: DesktopProcessDiffText[],
  omitted: boolean = false): DesktopProcessDiffPreview {
  const files: DesktopProcessDiffFile[] = [];
  let remaining = PREVIEW_LINES;
  let truncated = omitted;
  for (const file of input) {
    const all = diffLines(file.oldText, file.newText);
    const stats = diffStatOf(all);
    const contextual = collapseContext(all, 3);
    const lines = contextual.slice(0, remaining);
    const clipped = file.truncated || contextual.length > lines.length;
    files.push({ path: file.path, lines: lines, added: stats.added, removed: stats.removed, truncated: clipped });
    remaining -= lines.length;
    truncated = truncated || clipped;
  }
  return { stage: stage, files: files, truncated: truncated };
}

export function desktopProcessDiff(tool: string, rawArgs: string, pending: boolean, successful: boolean,
  nested: boolean, meta?: DesktopProcessDiffMeta): DesktopProcessDiffPreview | undefined {
  if (nested || (!pending && !successful)) { return undefined; }
  const args = rawArgs.length <= MAX_ARGS ? parseJson(rawArgs) : undefined;
  const intended = plan(tool, rawArgs, args);
  if (pending) {
    if (intended !== null) { return diffCard('planned', [fileText(intended.path, intended.oldText, intended.newText)]); }
    return tool === 'apply_patch' ? plannedPatch(getString(args, 'input') ?? '') : undefined;
  }
  if (tool === 'str_replace_editor' && intended !== null) { return undefined; }
  if (meta !== undefined) {
    const files = meta.files.map((file: DesktopProcessDiffText): DesktopProcessDiffText => ({
      path: intended !== null && file.path === meta.absolutePath ? intended.path : file.path,
      oldText: file.oldText, newText: file.newText, truncated: file.truncated
    }));
    return diffCard('applied', files, meta.truncated);
  }
  return tool === 'write' && intended !== null ?
    diffCard('written', [fileText(intended.path, null, intended.newText)]) : undefined;
}
