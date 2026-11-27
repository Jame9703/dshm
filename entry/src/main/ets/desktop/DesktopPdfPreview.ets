import { PdfView, pdfService, pdfViewManager } from '@kit.PDFKit';
import { DesktopDocumentZoomControls } from './DesktopDocumentZoomControls';
import {
  clampDesktopDocumentZoom, DESKTOP_DOCUMENT_ZOOM_MAXIMUM, DESKTOP_DOCUMENT_ZOOM_MINIMUM
} from './DesktopDocumentZoomModel';
import type { DesktopDocumentViewState } from './DesktopDocumentZoomModel';

type DesktopPdfPhase = 'loading' | 'ready' | 'password' | 'failed';

@Component
export struct DesktopPdfPreview {
  @Prop path: string = '';
  @Prop active: boolean = true;
  @Prop ownerKey: string = '';
  @Prop initialView: DesktopDocumentViewState | undefined = undefined;
  onViewChange: (view: DesktopDocumentViewState) => void = (_view: DesktopDocumentViewState): void => {};
  onOpenSystem?: () => void;

  private sourceKey(): string { return `${this.ownerKey}\u0000${this.path}`; }

  private usable(): boolean {
    return this.path.startsWith('/') && !this.path.includes('\0') &&
      canIUse('SystemCapability.OfficeService.PDFService.Core');
  }

  build() {
    Column() {
      if (this.active && this.usable()) {
        ForEach([this.sourceKey()], (_source: string): void => {
          DesktopPdfReader({ path: this.path, initialView: this.initialView, onViewChange: this.onViewChange,
            onOpenSystem: this.onOpenSystem })
        }, (source: string): string => source)
      } else if (this.active) {
        Column({ space: 12 }) {
          Text($r('app.string.desktop_pdf_unavailable')).fontSize(13).fontColor($r('sys.color.font_secondary'))
          if (this.onOpenSystem !== undefined) {
            Button($r('app.string.desktop_pdf_open_system'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopPdfOpenSystem').onClick((): void => this.onOpenSystem?.())
          }
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(18)
      }
    }.width('100%').height('100%')
  }
}

/** One controller owns one attached view and serializes retries against the PDFKit load lifetime. */
@Component
struct DesktopPdfReader {
  @Prop path: string = '';
  @Prop initialView: DesktopDocumentViewState | undefined = undefined;
  onViewChange: (view: DesktopDocumentViewState) => void = (_view: DesktopDocumentViewState): void => {};
  onOpenSystem?: () => void;
  @State private phase: DesktopPdfPhase = 'loading';
  @State private page: number = 1;
  @State private pages: number = 0;
  @State private previewScale: number = 1;
  @State private fitWidth: boolean = true;
  @State private password: string = '';
  @State private wrongPassword: boolean = false;

  private readonly controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private mounted: boolean = false;
  private attached: boolean = false;
  private loading: boolean = false;
  private allocated: boolean = false;
  private applyingSavedView: boolean = false;

  aboutToAppear(): void { this.mounted = true; }

  aboutToDisappear(): void {
    this.mounted = false;
    this.password = '';
    this.release();
  }

  private attach(): void {
    if (!this.mounted || this.attached) { return; }
    this.attached = true;
    this.controller.registerPageChangedListener((index: number): void => {
      if (!this.ready() || index < 0 || index >= this.pages || index + 1 === this.page) { return; }
      this.page = index + 1;
      this.publishView();
    });
    this.controller.registerPageFitChangedListener((mode: pdfService.PageFit): void => {
      if (!this.ready()) { return; }
      const fit = mode === pdfService.PageFit.FIT_WIDTH;
      if (this.fitWidth !== fit) {
        this.fitWidth = fit;
        this.publishView();
      }
    });
    this.controller.registerScaleChangedListener((scale: number): void => {
      if (!this.ready() || !Number.isFinite(scale) || scale <= 0 || this.previewScale === scale) { return; }
      this.previewScale = scale;
      this.publishView();
    });
    this.load('');
  }

  private ready(): boolean { return this.mounted && this.phase === 'ready'; }

  private release(): void {
    if (this.loading || !this.allocated) { return; }
    this.allocated = false;
    try { this.controller.releaseDocument(); } catch (_) {}
  }

  private async load(password: string): Promise<void> {
    if (!this.mounted || this.loading) { return; }
    this.release();
    this.loading = true;
    this.allocated = true;
    this.phase = 'loading';
    this.password = '';
    try {
      const preferredPage = this.initialView?.page ?? 1;
      const index = Number.isFinite(preferredPage) ? Math.max(0, Math.trunc(preferredPage) - 1) : 0;
      const result = await this.loadAtPage(password, index);
      if (!this.mounted) { return; }
      if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
        this.wrongPassword = password.length > 0;
        this.phase = 'password';
      } else if (result === pdfService.ParseResult.PARSE_SUCCESS) {
        const count = this.controller.getPageCount();
        if (count <= 0) {
          this.phase = 'failed';
          return;
        }
        this.pages = count;
        this.phase = 'ready';
        this.restoreView();
      } else {
        this.phase = 'failed';
      }
    } catch (_) {
      if (this.mounted) { this.phase = 'failed'; }
    } finally {
      this.loading = false;
      if (!this.ready()) { this.release(); }
    }
  }

  private async loadAtPage(password: string, index: number): Promise<pdfService.ParseResult> {
    try {
      return await this.controller.loadDocument(this.path, password, index);
    } catch (_) {
      if (!this.mounted || index === 0) { return pdfService.ParseResult.PARSE_ERROR_FILE; }
      // A reloaded document can have fewer pages than its previous tab state.
      try { this.controller.releaseDocument(); } catch (_) {}
      return this.controller.loadDocument(this.path, password, 0);
    }
  }

  private restoreView(): void {
    this.applyingSavedView = true;
    try {
      this.controller.setMinZoom(DESKTOP_DOCUMENT_ZOOM_MINIMUM);
      this.controller.setMaxZoom(DESKTOP_DOCUMENT_ZOOM_MAXIMUM);
      const saved = this.initialView;
      if (saved?.fitWidth === false) { this.changeZoom(saved.scale); }
      else { this.fit(); }
      this.jump(saved?.page ?? 1);
    } finally {
      this.applyingSavedView = false;
    }
    this.publishView();
  }

  private jump(page: number): void {
    if (!this.ready() || !Number.isFinite(page)) { return; }
    const next = Math.max(1, Math.min(this.pages, Math.trunc(page)));
    if (this.controller.getPageIndex() !== next - 1) { this.controller.goToPage(next - 1); }
    if (next !== this.page) {
      this.page = next;
      this.publishView();
    }
  }

  private changeZoom(requested: number): void {
    if (!this.ready() || !Number.isFinite(requested)) { return; }
    this.fitWidth = false;
    this.previewScale = clampDesktopDocumentZoom(requested);
    this.controller.setPageFit(pdfService.PageFit.FIT_NONE);
    this.controller.setPageZoom(this.previewScale);
    this.publishView();
  }

  private fit(): void {
    if (!this.ready()) { return; }
    this.fitWidth = true;
    this.controller.setPageFit(pdfService.PageFit.FIT_WIDTH);
    const scale = this.controller.getPageZoom();
    if (Number.isFinite(scale) && scale > 0) { this.previewScale = scale; }
    this.publishView();
  }

  private publishView(): void {
    if (!this.ready() || this.applyingSavedView) { return; }
    this.onViewChange({ page: this.page, scale: this.previewScale, fitWidth: this.fitWidth });
  }

  @Builder
  private Toolbar() {
    Row({ space: 10 }) {
      Row({ space: 3 }) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_browser_chevron_left_outline')).width(16).height(16)
            .supportSvg2(true).accessibilityLevel('no')
        }.key('desktopPdfPreviousPage').size({ width: 29, height: 30 }).borderRadius(7)
          .enabled(this.page > 1).focusOnTouch(false).accessibilityText($r('app.string.desktop_pdf_previous_page'))
          .onClick((): void => this.jump(this.page - 1))
        Text($r('app.string.desktop_pdf_page_count', this.page, this.pages)).key('desktopPdfPageCount')
          .fontSize(12).fontColor($r('sys.color.font_secondary')).maxLines(1)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_browser_chevron_right_outline')).width(16).height(16)
            .supportSvg2(true).accessibilityLevel('no')
        }.key('desktopPdfNextPage').size({ width: 29, height: 30 }).borderRadius(7)
          .enabled(this.page < this.pages).focusOnTouch(false).accessibilityText($r('app.string.desktop_pdf_next_page'))
          .onClick((): void => this.jump(this.page + 1))
      }.backgroundColor($r('app.color.workspace_panel')).borderRadius(9).padding({ left: 3, right: 3 })
      DesktopDocumentZoomControls({ zoomScale: this.previewScale, fitWidth: this.fitWidth, keyPrefix: 'desktopPdfZoom',
        onZoom: (scale: number): void => this.changeZoom(scale), onFit: (): void => this.fit() })
    }.margin({ right: 12, bottom: 12 }).key('desktopPdfToolbar')
  }

  @Builder
  private Status() {
    Column({ space: 12 }) {
      if (this.phase === 'loading') {
        LoadingProgress().width(22).height(22).accessibilityLevel('no')
        Text($r('app.string.desktop_pdf_loading')).key('desktopPdfLoading')
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
      } else if (this.phase === 'password') {
        Text(this.wrongPassword ? $r('app.string.desktop_pdf_password_incorrect') :
          $r('app.string.desktop_pdf_password_required')).key('desktopPdfPasswordMessage')
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
        TextInput({ text: this.password, placeholder: $r('app.string.desktop_pdf_password_placeholder') })
          .key('desktopPdfPassword').type(InputType.Password).width('100%').constraintSize({ maxWidth: 340 })
          .onChange((value: string): void => { this.password = value; })
          .onSubmit((): void => { if (this.password) { this.load(this.password); } })
        Button($r('app.string.desktop_pdf_unlock'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(this.password.length > 0).key('desktopPdfUnlock').onClick((): void => { this.load(this.password); })
      } else {
        Text($r('app.string.desktop_pdf_load_failed')).key('desktopPdfLoadFailed')
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
        Button($r('app.string.desktop_pdf_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPdfRetry').onClick((): void => { this.load(''); })
      }
      if (this.phase !== 'loading' && this.onOpenSystem !== undefined) {
        Button($r('app.string.desktop_pdf_open_system'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPdfOpenSystem').onClick((): void => this.onOpenSystem?.())
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(18)
      .backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      PdfView({ controller: this.controller, pageLayout: pdfService.PageLayout.LAYOUT_SINGLE, isContinuous: true,
        showScroll: true, pageFit: pdfService.PageFit.FIT_WIDTH })
        .width('100%').height('100%').onAppear((): void => this.attach())
      if (this.phase === 'ready') {
        this.Toolbar()
      } else {
        this.Status()
      }
    }.width('100%').height('100%').key('desktopPdfReader')
  }
}
