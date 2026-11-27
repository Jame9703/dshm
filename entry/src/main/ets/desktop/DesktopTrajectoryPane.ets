import { formatDuration } from 'appstate';
import { copyText } from 'platform';
import { StartupFrameCallback } from '../common/DesktopStartup';
import type { DesktopTraceRow } from './DesktopTrajectoryLog';

interface TraceLabelRow {
  id: string;
  turn: number;
  event?: DesktopTraceRow;
}

class TraceListSource implements IDataSource {
  private rows: TraceLabelRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.rows.length; }
  getData(index: number): TraceLabelRow { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
  reset(rows: TraceLabelRow[]): void {
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }
  indexOf(event: string): number {
    return this.rows.findIndex((item: TraceLabelRow): boolean => item.event?.id === event);
  }
}

@Component
export struct DesktopTrajectoryPane {
  readRecords?: () => DesktopTraceRow[];
  @Prop @Watch('reload') revision: number = 0;
  @Prop @Watch('reset') sessionId: string = '';
  @Prop hasEarlier: boolean = false;
  @Prop loading: boolean = false;
  @Prop codeFamily: string = '';
  @Prop codeSize: number = 12;
  onEarlier: () => void = (): void => {};
  @State private rows: DesktopTraceRow[] = [];
  @State private query: string = '';
  @State private actualDuration: boolean = false;
  @State private actualTime: boolean = false;
  @State private closedTurns: Set<number> = new Set();
  @State private opened: Set<string> = new Set();
  @State private focused: string = '';
  @State private matchesView: DesktopTraceRow[] = [];
  private readonly ledger: TraceListSource = new TraceListSource();
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.reload(); }

  private reset(): void {
    this.query = '';
    this.closedTurns = new Set();
    this.opened = new Set();
    this.focused = '';
    this.reload();
  }

  private reload(): void {
    this.rows = this.readRecords?.() ?? [];
    this.applySearch();
  }

  private matches(row: DesktopTraceRow, query: string): boolean {
    return query.length === 0 || [row.title, row.content, row.reasoning, row.argumentsText]
      .some((value: string): boolean => value.toLowerCase().includes(query)) ||
      (row.detail !== undefined && (JSON.stringify(row.detail) ?? '').toLowerCase().includes(query));
  }

  private applySearch(): void {
    const query = this.query.trim().toLowerCase();
    this.matchesView = query ?
      this.rows.filter((row: DesktopTraceRow): boolean => this.matches(row, query)) : this.rows;
    this.updateLedger();
  }

  private updateLedger(): void {
    const result: TraceLabelRow[] = [];
    let previous = -1;
    for (const row of this.matchesView) {
      if (row.turn !== previous) {
        result.push({ id: 'turn-' + row.id, turn: row.turn });
        previous = row.turn;
      }
      if (this.query.trim() || !this.closedTurns.has(row.turn)) {
        result.push({ id: row.id + ':' + row.revision, turn: row.turn, event: row });
      }
    }
    this.ledger.reset(result);
  }

  private timeline(): DesktopTraceRow[] {
    return this.matchesView.slice(-50);
  }

  private widthUnits(row: DesktopTraceRow): number {
    return this.actualDuration ? Math.max(1, row.duration) : 1;
  }

  private focus(row: DesktopTraceRow): void {
    const closed = new Set(this.closedTurns);
    closed.delete(row.turn);
    this.closedTurns = closed;
    this.focused = row.id;
    this.updateLedger();
    const index = this.ledger.indexOf(row.id);
    if (index >= 0) {
      this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
        if (this.focused === row.id) { this.scroller.scrollToIndex(index, false, ScrollAlign.START); }
      }));
    }
  }

  private toggleTurn(turn: number): void {
    const next = new Set(this.closedTurns);
    if (!next.delete(turn)) { next.add(turn); }
    this.closedTurns = next;
    this.updateLedger();
  }

  private toggleTurns(): void {
    const all = new Set(this.rows.map((row: DesktopTraceRow): number => row.turn));
    this.closedTurns = this.closedTurns.size === all.size ? new Set() : all;
    this.updateLedger();
  }

  private toggleRow(id: string): void {
    const next = new Set(this.opened);
    if (!next.delete(id)) { next.add(id); }
    this.opened = next;
  }

  private toggleCalls(kind: string): void {
    const calls = this.matchesView.filter((row: DesktopTraceRow): boolean => row.kind === kind);
    const open = !calls.every((row: DesktopTraceRow): boolean => this.opened.has(row.id));
    const next = new Set(this.opened);
    for (const row of calls) {
      if (open) { next.add(row.id); } else { next.delete(row.id); }
    }
    this.opened = next;
  }

  private label(kind: string): Resource {
    switch (kind) {
      case 'user': return $r('app.string.desktop_trace_user');
      case 'assistant': return $r('app.string.desktop_trace_assistant');
      case 'tool': return $r('app.string.desktop_trace_tool');
      case 'subtool': return $r('app.string.desktop_trace_subtool');
      case 'system': return $r('app.string.desktop_trace_system');
      case 'compaction': return $r('app.string.desktop_trace_compaction');
      case 'boundary': return $r('app.string.desktop_trace_boundary');
      default: return $r('app.string.desktop_trace_context');
    }
  }

  private color(row: DesktopTraceRow): ResourceColor {
    if (row.failed) { return $r('sys.color.warning'); }
    switch (row.kind) {
      case 'user': return '#6A9BE4';
      case 'assistant': return '#4777E8';
      case 'tool': return '#7F69C7';
      case 'subtool': return '#AE93DE';
      default: return $r('sys.color.font_tertiary');
    }
  }

  private stamp(row: DesktopTraceRow): string {
    if (this.actualTime) { return row.started > 0 ? new Date(row.started).toLocaleTimeString() : ''; }
    return row.duration > 0 ? formatDuration(row.duration) : '';
  }

  private raw(value?: Object): string {
    return value === undefined ? '' : (JSON.stringify(value, undefined, 2) ?? '');
  }

  @Builder
  private Overview() {
    Row({ space: 2 }) {
      ForEach(this.timeline(), (row: DesktopTraceRow): void => {
        Column()
          .key('desktopTracePoint-' + row.id).height(this.focused === row.id ? 15 : 11)
          .backgroundColor(this.color(row)).borderRadius(2).layoutWeight(this.widthUnits(row))
          .focusable(true).accessibilityText(this.label(row.kind)).accessibilitySelected(this.focused === row.id)
          .onClick((): void => { this.focus(row); })
      }, (row: DesktopTraceRow): string => row.id + ':' + row.revision)
    }.width('100%').height(22)
  }

  @Builder
  private Toolbar() {
    Scroll() {
      Row({ space: 4 }) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 4 }) {
            Image($r('app.media.dsh_trace_duration_outline')).width(14).height(14).supportSvg2(true)
              .accessibilityLevel('no')
            Text($r('app.string.desktop_trace_duration')).fontSize(12)
          }
        }
          .key('desktopTraceDuration').height(30).fontSize(12).accessibilitySelected(this.actualDuration)
          .accessibilityText($r('app.string.desktop_trace_duration'))
          .backgroundColor(this.actualDuration ? $r('app.color.workspace_selection') : Color.Transparent)
          .onClick((): void => { this.actualDuration = !this.actualDuration; })
        Button($r('app.string.desktop_trace_actual_time'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTraceActualTime').height(30).fontSize(12).accessibilitySelected(this.actualTime)
          .backgroundColor(this.actualTime ? $r('app.color.workspace_selection') : Color.Transparent)
          .onClick((): void => { this.actualTime = !this.actualTime; })
        Button($r('app.string.desktop_trace_turns'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTraceToggleTurns').height(30).fontSize(12).onClick((): void => { this.toggleTurns(); })
        Button($r('app.string.desktop_trace_calls'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTraceToggleCalls').height(30).fontSize(12).onClick((): void => { this.toggleCalls('tool'); })
        Button($r('app.string.desktop_trace_subcalls'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTraceToggleSubcalls').height(30).fontSize(12).onClick((): void => { this.toggleCalls('subtool'); })
      }.height(34)
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).constraintSize({ minWidth: 96 }).layoutWeight(1)
  }

  @Builder
  private Details(label: Resource, content: string) {
    if (content) {
      Row({ space: 6 }) {
        Text(label).fontSize(11).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_session_copy')).width(14).height(14).supportSvg2(true)
        }.width(28).height(26).padding(0).accessibilityText($r('app.string.desktop_trace_copy'))
          .onClick((): void => { copyText(content); })
      }.width('100%')
      Text(content).fontSize(this.codeSize).fontFamily(this.codeFamily).copyOption(CopyOptions.LocalDevice)
        .fontColor($r('sys.color.font_primary')).width('100%').padding(8).borderRadius(6)
        .backgroundColor($r('app.color.workspace_panel'))
    }
  }

  @Builder
  private EventRow(row: DesktopTraceRow) {
    Column({ space: 3 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(13).height(13).supportSvg2(true)
            .rotate({ angle: this.opened.has(row.id) ? 0 : -90 }).accessibilityLevel('no')
          Text(this.label(row.kind)).fontSize(12).fontColor(this.color(row))
          if (row.step > 0) {
            Text($r('app.string.desktop_trace_step', row.step)).fontSize(11).fontColor($r('sys.color.font_tertiary'))
          }
          Text(row.title || row.content).fontSize(12).fontColor($r('sys.color.font_primary')).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.stamp(row)).fontSize(11).fontColor($r('sys.color.font_tertiary'))
        }.width('100%').padding({ left: 7 + Math.min(row.depth, 8) * 11, right: 7 })
      }.key('desktopTraceRow-' + row.id).width('100%').height(33).padding(0).borderRadius(6)
        .accessibilitySelected(this.opened.has(row.id))
        .backgroundColor(this.focused === row.id ? $r('app.color.workspace_selection') : Color.Transparent)
        .onClick((): void => { this.toggleRow(row.id); })
      if (this.opened.has(row.id)) {
        Column({ space: 4 }) {
          this.Details($r('app.string.desktop_trace_reasoning'), row.reasoning)
          this.Details($r('app.string.desktop_trace_args'), row.argumentsText)
          this.Details($r('app.string.desktop_trace_output'), row.content)
          this.Details($r('app.string.desktop_trace_usage'), this.raw(row.usage))
          if (row.detail !== undefined) {
            this.Details($r('app.string.desktop_trace_raw'), this.raw(row.detail))
          }
        }.width('100%').padding({ left: 27, right: 6, bottom: 8 })
      }
    }.width('100%').border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        this.Toolbar()
        TextInput({ text: this.query, placeholder: $r('app.string.desktop_trace_search') })
          .key('desktopTraceSearch').height(30).fontSize(12).constraintSize({ minWidth: 100, maxWidth: 186 })
          .onChange((value: string): void => { this.query = value; this.applySearch(); })
      }.width('100%')
      this.Overview()
      if (this.hasEarlier) {
        Button($r('app.string.desktop_chat_earlier'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTraceEarlier').height(30).fontSize(12).onClick(this.onEarlier)
      }
      if (this.rows.length === 0 && !this.loading) {
        Text($r('app.string.desktop_trace_empty')).fontSize(13).fontColor($r('sys.color.font_secondary')).padding(12)
      } else if (this.query && this.matchesView.length === 0) {
        Text($r('app.string.desktop_trace_no_matches')).fontSize(13)
          .fontColor($r('sys.color.font_secondary')).padding(12)
      }
      List({ scroller: this.scroller }) {
        LazyForEach(this.ledger, (item: TraceLabelRow): void => {
          ListItem() {
            if (item.event !== undefined) {
              this.EventRow(item.event)
            } else {
              Button(item.turn > 0 ? $r('app.string.desktop_trace_turn', item.turn) :
                $r('app.string.desktop_trace_between'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                .key('desktopTraceTurn-' + item.turn).height(34).width('100%').align(Alignment.Start)
                .fontSize(13).fontWeight(FontWeight.Medium).accessibilitySelected(!this.closedTurns.has(item.turn))
                .onClick((): void => { this.toggleTurn(item.turn); })
            }
          }
        }, (item: TraceLabelRow): string => item.id)
      }.key('desktopTraceLedger').width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.key('desktopTrajectoryView').width('100%').padding({ left: 20, right: 20, top: 6, bottom: 8 }).layoutWeight(1)
  }
}
