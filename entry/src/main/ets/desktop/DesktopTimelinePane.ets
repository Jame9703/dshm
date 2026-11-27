import type { StreamSink } from 'connection';
import { getField, getNumber, getRecord, getString, randomUuid } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopTimelineRuler } from './DesktopTimelineRuler';
import { desktopTimelineDiscussionKey, desktopTimelineDiscussionNotice, desktopTimelineDiscussionPayload,
  desktopTimelineOwnAnnotation, TIMELINE_DISCUSSION_LIMIT, TIMELINE_PRIORITIES } from './DesktopTimelineActions';
import type { DesktopTimelineDiscussionTarget, DesktopTimelineNoticeLabels } from './DesktopTimelineActions';
import { desktopTimelineValue, readDesktopTimeline } from './DesktopTimelineModel';
import type { DesktopTimelineReport, DesktopTimelineSource, DesktopTimelineTask, DesktopTimelineTree,
  DesktopTimelineView } from './DesktopTimelineModel';

interface TimelineDetailTarget {
  tree: string;
  id: string;
  scroll: number;
}

@Component
export struct DesktopTimelinePane {
  host?: DesktopHostActions;
  @Prop sessionId: string = '';
  @Prop @Watch('openingChanged') opening?: DesktopTimelineSource = undefined;
  @Prop @Watch('activeChanged') active: boolean = false;
  @Prop writable: boolean = false;
  onWeb: () => void = (): void => {};
  onNotify: (sessionId: string, text: string) => Promise<string> =
    (_sessionId: string, _text: string): Promise<string> => Promise.resolve('unavailable');

  @State private view: DesktopTimelineView = readDesktopTimeline();
  @State private viewRevision: number = 0;
  @State private tab: string = 'tasks';
  @State private treeId: string = '';
  @State private folded: string[] = [];
  @State private rulerVisited: boolean = false;
  @State private taskTrail: TimelineDetailTarget[] = [];
  @State private reportTrail: TimelineDetailTarget[] = [];
  @State private ready: boolean = false;
  @State private updating: boolean = false;
  @State private failed: boolean = false;
  @State private editBusy: boolean = false;
  @State private actionStatus: string = '';
  @State private discussionText: string = '';
  @State private discussionScope: string = '';
  @State private discussionExpanded: boolean = false;
  private publishedDiscussionText: string = '';
  private discussionId: string = '';
  private actionScope: string = '';
  private readonly scroll = new Scroller();
  private taskScroll: number = 0;
  private reportScroll: number = 0;
  private reportById: Map<string, DesktopTimelineReport> = new Map();
  private mounted: boolean = false;
  private generation: number = 0;
  private sequence: number = -2;
  private stopFollow?: () => void;
  private retryTimer: number = -1;
  private retries: number = 0;
  private scrollVersion: number = 0;

  aboutToAppear(): void {
    this.mounted = true;
    this.openingChanged();
    this.activeChanged();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.stop();
  }

  private activeChanged(): void {
    if (this.mounted && this.active) {
      this.retries = 0;
      this.connect();
    } else {
      this.stop();
    }
  }

  private openingChanged(): void {
    if (this.opening !== undefined) { this.accept(this.opening); }
  }

  private accept(source: DesktopTimelineSource): void {
    if (source.sequence <= this.sequence) { return; }
    this.sequence = source.sequence;
    this.view = readDesktopTimeline(source.value);
    this.reportById.clear();
    for (const row of this.view.reports) { this.reportById.set(row.id, row); }
    this.viewRevision++;
    this.ready = true;
    this.updating = false;
    this.failed = false;
  }

  private stop(): void {
    this.generation++;
    this.stopFollow?.();
    this.stopFollow = undefined;
    if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
  }

  private current(generation: number): boolean {
    return this.mounted && this.active && generation === this.generation;
  }

  private connect(): void {
    this.stop();
    const generation = this.generation;
    const host = this.host;
    if (!this.current(generation) || host === undefined || !this.sessionId) { return; }
    const address: Record<string, Object> = { 'sessionId': this.sessionId };
    this.updating = true;
    this.failed = false;
    const sink: StreamSink = {
      onItem: (frame: Object): void => {
        if (!this.current(generation)) { return; }
        if (getString(frame, 'type') === 'ready') {
          this.retries = 0;
          this.readBaseline(host, address, generation);
        } else {
          const update = desktopTimelineValue(frame);
          if (update !== undefined) { this.accept(update); }
        }
      },
      onError: (): void => { this.reconnect(generation); },
      onEnd: (): void => { this.reconnect(generation); }
    };
    this.stopFollow = host.watch('session/observeProjections', address, sink);
    if (this.stopFollow === undefined) { this.reconnect(generation); }
  }

  private async readBaseline(host: DesktopHostActions, address: Record<string, Object>, generation: number): Promise<void> {
    const result = await host.call('session/projections', address);
    if (!this.current(generation)) { return; }
    this.updating = false;
    const snapshot = getRecord(getRecord(result.value, 'values'), 'timeline');
    const sequence = getNumber(result.value, 'asOfSeq');
    if (!result.ok || sequence === undefined || !Number.isSafeInteger(sequence)) {
      this.failed = true;
      return;
    }
    if (snapshot !== undefined) {
      this.accept({ sequence: sequence, value: snapshot });
    } else if (sequence >= this.sequence) {
      this.sequence = sequence;
      this.view = readDesktopTimeline();
      this.reportById.clear();
      this.viewRevision++;
      this.ready = true;
    }
  }

  private reconnect(generation: number): void {
    if (!this.current(generation)) { return; }
    this.stop();
    this.updating = false;
    this.failed = true;
    if (this.retries >= 3) { return; }
    this.retries++;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (this.mounted && this.active) { this.connect(); }
    }, 1200 * this.retries);
  }

  private selectedTree(): DesktopTimelineTree | undefined {
    return this.view.trees.find((tree: DesktopTimelineTree): boolean => tree.id === (this.treeId || this.view.activeTree)) ??
      this.view.trees[0];
  }

  private treeOptions(): MenuElement[] {
    return this.view.trees.map((tree: DesktopTimelineTree): MenuElement => ({
      value: tree.title, action: (): void => { this.selectTree(tree.id); }
    }));
  }

  private selectTree(id: string): void {
    this.treeId = id;
    this.folded = [];
    this.taskTrail = [];
    this.moveScroll(0);
  }

  private isFolded(id: string): boolean { return this.folded.includes(id); }

  private fold(id: string): void {
    this.folded = this.isFolded(id) ? this.folded.filter((item: string): boolean => item !== id) : [...this.folded, id];
  }

  private visibleTasks(tree?: DesktopTimelineTree): DesktopTimelineTask[] {
    const rows: DesktopTimelineTask[] = [];
    let collapsedDepth = -1;
    for (const task of tree?.tasks ?? []) {
      if (collapsedDepth >= 0 && task.depth > collapsedDepth) { continue; }
      collapsedDepth = this.isFolded(task.id) ? task.depth : -1;
      rows.push(task);
    }
    return rows;
  }

  private report(id: string): DesktopTimelineReport | undefined {
    return this.reportById.get(id);
  }

  private task(target?: TimelineDetailTarget): DesktopTimelineTask | undefined {
    return this.view.trees.find((tree: DesktopTimelineTree): boolean => tree.id === target?.tree)?.tasks
      .find((task: DesktopTimelineTask): boolean => task.id === target?.id);
  }

  private trail(): TimelineDetailTarget[] { return this.tab === 'tasks' ? this.taskTrail : this.reportTrail; }

  private target(): TimelineDetailTarget | undefined { return this.trail()[this.trail().length - 1]; }

  private recordedScrollOffset(): number {
    try { return this.scroll.currentOffset().yOffset; } catch (_) { return 0; }
  }

  private moveScroll(offset: number): void {
    const revision = ++this.scrollVersion;
    setTimeout((): void => {
      if (this.mounted && !this.rulerShown() && revision === this.scrollVersion) {
        this.scroll.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
      }
    }, 0);
  }

  private rulerShown(): boolean { return this.tab === 'reports' && this.reportTrail.length === 0; }

  private selectTab(tab: string): void {
    if (tab === this.tab) { return; }
    if (this.tab === 'tasks') { this.taskScroll = this.recordedScrollOffset(); }
    else { this.reportScroll = this.recordedScrollOffset(); }
    if (tab === 'reports') { this.rulerVisited = true; }
    this.tab = tab;
    this.moveScroll(tab === 'tasks' ? this.taskScroll : this.reportScroll);
  }

  private pushDetail(tree: string, id: string): void {
    if (this.trail().some((row: TimelineDetailTarget): boolean => row.id === id && row.tree === tree)) { return; }
    const target: TimelineDetailTarget = { tree: tree, id: id, scroll: this.recordedScrollOffset() };
    if (this.tab === 'tasks') { this.taskTrail = [...this.taskTrail, target]; }
    else { this.reportTrail = [...this.reportTrail, target]; }
    this.moveScroll(0);
  }

  private back(): void {
    const offset = this.target()?.scroll ?? 0;
    if (this.tab === 'tasks') { this.taskTrail = this.taskTrail.slice(0, -1); }
    else { this.reportTrail = this.reportTrail.slice(0, -1); }
    this.moveScroll(offset);
  }

  private writeScope(): DesktopTimelineDiscussionTarget | undefined {
    const target = this.target();
    if (target === undefined) { return undefined; }
    if (this.tab === 'reports') {
      return this.report(target.id) === undefined ? undefined : { kind: 'report', tree: '', id: target.id };
    }
    return this.task(target) === undefined ? undefined : { kind: 'task', tree: target.tree, id: target.id };
  }

  private actionKey(): string {
    const scope = this.writeScope();
    if (scope === undefined) { return ''; }
    return desktopTimelineDiscussionKey(scope) + ':' + (scope.kind === 'task' ? this.task(this.target())?.ownPriority ?? '' : '');
  }

  private canWrite(): boolean {
    return this.mounted && this.active && this.writable && !this.editBusy && this.host !== undefined && !!this.sessionId;
  }

  private isDiscussionOpen(scope: DesktopTimelineDiscussionTarget): boolean {
    return this.discussionExpanded && desktopTimelineDiscussionKey(scope) === this.discussionScope;
  }

  private clearDiscussion(): void {
    this.discussionText = '';
    this.discussionScope = '';
    this.discussionExpanded = false;
    this.discussionId = '';
    this.publishedDiscussionText = '';
  }

  private toggleDiscussion(scope: DesktopTimelineDiscussionTarget): void {
    if (!this.canWrite()) { return; }
    const key = desktopTimelineDiscussionKey(scope);
    if (key === this.discussionScope) {
      this.discussionExpanded = !this.discussionExpanded;
      return;
    }
    this.clearDiscussion();
    this.actionStatus = '';
    this.discussionScope = key;
    this.discussionExpanded = true;
  }

  private priorityOptions(): MenuElement[] {
    const options: MenuElement[] = [];
    options.push({ value: $r('app.string.desktop_timeline_priority_none'), action: (): void => { this.setPriority(null); } });
    for (const priority of TIMELINE_PRIORITIES) {
      options.push({ value: priority, action: (): void => { this.setPriority(priority); } });
    }
    return options;
  }

  private async refreshEditedTimeline(): Promise<void> {
    const host = this.host;
    if (host !== undefined && this.active && this.mounted) {
      await this.readBaseline(host, { 'sessionId': this.sessionId }, this.generation);
    }
  }

  private async setPriority(priority: string | null): Promise<void> {
    const host = this.host;
    const scope = this.writeScope();
    const task = this.task(this.target());
    if (!this.canWrite() || host === undefined || scope?.kind !== 'task' || task === undefined ||
      task.ownPriority === (priority ?? '')) { return; }
    this.editBusy = true;
    this.actionStatus = '';
    this.actionScope = desktopTimelineDiscussionKey(scope);
    const payload: Record<string, Object | null> = {
      'action': 'priority', 'sessionId': this.sessionId, 'tree': scope.tree, 'task': scope.id, 'priority': priority
    };
    const reply = await host.editTimeline(payload);
    if (!this.mounted) { return; }
    if (reply.ok && getString(reply.value, 'action') === 'priority') {
      await this.refreshEditedTimeline();
    } else {
      this.actionStatus = reply.error?.message || this.resourceText($r('app.string.desktop_timeline_edit_failed'));
    }
    if (this.mounted) { this.editBusy = false; }
  }

  private resourceText(resource: Resource): string {
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(resource.id) ?? '';
  }

  private noticeLabels(): DesktopTimelineNoticeLabels {
    return {
      header: this.resourceText($r('app.string.desktop_timeline_notice_title')),
      report: this.resourceText($r('app.string.desktop_timeline_report_label')),
      task: this.resourceText($r('app.string.desktop_timeline_task_target')),
      tree: this.resourceText($r('app.string.desktop_timeline_task_tree')),
      progress: this.resourceText($r('app.string.desktop_timeline_report_progress')),
      uncertainties: this.resourceText($r('app.string.desktop_timeline_report_unknowns')),
      actions: this.resourceText($r('app.string.desktop_timeline_report_actions')),
      reference: this.resourceText($r('app.string.desktop_timeline_discussion_reference')),
      instructions: this.resourceText($r('app.string.desktop_timeline_discussion_instructions')),
      message: this.resourceText($r('app.string.desktop_timeline_discussion_message'))
    };
  }

  private async saveDiscussion(scope: DesktopTimelineDiscussionTarget): Promise<void> {
    const host = this.host;
    const message = this.discussionText.trim();
    if (!this.canWrite() || host === undefined || !this.isDiscussionOpen(scope) ||
      !message || message.length > TIMELINE_DISCUSSION_LIMIT) { return; }
    const session = this.sessionId;
    if (!this.discussionId || message !== this.publishedDiscussionText) {
      this.discussionId = randomUuid();
      this.publishedDiscussionText = message;
    }
    const id = this.discussionId;
    const payload: Record<string, Object> = {
      'action': 'annotate', 'sessionId': session, 'id': id,
      'target': desktopTimelineDiscussionPayload(scope), 'text': message
    };
    this.editBusy = true;
    this.actionStatus = '';
    this.actionScope = desktopTimelineDiscussionKey(scope);
    const result = await host.editTimeline(payload);
    if (!this.mounted || session !== this.sessionId) { return; }
    const annotation = getRecord(result.value, 'annotation');
    const pendingReply = getField(annotation, 'reply') === null;
    if (!result.ok || getString(result.value, 'action') !== 'annotate' ||
      !desktopTimelineOwnAnnotation(annotation, id, scope, message) ||
      (!pendingReply && getRecord(annotation, 'reply') === undefined)) {
      this.actionStatus = result.error?.message || this.resourceText($r('app.string.desktop_timeline_edit_failed'));
      this.editBusy = false;
      return;
    }
    this.clearDiscussion();
    let notified = true;
    if (pendingReply) {
      const text = desktopTimelineDiscussionNotice(scope, id, message, getRecord(result.value, 'context'), this.noticeLabels());
      try { notified = (await this.onNotify(session, text)).length === 0; }
      catch (_) { notified = false; }
    }
    if (!this.mounted || session !== this.sessionId) { return; }
    this.actionStatus = this.resourceText(notified ? $r('app.string.desktop_timeline_discussion_saved') :
      $r('app.string.desktop_timeline_discussion_notify_unknown'));
    await this.refreshEditedTimeline();
    if (this.mounted) { this.editBusy = false; }
  }

  @Builder
  private EditFooter(scope?: DesktopTimelineDiscussionTarget) {
    if (scope !== undefined && this.writable) {
      Column({ space: 7 }) {
        if (this.isDiscussionOpen(scope)) {
          TextArea({ text: this.discussionText, placeholder: $r('app.string.desktop_timeline_discussion_placeholder') })
            .key('desktopTimelineDiscussionText').height(72).width('100%').fontSize(13)
            .maxLength(TIMELINE_DISCUSSION_LIMIT).enabled(this.canWrite())
            .onChange((value: string): void => {
              if (!this.editBusy && value !== this.discussionText) { this.discussionText = value; this.actionStatus = ''; }
            })
          Row({ space: 6 }) {
            Text($r('app.string.desktop_timeline_count', this.discussionText.length, TIMELINE_DISCUSSION_LIMIT))
              .fontSize(10).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            Button($r('app.string.desktop_timeline_discussion_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopTimelineDiscussionCancel').height(30).enabled(!this.editBusy)
              .onClick((): void => { this.clearDiscussion(); this.actionStatus = ''; })
            Button($r('app.string.desktop_timeline_save'), { buttonStyle: ButtonStyleMode.NORMAL })
              .key('desktopTimelineDiscussionSave').height(30)
              .enabled(this.canWrite() && this.discussionText.trim().length > 0)
              .onClick((): void => { this.saveDiscussion(scope); })
          }.width('100%')
        }
        Row({ space: 6 }) {
          if (scope.kind === 'task') {
            Button($r('app.string.desktop_timeline_priority_value', this.task(this.target())?.priority ||
              this.resourceText($r('app.string.desktop_timeline_priority_none'))), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopTimelineTaskPriority').height(30).enabled(this.canWrite())
              .bindMenu(this.priorityOptions(), desktopMenuOptions(Placement.TopLeft))
          }
          Button($r('app.string.desktop_timeline_discussion_add'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineDiscuss').height(30).enabled(this.canWrite())
            .accessibilitySelected(this.isDiscussionOpen(scope)).onClick((): void => { this.toggleDiscussion(scope); })
          if (this.editBusy) { LoadingProgress().width(16).height(16) }
        }.width('100%')
        if (this.actionStatus && this.actionScope === desktopTimelineDiscussionKey(scope)) {
          Text(this.actionStatus).key('desktopTimelineEditStatus').width('100%')
            .fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
      }.width('100%').padding({ top: 6 }).alignItems(HorizontalAlign.Start)
        .borderWidth({ top: 0.5 }).borderColor($r('sys.color.comp_divider'))
    }
  }

  private status(value: string): Resource {
    switch (value) {
      case 'active': return $r('app.string.desktop_timeline_active');
      case 'done': return $r('app.string.desktop_timeline_done');
      case 'blocked': return $r('app.string.desktop_timeline_blocked');
      case 'paused': return $r('app.string.desktop_timeline_paused');
      default: return $r('app.string.desktop_timeline_pending');
    }
  }

  private time(value: number): string { return new Date(value).toLocaleString(); }

  private duration(ms: number): string {
    const minutes = Math.floor(ms / 60000);
    if (minutes <= 0) { return '<1m'; }
    const hours = Math.floor(minutes / 60);
    return hours > 0 ? String(hours) + 'h ' + (minutes % 60) + 'm' : String(minutes) + 'm';
  }

  private targetAnnotations(kind: string, tree: string, id: string): Object[] {
    return this.view.annotations.filter((entry: Object): boolean => {
      const target = getRecord(entry, 'target');
      return getString(target, 'kind') === kind && (kind === 'report' ? getString(target, 'report') === id :
        getString(target, 'tree') === tree && (kind !== 'task' || getString(target, 'task') === id));
    });
  }

  @Builder
  private Tab(label: Resource, id: string, key: string) {
    Button(label, { buttonStyle: this.tab === id ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL })
      .key(key).height(32).layoutWeight(1).accessibilitySelected(this.tab === id)
      .onClick((): void => { this.selectTab(id); })
  }

  @Builder
  private TaskRow(tree: DesktopTimelineTree, task: DesktopTimelineTask) {
    Row({ space: 5 }) {
      if (task.children > 0) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_browser_chevron_right_outline')).width(12).height(12).supportSvg2(true)
            .rotate({ angle: this.isFolded(task.id) ? 0 : 90 }).accessibilityLevel('no')
        }.width(24).height(30).padding(0).key('desktopTimelineFold-' + task.id)
          .accessibilityText(task.title).onClick((): void => { this.fold(task.id); })
      } else {
        Circle({ width: 6, height: 6 }).fill(task.status === 'done' ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
          .margin({ left: 9, right: 9 }).accessibilityLevel('no')
      }
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Column({ space: 4 }) {
          Text(task.title).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
          Row({ space: 6 }) {
            Text(this.status(task.status)).fontSize(11).fontColor($r('sys.color.font_secondary'))
            if (task.priority) { Text(task.priority).fontSize(11).fontColor($r('sys.color.brand')) }
            if (task.note) {
              Text(task.note).fontSize(11).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).padding(3).borderRadius(6).key('desktopTimelineTask-' + task.id)
        .accessibilityText(task.title).onClick((): void => { this.pushDetail(tree.id, task.id); })
      Text((task.progress * 100).toFixed(2) + '%').fontSize(11).fontColor($r('sys.color.font_secondary'))
    }.width('100%').padding({ left: 8 + Math.min(5, task.depth) * 10 })
  }

  @Builder
  private Discussions(kind: string, tree: string, id: string) {
    if (this.targetAnnotations(kind, tree, id).length > 0) {
      Text($r('app.string.desktop_timeline_discussions')).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
      ForEach(this.targetAnnotations(kind, tree, id), (entry: Object): void => {
        Column({ space: 6 }) {
          Text(getString(entry, 'text') ?? '').fontSize(13).copyOption(CopyOptions.LocalDevice)
          if (getString(getRecord(entry, 'reply'), 'text')) {
            Text(getString(getRecord(entry, 'reply'), 'text') ?? '').fontSize(13)
              .fontColor($r('sys.color.font_secondary')).copyOption(CopyOptions.LocalDevice)
          }
        }.width('100%').padding(8).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.workspace_panel'))
      }, (entry: Object): string => (getString(entry, 'id') ?? '') + ':' + (getString(getRecord(entry, 'reply'), 'text') ?? ''))
    }
  }

  @Builder
  private Tasks(tree?: DesktopTimelineTree) {
    if (tree === undefined) {
      Text($r('app.string.desktop_timeline_no_tasks')).width('100%').fontSize(13).fontColor($r('sys.color.font_secondary'))
    } else {
      Row({ space: 8 }) {
        Button(tree.title, { buttonStyle: ButtonStyleMode.TEXTUAL }).layoutWeight(1).key('desktopTimelineTree')
          .bindMenu(this.treeOptions(), desktopMenuOptions(Placement.BottomLeft))
        Text((tree.progress * 100).toFixed(2) + '%').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      Progress({ value: tree.progress * 100, total: 100, type: ProgressType.Linear }).width('100%')
      if (tree.description) { Text(tree.description).fontSize(13).width('100%') }
      ForEach(this.visibleTasks(tree), (task: DesktopTimelineTask): void => { this.TaskRow(tree, task) },
        (task: DesktopTimelineTask): string => tree.id + ':' + task.id + ':' + task.status + ':' + task.progress + ':' +
          task.title + ':' + task.note + ':' + task.priority + ':' + task.depth + ':' + task.children)
      this.Discussions('tree', tree.id, '')
    }
  }

  @Builder
  private ReportRow(report: DesktopTimelineReport, key: string) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text($r('app.string.desktop_timeline_level', report.level + 1)).fontSize(12).fontColor($r('sys.color.brand'))
          Text(this.time(report.end)).fontSize(11).fontColor($r('sys.color.font_secondary'))
        }.width('100%')
        Text(report.progress[0] || $r('app.string.desktop_timeline_report_label')).width('100%')
          .fontSize(14).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start).padding(9)
    }.width('100%').padding(0).borderRadius(8).key(key).backgroundColor($r('app.color.workspace_panel'))
      .onClick((): void => { this.pushDetail('', report.id); })
  }

  @Builder
  private TaskDetail(task?: DesktopTimelineTask, target?: TimelineDetailTarget) {
    Column({ space: 9 }) {
      if (task !== undefined && target !== undefined) {
        Text(task.title).width('100%').fontSize(18).fontWeight(FontWeight.Medium)
        Text(this.status(task.status)).fontSize(13).fontColor($r('sys.color.font_secondary'))
        Progress({ value: task.progress * 100, total: 100, type: ProgressType.Linear }).width('100%')
        if (task.description) { Text(task.description).width('100%').fontSize(14) }
        if (task.note) { Text(task.note).width('100%').fontSize(13).copyOption(CopyOptions.LocalDevice) }
        if (task.details) { Text(task.details).width('100%').fontSize(13).copyOption(CopyOptions.LocalDevice) }
        if (task.history.length > 0) {
          Text($r('app.string.desktop_timeline_task_history')).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
          ForEach(task.history.slice(-40).reverse(), (row: Object): void => {
            Column({ space: 3 }) {
              Text(this.time(getNumber(row, 'at') ?? 0)).fontSize(11).fontColor($r('sys.color.font_secondary'))
              Text(getString(row, 'note') || getString(row, 'details') || getString(row, 'title') || '').fontSize(13)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }, (row: Object, index: number): string => String(getNumber(row, 'at') ?? 0) + ':' + index)
        }
        this.Discussions('task', target.tree, target.id)
      } else {
        Text($r('app.string.desktop_timeline_missing_detail')).width('100%').fontSize(13)
      }
    }.key('desktopTimelineTaskDetail').width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ReportSection(title: Resource, lines: string[]) {
    if (lines.length > 0) {
      Text(title).fontWeight(FontWeight.Medium).fontSize(14).width('100%')
      ForEach(lines, (line: string): void => {
        Text('• ' + line).fontSize(13).width('100%').copyOption(CopyOptions.LocalDevice)
      }, (line: string, index: number): string => String(index) + ':' + line)
    }
  }

  @Builder
  private ReportDetail(report?: DesktopTimelineReport) {
    Column({ space: 9 }) {
      if (report !== undefined) {
        Text($r('app.string.desktop_timeline_level', report.level + 1)).width('100%')
          .fontSize(18).fontWeight(FontWeight.Medium)
        Text(this.time(report.start) + ' – ' + this.time(report.end)).width('100%')
          .fontColor($r('sys.color.font_secondary')).fontSize(12)
        Text($r('app.string.desktop_timeline_tool_calls', report.toolCount)).fontSize(12)
        if (report.savedPeriod !== undefined) {
          Text($r('app.string.desktop_timeline_saved_period', this.duration(report.savedPeriod))).fontSize(12)
        }
        if (report.workMs !== undefined && report.workMs !== report.savedPeriod) {
          Text($r('app.string.desktop_timeline_work_duration', this.duration(report.workMs))).fontSize(12)
        }
        this.ReportSection($r('app.string.desktop_timeline_report_progress'), report.progress)
        this.ReportSection($r('app.string.desktop_timeline_report_unknowns'), report.uncertainties)
        this.ReportSection($r('app.string.desktop_timeline_report_actions'), report.actions)
        if (report.children.length > 0) {
          Text($r('app.string.desktop_timeline_child_reports')).fontSize(14).fontWeight(FontWeight.Medium)
          ForEach(report.children, (id: string): void => {
            if (this.report(id) !== undefined) { this.ReportRow(this.report(id)!, 'desktopTimelineReportChild-' + id) }
          }, (id: string): string => id)
        }
        this.Discussions('report', '', report.id)
      } else {
        Text($r('app.string.desktop_timeline_missing_detail')).width('100%').fontSize(13)
      }
    }.key('desktopTimelineReportDetail').width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        this.Tab($r('app.string.desktop_timeline_task_tree'), 'tasks', 'desktopTimelineTasksTab')
        this.Tab($r('app.string.desktop_timeline_report_label'), 'reports', 'desktopTimelineReportsTab')
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.link')).fontSize(16).fontColor([$r('sys.color.font_secondary')]).accessibilityLevel('no')
        }.width(28).height(30).padding(0).key('desktopTimelineOpenWeb')
          .accessibilityText($r('app.string.desktop_timeline_web_actions')).onClick(this.onWeb)
      }.width('100%')
      if (this.target() !== undefined) {
        Row() {
          Button($r('app.string.desktop_timeline_back'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineDetailBack').height(32).onClick((): void => { this.back(); })
        }.width('100%')
      }
      if (this.failed) {
        Row({ space: 6 }) {
          Text($r('app.string.desktop_timeline_link_lost')).fontSize(12).layoutWeight(1)
          Button($r('app.string.desktop_experiment_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineRetry').onClick((): void => { this.retries = 0; this.connect(); })
        }.width('100%')
      }
      if (this.updating && !this.ready) { LoadingProgress().width(20).height(20) }
      if (this.view.error) { Text(this.view.error).fontSize(12).fontColor($r('app.color.workspace_status_error')) }
      if (this.rulerVisited) {
        DesktopTimelineRuler({ host: this.host, active: this.active && this.rulerShown(), reports: this.view.reports,
          onOpen: (id: string): void => { this.pushDetail('', id); } })
          .visibility(this.rulerShown() ? Visibility.Visible : Visibility.None).layoutWeight(1)
      }
      if (!this.rulerShown()) {
        Scroll(this.scroll) {
          Column({ space: 9 }) {
            ForEach([this.viewRevision], (_revision: number): void => {
              if (this.tab === 'tasks') {
                if (this.target() === undefined) { this.Tasks(this.selectedTree()) }
                else { this.TaskDetail(this.task(this.target()), this.target()) }
              } else {
                this.ReportDetail(this.report(this.target()?.id ?? ''))
              }
            }, (revision: number): string => String(revision))
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart)
      }
      if (this.writable && this.actionKey()) {
        ForEach([this.actionKey()], (_key: string): void => { this.EditFooter(this.writeScope()) },
          (key: string): string => key)
      }
    }.key('desktopTimelinePane').width('100%').height('100%').padding(10).alignItems(HorizontalAlign.Start)
  }
}
