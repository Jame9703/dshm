import type { DesktopCompactionRow as DesktopCompactionRowData } from './DesktopCompactionModel';
import { desktopMenuOptions } from './DesktopMenuOptions';

const PREVIEW_TOOLTIP_DELAY_MS: number = 200;

@Component
export struct DesktopCompactionRow {
  @Prop @Watch('syncPreviewIdentity') row: DesktopCompactionRowData;
  @Prop @Watch('syncPreviewIdentity') previewAvailable: boolean = false;
  @Prop bodySize: number = 14;
  @Prop fontFamily: string = '';
  onOpenSummary: (summarySequence: number, isCurrent: () => boolean) => Promise<ResourceStr | undefined> =
    async (): Promise<undefined> => undefined;

  @State private opening: boolean = false;
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private pressing: boolean = false;
  @State private tooltipVisible: boolean = false;
  @State private expanded: boolean = false;
  @State private failure: ResourceStr | undefined = undefined;

  private previewIdentity: string = '';
  private previewGeneration: number = 0;
  private tooltipTimer: number = -1;

  aboutToAppear(): void {
    this.syncPreviewIdentity();
  }

  aboutToDisappear(): void {
    this.previewIdentity = '';
    this.previewGeneration++;
    this.dismissTooltip();
  }

  private syncPreviewIdentity(): void {
    const identity: string = this.row.id + ':' + String(this.row.summarySequence ?? -1) + ':' +
      String(this.previewAvailable);
    if (identity === this.previewIdentity) { return; }
    this.previewIdentity = identity;
    this.previewGeneration++;
    this.opening = false;
    this.failure = undefined;
    this.expanded = false;
    this.hovered = false;
    this.focused = false;
    this.pressing = false;
    this.dismissTooltip();
  }

  private canOpen(): boolean {
    return this.previewAvailable && this.row.status === 'landed' && this.row.summarySequence !== undefined;
  }

  private details(): string | undefined {
    const output: string | undefined = this.row.status === 'ended' ? this.row.error ?? this.row.fallbackSummary : undefined;
    return output !== undefined && output.includes('\n') ? output : undefined;
  }

  private title(): Resource {
    return this.row.status === 'landed' && this.row.commandId === undefined
      ? $r('app.string.desktop_compaction_title') : $r('app.string.desktop_compaction_command_title');
  }

  private summary(): ResourceStr {
    if (this.row.status === 'landed') {
      const items: number | undefined = this.row.shadowedItemCount;
      const tokens: number | undefined = this.row.shadowedTokenCount;
      if (items !== undefined && tokens !== undefined) {
        return $r('app.string.desktop_compaction_completed', String(items), String(tokens));
      }
      return this.row.fallbackSummary ?? $r('app.string.desktop_compaction_landed');
    }
    if (this.row.status === 'running') { return $r('app.string.desktop_compaction_running'); }
    if (this.row.status === 'interrupted') { return $r('app.string.desktop_compaction_task_stopped'); }
    return this.row.error ?? this.row.fallbackSummary ?? $r('app.string.desktop_trace_completed');
  }

  private failed(): boolean {
    return this.row.status === 'interrupted' || (this.row.status === 'ended' && this.row.error !== undefined);
  }

  private actionDescription(): Resource {
    if (this.canOpen()) { return $r('app.string.desktop_compaction_open'); }
    return this.expanded ? $r('app.string.desktop_question_collapse') : $r('app.string.desktop_question_expand');
  }

  private statusLabel(): Resource | undefined {
    if (this.opening || this.row.status === 'running') { return $r('app.string.status_running'); }
    return this.failed() ? $r('app.string.desktop_trace_failed') : undefined;
  }

  private dismissTooltip(): void {
    if (this.tooltipTimer !== -1) {
      clearTimeout(this.tooltipTimer);
      this.tooltipTimer = -1;
    }
    this.tooltipVisible = false;
  }

  private syncTooltip(): void {
    if (!this.canOpen() || this.opening || (!this.hovered && !this.focused)) {
      this.dismissTooltip();
    } else if (!this.tooltipVisible && this.tooltipTimer === -1) {
      this.tooltipTimer = setTimeout((): void => {
        this.tooltipTimer = -1;
        this.tooltipVisible = true;
      }, PREVIEW_TOOLTIP_DELAY_MS);
    }
  }

  private async openSummary(): Promise<void> {
    const sequence: number | undefined = this.row.summarySequence;
    if (!this.canOpen() || sequence === undefined || this.opening) { return; }
    const generation: number = ++this.previewGeneration;
    const isCurrent: () => boolean = (): boolean => generation === this.previewGeneration;
    this.opening = true;
    this.failure = undefined;
    this.dismissTooltip();
    try {
      const failure: ResourceStr | undefined = await this.onOpenSummary(sequence, isCurrent);
      if (isCurrent()) { this.failure = failure; }
    } catch (error) {
      if (isCurrent()) {
        this.failure = error instanceof Error ? error.message : $r('app.string.desktop_compaction_read_failed');
      }
    } finally {
      if (isCurrent()) { this.opening = false; }
    }
  }

  private active(): boolean {
    return !this.opening && (this.hovered || this.focused || this.pressing);
  }

  private leadingIcon(): Resource {
    if (this.details() !== undefined && this.expanded) { return $r('app.media.dsh_queue_chevron_down_outline'); }
    if (this.active() && (this.canOpen() || this.details() !== undefined)) {
      return $r('app.media.dsh_browser_chevron_right_outline');
    }
    return $r('app.media.dsh_compaction_api_outline');
  }

  @Builder
  private Header() {
    Row() {
      Row() {
        if (this.opening || this.row.status === 'running') {
          LoadingProgress().key('desktopCompactionOpening-' + this.row.id)
            .width(this.bodySize).height(this.bodySize).color($r('sys.color.font_tertiary')).accessibilityLevel('no')
        } else {
          Image(this.leadingIcon()).width(this.bodySize).height(this.bodySize)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
        }
      }.width(this.bodySize + 2).justifyContent(FlexAlign.Center).margin({ right: 6 })
      Text(this.title()).fontSize(this.bodySize - 1).fontFamily(this.fontFamily)
        .fontColor(this.active() ? $r('sys.color.font_secondary') : $r('sys.color.font_tertiary')).maxLines(1)
      Circle({ width: 2, height: 2 }).fill($r('sys.color.font_tertiary')).margin({ left: 8, right: 8 })
        .accessibilityLevel('no')
      Text(this.summary()).key('desktopCompactionSummary-' + this.row.id).fontSize(this.bodySize - 1)
        .fontFamily(this.fontFamily).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        .fontColor(this.failed() ? $r('app.color.workspace_status_error')
          : this.active() ? $r('sys.color.font_secondary') : $r('sys.color.font_tertiary'))
    }.width('100%').height(this.bodySize + 10).alignItems(VerticalAlign.Center)
  }

  @Builder
  private PreviewTooltip() {
    Text($r('app.string.desktop_compaction_open')).fontSize(12).fontColor($r('sys.color.font_primary'))
      .padding({ left: 8, right: 8, top: 5, bottom: 5 }).accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column({ space: 4 }) {
      if (this.canOpen() || this.details() !== undefined) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          this.Header()
        }.key((this.canOpen() ? 'desktopCompactionOpen-' : 'desktopCompactionDetails-') + this.row.id)
          .width('100%').height(this.bodySize + 10).padding(0).borderRadius(6).focusOnTouch(false)
          .enabled(!this.opening).accessibilityGroup(true)
          .accessibilityDescription(this.actionDescription())
          .accessibilitySelected(this.expanded)
          .backgroundColor(this.active() ? $r('app.color.workspace_selection') : Color.Transparent)
          .onHover((hovered: boolean): void => {
            this.hovered = hovered;
            this.syncTooltip();
          })
          .onFocus((): void => {
            this.focused = true;
            this.syncTooltip();
          })
          .onBlur((): void => {
            this.focused = false;
            this.syncTooltip();
          })
          .onTouch((event: TouchEvent): void => {
            this.pressing = event.type === TouchType.Down || event.type === TouchType.Move;
          })
          .onClick((): void => {
            if (this.canOpen()) { this.openSummary(); } else { this.expanded = !this.expanded; }
          })
          .bindPopup(this.tooltipVisible, { builder: this.PreviewTooltip(), placement: Placement.Top,
            targetSpace: 6, enableArrow: false, focusable: false, mask: false, autoCancel: false,
            systemMaterial: desktopMenuOptions(Placement.Top).systemMaterial,
            onStateChange: (event): void => { if (!event.isVisible) { this.dismissTooltip(); } } })
      } else {
        this.Header()
      }
      if (this.expanded && this.details() !== undefined) {
        Scroll() {
          Text(this.details()).key('desktopCompactionOutput-' + this.row.id).fontSize(this.bodySize - 2)
            .fontFamily('monospace').fontColor(this.failed() ? $r('app.color.workspace_status_error') :
              $r('sys.color.font_primary')).width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }.constraintSize({ maxHeight: 260 }).width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .borderRadius(8).backgroundColor($r('app.color.workspace_panel'))
          .borderWidth(0.5).borderColor($r('sys.color.comp_divider'))
      }
      if (this.failure !== undefined) {
        Text(this.failure).key('desktopCompactionFailure-' + this.row.id).fontSize(this.bodySize - 1)
          .fontFamily(this.fontFamily).fontColor($r('app.color.workspace_status_error'))
          .width('100%').accessibilityLevel('yes')
      }
    }.key('desktopCompactionMarker-' + this.row.id).width('100%').padding({ top: 2, bottom: 2 })
      .alignItems(HorizontalAlign.Start).accessibilityStateDescription(this.statusLabel())
  }
}
