/**
 * Demo 单页入口：Tabs 双页签骨架（沉浸光感 / 碰一碰）+ 主题切换。
 *
 * 【页面组织】（plan R4）单页 Tabs 两页签，两个演示页常驻不卸载——
 * 碰一碰注入目标 Web 不因导航卸载（模拟按钮随时可用、挂起队列就绪即补发）。
 *
 * 【主题切换】System / Light / Dark 三档（默认 System），接 DemoTheme 单例；
 * 切 Light/Dark 时应用外观同步切换（setColorMode），System 档交回系统。
 * 材质/面板明暗不走这里——一律经 themeDark(mode, systemDark) 显式求值
 * （生产纪律：材质明暗不用 SYSTEM 档，DemoTheme 头注同一口径）。
 *
 * 【状态管理】State Management V2：@ComponentV2 + @Local（greenfield 规则）。
 *
 * @module Index
 */
import { common } from '@kit.AbilityKit';
import { DemoThemeState } from '../common/DemoTheme';
import { ThemeMode } from '../model/DemoTypes';
import { KnockDemoViewModel } from '../viewmodel/KnockDemoViewModel';
import { ImmersiveDemoView } from '../views/ImmersiveDemoView';
import { KnockDemoView } from '../views/KnockDemoView';

@Entry
@ComponentV2
struct Index {
  /** 主题状态单例（EntryAbility 喂系统明暗；此处切换档位）。 */
  @Local theme: DemoThemeState = DemoThemeState.shared();

  /**
   * 碰一碰 VM（页面级持有）：真实接收注册必须在**页签渲染前**发生——
   * 官方样本 KnockFileShare 在首页 aboutToAppear 即注册；原实现挂在碰一碰页签的
   * Web onPageEnd 之后，用户没切页签就碰 ⇒ 系统侧无接收方（实测「碰没反应」根因之一）。
   */
  @Local knockVm: KnockDemoViewModel = new KnockDemoViewModel();

  aboutToAppear(): void {
    // 上下文 + 立即注册真实接收（knockShare + dataReceive），不等任何页签/Web 就绪
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (ctx !== undefined) {
      this.knockVm.attachContext(ctx);
      this.knockVm.startKnockReceiver();
    }
  }

  aboutToDisappear(): void {
    // 页面销毁才注销（页签切换不注销：接收能力应常驻）
    this.knockVm.stopReceiver();
  }

  /** 主题档位切换钮（当前档高亮；档位字面量即按钮文案）。 */
  @Builder
  themeChip(mode: ThemeMode) {
    Text(mode)
      .fontSize(13)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.theme.themeMode === mode ? '#0A59F7' : '#1F888888')
      .fontColor(this.theme.themeMode === mode ? '#FFFFFF' : '#888888')
      .onClick((): void => {
        this.theme.setThemeMode(mode);
      })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('DSHM Demo')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        Blank()
        this.themeChip('System')
        this.themeChip('Light')
        this.themeChip('Dark')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })

      Tabs({ barPosition: BarPosition.Start }) {
        TabContent() {
          ImmersiveDemoView()
        }
        .tabBar('沉浸光感')
        TabContent() {
          // 碰一碰页签：模拟链路（US3）+ 真实接收状态行（VM 由页面持有并注入）
          KnockDemoView({ vm: this.knockVm })
        }
        .tabBar('碰一碰')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
