import { getArray, getField, getRecord, getString } from 'connection';
import { desktopMessageAttachments } from './DesktopAttachments';
import type { DesktopMediaAttachment } from './DesktopAttachments';

export interface DesktopQueuedPrompt {
  id: string;
  requestId: string;
  text: string;
  editable: boolean;
  attachments: DesktopMediaAttachment[];
  sending?: boolean;
}

function queuedPrompt(raw: Object): DesktopQueuedPrompt | undefined {
  const id = getString(raw, 'id') ?? '';
  const parts = getArray(raw, 'content');
  if (!id || parts === undefined) { return undefined; }
  const text: string[] = [];
  let editable = parts.length > 0;
  for (const part of parts) {
    const type = getString(part, 'type');
    if (type === 'text') {
      text.push(getString(part, 'text') ?? '');
    } else {
      editable = false;
    }
  }
  return { id: id, requestId: getString(getRecord(raw, 'source'), 'rpcId') ?? '',
    text: text.join('\n'), editable: editable, attachments: desktopMessageAttachments(raw) };
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
