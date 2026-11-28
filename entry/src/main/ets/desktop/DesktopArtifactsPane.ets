import {
  desktopAppliedSummary, DesktopChangedFile, DesktopChangeSummary, DesktopChangeTarget, DesktopDeliveredFile,
  DesktopTurnArtifacts
} from './DesktopArtifacts';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';

const COLLAPSED_FILES: number = 4;

@Component
export struct DesktopArtifactsPane {
  host?: DesktopHostActions;
  @Prop sessionId: string = '';
  @Prop @Watch('reload') artifacts: DesktopTurnArtifacts | undefined = undefined;
  @Prop @Watch('reload') showCodeDiff: boolean = true;
  onFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  onFileAction: (path: string, name: string, reveal: boolean) => void =
    (_path: string, _name: string, _reveal: boolean): void => {};
  onReview: (target: DesktopChangeTarget) => void = (_target: DesktopChangeTarget): void => {};

  @State private summary: DesktopChangeSummary | undefined = undefined;
  @State private expandedFiles: boolean = false;
  @State private expandedChanges: boolean = false;
  private revision: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.revision++;
  }

  private async reload(): Promise<void> {
    const revision = ++this.revision;
    this.summary = undefined;
    const artifacts = this.artifacts;
    if (!this.showCodeDiff || artifacts === undefined) {
      return;
    }
    const summary = artifacts.changeSequence >= 0 ? await this.host?.changeSummary(this.sessionId, artifacts.changeSequence) : undefined;
    if (revision === this.revision) {
      this.summary = summary ?? (artifacts.applied.length > 0 ? desktopAppliedSummary(artifacts) : undefined);
    }
  }

  private openReview(index: number): void {
    const summary = this.summary;
    const sequence = this.artifacts?.changeSequence ?? -1;
    if (this.showCodeDiff && summary !== undefined) {
      this.onReview({ sessionId: this.sessionId, sequence: sequence, summary: summary, index: index });
    }
  }

  private fileOptions(file: DesktopDeliveredFile): MenuElement[] {
    return [
      { value: '在侧边栏预览', action: (): void => { this.onFile(file.path, file.name); } },
      { value: '用系统预览打开', action: (): void => { this.onFileAction(file.path, file.name, false); } },
      { value: '在文件夹中显示', action: (): void => { this.onFileAction(file.path, file.name, true); } }
    ];
  }

  @Builder
  private ChangeCounts(added: number, deleted: number) {
    Text(`+${added}`).fontSize(12).fontFamily('monospace').fontColor($r('app.color.desktop_diff_add_count'))
    Text(`−${deleted}`).fontSize(12).fontFamily('monospace').fontColor($r('app.color.desktop_diff_delete_count'))
  }

  @Builder
  private Changes(summary: DesktopChangeSummary) {
    Column({ space: 2 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.doc_text')).fontSize(17).fontColor([$r('sys.color.font_secondary')])
          Text(summary.applied ? `工具改动 · ${summary.total} 个文件` :
            summary.total === 1 ? `已编辑 ${summary.files[0].display}` : `已编辑 ${summary.total} 个文件`)
            .fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (!summary.applied) {
            this.ChangeCounts(summary.added, summary.deleted)
          }
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([$r('sys.color.font_tertiary')])
        }.width('100%')
      }
      .width('100%').padding({ left: 11, right: 11, top: 6, bottom: 6 }).borderRadius(7)
      .accessibilityDescription('在侧边栏查看本轮改动').onClick((): void => { this.openReview(0); })
      if (summary.total > 1) {
        ForEach(this.expandedChanges ? summary.files : summary.files.slice(0, COLLAPSED_FILES),
          (file: DesktopChangedFile, index: number): void => {
            Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Row({ space: 7 }) {
                Text(file.display).fontSize(13).fontColor($r('sys.color.font_primary')).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                if (file.binary || file.oversized) {
                  Text(file.binary ? '二进制' : '过大').fontSize(12).fontColor($r('sys.color.font_secondary'))
                } else if (!summary.applied) {
                  this.ChangeCounts(file.added, file.deleted)
                }
              }.width('100%')
            }
            .width('100%').height(30).padding({ left: 12, right: 13 }).borderRadius(6)
            .accessibilityDescription(`查看 ${file.display} 的改动`).onClick((): void => { this.openReview(index); })
          }, (file: DesktopChangedFile): string => file.path)
        if (summary.files.length > COLLAPSED_FILES) {
          Button(this.expandedChanges ? '收起' : `全部 ${summary.files.length} 个文件`, { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick((): void => { this.expandedChanges = !this.expandedChanges; })
        }
      }
    }
    .width('100%').padding(4).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private Delivered(file: DesktopDeliveredFile) {
    Row({ space: 3 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.doc_text')).fontSize(20).fontColor([$r('sys.color.font_secondary')])
          Column({ space: 3 }) {
            Text(file.name).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(14)
            Text(file.description || (file.name.lastIndexOf('.') > 0 ?
              file.name.substring(file.name.lastIndexOf('.') + 1).toUpperCase() : '文件'))
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontSize(12).fontColor($r('sys.color.font_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
      }
      .layoutWeight(1).borderRadius(8).padding(9).accessibilityDescription(`在侧边栏预览 ${file.path}`)
      .onClick((): void => { this.onFile(file.path, file.name); })
      Button('⋯', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(32).padding(0)
        .accessibilityDescription(`${file.name} 操作`).bindMenu(this.fileOptions(file), desktopMenuOptions(Placement.BottomRight))
    }
    .width('100%').padding(4).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Column({ space: 6 }) {
      if (this.showCodeDiff && this.summary !== undefined && this.summary.files.length > 0) {
        this.Changes(this.summary)
      }
      ForEach(this.expandedFiles ? this.artifacts?.files ?? [] : this.artifacts?.files.slice(0, COLLAPSED_FILES) ?? [],
        (file: DesktopDeliveredFile): void => { this.Delivered(file) }, (file: DesktopDeliveredFile): string => file.id)
      if ((this.artifacts?.files.length ?? 0) > COLLAPSED_FILES) {
        Button(this.expandedFiles ? '收起' : `全部 ${this.artifacts?.files.length ?? 0} 个文件`,
          { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.expandedFiles = !this.expandedFiles; })
      }
    }
    .width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
  }
}
