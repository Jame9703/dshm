import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/** 窗口状态数字取自 window.WindowStatusType 的官方枚举值。 */
function statusName(value: number): string {
  switch (value) {
    case 1: return '1 FULL_SCREEN';
    case 2: return '2 MAXIMIZE';
    case 3: return '3 MINIMIZE';
    case 4: return '4 FLOATING';
    case 5: return '5 SPLIT_SCREEN';
    default: return String(value) + ' UNKNOWN';
  }
}

@Entry
@Component
struct Index {
  @State windowStatus: string = '未读取';
  @State freeWindow: string = '-';
  @State readError: string = '';

  private refresh(): void {
    this.readError = '';
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window): void => {
        this.windowStatus = statusName(win.getWindowStatus());
        try {
          this.freeWindow = win.isInFreeWindowMode() ? 'true' : 'false';
        } catch (e) {
          this.freeWindow = 'unsupported';
        }
      }).catch((e: BusinessError): void => {
        this.readError = 'getLastWindow 失败: ' + e.code + ' ' + e.message;
      });
    } catch (e) {
      this.readError = '读取窗口状态异常';
    }
  }

  aboutToAppear(): void {
    this.refresh();
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('平板「PC 应用」最小复现').fontSize(24).fontWeight(FontWeight.Bold)
        Text('manifest 关键声明').fontSize(18).fontWeight(FontWeight.Medium)
        Text('module.deviceTypes = ["tablet", "2in1"]  （不含 "phone"）')
          .fontSize(14).fontColor(Color.Blue)
        Text('abilities.EntryAbility.supportWindowMode = 未声明（缺省 ⇒ fullscreen/split/floating）')
          .fontSize(14).fontColor(Color.Blue)

        Text('实时窗口读数').fontSize(18).fontWeight(FontWeight.Medium)
        Text('windowStatus: ' + this.windowStatus).fontSize(16)
        Text('isInFreeWindowMode: ' + this.freeWindow).fontSize(16)
        if (this.readError.length > 0) {
          Text(this.readError).fontSize(14).fontColor(Color.Red)
        }
        Button('刷新窗口状态').onClick((): void => { this.refresh(); })

        Text('请按以下步骤取证').fontSize(18).fontWeight(FontWeight.Medium)
        Text('1. 上滑进入最近任务：查看本应用任务卡片是否带「PC 应用」角标。')
          .fontSize(14)
        Text('2. 分屏：应用全屏时，从屏幕底部上滑至左上方热区，选择另一个支持分屏的应用。'
          + '观察 windowStatus 是否变为 5 SPLIT_SCREEN，且窗口宽度约为屏幕一半。')
          .fontSize(14)
        Text('3. 小窗/悬浮窗：从最近任务、Dock 或多窗手势尝试「悬浮窗」，观察是否不可用。')
          .fontSize(14)
        Text('预期：变体 A（含 2in1、不含 phone）被系统判为 PC 应用，平板上不支持悬浮窗；'
          + '变体 B（仅 tablet）不被判为 PC 应用。')
          .fontSize(14).fontColor(Color.Gray)
      }
      .width('100%')
      .padding(20)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
