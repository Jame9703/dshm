import { MarkdownRenderer } from '../view/MarkdownRenderer';

@Component
export struct DesktopPlanPreviewPane {
  @Prop markdown: string = '';
  onClosePreview: () => void = (): void => {};

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
      Scroll() {
        Column() {
          MarkdownRenderer({ text: this.markdown })
        }
        .width('100%').padding(16).alignItems(HorizontalAlign.Start)
      }
      .width('100%').layoutWeight(1).align(Alignment.TopStart)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
    .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }
}
