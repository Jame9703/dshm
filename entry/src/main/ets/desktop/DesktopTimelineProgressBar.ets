import type { DesktopTimelineParts } from './DesktopTimelineModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';

@Component
export struct DesktopTimelineProgressBar {
  @Prop progress: number = 0;
  @Prop status: string = 'pending';
  @Prop parts?: DesktopTimelineParts = undefined;
  @Prop decimals: number = 2;
  @Prop thickness: number = 8;

  private fill(): Resource {
    if (this.status === 'done') { return $r('app.color.workspace_timeline_done'); }
    if (this.status === 'blocked') { return $r('app.color.workspace_selection'); }
    return $r('sys.color.brand');
  }

  @Builder
  private Segment(id: string, fraction: number, color: Resource) {
    if (fraction > 0) {
      Row().key('desktopTimelineProgressSegment-' + id).width((fraction * 100) + '%').height('100%')
        .backgroundColor(color).accessibilityLevel('no')
    }
  }

  build() {
    Row() {
      if (this.parts !== undefined) {
        this.Segment('done', this.parts.done, $r('app.color.workspace_timeline_done'))
        this.Segment('active', this.parts.active, $r('sys.color.brand'))
        this.Segment('pending', this.parts.pending, $r('app.color.workspace_panel'))
        this.Segment('blocked', this.parts.blocked, $r('app.color.workspace_selection'))
      } else {
        this.Segment('total', this.progress, this.fill())
      }
    }.width('100%').height(this.thickness).borderRadius(this.thickness / 2).clip(true)
    .backgroundColor($r('app.color.workspace_selection')).accessibilityText(
      $r('app.string.desktop_timeline_progress_a11y', desktopTimelinePercent(this.progress, this.decimals)))
  }
}
