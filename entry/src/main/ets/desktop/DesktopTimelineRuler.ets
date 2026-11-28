import { KeyCode } from '@kit.InputKit';
import { LengthMetrics } from '@kit.ArkUI';
import { StartupFrameCallback } from '../common/DesktopStartup';
import { getArray, getRecord, getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import type { DesktopTimelineReport } from './DesktopTimelineModel';
import type { DesktopTimelineRulerViewport } from './DesktopTimelineViewport';
import { DESKTOP_TIMELINE_NS, desktopTimelineMilliseconds, desktopTimelinePeriods } from './DesktopTimelineSettingsModel';
import { DesktopTimelineRulerIndex, DesktopTimelineScale, desktopTimelineLiveAnchor, desktopTimelineReportInWeek,
  desktopTimelineReportNeedsFit, desktopTimelineRulerFit, desktopTimelineRulerTicks, desktopTimelineScale,
  desktopTimelineZoomOffset, TIMELINE_RULER_DAY, TIMELINE_RULER_HOUR, TIMELINE_RULER_MAX_ZOOM, TIMELINE_RULER_MINUTE,
  TIMELINE_RULER_REPORT_FONT_SIZE, TIMELINE_RULER_WEEK
} from './DesktopTimelineRulerModel';
import type { DesktopTimelineRulerBlock, DesktopTimelineRulerTick } from './DesktopTimelineRulerModel';

const RULER_WIDTH: number = 52;
const MIN_COLUMN: number = 48;
const LEVEL_COLORS: string[] = ['#4084DB', '#43A977', '#7B70D3', '#C98730', '#D46876'];

@Component
export struct DesktopTimelineRuler {
  host?: DesktopHostActions;
  savedViewport?: DesktopTimelineRulerViewport;
  onViewport: (value: DesktopTimelineRulerViewport) => void = (): void => {};
  @Prop @Watch('reportsChanged') reports: DesktopTimelineReport[] = [];
  @Prop @Watch('activeChanged') active: boolean = false;
  @Prop @Watch('wheelModifierChanged') wheelModifierHeld: boolean = false;
  onOpen: (id: string) => void = (_id: string): void => {};

  @State private levels: number[] = [];
  @State private focusLevel: number = -1;
  @State private zoom: number = 1;
  @State private anchor: number = 0;
  @State private pinned: boolean = false;
  @State private unread: boolean = false;
  @State private empty: boolean = true;
  private rendered: boolean = false;
  private weekCheckedAt: number = -1;
  @State private blocks: DesktopTimelineRulerBlock[] = [];
  @State private ticks: DesktopTimelineRulerTick[] = [];
  @State private viewport: number = 380;
  @State private availableWidth: number = 320;
  @State private scrollTop: number = 0;
  @State private configured: number[] = [];
  private readonly vertical = new Scroller();
  private readonly horizontal = new Scroller();
  private pendingViewport?: DesktopTimelineRulerViewport;
  private measuredHeight: boolean = false;
  private measuredWidth: boolean = false;
  private scrollLeft: number = 0;
  private leftVersion: number = 0;
  private applyingLeft: boolean = false;
  private index = new DesktopTimelineRulerIndex([]);
  private mounted: boolean = false;
  private firstFit: boolean = true;
  private clock: number = -1;
  private moveVersion: number = 0;
  private incomingTop: number = -1;
  private readCadenceRequested: boolean = false;
  private newest: string = '';
  private priorPinch: number = 1;
  @State private axisZooming: boolean = false;
  private axisTimer: number = -1;
  private viewportWindowY?: number;

  aboutToAppear(): void {
    this.mounted = true;
    const saved = this.savedViewport;
    if (saved !== undefined) {
      this.pendingViewport = saved;
      this.firstFit = false;
      this.zoom = saved.zoom;
      this.focusLevel = saved.level;
      this.anchor = saved.anchor;
      this.pinned = saved.pinned;
      this.unread = saved.unread;
      this.newest = saved.newest;
      this.scrollLeft = saved.horizontal;
    }
    this.reportsChanged();
    this.activeChanged();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.clearZoomInput();
    this.moveVersion++;
    this.leftVersion++;
    this.stopClock();
  }

  private stopClock(): void {
    if (this.clock >= 0) { clearTimeout(this.clock); this.clock = -1; }
  }

  private activeChanged(): void {
    this.stopClock();
    if (this.mounted && this.active) {
      this.refreshTime();
      this.tick();
      if (!this.readCadenceRequested) { this.readCadence(); }
      this.restoreMeasuredViewport();
      if (this.measuredHeight && this.pendingViewport === undefined) { this.seek(this.scrollTop); }
      this.restoreHorizontal();
    } else { this.clearZoomInput(); }
  }

  private tick(): void {
    if (!this.mounted || !this.active) { return; }
    const untilMinute = TIMELINE_RULER_MINUTE - Date.now() % TIMELINE_RULER_MINUTE;
    this.clock = setTimeout((): void => {
      this.clock = -1;
      if (!this.mounted || !this.active) { return; }
      this.refreshTime();
      this.tick();
    }, untilMinute);
  }

  private async readCadence(): Promise<void> {
    this.readCadenceRequested = true;
    const result = await this.host?.call('settings/describe');
    if (!this.mounted || !result?.ok) { return; }
    const doc = (getArray(result.value, 'namespaces') ?? []).find((item: Object): boolean =>
      getString(item, 'ns') === DESKTOP_TIMELINE_NS);
    const value = getRecord(doc, 'value');
    if (value === undefined) { return; }
    this.configured = desktopTimelinePeriods(value).map(desktopTimelineMilliseconds);
    this.readLevels();
    this.rebuild();
  }

  private readLevels(): void {
    let count = this.configured.length;
    for (const report of this.reports) { count = Math.max(count, report.level + 1); }
    this.levels = Array.from(new Set<number>(this.reports.map((row: DesktopTimelineReport): number => row.level)));
    for (let level = 0; level < count; level++) {
      if (!this.levels.includes(level)) { this.levels = [...this.levels, level]; }
    }
    this.levels = this.levels.slice().sort((a: number, b: number): number => a - b);
    if (this.levels.length > 0 && !this.levels.includes(this.focusLevel)) { this.focusLevel = -1; }
  }

  private reportsChanged(): void {
    if (!this.mounted) { return; }
    const next = this.reports[0]?.id ?? '';
    if (this.pinned && this.newest && next && this.newest !== next) { this.unread = true; }
    this.newest = next;
    this.index = new DesktopTimelineRulerIndex(this.reports);
    this.weekCheckedAt = -1;
    this.readLevels();
    if (!this.pinned) { this.anchor = this.liveAnchor(); }
    if (this.firstFit) { this.tryFit(); }
    this.rebuild();
    this.saveViewport();
  }

  private liveAnchor(): number { return desktopTimelineLiveAnchor(Date.now(), this.reports); }

  private tryFit(): void {
    if (!this.measuredHeight || !this.active) { return; }
    const latest = this.reports.find((row: DesktopTimelineReport): boolean => desktopTimelineReportInWeek(row, this.anchor));
    if (latest === undefined) { return; }
    let lowest = latest.level;
    for (const row of this.reports) {
      if (desktopTimelineReportInWeek(row, this.anchor)) { lowest = Math.min(lowest, row.level); }
    }
    this.focusLevel = lowest;
    this.firstFit = false;
    this.fit(lowest, undefined, false);
  }

  private refreshTime(): void {
    if (this.pinned) { return; }
    const current = this.liveAnchor();
    if (this.anchor !== current) {
      this.anchor = current;
      if (this.scrollTop > 0) {
        const latest = this.reports.find((row: DesktopTimelineReport): boolean => desktopTimelineReportInWeek(row, current));
        this.seek(this.timeScale().position(latest?.end ?? current) - this.viewport * 0.08);
      } else {
        this.rebuild();
      }
    }
  }

  private timeScale(): DesktopTimelineScale { return desktopTimelineScale(this.anchor, this.zoom, this.viewport); }

  private rebuild(): void {
    if (!this.active && this.rendered) { return; }
    const scale = this.timeScale();
    this.blocks = this.index.visible(scale, this.scrollTop, this.viewport);
    this.ticks = desktopTimelineRulerTicks(scale, this.scrollTop, this.viewport);
    if (this.weekCheckedAt !== this.anchor) {
      this.weekCheckedAt = this.anchor;
      this.empty = !this.reports.some((row: DesktopTimelineReport): boolean => desktopTimelineReportInWeek(row, this.anchor));
    }
    this.rendered = true;
  }

  private seek(offset: number): void {
    this.scrollTop = this.timeScale().offset(offset, this.viewport);
    this.rebuild();
    const move = ++this.moveVersion;
    this.incomingTop = this.scrollTop;
    this.saveViewport();
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      if (this.mounted && this.active && this.measuredHeight && this.moveVersion === move) {
        this.vertical.scrollTo({ xOffset: 0, yOffset: this.scrollTop, animation: false });
        setTimeout((): void => {
          if (this.mounted && this.moveVersion === move) { this.incomingTop = -1; }
        }, 70);
      }
    }));
  }

  private didScroll(): void {
    if (!this.active || !this.measuredHeight || this.pendingViewport !== undefined) { return; }
    const offset = this.vertical.currentOffset().yOffset;
    if (!Number.isFinite(offset) || Math.abs(offset - this.scrollTop) < 0.9) {
      if (this.incomingTop >= 0 && Math.abs(offset - this.incomingTop) < 0.9) { this.incomingTop = -1; }
      return;
    }
    // Ignore intermediate offsets while the native scroller is rebinding to a new density.
    if (this.incomingTop >= 0) { return; }
    this.scrollTop = this.timeScale().offset(offset, this.viewport);
    this.pinned = this.scrollTop >= 0.9 || this.anchor < this.liveAnchor() - TIMELINE_RULER_WEEK;
    if (!this.pinned) { this.unread = false; this.anchor = this.liveAnchor(); }
    this.rebuild();
    this.saveViewport();
  }

  private saveViewport(): void {
    if (!this.mounted || !this.active || !this.measuredHeight || this.firstFit || this.pendingViewport !== undefined) { return; }
    this.onViewport({ zoom: this.zoom, level: this.focusLevel, anchor: this.anchor, pinned: this.pinned,
      backMs: Math.max(0, this.anchor - this.timeScale().time(this.scrollTop)), horizontal: this.scrollLeft,
      newest: this.newest, unread: this.unread });
  }

  private restoreMeasuredViewport(): void {
    const saved = this.pendingViewport;
    if (!this.mounted || !this.active || !this.measuredHeight || saved === undefined) { return; }
    this.pendingViewport = undefined;
    this.seek(this.timeScale().position(this.anchor - saved.backMs));
    this.restoreHorizontal();
  }

  private measureHeight(height: number): void {
    if (!this.active || !Number.isFinite(height) || height <= 0) { return; }
    if (this.measuredHeight && Math.abs(this.viewport - height) < 2) { return; }
    const first = !this.measuredHeight;
    const old = this.timeScale();
    const middle = old.time(this.scrollTop + this.viewport / 2);
    this.measuredHeight = true;
    this.viewport = height;
    if (this.pendingViewport !== undefined) {
      this.restoreMeasuredViewport();
    } else if (this.firstFit) {
      this.tryFit();
      if (this.firstFit) { this.seek(0); }
    } else if (first || (!this.pinned && this.scrollTop < 1)) {
      this.seek(this.scrollTop);
    } else {
      this.seek(this.timeScale().position(middle) - height / 2);
    }
  }

  private measureWidth(width: number): void {
    if (!Number.isFinite(width) || width <= 0 || (this.measuredWidth && Math.abs(this.availableWidth - width) < 1)) {
      return;
    }
    this.measuredWidth = true;
    this.availableWidth = width;
    this.restoreHorizontal();
  }

  private saveHorizontal(): void {
    if (!this.active || !this.measuredWidth || this.applyingLeft || this.pendingViewport !== undefined) { return; }
    const offset = this.horizontal.currentOffset().xOffset;
    if (Number.isFinite(offset) && Math.abs(offset - this.scrollLeft) >= 0.9) {
      this.scrollLeft = Math.max(0, offset);
      this.saveViewport();
    }
  }

  private restoreHorizontal(): void {
    if (!this.active || !this.mounted || !this.measuredWidth || this.pendingViewport !== undefined ||
        this.scrollLeft <= 0) { return; }
    const revision = ++this.leftVersion;
    this.applyingLeft = true;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      if (this.mounted && this.active && revision === this.leftVersion) {
        const max = Math.max(0, this.rulerWidth() - this.availableWidth);
        this.horizontal.scrollTo({ xOffset: Math.min(max, this.scrollLeft), yOffset: 0, animation: false });
        setTimeout((): void => {
          if (this.mounted && revision === this.leftVersion) { this.applyingLeft = false; }
        }, 70);
      }
    }));
  }

  private span(level: number): number {
    return this.configured[level] ??
      this.reports.find((row: DesktopTimelineReport): boolean => row.level === level)?.savedPeriod ??
      TIMELINE_RULER_MINUTE;
  }

  private fit(level: number, target?: DesktopTimelineReport, pin: boolean = true): void {
    const near = this.timeScale().time(this.scrollTop + this.viewport * 0.35);
    const window = desktopTimelineRulerFit(this.reports, level, this.span(level), this.anchor, this.viewport, near,
      target, this.reportFontSize());
    this.firstFit = false;
    this.focusLevel = level;
    this.zoom = window.zoom;
    this.pinned = this.pinned || (pin && window.offset > 0);
    this.seek(window.offset);
  }

  private levelClick(level: number): void {
    if (this.focusLevel === level && this.levels.length > 1) {
      this.focusLevel = -1;
      this.rebuild();
      this.saveViewport();
    } else { this.fit(level); }
  }

  private clearZoomInput(): void {
    clearTimeout(this.axisTimer);
    this.axisZooming = false;
  }

  private wheelModifierChanged(): void {
    if (!this.wheelModifierHeld) { this.clearZoomInput(); }
  }

  private rulerKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_EQUALS || event.keyCode === KeyCode.KEYCODE_MINUS) {
      this.adjustZoom(event.keyCode === KeyCode.KEYCODE_MINUS ? -1 : 1, this.viewport / 2);
      return true;
    }
    return false;
  }

  private rulerWheel(event: AxisEvent): void {
    const delta = event.getVerticalAxisValue();
    if (!this.active || delta === 0) { return; }
    clearTimeout(this.axisTimer);
    this.axisZooming = event.getModifierKeyState?.(['Ctrl']) === true || this.wheelModifierHeld;
    if (!this.axisZooming) { return; }
    // The native Scroll also animates a wheel event over subsequent frames.
    this.axisTimer = setTimeout((): void => { this.axisZooming = false; }, 260);
    const pointer = this.viewportWindowY !== undefined && Number.isFinite(event.windowY) ?
      event.windowY - this.viewportWindowY : event.y;
    this.adjustZoom(-Math.max(-240, Math.min(240, delta)) / 300, pointer);
  }

  private rulerScrollOffset(offset: number): number {
    return this.axisZooming || this.wheelModifierHeld ? 0 : offset;
  }

  private adjustZoom(delta: number, pointer: number): void {
    const next = Math.max(0, Math.min(TIMELINE_RULER_MAX_ZOOM, this.zoom + delta));
    if (Math.abs(next - this.zoom) < 0.001) { return; }
    const prior = this.timeScale();
    const actual = this.incomingTop < 0 ? this.vertical.currentOffset().yOffset : this.scrollTop;
    this.firstFit = false;
    this.zoom = next;
    const offset = desktopTimelineZoomOffset(prior, this.timeScale(), Number.isFinite(actual) ? actual : this.scrollTop,
      Math.max(0, Math.min(this.viewport, pointer)), this.viewport);
    if (offset > 0) { this.pinned = true; }
    this.seek(offset);
  }

  private now(): void {
    this.pinned = false;
    this.unread = false;
    this.anchor = this.liveAnchor();
    this.seek(0);
  }

  private lastReport(): void {
    const report = this.reports.find((row: DesktopTimelineReport): boolean => row.end <= this.liveAnchor());
    if (report === undefined) { return; }
    this.pinned = true;
    this.anchor = Math.max(report.end, report.start + 1);
    this.fit(report.level, report);
  }

  private rulerWidth(): number { return Math.max(this.availableWidth, RULER_WIDTH + this.levels.length * MIN_COLUMN); }

  private columnWidth(level: number): number {
    const space = this.rulerWidth() - RULER_WIDTH;
    const count = Math.max(1, this.levels.length);
    if (this.focusLevel < 0 || count === 1) { return space / count; }
    const other = Math.max(MIN_COLUMN, space / (count + 11));
    return level === this.focusLevel ? space - other * (count - 1) : other;
  }

  private leading(level: number): number {
    let x = RULER_WIDTH;
    for (const column of this.levels) {
      if (column === level) { break; }
      x += this.columnWidth(column);
    }
    return x;
  }

  private periodText(ms: number): string {
    if (ms >= TIMELINE_RULER_DAY) { return String(Number((ms / TIMELINE_RULER_DAY).toFixed(2))) + 'd'; }
    if (ms >= TIMELINE_RULER_HOUR) { return String(Number((ms / TIMELINE_RULER_HOUR).toFixed(2))) + 'h'; }
    return String(Number((ms / TIMELINE_RULER_MINUTE).toFixed(2))) + 'm';
  }

  private clockText(time: number): string {
    const date = new Date(time);
    const hh = String(date.getHours()).padStart(2, '0');
    const mm = String(date.getMinutes()).padStart(2, '0');
    return hh + ':' + mm;
  }

  private tickText(time: number): string {
    const day = new Date(time);
    const anchorDay = new Date(this.anchor);
    const window = this.viewport / this.timeScale().density * TIMELINE_RULER_HOUR;
    if (window >= TIMELINE_RULER_DAY || day.toDateString() !== anchorDay.toDateString()) {
      const date = String(day.getMonth() + 1) + '/' + day.getDate();
      return window >= TIMELINE_RULER_DAY ? date : date + ' ' + this.clockText(time);
    }
    return this.clockText(time);
  }

  private reportFontSize(): number {
    const ui = this.getUIContext();
    return ui.px2vp(ui.fp2px(TIMELINE_RULER_REPORT_FONT_SIZE));
  }

  private needsFocus(block: DesktopTimelineRulerBlock): boolean {
    return block.report.level !== this.focusLevel || desktopTimelineReportNeedsFit(block.report, this.timeScale(),
      this.scrollTop, this.viewport, this.zoom, this.reportFontSize());
  }

  private activate(block: DesktopTimelineRulerBlock): void {
    if (this.needsFocus(block)) { this.fit(block.report.level, block.report); }
    else { this.onOpen(block.report.id); }
  }

  @Builder
  private Level(level: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 4 }) {
        Circle({ width: 6, height: 6 }).fill(level < this.configured.length ? LEVEL_COLORS[level] : Color.Transparent)
          .stroke(LEVEL_COLORS[level]).strokeWidth(1).accessibilityLevel('no')
        Text(this.periodText(this.span(level))).fontSize(11).maxLines(1)
      }.justifyContent(FlexAlign.Center).width('100%')
    }.key('desktopTimelineRulerLevel-' + level).width(this.columnWidth(level)).height(36).padding(0)
      .backgroundColor(this.focusLevel === level ? $r('app.color.workspace_panel') : Color.Transparent)
      .borderWidth({ left: 0.5, bottom: this.focusLevel === level ? 2 : 0.5 })
      .borderColor({ left: $r('sys.color.comp_divider'), bottom: this.focusLevel === level ?
        LEVEL_COLORS[level] : $r('sys.color.comp_divider') })
      .accessibilitySelected(this.focusLevel === level)
      .accessibilityText($r('app.string.desktop_timeline_level', level + 1)).onClick((): void => { this.levelClick(level); })
  }

  @Builder
  private Block(block: DesktopTimelineRulerBlock) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 4 }) {
        if (this.columnWidth(block.report.level) >= 104 && block.height >= 34) {
          if (block.height > 60) {
            Text(this.clockText(block.report.end) + ' · ' + this.periodText(block.report.end - block.report.start))
              .fontSize(10).fontColor($r('sys.color.font_secondary')).width('100%')
          }
          Text(block.report.progress[0] ?? '').fontSize(TIMELINE_RULER_REPORT_FONT_SIZE).maxLines(block.height > 70 ? 3 : 1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        } else if (block.height > 15) {
          Text('↗').fontSize(11).fontColor($r('sys.color.font_secondary'))
        }
      }.alignItems(HorizontalAlign.Start).width('100%').height('100%')
        .padding({ left: 5, right: 4, top: Math.max(0, this.scrollTop - block.top) + (block.height > 34 ? 4 : 0) })
    }.width(this.columnWidth(block.report.level) - 6).height(block.height).padding(0).borderRadius(4).clip(true)
      .position({ x: this.leading(block.report.level) + 3, y: block.top })
      .backgroundColor($r('app.color.workspace_panel')).borderWidth({ left: 3 })
      .borderColor(block.report.source === 'no-activity' ? $r('sys.color.comp_divider') : LEVEL_COLORS[block.report.level])
      .key('desktopTimelineReport-' + block.report.id)
      .accessibilityText((block.report.progress[0] ?? '') + ' · ' + this.clockText(block.report.end))
      .onClick((): void => { this.activate(block); })
  }

  @Builder
  private Canvas() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width(this.rulerWidth()).height(this.timeScale().height)
      ForEach(this.levels, (level: number): void => {
        Column().width(this.columnWidth(level)).height(this.timeScale().height)
          .position({ x: this.leading(level), y: 0 })
          .borderWidth({ left: 0.5 }).borderColor($r('sys.color.comp_divider')).hitTestBehavior(HitTestMode.None)
      }, (level: number): string => String(level) + ':' + this.columnWidth(level))
      ForEach(this.ticks, (tick: DesktopTimelineRulerTick): void => {
        Divider().width(this.rulerWidth()).strokeWidth(tick.major ? 0.8 : 0.4).color($r('sys.color.comp_divider'))
          .position({ x: 0, y: tick.position }).hitTestBehavior(HitTestMode.None)
        Text(this.tickText(tick.time)).width(RULER_WIDTH - 5).textAlign(TextAlign.End).fontSize(9)
          .fontColor(tick.major ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
          .position({ x: 0, y: Math.max(0, tick.position - 7) }).hitTestBehavior(HitTestMode.None)
      }, (tick: DesktopTimelineRulerTick): string => String(tick.time) + ':' + tick.position + ':' + tick.major)
      Text(this.clockText(this.anchor)).width(RULER_WIDTH - 5).textAlign(TextAlign.End).fontSize(9)
        .fontColor($r('sys.color.brand')).position({ x: 0, y: 2 }).hitTestBehavior(HitTestMode.None)
      ForEach(this.blocks, (block: DesktopTimelineRulerBlock): void => { this.Block(block) },
        (block: DesktopTimelineRulerBlock): string => block.report.id + ':' + block.top + ':' + block.height + ':' +
          this.columnWidth(block.report.level) + ':' + (block.report.progress[0] ?? ''))
    }.width(this.rulerWidth()).height(this.timeScale().height).clip(true)
  }

  build() {
    Column({ space: 7 }) {
      Row({ space: 5 }) {
        Button('−', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopTimelineRulerZoomOut')
          .width(30).height(30).padding(0).enabled(this.zoom > 0)
          .accessibilityText($r('app.string.desktop_timeline_zoom_out'))
          .onClick((): void => { this.adjustZoom(-1, this.viewport / 2); })
        Text($r('app.string.desktop_timeline_zoom_value', Math.round(this.timeScale().density)))
          .key('desktopTimelineRulerZoomValue').fontSize(11).fontColor($r('sys.color.font_secondary'))
        Button('+', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopTimelineRulerZoomIn')
          .width(30).height(30).padding(0).enabled(this.zoom < TIMELINE_RULER_MAX_ZOOM)
          .accessibilityText($r('app.string.desktop_timeline_zoom_in'))
          .onClick((): void => { this.adjustZoom(1, this.viewport / 2); })
        Blank()
        if (this.pinned || this.scrollTop > 0) {
          Button(this.unread ? $r('app.string.desktop_timeline_now_new') : $r('app.string.desktop_timeline_now'),
            { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).height(30).key('desktopTimelineRulerReturnNow')
            .onClick((): void => { this.now(); })
        }
      }.width('100%')
      Scroll(this.horizontal) {
        Column() {
          Row() {
            Text($r('app.string.desktop_timeline_time_axis')).width(RULER_WIDTH).textAlign(TextAlign.Center).fontSize(11)
            ForEach(this.levels, (level: number): void => { this.Level(level) }, (level: number): string => String(level))
          }.height(36).width(this.rulerWidth()).borderWidth({ bottom: 0.5 }).borderColor($r('sys.color.comp_divider'))
          Stack() {
            Scroll(this.vertical) { this.Canvas() }
              .key('desktopTimelineRulerViewport').width('100%').height('100%')
              .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.None)
              .enableScrollInteraction(!this.wheelModifierHeld && !this.axisZooming)
              .onScrollFrameBegin((offset: number, _state: ScrollState): OnScrollFrameBeginHandlerResult =>
                ({ offsetRemain: this.rulerScrollOffset(offset) }))
              .onDidScroll((_offset: number, _state: ScrollState): void => { this.didScroll(); })
              .onAxisEvent((event: AxisEvent): void => { this.rulerWheel(event); })
              .parallelGesture(PinchGesture({ fingers: 2 })
                .onActionStart((): void => { this.priorPinch = 1; })
                .onActionUpdate((event: PinchGestureEvent): void => {
                  if (event.scale <= 0) { return; }
                  const change = Math.log(event.scale / this.priorPinch);
                  if (Math.abs(change) < 0.03) { return; }
                  this.priorPinch = event.scale;
                  this.adjustZoom(change * 1.3, event.pinchCenterY);
                }))
          }.width(this.rulerWidth()).layoutWeight(1).focusable(true).focusOnTouch(true)
            .focusBox({ strokeWidth: LengthMetrics.vp(0) })
            .onAreaChange((_old: Area, area: Area): void => {
              const location = Number(area.globalPosition.y);
              if (Number.isFinite(location)) { this.viewportWindowY = location; }
              this.measureHeight(Number(area.height));
            })
            .onKeyEvent((event: KeyEvent): boolean => this.rulerKey(event))
        }.width(this.rulerWidth()).height('100%')
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).width('100%').layoutWeight(1)
        .key('desktopTimelineRulerHorizontalViewport')
        .onAreaChange((_old: Area, area: Area): void => { this.measureWidth(Number(area.width)); })
        .onDidScroll((_offset: number, _state: ScrollState): void => { this.saveHorizontal(); })
      if (this.empty) {
        Text($r('app.string.desktop_timeline_empty_window')).width('100%').fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        if (this.reports.some((row: DesktopTimelineReport): boolean => row.end <= this.liveAnchor())) {
          Button($r('app.string.desktop_timeline_jump_last'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineRulerJumpLast').onClick((): void => { this.lastReport(); })
        }
      }
    }.width('100%').height('100%').key('desktopTimelineRuler')
  }
}
