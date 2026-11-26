import { getArray, getField, getNumber, getRecord, getString } from 'connection';

export interface DesktopQueueAttachment {
  id: string;
  name: string;
  bytes: number;
  image: boolean;
  reference?: Object;
}

export interface DesktopQueuedPrompt {
  id: string;
  requestId: string;
  text: string;
  editable: boolean;
  attachments: DesktopQueueAttachment[];
  sending?: boolean;
}

function queuedPrompt(raw: Object): DesktopQueuedPrompt | undefined {
  const id = getString(raw, 'id') ?? '';
  const parts = getArray(raw, 'content');
  if (!id || parts === undefined) { return undefined; }
  const text: string[] = [];
  const attachments: DesktopQueueAttachment[] = [];
  let editable = parts.length > 0;
  for (const part of parts) {
    const type = getString(part, 'type');
    if (type === 'text') {
      text.push(getString(part, 'text') ?? '');
      continue;
    }
    editable = false;
    const reference = getRecord(part, 'attachment');
    const attachmentId = getString(reference, 'attachmentId') ?? '';
    if (attachmentId && (type === 'file' || type === 'image')) {
      attachments.push({ id: attachmentId, name: getString(reference, 'name') ?? '图片',
        bytes: getNumber(reference, 'bytes') ?? 0, image: type === 'image', reference: reference });
    }
  }
  return { id: id, requestId: getString(getRecord(raw, 'source'), 'rpcId') ?? '',
    text: text.join('\n'), editable: editable, attachments: attachments };
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
