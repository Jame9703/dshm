/**
 * 三诊断探针（diag-material / diag-webmenu / diag-knock）——生产
 * WebApp.ets writeDiagMarker 机制的 demo 复刻。
 *
 * 【机制（生产逐位对齐）】filesDir 下同名文件，追加一行
 * 「ISO 时间戳 + 空格 + 标记文本 + 换行」；追加而非覆盖：多次事件按序累积，
 * 既能证明发生过，又能看到时间线；写失败静默（诊断辅助，不碰业务路径）。
 *
 * 【为什么不依赖 hilog】本机 hilog 对本应用的 ArkTS 输出不可读（生产真机实测
 * 结论，diag-web-console 头注同一口径）⇒ 全链诊断落 filesDir，设备文件管理器/
 * 终端可直接 cat（spec US5 独立验收口径）。
 *
 * @module Diag
 */
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class Diag {
  /** filesDir 路径（EntryAbility.onCreate 一次性喂入；未初始化时静默不写）。 */
  private static filesDir: string = '';
  /** 最近诊断行（内存环缓冲：界面直接展示，无需 hdc 取文件即可现场自证）。 */
  private static recentLines: Array<string> = [];
  /** 环缓冲上限（够看清一次碰一碰的整条链路）。 */
  private static readonly RECENT_MAX: number = 40;

  /** 最近 N 行（按时间先后；最新在末尾）。 */
  static recent(n: number): Array<string> {
    const all: Array<string> = Diag.recentLines;
    const from: number = all.length > n ? all.length - n : 0;
    const out: Array<string> = [];
    for (let i = from; i < all.length; i++) {
      out.push(all[i]);
    }
    return out;
  }

  /** 一次性初始化（EntryAbility.onCreate 调用；重复调用后者胜出）。 */
  static init(ctx: common.Context): void {
    Diag.filesDir = ctx.filesDir;
  }

  /** 沉浸光感能力探针（启动一次性读数 + 材质构造相关留痕）。 */
  static material(line: string): void {
    Diag.append('diag-material', line);
  }

  /** 网页菜单全链路探针（show/fallback/open/appear/dismiss/item 等）。 */
  static webmenu(line: string): void {
    Diag.append('diag-webmenu', line);
  }

  /** 碰一碰全链探针（注册/重试/接收/注入/unrouted 等）。 */
  static knock(line: string): void {
    Diag.append('diag-knock', line);
  }

  /** 追加写一行「ISO 时间戳 + 详情」；写失败静默。 */
  private static append(name: string, detail: string): void {
    // 环缓冲先记（界面展示用；文件写失败也有内存视图）
    Diag.recentLines.push(`${name.replace('diag-', '')}: ${detail}`);
    if (Diag.recentLines.length > Diag.RECENT_MAX) {
      Diag.recentLines.splice(0, Diag.recentLines.length - Diag.RECENT_MAX);
    }
    try {
      if (Diag.filesDir.length === 0) {
        return;
      }
      const p: string = `${Diag.filesDir}/${name}`;
      const file: fileIo.File = fileIo.openSync(p,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND);
      fileIo.writeSync(file.fd, `${new Date().toISOString()} ${detail}\n`);
      fileIo.closeSync(file);
    } catch (e) {
      // 诊断写失败静默：不碰业务路径
    }
  }
}
