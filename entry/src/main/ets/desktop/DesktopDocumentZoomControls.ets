import { desktopMenuOptions } from './DesktopMenuOptions';
import {
  DESKTOP_DOCUMENT_ZOOM_MAXIMUM, DESKTOP_DOCUMENT_ZOOM_MINIMUM, DESKTOP_DOCUMENT_ZOOM_PRESETS,
  steppedDesktopDocumentZoom
} from './DesktopDocumentZoomModel';

function zoomPercent(scale: number): string {
  return String(Math.round(scale * 100)) + '%';
}

@Component
export struct DesktopDocumentZoomControls {
  @Prop zoomScale: number = 1;
  @Prop fitWidth: boolean = true;
  @Prop visible: boolean = true;
  @Prop showFit: boolean = true;
  @Prop keyPrefix: string = 'desktopDocumentZoom';
  @Prop minimumScale: number = DESKTOP_DOCUMENT_ZOOM_MINIMUM;
  @Prop maximumScale: number = DESKTOP_DOCUMENT_ZOOM_MAXIMUM;
  onZoom: (scale: number) => void = () => {};
  onFit: () => void = () => {};
  onActiveChange: (active: boolean) => void = () => {};

  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private menuOpen: boolean = false;

  aboutToDisappear(): void {
    this.onActiveChange(false);
  }

  private active(): boolean {
    return this.hovered || this.focused || this.menuOpen;
  }

  private focusChanged(focused: boolean): void {
    this.focused = focused;
    this.onActiveChange(this.active());
  }

  private menuChanged(open: boolean): void {
    this.menuOpen = open;
    this.onActiveChange(this.active());
  }

  private options(): MenuOptions {
    const options: MenuOptions = desktopMenuOptions(Placement.TopLeft);
    options.onAppear = (): void => { this.menuChanged(true); };
    options.onDisappear = (): void => { this.menuChanged(false); };
    return options;
  }

  private presets(): number[] {
    return DESKTOP_DOCUMENT_ZOOM_PRESETS.filter((scale: number): boolean =>
      scale >= this.minimumScale && scale <= this.maximumScale);
  }

  @Builder
  private ZoomMenu() {
    Menu() {
      if (this.showFit) {
        MenuItemGroup() {
          MenuItem({ content: $r('app.string.desktop_document_zoom_fit') })
            .key(this.keyPrefix + 'Fit').selectIcon(true).selected(this.fitWidth)
            .onChange((): void => this.onFit())
        }
      }
      MenuItemGroup() {
        ForEach(this.presets(), (scale: number): void => {
          MenuItem({ content: zoomPercent(scale) })
            .key(this.keyPrefix + 'Preset-' + String(Math.round(scale * 100)))
            .selectIcon(true).selected(!this.fitWidth && this.zoomScale === scale)
            .onChange((): void => this.onZoom(scale))
        }, (scale: number): string => String(scale))
      }
    }
  }

  @Builder
  private Tool(direction: number, icon: Resource, label: Resource, suffix: string, enabled: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(icon).width(14).height(14).supportSvg2(true).draggable(false).accessibilityLevel('no')
    }.key(this.keyPrefix + suffix).width(28).height(28).padding(0).borderRadius(6)
      .enabled(enabled).focusOnTouch(false).accessibilityText(label)
      .onFocus((): void => { this.focusChanged(true); }).onBlur((): void => { this.focusChanged(false); })
      .onClick((): void => {
        this.onZoom(steppedDesktopDocumentZoom(this.zoomScale, direction, this.minimumScale, this.maximumScale));
      })
  }

  build() {
    Row({ space: 2 }) {
      this.Tool(-1, $r('app.media.dsh_document_zoom_minus'), $r('app.string.desktop_document_zoom_out'), 'Out',
        this.zoomScale > this.minimumScale)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 2 }) {
          Text(zoomPercent(this.zoomScale)).fontSize(12).fontColor($r('sys.color.font_primary'))
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
        }
      }.key(this.keyPrefix + 'Menu').height(28).constraintSize({ minWidth: 58 })
        .padding({ left: 6, right: 6 }).borderRadius(6).focusOnTouch(false)
        .accessibilityText($r('app.string.desktop_document_zoom_menu'))
        .accessibilityDescription(zoomPercent(this.zoomScale))
        .onFocus((): void => { this.focusChanged(true); }).onBlur((): void => { this.focusChanged(false); })
        .bindMenu(this.ZoomMenu, this.options())
      this.Tool(1, $r('app.media.dsh_reference_menu_plus'), $r('app.string.desktop_document_zoom_in'), 'In',
        this.zoomScale < this.maximumScale)
    }.key(this.keyPrefix + 'Controls').padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .accessibilityDescription($r('app.string.desktop_document_zoom_controls'))
      .border({ width: 0.5, color: $r('app.color.workspace_border'), radius: 12 })
      .backgroundColor($r('app.color.workspace_canvas')).shadow(ShadowStyle.OUTER_DEFAULT_MD)
      .opacity(this.visible || this.active() ? 1 : 0)
      .hitTestBehavior(this.visible || this.active() ? HitTestMode.Default : HitTestMode.None)
      .onHover((hovered: boolean): void => {
        this.hovered = hovered;
        this.onActiveChange(this.active());
      })
  }
}
