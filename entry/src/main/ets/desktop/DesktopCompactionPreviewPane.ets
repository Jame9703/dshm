import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DEFAULT_DESKTOP_TYPOGRAPHY } from './DesktopTheme';
import type { DesktopTypography } from './DesktopTheme';

@Component
export struct DesktopCompactionPreviewPane {
  @Prop markdown: string | undefined = undefined;
  @Prop typography: DesktopTypography = DEFAULT_DESKTOP_TYPOGRAPHY;
  onLink: (url: string) => void = (_url: string): void => {};

  build() {
    Scroll() {
      Column() {
        if (this.markdown === undefined) {
          Text($r('app.string.desktop_compaction_preview_expired'))
            .key('desktopCompactionPreviewExpired').fontSize(this.typography.textSize)
            .fontColor($r('sys.color.font_secondary'))
        } else {
          MarkdownRenderer({ text: this.markdown, typography: this.typography, onLink: this.onLink })
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
      .key('desktopCompactionPreview').accessibilityText($r('app.string.desktop_compaction_preview_title'))
      .backgroundColor($r('app.color.workspace_canvas'))
  }
}
