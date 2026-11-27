import { formatClock, formatDuration } from 'appstate';
import { getBoolean, getField, getNumber } from 'connection';
import { copyText } from 'platform';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopHostActions } from './DesktopHostActions';
import type { DesktopTraceRequest } from './DesktopTraceRequests';
import type { DesktopTraceRow } from './DesktopTrajectoryLog';

const RESULT_ENDPOINT: string = 'toolResults/watch';
const USAGE_FIELDS: string[] = ['inputTokens', 'cacheReadTokens', 'cacheWriteTokens', 'outputTokens', 'reasoningTokens'];

@Component
export struct DesktopTrajectoryInspector {
  host?: DesktopHostActions;
  @Prop @Watch('updateSelection') row: DesktopTraceRow | undefined = undefined;
  @Prop @Watch('updateSelection') sessionId: string = '';
  @Prop codeFamily: string = '';
  @Prop codeSize: number = 12;
  onClose: () => void = (): void => {};
  onRecord: (id: string) => void = (_id: string): void => {};
  @State private active: string = 'overview';
  @State private liveOutput: string | undefined = undefined;
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
    if (row?.kind === 'system') { return row.tools?.length ? ['system', 'tools', 'raw'] : ['system', 'raw']; }
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
    this.syncResult();
  }

  private choose(tab: string): void {
    this.active = tab;
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
      case 'inputTokens': return $r('app.string.desktop_trace_input_tokens');
      case 'cacheReadTokens': return $r('app.string.desktop_trace_cache_read');
      case 'cacheWriteTokens': return $r('app.string.desktop_trace_cache_write');
      case 'outputTokens': return $r('app.string.desktop_trace_output_tokens');
      default: return $r('app.string.desktop_trace_reasoning');
    }
  }

  private usageFields(usage?: Object): string[] {
    return USAGE_FIELDS.filter((field: string): boolean => getNumber(usage, field) !== undefined);
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
      if (request.assistant) {
        Button($r('app.string.desktop_trace_assistant'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTraceRequestAssistant').height(32).fontSize(12)
          .onClick((): void => { this.onRecord(request.assistant ?? ''); })
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
  private Usage(usage?: Object) {
    if (this.usageFields(usage).length > 0) {
      ForEach(this.usageFields(usage), (field: string): void => {
        this.Fact(this.usageLabel(field), String(getNumber(usage, field) ?? 0))
      }, (field: string): string => field)
    } else {
      Text($r('app.string.desktop_trace_usage_unreported')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    }
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
    } else if (this.active === 'usage') { this.Usage(this.row?.request?.usage ?? this.row?.usage) }
    else if (this.active === 'timing') { this.Timing(this.row?.request) }
    else if (this.active === 'input') { this.Code(this.row?.argumentsText ?? '', 'desktopTraceToolInput') }
    else if (this.active === 'output') { this.Result() }
    else if (this.active === 'schema') { this.Code(this.raw(this.row?.schema), 'desktopTraceToolSchema') }
    else if (this.active === 'system') { this.Code(this.row?.content ?? '', 'desktopTraceSystemPrompt') }
    else if (this.active === 'tools') { this.Code(this.raw(this.row?.tools), 'desktopTraceSystemTools') }
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
