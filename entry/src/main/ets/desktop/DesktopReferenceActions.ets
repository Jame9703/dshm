import { common, Want, wantConstant } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { getBoolean, getField, getNumber, getRecord, getString, randomUuid } from 'connection';
import { mimeTypeForName, openSystemPreview, saveCachedDownload, uriFromPath } from 'platform';
import { DesktopHostActions } from './DesktopHostActions';

export enum DesktopReferenceAction {
  REVEAL = 'reveal',
  OPEN = 'open',
  COPY_PATH = 'copyPath',
  COPY_IMAGE = 'copyImage',
  DOWNLOAD = 'download',
  ADD_TO_CHAT = 'addToChat'
}

export interface DesktopFileReferenceOffer {
  sessionId: string;
  path: string;
}

export interface DesktopReferenceSource {
  host: DesktopHostActions;
  sessionId: string;
  path: string;
  absolutePath: string;
}

// The bundled workspaceFiles service defaults to a 32 MiB complete-file reply.
const WORKSPACE_COMPLETE_BYTES: number = 32 * 1024 * 1024;

export async function openDesktopReferenceFile(context: common.UIAbilityContext, path: string,
  name: string): Promise<boolean> {
  const uri = uriFromPath(path);
  if (!uri) { return false; }
  const mediaType = mimeTypeForName(name);
  const want: Want = { action: 'ohos.want.action.viewData', uri: uri,
    flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION };
  if (mediaType) { want.type = mediaType; }
  try {
    await context.startAbility(want);
    return true;
  } catch (_) {
    return openSystemPreview(context, uri, name, mediaType);
  }
}

async function readWorkspaceTransfer(source: DesktopReferenceSource): Promise<ArrayBuffer | undefined> {
  const result = await source.host.readWorkspaceBytes(source.sessionId, source.path, WORKSPACE_COMPLETE_BYTES);
  if (result.error?.code === 'workspace-file/too-large') {
    // Preserve saving large local files without materializing them in UI memory.
    // The Host must still confirm the same source before the local copy.
    const stat = await source.host.call('workspaceFiles/stat', {
      'workspaceFileScopeId': source.sessionId, 'path': source.path
    });
    if (stat.ok && getString(stat.value, 'absolutePath') === source.absolutePath) { return undefined; }
  }
  if (!result.ok) { throw new Error('Original file unavailable'); }
  const metadata = getRecord(result.value, 'metadata');
  const bytes = getField(result.value, 'data');
  const length = getNumber(metadata, 'bytes');
  if (!(bytes instanceof ArrayBuffer) || bytes.byteLength > WORKSPACE_COMPLETE_BYTES ||
    getString(metadata, 'absolutePath') !== source.absolutePath ||
    getBoolean(metadata, 'eof') !== true || getNumber(metadata, 'offset') !== 0 ||
    (length !== undefined && length !== bytes.byteLength)) {
    throw new Error('Original file reply incomplete');
  }
  return bytes;
}

export async function saveDesktopReferenceFile(context: common.UIAbilityContext, source: DesktopReferenceSource,
  name: string): Promise<boolean> {
  // Saving over the original path must read the complete source snapshot.
  const bytes = await readWorkspaceTransfer(source);
  const cache = context.cacheDir + '/reference-' + randomUuid();
  try {
    if (bytes === undefined) {
      await fileIo.copyFile(source.absolutePath, cache);
    } else {
      const file = await fileIo.open(cache, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        if (bytes.byteLength && await fileIo.write(file.fd, bytes) !== bytes.byteLength) {
          throw new Error('Original file snapshot incomplete');
        }
      } finally {
        await fileIo.close(file);
      }
    }
    return (await saveCachedDownload(context, cache, name)).length > 0;
  } finally {
    await fileIo.unlink(cache).catch((): void => {});
  }
}

export async function copyDesktopReferenceImage(source: DesktopReferenceSource): Promise<void> {
  const bytes = await readWorkspaceTransfer(source);
  if (bytes !== undefined) {
    await copyReferenceImageSource(image.createImageSource(bytes));
    return;
  }
  const file = await fileIo.open(source.absolutePath, fileIo.OpenMode.READ_ONLY);
  try {
    await copyReferenceImageSource(image.createImageSource(file.fd));
  } finally {
    await fileIo.close(file);
  }
}

async function copyReferenceImageSource(source: image.ImageSource): Promise<void> {
  try {
    const bitmap = await source.createPixelMap();
    try {
      const payload = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, bitmap);
      await pasteboard.getSystemPasteboard().setData(payload);
    } finally {
      await bitmap.release();
    }
  } finally {
    await source.release();
  }
}
