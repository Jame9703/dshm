import { hilog } from '@kit.PerformanceAnalysisKit';
import EntryAbility from '../entryability/EntryAbility';

const DOMAIN: number = 0xD002;
const TAG: string = 'PetSubPoc';

/**
 * 宿主主窗页面 —— B1 取证版。
 * onTouch 全量打点（Q3 穿透落点证明：子窗掩码外的点击应落到本页并留痕）；
 * Click 计数第 2 次触发 minimizeHost（Q6 触发器，避免与 Q3 的第 1 次穿透点击混淆）。
 */
@Entry
@Component
struct Host {
  @State clickCount: number = 0;

  build() {
    Column() {
      Text('host').fontSize(12).fontColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .justifyContent(FlexAlign.Center)
    .onTouch((event: TouchEvent): void => {
      const t: TouchObject = event.touches[0];
      hilog.info(DOMAIN, TAG, 'host touch %{public}s at display %{public}f,%{public}f', event.type, t.displayX, t.displayY);
      if (event.type === TouchType.Up) {
        this.clickCount += 1;
        hilog.info(DOMAIN, TAG, 'host click#%{public}d', this.clickCount);
        if (this.clickCount >= 2) {
          const ab: EntryAbility | undefined = EntryAbility.getInstance();
          if (ab !== undefined) {
            ab.minimizeHost();
          }
        }
      }
    })
  }
}
