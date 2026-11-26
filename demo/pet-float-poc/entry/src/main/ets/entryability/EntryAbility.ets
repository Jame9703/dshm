import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD001;
const TAG: string = 'PetPoc';

/**
 * PC/2in1 桌宠 POC：
 *  - 自由窗口 + 无标题栏/三键 + 透明容器 + 去阴影 + 置顶
 *  - 窗口尺寸按屏幕宽度约 20%，放在右下角
 *  - 每步独立 try/catch 并打点：一次运行拿到全部能力读数，单点失败不中断链路
 *  - 不写业务逻辑；仅验证公开 API 的实际效果
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Pet', (err: BusinessError): void => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}d %{public}s', err.code, err.message);
        return;
      }
      windowStage.getMainWindow().then((win: window.Window): void => {
        this.setupPetWindow(win);
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

  private buildMask(mw: number, mh: number): Uint8Array {
    const mask: Uint8Array = new Uint8Array(mw * mh);
    mask.fill(255);
    const corner: number = Math.min(64, Math.floor(mw / 8));
    for (let yy: number = 0; yy < corner; yy++) {
      for (let xx: number = 0; xx < corner; xx++) {
        mask[yy * mw + xx] = 0;
        mask[yy * mw + (mw - 1 - xx)] = 0;
        mask[(mh - 1 - yy) * mw + xx] = 0;
        mask[(mh - 1 - yy) * mw + (mw - 1 - xx)] = 0;
      }
    }
    return mask;
  }

  private async setupPetWindow(win: window.Window): Promise<void> {
    const d: display.Display = display.getDefaultDisplaySync();
    const size: number = Math.max(220, Math.round(d.width * 0.2));
    const x: number = Math.max(0, d.width - size - Math.round(d.width * 0.04));
    const y: number = Math.max(0, d.height - size - Math.round(d.height * 0.12));
    hilog.info(DOMAIN, TAG, 'display=%{public}dx%{public}d size=%{public}d pos=%{public}d,%{public}d',
      d.width, d.height, size, x, y);

    await this.tryStep('resize', async (): Promise<void> => {
      await win.resize(size, size);
    });
    await this.tryStep('moveWindowTo', async (): Promise<void> => {
      await win.moveWindowTo(x, y);
    });
    // 迭代2：不再调用 setWindowContainerColor（隔离容器色变量；
    // 上一轮已证 8 位 ARGB 被 401 拒、6 位不透明可过）
    hilog.info(DOMAIN, TAG, 'containerColor skipped (iteration2: unset)');
    await this.tryStep('decorVisible(false)', (): void => {
      win.setWindowDecorVisible(false);
    });
    await this.tryStep('titleButtonVisible(false)', (): void => {
      win.setWindowTitleButtonVisible(false, false, false);
    });
    await this.tryStep('backgroundColor#00000000', (): void => {
      win.setWindowBackgroundColor('#00000000');
    });
    await this.tryStep('shadowEnabled(false)', async (): Promise<void> => {
      await win.setWindowShadowEnabled(false);
    });
    await this.tryStep('topmost(true)', async (): Promise<void> => {
      await win.setWindowTopmost(true);
    });
    hilog.info(DOMAIN, TAG, 'pet window setup end');

    // 延时探针 1（6s）：红色透明底，判别 alpha 是否被解析（红卡=alpha 丢弃；透出=alpha 生效）
    setTimeout((): void => {
      this.tryStep('probe bgColor#00FF0000', (): void => {
        win.setWindowBackgroundColor('#00FF0000');
      });
    }, 6000);
    // 延时探针 2（12s）：恢复透明底
    setTimeout((): void => {
      this.tryStep('probe restore bgColor#00000000', (): void => {
        win.setWindowBackgroundColor('#00000000');
      });
    }, 12000);
    // 延时探针 3（18s）：主窗逐像素 alpha 掩码（文档称主窗 1300004，实测验证）
    setTimeout((): void => {
      this.tryStep('probe setWindowMaskWithAlpha(corners=0)', async (): Promise<void> => {
        await win.setWindowMaskWithAlpha(this.buildMask(size, size), size, size);
      });
    }, 18000);
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onDestroy(): void {
  }
}
