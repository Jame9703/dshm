import { FeedbackRow } from 'appstate';
import { copyText } from 'platform';
import { DesktopRating } from './DesktopFeedback';

@Component
export struct DesktopReplyActions {
  @Prop messageId: string = '';
  @Prop text: string = '';
  @Prop timestamp: number = 0;
  @Prop feedbackRows: FeedbackRow[] = [];
  @Prop choosing: boolean = false;
  onWarm: () => void = (): void => {};
  onRating: (messageId: string, rating: DesktopRating) => void =
    (_messageId: string, _rating: DesktopRating): void => {};
  @State private copied: boolean = false;
  private resetCopy: number = -1;

  aboutToDisappear(): void {
    if (this.resetCopy !== -1) { clearTimeout(this.resetCopy); }
  }

  private selected(rating: DesktopRating): boolean {
    return this.feedbackRows.some((row: FeedbackRow): boolean => row.messageId === this.messageId && row.rating === rating);
  }

  private clock(): string {
    const date = new Date(this.timestamp);
    return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  private async copyReply(): Promise<void> {
    if (!(await copyText(this.text))) { return; }
    if (this.resetCopy !== -1) { clearTimeout(this.resetCopy); }
    this.copied = true;
    this.resetCopy = setTimeout((): void => { this.copied = false; this.resetCopy = -1; }, 1600);
  }

  @Builder
  private Icon(resource: Resource) {
    Image(resource).width(16).height(16).supportSvg2(true).draggable(false).accessibilityLevel('no')
  }

  @Builder
  private Rate(rating: DesktopRating, icon: Resource, activeIcon: Resource, label: string, keyPrefix: string) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      this.Icon(this.selected(rating) ? activeIcon : icon)
    }.width(28).height(28).padding(0).borderRadius(7).enabled(!this.choosing).focusOnTouch(false)
      .key(keyPrefix + (this.selected(rating) ? 'Active-' : '-') + this.messageId)
      .accessibilityText(this.selected(rating) ? '取消标记' : label).accessibilitySelected(this.selected(rating))
      .onFocus(this.onWarm).onHover((hovered: boolean): void => { if (hovered) { this.onWarm(); } })
      .onClick((): void => { this.onRating(this.messageId, rating); })
  }

  build() {
    Row({ space: 3 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.Icon(this.copied ? $r('app.media.dsh_dock_check') : $r('app.media.dsh_session_copy'))
      }.width(28).height(28).padding(0).borderRadius(7).focusOnTouch(false)
        .key('desktopReplyCopy-' + this.messageId).accessibilityText(this.copied ? '已复制' : '复制')
        .onClick((): void => { this.copyReply(); })
      this.Rate(DesktopRating.POSITIVE, $r('app.media.dsh_feedback_like_outline'),
        $r('app.media.dsh_feedback_like_fill'), '好的回答', 'desktopReplyLike')
      this.Rate(DesktopRating.NEGATIVE, $r('app.media.dsh_feedback_dislike_outline'),
        $r('app.media.dsh_feedback_dislike_fill'), '有问题的回答', 'desktopReplyDislike')
      if (this.timestamp > 0) {
        Text(this.clock()).fontSize(12).fontColor($r('sys.color.font_tertiary')).margin({ left: 4 })
      }
    }.width('100%').constraintSize({ maxWidth: 712 })
  }
}
