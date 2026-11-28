import { settings } from '@kit.BasicServicesKit';
import { desktopPreparingSkillTool } from './DesktopSkillToolModel';
import type { DesktopSkillToolView } from './DesktopSkillToolModel';

@Component
export struct DesktopSkillToolRow {
  @Prop @Watch('syncMotion') view: DesktopSkillToolView = desktopPreparingSkillTool();
  @Prop callId: string = '';
  @Prop open: boolean = false;
  @Prop inspectAvailable: boolean = false;
  @Prop bodySize: number = 14;
  @Prop bodyFamily: string = '';
  @Prop codeSize: number = 11;
  @Prop codeFamily: string = 'monospace';
  onToggle: () => void = (): void => {};
  onInspect: () => void = (): void => {};
  @State private hovered: boolean = false;
  @State private intensity: number = 1;
  private moving: boolean = false;
  private visible: boolean = false;

  private syncMotion(): void {
    const active = this.visible && (this.view.state === 'preparing' || this.view.state === 'running');
    if (active === this.moving) { return; }
    this.moving = active;
    if (!active) {
      this.getUIContext().animateTo({ duration: 0 }, (): void => { this.intensity = 1; });
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      try {
        const speed = settings.getValueSync(context, settings.display.ANIMATOR_DURATION_SCALE, '1',
          settings.domainName.DEVICE_SHARED);
        if (speed.length > 0 && Number(speed) === 0) { return; }
      } catch (_) {}
    }
    const ui = this.getUIContext();
    ui.animateToImmediately({ duration: 0 }, (): void => { this.intensity = 0.6; });
    ui.animateTo({ duration: 850, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate },
      (): void => { this.intensity = 1; });
  }

  private status(): string {
    const label = this.view.state === 'preparing' ? $r('app.string.desktop_skill_tool_preparing') :
      this.view.state === 'running' ? $r('app.string.desktop_skill_tool_running') :
        this.view.state === 'failed' ? $r('app.string.desktop_skill_tool_failed') : undefined;
    return label === undefined ? '' : this.getUIContext().getHostContext()?.resourceManager.getStringSync(label.id) ?? '';
  }

  private summaryColor(): ResourceColor {
    if (this.view.state === 'failed') { return $r('app.color.workspace_status_error'); }
    if (this.view.state === 'stopped') { return $r('sys.color.warning'); }
    if (this.hovered) { return $r('sys.color.font_secondary'); }
    return $r('sys.color.font_tertiary');
  }

  @Builder
  private Header() {
    Row({ space: 6 }) {
      Image(this.view.output && (this.open || this.hovered) ? $r('app.media.dsh_queue_chevron_down_outline') :
        $r('app.media.dsh_skill_outline'))
        .width(this.bodySize).height(this.bodySize).supportSvg2(true).draggable(false).accessibilityLevel('no')
      Text($r('app.string.desktop_skill_tool_title')).fontSize(Math.max(10, this.bodySize - 1)).fontFamily(this.bodyFamily)
        .fontColor(this.hovered ? $r('sys.color.font_secondary') : $r('sys.color.font_tertiary')).opacity(this.intensity)
      if (this.view.state !== 'preparing') {
        Circle().width(2).height(2).fill($r('sys.color.font_tertiary')).margin({ left: 2, right: 2 })
          .accessibilityLevel('no')
        Text(this.view.state === 'stopped' ? $r('app.string.desktop_skill_tool_stopped') : this.view.summary)
          .fontSize(Math.max(10, this.bodySize - 1)).fontFamily(this.bodyFamily).fontColor(this.summaryColor())
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).opacity(this.intensity)
      }
    }.width('100%').height(this.bodySize + 10).accessibilityDescription(this.status())
    .key('desktopSkillToolHeader-' + this.callId)
  }

  @Builder
  private Instructions() {
    Column() {
      Text($r('app.string.desktop_skill_tool_instructions')).width('100%').fontSize(11).fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_tertiary')).padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .border({ width: { bottom: 0.5 }, color: $r('app.color.workspace_border') })
      Scroll() {
        Text(this.view.output).key('desktopSkillInstructions-' + this.callId)
          .width('100%').fontSize(this.codeSize).fontFamily(this.codeFamily).copyOption(CopyOptions.LocalDevice)
          .fontColor(this.view.state === 'failed' ? $r('app.color.workspace_status_error') : $r('sys.color.font_secondary'))
          .padding({ left: 12, right: 12, top: 10, bottom: 12 })
      }.width('100%').constraintSize({ maxHeight: 224 }).scrollBar(BarState.Auto)
    }.width('100%').borderRadius(12).clip(true).border({ width: 0.5, color: $r('app.color.workspace_border') })
      .backgroundColor($r('app.color.workspace_panel')).margin({ top: 4, bottom: 4 })
  }

  build() {
    Column({ space: 2 }) {
      if (this.view.output) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          this.Header()
        }.key('desktopSkillToolRow-' + this.callId).width('100%').height(this.bodySize + 10).padding(0)
          .borderRadius(6).focusOnTouch(false).accessibilitySelected(this.open)
          .onHover((active: boolean): void => { this.hovered = active; }).onClick(this.onToggle)
      } else {
        this.Header()
      }
      if (this.open && this.view.output) {
        this.Instructions()
        if (this.inspectAvailable) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 4 }) {
              Image($r('app.media.dsh_cordis_inspect_outline')).width(14).height(14).supportSvg2(true)
                .draggable(false).accessibilityLevel('no')
              Text($r('app.string.desktop_skill_tool_inspect')).fontSize(11).fontColor($r('sys.color.font_secondary'))
            }
          }.key('desktopSkillInspect-' + this.callId).height(23).padding({ left: 8, right: 8 }).borderRadius(40)
            .border({ width: 0.5, color: $r('app.color.workspace_border') }).focusOnTouch(false).onClick(this.onInspect)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
    .onVisibleAreaChange([0.01], (visible: boolean): void => { this.visible = visible; this.syncMotion(); })
  }
}
