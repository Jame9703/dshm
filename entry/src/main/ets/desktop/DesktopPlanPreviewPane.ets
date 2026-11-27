import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { readDesktopPlan } from './DesktopPlan';
import type { DesktopPlanDocument } from './DesktopPlan';
import type { DesktopHostActions } from './DesktopHostActions';

@Component
export struct DesktopPlanPreviewPane {
  host?: DesktopHostActions;
  @Prop sessionId: string = '';
  @Prop @Watch('loadPlan') document: DesktopPlanDocument | undefined = undefined;
  @Prop @Watch('loadPlan') shown: boolean = false;
  onClosePreview: () => void = (): void => {};

  @State private markdown: string = '';
  @State private loading: boolean = false;
  private loaded?: DesktopPlanDocument;
  private revision: number = 0;

  aboutToAppear(): void { this.loadPlan(); }
  aboutToDisappear(): void { this.revision++; }

  private async loadPlan(): Promise<void> {
    const document = this.document;
    const owner = this.host;
    if (document === undefined || !this.shown || this.loaded === document || owner === undefined) { return; }
    const revision = ++this.revision;
    this.loaded = document;
    this.loading = !document.markdown;
    this.markdown = document.markdown;
    if (this.loading) {
      const markdown = await readDesktopPlan(owner, this.sessionId, document);
      if (revision !== this.revision) { return; }
      this.markdown = markdown;
      this.loading = false;
    }
  }

  private retry(): void {
    this.loaded = undefined;
    this.loadPlan();
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(16).fontColor([$r('sys.color.font_secondary')])
        Text('计划预览').fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([$r('sys.color.font_secondary')])
        }
        .key('desktopClosePlanPreview').width(30).height(30).padding(0)
        .accessibilityText('关闭计划预览').onClick(this.onClosePreview)
      }
      .width('100%').height(42).padding({ left: 12, right: 6 })
      .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      if (this.loading) {
        LoadingProgress().width(24).height(24).margin(12).accessibilityText('正在读取计划')
      } else if (!this.markdown) {
        Row({ space: 6 }) {
          Text('无法读取计划').fontSize(13)
          Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.retry(); })
        }.padding(12)
      } else {
        Scroll() {
          Column() {
            MarkdownRenderer({ text: this.markdown })
          }
          .width('100%').padding(16).alignItems(HorizontalAlign.Start)
        }
        .width('100%').layoutWeight(1).align(Alignment.TopStart)
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
    .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }
}
