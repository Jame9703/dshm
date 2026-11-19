/**
 * 碰一碰·演示视图（US3 模拟链路 + US4 真实接收）：Web 输入区 + 模拟按钮×2 +
 * 挂起/注入/注册状态行。
 *
 * 【装配】Web 加载 rawfile 'knock-demo.html'（file-intake 演示页，T014）；垫片经
 * javaScriptOnDocumentStart 注册（scriptRules ['*']，生产 WebApp.ets :5469 同一注册形态）
 * ——document-start 保证 __DSHM_KNOCK__ 先于页面脚本就位，注入才有落点。
 *
 * 【控制器接线】Web 构造用 VM 自持的 controller；onControllerAttached 把控制器注入 VM
 * （与 ImmersiveDemoView 同一装配风格：视图负责生命周期，VM 负责编排）。
 * onPageBegin/onPageEnd 同步 VM 的就绪判据：重载窗口期间点按钮走挂起队列，就绪后补发。
 *
 * 【生命周期归属（2026-11-17 对照官方样本修订）】VM 由 Index 持有（@Param 注入）：
 * 真实接收入器在 **Index.aboutToAppear** 注册（不等本页签渲染 / Web 就绪，官方同此），
 * 注销在 Index.aboutToDisappear；本视图只做装配与状态展示，不持有注册生命周期。
 *
 * 【状态管理】State Management V2：@ComponentV2 + @Local 挂 @ObservedV2 视图模型，
 * @Trace 成员（status/lastInject/pendingCount/receiverState）驱动状态行刷新。
 *
 * @module KnockDemoView
 */
import { common } from '@kit.AbilityKit';
import { KNOCK_SHIM_SCRIPT } from '../service/KnockShim';
import { KnockDemoViewModel } from '../viewmodel/KnockDemoViewModel';

@ComponentV2
export struct KnockDemoView {
  /** 视图模型（Index 持有并注入：接收注册须在本页签渲染前发生，见 VM 头注）。 */
  @Require @Param vm: KnockDemoViewModel;

  /**
   * document-start 注入清单（T015 垫片）：scriptRules ['*'] 对本页所有文档生效。
   * 类型沿用 ArkWeb 全局 ScriptItem（生产 pickerShimScripts 同一写法）。
   */
  private shimScripts: Array<ScriptItem> = [
    { script: KNOCK_SHIM_SCRIPT, scriptRules: ['*'] }
  ];

  aboutToAppear(): void {
    // 上下文注入：rawfile 读取与 DocumentViewPicker 都要它（VM 内部统一走 this.ctx）。
    // Index.aboutToAppear 已注入过一次（接收注册要用），此处幂等覆盖为同一对象。
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (ctx !== undefined) {
      this.vm.attachContext(ctx);
    }
    // 真实接收注册不在本视图：由 Index.aboutToAppear 立即调用（对齐官方示例时机）
  }

  aboutToDisappear(): void {
    // 接收器生命周期归 Index（aboutToDisappear 注销）：本视图可能随页签切换重建，
    // 在此注销会把「碰一碰页签未显示期间的接收能力」误关掉
  }

  build() {
    Column({ space: 12 }) {
      Text('碰一碰传文件演示（模拟链路·单机必现）')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Text('两路来源（内置样例 / 系统文件选择器）→ 16MiB 校验 → 同一注入出口'
        + '（KnockShim.injectFile）→ 垫片合成 paste → 附件 chip 进输入区，不自动发送（FR-007/FR-009）。')
        .fontSize(12)
        .fontColor('#888888')

      Row({ space: 8 }) {
        Button('模拟碰一碰（内置样例）')
          .fontSize(14)
          .layoutWeight(1)
          .onClick((): void => {
            this.vm.simulateFromSample();
          })
        Button('模拟碰一碰（选文件）')
          .fontSize(14)
          .layoutWeight(1)
          .onClick((): void => {
            this.vm.simulateFromPicker();
          })
      }
      .width('100%')

      Text(`状态：${this.vm.status}`)
        .fontSize(12)
        .fontColor('#888888')
      Text(`挂起队列：${this.vm.pendingCount} / 10    最近注入：${this.vm.lastInject}`)
        .fontSize(12)
        .fontColor('#888888')
      // 注册状态行：建窗即注册（EntryAbility），onPhase 推进 receiverState 即时刷新
      Text(`真实接收注册状态：${this.vm.receiverStateLabel()}`)
        .fontSize(12)
        .fontColor('#888888')
      // diag 最近 8 行（无 hdc 也能现场自证：注册是否成功 / 是否收到 target / 注入路由）
      Text(`diag-knock 最近 8 行：\n${this.vm.diagFeed}`)
        .fontSize(11)
        .fontColor('#666666')
        .maxLines(10)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Web({ src: $rawfile('knock-demo.html'), controller: this.vm.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        // 垫片 document-start 注册（生产 :5469 同一形态）；页面脚本前就位才有落点
        .javaScriptOnDocumentStart(this.shimScripts)
        .onControllerAttached((): void => {
          this.vm.attachController(this.vm.webController);
        })
        .onPageBegin((): void => {
          this.vm.onWebPageBegin();
        })
        .onPageEnd((): void => {
          this.vm.onWebPageEnd();
        })
        .layoutWeight(1)
        .width('100%')
        .borderRadius(8)
        .clip(true)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }
}
