import type { SessionListItem } from 'appstate';
import { desktopSubagentFromSummary } from './DesktopSubagents';
import type { DesktopSubagentEntry } from './DesktopSubagents';
import { desktopWorkflowAbnormal, DesktopWorkflowStatus } from './DesktopWorkflowTimeline';
import type { DesktopWorkflowMember, DesktopWorkflowPhase, DesktopWorkflowView } from './DesktopWorkflowTimeline';

enum WorkflowMode { CLEAN, RUNNING, ABNORMAL }

interface WorkflowDisclosure {
  mode: WorkflowMode;
  count: number;
  open: boolean;
  pending: boolean;
}

function modeFor(status: DesktopWorkflowStatus): WorkflowMode {
  if (desktopWorkflowAbnormal(status)) { return WorkflowMode.ABNORMAL; }
  return status === DesktopWorkflowStatus.RUNNING ? WorkflowMode.RUNNING : WorkflowMode.CLEAN;
}

function disclosure(previous: WorkflowDisclosure | undefined, mode: WorkflowMode, count: number,
  focused: boolean): WorkflowDisclosure {
  if (previous === undefined) { return { mode: mode, count: count, open: mode !== WorkflowMode.CLEAN, pending: false }; }
  if (previous.mode === mode && previous.count === count) { return previous; }
  if (mode === WorkflowMode.CLEAN) {
    const pending = previous.open && focused;
    return { mode: mode, count: count, open: pending, pending: pending };
  }
  return { mode: mode, count: count, open: previous.open || previous.mode === WorkflowMode.CLEAN ||
    (mode === WorkflowMode.ABNORMAL && previous.mode !== WorkflowMode.ABNORMAL), pending: false };
}

function statusLabel(status: DesktopWorkflowStatus): Resource {
  switch (status) {
    case DesktopWorkflowStatus.COMPLETED: return $r('app.string.desktop_workflow_completed');
    case DesktopWorkflowStatus.FAILED: return $r('app.string.desktop_workflow_failed');
    case DesktopWorkflowStatus.CANCELLED: return $r('app.string.desktop_workflow_cancelled');
    case DesktopWorkflowStatus.INTERRUPTED: return $r('app.string.desktop_workflow_interrupted');
    default: return $r('app.string.desktop_workflow_running');
  }
}

function dotColor(status: DesktopWorkflowStatus): Resource {
  switch (status) {
    case DesktopWorkflowStatus.COMPLETED: return $r('sys.color.font_tertiary');
    case DesktopWorkflowStatus.FAILED: return $r('sys.color.warning');
    case DesktopWorkflowStatus.CANCELLED:
    case DesktopWorkflowStatus.INTERRUPTED: return $r('sys.color.alert');
    default: return $r('sys.color.font_tertiary');
  }
}

@Component
struct WorkflowStatusIndicator {
  @Prop status: DesktopWorkflowStatus = DesktopWorkflowStatus.RUNNING;

  build() {
    Row() {
      if (this.status === DesktopWorkflowStatus.RUNNING) {
        LoadingProgress().width(14).height(14).color($r('sys.color.brand'))
      } else {
        Circle().width(6).height(6).fill(dotColor(this.status))
      }
    }.width(14).height(14).justifyContent(FlexAlign.Center).accessibilityLevel('no')
  }
}

@Component
struct WorkflowMemberRow {
  @Prop member: DesktopWorkflowMember;
  @Prop sessionId: string = '';
  @Prop summaries: SessionListItem[] = [];
  onOpen: (target: DesktopSubagentEntry) => void = (_target: DesktopSubagentEntry): void => {};
  onFocused: () => void = (): void => {};
  onBlurred: () => void = (): void => {};
  @State private focused: boolean = false;

  private target(): DesktopSubagentEntry | undefined {
    if (this.member.status !== DesktopWorkflowStatus.RUNNING) { return undefined; }
    const summary = this.summaries.find((item: SessionListItem): boolean => item.id === this.member.childId);
    if (summary?.running !== true) { return undefined; }
    const child = desktopSubagentFromSummary(summary);
    return child?.parentId === this.sessionId && (child.mode === 'continuable' || child.mode === 'one-shot') ? child : undefined;
  }

  @Builder
  private Label() {
    Row({ space: 5 }) {
      WorkflowStatusIndicator({ status: this.member.status })
      Text(this.member.label || $r('app.string.desktop_workflow_empty_member')).fontSize(13).layoutWeight(1)
        .fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(statusLabel(this.member.status)).fontSize(11).fontColor($r('sys.color.font_secondary'))
    }.width('100%').height(27)
  }

  build() {
    Row() {
      if (this.target() !== undefined || this.focused) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL, type: ButtonType.Normal }) {
          this.Label()
        }.key('desktopWorkflowMemberOpen-' + this.member.sequence).height(27).width('100%')
          .padding({ left: 4, right: 4 }).borderRadius(6).focusOnTouch(false)
          .onFocus((): void => { this.focused = true; this.onFocused(); })
          .onBlur((): void => { this.focused = false; this.onBlurred(); })
          .onClick((): void => {
            const target = this.target();
            if (target !== undefined) { this.onOpen(target); }
          })
      } else {
        this.Label()
      }
    }.key('desktopWorkflowMember-' + this.member.sequence).width('100%')
  }
}

@Component
export struct DesktopWorkflowPane {
  @Prop @Watch('updateDisclosures') view: DesktopWorkflowView;
  runId: string = '';
  @Prop sessionId: string = '';
  @Prop summaries: SessionListItem[] = [];
  onOpen: (entry: DesktopSubagentEntry) => void = (_entry: DesktopSubagentEntry): void => {};
  @State private expanded: boolean = false;
  @State private openPhases: string[] = [];
  private runDisclosure?: WorkflowDisclosure;
  private readonly phases: Map<string, WorkflowDisclosure> = new Map();
  private focusInside: boolean = false;
  private focusInPhase: string = '';
  private blurTimer: number = -1;

  aboutToAppear(): void { this.updateDisclosures(); }
  aboutToDisappear(): void { clearTimeout(this.blurTimer); }

  private updateDisclosures(): void {
    let runMode = modeFor(this.view.status);
    let phaseRestarted = false;
    const open: string[] = [];
    for (const phase of this.view.phases) {
      const mode = phase.members.reduce((current: WorkflowMode, member: DesktopWorkflowMember): WorkflowMode =>
        Math.max(current, modeFor(member.status)), WorkflowMode.CLEAN);
      runMode = Math.max(runMode, mode);
      const previous = this.phases.get(phase.key);
      const next = disclosure(previous, mode, phase.members.length, this.focusInPhase === phase.key);
      phaseRestarted = phaseRestarted || (previous?.mode === WorkflowMode.CLEAN &&
        (next.mode !== WorkflowMode.CLEAN || previous.count !== next.count));
      this.phases.set(phase.key, next);
      if (next.open) { open.push(phase.key); }
    }
    this.runDisclosure = disclosure(this.runDisclosure, runMode, this.view.memberCount, this.focusInside);
    if (phaseRestarted && runMode !== WorkflowMode.CLEAN) { this.runDisclosure.open = true; }
    this.expanded = this.runDisclosure.open;
    this.openPhases = open;
  }

  private toggleRun(): void {
    if (this.runDisclosure !== undefined) {
      this.runDisclosure.open = !this.expanded;
      this.runDisclosure.pending = false;
      this.expanded = this.runDisclosure.open;
    }
  }

  private togglePhase(key: string): void {
    const state = this.phases.get(key);
    if (state === undefined) { return; }
    state.open = !state.open;
    state.pending = false;
    this.openPhases = state.open ? [...this.openPhases, key] :
      this.openPhases.filter((id: string): boolean => id !== key);
  }

  private focusChanged(inside: boolean, phase: string = ''): void {
    clearTimeout(this.blurTimer);
    if (inside) {
      this.focusInside = true;
      this.focusInPhase = phase;
      this.collapseUnfocused();
    } else {
      this.blurTimer = setTimeout((): void => {
        this.focusInside = false;
        this.focusInPhase = '';
        this.collapseUnfocused();
      }, 0);
    }
  }

  private collapseUnfocused(): void {
    if (!this.focusInside && this.runDisclosure?.pending === true) {
      this.runDisclosure.open = false;
      this.runDisclosure.pending = false;
      this.expanded = false;
    }
    this.phases.forEach((state: WorkflowDisclosure, key: string): void => {
      if (key !== this.focusInPhase && state.pending) {
        state.open = false;
        state.pending = false;
        this.openPhases = this.openPhases.filter((id: string): boolean => id !== key);
      }
    });
  }

  private phaseSummary(phase: DesktopWorkflowPhase): string {
    const counts: Map<DesktopWorkflowStatus, number> = new Map();
    for (const member of phase.members) {
      counts.set(member.status, (counts.get(member.status) ?? 0) + 1);
    }
    const active: string[] = [];
    const running = counts.get(DesktopWorkflowStatus.RUNNING) ?? 0;
    const failed = counts.get(DesktopWorkflowStatus.FAILED) ?? 0;
    const cancelled = counts.get(DesktopWorkflowStatus.CANCELLED) ?? 0;
    const interrupted = counts.get(DesktopWorkflowStatus.INTERRUPTED) ?? 0;
    const completed = counts.get(DesktopWorkflowStatus.COMPLETED) ?? 0;
    if (running > 0) { active.push('运行中 ' + running); }
    if (failed > 0) { active.push('失败 ' + failed); }
    if (cancelled > 0) { active.push('已取消 ' + cancelled); }
    if (interrupted > 0) { active.push('已中断 ' + interrupted); }
    if (active.length === 0 || (interrupted > 0 && completed > 0)) { active.unshift('已完成 ' + completed); }
    return active.join(' · ');
  }

  @Builder
  private Separator() {
    Circle().width(2).height(2).fill($r('sys.color.font_tertiary')).accessibilityLevel('no')
  }

  @Builder
  private Phase(phase: DesktopWorkflowPhase) {
    Column({ space: 1 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL, type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          Image($r('app.media.dsh_browser_chevron_right_outline')).width(16).height(16)
            .rotate({ angle: this.openPhases.includes(phase.key) ? 90 : 0 })
            .draggable(false).supportSvg2(true).accessibilityLevel('no')
          Text(phase.label === undefined ? $r('app.string.desktop_workflow_unphased') :
            phase.label || $r('app.string.desktop_workflow_empty_phase')).fontSize(13)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '42%' })
          this.Separator()
          Text($r('app.string.desktop_workflow_members', phase.members.length)).fontSize(12).layoutWeight(1)
            .fontColor($r('sys.color.font_secondary')).maxLines(1)
          Text(this.phaseSummary(phase)).fontSize(11).fontColor($r('sys.color.font_secondary'))
        }.width('100%')
      }.key('desktopWorkflowPhase-' + phase.key).height(32).padding({ left: 4, right: 8 }).width('100%').borderRadius(6)
        .focusOnTouch(false).accessibilitySelected(this.openPhases.includes(phase.key))
        .onFocus((): void => { this.focusChanged(true); }).onBlur((): void => { this.focusChanged(false); })
        .onClick((): void => { this.togglePhase(phase.key); })
      if (this.openPhases.includes(phase.key)) {
        ForEach(phase.members, (member: DesktopWorkflowMember): void => {
          WorkflowMemberRow({ member: member, sessionId: this.sessionId, summaries: this.summaries, onOpen: this.onOpen,
            onFocused: (): void => { this.focusChanged(true, phase.key); },
            onBlurred: (): void => { this.focusChanged(false); } }).margin({ left: 18 })
        }, (member: DesktopWorkflowMember): string => String(member.sequence) + ':' + member.status)
      }
    }.width('100%')
  }

  build() {
    Column({ space: 4 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL, type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          Image($r('app.media.dsh_browser_chevron_right_outline')).width(16).height(16)
            .rotate({ angle: this.expanded ? 90 : 0 }).draggable(false).supportSvg2(true).accessibilityLevel('no')
          Text(this.view.name).fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .constraintSize({ maxWidth: '42%' }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          this.Separator()
          Text($r('app.string.desktop_workflow_members', this.view.memberCount)).fontSize(13).layoutWeight(1)
            .maxLines(1).fontColor($r('sys.color.font_secondary'))
          WorkflowStatusIndicator({ status: this.view.status })
          Text(statusLabel(this.view.status)).key('desktopWorkflowRunStatus').fontSize(11)
            .fontColor($r('sys.color.font_primary'))
        }.width('100%')
      }.key('desktopWorkflowRun-' + this.runId).width('100%').height(32).padding({ left: 8, right: 8 })
        .borderRadius(8).backgroundColor($r('app.color.workspace_panel')).accessibilitySelected(this.expanded)
        .focusOnTouch(false).onClick((): void => { this.toggleRun(); })
      if (this.expanded) {
        if (this.view.phases.length === 0) {
          Text($r('app.string.desktop_workflow_empty_run')).fontSize(12)
            .padding({ left: 22 }).width('100%').fontColor($r('sys.color.font_secondary'))
        } else {
          Column() {
            ForEach(this.view.phases, (phase: DesktopWorkflowPhase): void => {
              this.Phase(phase)
            }, (phase: DesktopWorkflowPhase): string => JSON.stringify(phase))
          }.width('100%').padding({ left: 18 })
        }
      }
    }.width('100%').constraintSize({ maxWidth: 712 })
  }
}
