import { common, wantConstant } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { randomUuid } from 'connection';
import { mimeTypeForName, openSystemPreview, saveCachedDownload, uriFromPath } from 'platform';

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

export async function openDesktopReferenceFile(context: common.UIAbilityContext, path: string,
  name: string): Promise<boolean> {
  const uri = uriFromPath(path);
  try {
    await context.startAbility({ action: 'ohos.want.action.viewData', uri: uri,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION });
    return true;
  } catch (_) {
    return openSystemPreview(context, uri, name, mimeTypeForName(name));
  }
}

export async function saveDesktopReferenceFile(context: common.UIAbilityContext, path: string, name: string): Promise<boolean> {
  // Saving over the original path must read the complete source snapshot.
  const cache = context.cacheDir + '/reference-' + randomUuid();
  try {
    await fileIo.copyFile(path, cache);
    return (await saveCachedDownload(context, cache, name)).length > 0;
  } finally {
    await fileIo.unlink(cache).catch((): void => {});
  }
}

export async function copyDesktopReferenceImage(path: string): Promise<void> {
  const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
  try {
    const source = image.createImageSource(file.fd);
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
  } finally {
    await fileIo.close(file);
  }
}
