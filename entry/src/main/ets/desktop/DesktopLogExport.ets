import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { randomUuid } from 'connection';
import { saveCachedDownload } from 'platform';

export interface DesktopLogSaveResult {
  saved: boolean;
  error: string;
}

export async function exportDesktopLog(context: common.Context, sessionId: string,
  download: (onData: (chunk: ArrayBuffer) => void) => Promise<string>,
  chooseLocation: () => boolean): Promise<DesktopLogSaveResult> {
  const path = `${context.cacheDir}/session-export-${randomUuid()}.zip`;
  const name = `dsh-session-${sessionId.replace(new RegExp('[^A-Za-z0-9_-]', 'g'), '_')}.zip`;
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    let bytes = 0;
    let signature = 0;
    let problem: string;
    try {
      problem = await download((chunk: ArrayBuffer): void => {
        if (bytes < 2) {
          const prefix = new Uint8Array(chunk);
          for (let at = 0; at < prefix.length && bytes + at < 2; at++) {
            signature = signature * 256 + prefix[at];
          }
        }
        const written = fileIo.writeSync(file.fd, chunk);
        if (written !== chunk.byteLength) { throw new Error('short write'); }
        bytes += written;
      });
    } finally {
      fileIo.closeSync(file);
    }
    if (problem) { return { saved: false, error: problem }; }
    if (bytes < 22 || signature !== 0x504b) { return { saved: false, error: '宿主未返回完整的 ZIP 日志' }; }
    if (!chooseLocation()) { return { saved: false, error: '' }; }
    const location = await saveCachedDownload(context, path, name);
    return { saved: location.length > 0, error: '' };
  } catch (_) {
    return { saved: false, error: '无法保存会话日志' };
  } finally {
    try { fileIo.unlinkSync(path); } catch (_) { }
  }
}
