import { common } from '@kit.AbilityKit';
import { FeedbackRow } from 'appstate';
import { copyText, shareText } from 'platform';
import { DesktopRating } from './DesktopFeedback';
import { DesktopReplyMedia, desktopReplyMediaText } from './DesktopReplyMedia';
import { DesktopChatUsageTurn } from './DesktopChatUsage';
import type { DesktopChatTurnUsage } from './DesktopChatUsageModel';

@Component
export struct DesktopReplyActions {
  @Prop @Watch('observeMedia') messageId: string = '';
  @Prop @Watch('observeMedia') scopeId: string = '';
  @Prop @Watch('updateMediaText') text: string = '';
  replyMedia?: DesktopReplyMedia;
  @Prop timestamp: number = 0;
  @Prop turnUsage?: DesktopChatTurnUsage = undefined;
  @Prop compactUsage: boolean = false;
  @Prop availableWidth: number = 420;
  @Prop feedbackRows: FeedbackRow[] = [];
  @Prop choosing: boolean = false;
  @Prop canFork: boolean = false;
  @Prop forking: boolean = false;
  onFork: () => void = (): void => {};
  onWarm: () => void = (): void => {};
  onRating: (messageId: string, rating: DesktopRating) => void =
    (_messageId: string, _rating: DesktopRating): void => {};
  @State private copied: boolean = false;
  @State private mediaTextAvailable: boolean = false;
  @State private reading: boolean = false;
  @State private sharing: boolean = false;
  private plainText: string = '';
  private mounted: boolean = false;
  private resetCopy: number = -1;
  private stopObservingMedia?: () => void;

  aboutToAppear(): void {
    this.mounted = true;
    this.updateMediaText();
    this.observeMedia();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.stopObservingMedia?.();
    this.stopObservingMedia = undefined;
    if (this.resetCopy !== -1) { clearTimeout(this.resetCopy); }
  }

  private mediaKey(): string {
    return JSON.stringify([this.scopeId, this.messageId]);
  }

  private observeMedia(): void {
    this.stopObservingMedia?.();
    this.stopObservingMedia = undefined;
    if (!this.mounted) { return; }
    this.sharing = false;
    this.reading = false;
    this.stopObservingMedia = this.replyMedia?.observe(this.mediaKey(), (reading: boolean): void => {
      this.reading = reading;
    });
  }

  private updateMediaText(): void {
    this.plainText = desktopReplyMediaText(this.text);
    this.mediaTextAvailable = this.plainText.length > 0;
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
  }

  private replyTitle(): string {
    try {
      return this.getUIContext().getHostContext()?.resourceManager.getStringSync(
        $r('app.string.desktop_reply_share_title').id) ?? '';
    } catch (_) {
      return '';
    }
  }

  private toggleReading(): void {
    const media = this.replyMedia;
    if (media === undefined || (!this.mediaTextAvailable && !this.reading)) { return; }
    const ability = this.abilityContext();
    if (ability === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_reply_read_failed') });
      return;
    }
    const key = this.mediaKey();
    media.toggle(ability, key, this.plainText, this.replyTitle(), (): void => {
      if (this.mounted && this.mediaKey() === key) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_reply_read_failed') });
      }
    });
  }

  private async shareReply(): Promise<void> {
    if (!this.mediaTextAvailable || this.sharing) { return; }
    const ability = this.abilityContext();
    if (ability === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_reply_share_failed') });
      return;
    }
    const key = this.mediaKey();
    this.sharing = true;
    const opened = await shareText(ability, { content: this.plainText, title: this.replyTitle() });
    if (!this.mounted || this.mediaKey() !== key) { return; }
    this.sharing = false;
    if (!opened) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_reply_share_failed') });
    }
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
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.Icon($r('app.media.dsh_session_branch_outline'))
      }.width(28).height(28).padding(0).borderRadius(7).focusOnTouch(false)
        .enabled(this.canFork && !this.forking).key('desktopReplyFork-' + this.messageId)
        .accessibilityText(this.canFork ? '在新对话中分支' : '仅可从已完成轮次的最后一条消息分支')
        .onClick(this.onFork)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.Icon(this.reading ? $r('app.media.dsh_cordis_stop_fill') : $r('app.media.dsh_reply_read_aloud'))
      }.width(24).height(24).padding(0).borderRadius(6).focusOnTouch(false)
        .enabled(this.replyMedia !== undefined && (this.mediaTextAvailable || this.reading))
        .key('desktopReplyReadAloud-' + this.messageId)
        .accessibilityText(this.reading ? $r('app.string.desktop_reply_stop_reading') : $r('app.string.desktop_reply_read_aloud'))
        .onClick((): void => { this.toggleReading(); })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.Icon($r('app.media.dsh_reply_share'))
      }.width(24).height(24).padding(0).borderRadius(6).focusOnTouch(false)
        .enabled(this.mediaTextAvailable && !this.sharing)
        .key('desktopReplyShare-' + this.messageId)
        .accessibilityText($r('app.string.desktop_reply_share'))
        .onClick((): void => { this.shareReply(); })
      if (!this.compactUsage && this.turnUsage !== undefined) {
        DesktopChatUsageTurn({ usage: this.turnUsage, compact: this.compactUsage,
          ownerKey: this.scopeId + ':' + this.messageId, availableWidth: this.availableWidth,
          narrow: this.availableWidth <= 480 })
      }
      if (this.timestamp > 0) {
        Text(this.clock()).fontSize(12).fontColor($r('sys.color.font_tertiary')).margin({ left: 4 })
      }
    }.width('100%').constraintSize({ maxWidth: 712 })
  }
}
