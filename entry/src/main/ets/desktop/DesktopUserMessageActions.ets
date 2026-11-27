import { copyText } from 'platform';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { desktopUserMessageClipboardText, desktopUserMessageClockParts } from './DesktopUserMessageActionsModel';

const COPY_FEEDBACK_MS: number = 1600;
const TOOLTIP_DELAY_MS: number = 350;

const calendarListeners: Set<(now: number) => void> = new Set<(now: number) => void>();
let calendarTimer: number = -1;

// All mounted messages share one local-midnight refresh.
function scheduleCalendarRefresh(): void {
  const midnight: Date = new Date();
  midnight.setHours(24, 0, 0, 0);
  calendarTimer = setTimeout((): void => {
    const now: number = Date.now();
    calendarListeners.forEach((listener: (now: number) => void): void => { listener(now); });
    scheduleCalendarRefresh();
  }, Math.max(1, midnight.getTime() - Date.now()));
}

@Component
export struct DesktopUserMessageActions {
  @Prop messageId: string = '';
  @Prop timestamp: number = 0;
  @Prop @Watch('resetCopyState') text: string = '';
  @Prop revealOnHover: boolean = false;
  @Prop messageHovered: boolean = false;
  @Prop bodySize: number = 14;

  @State private copied: boolean = false;
  @State private actionHovered: boolean = false;
  @State private actionFocused: boolean = false;
  @State private pressing: boolean = false;
  @State private tooltipVisible: boolean = false;
  @State private now: number = Date.now();

  private copyTimer: number = -1;
  private tooltipTimer: number = -1;
  private copyGeneration: number = 0;
  private readonly refreshCalendar: (now: number) => void = (now: number): void => { this.now = now; };

  aboutToAppear(): void {
    this.now = Date.now();
    calendarListeners.add(this.refreshCalendar);
    if (calendarTimer === -1) { scheduleCalendarRefresh(); }
  }

  aboutToDisappear(): void {
    this.resetCopyState();
    this.dismissTooltip();
    calendarListeners.delete(this.refreshCalendar);
    if (calendarListeners.size === 0) {
      clearTimeout(calendarTimer);
      calendarTimer = -1;
    }
  }

  private clock(): ResourceStr {
    const parts = desktopUserMessageClockParts(this.timestamp, this.now);
    if (parts === undefined) { return ''; }
    if (parts.sameDay) { return parts.hourMinute; }
    if (parts.sameYear) {
      return $r('app.string.desktop_user_message_clock_md', parts.month, parts.day, parts.hourMinute);
    }
    return $r('app.string.desktop_user_message_clock_ymd', parts.year, parts.month, parts.day, parts.hourMinute);
  }

  private actionLabel(): Resource {
    return this.copied ? $r('app.string.desktop_user_message_copied') : $r('app.string.desktop_trace_copy');
  }

  private revealed(): boolean {
    return !this.revealOnHover || this.messageHovered || this.actionHovered || this.actionFocused ||
      this.pressing || this.copied;
  }

  private dismissTooltip(): void {
    if (this.tooltipTimer !== -1) {
      clearTimeout(this.tooltipTimer);
      this.tooltipTimer = -1;
    }
    this.tooltipVisible = false;
  }

  private syncTooltip(): void {
    if (!this.actionHovered && !this.actionFocused) {
      this.dismissTooltip();
    } else if (!this.tooltipVisible && this.tooltipTimer === -1) {
      this.tooltipTimer = setTimeout((): void => {
        this.tooltipTimer = -1;
        this.tooltipVisible = true;
      }, TOOLTIP_DELAY_MS);
    }
  }

  private resetCopyState(): void {
    this.copyGeneration++;
    if (this.copyTimer !== -1) {
      clearTimeout(this.copyTimer);
      this.copyTimer = -1;
    }
    this.copied = false;
  }

  private async copyMessage(): Promise<void> {
    if (this.text.length === 0) { return; }
    const generation: number = ++this.copyGeneration;
    const text: string = desktopUserMessageClipboardText(this.text);
    if (!(await copyText(text)) || generation !== this.copyGeneration) { return; }
    if (this.copyTimer !== -1) { clearTimeout(this.copyTimer); }
    this.copied = true;
    this.copyTimer = setTimeout((): void => {
      this.copied = false;
      this.copyTimer = -1;
    }, COPY_FEEDBACK_MS);
  }

  @Builder
  private CopyTooltip() {
    Text(this.actionLabel()).fontSize(12).fontColor($r('sys.color.font_primary')).padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }

  build() {
    Row({ space: 8 }) {
      if (this.clock() !== '') {
        Text(this.clock()).key('desktopUserMessageTime-' + this.messageId)
          .fontSize(this.bodySize - 1).fontColor($r('sys.color.font_tertiary'))
          .margin({ right: 12 }).maxLines(1)
      }
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image(this.copied ? $r('app.media.dsh_dock_check') : $r('app.media.dsh_session_copy'))
          .key((this.copied ? 'desktopUserCopied-' : 'desktopUserCopyGlyph-') + this.messageId)
          .width(this.bodySize + 1).height(this.bodySize + 1).supportSvg2(true)
          .draggable(false).accessibilityLevel('no')
      }.key('desktopUserCopy-' + this.messageId)
        .width(this.bodySize + 14).height(this.bodySize + 14).padding(0).borderRadius(7)
        .enabled(this.text.length > 0).focusOnTouch(false).accessibilityText(this.actionLabel())
        .onHover((hovered: boolean): void => {
          this.actionHovered = hovered;
          this.syncTooltip();
        })
        .onFocus((): void => {
          this.actionFocused = true;
          this.syncTooltip();
        })
        .onBlur((): void => {
          this.actionFocused = false;
          this.syncTooltip();
        })
        .onTouch((event: TouchEvent): void => {
          this.pressing = event.type === TouchType.Down || event.type === TouchType.Move;
        })
        .onClick((): void => { this.copyMessage(); })
        .bindPopup(this.tooltipVisible, { builder: this.CopyTooltip(), placement: Placement.Bottom,
          targetSpace: 6, enableArrow: false, focusable: false, mask: false, autoCancel: false,
          systemMaterial: desktopMenuOptions(Placement.Bottom).systemMaterial,
          onStateChange: (event): void => { if (!event.isVisible) { this.dismissTooltip(); } } })
    }.key('desktopUserMessageActions-' + this.messageId)
      .height(this.bodySize + 14).opacity(this.revealed() ? 1 : 0)
  }
}
