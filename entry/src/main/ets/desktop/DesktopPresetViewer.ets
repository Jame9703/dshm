import { KeyCode } from '@kit.InputKit';

@Component
export struct DesktopPresetViewer {
  @Prop presetName: string = '';
  @Prop yaml: string = '';
  @Prop maxCodeHeight: number = 560;
  onClose: () => void = (): void => {};

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_preset_view_title', this.presetName))
          .key('desktopPresetViewerTitle').fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_settings_close')).width(14).height(14).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
        }.key('desktopPresetViewerHeaderClose').width(28).height(28).padding(0).borderRadius(8)
          .accessibilityText($r('app.string.desktop_preset_view_close')).onClick(this.onClose)
      }.width('100%')
      Scroll() {
        Text(this.yaml).key('desktopPresetViewerYaml').fontFamily('monospace').fontSize(12.5).lineHeight(18.75)
          .fontColor($r('sys.color.font_secondary')).copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE).draggable(false)
      }.key('desktopPresetViewerScroll').width('100%').constraintSize({ maxHeight: this.maxCodeHeight })
        .scrollable(ScrollDirection.FREE).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.None)
        .align(Alignment.TopStart).padding(12).clip(true).borderRadius(16)
        .border({ width: 0.5, color: $r('app.color.workspace_border') })
        .backgroundColor($r('app.color.desktop_settings_surface'))
      Row() {
        Button($r('app.string.desktop_preset_view_close'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPresetViewerClose').height(36).padding({ left: 14, right: 14 }).fontSize(14)
          .fontColor($r('sys.color.font_primary')).borderRadius(12).defaultFocus(true)
          .border({ width: 0.5, color: $r('app.color.workspace_border') }).onClick(this.onClose)
      }.width('100%').justifyContent(FlexAlign.End)
    }.key('desktopPresetViewer').width('100%').padding(24)
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
        event.stopPropagation();
        this.onClose();
        return true;
      })
  }
}
