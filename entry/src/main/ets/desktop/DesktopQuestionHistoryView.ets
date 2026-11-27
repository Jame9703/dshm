import { DesktopUserMessageActions } from './DesktopUserMessageActions';
import { desktopQuestionHistoryAnswerValues, desktopQuestionHistoryClipboardText } from './DesktopQuestionHistory';
import type { DesktopQuestionHistoryQuestion, DesktopQuestionHistoryRow } from './DesktopQuestionHistory';

@Component
export struct DesktopQuestionHistoryView {
  @Prop @Watch('rowChanged') row?: DesktopQuestionHistoryRow = undefined;
  @Prop review: boolean = false;
  @Prop bodySize: number = 14;
  @Prop bodyFamily: string = '';
  onClose: () => void = (): void => {};
  @State private page: number = 0;
  private lastRow: string = '';

  aboutToAppear(): void { this.rowChanged(); }

  private rowChanged(): void {
    const id = this.row?.id ?? '';
    if (this.lastRow !== id) { this.page = 0; }
    this.lastRow = id;
    this.page = Math.min(this.page, Math.max(0, (this.row?.questions.length ?? 0) - 1));
  }

  private questions(): DesktopQuestionHistoryQuestion[] {
    const rows = this.row?.questions ?? [];
    return this.review ? rows.slice(this.page, this.page + 1) : rows;
  }

  private answer(id: string): ResourceStr {
    const row = this.row;
    if (row === undefined) { return ''; }
    const values = desktopQuestionHistoryAnswerValues(row, id);
    return values.length > 0 ? values.join(', ') : $r('app.string.desktop_question_reply_skipped');
  }

  private clipboard(): string {
    const row = this.row;
    if (row === undefined) { return ''; }
    const manager = this.getUIContext().getHostContext()?.resourceManager;
    if (manager === undefined) { return row.text; }
    return desktopQuestionHistoryClipboardText(row,
      manager.getStringSync($r('app.string.desktop_question_reply_answer_prefix').id),
      manager.getStringSync($r('app.string.desktop_question_reply_skipped').id));
  }

  @Builder
  private ReviewHeader() {
    Row({ space: 8 }) {
      Text(this.row?.kind === 'queued' ? $r('app.string.desktop_question_reply_queued') :
        $r('app.string.desktop_question_reply_answered'))
        .fontSize(13).fontColor($r('sys.color.font_secondary'))
      Blank()
      if ((this.row?.questions.length ?? 0) > 1) {
        Button($r('app.string.desktop_question_previous'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(12).height(28).enabled(this.page > 0).onClick((): void => { this.page--; })
        Text(`${this.page + 1} / ${this.row?.questions.length ?? 0}`).fontSize(12).fontColor($r('sys.color.font_secondary'))
        Button($r('app.string.desktop_question_next'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(12).height(28).enabled(this.page + 1 < (this.row?.questions.length ?? 0))
          .onClick((): void => { this.page++; })
      }
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_dock_close')).width(15).height(15).supportSvg2(true).accessibilityLevel('no')
      }.key('desktopQuestionHistoryReviewClose').width(30).height(28).padding(0)
        .accessibilityText($r('app.string.desktop_question_hide')).onClick(this.onClose)
    }.width('100%')
  }

  build() {
    Column({ space: 6 }) {
      if (this.row !== undefined) {
        Column({ space: 12 }) {
          if (this.review) { this.ReviewHeader() }
          if (this.row.questions.length === 0) {
            Text(this.row.text).fontSize(this.bodySize).fontFamily(this.bodyFamily)
              .fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
          } else {
            ForEach(this.questions(), (question: DesktopQuestionHistoryQuestion): void => {
              Column({ space: 3 }) {
                if (question.header && question.header !== question.question) {
                  Text(question.header).fontSize(Math.max(11, this.bodySize - 1)).fontFamily(this.bodyFamily)
                    .fontColor($r('sys.color.font_secondary'))
                }
                Text(question.question).fontSize(this.bodySize).fontFamily(this.bodyFamily)
                  .fontColor($r('sys.color.font_secondary')).copyOption(CopyOptions.LocalDevice)
                Text(this.answer(question.id)).key(`desktopQuestionReplyAnswer-${this.row?.callId ?? ''}-${question.id}`)
                  .fontSize(this.bodySize).fontFamily(this.bodyFamily).fontColor($r('sys.color.font_primary'))
                  .margin({ top: 1 }).copyOption(CopyOptions.LocalDevice)
              }.alignItems(HorizontalAlign.Start)
            }, (question: DesktopQuestionHistoryQuestion): string => question.id + ':' + question.question)
          }
        }.constraintSize({ maxWidth: this.review ? 712 : '82%' })
          .alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(16).backgroundColor($r('app.color.workspace_panel'))
        if (!this.review) {
          DesktopUserMessageActions({ messageId: this.row.id, timestamp: this.row.time,
            text: this.clipboard(), bodySize: this.bodySize, clockOnly: true })
        }
      }
    }.key(this.review ? 'desktopQuestionHistoryReview' : 'desktopQuestionReply-' + (this.row?.callId ?? ''))
      .accessibilityDescription($r('app.string.desktop_question_reply_label'))
      .width('100%').constraintSize({ maxWidth: 712 })
      .alignItems(this.review ? HorizontalAlign.Start : HorizontalAlign.End)
  }
}
