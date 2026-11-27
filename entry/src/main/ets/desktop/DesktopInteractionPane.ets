import { MarkdownRenderer } from '../view/MarkdownRenderer';
import type { DesktopInteraction, DesktopQuestion, DesktopQuestionAnswer, DesktopQuestionDraft,
  DesktopQuestionOption, DesktopQuestionProgress } from './DesktopInteractions';
import type { DesktopPlanDocument } from './DesktopPlan';
import type { DesktopTypography } from './DesktopTheme';

@Component
export struct DesktopInteractionPane {
  @Prop request?: DesktopInteraction = undefined;
  @Prop busy: boolean = false;
  @Prop typography: DesktopTypography | undefined = undefined;
  onDecision: (id: string, allow: boolean) => void = (_id: string, _allow: boolean): void => {};
  onAnswer: (id: string, answers: DesktopQuestionAnswer[]) => void =
    (_id: string, _answers: DesktopQuestionAnswer[]): void => {};
  onPlanDecision: (id: string, approve: boolean) => void = (_id: string, _approve: boolean): void => {};
  onPlanPreview: (plan: DesktopPlanDocument) => void = (_plan: DesktopPlanDocument): void => {};
  onQuestionProgress: (id: string, progress: DesktopQuestionProgress, engage: boolean) => void =
    (_id: string, _progress: DesktopQuestionProgress, _engage: boolean): void => {};
  onQuestionHold: (id: string) => void = (_id: string): void => {};
  onQuestionClose: (id: string) => void = (_id: string): void => {};
  onLink: (url: string) => void = (_url: string): void => {};
  @State private drafts: DesktopQuestionDraft[] = [];
  @State private questionIndex: number = 0;
  @State private collapsed: boolean = false;
  @State private expanded: string[] = [];
  @State private incomplete: boolean = false;
  @State private now: number = 0;
  private clock: number = -1;

  aboutToAppear(): void {
    const request = this.request;
    if (request?.kind !== 'question' || request.planReview !== undefined) { return; }
    const progress = request.questionProgress;
    this.drafts = request.questions.map((question: DesktopQuestion, index: number): DesktopQuestionDraft => {
      const saved = progress?.drafts[index];
      if (saved?.id === question.id) { return saved; }
      const candidates = question.multi ? question.options : question.options.slice(0, 1);
      return { id: question.id, selected: candidates.filter((option: DesktopQuestionOption): boolean => option.recommended)
        .map((option: DesktopQuestionOption): string => option.label), custom: '', skipped: false };
    });
    this.questionIndex = Math.min(progress?.index ?? 0, Math.max(0, request.questions.length - 1));
    if ((request.waitDeadline ?? 0) > 0) {
      this.now = Date.now();
      this.clock = setInterval((): void => { this.now = Date.now(); }, 1000);
    }
  }

  aboutToDisappear(): void { clearInterval(this.clock); }

  @Builder
  private PlanReview() {
    Row({ space: 7 }) {
      Circle().width(7).height(7).fill($r('sys.color.warning'))
      Text('计划待审').fontSize(13).fontColor($r('sys.color.font_secondary'))
      Blank()
      Button('查看完整计划', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .onClick((): void => {
          const review = this.request?.planReview;
          if (review !== undefined) {
            this.onPlanPreview(review.document);
          }
        })
    }
    .width('100%')
    Text(this.request?.planReview?.document.title ?? '').fontSize(17).fontWeight(FontWeight.Medium)
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    if (this.request?.planReview?.summary) {
      Text(this.request?.planReview?.summary ?? '').fontSize(14).fontColor($r('sys.color.font_secondary'))
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    Row({ space: 8 }) {
      Blank()
      Button('要求修改', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .onClick((): void => { this.onPlanDecision(this.request?.id ?? '', false); })
      Button('同意执行').enabled(!this.busy)
        .onClick((): void => { this.onPlanDecision(this.request?.id ?? '', true); })
    }
    .width('100%')
  }

  private isLast(): boolean { return this.questionIndex >= this.drafts.length - 1; }

  private answered(draft?: DesktopQuestionDraft): boolean {
    return draft !== undefined && (draft.selected.length > 0 || draft.custom.trim().length > 0);
  }

  private save(index: number, engage: boolean = false): void {
    if (this.questionIndex !== index) { this.expanded = []; }
    this.questionIndex = index;
    this.incomplete = false;
    this.onQuestionProgress(this.request?.id ?? '', { index: index, drafts: this.drafts }, engage);
  }

  private update(draft: DesktopQuestionDraft, next: number): void {
    this.drafts = this.drafts.map((item: DesktopQuestionDraft, index: number): DesktopQuestionDraft =>
      index === this.questionIndex ? draft : item);
    this.save(next, true);
  }

  private select(question: DesktopQuestion, label: string): void {
    const current = this.drafts[this.questionIndex];
    const selected = current?.selected ?? [];
    const next = question.multi || this.isLast() ? this.questionIndex : this.questionIndex + 1;
    this.update({
      id: question.id,
      selected: !question.multi ? [label] : selected.includes(label) ?
        selected.filter((item: string): boolean => item !== label) : [...selected, label],
      custom: question.multi ? current?.custom ?? '' : '', skipped: false
    }, next);
  }

  private updateText(question: DesktopQuestion, text: string): void {
    this.update({ id: question.id, selected: question.multi ? this.drafts[this.questionIndex]?.selected ?? [] : [],
      custom: text, skipped: false }, this.questionIndex);
  }

  private nextQuestion(): void {
    if (this.isLast()) { this.submit(); }
    else { this.save(this.questionIndex + 1); }
  }

  private skip(question: DesktopQuestion): void {
    const last = this.isLast();
    this.update({ id: question.id, selected: [], custom: '', skipped: true },
      last ? this.questionIndex : this.questionIndex + 1);
    if (last) { this.submit(); }
  }

  private submit(): void {
    const missing = this.drafts.findIndex((draft: DesktopQuestionDraft): boolean => !draft.skipped && !this.answered(draft));
    if (missing !== -1) {
      this.save(missing);
      this.incomplete = true;
      return;
    }
    this.onAnswer(this.request?.id ?? '', this.drafts.map((draft: DesktopQuestionDraft): DesktopQuestionAnswer => ({
      id: draft.id, selected: draft.selected, custom: draft.custom.trim() || undefined
    })));
  }

  private toggleDetail(id: string): void {
    this.expanded = this.expanded.includes(id) ? this.expanded.filter((item: string): boolean => item !== id) :
      [...this.expanded, id];
  }

  private waitSeconds(): number { return Math.max(0, Math.ceil(((this.request?.waitDeadline ?? 0) - this.now) / 1000)); }

  private selected(label: string): boolean {
    return this.drafts[this.questionIndex]?.selected.includes(label) === true;
  }

  @Builder
  private Approval() {
    Row({ space: 7 }) {
      Circle().width(7).height(7).fill(this.busy ? $r('sys.color.font_tertiary') : $r('sys.color.warning'))
      Text($r('app.string.desktop_approval_pending')).fontSize(12).fontColor($r('sys.color.font_secondary'))
    }
    Scroll() {
      Text(this.request?.reason || $r('app.string.desktop_approval_tool', this.request?.tool ?? ''))
        .fontSize(16).fontWeight(FontWeight.Medium).width('100%').copyOption(CopyOptions.InApp)
    }
    .width('100%').constraintSize({ maxHeight: 180 }).align(Alignment.TopStart)
    Row({ space: 8 }) {
      Blank()
      Button($r('app.string.desktop_approval_reject'), { buttonStyle: ButtonStyleMode.NORMAL }).enabled(!this.busy)
        .onClick((): void => { this.onDecision(this.request?.id ?? '', false); })
      Button($r('app.string.desktop_approval_allow')).enabled(!this.busy)
        .onClick((): void => { this.onDecision(this.request?.id ?? '', true); })
    }.width('100%')
  }

  @Builder
  private IconButton(icon: Resource, label: Resource, id: string, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(icon).width(15).height(15).supportSvg2(true).draggable(false).accessibilityLevel('no')
        .fillColor($r('sys.color.font_secondary'))
    }.width(32).height(32).borderRadius(7).padding(0).key(id)
    .accessibilityText(label).enabled(enabled).onClick(action)
  }

  @Builder
  private QuestionHeader(question: DesktopQuestion) {
    Row({ space: 6 }) {
      if (question.header) { Text(question.header).fontSize(12).fontColor($r('sys.color.font_secondary')) }
      Blank()
      if (this.request?.continued) {
        Text($r('app.string.desktop_question_continued')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      } else if (this.request?.timed && this.request?.questionHeld) {
        Text($r('app.string.desktop_question_held')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      } else if (this.waitSeconds() > 0) {
        Text($r('app.string.desktop_question_countdown', this.waitSeconds())).fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Button($r('app.string.desktop_question_hold'), { buttonStyle: ButtonStyleMode.NORMAL }).key('desktopQuestionHold')
          .height(28).enabled(!this.busy).onClick((): void => { this.onQuestionHold(this.request?.id ?? ''); })
      }
      this.IconButton(this.collapsed ? $r('app.media.dsh_queue_chevron_up_outline') :
        $r('app.media.dsh_queue_chevron_down_outline'), this.collapsed ? $r('app.string.desktop_question_expand_card') :
        $r('app.string.desktop_question_collapse_card'), 'desktopQuestionCollapse', !this.busy,
        (): void => { this.collapsed = !this.collapsed; })
      this.IconButton($r('app.media.dsh_dock_close'), this.request?.callId ? $r('app.string.desktop_question_hide') :
        $r('app.string.desktop_question_cancel'), 'desktopQuestionClose', !this.busy,
        (): void => { this.onQuestionClose(this.request?.id ?? ''); })
    }.width('100%')
  }

  @Builder
  private Choice(question: DesktopQuestion, option: DesktopQuestionOption, index: number) {
    Row({ space: 2 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Stack() {
            if (this.selected(option.label)) {
              Image($r('app.media.dsh_dock_check')).width(12).height(12).supportSvg2(true).draggable(false)
                .fillColor($r('sys.color.font_primary'))
            }
          }.width(16).height(16).border({ width: 1, color: $r('app.color.workspace_border') })
          .borderRadius(question.multi ? 4 : 8).accessibilityLevel('no')
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text(option.caption).fontSize(14).fontColor($r('sys.color.font_primary'))
              if (option.recommended) {
                Text($r('app.string.desktop_question_recommended')).fontSize(11).fontColor($r('sys.color.font_secondary'))
              }
            }
            if (option.detail) {
              Text(option.detail).fontSize(12).width('100%').fontColor($r('sys.color.font_secondary'))
                .maxLines(this.expanded.includes(option.label) ? 1000 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
      }
      .layoutWeight(1).padding(8).borderRadius(8).key('desktopQuestionOption-' + index)
      .backgroundColor(this.selected(option.label) ? $r('app.color.workspace_selection') : Color.Transparent)
      .accessibilityText(option.caption).accessibilitySelected(this.selected(option.label)).enabled(!this.busy)
      .onClick((): void => { this.select(question, option.label); })
      if (option.detail) {
        this.DetailToggle(option.label, 'desktopQuestionOptionDetail-' + index)
      }
    }.width('100%')
  }

  @Builder
  private DetailToggle(id: string, keyName: string) {
    this.IconButton(this.expanded.includes(id) ? $r('app.media.dsh_queue_chevron_up_outline') :
      $r('app.media.dsh_queue_chevron_down_outline'), this.expanded.includes(id) ?
      $r('app.string.desktop_question_collapse') : $r('app.string.desktop_question_expand'), keyName,
      true, (): void => { this.toggleDetail(id); })
  }

  @Builder
  private Question(question: DesktopQuestion) {
    this.QuestionHeader(question)
    if (!this.collapsed) {
      Scroll() {
        Column({ space: 7 }) {
          Row() {
            Text(question.prompt).fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
              .maxLines(this.expanded.includes('') ? 1000 : 3).textOverflow({ overflow: TextOverflow.Ellipsis })
              .copyOption(CopyOptions.InApp)
            this.DetailToggle('', 'desktopQuestionPromptDetail')
          }.width('100%')
          if (question.detail) { MarkdownRenderer({ text: question.detail, onLink: this.onLink,
            typography: this.typography }) }
          ForEach(question.options, (option: DesktopQuestionOption, index: number) => {
            this.Choice(question, option, index)
          }, (option: DesktopQuestionOption, index: number): string => question.id + ':' + option.label + ':' + index)
          if (question.custom) {
            TextArea({ text: this.drafts[this.questionIndex]?.custom ?? '',
              placeholder: $r('app.string.desktop_question_input') })
              .width('100%').constraintSize({ minHeight: 42, maxHeight: 120 }).fontSize(14)
              .borderRadius(8).key('desktopQuestionCustom').enabled(!this.busy)
              .onChange((value: string): void => { this.updateText(question, value); })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxHeight: 260 }).align(Alignment.TopStart)
      if (this.incomplete) {
        Text($r('app.string.desktop_question_incomplete')).key('desktopQuestionIncomplete')
          .fontSize(12).fontColor($r('sys.color.warning'))
      }
      this.QuestionFooter(question)
    }
  }

  @Builder
  private QuestionFooter(question: DesktopQuestion) {
    Row({ space: 6 }) {
      if (this.drafts.length > 1) {
        this.IconButton($r('app.media.dsh_browser_chevron_left_outline'), $r('app.string.desktop_question_previous'),
          'desktopQuestionPrevious', this.questionIndex > 0 && !this.busy, (): void => { this.save(this.questionIndex - 1); })
        Text(`${this.questionIndex + 1} / ${this.drafts.length}`).fontSize(12).fontColor($r('sys.color.font_secondary'))
        this.IconButton($r('app.media.dsh_browser_chevron_right_outline'), $r('app.string.desktop_question_next'),
          'desktopQuestionNext', !this.isLast() && !this.busy, (): void => { this.save(this.questionIndex + 1); })
      }
      Blank()
      Button($r('app.string.desktop_question_skip'), { buttonStyle: ButtonStyleMode.NORMAL }).key('desktopQuestionSkip')
        .enabled(!this.busy).onClick((): void => { this.skip(question); })
      Button(this.isLast() ? $r('app.string.desktop_question_submit') : $r('app.string.desktop_question_next'))
        .key('desktopQuestionContinue').enabled(!this.busy && this.answered(this.drafts[this.questionIndex]))
        .onClick((): void => { this.nextQuestion(); })
    }.width('100%')
  }

  build() {
    Column({ space: 10 }) {
      if (this.request?.kind === 'approval') {
        this.Approval()
      } else if (this.request?.planReview !== undefined) {
        this.PlanReview()
      } else {
        ForEach(this.request?.questions.slice(this.questionIndex, this.questionIndex + 1) ?? [],
          (question: DesktopQuestion) => { this.Question(question) }, (question: DesktopQuestion): string => question.id)
      }
    }
    .padding(14).width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
    .borderRadius(16).backgroundColor($r('app.color.workspace_panel'))
    .border({ width: 1, color: $r('app.color.workspace_border') })
  }
}
