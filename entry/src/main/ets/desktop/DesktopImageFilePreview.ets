import {
  clampDesktopDocumentZoom, desktopDocumentZoomOffset, desktopFitWidthZoom
} from './DesktopDocumentZoomModel';
import { DesktopDocumentZoomControls } from './DesktopDocumentZoomControls';
import type { DesktopDocumentViewState } from './DesktopDocumentZoomModel';

const FRAME_INSET: number = 24;
const CONTROLS_REVEAL_HEIGHT: number = 72;
const CONTROLS_HIDE_DELAY: number = 420;

interface DesktopImageScrollOffset {
  x: number;
  y: number;
}

@Component
export struct DesktopImageFilePreview {
  @Prop @Watch('restartImage') source: string = '';
  @Prop @Watch('restartImage') revision: number = 0;
  @Prop @Watch('activeChanged') active: boolean = true;
  @Prop name: string = '';
  @Prop loading: boolean = false;
  @Prop supported: boolean = true;
  @Prop revealOnHover: boolean = false;
  @Prop initialView: DesktopDocumentViewState | undefined = undefined;
  onViewChange: (view: DesktopDocumentViewState) => void = (_view: DesktopDocumentViewState): void => {};

  @State private viewportWidth: number = 1;
  @State private viewportHeight: number = 1;
  @State private intrinsicWidth: number = 0;
  @State private intrinsicHeight: number = 0;
  @State private fitWidth: boolean = true;
  @State private fixedScale: number = 1;
  @State private failed: boolean = false;
  @State private decoded: boolean = false;
  @State private toolbarVisible: boolean = false;

  private scroller: Scroller = new Scroller();
  private lastSource: string = '';
  private mounted: boolean = false;
  private inRevealZone: boolean = false;
  private controlsActive: boolean = false;
  private pinching: boolean = false;
  private touchInput: boolean = false;
  private pinchScale: number = 1;
  private panOrigin: DesktopImageScrollOffset = { x: 0, y: 0 };
  private pendingOffset?: DesktopImageScrollOffset;
  private scrollTimer: number = -1;
  private hideTimer: number = -1;

  aboutToAppear(): void {
    this.mounted = true;
    this.lastSource = this.source;
    this.restoreZoom();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.cancelInteraction();
  }

  private activeChanged(): void {
    if (!this.active) {
      this.decoded = false;
      this.cancelInteraction();
    }
  }

  private restartImage(): void {
    if (!this.mounted) { return; }
    const changedSource: boolean = this.lastSource !== this.source;
    this.lastSource = this.source;
    this.intrinsicWidth = 0;
    this.intrinsicHeight = 0;
    this.failed = false;
    this.decoded = false;
    this.cancelInteraction();
    if (changedSource) {
      this.restoreZoom();
      this.scrollTo(0, 0);
    }
  }

  private restoreZoom(): void {
    this.fitWidth = this.initialView?.fitWidth ?? true;
    this.fixedScale = clampDesktopDocumentZoom(this.initialView?.scale ?? 1);
  }

  private cancelInteraction(): void {
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
    this.pendingOffset = undefined;
    this.clearHide();
    this.pinching = false;
    this.inRevealZone = false;
    this.controlsActive = false;
    this.touchInput = false;
    this.toolbarVisible = false;
  }

  private identity(): string {
    return this.source + ':' + String(this.revision);
  }

  private isLoaded(): boolean {
    return this.decoded && this.intrinsicWidth > 0 && this.intrinsicHeight > 0 && !this.failed;
  }

  private imageDimensions(identity: string, width: number, height: number, decoded: boolean): void {
    if (!this.active || identity !== this.identity() || width <= 0 || height <= 0 ||
      !Number.isFinite(width) || !Number.isFinite(height)) { return; }
    this.intrinsicWidth = width;
    this.intrinsicHeight = height;
    if (decoded) { this.decoded = true; }
    this.failed = false;
  }

  private viewportMeasured(width: number, height: number): void {
    if (width > 0 && Number.isFinite(width)) { this.viewportWidth = width; }
    if (height > 0 && Number.isFinite(height)) { this.viewportHeight = height; }
  }

  private zoom(): number {
    return this.fitWidth ? desktopFitWidthZoom(this.viewportWidth, this.intrinsicWidth, FRAME_INSET) : this.fixedScale;
  }

  private pictureWidth(): number {
    return Math.max(1, this.intrinsicWidth * this.zoom());
  }

  private pictureHeight(): number {
    return Math.max(1, this.intrinsicHeight * this.zoom());
  }

  private scrollTo(x: number, y: number): void {
    this.scroller.scrollTo({ xOffset: Math.max(0, x), yOffset: Math.max(0, y), animation: false });
  }

  private applyPendingOffset(): void {
    const offset: DesktopImageScrollOffset | undefined = this.pendingOffset;
    this.pendingOffset = undefined;
    if (this.active && offset !== undefined) { this.scrollTo(offset.x, offset.y); }
  }

  private queueOffset(offset: DesktopImageScrollOffset): void {
    this.pendingOffset = offset;
    if (this.scrollTimer === -1) {
      this.scrollTimer = setTimeout((): void => {
        this.scrollTimer = -1;
        this.applyPendingOffset();
      }, 16);
    }
  }

  private updateZoom(next: number, fit: boolean, x: number = this.viewportWidth / 2,
    y: number = this.viewportHeight / 2): void {
    if (!this.isLoaded()) { return; }
    const previous: number = this.zoom();
    if (next !== previous) {
      const offset: OffsetResult = this.scroller.currentOffset();
      const xOffset: number = this.pendingOffset?.x ?? offset.xOffset;
      const yOffset: number = this.pendingOffset?.y ?? offset.yOffset;
      this.queueOffset({
        x: desktopDocumentZoomOffset(this.viewportWidth, this.intrinsicWidth, previous, next, xOffset, x, FRAME_INSET),
        y: desktopDocumentZoomOffset(this.viewportHeight, this.intrinsicHeight, previous, next, yOffset, y, FRAME_INSET)
      });
    }
    this.fixedScale = next;
    this.fitWidth = fit;
    this.onViewChange({ page: 1, scale: next, fitWidth: fit });
  }

  private selectZoom(next: number): void {
    this.updateZoom(clampDesktopDocumentZoom(next), false);
  }

  private selectFit(): void {
    this.updateZoom(desktopFitWidthZoom(this.viewportWidth, this.intrinsicWidth, FRAME_INSET), true);
  }

  private clearHide(): void {
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  private showControls(): void {
    this.clearHide();
    this.toolbarVisible = true;
  }

  private hideLater(): void {
    this.clearHide();
    if (!this.revealOnHover || this.touchInput || this.inRevealZone || this.controlsActive || this.pinching) { return; }
    this.hideTimer = setTimeout((): void => {
      this.hideTimer = -1;
      this.toolbarVisible = false;
    }, CONTROLS_HIDE_DELAY);
  }

  private mouseMoved(event: MouseEvent): void {
    if (!this.active || event.action !== MouseAction.Move) { return; }
    this.touchInput = false;
    this.inRevealZone = event.y >= this.viewportHeight - CONTROLS_REVEAL_HEIGHT;
    if (this.inRevealZone) { this.showControls(); } else { this.hideLater(); }
  }

  private controlActivity(active: boolean): void {
    if (!this.active) { return; }
    this.controlsActive = active;
    if (active) { this.showControls(); } else { this.hideLater(); }
  }

  private startPinch(): void {
    this.pinching = true;
    this.pinchScale = this.zoom();
    this.showControls();
  }

  private stopPinch(): void {
    this.pinching = false;
    this.hideLater();
  }

  private pinch(event: GestureEvent): void {
    this.updateZoom(clampDesktopDocumentZoom(this.pinchScale * event.scale), false, event.pinchCenterX, event.pinchCenterY);
  }

  private startPan(): void {
    const offset: OffsetResult = this.scroller.currentOffset();
    this.panOrigin = { x: offset.xOffset, y: offset.yOffset };
  }

  @Builder
  private ImageSurface(identity: string, source: string) {
    Image(source).key('desktopImageFileSurface')
      .width(this.pictureWidth()).height(this.pictureHeight()).objectFit(ImageFit.Contain).borderRadius(8)
      .supportSvg2(true).draggable(false).opacity(this.isLoaded() ? 1 : 0)
      .accessibilityText($r('app.string.desktop_image_file_preview_name', this.name))
      .onComplete((event): void => {
        if (event !== undefined) {
          this.imageDimensions(identity, event.width, event.height, event.loadingStatus === 1);
        }
      })
      .onError((): void => {
        if (this.active && identity === this.identity()) { this.failed = true; }
      })
      .parallelGesture(PanGesture({ direction: PanDirection.All, distance: 4 }).allowedTypes([SourceTool.MOUSE])
        .onActionStart((): void => { this.startPan(); })
        .onActionUpdate((event: GestureEvent): void => {
          this.scrollTo(this.panOrigin.x - event.offsetX, this.panOrigin.y - event.offsetY);
        }))
  }

  @Builder
  private Scrollport() {
    Scroll(this.scroller) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.active && this.supported && !this.loading && !this.failed && this.source.length > 0) {
          ForEach([this.identity()], (identity: string): void => {
            this.ImageSurface(identity, this.source)
          }, (identity: string): string => identity)
        }
      }.key('desktopImageFileCanvas')
        .width(Math.max(this.viewportWidth, this.pictureWidth() + FRAME_INSET))
        .height(Math.max(this.viewportHeight, this.pictureHeight() + FRAME_INSET))
        .onAreaChange((): void => { this.applyPendingOffset(); })
    }.key('desktopImageFileScrollport').width('100%').height('100%')
      .scrollable(ScrollDirection.FREE).edgeEffect(EdgeEffect.None).scrollBar(BarState.Auto)
      .parallelGesture(PinchGesture({ fingers: 2 }).onActionStart((): void => { this.startPinch(); })
        .onActionUpdate((event: GestureEvent): void => { this.pinch(event); })
        .onActionEnd((): void => { this.stopPinch(); }).onActionCancel((): void => { this.stopPinch(); }))
  }

  @Builder
  private Message(label: Resource, key: string) {
    Text(label).key(key).width('100%').fontSize(13).fontColor($r('sys.color.font_secondary'))
      .textAlign(TextAlign.Center).padding(10)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.Scrollport()
      if (this.active) {
        if (this.loading || (this.supported && this.source.length > 0 && !this.failed && !this.isLoaded())) {
          LoadingProgress().key('desktopImageFilePreviewLoading').width(24).height(24).color($r('sys.color.brand'))
            .accessibilityText($r('app.string.desktop_image_file_preview_loading'))
        } else if (this.failed) {
          this.Message($r('app.string.desktop_image_file_preview_failed'), 'desktopImageFilePreviewFailed')
        } else if (!this.supported || this.source.length === 0) {
          this.Message($r('app.string.desktop_image_file_preview_unsupported'), 'desktopImageFilePreviewUnsupported')
        } else if (this.isLoaded()) {
          DesktopDocumentZoomControls({
            zoomScale: this.zoom(), fitWidth: this.fitWidth, keyPrefix: 'desktopImageFileZoom',
            visible: !this.revealOnHover || this.touchInput || this.toolbarVisible,
            onZoom: (next: number): void => { this.selectZoom(next); },
            onFit: (): void => { this.selectFit(); },
            onActiveChange: (active: boolean): void => { this.controlActivity(active); }
          }).align(Alignment.Bottom).margin({ bottom: 14 })
        }
      }
    }.key('desktopImageFilePreview').width('100%').height('100%').clip(true)
      .hitTestBehavior(this.active ? HitTestMode.Default : HitTestMode.None)
      .onAreaChange((_old: Area, area: Area): void => {
        this.viewportMeasured(Number(area.width), Number(area.height));
      })
      .onMouse((event: MouseEvent): void => { this.mouseMoved(event); })
      .onHover((inside: boolean): void => { if (!inside) { this.inRevealZone = false; this.hideLater(); } })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down && event.source === SourceType.TouchScreen) {
          this.touchInput = true;
          this.showControls();
        }
      })
  }
}
