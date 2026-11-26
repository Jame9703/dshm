import { webview } from '@kit.ArkWeb';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { PetWindowHolder } from './PetWindowHolder';

const DOMAIN: number = 0xD004;
const TAG: string = 'DshPetHost';

/** 与插件 preload.js 同名的 13 个方法；回调由 runJavaScript 调 __DSHM_PET_DELIVER__。 */
class PetBridge {
  controller: webview.WebviewController | undefined = undefined;
  private interactive: boolean = true;
  private busy: boolean = false;
  private touchableState: boolean = true;
  private pulseTimer: number = -1;
  private pulseRestoreTimer: number = -1;

  setBounds(x: number, y: number, w: number, h: number, boxX: number, boxY: number,
    size: number, bottomPad: number, vx: number, vy: number, marginL: number, marginT: number): void {
    const sub: window.Window | undefined = PetWindowHolder.sub;
    if (sub === undefined) {
      return;
    }
    if (PetWindowHolder.lastBoxX >= 0
      && (Math.abs(boxX - PetWindowHolder.lastBoxX) > 2.5 || Math.abs(boxY - PetWindowHolder.lastBoxY) > 2.5)) {
      // 宠物本体单帧位移 >2.5px ⇒ 拖拽（漫游约 0.2px/帧，10 倍余量）
      PetWindowHolder.lastFastMove = Date.now();
    }
    PetWindowHolder.boxX = boxX;
    PetWindowHolder.boxY = boxY;
    PetWindowHolder.boxSize = size;
    PetWindowHolder.lastBoxX = boxX;
    PetWindowHolder.lastBoxY = boxY;
    sub.moveWindowTo(Math.round(x), Math.round(y)).catch((e: BusinessError): void => {
      hilog.info(DOMAIN, TAG, 'setBounds move rejected: %{public}d', e.code);
    });
    sub.resize(Math.round(w), Math.round(h)).catch((e: BusinessError): void => {
      hilog.info(DOMAIN, TAG, 'setBounds resize rejected: %{public}d', e.code);
    });
  }

  /**
   * JD-018 修复：ArkTS 没有 Electron 的 forward:hover，setWindowTouchable(false) 后
   * 页面收不到 hover，就永远不会再调 true（空闲后永久不可点）。
   * 这里在 false 期间每 300ms 短暂 true 50ms，让页面拿回一次 hover/move：
   *  - 指针在宠物身体内 → 页面调 setInteractive(true) → 停脉冲；
   *  - 指针仍在外面 → 页面会再调 false → 继续脉冲。
   */
  setInteractive(v: boolean): void {
    this.interactive = v;
    if (v || this.busy) {
      this.stopPulse();
      this.applyTouchable(true);
      return;
    }
    this.applyTouchable(false);
    this.startPulse();
  }

  setInputBusy(v: boolean): void {
    this.busy = v;
    if (v) {
      this.stopPulse();
      this.applyTouchable(true);
      return;
    }
    if (!this.interactive) {
      this.applyTouchable(false);
      this.startPulse();
    }
  }

  private applyTouchable(v: boolean): void {
    if (this.touchableState === v) {
      return;
    }
    this.touchableState = v;
    const sub: window.Window | undefined = PetWindowHolder.sub;
    if (sub !== undefined) {
      sub.setWindowTouchable(v).catch((e: BusinessError): void => {
        hilog.info(DOMAIN, TAG, 'setInteractive rejected: %{public}d', e.code);
      });
    }
  }

  private startPulse(): void {
    if (this.pulseTimer >= 0) {
      return;
    }
    this.pulseTimer = setInterval((): void => {
      if (this.interactive || this.busy) {
        return;
      }
      this.applyTouchable(true);
      if (this.pulseRestoreTimer >= 0) {
        clearTimeout(this.pulseRestoreTimer);
      }
      this.pulseRestoreTimer = setTimeout((): void => {
        this.pulseRestoreTimer = -1;
        if (!this.interactive && !this.busy) {
          this.applyTouchable(false);
        }
      }, 50);
    }, 300);
  }

  private stopPulse(): void {
    if (this.pulseTimer >= 0) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = -1;
    }
    if (this.pulseRestoreTimer >= 0) {
      clearTimeout(this.pulseRestoreTimer);
      this.pulseRestoreTimer = -1;
    }
  }

  setInputRegions(json: string): void {
  }

  requestKeyboardFocus(): void {
  }

  openDshSite(url: string): void {
    try {
      const ctx = getContext() as common.UIAbilityContext;
      ctx.openLink(url, { appLinkingOnly: false }).catch((e: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'openDshSite failed: %{public}d', e.code);
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'openDshSite context failed');
    }
  }

  focusDshHost(): void {
  }

  deliverDisplays(): void {
    const c: webview.WebviewController | undefined = this.controller;
    if (c === undefined) {
      return;
    }
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const rect: string = `{"x":0,"y":0,"width":${d.width},"height":${d.height}}`;
      const geo: string = `{"hull":${rect},"areas":[${rect}],"workAreas":[${rect}],"panels":[${rect}],"primaryIndex":0,"topInsetRatio":0}`;
      c.runJavaScript(`window.__DSHM_PET_DELIVER__ && window.__DSHM_PET_DELIVER__('displays', ${geo})`)
        .catch((e: BusinessError): void => {
          hilog.info(DOMAIN, TAG, 'deliverDisplays failed: %{public}d', e.code);
        });
    } catch (e) {
      // 忽略：渲染页会用 window.screen 兜底
    }
  }
}

@Entry
@Component
struct PetWeb {
  @StorageProp('dshPetUrl') private url: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: PetBridge = new PetBridge();

  aboutToAppear(): void {
    this.bridge.controller = this.controller;
  }

  build() {
    Stack() {
      Web({ src: this.url, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .backgroundColor(Color.Transparent)
        .javaScriptProxy({
          object: this.bridge,
          name: '__DSHM_PET_BRIDGE__',
          methodList: ['setBounds', 'setInteractive', 'setInputBusy', 'setInputRegions',
            'requestKeyboardFocus', 'openDshSite', 'focusDshHost'],
          controller: this.controller
        })
        .onPageEnd((): void => {
          this.bridge.deliverDisplays();
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
