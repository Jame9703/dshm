import { DesktopDelimitedPreview, DesktopSheetSelection } from './DesktopDelimitedPreview';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopWorkbook, DesktopWorkbookSheet } from './DesktopWorkbookModel';

const ZOOM_PRESETS: number[] = [10, 30, 50, 70, 100, 150, 200, 300, 400];

function featureName(key: string): ResourceStr {
  switch (key) {
    case 'charts': return $r('app.string.desktop_table_charts');
    case 'images': return $r('app.string.desktop_table_images');
    case 'shapes': return $r('app.string.desktop_table_shapes');
    case 'conditionalFormatting': return $r('app.string.desktop_table_conditional_formatting');
    default: return key;
  }
}

@Component
export struct DesktopWorkbookPreview {
  workbook?: DesktopWorkbook;
  @Prop focusScope: string = '';
  @State private active: number = 0;
  @State private zoom: number = 100;
  @State private tabWidth: number = 0;
  @State private tabStripWidth: number = 0;
  private readonly zooms = new Map<number, number>();
  private readonly selections = new Map<number, DesktopSheetSelection>();
  private readonly tabs = new Scroller();

  aboutToAppear(): void { this.active = this.workbook?.active ?? 0; }

  private switchSheet(index: number): void {
    if (this.active === index) { return; }
    this.zooms.set(this.active, this.zoom);
    this.active = index;
    this.zoom = this.zooms.get(index) ?? 100;
  }

  private setZoom(value: number): void { this.zoom = Math.min(400, Math.max(10, value)); }

  private features(): string {
    const manager = this.getUIContext().getHostContext()?.resourceManager;
    const separator = manager?.getStringSync($r('app.string.desktop_table_feature_separator')) ?? ', ';
    return (this.workbook?.unsupported ?? []).map((key: string): string => {
      const name = featureName(key);
      return typeof name === 'string' ? name : manager?.getStringSync(name) ?? key;
    }).join(separator);
  }

  private zoomOptions(): MenuElement[] {
    return ZOOM_PRESETS.map((value: number): MenuElement => ({
      value: String(value) + '%',
      action: (): void => { this.setZoom(value); }
    }));
  }

  @Builder
  private FooterButton(icon: Resource, label: Resource, key: string, size: number, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(icon).width(size).height(size).supportSvg2(true).accessibilityLevel('no')
    }.width(24).height(24).padding(0).borderRadius(4).focusOnTouch(false)
      .enabled(enabled).key(key).accessibilityText(label).onClick(action)
  }

  @Builder
  private Footer() {
    Row({ space: 0 }) {
      if (this.tabStripWidth > this.tabWidth && this.tabWidth > 0) {
        this.FooterButton($r('app.media.dsh_spreadsheet_arrow_doubleleft'), $r('app.string.desktop_table_tabs_left'),
          'desktopWorkbookTabsLeft', 12, true, (): void => { this.tabs.scrollBy(-150, 0); })
        this.FooterButton($r('app.media.dsh_spreadsheet_arrow_doubleright'), $r('app.string.desktop_table_tabs_right'),
          'desktopWorkbookTabsRight', 12, true, (): void => { this.tabs.scrollBy(150, 0); })
      }
      Scroll(this.tabs) {
        Row({ space: 0 }) {
          ForEach(this.workbook?.sheets ?? [], (sheet: DesktopWorkbookSheet, index: number): void => {
            Button(sheet.name, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .height(29).fontSize(12).fontColor('#222222').padding({ left: 10, right: 10 }).borderRadius(0)
              .backgroundColor(index === this.active ? '#efefef' : Color.Transparent).focusOnTouch(false)
              .key('desktopWorkbookSheet-' + index).accessibilitySelected(index === this.active)
              .onClick((): void => { this.switchSheet(index); })
          }, (sheet: DesktopWorkbookSheet): string => sheet.id)
        }.height('100%').onSizeChange((_old: SizeOptions, next: SizeOptions): void => {
          const width = Number(next.width);
          if (width !== this.tabStripWidth) { this.tabStripWidth = width; }
        })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
        .align(Alignment.Start).layoutWeight(1).height(29).key('desktopWorkbookSheets')
        .onSizeChange((_old: SizeOptions, next: SizeOptions): void => {
          const width = Number(next.width);
          if (width !== this.tabWidth) { this.tabWidth = width; }
        })
      this.FooterButton($r('app.media.dsh_spreadsheet_minus'), $r('app.string.desktop_table_zoom_out'),
        'desktopWorkbookZoomOut', 16, this.zoom !== 10, (): void => { this.setZoom(this.zoom - 10); })
      Button(String(this.zoom) + '%', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(24).width(48).fontSize(12).padding(0).borderRadius(4).focusOnTouch(false)
        .fontColor('#222222').key('desktopWorkbookZoom')
        .bindMenu(this.zoomOptions(), desktopMenuOptions(Placement.Top))
      this.FooterButton($r('app.media.dsh_spreadsheet_plus'), $r('app.string.desktop_table_zoom_in'),
        'desktopWorkbookZoomIn', 16, this.zoom !== 400, (): void => { this.setZoom(this.zoom + 10); })
    }.width('100%').height(29).backgroundColor('#f7f7f7').border({ width: { top: 1 }, color: '#dedede' })
  }

  @Builder
  private FeatureNotice() {
    Row({ space: 8 }) {
      Image($r('app.media.dsh_quota_warning_outline')).width(16).height(16).supportSvg2(true)
        .margin({ top: 2 }).accessibilityLevel('no')
      Text($r('app.string.desktop_table_unsupported', this.features())).fontSize(13)
        .fontColor($r('sys.color.warning')).layoutWeight(1).key('desktopWorkbookUnsupported')
    }.width('100%').alignItems(VerticalAlign.Top).padding({ top: 8, bottom: 8, left: 12, right: 12 })
      .backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Column() {
      if ((this.workbook?.unsupported.length ?? 0) > 0) { this.FeatureNotice() }
      WithTheme({ colorMode: ThemeColorMode.LIGHT }) {
        Column() {
          ForEach([this.active], (index: number): void => {
            Column() {
              DesktopDelimitedPreview({ sheet: this.workbook?.sheets[index], focusScope: this.focusScope,
                formulas: this.workbook?.formulas ?? false, zoom: this.zoom, initialSelection: this.selections.get(index),
                onSelection: (selection: DesktopSheetSelection): void => { this.selections.set(index, selection); } })
            }.width('100%').layoutWeight(1)
          }, (index: number): string => String(index))
          this.Footer()
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').key('desktopWorkbookPreview')
  }
}
