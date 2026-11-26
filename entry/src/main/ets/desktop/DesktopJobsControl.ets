import { JobDot, jobDotState, jobDurationText, jobElapsedMs, jobIsLive, jobStatusLabel, orderedJobs, SessionJob } from 'appstate';
import { getArray, getBoolean, getNumber, getRecord, getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';

interface DesktopJob extends SessionJob {
  outputTotal: number;
  exitCode?: number;
}

const OUTPUT_LIMIT: number = 65536;
const FOLD_ROWS: number = 5;

function readJob(raw: Object): DesktopJob | undefined {
  const id = getString(raw, 'id') ?? '';
  const status = getString(raw, 'status') ?? '';
  if (!id || !['running', 'stopping', 'completed', 'killed', 'failed'].includes(status)) {
    return undefined;
  }
  return { id: id, kind: getString(raw, 'kind') ?? '', label: getString(raw, 'label') || id, status: status,
    detail: getString(raw, 'progress') ?? getString(raw, 'detail'), exitCode: getNumber(raw, 'exitCode'),
    startedAt: getNumber(raw, 'startedAt') ?? 0, finishedAt: getNumber(raw, 'finishedAt'),
    outputTotal: getNumber(getRecord(raw, 'output'), 'total') ?? 0 };
}

@Component
export struct DesktopJobsControl {
  host?: DesktopHostActions;
  @Prop @Watch('resetSession') sessionId: string = '';
  @State private show: boolean = false;
  @State private jobs: DesktopJob[] = [];
  @State private rosterError: string = '';
  @State private ready: boolean = false;
  @State private observed: string = '';
  @State private output: string = '';
  @State private outputGap: boolean = false;
  @State private outputError: string = '';
  @State private outputEnded: boolean = false;
  @State private now: number = Date.now();
  @State private cleared: string[] = [];
  @State private settledFold: number = -1;
  @State private liveMore: boolean = false;
  @State private settledMore: boolean = false;
  @State private killId: string = '';
  @State private killPhase: string = '';
  private mounted: boolean = false;
  private rosterVersion: number = 0;
  private rosterFailures: number = 0;
  private rosterTimer: number = -1;
  private observeVersion: number = 0;
  private observeTimer: number = -1;
  private tickTimer: number = -1;
  private killTimer: number = -1;
  private outputCursor: number = -1;
  private stopRoster?: () => void;
  private stopOutput?: () => void;

  aboutToAppear(): void { this.mounted = true; this.resetSession(); }
  aboutToDisappear(): void { this.mounted = false; this.resetSession(); }

  private resetSession(): void {
    this.rosterVersion++;
    this.stopRoster?.();
    this.stopRoster = undefined;
    clearTimeout(this.rosterTimer);
    this.rosterFailures = 0;
    this.ready = false;
    this.jobs = [];
    this.rosterError = '';
    this.cleared = [];
    this.settledFold = -1;
    this.liveMore = false;
    this.settledMore = false;
    this.setPopup(false);
    if (this.mounted && this.sessionId) {
      this.watchRoster();
    }
  }

  private watchRoster(): void {
    const version = ++this.rosterVersion;
    clearTimeout(this.rosterTimer);
    this.stopRoster = this.host?.watch('job/list', { 'sessionId': this.sessionId }, {
      onItem: (value: Object): void => {
        if (version !== this.rosterVersion || getString(value, 'type') !== 'rows') { return; }
        const rows: DesktopJob[] = [];
        for (const entry of getArray(value, 'jobs') ?? []) {
          const job = readJob(entry);
          if (job !== undefined) { rows.push(job); }
        }
        // Keep the projection from the shared sorter while retaining the observation fields.
        const byId: Map<string, DesktopJob> = new Map();
        rows.forEach((job: DesktopJob): void => { byId.set(job.id, job); });
        const ordered: DesktopJob[] = [];
        orderedJobs(rows).forEach((item: SessionJob): void => {
          const job = byId.get(item.id);
          if (job !== undefined) { ordered.push(job); }
        });
        this.jobs = ordered;
        this.ready = true;
        this.rosterError = '';
        this.rosterFailures = 0;
        if (this.killId && !this.jobs.some((job: DesktopJob): boolean => job.id === this.killId && job.status === 'running')) {
          this.clearKill();
        }
        if (this.observed && !this.jobs.some((job: DesktopJob): boolean => job.id === this.observed)) {
          this.closeOutput();
        }
        this.updateClock();
      },
      onError: (code: string, message: string): void => { this.rosterEnded(version, message || code); },
      onEnd: (): void => { this.rosterEnded(version, '任务列表已断开'); }
    });
    if (this.stopRoster === undefined) { this.rosterEnded(version, '暂时无法读取后台任务'); }
  }

  private rosterEnded(version: number, message: string): void {
    if (version !== this.rosterVersion || !this.mounted) { return; }
    this.stopRoster = undefined;
    this.rosterError = message;
    this.rosterFailures++;
    this.rosterTimer = setTimeout((): void => { this.watchRoster(); }, Math.min(10000, this.rosterFailures * 1700));
  }

  private updateClock(): void {
    const needsClock = this.show && this.jobs.some((job: DesktopJob): boolean => jobIsLive(job));
    if (needsClock && this.tickTimer < 0) {
      this.now = Date.now();
      this.tickTimer = setInterval((): void => { this.now = Date.now(); }, 1000);
    } else if (!needsClock && this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  private setPopup(show: boolean): void {
    this.show = show;
    this.updateClock();
    if (!show) {
      this.clearKill();
      this.closeOutput();
    }
  }

  private closeOutput(): void {
    this.observeVersion++;
    this.stopOutput?.();
    this.stopOutput = undefined;
    clearTimeout(this.observeTimer);
    this.observed = '';
    this.output = '';
    this.outputGap = false;
    this.outputError = '';
    this.outputEnded = false;
    this.outputCursor = -1;
  }

  private toggleOutput(job: DesktopJob): void {
    const open = this.observed !== job.id;
    this.closeOutput();
    if (open) { this.observed = job.id; this.followOutput(job.id); }
  }

  private followOutput(id: string): void {
    const version = ++this.observeVersion;
    const body: Record<string, Object> = { 'sessionId': this.sessionId, 'jobId': id };
    if (this.outputCursor >= 0) { body['from'] = this.outputCursor; }
    this.stopOutput = this.host?.watch('job/follow', body, {
      onItem: (frame: Object): void => {
        if (version !== this.observeVersion) { return; }
        const type = getString(frame, 'type');
        if (type === 'opened') {
          const from = getNumber(frame, 'from') ?? 0;
          this.outputGap = this.outputGap || (this.output.length === 0 && from > 0) ||
            from > this.outputCursor && this.outputCursor >= 0;
          this.outputCursor = from;
          this.outputError = '';
        } else if (type === 'output') {
          this.appendOutput(frame);
        } else if (type === 'status') {
          this.outputEnded = true;
          this.outputError = '';
        }
      },
      onError: (code: string, message: string): void => { this.outputInterrupted(version, id, message || code); },
      onEnd: (): void => { this.outputInterrupted(version, id, '输出连接已断开'); }
    });
    if (this.stopOutput === undefined) { this.outputInterrupted(version, id, '暂时无法连接'); }
  }

  private appendOutput(frame: Object): void {
    const next = getNumber(frame, 'next');
    if (next === undefined || next <= this.outputCursor) { return; }
    let text = this.output;
    this.outputGap = this.outputGap || getBoolean(frame, 'lossy') === true;
    for (const chunk of getArray(frame, 'chunks') ?? []) {
      text += getString(chunk, 'text') ?? '';
      this.outputGap = this.outputGap || getBoolean(chunk, 'gapBefore') === true;
    }
    if (text.length > OUTPUT_LIMIT) {
      let cut = text.length - OUTPUT_LIMIT;
      const unit = text.charCodeAt(cut);
      if (unit >= 0xDC00 && unit <= 0xDFFF) { cut++; }
      text = text.substring(cut);
      this.outputGap = true;
    }
    this.output = text;
    this.outputCursor = next;
  }

  private outputInterrupted(version: number, id: string, message: string): void {
    if (version !== this.observeVersion) { return; }
    this.stopOutput = undefined;
    if (this.outputEnded) { return; }
    this.outputError = message;
    this.observeTimer = setTimeout((): void => { if (this.show && this.observed === id) { this.followOutput(id); } }, 2000);
  }

  private clearKill(): void {
    clearTimeout(this.killTimer);
    this.killId = '';
    this.killPhase = '';
  }

  private async kill(job: DesktopJob): Promise<void> {
    if (this.killId === job.id && this.killPhase === 'pending') { return; }
    if (this.killId !== job.id || this.killPhase !== 'armed') {
      this.clearKill();
      this.killId = job.id;
      this.killPhase = 'armed';
      this.killTimer = setTimeout((): void => { this.clearKill(); }, 3000);
      return;
    }
    clearTimeout(this.killTimer);
    this.killPhase = 'pending';
    const session = this.sessionId;
    const result = await this.host?.call('job/kill', { 'sessionId': session, 'jobId': job.id });
    if (session !== this.sessionId || this.killId !== job.id || this.killPhase !== 'pending') { return; }
    const outcome = getString(result?.value, 'outcome');
    if (!result?.ok || (outcome !== 'requested' && outcome !== 'already-finished')) {
      this.killPhase = 'failed';
      this.killTimer = setTimeout((): void => { this.clearKill(); }, 4000);
    }
  }

  private live(): DesktopJob[] { return this.jobs.filter((job: DesktopJob): boolean => jobIsLive(job)); }
  private settled(): DesktopJob[] {
    return this.jobs.filter((job: DesktopJob): boolean => !jobIsLive(job) && !this.cleared.includes(job.id));
  }

  private visible(inProgress: boolean): DesktopJob[] {
    const rows = inProgress ? this.live() : this.settled();
    const expanded = inProgress ? this.liveMore : this.settledMore;
    return !expanded && rows.length > FOLD_ROWS + 1 ? rows.slice(0, FOLD_ROWS) : rows;
  }

  private clearSettled(): void {
    this.cleared = [...this.cleared, ...this.settled().map((job: DesktopJob): string => job.id)];
    if (this.cleared.includes(this.observed)) { this.closeOutput(); }
  }

  private dot(job: DesktopJob): ResourceColor {
    const state = jobDotState(job.status);
    if (state === JobDot.ONGOING) { return $r('sys.color.brand'); }
    if (state === JobDot.ERROR || state === JobDot.WARNING || (job.exitCode ?? 0) !== 0) { return $r('sys.color.warning'); }
    return $r('app.color.desktop_diff_add_count');
  }

  @Builder
  private JobRow(job: DesktopJob) {
    Column({ space: 4 }) {
      Row({ space: 5 }) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 7 }) {
            Circle().width(7).height(7).fill(this.dot(job))
            Column({ space: 2 }) {
              Text(job.label).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text([jobStatusLabel(job.status), job.detail ?? '', jobDurationText(jobElapsedMs(job, this.now))]
                .filter((text: string): boolean => text.length > 0).join(' · '))
                .fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%')
        }
        .layoutWeight(1).padding(6).borderRadius(8).stateEffect(jobIsLive(job) || job.outputTotal > 0)
        .onClick((): void => { if (jobIsLive(job) || job.outputTotal > 0) { this.toggleOutput(job); } })
        if (job.status === 'running') {
          Button(this.killId !== job.id ? '停止任务' : this.killPhase === 'armed' ? '确认停止' :
            this.killPhase === 'pending' ? '正在停止' : '停止失败', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(30).padding({ left: 7, right: 7 }).enabled(this.killId !== job.id || this.killPhase !== 'pending')
            .onClick((): void => { this.kill(job); })
        }
      }.width('100%')
      if (this.observed === job.id) {
        Scroll() {
          Column({ space: 4 }) {
            if (this.outputGap) { Text('……较早的输出已丢弃……').fontSize(12) }
            Text(this.output || '（无输出）').fontFamily('monospace').fontSize(12).width('100%')
              .copyOption(CopyOptions.LocalDevice)
            if (this.outputError) { Text('实时输出流中断：' + this.outputError).fontSize(11) }
          }.alignItems(HorizontalAlign.Start).width('100%').padding(8)
        }.align(Alignment.TopStart).width('100%').constraintSize({ maxHeight: 186 })
        .backgroundColor($r('app.color.workspace_panel')).borderRadius(8)
      }
    }.width('100%')
  }

  @Builder
  private FoldJobs(count: number, expanded: boolean, active: boolean) {
    Button(expanded ? '收起' : `显示其余 ${count - FOLD_ROWS} 个${active ? '运行中' : '已结束'}`,
      { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
        if (active) { this.liveMore = !this.liveMore; } else { this.settledMore = !this.settledMore; }
      })
  }

  @Builder
  private Panel() {
    Scroll() {
      Column({ space: 6 }) {
        Text('后台任务').fontSize(15).fontWeight(FontWeight.Medium).padding({ left: 6, bottom: 3 })
        if (this.rosterError) { Text(this.rosterError).fontSize(12).padding(5) }
        if (!this.ready && !this.rosterError) { LoadingProgress().width(22).height(22).margin(8) }
        ForEach(this.visible(true), (job: DesktopJob): void => { this.JobRow(job) },
          (job: DesktopJob): string => `${job.id}:${job.status}:${job.outputTotal}:${job.detail ?? ''}`)
        if (this.live().length > FOLD_ROWS + 1) { this.FoldJobs(this.live().length, this.liveMore, true) }
        if (this.settled().length > 0) {
          Row() {
            Button(`已结束 ${this.settled().length}`, { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick((): void => {
                const wasOpen = this.settledFold === 1 || (this.settledFold < 0 && this.live().length === 0);
                this.settledFold = wasOpen ? 0 : 1;
                if (wasOpen && this.settled().some((job: DesktopJob): boolean => job.id === this.observed)) {
                  this.closeOutput();
                }
              })
            Blank()
            Button('清空', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.clearSettled(); })
          }.width('100%')
          if (this.settledFold === 1 || (this.settledFold < 0 && this.live().length === 0)) {
            ForEach(this.visible(false), (job: DesktopJob): void => { this.JobRow(job) },
              (job: DesktopJob): string => `${job.id}:${job.status}:${job.outputTotal}:${job.detail ?? ''}`)
            if (this.settled().length > FOLD_ROWS + 1) { this.FoldJobs(this.settled().length, this.settledMore, false) }
          }
        }
        if (this.ready && this.live().length === 0 && this.settled().length === 0) {
          Text('没有后台任务').fontSize(13).fontColor($r('sys.color.font_secondary')).padding(6)
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding(12)
    }.width(328).constraintSize({ maxHeight: 426 }).align(Alignment.TopStart)
  }

  build() {
    Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(16)
        if (this.live().length > 0) { Circle().width(7).height(7).fill($r('sys.color.brand')) }
      }
    }
    .width(38).height(34).padding(0).focusOnTouch(false).key('desktopJobsToggle')
    .accessibilityText(this.live().length > 0 ? `后台任务，${this.live().length} 个运行中` : '后台任务')
    .onClick((): void => { this.setPopup(!this.show); })
    .bindPopup(this.show, { builder: this.Panel(), placement: Placement.BottomRight, enableArrow: false,
      systemMaterial: desktopMenuOptions(Placement.BottomRight).systemMaterial,
      onStateChange: (event): void => { if (!event.isVisible && this.show) { this.setPopup(false); } } })
  }
}
