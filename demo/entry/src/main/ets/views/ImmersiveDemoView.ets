/**
 * 沉浸光感·弹窗演示视图（US1 + US2）：4 形态弹窗按钮区 + Web 演示区
 * （网页右键/长按菜单原生接管）。
 *
 * 【状态管理】State Management V2：@ComponentV2 + @Local 挂 @ObservedV2
 * 视图模型，@Trace 成员变化驱动状态行刷新。
 *
 * @module ImmersiveDemoView
 */
import { WEB_CONTEXT_MENU_COMPAT } from '../service/WebMenuHost';
import { ImmersiveDemoViewModel } from '../viewmodel/ImmersiveDemoViewModel';

@ComponentV2
export struct ImmersiveDemoView {
  /** 视图模型（@ObservedV2 实例：@Trace lastForm 驱动状态行）。 */
  @Local vm: ImmersiveDemoViewModel = new ImmersiveDemoViewModel();

  aboutToAppear(): void {
    // UI 上下文注入：弹窗动作经它调 showAlertDialog（生产同款 getUIContext 链）
    this.vm.attach(this.getUIContext());
  }

  build() {
    Column({ space: 12 }) {
      Text('AlertDialog 材质演示（THICK·非交互）')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Text('四形态逐位对齐生产 WebApp.ets 四处弹窗；API>=26 挂玻璃材质，'
        + '<26 纯色兜底，材质构造异常不崩（FR-002/FR-003）。')
        .fontSize(12)
        .fontColor('#888888')
      Button('形态一：确认类双按钮（登录确认）')
        .width('100%')
        .onClick((): void => {
          this.vm.showConfirmLoginDialog();
        })
      Button('形态二：确认类双按钮（外开确认）')
        .width('100%')
        .onClick((): void => {
          this.vm.showOpenExternalConfirmDialog();
        })
      Button('形态三：失败提示（外开失败）')
        .width('100%')
        .onClick((): void => {
          this.vm.showOpenFailedDialog();
        })
      Button('形态四：失败提示（预览未受理）')
        .width('100%')
        .onClick((): void => {
          this.vm.showPreviewFailedDialog();
        })
      Text(`最近动作：${this.vm.lastForm.length > 0 ? this.vm.lastForm : '（尚未弹出）'}`)
        .fontSize(12)
        .fontColor('#888888')
      Divider()
      Text('网页菜单接管演示（THIN 材质·语境菜单）')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Text('长按/右键下方五类对象（链接/图片/输入框/选区/空白区），菜单锚定触点弹出、'
        + '明暗随主题显式指定；菜单项空集回退系统默认菜单（FR-004/FR-005）。')
        .fontSize(12)
        .fontColor('#888888')
      Web({ src: $rawfile('immersive-demo.html'), controller: this.vm.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        // 右键/长按菜单接管前提：开启默认菜单（API 24+ typeof 守卫，生产 :180-188 同款）
        .attributeModifier(WEB_CONTEXT_MENU_COMPAT)
        .onContextMenuShow((event?: OnContextMenuShowEvent): boolean => {
          return this.vm.handleContextMenuShow(event);
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
