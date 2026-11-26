import { FEEDBACK_CATEGORIES, FeedbackCategory } from 'appstate';

@Component
export struct DesktopFeedbackDialog {
  onClose: () => void = (): void => {};
  onSubmit: (category: string, note: string) => Promise<string> =
    (_category: string, _note: string): Promise<string> => Promise.resolve('');
  @State private category: string = '';
  @State private note: string = '';
  @State private sending: boolean = false;
  @State private problem: string = '';

  private async submit(): Promise<void> {
    if (this.sending) { return; }
    this.sending = true;
    this.problem = '';
    try {
      this.problem = await this.onSubmit(this.category, this.note);
    } finally {
      this.sending = false;
    }
  }

  build() {
    Column({ space: 18 }) {
      Row({ space: 10 }) {
        Text('提交反馈').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
          .fontColor($r('sys.color.font_primary')).key('desktopFeedbackDialogTitle')
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.width(30).height(30).padding(0).key('desktopFeedbackClose').accessibilityText('关闭').onClick(this.onClose)
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(FEEDBACK_CATEGORIES, (option: FeedbackCategory) => {
          Button(option.label, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }).height(28)
            .key('desktopFeedbackCategory-' + option.id)
            .padding({ left: 12, right: 12 }).margin({ right: 8, bottom: 8 })
            .border({ width: 0.5, radius: 7, color: this.category === option.id ? $r('sys.color.brand') :
              $r('app.color.workspace_border') })
            .backgroundColor(this.category === option.id ? $r('sys.color.brand') : Color.Transparent)
            .fontColor(this.category === option.id ? Color.White : $r('sys.color.font_primary'))
            .fontSize(13).enabled(!this.sending)
            .accessibilitySelected(this.category === option.id)
            .onClick((): void => { this.category = this.category === option.id ? '' : option.id; })
        }, (option: FeedbackCategory): string => option.id)
      }.width('100%').accessibilityGroup(false).accessibilityText('反馈分类')
      TextArea({ text: this.note, placeholder: '填写详情以帮助我们改进体验，提交内容会包括当前对话的日志' })
        .key('desktopFeedbackNote').accessibilityText('反馈详情').width('100%').height(116).fontSize(14).lineHeight(22)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .border({ width: 0.5, radius: 12, color: $r('app.color.workspace_border') })
        .backgroundColor($r('app.color.workspace_panel')).enabled(!this.sending)
        .onChange((value: string): void => { this.note = value; })
      if (this.problem) {
        Text(this.problem).fontSize(13).fontColor($r('sys.color.warning')).width('100%')
          .key('desktopFeedbackProblem')
      }
      Button(this.sending ? '提交中…' : '提交', { type: ButtonType.Normal }).width('100%').height(44)
        .fontWeight(FontWeight.Medium).fontSize(14).borderRadius(12)
        .key('desktopFeedbackSubmit').enabled(!this.sending).onClick((): void => { this.submit(); })
    }.padding(22).width('100%').alignItems(HorizontalAlign.Start)
  }
}
