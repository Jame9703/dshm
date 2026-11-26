import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { getString } from 'connection';
import { uriFromPath } from 'platform';

export interface DesktopDroppedFiles {
  uris: string[];
  hasFolder: boolean;
}

export const DESKTOP_ATTACHMENT_DROP_TYPES: uniformTypeDescriptor.UniformDataType[] = [
  uniformTypeDescriptor.UniformDataType.FILE_URI, uniformTypeDescriptor.UniformDataType.IMAGE,
  uniformTypeDescriptor.UniformDataType.FILE, uniformTypeDescriptor.UniformDataType.FOLDER,
  uniformTypeDescriptor.UniformDataType.DIRECTORY
];

function isFolder(type?: string): boolean {
  return type === uniformTypeDescriptor.UniformDataType.FOLDER ||
    type === uniformTypeDescriptor.UniformDataType.DIRECTORY;
}

export function desktopAttachmentUri(value?: string): string {
  if (value?.startsWith('file://')) { return value; }
  return value?.startsWith('/') ? uriFromPath(value) : '';
}

export function desktopDroppedFiles(data: unifiedDataChannel.UnifiedData): DesktopDroppedFiles {
  const uris = new Set<string>();
  let hasFolder = false;
  for (const record of data.getRecords()) {
    if (isFolder(record.getType())) {
      hasFolder = true;
      continue;
    }
    if (record instanceof unifiedDataChannel.File) {
      const uri = desktopAttachmentUri(record.uri);
      if (uri) { uris.add(uri); }
      continue;
    }
    const value = record.getEntry(uniformTypeDescriptor.UniformDataType.FILE_URI);
    if (typeof value === 'string') {
      const uri = desktopAttachmentUri(value);
      if (uri) { uris.add(uri); }
    } else if (typeof value === 'object' && value !== null) {
      if (isFolder(getString(value, 'fileType'))) {
        hasFolder = true;
      } else {
        const uri = desktopAttachmentUri(getString(value, 'oriUri'));
        if (uri) { uris.add(uri); }
      }
    }
  }
  return { uris: Array.from(uris), hasFolder: hasFolder };
}

export function desktopClipboardHasAttachments(): boolean {
  try {
    const board = pasteboard.getSystemPasteboard();
    return board.hasDataType(pasteboard.MIMETYPE_PIXELMAP) || board.hasDataType(pasteboard.MIMETYPE_TEXT_URI) ||
      board.hasDataType(uniformTypeDescriptor.UniformDataType.FILE_URI);
  } catch (_) {
    return false;
  }
}

export function desktopClipboardHasText(): boolean {
  try {
    const board = pasteboard.getSystemPasteboard();
    return board.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN) || board.hasDataType(pasteboard.MIMETYPE_TEXT_HTML);
  } catch (_) {
    return true;
  }
}

export async function packDesktopClipboardPicture(picture: image.PixelMap): Promise<ArrayBuffer> {
  const packer = image.createImagePacker();
  try {
    return await packer.packToData(picture, { format: 'image/png', quality: 100 });
  } finally {
    await packer.release();
  }
}
