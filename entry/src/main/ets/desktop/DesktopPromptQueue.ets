import { getArray, getField, getRecord, getString } from 'connection';
import { desktopMessageAttachments } from './DesktopAttachments';
import type { DesktopMediaAttachment } from './DesktopAttachments';
import type { DesktopSubmissionEcho } from './DesktopSubmissionEcho';
import { desktopUserMessageClipboardText } from './DesktopUserMessageActionsModel';

export interface DesktopQueuedPrompt {
  id: string;
  requestId: string;
  text: string;
  preview: string;
  editable: boolean;
  attachments: DesktopMediaAttachment[];
  sending?: boolean;
}

export function desktopQueuedPromptPreview(text: string): string {
  // Match the non-interactive WebUI user-text seat: mask on the original text before collapsing runs.
  return desktopQueueCollapseWhitespace(desktopUserMessageClipboardText(text)).trim();
}

export function desktopQueueCollapseWhitespace(text: string): string {
  return text.replace(new RegExp('\\s+', 'gu'), ' ');
}

export function desktopVisiblePromptQueue(rows: DesktopQueuedPrompt[], echoes: DesktopSubmissionEcho[],
  sending?: DesktopQueuedPrompt): DesktopQueuedPrompt[] {
  if (rows.length === 0) { return sending === undefined ? rows : [sending]; }
  if (echoes.length === 0 && sending === undefined) { return rows; }
  const inTranscript = new Set<string>();
  for (const echo of echoes) {
    if (echo.placement === 'transcript') { inTranscript.add(echo.requestId); }
  }
  const confirmed = inTranscript.size === 0 ? rows : rows.filter((row: DesktopQueuedPrompt): boolean =>
    !inTranscript.has(row.requestId));
  return sending === undefined || confirmed.some((row: DesktopQueuedPrompt): boolean => row.requestId === sending.requestId) ?
    confirmed : [...confirmed, sending];
}

export function desktopQueueFileSize(bytes: number): string {
  if (bytes < 1024) { return `${bytes}B`; }
  const kb = bytes / 1024;
  const mb = kb / 1024;
  const gb = mb / 1024;
  if (kb < 1024) { return `${kb < 10 ? kb.toFixed(1) : Math.round(kb)}KB`; }
  if (mb < 1024) { return `${mb < 10 ? mb.toFixed(1) : Math.round(mb)}MB`; }
  return `${gb < 10 ? gb.toFixed(1) : Math.round(gb)}GB`;
}

function queuedPrompt(raw: Object): DesktopQueuedPrompt | undefined {
  const id = getString(raw, 'id') ?? '';
  const parts = getArray(raw, 'content');
  if (!id || parts === undefined) { return undefined; }
  const text: string[] = [];
  let editable = true;
  for (const part of parts) {
    const type = getString(part, 'type');
    if (type === 'text') {
      text.push(getString(part, 'text') ?? '');
    } else {
      editable = false;
    }
  }
  const source = getRecord(raw, 'source');
  const requestId = getString(source, 'kind') === 'user' ? getString(source, 'rpcId') ?? '' : '';
  const value = text.join('');
  return { id: id, requestId: requestId, text: value, preview: desktopQueuedPromptPreview(value),
    editable: editable, attachments: desktopMessageAttachments(raw) };
}

export class DesktopPromptQueue {
  rows: DesktopQueuedPrompt[] = [];
  private sequence: number = -1;

  reset(): void {
    this.sequence = -1;
    this.rows = [];
  }

  observe(values: Object | undefined, sequence: number): boolean {
    const inbox = getField(values, 'inbox');
    if (inbox === undefined || sequence <= this.sequence) { return false; }
    const pending = inbox === null ? [] : getArray(inbox, 'next-turn');
    if (pending === undefined) { return false; }
    this.sequence = sequence;
    const rows: DesktopQueuedPrompt[] = [];
    for (const entry of pending) {
      const row = queuedPrompt(entry);
      if (row !== undefined) { rows.push(row); }
    }
    if (rows.length === 0 && this.rows.length === 0) { return false; }
    this.rows = rows;
    return true;
  }
}
