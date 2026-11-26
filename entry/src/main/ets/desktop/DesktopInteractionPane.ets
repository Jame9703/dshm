import { MarkdownRenderer } from '../view/MarkdownRenderer';
import type { DesktopInteraction, DesktopQuestion, DesktopQuestionAnswer, DesktopQuestionOption } from './DesktopInteractions';

@Component
export struct DesktopInteractionPane {
  @Prop request?: DesktopInteraction = undefined;
  @Prop busy: boolean = false;
  onDecision: (id: string, allow: boolean) => void = (_id: string, _allow: boolean): void => {};
  onAnswer: (id: string, answers: DesktopQuestionAnswer[]) => void =
    (_id: string, _answers: DesktopQuestionAnswer[]): void => {};
  @State private draft: DesktopQuestionAnswer[] = [];

  private answerFor(id: string): DesktopQuestionAnswer | undefined {
    return this.draft.find((answer: DesktopQuestionAnswer): boolean => answer.id === id);
  }

  private setAnswer(answer: DesktopQuestionAnswer): void {
    this.draft = [...this.draft.filter((item: DesktopQuestionAnswer): boolean => item.id !== answer.id), answer];
  }

  private select(question: DesktopQuestion, label: string): void {
    const current = this.answerFor(question.id);
    const selected = current?.selected ?? [];
    this.setAnswer({
      id: question.id,
      selected: selected.includes(label) ? selected.filter((item: string): boolean => item !== label) :
        (question.multi ? [...selected, label] : [label]),
      custom: question.multi ? current?.custom : undefined
    });
  }

  private updateText(question: DesktopQuestion, text: string): void {
    const current = this.answerFor(question.id);
    this.setAnswer({
      id: question.id, selected: question.multi ? current?.selected ?? [] : [], custom: text
    });
  }

  private canSubmit(): boolean {
    const questions = this.request?.questions ?? [];
    return questions.length > 0 && questions.every((question: DesktopQuestion): boolean => {
      const row = this.answerFor(question.id);
      return row !== undefined && (row.selected.length > 0 || (row.custom?.trim().length ?? 0) > 0);
    });
  }

  private submit(): void {
    if (!this.canSubmit() || this.request === undefined) {
      return;
    }
    const answers: DesktopQuestionAnswer[] = [];
    for (const question of this.request.questions) {
      const item = this.answerFor(question.id);
      if (item !== undefined) {
        const trimmed = item.custom?.trim() ?? '';
        answers.push({ id: item.id, selected: item.selected, custom: trimmed || undefined });
      }
    }
    this.onAnswer(this.request.id, answers);
  }

  @Builder
  private Approval() {
    Text('需要工具审批').fontSize(16).fontWeight(FontWeight.Medium)
    if ((this.request?.tool.length ?? 0) > 0) {
      Text(this.request?.tool ?? '').fontSize(14).fontColor($r('sys.color.font_secondary'))
    }
    if ((this.request?.reason.length ?? 0) > 0) {
      Text(this.request?.reason ?? '').fontSize(14).width('100%').copyOption(CopyOptions.InApp)
    }
    Row({ space: 8 }) {
      Button('拒绝', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .onClick((): void => { this.onDecision(this.request?.id ?? '', false); })
      Button('允许一次').enabled(!this.busy)
        .onClick((): void => { this.onDecision(this.request?.id ?? '', true); })
    }
  }

  @Builder
  private Question(question: DesktopQuestion) {
    Column({ space: 8 }) {
      if (question.header) {
        Text(question.header).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      Text(question.prompt).fontSize(15).fontWeight(FontWeight.Medium)
      if (question.detail) {
        MarkdownRenderer({ text: question.detail })
      }
      ForEach(question.options, (option: DesktopQuestionOption) => {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 8 }) {
            Text(this.answerFor(question.id)?.selected.includes(option.label) ? '✓' : '○')
            Column({ space: 2 }) {
              Text(option.label).fontSize(14).width('100%')
              if (option.detail.length > 0) {
                Text(option.detail).fontSize(12).width('100%').fontColor($r('sys.color.font_secondary'))
              }
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        }
        .width('100%').padding(8).borderRadius(8)
        .backgroundColor(this.answerFor(question.id)?.selected.includes(option.label) ?
          $r('app.color.workspace_selection') : Color.Transparent)
        .accessibilityText(option.label).enabled(!this.busy)
        .onClick((): void => { this.select(question, option.label); })
      }, (option: DesktopQuestionOption): string => option.label)
      if (question.custom) {
        TextInput({ text: this.answerFor(question.id)?.custom ?? '', placeholder: '输入其他答案' })
          .enabled(!this.busy).onChange((value: string): void => { this.updateText(question, value); })
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 10 }) {
      if (this.request?.kind === 'approval') {
        this.Approval()
      } else {
        Scroll() {
          Column({ space: 14 }) {
            ForEach(this.request?.questions ?? [], (question: DesktopQuestion) => {
              this.Question(question)
            }, (question: DesktopQuestion): string => question.id)
          }
          .width('100%').alignItems(HorizontalAlign.Start)
        }
        .width('100%').constraintSize({ maxHeight: 300 }).align(Alignment.TopStart)
        Button('提交回答').enabled(!this.busy && this.canSubmit()).onClick((): void => { this.submit(); })
      }
    }
    .padding(14).width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
    .borderRadius(16).backgroundColor($r('app.color.workspace_panel'))
  }
}
