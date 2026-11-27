import { DiffLineKind, formatClock, formatDuration } from 'appstate';
import type { DiffLine } from 'appstate';
import { getBoolean, getField } from 'connection';
import { copyText } from 'platform';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopHostActions } from './DesktopHostActions';
import type { DesktopTraceRequest } from './DesktopTraceRequests';
import type { DesktopTraceRow } from './DesktopTrajectoryLog';
import { desktopTracePromptDiff } from './DesktopTracePromptDiff';
import type { DesktopPromptDiffSection, DesktopPromptHunk } from './DesktopTracePromptDiff';
import { desktopTraceUsageLines } from './DesktopTraceUsage';
import type { DesktopTraceUsageLine } from './DesktopTraceUsage';

const RESULT_ENDPOINT: string = 'toolResults/watch';

@Component
export struct DesktopTrajectoryInspector {
  host?: DesktopHostActions;
  @Prop @Watch('updateSelection') row: DesktopTraceRow | undefined = undefined;
  @Prop @Watch('updateSelection') sessionId: string = '';
  @Prop historyIncomplete: boolean = false;
  @Prop codeFamily: string = '';
  @Prop codeSize: number = 12;
  onClose: () => void = (): void => {};
  onRecord: (id: string) => void = (_id: string): void => {};
  @State private active: string = 'overview';
  @State private liveOutput: string | undefined = undefined;
  @State private diff: DesktopPromptDiffSection[] = [];
  private diffRevision: number = 0;
  private selectedId: string = '';
  private selectedSession: string = '';
  private watchingSeq: number = -1;
  private generation: number = 0;
  private retry: number = -1;
  private stopResult?: () => void;
  private mounted: boolean = false;

  aboutToAppear(): void { this.mounted = true; this.updateSelection(); }
  aboutToDisappear(): void { this.mounted = false; this.releaseResult(); }

  private tool(): boolean { return this.row?.kind === 'tool' || this.row?.kind === 'subtool'; }

  private tabs(): string[] {
    const row = this.row;
    if (row?.request !== undefined) {
      return row.request.options !== undefined ? ['overview', 'options', 'usage', 'timing'] : ['overview', 'usage', 'timing'];
    }
    if (this.tool()) {
      const tabs: string[] = ['overview'];
      if (row?.argumentsText) { tabs.push('input'); }
      if (row?.content || (row?.resultSequence ?? -1) >= 0) { tabs.push('output'); }
      return [...tabs, 'schema', 'timing'];
    }
    if (row?.kind === 'system') {
      const tabs: string[] = row.prompt?.previous !== undefined ? ['diff', 'system'] : ['system'];
      if (row.prompt?.current.tools !== undefined) { tabs.push('tools'); }
      if (row.detail !== undefined) { tabs.push('raw'); }
      return tabs;
    }
    if (row?.kind === 'compaction') { return ['overview', 'raw']; }
    return row?.usage !== undefined ? ['overview', 'preview', 'raw', 'source', 'usage'] :
      ['overview', 'preview', 'raw', 'source'];
  }

  private updateSelection(): void {
    const id = this.row?.id ?? '';
    if (this.selectedId !== id || this.selectedSession !== this.sessionId) {
      this.releaseResult();
      this.selectedId = id;
      this.selectedSession = this.sessionId;
      this.active = this.tabs()[0];
    } else if (!this.tabs().includes(this.active)) {
      this.active = this.tabs()[0];
    }
    this.syncTab();
  }

  private choose(tab: string): void {
    this.active = tab;
    this.syncTab();
  }

  private syncTab(): void {
    this.diffRevision++;
    this.diff = this.active === 'diff' ? desktopTracePromptDiff(this.row?.prompt) : [];
    this.syncResult();
  }

  private syncResult(): void {
    const sequence = this.mounted && this.active === 'output' ? this.row?.resultSequence ?? -1 : -1;
    if (sequence === this.watchingSeq) { return; }
    this.releaseResult();
    if (sequence >= 0 && this.sessionId && this.host !== undefined) {
      this.watchingSeq = sequence;
      this.connect();
    }
  }

  private releaseResult(): void {
    this.generation++;
    clearTimeout(this.retry);
    this.retry = -1;
    this.watchingSeq = -1;
    this.stopResult?.();
    this.stopResult = undefined;
    this.liveOutput = undefined;
  }

  private connect(): void {
    const generation = ++this.generation;
    this.stopResult = this.host?.watch(RESULT_ENDPOINT, { 'sessionId': this.sessionId, 'seq': this.watchingSeq }, {
      onItem: (frame: Object): void => {
        if (this.generation !== generation) { return; }
        const value = getField(frame, 'value');
        this.liveOutput = getBoolean(frame, 'available') === true && value !== undefined ? this.raw(value) : undefined;
      },
      onError: (code: string, _message: string): void => { this.streamClosed(generation, code === 'carrier/closed'); },
      onEnd: (): void => { this.streamClosed(generation, true); }
    });
    if (this.stopResult === undefined) { this.streamClosed(generation, true); }
  }

  private streamClosed(generation: number, mayRetry: boolean): void {
    if (generation !== this.generation) { return; }
    this.stopResult = undefined;
    this.liveOutput = undefined;
    if (mayRetry) {
      clearTimeout(this.retry);
      this.retry = setTimeout((): void => {
        if (this.mounted && this.generation === generation && this.watchingSeq >= 0) { this.connect(); }
      }, 1500);
    }
  }

  private raw(value?: Object): string { return value === undefined ? '' : (JSON.stringify(value, undefined, 2) ?? ''); }

  private resultText(): string { return this.liveOutput ?? this.row?.content ?? ''; }

  private tabLabel(tab: string): Resource {
    switch (tab) {
      case 'overview': return $r('app.string.desktop_trace_overview');
      case 'options': return $r('app.string.desktop_trace_options');
      case 'usage': return $r('app.string.desktop_trace_usage');
      case 'timing': return $r('app.string.desktop_trace_timing');
      case 'input': return $r('app.string.desktop_trace_args');
      case 'output': return $r('app.string.desktop_trace_result');
      case 'schema': return $r('app.string.desktop_trace_schema');
      case 'diff': return $r('app.string.desktop_trace_diff');
      case 'system': return $r('app.string.desktop_trace_system_prompt');
      case 'tools': return $r('app.string.desktop_trace_tool_definitions');
      case 'preview': return $r('app.string.desktop_trace_preview');
      case 'source': return $r('app.string.desktop_trace_source');
      default: return $r('app.string.desktop_trace_raw');
    }
  }

  private status(): Resource {
    const status = this.row?.request?.status;
    if (this.row?.failed || status === 'failed') { return $r('app.string.desktop_trace_failed'); }
    if (status === 'interrupted') { return $r('app.string.desktop_trace_interrupted'); }
    if (status === 'running' || (this.tool() && (this.row?.resultSequence ?? -1) < 0)) {
      return $r('app.string.desktop_trace_running');
    }
    return $r('app.string.desktop_trace_completed');
  }

  private usageLabel(field: string): Resource {
    switch (field) {
      case 'input': return $r('app.string.desktop_trace_input_tokens');
      case 'cacheRead': return $r('app.string.desktop_trace_cache_read');
      case 'cacheWrite': return $r('app.string.desktop_trace_cache_write');
      case 'uncached': return $r('app.string.desktop_trace_input_other');
      case 'output': return $r('app.string.desktop_trace_output_tokens');
      case 'content': return $r('app.string.desktop_trace_output_content');
      default: return $r('app.string.desktop_trace_reasoning');
    }
  }

  private usage(cumulative: boolean): DesktopTraceUsageLine[] {
    const request = this.row?.request;
    return desktopTraceUsageLines(cumulative ? request?.cumulativeUsage : request?.usage ?? this.row?.usage);
  }

  private diffColor(kind: DiffLineKind): ResourceColor {
    if (kind === DiffLineKind.ADDED) { return $r('app.color.desktop_diff_added'); }
    if (kind === DiffLineKind.REMOVED) { return $r('app.color.desktop_diff_deleted'); }
    return Color.Transparent;
  }

  private diffText(line: DiffLine): string {
    return (line.kind === DiffLineKind.ADDED ? '+' : line.kind === DiffLineKind.REMOVED ? '-' : ' ') + line.text;
  }

  @Builder
  private Fact(label: Resource, value: ResourceStr) {
    Row({ space: 8 }) {
      Text(label).fontSize(12).fontColor($r('sys.color.font_tertiary'))
      Text(value).fontSize(12).fontColor($r('sys.color.font_primary')).layoutWeight(1)
    }.width('100%')
  }

  @Builder
  private CopyButton(copy: () => void) {
    Row() {
      Blank()
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_session_copy')).width(14).height(14).supportSvg2(true)
      }.width(30).height(28).padding(0).accessibilityText($r('app.string.desktop_trace_copy')).onClick(copy)
    }.width('100%')
  }

  @Builder
  private Code(content: string, key: string) {
    if (content.length > 0) {
      this.CopyButton((): void => { copyText(content); })
      Text(content).key(key).fontSize(this.codeSize).fontFamily(this.codeFamily).copyOption(CopyOptions.LocalDevice)
        .fontColor($r('sys.color.font_primary')).width('100%').padding(8).borderRadius(6)
        .backgroundColor($r('app.color.workspace_panel'))
    } else {
      Text($r('app.string.desktop_trace_unavailable')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    }
  }

  @Builder
  private Result() {
    if (this.resultText().length > 0) {
      this.CopyButton((): void => { copyText(this.resultText()); })
      Text(this.resultText()).key('desktopTraceToolOutput').fontSize(this.codeSize).fontFamily(this.codeFamily)
        .copyOption(CopyOptions.LocalDevice).fontColor($r('sys.color.font_primary'))
        .width('100%').padding(8).borderRadius(6).backgroundColor($r('app.color.workspace_panel'))
    } else {
      Text($r('app.string.desktop_trace_unavailable')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    }
  }

  @Builder
  private Overview(request?: DesktopTraceRequest) {
    this.Fact($r('app.string.desktop_trace_status'), this.status())
    if (request !== undefined) {
      if (request.provider) { this.Fact($r('app.string.desktop_trace_provider'), request.provider) }
      if (request.model) { this.Fact($r('app.string.desktop_trace_model'), request.model) }
      this.Fact($r('app.string.desktop_trace_calls'), String(request.toolCalls))
      if (request.subCalls > 0) { this.Fact($r('app.string.desktop_trace_subcalls'), String(request.subCalls)) }
      if (request.retry !== undefined) {
        this.Code(this.raw(request.retry), 'desktopTraceRetryInfo')
      }
      if (request.problem) {
        Text(request.problem).fontSize(12).fontColor($r('sys.color.warning'))
      }
      if (request.result) {
        Button(request.purpose === 'compaction' ? $r('app.string.desktop_trace_compaction') :
          $r('app.string.desktop_trace_assistant'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTraceRequestAssistant').height(32).fontSize(12)
          .onClick((): void => { this.onRecord(request.result ?? ''); })
      }
    } else if (this.row?.title) {
      Text(this.row?.title ?? '').fontSize(13).fontWeight(FontWeight.Medium)
    }
    if (this.row?.content) {
      Text(this.row?.content ?? '').fontSize(13).fontColor($r('sys.color.font_primary')).maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  private Usage(cumulative: boolean) {
    if (this.usage(cumulative).length > 0) {
      ForEach(this.usage(cumulative), (line: DesktopTraceUsageLine): void => {
        Row({ space: 8 }) {
          Text(this.usageLabel(line.metric)).fontSize(12).fontColor($r('sys.color.font_tertiary'))
          Text($r('app.string.desktop_trace_tokens', line.amount)).fontSize(12)
            .key('desktopTraceUsage-' + (cumulative ? 'cumulative-' : 'request-') + line.metric)
            .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        }.width('100%').padding({ left: line.detail ? 12 : 0 })
      }, (line: DesktopTraceUsageLine): string => line.metric + ':' + line.amount)
    } else {
      Text($r('app.string.desktop_trace_usage_unreported')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    }
  }

  @Builder
  private UsagePanel() {
    if (this.row?.request !== undefined) {
      Text($r('app.string.desktop_trace_this_request')).fontSize(13).fontWeight(FontWeight.Medium)
    }
    this.Usage(false)
    if (this.row?.request !== undefined) {
      Text(this.historyIncomplete ? $r('app.string.desktop_trace_loaded_cumulative') :
        $r('app.string.desktop_trace_session_cumulative')).key('desktopTraceCumulativeHeading')
        .fontSize(13).fontWeight(FontWeight.Medium).padding({ top: 8 })
      this.Usage(true)
    }
  }

  @Builder
  private PromptDiff() {
    ForEach(this.diff, (section: DesktopPromptDiffSection): void => {
      Column({ space: 4 }) {
        Text(this.tabLabel(section.id)).fontSize(13).fontWeight(FontWeight.Medium)
        ForEach(section.hunks, (hunk: DesktopPromptHunk, index: number): void => {
          Column() {
            Text(hunk.header).fontSize(this.codeSize).fontFamily(this.codeFamily).width('100%')
              .fontColor($r('sys.color.font_tertiary')).padding({ left: 6, top: 4, bottom: 4 })
            ForEach(hunk.lines, (line: DiffLine): void => {
              Text(this.diffText(line)).fontSize(this.codeSize).fontFamily(this.codeFamily).width('100%')
                .copyOption(CopyOptions.LocalDevice).padding({ left: 6, right: 6 })
                .backgroundColor(this.diffColor(line.kind))
            }, (_line: DiffLine, offset: number): string => String(offset))
          }.width('100%').borderRadius(6).clip(true).backgroundColor($r('app.color.workspace_panel'))
        }, (hunk: DesktopPromptHunk, index: number): string => hunk.header + ':' + index)
      }.key('desktopTracePromptDiff-' + section.id).width('100%').alignItems(HorizontalAlign.Start)
    }, (section: DesktopPromptDiffSection): string => section.id + ':' + this.diffRevision)
  }

  @Builder
  private Timing(request?: DesktopTraceRequest) {
    if ((this.row?.started ?? 0) > 0) {
      this.Fact($r('app.string.desktop_trace_started'), formatClock(this.row?.started ?? 0))
    }
    if ((this.row?.duration ?? 0) > 0) {
      this.Fact($r('app.string.desktop_trace_duration'), formatDuration(this.row?.duration ?? 0))
    }
    if (request !== undefined && request.firstToken > 0) {
      this.Fact($r('app.string.desktop_trace_ttft'), formatDuration(request.firstToken - request.started))
      if (request.completed > 0) {
        this.Fact($r('app.string.desktop_trace_generation'), formatDuration(request.completed - request.firstToken))
      }
    }
    if ((this.row?.duration ?? 0) <= 0 && request?.status !== 'running') {
      Text($r('app.string.desktop_trace_unavailable')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    }
  }

  @Builder
  private Body() {
    if (this.active === 'overview') { this.Overview(this.row?.request) }
    else if (this.active === 'options') {
      this.Code(this.raw(this.row?.request?.options), 'desktopTraceRequestOptions')
      if (this.row?.request?.defaults !== undefined) {
        Text($r('app.string.desktop_trace_adapter_defaults')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        this.Code(this.raw(this.row?.request?.defaults), 'desktopTraceAdapterDefaults')
      }
    } else if (this.active === 'usage') { this.UsagePanel() }
    else if (this.active === 'timing') { this.Timing(this.row?.request) }
    else if (this.active === 'input') { this.Code(this.row?.argumentsText ?? '', 'desktopTraceToolInput') }
    else if (this.active === 'output') { this.Result() }
    else if (this.active === 'schema') { this.Code(this.raw(this.row?.schema), 'desktopTraceToolSchema') }
    else if (this.active === 'diff') { this.PromptDiff() }
    else if (this.active === 'system') {
      this.Code(this.row?.prompt?.current.system ?? this.row?.content ?? '', 'desktopTraceSystemPrompt')
    } else if (this.active === 'tools') {
      this.Code(this.raw(this.row?.prompt?.current.tools), 'desktopTraceSystemTools')
    }
    else if (this.active === 'preview') {
      if (this.row?.reasoning) {
        Text($r('app.string.desktop_trace_reasoning')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
        MarkdownRenderer({ text: this.row?.reasoning ?? '' })
      }
      MarkdownRenderer({ text: this.row?.content ?? '' })
    } else if (this.active === 'source') {
      this.Code(this.raw(getField(this.row?.detail, 'source') ??
        getField(getField(this.row?.detail, 'message'), 'source')), 'desktopTraceEventSource')
    } else {
      this.Code(this.raw(this.row?.detail), 'desktopTraceEventRaw')
    }
  }

  build() {
    Column() {
      Row({ space: 7 }) {
        if (this.row?.request !== undefined) {
          Text($r('app.string.desktop_trace_request_number', this.row?.request?.number ?? 0))
            .fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        } else {
          Text(this.row?.title || $r('app.string.desktop_trace_event')).fontSize(14).fontWeight(FontWeight.Medium)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true)
        }.key('desktopTraceInspectorClose').width(32).height(32).padding(0)
          .accessibilityText($r('app.string.desktop_trace_close_details')).onClick(this.onClose)
      }.width('100%').height(38)
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.tabs(), (tab: string): void => {
            Button(this.tabLabel(tab), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopTraceInspectorTab-' + tab).height(28).fontSize(12)
              .accessibilitySelected(this.active === tab)
              .backgroundColor(this.active === tab ? $r('app.color.workspace_selection') : Color.Transparent)
              .onClick((): void => { this.choose(tab); })
          }, (tab: string): string => tab)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
      Scroll() {
        Column({ space: 6 }) {
          this.Body()
        }.key('desktopTraceInspectorBody').alignItems(HorizontalAlign.Start).width('100%').padding({ top: 6, bottom: 10 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.key('desktopTraceInspector').width('100%').height('100%').padding({ left: 10, right: 10 })
      .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }
}
