import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { randomUuid } from 'connection';
import { pickDocumentUris, PickOutcome, readDocumentBytes, saveCachedDownload } from 'platform';
import { TIMELINE_CHECKPOINT_BYTES } from './DesktopTimelineCheckpoint';

export interface DesktopTimelinePickedCheckpoint {
  name: string;
  content: string;
}

export async function pickDesktopTimelineCheckpoint(context: common.Context): Promise<DesktopTimelinePickedCheckpoint | undefined> {
  const selected = await pickDocumentUris(context, 1, ['.json']);
  if (selected.outcome === PickOutcome.CANCELLED) { return undefined; }
  if (selected.outcome !== PickOutcome.PICKED || !selected.uris[0]) { throw new Error('select'); }
  const file = await readDocumentBytes(selected.uris[0], undefined, TIMELINE_CHECKPOINT_BYTES);
  if (file.outcome === PickOutcome.TOO_LARGE) { throw new Error('limit'); }
  if (file.outcome !== PickOutcome.PICKED || file.data === undefined) { throw new Error('read'); }
  const content = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(file.data))
    .replace(/^\uFEFF/, '');
  return { name: file.name, content: content };
}

export async function saveDesktopTimelineCheckpoint(context: common.Context, name: string, content: string): Promise<boolean> {
  const bytes = new util.TextEncoder().encodeInto(content);
  if (bytes.byteLength > TIMELINE_CHECKPOINT_BYTES) { throw new Error('limit'); }
  const path = context.cacheDir + '/timeline-export-' + randomUuid() + '.json';
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const written = fileIo.writeSync(file.fd, bytes.buffer);
      if (written !== bytes.byteLength) { throw new Error('short write'); }
    } finally {
      fileIo.closeSync(file);
    }
    return (await saveCachedDownload(context, path, name)).length > 0;
  } finally {
    try { fileIo.unlinkSync(path); } catch (_) { }
  }
}
