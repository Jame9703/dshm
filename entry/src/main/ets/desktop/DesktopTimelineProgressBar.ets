import { KeyCode } from '@kit.InputKit';
import { desktopMenuOptions } from './DesktopMenuOptions';
import type { DesktopTimelineParts, DesktopTimelineProgressPart } from './DesktopTimelineModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';

const TIMELINE_PROGRESS_ORDER: string[] = ['done', 'active', 'pending', 'blocked'];

@Component
export struct DesktopTimelineProgressBar {
  @Prop progress: number = 0;
  @Prop status: string = 'pending';
  @Prop @Watch('partsChanged') parts?: DesktopTimelineParts = undefined;
  @Prop decimals: number = 2;
  @Prop thickness: number = 8;
  @Prop progressKey: string = '';
  @Prop label: string = '';
  onTap?: () => void;

  @State private selected: string = '';
  @State private expanded: boolean = false;
  @State private dismissed: boolean = false;
  private timer: number = -1;
  private leaveTimer: number = -1;
  private pointerPart: string = '';

  aboutToDisappear(): void { this.stopTimer(); this.cancelLeave(); }

  private getPart(id: string): DesktopTimelineProgressPart | undefined {
    const parts = this.parts;
    if (id === 'done') { return parts?.done; }
    if (id === 'active') { return parts?.active; }
    if (id === 'pending') { return parts?.pending; }
    if (id === 'blocked') { return parts?.blocked; }
    return undefined;
  }

  private visibleParts(): string[] {
    return TIMELINE_PROGRESS_ORDER.filter((id: string): boolean => (this.getPart(id)?.fraction ?? 0) > 0);
  }

  private partsChanged(): void {
    if (this.parts === undefined || (this.selected && !this.visibleParts().includes(this.selected))) { this.clear(); }
  }

  private stopTimer(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
  }

  private clear(): void {
    this.stopTimer();
    this.cancelLeave();
    this.selected = '';
    this.expanded = false;
    this.dismissed = false;
  }

  private select(id: string): void {
    if (!id || this.selected === id) { return; }
    this.stopTimer();
    this.selected = id;
    this.expanded = false;
    if (this.dismissed) { return; }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (this.selected === id && !this.dismissed) { this.expanded = true; }
    }, 500);
  }

  private cancelLeave(): void {
    if (this.leaveTimer >= 0) { clearTimeout(this.leaveTimer); this.leaveTimer = -1; }
  }

  private hoverPart(id: string, hovered: boolean): void {
    if (id === 'total') { return; }
    if (hovered) {
      this.pointerPart = id;
      this.cancelLeave();
      this.select(id);
    } else if (this.pointerPart === id) {
      this.pointerPart = '';
      this.cancelLeave();
      // A neighboring segment can receive its enter event in the same pointer dispatch.
      this.leaveTimer = setTimeout((): void => {
        this.leaveTimer = -1;
        if (!this.pointerPart) { this.clear(); }
      }, 0);
    }
  }

  private tapPart(id: string): void {
    if (this.onTap !== undefined) { this.onTap(); return; }
    if (id === 'total') { return; }
    if (this.dismissed) { this.clear(); }
    this.select(id);
    if (this.progressKey) { this.getUIContext().getFocusController().requestFocus(this.progressKey); }
  }

  private onProgressKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || this.parts === undefined) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.stopTimer();
      this.selected = '';
      this.expanded = false;
      this.dismissed = true;
      return true;
    }
    if (event.keyCode !== KeyCode.KEYCODE_DPAD_LEFT && event.keyCode !== KeyCode.KEYCODE_DPAD_RIGHT) { return false; }
    const visible = this.visibleParts();
    if (visible.length === 0) { return false; }
    const current = visible.indexOf(this.selected);
    const step = event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT ? 1 : -1;
    const index = current < 0 ? (step > 0 ? 0 : visible.length - 1) : (current + step + visible.length) % visible.length;
    this.select(visible[index]);
    return true;
  }

  private fill(): Resource {
    if (this.status === 'done') { return $r('app.color.workspace_timeline_done'); }
    if (this.status === 'blocked') { return $r('app.color.workspace_selection'); }
    return $r('sys.color.brand');
  }

  private partLabel(id: string): Resource {
    if (id === 'done') { return $r('app.string.desktop_timeline_progress_done'); }
    if (id === 'active') { return $r('app.string.desktop_timeline_progress_active'); }
    if (id === 'blocked') { return $r('app.string.desktop_timeline_progress_blocked'); }
    return $r('app.string.desktop_timeline_progress_pending');
  }

  private partSummary(id: string): string {
    const part = this.getPart(id);
    const manager = this.getUIContext().getHostContext()?.resourceManager;
    if (part === undefined || manager === undefined) { return ''; }
    const value = id === 'done' ? desktopTimelinePercent(part.fraction, this.decimals) :
      (part.fraction * 100).toFixed(this.decimals);
    return manager.getStringSync(this.partLabel(id).id, part.leaves, value);
  }

  private accessibleName(): string {
    return this.label || this.getUIContext().getHostContext()?.resourceManager.getStringSync(
      $r('app.string.desktop_timeline_metric_progress').id) || '';
  }

  private description(): string {
    if (this.parts === undefined) {
      return desktopTimelinePercent(this.progress, this.decimals) + '%';
    }
    return TIMELINE_PROGRESS_ORDER.map((id: string): string => this.partSummary(id)).join('\n');
  }

  private taskTitles(id: string): string[] {
    const part = this.getPart(id);
    if (part === undefined) { return []; }
    const titles = part.titles.slice(0, part.leaves > 6 ? 5 : 6)
      .map((value: string): string => value.replace(new RegExp('\\s+', 'g'), ' ').trim());
    if (part.leaves > 6) { titles.push('…'); }
    return titles;
  }

  @Builder
  private Tip() {
    Column({ space: 4 }) {
      Text(this.partSummary(this.selected)).fontSize(12).fontWeight(FontWeight.Medium)
        .key('desktopTimelineProgressSummary-' + this.selected)
      if (this.expanded) {
        ForEach(this.taskTitles(this.selected), (title: string, index: number): void => {
          Text(title === '…' ? title : '– ' + title).fontSize(12).key('desktopTimelineProgressTask-' + index)
        }, (title: string, index: number): string => String(index) + ':' + title)
      }
    }.key('desktopTimelineProgressPopup').constraintSize({ maxWidth: 360 })
      .padding({ left: 10, right: 10, top: 7, bottom: 7 }).alignItems(HorizontalAlign.Start)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private Segment(id: string, fraction: number, color: Resource) {
    if (fraction > 0) {
      Row().key('desktopTimelineProgressSegment-' + id).width((fraction * 100) + '%').height('100%')
        .backgroundColor(color).accessibilityLevel('no')
        .linearGradient(id === 'blocked' ? { angle: 135, repeating: true, colors: [
          [$r('app.color.workspace_panel'), 0], [$r('app.color.workspace_panel'), 0.04],
          [$r('app.color.workspace_selection'), 0.04], [$r('app.color.workspace_selection'), 0.08]
        ] } : undefined)
        .onHover((hovered: boolean): void => { this.hoverPart(id, hovered); })
        .onClick((): void => { this.tapPart(id); })
    }
  }

  build() {
    Row() {
      if (this.parts !== undefined) {
        this.Segment('done', this.parts.done.fraction, $r('app.color.workspace_timeline_done'))
        this.Segment('active', this.parts.active.fraction, $r('sys.color.brand'))
        this.Segment('pending', this.parts.pending.fraction, $r('app.color.workspace_panel'))
        this.Segment('blocked', this.parts.blocked.fraction, $r('app.color.workspace_selection'))
      } else {
        this.Segment('total', this.progress, this.fill())
      }
    }.key(this.progressKey).width('100%').height(this.thickness).borderRadius(this.thickness / 2).clip(true)
      .backgroundColor($r('app.color.workspace_selection'))
      .accessibilityRole(AccessibilityRoleType.PROGRESS).accessibilityText(this.accessibleName())
      .accessibilityDescription(this.description()).focusable(this.parts !== undefined)
      .onFocus((): void => { if (!this.selected) { this.select(this.visibleParts()[0] ?? ''); } })
      .onBlur((): void => { this.clear(); })
      .onHover((hovered: boolean): void => {
        if (!hovered) { this.pointerPart = ''; this.clear(); }
      })
      .onKeyEvent((event: KeyEvent): boolean => this.onProgressKey(event))
      .bindPopup(this.selected !== '' && !this.dismissed, { builder: this.Tip(), placement: Placement.Top,
        targetSpace: 6, enableArrow: false, focusable: false, mask: false, autoCancel: true,
        systemMaterial: desktopMenuOptions(Placement.Top).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible && !this.dismissed) { this.clear(); } } })
  }
}
