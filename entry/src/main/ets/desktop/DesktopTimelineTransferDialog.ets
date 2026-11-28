import { randomUuid } from 'connection';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';
import { previewDesktopTimelineCheckpoint } from './DesktopTimelineCheckpoint';
import type { DesktopTimelineCheckpointPreview } from './DesktopTimelineCheckpoint';
import { pickDesktopTimelineCheckpoint } from './DesktopTimelineTransferIO';

export interface DesktopTimelineImportRequest {
  id: string;
  content: string;
  copy: boolean;
  proceed: boolean;
}


@Component
export struct DesktopTimelineTransferDialog {
  @Prop running: boolean = false;
  @Prop progressDecimals: number = 2;
  readOnly: () => boolean = (): boolean => false;
  onBusy: (busy: boolean) => void = (_busy: boolean): void => {};
  onImport: (request: DesktopTimelineImportRequest) => Promise<string> =
    (_request: DesktopTimelineImportRequest): Promise<string> => Promise.resolve('Unavailable');
  onClose: () => void = (): void => {};

  @State private name: string = '';
  @State private preview?: DesktopTimelineCheckpointPreview = undefined;
  @State private copy: boolean = false;
  @State private proceed: boolean = false;
  @State private busy: boolean = false;
  @State private error: string = '';
  private content: string = '';
  private requestId: string = '';
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; }

  aboutToDisappear(): void {
    this.active = false;
    this.content = '';
    this.onBusy(false);
  }

  private setBusy(busy: boolean): void {
    this.busy = busy;
    this.onBusy(busy);
  }

  private resetFile(): void {
    this.content = '';
    this.name = '';
    this.preview = undefined;
    this.requestId = '';
  }

  private localized(resource: Resource): string {
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(resource.id) ?? '';
  }

  private async choose(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined || this.busy) { return; }
    this.setBusy(true);
    this.error = '';
    try {
      const selected = await pickDesktopTimelineCheckpoint(context);
      if (!this.active || selected === undefined) { return; }
      this.resetFile();
      const preview = previewDesktopTimelineCheckpoint(selected.content);
      if (preview === undefined) {
        this.error = this.localized($r('app.string.desktop_timeline_transfer_invalid'));
        return;
      }
      this.requestId = randomUuid();
      this.content = selected.content;
      this.name = selected.name;
      this.preview = preview;
    } catch (error) {
      if (this.active) {
        this.resetFile();
        this.error = this.localized(error instanceof Error && error.message === 'limit' ?
          $r('app.string.desktop_timeline_transfer_limit') : $r('app.string.desktop_timeline_transfer_read_failed'));
      }
    } finally {
      if (this.active) { this.setBusy(false); }
    }
  }

  private async commitImport(): Promise<void> {
    if (!this.active || this.busy || this.preview === undefined || this.running || this.readOnly() ||
      !this.requestId || !this.content) { return; }
    const request: DesktopTimelineImportRequest = { id: this.requestId, content: this.content,
      copy: this.copy, proceed: this.proceed };
    this.setBusy(true);
    this.error = '';
    try {
      const error = await this.onImport(request);
      if (!this.active) { return; }
      if (!error) {
        this.setBusy(false);
        this.onClose();
      } else {
        this.error = error;
      }
    } catch (_) {
      if (this.active) { this.error = this.localized($r('app.string.desktop_timeline_transfer_failed')); }
    } finally {
      if (this.active && this.busy) { this.setBusy(false); }
    }
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.desktop_timeline_import_tree')).fontSize(22).fontWeight(FontWeight.Medium).width('100%')
      Text($r('app.string.desktop_timeline_transfer_hint')).fontSize(13)
        .fontColor($r('sys.color.font_secondary')).width('100%')
      Button($r('app.string.desktop_timeline_transfer_choose'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopTimelineTransferChoose').enabled(!this.busy).onClick((): void => { this.choose(); })
      if (this.preview !== undefined) {
        Column({ space: 5 }) {
          Text(this.preview?.title ?? '').fontSize(15).fontWeight(FontWeight.Medium)
          Text(this.name).fontSize(12).fontColor($r('sys.color.font_secondary'))
          Text($r('app.string.desktop_timeline_transfer_preview', this.preview?.tasks ?? 0,
            desktopTimelinePercent(this.preview?.progress ?? 0, this.progressDecimals))).fontSize(13)
        }.key('desktopTimelineTransferPreview').alignItems(HorizontalAlign.Start).width('100%')
      }
      Row({ space: 8 }) {
        Text($r('app.string.desktop_timeline_transfer_continue')).fontSize(14).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.proceed }).key('desktopTimelineTransferContinue')
          .accessibilityText($r('app.string.desktop_timeline_transfer_continue')).enabled(!this.busy)
          .onChange((value: boolean): void => {
            if (this.busy || value === this.proceed) { return; }
            this.proceed = value;
            if (this.preview !== undefined) { this.requestId = randomUuid(); }
          })
      }.width('100%')
      Row({ space: 8 }) {
        Text($r('app.string.desktop_timeline_transfer_copy')).fontSize(14).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.copy }).key('desktopTimelineTransferCopy')
          .accessibilityText($r('app.string.desktop_timeline_transfer_copy')).enabled(!this.busy)
          .onChange((value: boolean): void => {
            if (this.busy || value === this.copy) { return; }
            this.copy = value;
            if (this.preview !== undefined) { this.requestId = randomUuid(); }
          })
      }.width('100%')
      if (this.running) {
        Text($r('app.string.desktop_timeline_transfer_wait_idle')).width('100%').fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      if (this.error) {
        Text(this.error).key('desktopTimelineTransferError').fontSize(13).width('100%')
          .fontColor($r('app.color.workspace_status_error'))
      }
      Row({ space: 8 }) {
        Blank()
        if (this.busy) { LoadingProgress().width(18).height(18) }
        Button($r('app.string.desktop_timeline_discussion_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTimelineTransferCancel').enabled(!this.busy).onClick(this.onClose)
        Button($r('app.string.desktop_timeline_import_tree')).key('desktopTimelineTransferConfirm')
          .enabled(!this.busy && this.preview !== undefined && !this.running)
          .onClick((): void => { this.commitImport(); })
      }.width('100%')
    }.key('desktopTimelineTransfer').width('100%').padding(22).alignItems(HorizontalAlign.Start)
  }
}
