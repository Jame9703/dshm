import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD001;
const TAG: string = 'PetPoc';

@Entry
@Component
struct Pet {
  @State dragging: boolean = false;

  private logWindowStatus(source: string): void {
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      const st: number = win.getWindowStatus();
      let free: string = 'unknown';
      try {
        free = win.isInFreeWindowMode() ? 'true' : 'false';
      } catch (e) {
        free = 'unsupported';
      }
      hilog.info(DOMAIN, TAG, 'windowStatus=%{public}d freeWindow=%{public}s source=%{public}s', st, free, source);
    }).catch((e: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'query window failed: %{public}d', e.code);
    });
  }

  private beginDrag(): void {
    if (this.dragging) {
      return;
    }
    this.dragging = true;
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      // 无系统标题栏时，只能由自绘热区调用 startMoving；非自由窗口会返回 801
      win.startMoving().catch((e: BusinessError): void => {
        hilog.info(DOMAIN, TAG, 'startMoving not applicable: %{public}d %{public}s', e.code, e.message);
      }).finally((): void => {
        this.dragging = false;
      });
    }).catch((e: BusinessError): void => {
      this.dragging = false;
      hilog.error(DOMAIN, TAG, 'getLastWindow failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  private exit(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.terminateSelf().catch((e: BusinessError): void => {
      hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  @Builder
  petMenu() {
    Menu() {
      MenuItem({ content: '退出桌宠' }).onClick((): void => {
        this.exit();
      })
      MenuItem({ content: '记录窗口状态' }).onClick((): void => {
        this.logWindowStatus('menu');
      })
    }
  }

  build() {
    Stack() {
      // 桌宠本体：占满窗口的一个圆 + 眼睛；四角保持透明
      Circle()
        .width('86%')
        .height('86%')
        .fill('#FFE08A')
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
      Column({ space: 6 }) {
        Row({ space: 26 }) {
          Circle().width(14).height(14).fill('#2B2B2B')
          Circle().width(14).height(14).fill('#2B2B2B')
        }
        Text('DSHM PET').fontSize(14).fontColor('#5A4A2A')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAppear((): void => {
      hilog.info(DOMAIN, TAG, 'pet page appeared');
      this.logWindowStatus('onAppear');
    })
    // 触摸打点：穿透测试的判定依据（无 Down 日志 = 点击穿透到下层）
    .onTouch((event: TouchEvent): void => {
      const t: TouchObject | undefined = event.touches.length > 0 ? event.touches[0] : undefined;
      const typeStr: string = event.type === TouchType.Down ? 'Down'
        : event.type === TouchType.Up ? 'Up'
          : event.type === TouchType.Move ? 'Move' : 'Cancel';
      if (t !== undefined) {
        hilog.info(DOMAIN, TAG, 'touch %{public}s at display %{public}d,%{public}d', typeStr, t.displayX, t.displayY);
      } else {
        hilog.info(DOMAIN, TAG, 'touch %{public}s (no touch object)', typeStr);
      }
      if (event.type === TouchType.Down) {
        this.beginDrag();
      }
    })
    // 无标题栏时需要自己的退出入口：右键菜单（与桌宠规划一致）
    .bindContextMenu(this.petMenu, ResponseType.RightClick)
  }
}
