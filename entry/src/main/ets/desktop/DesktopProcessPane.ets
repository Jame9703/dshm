import { DiffLineKind, presentTool, ToolKind, ToolState, toolStateLabel, toolSummaryOf } from 'appstate';
import type { DiffLine } from 'appstate';
import { getString, parseJson } from 'connection';
import { DesktopProcessGroup, DesktopToolStep } from './DesktopToolLog';
import { desktopFileName } from './DesktopArtifacts';
import { desktopTimelineStatus } from './DesktopTimelineModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';
import type { DesktopTimelineReceipt, DesktopTimelineReceiptTask } from './DesktopTimelineReceipt';
import { desktopProcessDiff } from './DesktopProcessDiffModel';
import type { DesktopProcessDiffFile, DesktopProcessDiffPreview, DesktopProcessDiffStage } from './DesktopProcessDiffModel';
import { DesktopSkillToolRow } from './DesktopSkillToolRow';

@Component
export struct DesktopProcessPane {
  @Prop group: DesktopProcessGroup | undefined = undefined;
  @Prop expanded: boolean = false;
  @Prop grouped: boolean = true;
  @Prop liveProcessDetail: boolean = false;
  @Prop inspected: string = '';
  @Prop expandedSkills: string[] = [];
  @Prop skillInspection: boolean = false;
  @Prop bodySize: number = 14;
  @Prop bodyFamily: string = '';
  @Prop codeSize: number = 11;
  @Prop timelineDecimals: number = 2;
  @Prop codeFamily: string = 'monospace';
  onToggle: () => void = (): void => {};
  onTimelineReceipt: (tree: string, task: string) => void = (): void => {};
  onInspect: (id: string) => void = (_id: string): void => {};
  onSkillToggle: (id: string) => void = (_id: string): void => {};
  onSkillInspect: (id: string) => void = (_id: string): void => {};
  onFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  onOpenQuestion: (id: string) => boolean = (_id: string): boolean => false;

  private runningStep(): DesktopToolStep | undefined {
    return this.group?.steps.find((step: DesktopToolStep): boolean =>
      !step.interrupted && step.item.toolState === ToolState.RUNNING);
  }

  private runningSummary(): string {
    const step = this.runningStep();
    return step === undefined ? '' : toolSummaryOf(this.kind(step), step.item.toolArgs);
  }

  private kind(row: DesktopToolStep): ToolKind { return presentTool(row.item, '').kind; }

  private icon(kind: ToolKind): Resource {
    if (kind === ToolKind.TERMINAL) { return $r('sys.symbol.code'); }
    if (kind === ToolKind.SEARCH) { return $r('sys.symbol.magnifyingglass'); }
    if (kind === ToolKind.WRITE || kind === ToolKind.EDIT) { return $r('sys.symbol.square_and_pencil'); }
    if (kind === ToolKind.WEB) { return $r('sys.symbol.link'); }
    return $r('sys.symbol.doc_text');
  }

  private status(row: DesktopToolStep): string {
    return row.interrupted ? '已中断' : toolStateLabel(row.item.toolState);
  }

  private filePath(row: DesktopToolStep): string {
    const kind = this.kind(row);
    if (kind !== ToolKind.READ && kind !== ToolKind.WRITE && kind !== ToolKind.EDIT) { return ''; }
    const args = parseJson(row.item.toolArgs);
    return getString(args, 'file_path') ?? getString(args, 'path') ?? '';
  }

  private open(row: DesktopToolStep): void {
    const path = this.filePath(row);
    if (path) { this.onFile(path, desktopFileName(path)); }
  }

  private inspect(id: string): void {
    if (!this.onOpenQuestion(id)) { this.onInspect(id); }
  }

  private filePreviews(row: DesktopToolStep): DesktopProcessDiffPreview[] {
    const pending = row.resultSequence < 0 && !row.interrupted;
    const successful = row.resultSequence >= 0 && row.item.toolState === ToolState.SUCCESS;
    const preview = desktopProcessDiff(row.item.toolName, row.item.toolArgs, pending, successful,
      row.nested === true || row.depth > 0, row.diffMeta);
    return preview === undefined ? [] : [preview];
  }

  private diffTitle(stage: DesktopProcessDiffStage): Resource {
    switch (stage) {
      case 'applied': return $r('app.string.desktop_process_diff_applied');
      case 'written': return $r('app.string.desktop_process_diff_written');
      case 'planned-files': return $r('app.string.desktop_process_diff_files');
      default: return $r('app.string.desktop_process_diff_planned');
    }
  }

  private diffLineBackground(kind: DiffLineKind): ResourceColor {
    if (kind === DiffLineKind.ADDED) { return $r('app.color.desktop_diff_added'); }
    if (kind === DiffLineKind.REMOVED) { return $r('app.color.desktop_diff_deleted'); }
    return Color.Transparent;
  }

  @Builder
  private PreviewLine(line: DiffLine, key: string) {
    Row({ space: 4 }) {
      if (line.kind === DiffLineKind.SKIPPED) {
        Text($r('app.string.desktop_process_diff_context', line.skipped)).fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
      } else {
        Text(line.kind === DiffLineKind.ADDED ? '+' : line.kind === DiffLineKind.REMOVED ? '-' : ' ')
          .fontFamily(this.codeFamily).fontSize(this.codeSize).width(13)
        Text(line.text).fontFamily(this.codeFamily).fontSize(this.codeSize).layoutWeight(1)
          .wordBreak(WordBreak.BREAK_ALL).copyOption(CopyOptions.LocalDevice)
      }
    }.key(key).width('100%').padding({ left: 6, right: 6, top: 2, bottom: 2 })
    .alignItems(VerticalAlign.Top).backgroundColor(this.diffLineBackground(line.kind))
  }

  @Builder
  private DiffFile(file: DesktopProcessDiffFile, key: string, lineKey: string) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        if (file.action === 'delete') {
          Text(file.path).fontSize(12).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text($r('app.string.desktop_process_diff_delete')).fontSize(11)
            .fontColor($r('app.color.desktop_diff_delete_count'))
        } else {
          Button(file.moveTo === undefined ? file.path : file.path + ' → ' + file.moveTo,
            { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key(key + '-Open').height(26).layoutWeight(1).fontSize(12).padding(0)
            .onClick((): void => {
              const path = file.moveTo ?? file.path;
              this.onFile(path, desktopFileName(path));
            })
        }
        if (file.added > 0) {
          Text('+' + file.added.toString()).fontSize(11).fontColor($r('app.color.desktop_diff_add_count'))
        }
        if (file.removed > 0) {
          Text('-' + file.removed.toString()).fontSize(11).fontColor($r('app.color.desktop_diff_delete_count'))
        }
      }.width('100%')
      ForEach(file.lines, (line: DiffLine, index: number): void => {
        this.PreviewLine(line, lineKey + index.toString())
      }, (_line: DiffLine, index: number): string => index.toString())
    }.key(key).width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private FileReview(row: DesktopToolStep) {
    ForEach(this.filePreviews(row), (preview: DesktopProcessDiffPreview): void => {
      Column({ space: 5 }) {
        Text(this.diffTitle(preview.stage)).key('desktopProcessDiffStatus-' + row.id).fontSize(12)
          .fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_secondary'))
        ForEach(preview.files, (file: DesktopProcessDiffFile, index: number): void => {
          this.DiffFile(file, 'desktopProcessDiffFile-' + row.id + '-' + index.toString(),
            'desktopProcessDiffLine-' + row.id + '-' + index.toString() + '-')
        }, (_file: DesktopProcessDiffFile, index: number): string => index.toString())
        if (preview.truncated) {
          Text($r('app.string.desktop_process_diff_truncated')).fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
      }.key((preview.stage === 'planned-files' ? 'desktopProcessPatchFiles-' : 'desktopProcessDiff-') + row.id)
      .alignItems(HorizontalAlign.Start).width('100%').padding(8).borderRadius(8)
      .backgroundColor($r('app.color.workspace_panel'))
    }, (preview: DesktopProcessDiffPreview): string => row.id + ':' + preview.stage + ':' + (row.diffRevision ?? 0))
  }

  @Builder
  private Details(row: DesktopToolStep) {
    Column({ space: 6 }) {
      if (row.item.toolArgs) {
        Text('参数').fontSize(12).fontColor($r('sys.color.font_secondary'))
        Text(row.item.toolArgs.slice(0, 16000)).fontFamily(this.codeFamily).fontSize(this.codeSize).width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      if (row.item.toolOutput || row.error) {
        Text('结果').fontSize(12).fontColor($r('sys.color.font_secondary'))
        Text((row.item.toolOutput || row.error).slice(0, 24000)).fontFamily(this.codeFamily).fontSize(this.codeSize)
          .width('100%').copyOption(CopyOptions.LocalDevice)
      }
      if (row.item.toolOutput.length > 24000 || row.item.toolArgs.length > 16000) {
        Text('内容较长，已截断').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      if (this.filePath(row)) {
        Button('在侧边栏打开文件', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => { this.open(row); })
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding(8).borderRadius(8)
    .backgroundColor($r('app.color.workspace_panel'))
  }

  private percent(value: number): string {
    return desktopTimelinePercent(value, this.timelineDecimals) + '%';
  }

  private progressChange(before: number, after: number): string {
    const prior = this.percent(before);
    const current = this.percent(after);
    return prior === current ? current : prior + ' → ' + current;
  }

  private receiptTime(receipt: DesktopTimelineReceipt): string {
    const time = new Date(receipt.at).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false });
    const previous = receipt.previousAt;
    if (previous === undefined || previous > receipt.at) { return time; }
    const resourceManager = this.getUIContext().getHostContext()?.resourceManager;
    if (resourceManager === undefined) { return time; }
    const hoursLabel = resourceManager.getStringSync($r('app.string.desktop_timeline_hours').id);
    const minutesLabel = resourceManager.getStringSync($r('app.string.desktop_timeline_minutes').id);
    const minutes = Math.floor((receipt.at - previous) / 60000);
    const hours = Math.floor(minutes / 60);
    const duration = minutes < 1 ? '< 1 ' + minutesLabel :
      (hours > 0 ? hours + ' ' + hoursLabel + ' ' : '') + (minutes % 60 > 0 ? (minutes % 60) + ' ' + minutesLabel : '');
    return time + ' · ' +
      resourceManager.getStringSync($r('app.string.desktop_timeline_receipt_gap').id, duration.trim());
  }

  @Builder
  private ReceiptIcon(status: string) {
    if (status === 'done' || status === 'active') {
      Image(status === 'done' ? $r('app.media.dsh_dock_check') : $r('app.media.dsh_clock_outline'))
        .width(14).height(14).supportSvg2(true).accessibilityLevel('no')
    } else {
      Row() {
        Circle({ width: 6, height: 6 }).fill($r('sys.color.font_secondary'))
      }.justifyContent(FlexAlign.Center).width(14).accessibilityLevel('no')
    }
  }

  @Builder
  private ReceiptHeader(callId: string, receipt: DesktopTimelineReceipt) {
    Row({ space: 3 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Image($r('app.media.dsh_timeline_icon')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
          Text($r('app.string.desktop_timeline_receipt_update')).fontSize(13).maxLines(1)
          if (this.inspected !== callId) {
            Text(receipt.title).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1).fontColor($r('sys.color.font_secondary'))
            Text(this.progressChange(receipt.before, receipt.after)).fontSize(12).fontColor($r('sys.color.font_secondary'))
          } else { Blank() }
          Image($r('app.media.dsh_browser_chevron_right_outline')).width(10).height(10).supportSvg2(true)
            .rotate({ angle: this.inspected === callId ? 90 : 0 }).accessibilityLevel('no')
        }.width('100%')
      }.key('desktopProcessStep-' + callId).padding({ left: 6, right: 6 }).layoutWeight(1).height(34).borderRadius(7)
      .onClick((): void => { this.inspect(callId); })
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_browser_right_up_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
      }.key('desktopTimelineReceiptTree-' + callId).width(32).height(32).padding(0).borderRadius(7)
      .accessibilityText($r('app.string.desktop_timeline_task_tree'))
      .onClick((): void => { this.onTimelineReceipt(receipt.tree, ''); })
    }.width('100%')
  }

  @Builder
  private Receipt(callId: string, receipt: DesktopTimelineReceipt) {
    Column({ space: 4 }) {
      Row({ space: 7 }) {
        Image($r('app.media.dsh_timeline_icon')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        Text(receipt.title).fontSize(13).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text(this.progressChange(receipt.before, receipt.after)).fontSize(15).fontWeight(FontWeight.Medium)
      }.width('100%').padding({ left: 7, right: 7, top: 6 })
      Row({ space: 7 }) {
        Text(receipt.branch).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1).fontColor($r('sys.color.font_tertiary'))
        Text(this.receiptTime(receipt)).fontSize(11).fontColor($r('sys.color.font_tertiary'))
      }.width('100%').padding({ left: 7, right: 7, bottom: 4 })
      ForEach(receipt.tasks, (task: DesktopTimelineReceiptTask): void => {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 7 }) {
            this.ReceiptIcon(task.status)
            Column({ space: 2 }) {
              Text(task.title).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (task.note) {
                Text(task.note).fontSize(11).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor($r('sys.color.font_tertiary'))
              }
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (task.status === 'blocked' || task.status === 'paused' || task.status === 'retired') {
              Text(desktopTimelineStatus(task.status)).fontSize(11).fontColor($r('sys.color.font_secondary'))
            }
            Text(this.progressChange(task.before, task.after)).fontSize(12).fontColor($r('sys.color.font_secondary'))
          }.width('100%')
        }.key('desktopTimelineReceiptTask-' + callId + '-' + task.id).width('100%').height(task.note ? 40 : 29)
        .padding({ left: 9, right: 9 }).borderRadius(6)
        .onClick((): void => { this.onTimelineReceipt(receipt.tree, task.id); })
      }, (task: DesktopTimelineReceiptTask): string => task.id)
      if (receipt.total > receipt.tasks.length) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 5 }) {
            Text($r('app.string.desktop_timeline_receipt_more', receipt.total - receipt.tasks.length)).fontSize(12)
            Image($r('app.media.dsh_browser_right_up_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
          }
        }.height(28).onClick((): void => { this.onTimelineReceipt(receipt.tree, ''); })
      }
    }.width('100%').padding(4).borderRadius(8).alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private Step(row: DesktopToolStep) {
    Column({ space: 3 }) {
      if (row.skill !== undefined) {
        DesktopSkillToolRow({ view: row.skill, callId: row.id, open: this.expandedSkills.includes(row.id),
          inspectAvailable: this.skillInspection, bodySize: this.bodySize, bodyFamily: this.bodyFamily,
          codeSize: this.codeSize, codeFamily: this.codeFamily,
          onToggle: (): void => { this.onSkillToggle(row.id); }, onInspect: (): void => { this.onSkillInspect(row.id); } })
      } else if (row.timeline !== undefined) {
        this.ReceiptHeader(row.id, row.timeline)
        if (this.inspected === row.id) { this.Receipt(row.id, row.timeline) }
      } else {
        this.GenericStep(row)
      }
    }.width('100%').padding({ left: 9 + Math.min(4, row.depth) * 13 })
  }

  @Builder
  private GenericStep(row: DesktopToolStep) {
    Column({ space: 3 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          SymbolGlyph(this.icon(this.kind(row))).fontSize(15).fontColor([$r('sys.color.font_secondary')])
          Text(row.item.toolName).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(toolSummaryOf(this.kind(row), row.item.toolArgs)).fontSize(12).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).fontColor($r('sys.color.font_secondary'))
          Text(this.status(row)).fontSize(12).fontColor($r('sys.color.font_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(9)
            .rotate({ angle: this.inspected === row.id ? 90 : 0 }).fontColor([$r('sys.color.font_tertiary')])
        }.width('100%')
      }.key('desktopProcessStep-' + row.id).padding({ left: 6, right: 6 }).width('100%').height(34).borderRadius(7)
      .onClick((): void => { this.inspect(row.id); })
      if (this.inspected === row.id) {
        this.FileReview(row)
        this.Details(row)
      }
    }.width('100%')
  }

  build() {
    Column({ space: 2 }) {
      if (this.grouped) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10)
              .rotate({ angle: this.expanded ? 90 : 0 })
            if (this.runningStep() !== undefined) { LoadingProgress().width(15).height(15) }
            Text(this.runningStep() !== undefined ? '工具执行中' : `执行了 ${this.group?.steps.length ?? 0} 个工具`)
              .fontSize(13).fontColor($r('sys.color.font_secondary'))
            if (this.liveProcessDetail && this.runningSummary()) {
              Text(this.runningSummary()).key('desktopLiveProcessDetail').layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(12).fontColor($r('sys.color.font_tertiary'))
            } else { Blank() }
          }.width('100%')
        }.key('desktopProcessGroup-' + (this.group?.id ?? '')).padding({ left: 5, right: 5 })
          .width('100%').height(33).borderRadius(7).onClick(this.onToggle)
      }
      if (this.expanded || !this.grouped) {
        ForEach(this.group?.steps ?? [], (row: DesktopToolStep): void => { this.Step(row) },
          (row: DesktopToolStep): string => row.id + (row.timelineRevision === 0 ? '' : ':' + row.timelineRevision) +
            (row.diffRevision === undefined ? '' : ':diff:' + row.diffRevision) +
            (row.skillRevision === undefined ? '' : ':skill:' + row.skillRevision))
      }
    }.width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
  }
}
