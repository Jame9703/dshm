import { LengthMetrics } from '@kit.ArkUI';
import { controlMaterial } from 'platform';
import { StartupFrameCallback } from '../common/DesktopStartup';
import type { DesktopAccountNotice, DesktopAccountNoticeAction } from './DesktopAccountNotices';

@Component
export struct DesktopAccountNoticeCard {
  @Prop notice: DesktopAccountNotice;
  @Prop behind: number = 0;
  @Prop copyHeight: number = 220;
  onDisplayed: (id: string) => void = (_id: string): void => {};
  onAccount: (id: string) => void = (_id: string): void => {};
  onDismiss: (id: string) => void = (_id: string): void => {};
  private visible: boolean = false;

  aboutToDisappear(): void { this.visible = false; }

  private onVisibility(shown: boolean): void {
    this.visible = shown;
    if (shown) {
      this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
        if (this.visible) { this.onDisplayed(this.notice.id); }
      }));
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.behind >= 2) {
        Row().width('94%').height(17).borderRadius(15).backgroundColor($r('app.color.workspace_selection'))
          .accessibilityLevel('no')
      }
      if (this.behind >= 1) {
        Row().width('97%').height(17).borderRadius(15).margin({ top: this.behind >= 2 ? 4 : 0 })
          .backgroundColor($r('app.color.workspace_panel')).accessibilityLevel('no')
      }
      Column({ space: 8 }) {
        Row({ space: 4 }) {
          Image($r('app.media.dsh_account_notice')).width(14).height(14).supportSvg2(true)
            .accessibilityLevel('no')
          Text(this.notice.title).key('desktopAccountNoticeTitle').fontSize(14)
            .fontWeight(FontWeight.Medium).layoutWeight(1)
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_dock_close')).width(10).height(10).accessibilityLevel('no')
          }.key('desktopAccountNoticeClose').width(24).height(24).padding(0).borderRadius(6)
            .accessibilityText($r('app.string.desktop_account_notice_close'))
            .onClick((): void => { this.onDismiss(this.notice.id); })
        }.width('100%').alignItems(VerticalAlign.Top)
        if (this.notice.body) {
          Scroll() {
            Text(this.notice.body).key('desktopAccountNoticeBody').width('100%')
              .fontSize(14).lineHeight(22).fontColor($r('sys.color.font_secondary'))
          }.width('100%').constraintSize({ maxHeight: this.copyHeight }).scrollBar(BarState.Auto)
        }
        if (this.notice.actions.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(6) } }) {
            ForEach(this.notice.actions, (action: DesktopAccountNoticeAction, index: number): void => {
              Button(action.label, { buttonStyle: action.primary ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL })
                .key('desktopAccountNoticeAction-' + index).fontSize(13).constraintSize({ minHeight: 28, maxWidth: '100%' })
                .onClick((): void => {
                  if (action.target === 'dismiss') { this.onDismiss(this.notice.id); }
                  else { this.onAccount(this.notice.id); }
                })
            }, (action: DesktopAccountNoticeAction, index: number): string => index + ':' + action.target + ':' + action.label)
          }.width('100%')
        }
      }.key('desktopAccountNotice').width('100%').padding(16).margin({ top: Math.min(2, this.behind) * 4 })
        .borderRadius(16).shadow({ radius: 16, color: '#28000000', offsetY: 3 })
        .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : undefined)
        .systemMaterial(controlMaterial()).alignItems(HorizontalAlign.Start)
        .onVisibleAreaChange([0], (visible: boolean): void => { this.onVisibility(visible); })
    }.width('100%')
  }
}
