import { DesktopTimelineHelp } from './DesktopTimelineHelp';
import type { DesktopTimelineTree } from './DesktopTimelineModel';
import { desktopTimelineStatus } from './DesktopTimelineModel';
import { DESKTOP_TIMELINE_MINUTE, desktopTimelineDuration, desktopTimelineElapsed,
  desktopTimelineEstimate } from './DesktopTimelineMetricsModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';
import { DesktopTimelineProgressBar } from './DesktopTimelineProgressBar';

@Component
export struct DesktopTimelineOverview {
  @Prop @Watch('syncClock') tree?: DesktopTimelineTree = undefined;
  @Prop @Watch('syncClock') active: boolean = false;
  @Prop @Watch('syncClock') running: boolean = false;
  @Prop decimals: number = 2;
  @Prop segmented: boolean = true;
  @State private now: number = 0;
  private timer: number = -1;
  private mounted: boolean = false;

  aboutToAppear(): void { this.mounted = true; this.syncClock(); }

  aboutToDisappear(): void { this.mounted = false; this.stopClock(); }

  private stopClock(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
  }

  private working(): boolean { return this.running && this.tree?.status === 'active'; }

  private syncClock(): void {
    this.stopClock();
    if (!this.mounted || !this.active || !this.working()) { return; }
    const now = Date.now();
    this.now = now;
    this.timer = setTimeout((): void => { this.syncClock(); }, DESKTOP_TIMELINE_MINUTE - now % DESKTOP_TIMELINE_MINUTE);
  }

  private elapsed(): number {
    return desktopTimelineElapsed(this.tree?.createdAt ?? 0, this.tree?.latestActivityAt ?? 0, this.now, this.working());
  }

  private estimate(): string {
    const estimate = desktopTimelineEstimate(this.elapsed(), this.tree?.progress ?? 0);
    return estimate || this.getUIContext().getHostContext()?.resourceManager.getStringSync(
      $r('app.string.desktop_timeline_metric_unknown').id) || '–';
  }

  private leafCount(): number {
    const parts = this.tree?.parts;
    return parts === undefined ? 0 : parts.done.leaves + parts.active.leaves + parts.pending.leaves + parts.blocked.leaves;
  }

  build() {
    Column({ space: 9 }) {
      Row() {
        Text($r('app.string.desktop_timeline_metric_progress')).fontSize(13).fontWeight(FontWeight.Medium)
        Blank()
        Text(desktopTimelineStatus(this.tree?.status ?? 'pending')).fontSize(11).fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      Row({ space: 10 }) {
        Row() {
          DesktopTimelineProgressBar({ progress: this.tree?.progress ?? 0, status: this.tree?.status ?? 'pending',
            parts: this.segmented ? this.tree?.parts : undefined, decimals: this.decimals,
            progressKey: 'desktopTimelineTreeProgress' })
        }.layoutWeight(1)
        Text(desktopTimelinePercent(this.tree?.progress ?? 0, this.decimals) + '%').fontSize(24).fontWeight(FontWeight.Medium)
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween }) {
        Text($r('app.string.desktop_timeline_metric_leaves', this.tree?.parts?.done.leaves ?? 0, this.leafCount()))
          .key('desktopTimelineTreeLeaves').fontSize(11).fontColor($r('sys.color.font_secondary')).padding({ right: 8 })
        Row({ space: 5 }) {
          Text($r('app.string.desktop_timeline_metric_elapsed', desktopTimelineDuration(this.elapsed())))
            .key('desktopTimelineTreeElapsed').fontSize(11).fontColor($r('sys.color.font_secondary'))
          if (this.working()) {
            Text('·').fontSize(11).fontColor($r('sys.color.font_secondary'))
            Text($r('app.string.desktop_timeline_metric_estimate', this.estimate()))
              .key('desktopTimelineTreeEstimate').fontSize(11).fontColor($r('sys.color.font_secondary'))
            DesktopTimelineHelp({ label: $r('app.string.desktop_timeline_metric_estimate_help'),
              message: $r('app.string.desktop_timeline_metric_estimate_hint'),
              summary: $r('app.string.desktop_timeline_metric_estimate_formula', this.estimate()),
              buttonKey: 'desktopTimelineTreeEstimateHelp', popupKey: 'desktopTimelineTreeEstimatePopup' })
          }
        }
      }.width('100%')
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 8 })
      .alignItems(HorizontalAlign.Start).borderRadius(8)
      .border({ width: 0.5, color: $r('app.color.workspace_border') })
  }
}
