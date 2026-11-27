import { accessibility } from '@kit.AccessibilityKit';
import { settings } from '@kit.BasicServicesKit';

const RUN_CLOCK_INTERVAL_MS: number = 1000;

export interface DesktopChatRunningDuration {
  hours: number;
  minutes: number;
  seconds: number;
}

export function desktopChatRunningDuration(startTime: number, now: number): DesktopChatRunningDuration {
  const elapsed: number = Math.max(1, Math.floor((now - startTime) / RUN_CLOCK_INTERVAL_MS));
  return { hours: Math.floor(elapsed / 3600), minutes: Math.floor(elapsed / 60) % 60, seconds: elapsed % 60 };
}

@Component
export struct DesktopChatRunningStatus {
  @Prop @Watch('syncStatus') startTime: number | undefined = undefined;
  @Prop @Watch('syncStatus') paused: boolean = false;
  @Prop @Watch('syncStatus') holding: boolean = false;
  @Prop showDivider: boolean = false;
  @Prop bodySize: number = 14;
  @Prop textFamily: string = '';
  @Prop reduceMotion: boolean = false;

  @State private now: number = Date.now();
  @State private systemReduceMotion: boolean = false;
  @State private whaleFailed: boolean = false;
  private timer: number = -1;
  private mounted: boolean = false;
  private announced: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.syncStatus();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.announced = false;
    this.stopClock();
  }

  private stopClock(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private syncStatus(): void {
    if (!this.mounted) { return; }
    if (this.holding) {
      this.stopClock();
      this.announced = false;
      return;
    }
    this.readMotionSetting();
    if (!this.announced) {
      this.announced = true;
      this.announceRunning();
    }
    if (this.paused || this.startTime === undefined || !Number.isFinite(this.startTime)) {
      this.stopClock();
      return;
    }
    this.now = Date.now();
    if (this.timer === -1) {
      this.timer = setInterval((): void => { this.now = Date.now(); }, RUN_CLOCK_INTERVAL_MS);
    }
  }

  private readMotionSetting(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) { return; }
    try {
      const scale: string = settings.getValueSync(context, settings.display.ANIMATOR_DURATION_SCALE, '1',
        settings.domainName.DEVICE_SHARED);
      this.systemReduceMotion = scale.length > 0 && Number(scale) === 0;
    } catch (_) {
      this.systemReduceMotion = false;
    }
  }

  private announceRunning(): void {
    const bundle: string | undefined = this.getUIContext().getHostContext()?.applicationInfo.name;
    if (bundle === undefined) { return; }
    const event: accessibility.EventInfo =
      new accessibility.EventInfo('announceForAccessibilityNotInterrupt', bundle, 'common');
    event.textResourceAnnouncedForAccessibility = $r('app.string.desktop_chat_running');
    accessibility.sendAccessibilityEvent(event).catch((): void => {});
  }

  private label(): Resource {
    const startTime: number | undefined = this.startTime;
    if (startTime === undefined || !Number.isFinite(startTime)) { return $r('app.string.desktop_chat_running'); }
    const time: DesktopChatRunningDuration = desktopChatRunningDuration(startTime, this.now);
    if (time.hours > 0) {
      return $r('app.string.desktop_chat_running_for_hours', time.hours, time.minutes, time.seconds);
    }
    if (time.minutes > 0) {
      return $r('app.string.desktop_chat_running_for_minutes', time.minutes, time.seconds);
    }
    return $r('app.string.desktop_chat_running_for_seconds', time.seconds);
  }

  private stillWhale(): boolean {
    return this.reduceMotion || this.systemReduceMotion || this.whaleFailed;
  }

  @Builder
  private Whale() {
    if (this.stillWhale()) {
      Image($r('app.media.dsh_chat_running_whale_still')).key('desktopChatRunningWhale')
        .width(this.bodySize).height(this.bodySize).supportSvg2(true).draggable(false).accessibilityLevel('no')
    } else {
      // The WebUI alpha mask is APNG. The media variant preserves its pixels and timing as lossless animated WebP.
      Image($r('app.media.dsh_chat_running_whale')).key('desktopChatRunningWhale')
        .width(this.bodySize).height(this.bodySize).draggable(false).accessibilityLevel('no')
        .onError((): void => { this.whaleFailed = true; })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.holding) {
        Blank().key('desktopChatRunningHolding').height(this.bodySize + 18).accessibilityLevel('no')
      } else {
        if (this.showDivider) {
          Divider().key('desktopChatRunningDivider').width('100%').strokeWidth(0.5)
            .color($r('sys.color.comp_divider')).accessibilityLevel('no')
        }
        Row({ space: 6 }) {
          this.Whale()
          Text(this.label()).key('desktopChatRunningLabel').fontSize(this.bodySize - 2).lineHeight(this.bodySize + 8)
            .fontFamily(this.textFamily).fontColor($r('app.color.desktop_chat_running_label')).maxLines(1)
        }.height(this.bodySize + 14).margin({ top: 4 }).accessibilityGroup(true)
          .accessibilityText($r('app.string.desktop_chat_running'))
      }
    }.key('desktopChatRunningStatus').height(this.bodySize + 18).width('100%').hitTestBehavior(HitTestMode.None)
  }
}
