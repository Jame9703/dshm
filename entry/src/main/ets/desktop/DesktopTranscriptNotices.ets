import { desktopTranscriptRetrySeconds } from './DesktopTranscriptNoticesModel';
import type { DesktopTranscriptFailure, DesktopTranscriptNotice } from './DesktopTranscriptNoticesModel';

@Component
export struct DesktopTranscriptNoticeRow {
  @Prop @Watch('updateCountdown') notice: DesktopTranscriptNotice | undefined = undefined;
  @Prop fontSize: number = 13;
  @State private detailsOpen: boolean = false;
  @State private seconds: number = 1;
  private timer: number = -1;
  private deadline: number = 0;
  private countdownId: string = '';

  aboutToAppear(): void { this.updateCountdown(); }
  aboutToDisappear(): void { this.stopCountdown(); }

  private stopCountdown(): void {
    if (this.timer < 0) { return; }
    clearInterval(this.timer);
    this.timer = -1;
  }

  private tick(): void {
    const remaining = desktopTranscriptRetrySeconds(this.deadline - Date.now());
    if (this.seconds !== remaining) { this.seconds = remaining; }
    if (remaining === 1) { this.stopCountdown(); }
  }

  private updateCountdown(): void {
    const retry = this.notice?.retry;
    if (retry === undefined || this.notice?.retryState !== 'scheduled') {
      this.stopCountdown();
      return;
    }
    const id = `${this.notice.id}:${retry.sequence}:${retry.delayMs}`;
    if (id !== this.countdownId) {
      this.stopCountdown();
      this.countdownId = id;
      // The scheduled delay runs against the UI's clock, which can differ from the host clock.
      this.deadline = Date.now() + retry.delayMs;
    }
    this.tick();
    if (this.seconds > 1 && this.timer < 0) { this.timer = setInterval((): void => this.tick(), 250); }
  }

  private retrySummary(): Resource {
    const retry = this.notice?.retry;
    const maximum = retry?.maximum === undefined ? '∞' : String(retry.maximum);
    const attempt = retry?.number ?? 1;
    const scheduledSeconds = desktopTranscriptRetrySeconds(retry?.delayMs ?? 0);
    if (this.notice?.retryState === 'scheduled') {
      return $r('app.string.desktop_transcript_retry_active', attempt, maximum, this.seconds);
    }
    if (this.notice?.retryState === 'cancelled') {
      return $r('app.string.desktop_transcript_retry_cancelled', attempt, maximum, scheduledSeconds);
    }
    return $r('app.string.desktop_transcript_retry_started', attempt, maximum, scheduledSeconds);
  }

  private reason(failure?: DesktopTranscriptFailure): ResourceStr {
    switch (failure?.code) {
      case 'ACCOUNT_SIGNED_OUT': return $r('app.string.desktop_transcript_failure_signed_out');
      case 'INTERRUPTED': return $r('app.string.desktop_transcript_failure_interrupted');
      case 'ACCOUNT_SIGN_IN_REQUIRED': return $r('app.string.desktop_transcript_failure_sign_in_required');
      case 'QUOTA':
      case 'ACCOUNT_QUOTA': return $r('app.string.desktop_transcript_failure_quota');
      case 'AUTH': return $r('app.string.desktop_transcript_failure_auth');
      default: return failure?.message ?? '';
    }
  }

  private statusTitle(): Resource {
    if (this.notice?.kind === 'turn-max-tokens') { return $r('app.string.desktop_transcript_token_limit'); }
    const code = this.notice?.failure?.code;
    return code === 'ACCOUNT_SIGNED_OUT' || code === 'INTERRUPTED' ?
      $r('app.string.desktop_transcript_task_stopped') : $r('app.string.desktop_transcript_turn_failed');
  }

  private statusMessage(): ResourceStr {
    return this.notice?.kind === 'turn-max-tokens' ? $r('app.string.desktop_transcript_token_limit_hint') :
      this.reason(this.notice?.failure);
  }

  private statusColor(): ResourceColor {
    return this.notice?.kind === 'turn-max-tokens' ? $r('sys.color.warning') : $r('sys.color.alert');
  }

  private statusCode(): string {
    const code = this.notice?.failure?.code ?? '';
    return code === 'INTERRUPTED' ? '' : code;
  }

  @Builder
  private Retry() {
    Column({ space: 3 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Text(this.retrySummary()).fontSize(this.fontSize)
            .fontColor(this.notice?.retryState === 'scheduled' ? $r('sys.color.font_secondary') :
              $r('sys.color.font_tertiary'))
          SymbolGlyph(this.detailsOpen ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right')).fontSize(9)
            .fontColor([$r('sys.color.font_tertiary')]).accessibilityLevel('no')
        }
      }.key(`desktopTranscriptRetry-${this.notice?.id ?? ''}`)
        .constraintSize({ maxWidth: '100%', minHeight: this.fontSize + 10 })
        .padding({ left: 0, right: 3 }).borderRadius(6).focusOnTouch(false)
        .accessibilityText(this.retrySummary()).accessibilitySelected(this.detailsOpen)
        .onClick((): void => { this.detailsOpen = !this.detailsOpen; })
      if (this.detailsOpen) {
        Column({ space: 2 }) {
          Text($r('app.string.desktop_transcript_retry_delay', Math.round(this.notice?.retry?.delayMs ?? 0)))
            .fontSize(this.fontSize).fontColor($r('sys.color.font_secondary'))
          Text() {
            Span($r('app.string.desktop_transcript_retry_failure')).fontColor($r('sys.color.font_secondary'))
            Span(this.reason(this.notice?.retry?.failure)).fontColor($r('sys.color.font_tertiary'))
          }.fontSize(this.fontSize).copyOption(CopyOptions.LocalDevice)
        }.key(`desktopTranscriptRetryDetail-${this.notice?.id ?? ''}`)
          .width('100%').alignItems(HorizontalAlign.Start).padding({ left: 14 })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TerminalStatus() {
    Row({ space: 8 }) {
      Circle().width(7).height(7).fill(this.statusColor()).margin({ top: Math.max(3, this.fontSize / 2 - 1) })
        .accessibilityLevel('no')
      Text() {
        Span(this.statusTitle()).fontWeight(FontWeight.Medium).fontColor(this.statusColor())
        Span(' ')
        Span(this.statusMessage()).fontColor($r('sys.color.font_secondary'))
      }.fontSize(this.fontSize).layoutWeight(1).copyOption(CopyOptions.LocalDevice)
      if (this.statusCode().length > 0) {
        Text(this.statusCode()).fontFamily('monospace').fontSize(Math.max(10, this.fontSize - 1))
          .fontColor($r('sys.color.font_tertiary')).constraintSize({ maxWidth: '30%' })
          .copyOption(CopyOptions.LocalDevice)
      }
    }.key(`desktopTranscriptTerminalNotice-${this.notice?.turn ?? 0}`)
      .width('100%').alignItems(VerticalAlign.Top).padding({ top: 2, bottom: 2 })
  }

  build() {
    Column() {
      if (this.notice?.kind === 'retry') {
        this.Retry()
      } else if (this.notice !== undefined) {
        this.TerminalStatus()
      }
    }.width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
  }
}
