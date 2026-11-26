import { KeyCode } from '@kit.InputKit';
import { DesktopGoal, DesktopGoalAction, DesktopGoalRef } from './DesktopGoal';

@Component
export struct DesktopGoalBar {
  @Prop @Watch('goalChanged') goal: DesktopGoal = {
    id: '', revision: 0, objective: '', phase: '', blocker: '', activation: ''
  };
  @Prop busy: boolean = false;
  onAction: (action: DesktopGoalAction, ref: DesktopGoalRef, objective: string) => Promise<string> =
    (_action: DesktopGoalAction, _ref: DesktopGoalRef, _objective: string): Promise<string> => Promise.resolve('');
  @State private editing: boolean = false;
  @State private draft: string = '';
  @State private notice: string = '';
  private editingRef?: DesktopGoalRef;
  private seenId: string = '';
  private inFlight: boolean = false;

  aboutToAppear(): void {
    this.seenId = this.goal.id;
  }

  private goalChanged(): void {
    if (this.goal.id !== this.seenId) {
      this.seenId = this.goal.id;
      this.cancel();
    }
  }

  private cancel(): void {
    this.editing = false;
    this.editingRef = undefined;
    this.notice = '';
  }

  private edit(): void {
    this.editingRef = { id: this.goal.id, revision: this.goal.revision };
    this.draft = this.goal.objective;
    this.notice = '';
    this.editing = true;
  }

  private canResume(): boolean {
    return this.goal.phase !== 'active' || this.goal.activation === 'disarmed';
  }

  private phaseLabel(): string {
    if (this.goal.phase === 'paused') { return '已暂停的目标'; }
    if (this.goal.phase === 'blocked') { return '受阻的目标'; }
    return this.goal.activation === 'disarmed' ? '待继续的目标' : '进行中的目标';
  }

  private async run(action: DesktopGoalAction): Promise<void> {
    const edit = action === DesktopGoalAction.EDIT;
    if (this.busy || this.inFlight || (edit && !this.draft.trim())) { return; }
    const ref: DesktopGoalRef = edit && this.editingRef !== undefined ? this.editingRef :
      { id: this.goal.id, revision: this.goal.revision };
    this.inFlight = true;
    this.notice = '';
    try {
      const error = await this.onAction(action, ref, edit ? this.draft : '');
      if (ref.id === this.goal.id) {
        if (!error && edit) { this.cancel(); }
        this.notice = error;
      }
    } finally {
      this.inFlight = false;
    }
  }

  @Builder
  private Glyph(resource: Resource) {
    Image(resource).width(14).height(14).supportSvg2(true).draggable(false).accessibilityLevel('no')
  }

  @Builder
  private IconButton(resource: Resource, label: string, id: string, active: boolean, action: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) { this.Glyph(resource) }
      .key(id).width(28).height(28).padding(0).focusOnTouch(false).enabled(active && !this.busy)
      .accessibilityText(label).onClick(action)
  }

  build() {
    Column({ space: 3 }) {
      if (this.editing) {
        Row({ space: 8 }) {
          TextArea({ text: this.draft, placeholder: '目标内容' }).key('desktopGoalDraft')
            .accessibilityText('目标内容').layoutWeight(1).fontSize(13).lineHeight(20)
            .constraintSize({ minHeight: 36, maxHeight: 116 }).padding({ left: 4, right: 4, top: 7, bottom: 5 })
            .backgroundColor(Color.Transparent).enabled(!this.busy).defaultFocus(true).enterKeyType(EnterKeyType.Done)
            .onChange((value: string): void => { this.draft = value; })
            .onSubmit((): void => { this.run(DesktopGoalAction.EDIT); })
            .onKeyPreIme((event: KeyEvent): boolean => {
              if (event.type !== KeyType.Down || this.busy) { return false; }
              if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.cancel(); return true; }
              if (event.keyCode === KeyCode.KEYCODE_ENTER && !event.getModifierKeyState?.(['Shift'])) {
                this.run(DesktopGoalAction.EDIT);
                return true;
              }
              return false;
            })
          this.IconButton($r('app.media.dsh_dock_check'), '保存目标', 'desktopGoalSave', this.draft.trim().length > 0,
            (): void => { this.run(DesktopGoalAction.EDIT); })
          this.IconButton($r('app.media.dsh_dock_close'), '取消编辑', 'desktopGoalCancel', true,
            (): void => { this.cancel(); })
        }.width('100%').alignItems(VerticalAlign.Bottom)
      } else {
        Row({ space: 8 }) {
          this.Glyph($r('app.media.dsh_dock_goal'))
          Text(this.phaseLabel()).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          Text(this.goal.objective).fontSize(13).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).key('desktopGoalObjective')
          this.IconButton($r('app.media.dsh_dock_edit'), '编辑目标', 'desktopGoalEdit', true,
            (): void => { this.edit(); })
          this.IconButton($r('app.media.dsh_dock_trash'), '清除目标', 'desktopGoalClear', true,
            (): void => { this.run(DesktopGoalAction.CLEAR); })
          this.IconButton(this.canResume() ? $r('app.media.dsh_dock_play') : $r('app.media.dsh_dock_pause'),
            this.canResume() ? '恢复目标' : '暂停目标', 'desktopGoalContinuation',
            this.canResume() || this.goal.activation === 'armed',
            (): void => { this.run(this.canResume() ? DesktopGoalAction.RESUME : DesktopGoalAction.PAUSE); })
        }.width('100%').height(30)
      }
      if (this.notice || this.goal.blocker) {
        Text(this.notice || this.goal.blocker).fontSize(12).fontColor($r('sys.color.warning')).width('100%')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%').constraintSize({ maxWidth: 688 }).alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 5, top: 3, bottom: 3 }).borderRadius(12)
    .backgroundColor($r('app.color.workspace_panel')).border({ width: 1, color: $r('app.color.workspace_border') })
  }
}
