import { accessibility } from '@kit.AccessibilityKit';

export const DESKTOP_QUOTA_TOAST_HOLD_MS: number = 3000;
export const DESKTOP_QUOTA_TOAST_FADE_MS: number = 1000;

@Component
export struct DesktopQuotaToast {
  @Prop message: ResourceStr = $r('app.string.desktop_transcript_failure_quota');
  @Prop fading: boolean = false;
  @Prop showWarningIcon: boolean = true;

  aboutToAppear(): void {
    const name: string | undefined = this.getUIContext().getHostContext()?.applicationInfo.name;
    if (name === undefined) { return; }
    const event: accessibility.EventInfo = new accessibility.EventInfo('announceForAccessibility', name, 'common');
    if (typeof this.message === 'string') {
      event.textAnnouncedForAccessibility = this.message;
    } else {
      event.textResourceAnnouncedForAccessibility = this.message;
    }
    accessibility.sendAccessibilityEvent(event).catch((): void => {});
  }

  build() {
    Row({ space: 10 }) {
      if (this.showWarningIcon) {
        Image($r('app.media.dsh_quota_warning_outline')).key('desktopQuotaToastWarning')
          .width(18).height(18).supportSvg2(true).draggable(false).accessibilityLevel('no')
      }
      Text(this.message).key('desktopQuotaToastMessage').fontSize(14).lineHeight(22)
        .fontColor($r('sys.color.font_primary')).flexShrink(1)
    }.key('desktopQuotaToast').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .borderRadius(12).backgroundColor($r('app.color.workspace_panel')).shadow(ShadowStyle.OUTER_DEFAULT_MD)
      .constraintSize({ maxWidth: 640 }).hitTestBehavior(HitTestMode.None)
      .accessibilityGroup(true)
      .opacity(this.fading ? 0 : 1).animation({ duration: DESKTOP_QUOTA_TOAST_FADE_MS, curve: Curve.Ease })
      .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
  }
}

@Component
export struct DesktopAccountQuotaDialog {
  onDismiss: () => void = (): void => {};
  onTopUp: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_account_quota_title')).key('desktopAccountQuotaTitle')
          .fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor($r('sys.color.font_primary'))
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14)
            .draggable(false).supportSvg2(true).accessibilityLevel('no')
        }.key('desktopAccountQuotaClose').width(28).height(28).padding(0).borderRadius(6)
          .focusOnTouch(false).accessibilityText($r('app.string.desktop_account_quota_close'))
          .onClick(this.onDismiss)
      }.width('100%').padding({ top: 22, bottom: 12 })
      Text($r('app.string.desktop_account_quota_description')).key('desktopAccountQuotaDescription')
        .width('100%').fontSize(14).lineHeight(22).fontColor($r('sys.color.font_primary'))
      Row({ space: 8 }) {
        Button($r('app.string.desktop_account_quota_cancel'), { type: ButtonType.Normal })
          .key('desktopAccountQuotaCancel').height(36).padding({ left: 14, right: 14 })
          .fontSize(14).fontColor($r('sys.color.font_primary')).backgroundColor(Color.Transparent)
          .border({ width: 0.5, radius: 8, color: $r('app.color.workspace_border') })
          .focusOnTouch(false).onClick(this.onDismiss)
        Button($r('app.string.desktop_account_quota_top_up'), {
          type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED
        })
          .key('desktopAccountQuotaTopUp').height(36).padding({ left: 14, right: 14 })
          .fontSize(14).borderRadius(8).focusOnTouch(false).onClick(this.onTopUp)
      }.width('100%').justifyContent(FlexAlign.End).margin({ top: 20 })
    }.key('desktopAccountQuotaDialog').width('100%').padding({ left: 24, right: 24, bottom: 24 })
      .alignItems(HorizontalAlign.Start).accessibilityRole(AccessibilityRoleType.ALERT_DIALOG)
  }
}
