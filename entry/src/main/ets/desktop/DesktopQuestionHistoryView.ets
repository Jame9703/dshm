import { DesktopUserMessageActions } from './DesktopUserMessageActions';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { desktopQuestionOption } from './DesktopInteractions';
import type { DesktopQuestionOption } from './DesktopInteractions';
import type { DesktopTypography } from './DesktopTheme';
import { desktopQuestionHistoryAnswerValues, desktopQuestionHistoryClipboardText } from './DesktopQuestionHistory';
import type { DesktopQuestionHistoryAnswer, DesktopQuestionHistoryOption, DesktopQuestionHistoryQuestion,
  DesktopQuestionHistoryRow } from './DesktopQuestionHistory';

@Component
export struct DesktopQuestionHistoryView {
  @Prop @Watch('rowChanged') row?: DesktopQuestionHistoryRow = undefined;
  @Prop review: boolean = false;
  @Prop bodySize: number = 14;
  @Prop bodyFamily: string = '';
  @Prop typography: DesktopTypography | undefined = undefined;
  onClose: () => void = (): void => {};
  onLink: (href: string) => void = (_href: string): void => {};
  @State private page: number = 0;
  @State private collapsed: boolean = false;
  @State private expanded: string[] = [];
  private lastRow: string = '';

  aboutToAppear(): void { this.rowChanged(); }

  private rowChanged(): void {
    const id = this.row?.id ?? '';
    if (this.lastRow !== id) {
      this.page = 0;
      this.collapsed = false;
      this.expanded = [];
    }
    this.lastRow = id;
    this.page = Math.min(this.page, Math.max(0, (this.row?.questions.length ?? 0) - 1));
  }

  private questions(): DesktopQuestionHistoryQuestion[] {
    const rows = this.row?.questions ?? [];
    return this.review ? rows.slice(this.page, this.page + 1) : rows;
  }

  private changePage(page: number): void {
    if (page >= 0 && page < (this.row?.questions.length ?? 0)) {
      this.page = page;
      this.expanded = [];
    }
  }

  private toggleExpanded(id: string): void {
    this.expanded = this.expanded.includes(id) ?
      this.expanded.filter((entry: string): boolean => entry !== id) : [...this.expanded, id];
  }

  private recorded(id: string): DesktopQuestionHistoryAnswer | undefined {
    return this.row?.answers.find((answer: DesktopQuestionHistoryAnswer): boolean => answer.id === id);
  }

  private selected(questionId: string, label: string): boolean {
    return this.recorded(questionId)?.selected.includes(label) === true;
  }

  private extraSelections(question: DesktopQuestionHistoryQuestion): string[] {
    return this.recorded(question.id)?.selected.filter((label: string): boolean =>
      !(question.options ?? []).some((option: DesktopQuestionHistoryOption): boolean => option.label === label)) ?? [];
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
  private IconButton(icon: Resource, size: number, label: Resource, id: string, enabled: boolean,
    action: () => void) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(icon).width(size).height(size).supportSvg2(true).draggable(false)
        .fillColor($r('sys.color.font_secondary')).accessibilityLevel('no')
    }.key(id).width(28).height(28).padding(0).borderRadius(7).backgroundColor(Color.Transparent)
      .focusOnTouch(false).accessibilityText(label).enabled(enabled).onClick(action)
  }

  @Builder
  private ReviewHeader(question: DesktopQuestionHistoryQuestion) {
    Row({ space: 8 }) {
      Column({ space: 5 }) {
        if (question.header) {
          Text(question.header).fontSize(11).fontColor($r('sys.color.font_tertiary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.collapsed) {
          Text(question.question).key('desktopQuestionHistoryReviewCollapsedPrompt')
            .fontSize(16).lineHeight(22).fontWeight(FontWeight.Medium)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.row?.kind === 'queued' ? $r('app.string.desktop_question_reply_queued') :
        $r('app.string.desktop_question_reply_answered'))
        .fontSize(13).fontColor($r('sys.color.font_secondary'))
      this.IconButton(this.collapsed ? $r('app.media.dsh_queue_chevron_up_outline') :
        $r('app.media.dsh_queue_chevron_down_outline'), 18, this.collapsed ?
        $r('app.string.desktop_question_expand_card') : $r('app.string.desktop_question_collapse_card'),
        'desktopQuestionHistoryReviewCollapse', true, (): void => { this.collapsed = !this.collapsed; })
      this.IconButton($r('app.media.dsh_dock_close'), 15, $r('app.string.desktop_question_hide'),
        'desktopQuestionHistoryReviewClose', true, this.onClose)
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  private ReviewDetailToggle(id: string, key: string) {
    this.IconButton(this.expanded.includes(id) ? $r('app.media.dsh_queue_chevron_up_outline') :
      $r('app.media.dsh_queue_chevron_down_outline'), 14, this.expanded.includes(id) ?
      $r('app.string.desktop_question_collapse') : $r('app.string.desktop_question_expand'),
      key, true, (): void => { this.toggleExpanded(id); })
  }

  @Builder
  private ChoiceBox(checked: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Stack() {}
        .width(14).height(14).borderRadius(4)
        .backgroundColor(checked ? $r('sys.color.font_primary') : Color.Transparent)
        .border({ width: 0.5, color: checked ? $r('sys.color.font_primary') : $r('app.color.workspace_border') })
      if (checked) {
        Image($r('app.media.dsh_dock_check')).width(12).height(12).supportSvg2(true).draggable(false)
          .fillColor($r('app.color.workspace_canvas'))
      }
    }.width(20).height(20).margin({ top: 2 }).accessibilityLevel('no')
  }

  @Builder
  private ReviewChoice(question: DesktopQuestionHistoryQuestion, option: DesktopQuestionOption, index: number) {
    Row({ space: 2 }) {
      Row({ space: 8 }) {
        if (question.multiSelect) {
          this.ChoiceBox(this.selected(question.id, option.label))
        } else {
          Text(String(index + 1)).width(20).height(20).margin({ top: 2 }).textAlign(TextAlign.Center)
            .fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_secondary'))
            .borderRadius(4).backgroundColor($r('app.color.workspace_action')).accessibilityLevel('no')
        }
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(option.caption).fontSize(14).lineHeight(24).fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            if (option.recommended) {
              Text($r('app.string.desktop_question_recommended')).fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
            }
          }.width('100%')
          if (option.detail) {
            Text(option.detail).fontSize(12).width('100%').fontColor($r('sys.color.font_secondary'))
              .maxLines(this.expanded.includes(String(index)) ? 1000 : 2)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).copyOption(CopyOptions.InApp)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.key('desktopQuestionHistoryReviewOption-' + index)
        .layoutWeight(1).padding(8).borderRadius(8).alignItems(VerticalAlign.Top)
        .accessibilitySelected(this.selected(question.id, option.label))
        .backgroundColor(!question.multiSelect && this.selected(question.id, option.label) ?
          $r('app.color.workspace_selection') : Color.Transparent)
      if (option.detail) {
        this.ReviewDetailToggle(String(index), 'desktopQuestionHistoryReviewOptionDetail-' + index)
      }
    }.width('100%')
  }

  @Builder
  private ReviewQuestion(question: DesktopQuestionHistoryQuestion) {
    this.ReviewHeader(question)
    if (!this.collapsed) {
      Scroll() {
        Column({ space: 7 }) {
          Row() {
            Text(question.question).fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
              .maxLines(this.expanded.includes('prompt') ? 1000 : 3).textOverflow({ overflow: TextOverflow.Ellipsis })
              .copyOption(CopyOptions.InApp)
            this.ReviewDetailToggle('prompt', 'desktopQuestionHistoryReviewPromptDetail')
          }.width('100%')
          if (question.detail) {
            MarkdownRenderer({ text: question.detail, typography: this.typography, onLink: this.onLink })
          }
          ForEach(question.options ?? [], (option: DesktopQuestionHistoryOption, index: number): void => {
            this.ReviewChoice(question, desktopQuestionOption(option.label, option.description ?? ''), index)
          }, (option: DesktopQuestionHistoryOption, index: number): string => option.label + ':' + index)
          ForEach(this.extraSelections(question), (label: string): void => {
            Text(label).fontSize(14).width('100%').copyOption(CopyOptions.InApp).accessibilitySelected(true)
          }, (label: string, index: number): string => label + ':' + index)
          if (this.recorded(question.id)?.custom) {
            Row({ space: 8 }) {
              if (question.multiSelect && (question.options?.length ?? 0) > 0) { this.ChoiceBox(true) }
              else if ((question.options?.length ?? 0) > 0) {
                Image($r('app.media.dsh_dock_edit')).width(12).height(12).supportSvg2(true).draggable(false)
                  .fillColor($r('sys.color.font_secondary')).accessibilityLevel('no')
              }
              Text(this.recorded(question.id)?.custom ?? '').fontSize(14).layoutWeight(1).copyOption(CopyOptions.InApp)
            }.key('desktopQuestionHistoryReviewCustom').width('100%').padding(8).borderRadius(8)
              .backgroundColor($r('app.color.workspace_selection')).alignItems(VerticalAlign.Top)
          } else if (this.recorded(question.id)?.selected.length === 0) {
            Text($r('app.string.desktop_question_review_skipped')).key('desktopQuestionHistoryReviewSkipped')
              .fontSize(12).fontColor($r('sys.color.font_secondary'))
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.key('desktopQuestionHistoryReviewBody').width('100%').constraintSize({ maxHeight: 260 }).align(Alignment.TopStart)
      Row({ space: 6 }) {
        this.IconButton($r('app.media.dsh_browser_chevron_left_outline'), 14, $r('app.string.desktop_question_previous'),
          'desktopQuestionHistoryReviewPrevious', this.page > 0, (): void => { this.changePage(this.page - 1); })
        Text(`${this.page + 1} / ${this.row?.questions.length ?? 0}`).key('desktopQuestionHistoryReviewPage')
          .fontSize(14).lineHeight(24).fontColor($r('sys.color.font_secondary'))
        this.IconButton($r('app.media.dsh_browser_chevron_right_outline'), 14, $r('app.string.desktop_question_next'),
          'desktopQuestionHistoryReviewNext', this.page + 1 < (this.row?.questions.length ?? 0),
          (): void => { this.changePage(this.page + 1); })
      }.width('100%')
    }
  }

  build() {
    Column({ space: 6 }) {
      if (this.row !== undefined) {
        Column({ space: 12 }) {
          if (this.review && this.row.questions.length > 0) {
            ForEach(this.questions(), (question: DesktopQuestionHistoryQuestion): void => {
              Column({ space: 10 }) {
                this.ReviewQuestion(question)
              }.width('100%').alignItems(HorizontalAlign.Start)
            }, (question: DesktopQuestionHistoryQuestion): string => `${this.page}:${question.id}`)
          } else if (this.row.questions.length === 0) {
            if (this.review) {
              this.IconButton($r('app.media.dsh_dock_close'), 15, $r('app.string.desktop_question_hide'),
                'desktopQuestionHistoryReviewClose', true, this.onClose)
            }
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
