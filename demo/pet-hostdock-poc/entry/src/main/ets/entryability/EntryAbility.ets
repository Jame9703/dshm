import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD003;
const TAG: string = 'PetDockPoc';

/**
 * 宿主藏底 POC：
 *  - 宿主主窗固定 smallest 尺寸（320×100vp），放在宠物圆体下方，靠 topmost 带起子窗
 *  - 宠物子窗 640px 圆形，默认 z 序（不传 zLevelAboveParentLoosened），骑在宿主之上
 *  - 100ms 轮询子窗 rect，把宿主居中移到宠物下方；宿主残条不应露出
 */
export default class EntryAbility extends UIAbility {
  private hostWin: window.Window | undefined = undefined;
  private petSub: window.Window | undefined = undefined;
  private syncTimer: number = -1;

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
        hilog.error(DOMAIN, TAG, 'getMainWindow failed: %{public}d %{public}s', e.code, e.message);
      });
    });
  }

  private async setup(stage: window.WindowStage, host: window.Window): Promise<void> {
    try {
      this.hostWin = host;
      const d: display.Display = display.getDefaultDisplaySync();
      const petSize: number = 640;
      const petX: number = Math.max(0, d.width - petSize - Math.round(d.width * 0.03));
      const petY: number = Math.max(0, d.height - petSize - Math.round(d.height * 0.12));

      // 宿主缩到系统最小，先放在宠物下方（后续 sync 会持续跟随）
      await host.resize(320, 100);
      host.setWindowDecorVisible(false);
      host.setWindowTitleButtonVisible(false, false, false);
      await host.setWindowTopmost(true);
      const h0 = host.getWindowProperties().windowRect;
      hilog.info(DOMAIN, TAG, 'host init rect=%{public}d,%{public}d %{public}dx%{public}d',
        h0.left, h0.top, h0.width, h0.height);

      const options: window.SubWindowOptions = {
        title: 'PetSub',
        decorEnabled: false
      };
      const sub: window.Window = await stage.createSubWindowWithOptions('PetSub', options);
      this.petSub = sub;
      await sub.resize(petSize, petSize);
      await sub.moveWindowTo(petX, petY);
      // 顺序：setUIContent 先于背景/掩码（JD-015：否则 1300002）
      await sub.setUIContent('pages/Pet');
      sub.setWindowBackgroundColor('#00000000');
      const mask: Uint8Array = circleMask(petSize);
      await sub.setWindowMaskWithAlpha(mask, petSize, petSize);
      await sub.showWindow();
      const s0 = sub.getWindowProperties().windowRect;
      hilog.info(DOMAIN, TAG, 'sub rect=%{public}d,%{public}d %{public}dx%{public}d',
        s0.left, s0.top, s0.width, s0.height);

      this.syncHostUnderPet();
      this.syncTimer = setInterval((): void => {
        this.syncHostUnderPet();
      }, 100);
      hilog.info(DOMAIN, TAG, 'host-under-pet ready');
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'setup failed: %{public}d %{public}s', err.code, err.message);
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
      const x: number = Math.round(sr.left + (sr.width - hr.width) / 2);
      const y: number = Math.round(sr.top + (sr.height - hr.height) / 2);
      if (Math.abs(x - hr.left) <= 2 && Math.abs(y - hr.top) <= 2) {
        return;
      }
      host.moveWindowTo(x, y).then((): void => {
        hilog.info(DOMAIN, TAG, 'host moved to %{public}d,%{public}d', x, y);
      }).catch((e: BusinessError): void => {
        hilog.info(DOMAIN, TAG, 'host move rejected: %{public}d', e.code);
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.info(DOMAIN, TAG, 'sync skipped: %{public}d', err.code);
    }
  }

  onWindowStageDestroy(): void {
    if (this.syncTimer >= 0) {
      clearInterval(this.syncTimer);
      this.syncTimer = -1;
    }
    this.hostWin = undefined;
    this.petSub = undefined;
  }

  onForeground(): void {
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onDestroy(): void {
  }
}

function circleMask(size: number): Uint8Array {
  const mask: Uint8Array = new Uint8Array(size * size);
  const c: number = (size - 1) / 2;
  const r: number = size * 0.48;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx: number = x - c;
      const dy: number = y - c;
      const dist: number = Math.sqrt(dx * dx + dy * dy);
      let a: number = 0;
      if (dist <= r - 1) {
        a = 255;
      } else if (dist < r + 1) {
        a = Math.round(255 * (r + 1 - dist) / 2);
      }
      mask[y * size + x] = a;
    }
  }
  return mask;
}
