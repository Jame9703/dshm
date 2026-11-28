import { DesktopTimelineHelp } from './DesktopTimelineHelp';
import { desktopTimelineWeight } from './DesktopTimelineMetricsModel';
import type { DesktopTimelineTask } from './DesktopTimelineModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';

@Component
export struct DesktopTimelineTaskMetrics {
  @Prop task?: DesktopTimelineTask = undefined;
  @Prop decimals: number = 2;

  @Builder
  private Metric(label: ResourceStr, value: string, id: string, help: boolean = false) {
    Column({ space: 2 }) {
      Row({ space: 2 }) {
        Text(label).fontSize(11).fontColor($r('sys.color.font_secondary'))
        if (help) {
          DesktopTimelineHelp({ label: $r('app.string.desktop_timeline_metric_weight_hint'),
            message: $r('app.string.desktop_timeline_metric_weight_hint'),
            buttonKey: 'desktopTimelineTaskWeightHelp', popupKey: 'desktopTimelineTaskWeightPopup' })
        }
      }.height(24)
      Text(value).fontSize(15).fontWeight(FontWeight.Medium).key(id)
    }.padding({ left: 10, right: 10, top: 6, bottom: 8 }).alignItems(HorizontalAlign.Start)
      .borderRadius(8).constraintSize({ minWidth: 92 }).margin({ right: 6, bottom: 6 })
      .backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      this.Metric($r('app.string.desktop_timeline_metric_progress'),
        desktopTimelinePercent(this.task?.progress ?? 0, this.decimals) + '%', 'desktopTimelineTaskProgressMetric')
      this.Metric($r('app.string.desktop_timeline_metric_weight'), desktopTimelineWeight(this.task?.share ?? 1),
        'desktopTimelineTaskWeightMetric', true)
      if (this.task !== undefined && this.task.children === 0) {
        this.Metric($r('app.string.desktop_timeline_metric_units'),
          this.task.unitsDone + ' / ' + this.task.unitsTotal, 'desktopTimelineTaskUnitsMetric')
      }
    }.width('100%')
  }
}
