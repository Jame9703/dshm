import { desktopMenuOptions } from './DesktopMenuOptions';

@Component
export struct DesktopTimelineHelp {
  @Prop label: Resource = $r('app.string.desktop_timeline_metric_estimate_help');
  @Prop message: ResourceStr = '';
  @Prop summary: ResourceStr = '';
  @Prop buttonKey: string = '';
  @Prop popupKey: string = '';
  @State private open: boolean = false;

  @Builder
  private HelpText() {
    Column({ space: 7 }) {
      if (this.summary) { Text(this.summary).fontSize(13).fontWeight(FontWeight.Medium) }
      Text(this.message).fontSize(12)
    }.key(this.popupKey).constraintSize({ maxWidth: 320 }).padding(12).alignItems(HorizontalAlign.Start)
  }

  build() {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image($r('app.media.dsh_question_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
    }.key(this.buttonKey).width(28).height(28).padding(0).accessibilityText(this.label)
      .onClick((): void => { this.open = !this.open; })
      .bindPopup(this.open, { builder: this.HelpText(), placement: Placement.Top,
        targetSpace: 6, enableArrow: false, focusable: true, mask: false, autoCancel: true,
        systemMaterial: desktopMenuOptions(Placement.Top).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible) { this.open = false; } } })
  }
}
