import { accessibility } from '@kit.AccessibilityKit';

@Component
struct DesktopTimelineFlowSweep {
  @Prop trackWidth: number = 0;
  @State private sweepX: number = 0;

  aboutToAppear(): void { this.sweepX = -this.trackWidth; }

  private flow(): void {
    const span = this.trackWidth;
    this.getUIContext().keyframeAnimateTo({ iterations: -1 }, [
      { duration: 1000, curve: Curve.Linear, event: (): void => { this.sweepX = -span / 3; } },
      { duration: 1000, curve: Curve.Linear, event: (): void => { this.sweepX = span / 3; } },
      { duration: 1000, curve: Curve.Linear, event: (): void => { this.sweepX = span; } },
    ]);
  }

  build() {
    Row().width('100%').height('100%')
      .linearGradient({ angle: 100, colors: [
        [$r('app.color.workspace_timeline_flow_clear'), 0.15],
        [$r('app.color.workspace_timeline_flow_highlight'), 0.5],
        [$r('app.color.workspace_timeline_flow_clear'), 0.85],
      ] })
      .translate({ x: this.sweepX }).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onAppear((): void => { this.flow(); })
  }
}

/** The animated node exists only while its clipped track is visible and motion is allowed. */
@Component
export struct DesktopTimelineProgressFlow {
  @Prop share: number = 0;
  @State private trackWidth: number = 0;
  @State private visible: boolean = false;
  @State private reducedMotion: boolean = true;
  private observing: boolean = false;
  private readonly motionChanged = (enabled: boolean): void => { this.reducedMotion = enabled; };

  aboutToAppear(): void {
    try {
      this.reducedMotion = accessibility.isAnimationReduceEnabledSync();
      accessibility.onAnimationReduceStateChange(this.motionChanged);
      this.observing = true;
    } catch (_) {
      this.reducedMotion = true;
    }
  }

  aboutToDisappear(): void {
    if (this.observing) {
      try { accessibility.offAnimationReduceStateChange(this.motionChanged); } catch (_) {}
      this.observing = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.visible && !this.reducedMotion && this.trackWidth > 0) {
        ForEach([this.trackWidth], (width: number): void => {
          Stack({ alignContent: Alignment.Start }) {
            DesktopTimelineFlowSweep({ trackWidth: width })
          }.key('desktopTimelineProgressFlow').width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        }, (width: number): string => String(width))
      }
    }.width(this.share * 100 + '%').height('100%').clip(true)
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
      .onAreaChange((_: Area, area: Area): void => {
        const width = Number(area.width);
        if (Number.isFinite(width) && width !== this.trackWidth) { this.trackWidth = width; }
      })
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; })
  }
}
