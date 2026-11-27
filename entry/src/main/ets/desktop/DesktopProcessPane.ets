import { presentTool, ToolKind, ToolState, toolStateLabel, toolSummaryOf } from 'appstate';
import { getString, parseJson } from 'connection';
import { DesktopProcessGroup, DesktopToolStep } from './DesktopToolLog';
import { desktopFileName } from './DesktopArtifacts';
import type { DesktopInteraction } from './DesktopInteractions';

@Component
export struct DesktopProcessPane {
  @Prop group: DesktopProcessGroup | undefined = undefined;
  @Prop expanded: boolean = false;
  @Prop inspected: string = '';
  @Prop hiddenQuestions: DesktopInteraction[] = [];
  onToggle: () => void = (): void => {};
  onInspect: (id: string) => void = (_id: string): void => {};
  onFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  onQuestionResume: (id: string) => void = (_id: string): void => {};

  private busy(): boolean {
    return this.group?.steps.some((step: DesktopToolStep): boolean =>
      !step.interrupted && step.item.toolState === ToolState.RUNNING) === true;
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

  private questionId(callId: string): string {
    return this.hiddenQuestions.find((row: DesktopInteraction): boolean => row.callId === callId)?.id ?? '';
  }

  private inspect(id: string): void {
    const question = this.questionId(id);
    if (question) { this.onQuestionResume(question); }
    else { this.onInspect(id); }
  }

  @Builder
  private Details(row: DesktopToolStep) {
    Column({ space: 6 }) {
      if (row.item.toolArgs) {
        Text('参数').fontSize(12).fontColor($r('sys.color.font_secondary'))
        Text(row.item.toolArgs.slice(0, 16000)).fontFamily('monospace').fontSize(12).width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      if (row.item.toolOutput || row.error) {
        Text('结果').fontSize(12).fontColor($r('sys.color.font_secondary'))
        Text((row.item.toolOutput || row.error).slice(0, 24000)).fontFamily('monospace').fontSize(12)
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

  @Builder
  private Step(row: DesktopToolStep) {
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
      }.padding({ left: 6, right: 6 }).width('100%').height(34).borderRadius(7)
      .onClick((): void => { this.inspect(row.id); })
      if (this.inspected === row.id) {
        this.Details(row)
      }
    }.width('100%').padding({ left: 9 + Math.min(4, row.depth) * 13 })
  }

  build() {
    Column({ space: 2 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10)
            .rotate({ angle: this.expanded ? 90 : 0 })
          if (this.busy()) { LoadingProgress().width(15).height(15) }
          Text(this.busy() ? '工具执行中' : `执行了 ${this.group?.steps.length ?? 0} 个工具`)
            .fontSize(13).fontColor($r('sys.color.font_secondary'))
          Blank()
        }.width('100%')
      }.padding({ left: 5, right: 5 }).width('100%').height(33).borderRadius(7).onClick(this.onToggle)
      if (this.expanded) {
        ForEach(this.group?.steps ?? [], (row: DesktopToolStep): void => { this.Step(row) },
          (row: DesktopToolStep): string => row.id)
      }
    }.width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
  }
}
