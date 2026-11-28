@Component
export struct DesktopTimelineRemoveDialog {
  @Prop title: string = '';
  @Prop disabled: boolean = false;
  onBusy: (busy: boolean) => void = (_busy: boolean): void => {};
  onExport: () => Promise<string> = (): Promise<string> => Promise.resolve('');
  onRemove: () => Promise<string> = (): Promise<string> => Promise.resolve('');
  onClose: () => void = (): void => {};

  @State private busy: boolean = false;
  @State private error: string = '';
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; }

  aboutToDisappear(): void {
    this.active = false;
    this.onBusy(false);
  }

  private async perform(remove: boolean): Promise<void> {
    if (this.busy || (remove && this.disabled)) { return; }
    this.busy = true;
    this.onBusy(true);
    this.error = '';
    try {
      const error = await (remove ? this.onRemove() : this.onExport());
      if (!this.active) { return; }
      this.error = error;
      if (remove && !error) { this.onClose(); }
    } finally {
      if (this.active) {
        this.busy = false;
        this.onBusy(false);
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.desktop_timeline_remove_tree')).fontSize(21).fontWeight(FontWeight.Medium).width('100%')
      Text($r('app.string.desktop_timeline_remove_tree_hint', this.title)).fontSize(14).width('100%')
        .fontColor($r('sys.color.font_secondary'))
      if (this.disabled) {
        Text($r('app.string.desktop_timeline_remove_disabled')).fontSize(12).width('100%')
          .fontColor($r('sys.color.font_secondary'))
      }
      if (this.error) {
        Text(this.error).fontSize(13).width('100%').fontColor($r('app.color.workspace_status_error'))
          .key('desktopTimelineRemoveError')
      }
      Row({ space: 8 }) {
        Button($r('app.string.desktop_timeline_export_tree'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTimelineRemoveExport').enabled(!this.busy).onClick((): void => { this.perform(false); })
        Blank()
        if (this.busy) { LoadingProgress().width(18).height(18) }
        Button($r('app.string.desktop_timeline_discussion_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTimelineRemoveCancel').enabled(!this.busy).onClick(this.onClose)
        Button($r('app.string.desktop_timeline_remove_tree'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontColor($r('app.color.workspace_status_error')).key('desktopTimelineRemoveConfirm')
          .enabled(!this.busy && !this.disabled).onClick((): void => { this.perform(true); })
      }.width('100%')
    }.key('desktopTimelineRemoveDialog').width('100%').padding(22).alignItems(HorizontalAlign.Start)
  }
}
