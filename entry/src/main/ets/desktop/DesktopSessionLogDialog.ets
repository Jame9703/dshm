export enum DesktopLogStage {
  PREPARING,
  CHOOSING,
  SAVED,
  FAILED
}

@Component
export struct DesktopSessionLogDialog {
  @Prop stage: DesktopLogStage = DesktopLogStage.PREPARING;
  @Prop problem: string = '';
  onClose: () => void = (): void => {};

  private title(): string {
    if (this.stage === DesktopLogStage.SAVED) { return 'Session 日志已保存'; }
    if (this.stage === DesktopLogStage.FAILED) { return 'Session 导出失败'; }
    return '正在导出 Session';
  }

  private description(): string {
    if (this.stage === DesktopLogStage.SAVED) { return 'ZIP 文件已写入所选位置。'; }
    if (this.stage === DesktopLogStage.FAILED) { return this.problem; }
    if (this.stage === DesktopLogStage.CHOOSING) { return '请选择保存 ZIP 文件的位置。'; }
    return '正在准备包含指定 Session、子 Session 和附件的 ZIP 文件';
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        if (this.stage === DesktopLogStage.PREPARING) {
          LoadingProgress().width(22).height(22).color($r('sys.color.brand'))
        }
        Text(this.title()).key('desktopLogDialogTitle').fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.width(30).height(30).padding(0).accessibilityText('关闭').onClick(this.onClose)
      }.width('100%')
      Text(this.description()).fontSize(14).lineHeight(21).fontColor($r('sys.color.font_secondary')).width('100%')
      Row() {
        Button('关闭').key('desktopLogDialogClose').onClick(this.onClose)
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(22).width('100%').alignItems(HorizontalAlign.Start)
  }
}
