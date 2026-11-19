/**
 * Demo 入口 Ability（脚手架改写）。
 *
 * 【职责（对齐任务 T007）】
 *   1. 主窗加载 pages/Index（单页 Tabs 双页签骨架的入口）；
 *   2. onConfigurationUpdate 跟踪系统明暗，喂 DemoTheme.systemDark
 *      （System 档 themeDark 显式求值的依据，生产外观跟随桥的 demo 简化）；
 *   3. 启动一次性写 diag-material 能力读数（sdk/supported/level；API<26 记 below26）
 *      ——生产 WebApp.ets aboutToAppear 的沉浸光感能力探针逐位复刻。
 *
 * @module EntryAbility
 */
import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Diag } from '../service/Diag';
import { DemoKnockShareReceiver } from '../service/DemoKnockShareReceiver';
import { DemoThemeState } from '../common/DemoTheme';

const DOMAIN: number = 0x0000;
const TAG: string = 'DSHM-Demo';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 三探针的 filesDir 一次性喂入（先于任何诊断写）
    Diag.init(this.context);
    // 启动一次性沉浸光感能力读数（diag-material）
    this.writeMaterialProbe();
    // 初始系统明暗喂入（onConfigurationUpdate 只接住后续变化，冷启动这拍要自己读）
    this.applySystemDark(this.readInitialColorMode());
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 主窗就绪：加载单页 Tabs 双页签骨架（沉浸光感 / 碰一碰）
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    // 【碰一碰接收：建窗即注册（2026-11-17 对照官方样本 KnockFileShare）】
    // 官方在首页 aboutToAppear 注册；本实现提前到建窗，并用 windowStage 的**真实主窗 id**
    // （不依赖页面是否已加载，也不依赖 getLastWindow）。原「碰一碰页签就绪后才注册」在
    // 「未切页签就碰」时系统侧无接收方 ⇒ 文件落到系统「华为分享」文件夹（实测症状）。
    try {
      const mainWin: window.Window = windowStage.getMainWindowSync();
      const mainWindowId: number = mainWin.getWindowProperties().id;
      DemoKnockShareReceiver.bootstrap(this.context, mainWindowId, (detail: string): void => {
        Diag.knock(detail);
      });
      Diag.knock(`ability bootstrap mainWindowId=${mainWindowId}`);
    } catch (e) {
      Diag.knock(`ability bootstrap err ${(e as Error).message}`);
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  /**
   * 系统配置变化（明暗/字号等）：只关心明暗——喂 DemoTheme.systemDark。
   * System 档下材质/面板明暗靠它显式求值；Light/Dark 档不受影响（显式指定优先）。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    // Configuration.colorMode 在 SDK 类型面为可缺省：缺省时保持当前系统明暗
    const mode: ConfigurationConstant.ColorMode | undefined = newConfig.colorMode;
    if (mode !== undefined) {
      this.applySystemDark(mode);
    }
  }

  /** 冷启动读一次当前系统明暗（context.config 可能缺省：按未设置处理）。 */
  private readInitialColorMode(): ConfigurationConstant.ColorMode {
    const cfg: Configuration | undefined = this.context.config;
    if (cfg === undefined) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
    const mode: ConfigurationConstant.ColorMode | undefined = cfg.colorMode;
    return mode === undefined ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET : mode;
  }

  /** 系统明暗 → DemoTheme.systemDark（true=深色；NOT_SET/LIGHT 均 false）。 */
  private applySystemDark(colorMode: ConfigurationConstant.ColorMode): void {
    DemoThemeState.shared().systemDark =
      colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /**
   * 启动一次性沉浸光感能力探针（生产 WebApp.ets aboutToAppear 逐位复刻）：
   * isImmersiveMaterialSupported / getGlobalMaterialLevel 都是 API 26 起；
   * 低版本设备记 below26 即可（材质工厂本来就退回 undefined）。
   */
  private writeMaterialProbe(): void {
    try {
      if (deviceInfo.sdkApiVersion >= 26) {
        Diag.material(`sdk=${deviceInfo.sdkApiVersion}`
          + ` supported=${uiMaterial.isImmersiveMaterialSupported()}`
          + ` level=${uiMaterial.getGlobalMaterialLevel()}`);
      } else {
        Diag.material(`sdk=${deviceInfo.sdkApiVersion} below26`);
      }
    } catch (e) {
      Diag.material(`probe-error ${(e as Error).message}`);
    }
  }
}
