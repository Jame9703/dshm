import type { DesktopTranscriptDisclosure } from './DesktopTranscriptPresentation';

@Component
export struct DesktopTranscriptDisclosureRow {
  @Prop disclosure: DesktopTranscriptDisclosure | undefined = undefined;
  @Prop fontSize: number = 14;
  onToggle: () => void = (): void => {};

  private label(): Resource {
    if (this.disclosure?.status === 'failed') { return $r('app.string.desktop_transcript_process_failed'); }
    if (this.disclosure?.status === 'stopped') { return $r('app.string.desktop_transcript_process_stopped'); }
    const total = Math.floor((this.disclosure?.elapsedMs ?? 0) / 1000);
    if (total === 0) { return $r('app.string.desktop_transcript_process_completed'); }
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor(total / 60) % 60;
    const seconds = total % 60;
    if (hours > 0) { return $r('app.string.desktop_transcript_process_hours', hours, minutes, seconds); }
    if (minutes > 0) { return $r('app.string.desktop_transcript_process_minutes', minutes, seconds); }
    return $r('app.string.desktop_transcript_process_seconds', seconds);
  }

  @Builder
  private Status() {
    Row({ space: 4 }) {
      Text(this.label()).fontSize(this.fontSize).fontColor($r('sys.color.font_tertiary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .key(`desktopTranscriptDisclosureLabel-${this.disclosure?.turn ?? 0}`)
      if (this.disclosure?.canToggle) {
        Image(this.disclosure.open ? $r('app.media.dsh_queue_chevron_up_outline') :
          $r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14)
          .fillColor($r('sys.color.font_tertiary')).accessibilityLevel('no')
      }
    }.width('100%').justifyContent(FlexAlign.Start)
  }

  build() {
    Column() {
      if (this.disclosure?.canToggle) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          this.Status()
        }.key(`desktopTranscriptDisclosure-${this.disclosure.turn}`).width('100%')
          .height(this.fontSize + 19).padding({ bottom: 6 }).borderRadius(6)
          .accessibilityText(this.label()).accessibilitySelected(this.disclosure.open).focusOnTouch(false)
          .onClick(this.onToggle)
      } else {
        Row() { this.Status() }.key(`desktopTranscriptDisclosure-${this.disclosure?.turn ?? 0}`).width('100%')
          .height(this.fontSize + 19).padding({ bottom: 6 })
      }
      Divider().width('100%').strokeWidth(0.5).color($r('sys.color.comp_divider'))
    }.width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
  }
}
