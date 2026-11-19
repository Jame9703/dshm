/**
 * KnockShim —— 碰一碰注入垫片（demo 版）。
 *
 * 逐位移植生产 WebApp.ets 的 KNOCK_SHIM_JS / buildKnockEmitScript / pushKnockFile
 * 三件套，是「模拟碰一碰」与「真实接收」共用的唯一注入出口（FR-007）。
 *
 * 【注入链】base64 → __DSHM_KNOCK__.emit → 合成 ClipboardEvent('paste') →
 * 官方 file-intake 的 document 级监听 → 附件 chip 进输入区（不自动发送，FR-008）。
 * 【退路链】ClipboardEvent 构造失败则 DragEvent('drop')（官方 drop-events 同样
 * 无 isTrusted 门槛）→ 再失败返回 'unrouted' 留痕。
 * 【升级回归】上游若日后给 intake 加 isTrusted 校验，本链即失效——真机验收靠
 * emit 返回值 + [dshm-knock] console 转发定位（对齐生产注释口径）。
 *
 * 另附 platform/FilePreview.ets 的 mimeTypeForName 后缀映射（demo 内共享，
 * 供模拟管线与接收器对 KnockFile.mime 赋值，与生产同表）。
 */
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { KnockFile } from '../model/DemoTypes';
import { Diag } from './Diag';

/**
 * 注入结果。
 * ok=false：注入未完成（controller 未挂载同步抛 / runJavaScript 报 err 回调），
 *           调用方应把该文件回队补发（deliverKnockFiles 的 break 语义）。
 * ok=true：脚本已执行，result 为页面侧返回值（paste/drop/unrouted/no-shim/
 *          bad-payload/error）——与生产一致仅记 diag 标记，视为已消费不回队。
 */
export class KnockInjectResult {
  ok: boolean = false;
  result: string = '';

  constructor(ok: boolean, result: string) {
    this.ok = ok;
    this.result = result;
  }
}

/**
 * document-start 注入的垫片脚本：逐字移植生产 KNOCK_SHIM_JS（WebApp.ets :3393）。
 * 注册形态见 KnockDemoView：javaScriptOnDocumentStart([{script, scriptRules:['*']}]）。
 */
export const KNOCK_SHIM_SCRIPT: string = `(function () {
  if (window.__DSHM_KNOCK__) { return; }
  function log(m) {
    try { console.info('[dshm-knock] ' + m); } catch (e) { /* 诊断不阻断 */ }
  }
  /* base64 → Uint8Array；atob 在 ArkWeb（Chromium 内核）可用。 */
  function toFile(p) {
    var bin;
    try { bin = atob(String(p.base64 || '')); }
    catch (e) { log('atob 失败（载荷损坏？）'); return null; }
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) { bytes[i] = bin.charCodeAt(i); }
    var name = String(p.name || 'knock-file');
    var mime = String(p.mime || 'application/octet-stream');
    try { return new File([bytes], name, { type: mime }); }
    catch (e) { return new Blob([bytes], { type: mime }); }
  }
  /* 合成 document 级 paste：ClipboardEvent 的 init.clipboardData 带 DataTransfer，
     官方 file-intake.ts 从 clipboardData.items 取 File 路由进输入框。 */
  function dispatchPaste(file) {
    var dt = new DataTransfer();
    dt.items.add(file);
    var ev = new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true });
    if (!ev.clipboardData) { throw new Error('ClipboardEvent ctor 丢弃 clipboardData'); }
    document.dispatchEvent(ev);
    return 'paste';
  }
  /* 退路：官方 drop-events.ts 的 document 级 drop 监听（同样不校验 isTrusted）。 */
  function dispatchDrop(file) {
    var dt = new DataTransfer();
    dt.items.add(file);
    var ev = new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true });
    if (!ev.dataTransfer) { throw new Error('DragEvent ctor 丢弃 dataTransfer'); }
    document.dispatchEvent(ev);
    return 'drop';
  }
  window.__DSHM_KNOCK__ = {
    emit: function (payload) {
      var file = toFile(payload);
      if (!file) { return 'bad-payload'; }
      try { return dispatchPaste(file); }
      catch (e) { log('paste 路不通：' + (e && e.message ? e.message : e)); }
      try { return dispatchDrop(file); }
      catch (e) { log('drop 路不通：' + (e && e.message ? e.message : e)); }
      return 'unrouted';
    }
  };
  log('shim ready');
})();`;

/**
 * 单个碰一碰文件的注入脚本：JSON 载荷 → shim.emit → 合成 paste → 官方 intake。
 * 逐字移植生产 buildKnockEmitScript（WebApp.ets :3444）。
 */
export function buildKnockEmitScript(file: KnockFile): string {
  const payload: KnockFile = { name: file.name, mime: file.mime, size: file.size, base64: file.base64 };
  return `(function () {
  try {
    var api = window.__DSHM_KNOCK__;
    if (!api) {
      console.warn('[dshm-knock] shim 未注入（document-start 清单缺项？）');
      return 'no-shim';
    }
    return String(api.emit(${JSON.stringify(payload)}));
  } catch (e) {
    console.warn('[dshm-knock] emit 异常: ' + (e && e.message ? e.message : e));
    return 'error';
  }
})()`;
}

/**
 * runJavaScript 的字符串返回可能被 JSON 引号包裹（'"paste"'），状态展示前剥掉
 * 首尾引号；diag 标记照原始值记（与生产 'inject result=' 口径一致）。
 */
function normalizeJsResult(raw: string): string {
  let v: string = raw;
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    v = v.substring(1, v.length - 1);
  }
  return v;
}

/**
 * 单文件注入（唯一出口，FR-007）：base64 载荷 → __DSHM_KNOCK__.emit → 合成 paste
 * → 官方 intake。语义对齐生产 pushKnockFile（WebApp.ets :5777）：
 * - 同步抛（controller 未挂载）→ ok=false，diag 记 `inject throw=<msg>`；
 * - err 回调 → ok=false，diag 记 `inject err=<msg>`（生产此路文件已消费，
 *   demo 用 await 强化为可回队补发，不丢——diag 标记不变）；
 * - 正常回调 → ok=true，diag 记 `inject result=<raw>`，result 剥引号供状态展示。
 */
export async function injectFile(controller: webview.WebviewController, file: KnockFile): Promise<KnockInjectResult> {
  return new Promise<KnockInjectResult>((resolve) => {
    try {
      controller.runJavaScript(buildKnockEmitScript(file), (err: BusinessError, result: string) => {
        if (err) {
          Diag.knock(`inject err=${err.message}`);
          resolve(new KnockInjectResult(false, `err:${err.message}`));
          return;
        }
        Diag.knock(`inject result=${result}`);
        resolve(new KnockInjectResult(true, normalizeJsResult(result)));
      });
    } catch (e) {
      Diag.knock(`inject throw=${(e as BusinessError).message}`);
      resolve(new KnockInjectResult(false, `throw:${(e as BusinessError).message}`));
    }
  });
}

/**
 * 后缀 → MIME 表：逐字移植生产 platform/FilePreview.ets 的 MIME_BY_SUFFIX。
 * 表里没有的回空串，调用方（模拟管线/接收器）回退 'application/octet-stream'。
 */
const MIME_BY_SUFFIX: Record<string, string> = {
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'csv': 'text/csv',
  'ofd': 'general.ofd',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'xml': 'text/xml',
  'html': 'text/html',
  'htm': 'text/html',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'mp4': 'video/mp4'
};

/** 取文件名后缀（小写、去点）。没有后缀返回空串。（移植 platform/FilePreview.suffixOf） */
function suffixOf(name: string): string {
  const base: string = name.trim();
  const slash: number = Math.max(base.lastIndexOf('/'), base.lastIndexOf('\\'));
  const leaf: string = slash >= 0 ? base.substring(slash + 1) : base;
  const dot: number = leaf.lastIndexOf('.');
  if (dot <= 0 || dot === leaf.length - 1) {
    return '';
  }
  return leaf.substring(dot + 1).toLowerCase();
}

/** 后缀对应的 MIME；表中没有返回空串（调用方回退 application/octet-stream）。 */
export function mimeTypeForName(name: string): string {
  const suffix: string = suffixOf(name);
  const mime: string | undefined = MIME_BY_SUFFIX[suffix];
  return mime === undefined ? '' : mime;
}
