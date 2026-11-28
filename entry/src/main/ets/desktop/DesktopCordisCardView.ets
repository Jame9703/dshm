import { copyText } from 'platform';
import { desktopCordisCardIcon, desktopCordisCardStatus, desktopCordisCardTitle, desktopCordisOwner }
  from './DesktopCordisCards';
import type { DesktopCordisCard } from './DesktopCordisCards';
import type { DesktopCordisPackage, DesktopCordisRuntime, DesktopCordisSnapshot } from './DesktopCordisRuntime';
import type { DesktopCordisWebLocation } from './DesktopWorkspaceHandoff';

@Component
export struct DesktopCordisCardView {
  runtime?: DesktopCordisRuntime;
  @Prop @Watch('updateCard') card: DesktopCordisCard | undefined = undefined;
  @Prop @Watch('updateReading') sessionId: string = '';
  @Prop codeSize: number = 12;
  @Prop codeFamily: string = 'monospace';
  @Prop inspectAvailable: boolean = true;
  onInspect: (call: string) => void = (_call: string): void => {};
  onWeb: (location: DesktopCordisWebLocation) => void = (): void => {};
  @State private expanded: boolean = false;
  @State private clientSource: boolean = false;
  @State private wrap: boolean = true;
  @State private reading: string = '';
  @State private webRequired: boolean = false;
  @State private runProblem: string = '';
  private snapshot?: DesktopCordisSnapshot;
  private unwatch?: () => void;

  aboutToAppear(): void {
    this.updateCard();
    this.unwatch = this.runtime?.watch((snapshot: DesktopCordisSnapshot): void => {
      this.snapshot = snapshot;
      this.updateReading();
    });
  }

  aboutToDisappear(): void { this.unwatch?.(); }

  private openWeb(): void {
    const card = this.card;
    if (card === undefined || !card.plugin) { return; }
    const snapshot = this.snapshot;
    const row = snapshot === undefined ? undefined : desktopCordisOwner(snapshot, this.sessionId, card.plugin);
    this.onWeb({ pluginId: card.plugin, packageId: card.packageId,
      requestId: row?.target === card.packageId ? row.approval : '' });
  }

  private updateCard(): void {
    this.clientSource = !!this.card?.clientCode;
    this.updateReading();
  }

  private updateReading(): void {
    const card = this.card;
    const snapshot = this.snapshot;
    if (card === undefined) { return; }
    const owner = snapshot === undefined ? undefined : desktopCordisOwner(snapshot, this.sessionId, card.plugin);
    this.reading = desktopCordisCardStatus(card, owner, !!snapshot?.removed.has(card.plugin));
    this.webRequired = (this.reading === 'approval' || this.reading === 'client') && card.action === 'run' &&
      owner?.packages.some((pkg: DesktopCordisPackage): boolean => pkg.id === card.packageId && pkg.hasClient) === true;
    this.runProblem = this.reading === 'failed' && owner?.target === card.packageId ? owner?.problem ?? '' : '';
  }

  private shownStatus(): boolean {
    return this.card?.action !== 'define' || !!this.card?.plugin || this.card?.state !== 'completed';
  }

  private status(): Resource {
    switch (this.reading) {
      case 'removed': return $r('app.string.desktop_cordis_card_removed');
      case 'superseded': return $r('app.string.desktop_cordis_card_superseded');
      case 'client': return $r('app.string.desktop_cordis_client_pending');
      case 'approval': return $r('app.string.desktop_cordis_card_approval');
      case 'failed': return $r('app.string.desktop_cordis_failed');
      case 'interrupted': return $r('app.string.desktop_trace_interrupted');
      case 'completed': return $r('app.string.desktop_trace_completed');
      case 'active': return $r('app.string.desktop_cordis_running');
      case 'running': return $r('app.string.desktop_trace_running');
      default: return $r('app.string.desktop_cordis_card_idle');
    }
  }

  private color(): ResourceColor {
    if (this.reading === 'client' || this.reading === 'approval' || this.reading === 'failed') {
      return $r('sys.color.warning');
    }
    return this.reading === 'active' ? $r('sys.color.brand') : $r('sys.color.font_tertiary');
  }

  private summary(): string {
    if (this.card?.error) { return this.card.error; }
    if (this.card?.action === 'define') { return this.card.name || this.card.id; }
    return this.card?.plugin ? this.card.plugin + (this.card.packageId ? ' · ' + this.card.packageId : '') :
      this.card?.id ?? '';
  }

  private expandable(): boolean { return !!(this.card?.hostCode || this.card?.clientCode || this.card?.output); }

  private source(): string {
    return this.clientSource ? this.card?.clientCode ?? '' : this.card?.hostCode ?? '';
  }

  @Builder
  private Inspect() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image($r('app.media.dsh_cordis_inspect_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
    }.key('desktopCordisInspect-' + this.card?.id).width(28).height(28).padding(0).borderRadius(7)
      .accessibilityText($r('app.string.desktop_cordis_card_inspect'))
      .onClick((): void => { if (this.card !== undefined) { this.onInspect(this.card.id); } })
  }

  @Builder
  private Reading() {
    Text(this.status()).key('desktopCordisCardStatus-' + this.card?.id).fontSize(12).fontColor(this.color())
      .maxLines(1)
  }

  @Builder
  private Title() {
    Image(desktopCordisCardIcon(this.card?.action ?? '')).width(14).height(14)
      .supportSvg2(true).accessibilityLevel('no')
    Text(desktopCordisCardTitle(this.card?.action ?? '', this.card?.mode ?? '')).fontSize(14)
      .fontWeight(FontWeight.Medium).fontColor($r('sys.color.brand')).maxLines(1)
  }

  @Builder
  private Summary(isDefine: boolean) {
    Circle().width(2).height(2).fill($r('sys.color.brand'))
    Text(this.summary()).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor(this.card?.error ? $r('sys.color.warning') : $r('sys.color.font_secondary'))
      .constraintSize({ maxWidth: isDefine && !this.card?.error ? '42%' : '100%' }).layoutWeight(1)
    if (isDefine && !this.card?.error && this.card?.purpose) {
      Text(this.card?.purpose ?? '').fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('sys.color.font_tertiary')).layoutWeight(1)
    }
  }

  @Builder
  private SourceTabs() {
    Row({ space: 3 }) {
      Button('Client', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(28).fontSize(12)
        .key('desktopCordisSourceClient-' + this.card?.id)
        .enabled(!!this.card?.clientCode).accessibilitySelected(this.clientSource)
        .backgroundColor(this.clientSource ? $r('app.color.workspace_selection') : Color.Transparent)
        .onClick((): void => { this.clientSource = true; })
      Button('Host', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(28).fontSize(12)
        .key('desktopCordisSourceHost-' + this.card?.id)
        .enabled(!!this.card?.hostCode).accessibilitySelected(!this.clientSource)
        .backgroundColor(this.clientSource ? Color.Transparent : $r('app.color.workspace_selection'))
        .onClick((): void => { this.clientSource = false; })
      Blank()
      Button($r('app.string.desktop_cordis_card_wrap'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(28).fontSize(11).accessibilitySelected(this.wrap)
        .onClick((): void => { this.wrap = !this.wrap; })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_session_copy')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
      }.width(30).height(28).padding(0).accessibilityText($r('app.string.desktop_trace_copy'))
        .onClick((): void => { copyText(this.source()); })
    }.width('100%')
  }

  @Builder
  private Source() {
    Column({ space: 4 }) {
      this.SourceTabs()
      if (this.wrap) {
        Text(this.source()).key('desktopCordisSourceText-' + this.card?.id).fontSize(this.codeSize)
          .fontFamily(this.codeFamily).width('100%').copyOption(CopyOptions.LocalDevice).padding(6)
      } else {
        Scroll() {
          Text(this.source()).key('desktopCordisSourceText-' + this.card?.id).fontSize(this.codeSize)
            .fontFamily(this.codeFamily).copyOption(CopyOptions.LocalDevice).padding(6)
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).align(Alignment.Start)
      }
    }.width('100%').padding(6).borderRadius(7).backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private Output() {
    if (this.card?.output) {
      Text(this.card?.output ?? '').key('desktopCordisCardOutput-' + this.card?.id).fontSize(this.codeSize)
        .fontFamily(this.codeFamily).fontColor(this.card?.error ? $r('sys.color.warning') : $r('sys.color.font_secondary'))
        .width('100%').copyOption(CopyOptions.LocalDevice)
    }
  }

  @Builder
  private Definition() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 7 }) {
        this.Title()
        this.Summary(true)
        if (this.shownStatus()) { this.Reading() }
        if (this.expandable()) {
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true)
            .rotate({ angle: this.expanded ? 0 : -90 }).accessibilityLevel('no')
        }
      }.width('100%')
    }.key('desktopCordisDefinitionToggle-' + this.card?.id).width('100%').height(33)
      .padding({ left: 6, right: 6 }).borderRadius(7).accessibilitySelected(this.expanded)
      .onClick((): void => { if (this.expandable()) { this.expanded = !this.expanded; } })
    if (this.expanded) {
      Column({ space: 6 }) {
        if (this.card?.hostCode || this.card?.clientCode) { this.Source() }
        if (this.card?.output) {
          Text($r('app.string.desktop_trace_result')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
          this.Output()
        }
        Row({ space: 6 }) {
          if (this.card?.plugin) {
            Text($r('app.string.desktop_cordis_card_hint')).fontSize(11)
              .fontColor($r('sys.color.font_tertiary')).layoutWeight(1)
          } else {
            Blank()
          }
          if (this.inspectAvailable) { this.Inspect() }
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 8, right: 8 })
    }
  }

  @Builder
  private ActionCard() {
    Row({ space: 7 }) {
      this.Title()
      this.Summary(false)
      this.Reading()
      if (this.inspectAvailable) { this.Inspect() }
    }.height(32).width('100%').padding({ left: 6 })
    Column({ space: 4 }) {
      if (this.reading === 'removed' || this.reading === 'superseded') {
        Text(this.reading === 'removed' ? $r('app.string.desktop_cordis_card_missing') :
          $r('app.string.desktop_cordis_card_newer')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      } else {
        if (this.runProblem && this.runProblem !== this.card?.error) {
          Text(this.runProblem).fontSize(12).fontColor($r('sys.color.warning'))
        }
        this.Output()
      }
      if (this.webRequired) {
        Button($r('app.string.desktop_cordis_open_web'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopCordisCardOpenWeb-' + this.card?.id).height(30).fontSize(12)
          .onClick((): void => { this.openWeb(); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 8, right: 8 })
  }

  build() {
    Column({ space: 3 }) {
      if (this.card?.action === 'define') { this.Definition() }
      else { this.ActionCard() }
    }.key('desktopCordisCard-' + this.card?.id).alignItems(HorizontalAlign.Start)
      .width('100%').constraintSize({ maxWidth: 712 })
  }
}
