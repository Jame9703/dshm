import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD002;
const TAG: string = 'PetSubPoc';

/**
 * 独立子窗桌宠 POC（API 26）—— DevEco 取证修订版。
 *
 * 修订点（相对 WorkBuddy 初版）：
 *  1. 子窗链顺序修正：setUIContent 必须先于 setWindowBackgroundColor / setWindowMaskWithAlpha，
 *     否则子窗无内容态调 backgroundColor 报 1300002（2026-11-20 15:16 实测）。
 *  2. 每步独立 tryStep：单步失败不中断链路，一次运行拿到全部读数。
 *  3. rect 沉降复读：WM 异步生效，立即读的 rect 是旧值（初版 host rect=732,140 1930x1286 为假读数）。
 *  4. 离屏移动二次尝试：判定系统对自由窗离屏坐标的钳制行为。
 *  5. B1 配置：zLevelAboveParentLoosened 改回 false（默认约束"子窗 z 必须在父窗之上"）。
 *     原值 true 会放宽该约束，实测子窗 z(125/126) 落到父窗(128)与被抬升应用(微信 pc3=127)之下，
 *     宠物被盖且不可交互（15:36 z 序实读）。默认约束 + 父窗 topmost 才能让子窗骑在 topmost 带。
 */
export default class EntryAbility extends UIAbility {
  private static instance: EntryAbility | undefined = undefined;
  private petSub: window.Window | undefined = undefined;
  private mainWindow: window.Window | undefined = undefined;

  static getInstance(): EntryAbility | undefined {
    return EntryAbility.instance;
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    EntryAbility.instance = this;
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  /** Q6 触发器：最小化宿主主窗，观察独立子窗是否存活。 */
  minimizeHost(): void {
    const w: window.Window | undefined = this.mainWindow;
    if (w === undefined) {
      hilog.error(DOMAIN, TAG, 'minimizeHost: mainWindow missing');
      return;
    }
    w.minimize().then((): void => {
      hilog.info(DOMAIN, TAG, 'host.minimize ok (Q6 trigger)');
    }).catch((e: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'host.minimize fail: %{public}d %{public}s', e.code, e.message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Host', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}d %{public}s', err.code, err.message);
        return;
      }
      windowStage.getMainWindow().then((win: window.Window): void => {
        this.setupHostAndPet(windowStage, win);
      }).catch((e: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'getMainWindow failed: %{public}d %{public}s', e.code, e.message);
      });
    });
  }

  private async tryStep(name: string, fn: () => void | Promise<void>): Promise<boolean> {
    try {
      await fn();
      hilog.info(DOMAIN, TAG, 'step ok: %{public}s', name);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'step fail: %{public}s code=%{public}d %{public}s', name, err.code, err.message);
      return false;
    }
  }

  private logRect(name: string, win: window.Window): void {
    const r = win.getWindowProperties().windowRect;
    hilog.info(DOMAIN, TAG, '%{public}s rect=%{public}d,%{public}d %{public}dx%{public}d',
      name, r.left, r.top, r.width, r.height);
  }

  private async setupHostAndPet(stage: window.WindowStage, host: window.Window): Promise<void> {
    this.mainWindow = host;
    const d: display.Display = display.getDefaultDisplaySync();
    const size: number = Math.round(d.width * 0.2); // px
    const x: number = Math.max(0, d.width - size - Math.round(d.width * 0.04));
    const y: number = Math.max(0, d.height - size - Math.round(d.height * 0.12));

    // 1) 宿主主窗：缩最小、移出屏、去装饰、置顶
    await this.tryStep('host.resize(320,72)', async (): Promise<void> => {
      await host.resize(320, 72);
    });
    await this.tryStep('host.moveWindowTo(-2000,-2000)', async (): Promise<void> => {
      await host.moveWindowTo(-2000, -2000);
    });
    this.tryStep('host.decorVisible(false)', (): void => {
      host.setWindowDecorVisible(false);
    });
    this.tryStep('host.titleButtonVisible(false)', (): void => {
      host.setWindowTitleButtonVisible(false, false, false);
    });
    await this.tryStep('host.topmost(true)', async (): Promise<void> => {
      await host.setWindowTopmost(true);
    });
    this.logRect('host(immediate)', host);

    // 2) 独立子窗：先有内容，再改外观（顺序修正）
    let sub: window.Window | undefined = undefined;
    try {
      const options: window.SubWindowOptions = {
        title: 'PetSub',
        decorEnabled: false,
        zLevelAboveParentLoosened: false
      };
      sub = await stage.createSubWindowWithOptions('PetSub', options);
      hilog.info(DOMAIN, TAG, 'step ok: createSubWindowWithOptions(PetSub)');
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'step fail: createSubWindowWithOptions code=%{public}d %{public}s', err.code, err.message);
    }
    if (sub === undefined) {
      return;
    }
    this.petSub = sub;
    const s: window.Window = sub;
    await this.tryStep('sub.setUIContent(pages/Pet)', async (): Promise<void> => {
      await s.setUIContent('pages/Pet');
    });
    await this.tryStep('sub.resize(size)', async (): Promise<void> => {
      await s.resize(size, size);
    });
    await this.tryStep('sub.moveWindowTo(x,y)', async (): Promise<void> => {
      await s.moveWindowTo(x, y);
    });
    await this.tryStep('sub.bgColor(#00000000)', async (): Promise<void> => {
      s.setWindowBackgroundColor('#00000000');
    });
    await this.tryStep('sub.mask(circle 0.48)', async (): Promise<void> => {
      const mask: Uint8Array = makeCircleMask(size);
      await s.setWindowMaskWithAlpha(mask, size, size);
    });
    await this.tryStep('sub.showWindow', async (): Promise<void> => {
      await s.showWindow();
    });
    this.logRect('sub(immediate)', s);
    hilog.info(DOMAIN, TAG, 'pet subwindow setup end');

    // 3) 沉降复读（WM 异步生效后的真实 rect）
    setTimeout((): void => {
      this.logRect('host(settled)', host);
      this.logRect('sub(settled)', s);
    }, 1500);

    // 4) 离屏二次尝试：判定钳制是否为一次性或持续约束
    setTimeout((): void => {
      host.moveWindowTo(-2000, -2000).then((): void => {
        hilog.info(DOMAIN, TAG, 'retry offscreen move resolved');
        this.logRect('host(afterRetry)', host);
      }).catch((e: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'retry offscreen move rejected: %{public}d %{public}s', e.code, e.message);
      });
    }, 2500);
  }

  onWindowStageDestroy(): void {
    this.petSub = undefined;
  }

  onForeground(): void {
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground (independent subwindow should stay)');
  }

  onDestroy(): void {
  }
}

/** 生成圆形 alpha 掩码：圆内 255、圆外 0，边缘 2px 抗锯齿。 */
function makeCircleMask(size: number): Uint8Array {
  const mask: Uint8Array = new Uint8Array(size * size);
  const cx: number = (size - 1) / 2;
  const cy: number = (size - 1) / 2;
  const r: number = size * 0.48;
  for (let y: number = 0; y < size; y++) {
    for (let x: number = 0; x < size; x++) {
      const dx: number = x - cx;
      const dy: number = y - cy;
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
