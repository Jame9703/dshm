import { controlMaterial } from 'platform';
import type { DesktopTimelineTree } from './DesktopTimelineModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';
import { DesktopTimelineProgressBar } from './DesktopTimelineProgressBar';

@Component
export struct DesktopTimelineDock {
  @Prop owner: string = '';
  @Prop @Watch('targetChanged') tree?: DesktopTimelineTree = undefined;
  @Prop showing: boolean = false;
  @Prop removable: boolean = false;
  @Prop decimals: number = 2;
  @Prop segmented: boolean = true;
  onToggle: (owner: string, tree: string) => void = (): void => {};
  onRemove: (owner: string, tree: string) => Promise<boolean> = (): Promise<boolean> => Promise.resolve(false);
  @State private removing: boolean = false;
  @State private failed: boolean = false;
  private pendingTree: string = '';
  private generation: number = 0;

  aboutToDisappear(): void { this.generation++; }

  private targetChanged(): void {
    if (this.pendingTree === this.tree?.id) { return; }
    this.generation++;
    this.removing = false;
    this.failed = false;
  }

  private async removeDraft(): Promise<void> {
    const tree = this.tree?.id;
    if (!tree || !this.owner || !this.removable || this.removing) { return; }
    const generation = this.generation;
    this.pendingTree = tree;
    this.removing = true;
    this.failed = false;
    try {
      const ok = await this.onRemove(this.owner, tree);
      if (generation === this.generation && this.tree?.id === tree) { this.failed = !ok; }
    } finally {
      if (generation === this.generation) { this.removing = false; }
    }
  }

  private toggle(): void {
    if (this.tree !== undefined) { this.onToggle(this.owner, this.tree.id); }
  }

  @Builder
  private Action() {
    Row({ space: 10 }) {
      Text(this.tree?.title ?? '').fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '30%' })
        .onClick((): void => { this.toggle(); })
      Row() {
        DesktopTimelineProgressBar({ progress: this.tree?.progress ?? 0, status: this.tree?.status ?? 'pending',
          parts: this.segmented ? this.tree?.parts : undefined, decimals: this.decimals,
          progressKey: 'desktopTimelineDockProgress', onTap: (): void => { this.toggle(); } })
      }.layoutWeight(1).padding({ top: 10, bottom: 10 })
      Text(desktopTimelinePercent(this.tree?.progress ?? 0, this.decimals) + '%').key('desktopTimelineDockPercent')
        .fontSize(12).fontColor($r('sys.color.font_secondary')).onClick((): void => { this.toggle(); })
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_browser_right_up_outline')).width(16).height(16).supportSvg2(true)
          .rotate({ angle: this.showing ? 180 : 0 }).draggable(false).accessibilityLevel('no')
      }.key('desktopTimelineDockToggle').width(28).height(28).padding(0).focusOnTouch(false)
        .accessibilityText(this.showing ? $r('app.string.desktop_timeline_dock_close') : $r('app.string.desktop_timeline_dock_open'))
        .onClick((): void => { this.toggle(); })
    }.height(36).layoutWeight(1).padding({ left: 12, right: this.removable ? 1 : 5 })
  }

  build() {
    Column({ space: 3 }) {
      Row() {
        this.Action()
        if (this.removable) {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            if (this.removing) { LoadingProgress().width(16).height(16) }
            else {
              Image($r('app.media.dsh_dock_close')).width(16).height(16).supportSvg2(true)
                .draggable(false).accessibilityLevel('no')
            }
          }.key('desktopTimelineDockRemove').width(28).height(28).padding(0).margin({ right: 5 })
            .enabled(!this.removing).focusOnTouch(false)
            .accessibilityText($r('app.string.desktop_timeline_dock_remove')).onClick((): void => { this.removeDraft(); })
        }
      }.height(36).width('100%').borderRadius(10).border({ width: 0.5, color: $r('app.color.workspace_border') })
        .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : Color.Transparent)
        .systemMaterial(controlMaterial())
      if (this.failed) {
        Text($r('app.string.desktop_timeline_dock_remove_failed')).fontSize(12).key('desktopTimelineDockRemoveError')
          .fontColor($r('app.color.workspace_status_error')).padding({ left: 12 })
      }
    }.width('100%').constraintSize({ maxWidth: 688 }).key('desktopTimelineDock').alignItems(HorizontalAlign.Start)
  }
}
