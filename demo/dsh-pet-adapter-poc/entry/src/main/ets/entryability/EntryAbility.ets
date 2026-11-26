import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PetWindowHolder } from '../pages/PetWindowHolder';

const DOMAIN: number = 0xD004;
const TAG: string = 'DshPetHost';

/** 由 DevEco 按本机代理端口调整；configUrl 与页面同源（3090）。 */
const PET_PAGE: string = 'http://127.0.0.1:3090/dsh-pet-native/probe.html';

export default class EntryAbility extends UIAbility {
  private hostWin: window.Window | undefined = undefined;
  private petSub: window.Window | undefined = undefined;
  private syncTimer: number = -1;
  private maskedW: number = -1;
  private maskedH: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Host', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}d %{public}s', err.code, err.message);
        return;
      }
      windowStage.getMainWindow().then((win: window.Window): void => {
        this.setup(windowStage, win);
      }).catch((e: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'getMainWindow failed: %{public}d', e.code);
      });
    });
  }

  private async setup(stage: window.WindowStage, host: window.Window): Promise<void> {
    try {
      this.hostWin = host;
      const d: display.Display = display.getDefaultDisplaySync();
      const petSize: number = 620;
      const petX: number = Math.max(0, d.width - petSize - Math.round(d.width * 0.03));
      const petY: number = Math.max(0, d.height - petSize - Math.round(d.height * 0.12));

      try {
        await host.setWindowLimits({ minWidth: 40, minHeight: 40 }, true);
      } catch (e) {
        hilog.info(DOMAIN, TAG, 'setWindowLimits skipped');
      }
      await host.resize(24, 24);
      host.setWindowDecorVisible(false);
      host.setWindowTitleButtonVisible(false, false, false);
      await host.setWindowTopmost(true);

      const options: window.SubWindowOptions = { title: 'DshPet', decorEnabled: false, outlineEnabled: false };
      const sub: window.Window = await stage.createSubWindowWithOptions('DshPet', options);
      this.petSub = sub;
      PetWindowHolder.sub = sub;
      await sub.resize(petSize, petSize);
      await sub.moveWindowTo(petX, petY);
      const scale: number = d.densityPixels > 0 ? d.densityPixels : 1;
      const url: string = PET_PAGE
        + '?configUrl=' + encodeURIComponent('http://127.0.0.1:3090/dsh-pet-7340/config')
        + '&petIndex=0&scale=' + String(scale)
        + '&bridge=0&openTarget=web&isWindowClampedToWorkArea=1';
      AppStorage.setOrCreate<string>('dshPetUrl', url);
      await sub.setUIContent('pages/PetWeb');
      try {
        sub.setWindowBackgroundColor('#00000000');
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'bg transparent failed');
      }
      await sub.showWindow();
      hilog.info(DOMAIN, TAG, 'pet subwindow ready, url=%{public}s', url);
      this.syncHostUnderPet();
      this.syncTimer = setInterval((): void => {
        this.syncHostUnderPet();
        this.applyPetMask();
      }, 100);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'setup failed: %{public}d %{public}s', err.code, err.message);
    }
  }

  /** 边框掩码：窗口外圈 B 像素 alpha=0、其余 255。实测可使 WM 不再绘制窗口矩形阴影，
   *  且不裁剪任何内容（宠物/气泡/菜单都在内区）；窗口尺寸变化时重挂。 */
  private applyPetMask(): void {
    const sub: window.Window | undefined = this.petSub;
    if (sub === undefined) {
      return;
    }
    try {
      const rect = sub.getWindowProperties().windowRect;
      const w: number = rect.width;
      const h: number = rect.height;
      if (w <= 0 || h <= 0 || (w === this.maskedW && h === this.maskedH)) {
        return;
      }
      const border: number = 4;
      const mask: Uint8Array = new Uint8Array(w * h);
      for (let y = 0; y < h; y++) {
        const inY: boolean = y >= border && y < h - border;
        const rowBase: number = y * w;
        for (let x = 0; x < w; x++) {
          if (inY && x >= border && x < w - border) {
            mask[rowBase + x] = 255;
          }
        }
      }
      sub.setWindowMaskWithAlpha(mask, w, h).then((): void => {
        this.maskedW = w;
        this.maskedH = h;
        hilog.info(DOMAIN, TAG, 'border mask applied %{public}d x %{public}d', w, h);
      }).catch((e: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'border mask failed: %{public}d', e.code);
      });
    } catch (e) {
      // 未就绪
    }
  }

  private syncHostUnderPet(): void {
    const host: window.Window | undefined = this.hostWin;
    const sub: window.Window | undefined = this.petSub;
    if (host === undefined || sub === undefined) {
      return;
    }
    try {
      const sr = sub.getWindowProperties().windowRect;
      const hr = host.getWindowProperties().windowRect;
      let cx: number = sr.left + sr.width / 2;
      let cy: number = sr.top + sr.height / 2;
      if (PetWindowHolder.boxSize > 0 && PetWindowHolder.boxX >= 0) {
        cx = PetWindowHolder.boxX + PetWindowHolder.boxSize / 2;
        cy = PetWindowHolder.boxY + PetWindowHolder.boxSize * 0.5;
      }
      const x: number = Math.round(cx - hr.width / 2);
      const y: number = Math.round(cy - hr.height / 2);
      if (Math.abs(x - hr.left) > 2 || Math.abs(y - hr.top) > 2) {
        host.moveWindowTo(x, y).catch((e: BusinessError): void => {
          hilog.info(DOMAIN, TAG, 'host move rejected: %{public}d', e.code);
        });
      }
    } catch (e) {
      // 忽略
    }
  }

  onWindowStageDestroy(): void {
    if (this.syncTimer >= 0) {
      clearInterval(this.syncTimer);
      this.syncTimer = -1;
    }
    this.hostWin = undefined;
    this.petSub = undefined;
    PetWindowHolder.sub = undefined;
  }

  onForeground(): void {
  }

  onBackground(): void {
  }

  onDestroy(): void {
  }
}
