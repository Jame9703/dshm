import { LengthMetrics } from '@kit.ArkUI';
import { StartupFrameCallback } from '../common/DesktopStartup';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopTurnOutlineItem, desktopTurnOutlinePreview } from './DesktopTurnOutlineModel';

const MARK_PITCH: number = 10;
const RAIL_WIDTH: number = 28;
const FADE_LENGTH: number = 24;

class DesktopTurnRailSource implements IDataSource {
  private marks: DesktopTurnOutlineItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.marks.length; }
  getData(index: number): DesktopTurnOutlineItem { return this.marks[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }

  reset(items: DesktopTurnOutlineItem[]): void {
    this.marks = items;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }
}

/** A left-edge navigation rail over the chat scrollport. The transcript owns paging and jumping. */
@Component
export struct DesktopTurnOutline {
  @Prop @Watch('turnRowsChanged') items: DesktopTurnOutlineItem[] = [];
  @Prop @Watch('scheduleRailFollow') activeTurn: number = -1;
  @Prop busyTurn: number = -1;
  @Prop @Watch('scheduleRailFollow') transcriptHeight: number = 0;
  onNavigate: (item: DesktopTurnOutlineItem) => void = (_item: DesktopTurnOutlineItem): void => {};

  @State private previewTurn: number = -1;
  @State private previewPrompt: string = '';
  @State private previewResponse: string = '';
  private readonly marks: DesktopTurnRailSource = new DesktopTurnRailSource();
  private readonly railScroller: Scroller = new Scroller();
  private railMounted: boolean = false;
  private railFollowQueued: boolean = false;
  private pointerInside: boolean = false;
  private hoverTurn: number = -1;
  private focusTurn: number = -1;
  private firstMark: number = -1;
  private lastMark: number = -1;
  private previewedItem?: DesktopTurnOutlineItem;

  aboutToAppear(): void {
    this.railMounted = true;
    this.turnRowsChanged();
  }

  aboutToDisappear(): void {
    this.railMounted = false;
    this.previewedItem = undefined;
  }

  private lengthVp(): number {
    return this.items.length < 2 ? 0 :
      Math.min(420, Math.max(0, this.transcriptHeight - 64), this.items.length * MARK_PITCH + 2);
  }

  private turnIndex(turn: number): number {
    let start = 0;
    let end = this.items.length;
    while (start < end) {
      const middle = Math.floor((start + end) / 2);
      if (this.items[middle].turn < turn) { start = middle + 1; }
      else { end = middle; }
    }
    return this.items[start]?.turn === turn ? start : -1;
  }

  private currentItem(turn: number): DesktopTurnOutlineItem | undefined {
    return this.items[this.turnIndex(turn)];
  }

  private turnRowsChanged(): void {
    this.marks.reset(this.items);
    this.updatePreview();
    this.scheduleRailFollow();
  }

  private scheduleRailFollow(): void {
    if (!this.railMounted || this.railFollowQueued || this.pointerInside) { return; }
    this.railFollowQueued = true;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      this.railFollowQueued = false;
      if (!this.railMounted || this.pointerInside || this.lengthVp() >= this.items.length * MARK_PITCH + 2) { return; }
      const index = this.turnIndex(this.activeTurn);
      const edge = Math.ceil(FADE_LENGTH / MARK_PITCH) - 1;
      if (index >= 0 && (index < this.firstMark + edge || index > this.lastMark - edge)) {
        this.railScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
      }
    }));
  }

  private hovering(turn: number, entered: boolean): void {
    if (entered) { this.hoverTurn = turn; }
    else if (this.hoverTurn === turn) { this.hoverTurn = -1; }
    this.updatePreview();
  }

  private focusing(turn: number, entered: boolean): void {
    if (entered) { this.focusTurn = turn; }
    else if (this.focusTurn === turn) { this.focusTurn = -1; }
    this.updatePreview();
  }

  private updatePreview(): void {
    const turn = this.hoverTurn >= 0 ? this.hoverTurn : this.focusTurn;
    const item = turn < 0 ? undefined : this.currentItem(turn);
    if (item === undefined) {
      this.previewTurn = -1;
      this.previewedItem = undefined;
    } else if (item !== this.previewedItem) {
      this.previewedItem = item;
      this.previewPrompt = desktopTurnOutlinePreview(item.prompt, true, item.promptFromOutline);
      this.previewResponse = desktopTurnOutlinePreview(item.response, false, item.responseFromOutline);
      this.previewTurn = turn;
    }
  }

  private markerLength(row: DesktopTurnOutlineItem): number {
    if (this.activeTurn === row.turn) { return 20; }
    if (this.previewTurn === row.turn) { return 18; }
    return (this.currentItem(row.turn)?.anchorIndex ?? row.anchorIndex) < 0 ? 8 : 12;
  }

  private markerLabel(row: DesktopTurnOutlineItem): Resource {
    if ((this.currentItem(row.turn)?.anchorIndex ?? row.anchorIndex) >= 0) {
      return $r('app.string.desktop_turn_outline_jump', row.turn);
    }
    return $r('app.string.desktop_turn_outline_load', row.turn);
  }

  private go(turn: number): void {
    const item = this.currentItem(turn);
    if (item !== undefined && this.busyTurn !== turn) { this.onNavigate(item); }
  }

  @Builder
  private Preview(turn: number) {
    Column({ space: 4 }) {
      Text(this.previewPrompt || $r('app.string.desktop_turn_outline_number', turn))
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (this.previewResponse) {
        Text(this.previewResponse).fontSize(12).fontColor($r('sys.color.font_secondary'))
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
    }.key('desktopTurnOutlinePreview-' + turn).width(300).constraintSize({ maxHeight: 100 })
      .padding({ left: 12, right: 12, top: 10, bottom: 10 }).alignItems(HorizontalAlign.Start)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private Mark(row: DesktopTurnOutlineItem) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row() {
        Blank().width(this.markerLength(row)).height(2).borderRadius(2)
          .backgroundColor(this.activeTurn === row.turn ? $r('sys.color.font_primary') :
            this.previewTurn === row.turn ? $r('sys.color.font_tertiary') : $r('sys.color.comp_divider'))
          .opacity(this.busyTurn === row.turn ? 0.45 : this.markerLength(row) === 8 ? 0.6 : 1)
      }.width('100%').justifyContent(FlexAlign.Start)
    }.key('desktopTurnOutlineMark-' + row.turn).width(RAIL_WIDTH).height(MARK_PITCH)
      .padding(0).borderRadius(8).stateEffect(false).backgroundColor(Color.Transparent).focusOnTouch(false)
      .accessibilityText(this.markerLabel(row)).accessibilitySelected(this.activeTurn === row.turn)
      .onHover((entered: boolean): void => { this.hovering(row.turn, entered); })
      .onFocus((): void => { this.focusing(row.turn, true); })
      .onBlur((): void => { this.focusing(row.turn, false); })
      .onClick((): void => { this.go(row.turn); })
      .bindPopup(this.previewTurn === row.turn, {
        builder: this.Preview(row.turn), placement: Placement.Right, targetSpace: 10, enableArrow: false, focusable: false,
        mask: false, autoCancel: false, systemMaterial: desktopMenuOptions(Placement.Right).systemMaterial
      })
  }

  build() {
    List({ scroller: this.railScroller }) {
      LazyForEach(this.marks, (row: DesktopTurnOutlineItem): void => {
        ListItem() { this.Mark(row) }.height(MARK_PITCH)
      }, (row: DesktopTurnOutlineItem): string => String(row.turn))
    }.key('desktopTurnOutline').accessibilityText($r('app.string.desktop_turn_outline_label'))
      .width(RAIL_WIDTH).height(this.lengthVp()).padding({ top: 1, bottom: 1 })
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.None).cachedCount(3)
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(FADE_LENGTH) })
      .onHover((inside: boolean): void => {
        this.pointerInside = inside;
        if (!inside) {
          this.hoverTurn = -1;
          this.updatePreview();
          this.scheduleRailFollow();
        }
      }).onScrollIndex((first: number, last: number): void => {
        this.firstMark = first;
        this.lastMark = last;
        if (this.hoverTurn >= 0) {
          const index = this.turnIndex(this.hoverTurn);
          if (index < first || index > last) { this.hovering(this.hoverTurn, false); }
        }
      })
  }
}
