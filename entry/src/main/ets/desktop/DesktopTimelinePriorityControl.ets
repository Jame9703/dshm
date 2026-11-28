import { desktopMenuOptions } from './DesktopMenuOptions';
import { TIMELINE_PRIORITIES } from './DesktopTimelineActions';

@Component
export struct DesktopTimelinePriorityControl {
  @Prop current: string = '';
  @Prop own: string = '';
  @Prop inherited: string = '';
  @Prop allowed: boolean = false;
  onSelect: (priority: string | null) => void = (): void => {};

  private currentLabel(): string {
    return this.current || this.getUIContext().getHostContext()?.resourceManager.getStringSync(
      $r('app.string.desktop_timeline_priority_none').id) || '';
  }

  private description(priority: string): Resource {
    if (priority === 'P0') { return $r('app.string.desktop_timeline_priority_p0'); }
    if (priority === 'P1') { return $r('app.string.desktop_timeline_priority_p1'); }
    if (priority === 'P2') { return $r('app.string.desktop_timeline_priority_p2'); }
    return $r('app.string.desktop_timeline_priority_p3');
  }

  private tone(): Resource {
    if (this.current === 'P0') { return $r('app.color.workspace_status_error'); }
    if (this.current === 'P1') { return $r('sys.color.warning'); }
    if (this.current === 'P2') { return $r('sys.color.brand'); }
    return $r('sys.color.font_secondary');
  }

  private menuOptions(): MenuOptions {
    const options = desktopMenuOptions(Placement.TopLeft);
    options.showInSubWindow = false;
    return options;
  }

  @Builder
  private PriorityMenu() {
    Menu() {
      ForEach(TIMELINE_PRIORITIES, (priority: string): void => {
        MenuItem({ content: priority, labelInfo: this.description(priority) })
          .key('desktopTimelinePriority-' + priority).selectIcon(true).selected(this.own === priority)
          .onChange((): void => { this.onSelect(priority); })
      }, (priority: string): string => priority)
      MenuItem({ content: this.inherited ?
        $r('app.string.desktop_timeline_priority_inherit', this.inherited) :
        $r('app.string.desktop_timeline_priority_none') })
        .key('desktopTimelinePriority-Inherit').selectIcon(true).selected(!this.own)
        .onChange((): void => { this.onSelect(null); })
    }
  }

  build() {
    Row() {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 4 }) {
          Image($r('app.media.dsh_queue_queue_outline')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
          Text($r('app.string.desktop_timeline_priority_label')).fontSize(12)
          Text(this.currentLabel()).key('desktopTimelineTaskPriorityBadge').fontSize(12).fontColor(this.tone())
          Image($r('app.media.dsh_timeline_priority_chevrons')).width(12).height(12).supportSvg2(true)
            .accessibilityLevel('no')
        }
      }.key('desktopTimelineTaskPriority').height(30).enabled(this.allowed)
        .accessibilityText($r('app.string.desktop_timeline_priority_value', this.currentLabel()))
        .accessibilityDescription($r('app.string.desktop_timeline_priority_hint'))
        .bindMenu(this.PriorityMenu, this.menuOptions())
    }.bindTips($r('app.string.desktop_timeline_priority_hint'), { appearingTime: 480, enableArrow: false,
      systemMaterial: desktopMenuOptions(Placement.Top).systemMaterial })
  }
}
