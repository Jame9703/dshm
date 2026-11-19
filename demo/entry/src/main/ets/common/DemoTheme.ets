/**
 * Demo 主题状态与明暗求值（单源）。
 *
 * 【生产对照】生产 WebApp.ets 的 themeMode（'light' | 'dark'）由 web 侧外观跟随桥
 * 回传；demo 简化为「跟随系统明暗 + demo 内切换开关」（观感演示用，spec 假设节）。
 *
 * 【明暗显式求值（生产纪律）】材质/菜单面板的明暗不用 WithTheme 的 SYSTEM 档——
 * 2026-10-11 生产真机结论：SYSTEM 档实测仍给深色玻璃；必须先按 ThemeMode +
 * 系统明暗显式求出 themeDark，再把 LIGHT/DARK 显式传给 WithTheme/材质调用链。
 *
 * 【状态管理】State Management V2（greenfield 规则）：@ObservedV2 + @Trace 的
 * 单例状态，EntryAbility（onConfigurationUpdate 喂系统明暗）与页面（切换开关）
 * 共写，@ComponentV2 视图读 @Trace 属性即获响应式刷新。
 *
 * @module DemoTheme
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeMode } from '../model/DemoTypes';

/**
 * Demo 主题状态（V2 observed 单例）。
 * themeMode：demo 内可切换的三档主题（默认 System）；
 * systemDark：系统当前明暗（true=深色），由 EntryAbility.onConfigurationUpdate 跟踪喂入。
 */
@ObservedV2
export class DemoThemeState {
  /** demo 内主题档位（默认 System：跟随系统明暗）。 */
  @Trace themeMode: ThemeMode = 'System';
  /** 系统当前明暗（true=深色）；System 档 themeDark 求值依据。 */
  @Trace systemDark: boolean = false;
  private static inst: DemoThemeState | undefined = undefined;

  /** 单例取用（EntryAbility / Index / 各视图共用同一份状态）。 */
  static shared(): DemoThemeState {
    if (DemoThemeState.inst === undefined) {
      DemoThemeState.inst = new DemoThemeState();
    }
    return DemoThemeState.inst;
  }

  /**
   * 切换主题档位；同步把应用外观也切过去（demo 自身 UI 跟随，观感演示）。
   * System 档交回系统（COLOR_MODE_NOT_SET）；失败不影响材质明暗演示（材质明暗
   * 走 themeDark 显式求值，与这里的应用外观设置互不耦合）。
   */
  setThemeMode(mode: ThemeMode): void {
    this.themeMode = mode;
    try {
      const colorMode: ConfigurationConstant.ColorMode =
        mode === 'Dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : mode === 'Light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
            : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      getContext().getApplicationContext().setColorMode(colorMode);
    } catch (e) {
      // 外观设置失败静默：不影响材质/面板明暗的显式求值链
    }
  }
}

/**
 * 明暗显式求值（生产纪律：材质/面板明暗不用 SYSTEM 档）。
 * Light→false、Dark→true 显式指定；System 档落回系统明暗（systemDark 由
 * EntryAbility.onConfigurationUpdate 跟踪）。
 */
export function themeDark(mode: ThemeMode, systemDark: boolean): boolean {
  if (mode === 'Light') {
    return false;
  }
  if (mode === 'Dark') {
    return true;
  }
  return systemDark;
}
