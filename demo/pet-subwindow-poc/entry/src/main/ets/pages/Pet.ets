import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD002;
const TAG: string = 'PetSubPoc';

@Entry
@Component
struct Pet {
  @State dragging: boolean = false;

  private drag(): void {
    if (this.dragging) {
      return;
    }
    this.dragging = true;
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      win.startMoving().catch((e: BusinessError): void => {
        hilog.info(DOMAIN, TAG, 'startMoving not applicable: %{public}d %{public}s', e.code, e.message);
      }).finally((): void => {
        this.dragging = false;
      });
    }).catch((e: BusinessError): void => {
      this.dragging = false;
      hilog.error(DOMAIN, TAG, 'getLastWindow failed: %{public}d', e.code);
    });
  }

  private exit(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf().catch((e: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}d', e.code);
    });
  }

  private logStatus(source: string): void {
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      const st: number = win.getWindowStatus();
      let free: string = 'unknown';
      try {
        free = win.isInFreeWindowMode() ? 'true' : 'false';
      } catch (e) {
        free = 'unsupported';
      }
      hilog.info(DOMAIN, TAG, 'sub windowStatus=%{public}d freeWindow=%{public}s source=%{public}s', st, free, source);
    }).catch((e: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'query failed: %{public}d', e.code);
    });
  }

  @Builder
  petMenu() {
    Menu() {
      MenuItem({ content: '退出桌宠' }).onClick((): void => {
        this.exit();
      })
      MenuItem({ content: '记录窗口状态' }).onClick((): void => {
        this.logStatus('menu');
      })
    }
  }

  build() {
    Stack() {
      Circle()
        .width('88%')
        .height('88%')
        .fill('#FFE08A')
      Column({ space: 6 }) {
        Row({ space: 24 }) {
          Circle().width(14).height(14).fill('#2B2B2B')
          Circle().width(14).height(14).fill('#2B2B2B')
        }
        Text('DSHM PET').fontSize(13).fontColor('#5A4A2A')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAppear((): void => {
      this.logStatus('onAppear');
    })
    .onTouch((event: TouchEvent): void => {
      const t: TouchObject = event.touches[0];
      hilog.info(DOMAIN, TAG, 'pet touch %{public}s at display %{public}f,%{public}f', event.type, t.displayX, t.displayY);
      if (event.type === TouchType.Down) {
        this.drag();
      }
    })
    .bindContextMenu(this.petMenu, ResponseType.RightClick)
  }
}
