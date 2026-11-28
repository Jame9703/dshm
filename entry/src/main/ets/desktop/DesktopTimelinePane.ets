import { dialogMaterial } from 'platform';
import { getField, getNumber, getRecord, getString, randomUuid } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopTimelineRuler } from './DesktopTimelineRuler';
import { desktopTimelineCheckpoint, desktopTimelineCheckpointName, previewDesktopTimelineCheckpoint } from './DesktopTimelineCheckpoint';
import { saveDesktopTimelineCheckpoint } from './DesktopTimelineTransferIO';
import { DesktopTimelineTransferDialog } from './DesktopTimelineTransferDialog';
import { DesktopTimelineRemoveDialog } from './DesktopTimelineRemoveDialog';
import type { DesktopTimelineImportRequest } from './DesktopTimelineTransferDialog';
import { desktopTimelineControlDeadline, desktopTimelinePlayback } from './DesktopTimelineControl';
import type { DesktopTimelinePlayback } from './DesktopTimelineControl';
import { desktopTimelineDiscussionKey, desktopTimelineDiscussionNotice, desktopTimelineDiscussionPayload,
  desktopTimelineOwnAnnotation, TIMELINE_DISCUSSION_LIMIT, TIMELINE_PRIORITIES } from './DesktopTimelineActions';
import type { DesktopTimelineDiscussionTarget, DesktopTimelineNoticeLabels } from './DesktopTimelineActions';
import { desktopTimelineStatus, readDesktopTimeline } from './DesktopTimelineModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';
import { DesktopTimelineProgressBar } from './DesktopTimelineProgressBar';
import type { DesktopTimelineLocation, DesktopTimelineReport, DesktopTimelineSource, DesktopTimelineTask, DesktopTimelineTree,
  DesktopTimelineView } from './DesktopTimelineModel';

interface TimelineRemoveTarget {
  tree: DesktopTimelineTree;
  annotations: Object[];
}

interface TimelineBackupResult {
  saved: boolean;
  error: string;
}

interface TimelineControlAttempt {
  key: string;
  id: string;
  text: string;
}

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
  @Prop @Watch('applyLocation') location?: DesktopTimelineLocation = undefined;
  @Prop @Watch('activeChanged') active: boolean = false;
  @Prop writable: boolean = false;
  @Prop running: boolean = false;
  @Prop progressDecimals: number = 2;
  @Prop segmentedProgress: boolean = true;
  @Prop linkLost: boolean = false;
  onRetry: () => void = (): void => {};
  onTaskRoot: (session: string, tree: string) => void = (): void => {};
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
  @State private failed: boolean = false;
  @State private editBusy: boolean = false;
  @State private transferStatus: string = '';
  @State private exportBusy: boolean = false;
  @State private removeStale: boolean = false;
  private removeTarget?: TimelineRemoveTarget;
  private transferDialog: number = -1;
  private transferOpening: boolean = false;
  private transferBusy: boolean = false;
  private transferVersion: number = 0;
  @State private actionStatus: string = '';
  @State private discussionText: string = '';
  @State private discussionScope: string = '';
  @State private discussionExpanded: boolean = false;
  @State private controlNow: number = 0;
  @State private acknowledgedControls: Object[] = [];
  private controlTimer: number = -1;
  private controlAttempt?: TimelineControlAttempt;
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
  private scrollVersion: number = 0;
  private locationRevision: number = 0;

  aboutToAppear(): void {
    this.mounted = true;
    this.openingChanged();
    this.activeChanged();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.closeTransfer();
    this.stop();
  }

  private activeChanged(): void {
    if (this.mounted && this.active) {
      this.applyLocation();
      this.scheduleControlTimer();
      this.publishTaskRoot();
    } else {
      this.closeTransfer();
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
    const removal = this.removeTarget;
    if (removal !== undefined && !this.sameRemovalTarget(removal)) { this.removeStale = true; }
    const observed = new Set<string>(this.view.annotations.map((row: Object): string => getString(row, 'id') ?? ''));
    this.acknowledgedControls = this.acknowledgedControls.filter((row: Object): boolean =>
      !observed.has(getString(row, 'id') ?? ''));
    this.scheduleControlTimer();
    this.reportById.clear();
    for (const row of this.view.reports) { this.reportById.set(row.id, row); }
    this.viewRevision++;
    this.ready = true;
    this.failed = false;
    this.applyLocation();
    this.publishTaskRoot();
  }

  private applyLocation(): void {
    const location = this.location;
    if (!this.mounted || !this.active || !this.ready || location === undefined ||
        location.session !== this.sessionId || location.revision <= this.locationRevision) { return; }
    if (location.tree && !this.view.trees.some((tree: DesktopTimelineTree): boolean => tree.id === location.tree)) { return; }
    if (location.task && this.task({ tree: location.tree, id: location.task, scroll: 0 }) === undefined) { return; }
    this.locationRevision = location.revision;
    this.selectTab('tasks');
    this.reportTrail = [];
    this.selectTree(location.tree);
    if (location.task) { this.pushDetail(location.tree, location.task); }
  }

  private stop(): void {
    this.generation++;
    if (this.controlTimer >= 0) { clearTimeout(this.controlTimer); this.controlTimer = -1; }
  }

  private current(generation: number): boolean {
    return this.mounted && this.active && generation === this.generation;
  }

  private async readBaseline(host: DesktopHostActions, address: Record<string, Object>, generation: number): Promise<void> {
    const result = await host.call('session/projections', address);
    if (!this.current(generation)) { return; }
    const snapshot = getRecord(getRecord(result.value, 'values'), 'timeline');
    const sequence = getNumber(result.value, 'asOfSeq');
    if (!result.ok || sequence === undefined || !Number.isSafeInteger(sequence)) {
      this.failed = true;
      return;
    }
    this.failed = false;
    if (snapshot !== undefined) {
      this.accept({ sequence: sequence, value: snapshot });
    } else if (sequence >= this.sequence) {
      this.sequence = sequence;
      this.view = readDesktopTimeline();
      if (this.removeTarget !== undefined) { this.removeStale = true; }
      this.acknowledgedControls = [];
      this.scheduleControlTimer();
      this.reportById.clear();
      this.viewRevision++;
      this.ready = true;
      this.publishTaskRoot();
    }
  }

  private publishTaskRoot(): void {
    if (this.active && this.mounted) {
      const tree = this.tab === 'tasks' && this.taskTrail.length === 0 ? this.selectedTree()?.id ?? '' : '';
      this.onTaskRoot(this.sessionId, tree);
    }
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
    this.publishTaskRoot();
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
    this.scheduleControlTimer();
    this.moveScroll(tab === 'tasks' ? this.taskScroll : this.reportScroll);
    this.publishTaskRoot();
  }

  private pushDetail(tree: string, id: string): void {
    if (this.trail().some((row: TimelineDetailTarget): boolean => row.id === id && row.tree === tree)) { return; }
    const target: TimelineDetailTarget = { tree: tree, id: id, scroll: this.recordedScrollOffset() };
    if (this.tab === 'tasks') { this.taskTrail = [...this.taskTrail, target]; }
    else { this.reportTrail = [...this.reportTrail, target]; }
    this.moveScroll(0);
    this.publishTaskRoot();
  }

  private back(): void {
    const offset = this.target()?.scroll ?? 0;
    if (this.tab === 'tasks') { this.taskTrail = this.taskTrail.slice(0, -1); }
    else { this.reportTrail = this.reportTrail.slice(0, -1); }
    this.moveScroll(offset);
    this.publishTaskRoot();
  }

  private controlAnnotations(): Object[] {
    return this.acknowledgedControls.length ? this.view.annotations.concat(this.acknowledgedControls) : this.view.annotations;
  }

  private scheduleControlTimer(): void {
    if (this.controlTimer >= 0) { clearTimeout(this.controlTimer); this.controlTimer = -1; }
    this.controlNow = Date.now();
    if (!this.mounted || !this.active || this.tab !== 'tasks') { return; }
    const deadline = desktopTimelineControlDeadline(this.controlAnnotations(), this.controlNow);
    if (!Number.isFinite(deadline)) { return; }
    this.controlTimer = setTimeout((): void => {
      this.controlTimer = -1;
      this.scheduleControlTimer();
    }, Math.max(1, deadline - this.controlNow));
  }

  private playback(scope: DesktopTimelineDiscussionTarget, now: number = this.controlNow): DesktopTimelinePlayback {
    const tree = this.view.trees.find((row: DesktopTimelineTree): boolean => row.id === scope.tree);
    return desktopTimelinePlayback(tree, scope, this.controlAnnotations(), now);
  }

  private rememberControl(annotation: Object): void {
    const id = getString(annotation, 'id');
    if (!id || this.view.annotations.some((row: Object): boolean => getString(row, 'id') === id)) { return; }
    const pending = this.acknowledgedControls.filter((row: Object): boolean => getString(row, 'id') !== id);
    this.acknowledgedControls = [...pending.slice(-15), annotation];
    this.scheduleControlTimer();
  }

  private playbackLabel(scope: DesktopTimelineDiscussionTarget, playback: DesktopTimelinePlayback): Resource {
    if (playback.complete) { return $r('app.string.desktop_timeline_done'); }
    if (playback.waiting) {
      return playback.intent === 'pause' ? $r('app.string.desktop_timeline_pause_wait') :
        $r('app.string.desktop_timeline_resume_wait');
    }
    if (playback.retry) {
      return playback.intent === 'pause' ? $r('app.string.desktop_timeline_retry_pause') :
        $r('app.string.desktop_timeline_retry_resume');
    }
    if (playback.intent === 'pause') {
      return scope.kind === 'tree' ? $r('app.string.desktop_timeline_pause_plan') : $r('app.string.desktop_timeline_pause_task');
    }
    return scope.kind === 'tree' ? $r('app.string.desktop_timeline_resume_plan') : $r('app.string.desktop_timeline_resume_task');
  }

  private playbackKey(scope: DesktopTimelineDiscussionTarget): string {
    const state = this.playback(scope);
    const control = getRecord(state.receipt, 'control');
    return desktopTimelineDiscussionKey(scope) + ':' + state.available + ':' + state.complete + ':' + state.intent + ':' +
      state.waiting + ':' + state.retry + ':' + (getString(control, 'delivery') ?? '');
  }

  private async sendControl(scope: DesktopTimelineDiscussionTarget): Promise<void> {
    const host = this.host;
    const state = this.playback(scope, Date.now());
    if (!this.canWrite() || host === undefined || !state.available || state.waiting) { return; }
    const session = this.sessionId;
    const intent = state.intent;
    const key = desktopTimelineDiscussionKey(scope);
    const attemptKey = key + ':' + intent;
    const message = this.resourceText(intent === 'pause' ? $r('app.string.desktop_timeline_pause_request') :
      $r('app.string.desktop_timeline_resume_request'));
    if (this.controlAttempt === undefined || this.controlAttempt.key !== attemptKey || this.controlAttempt.text !== message) {
      this.controlAttempt = { key: attemptKey, id: randomUuid(), text: message };
    }
    const id = this.controlAttempt.id;
    const payload: Record<string, Object> = { 'action': 'control', 'sessionId': session,
      'target': desktopTimelineDiscussionPayload(scope), 'id': id, 'intent': intent, 'text': message };
    this.editBusy = true;
    this.actionScope = key;
    this.actionStatus = '';
    const reply = await host.editTimeline(payload);
    const annotation = getRecord(reply.value, 'annotation');
    const control = getRecord(annotation, 'control');
    const target = getRecord(annotation, 'target');
    const dispatch = getField(reply.value, 'dispatch');
    const valid = reply.ok && getString(reply.value, 'action') === 'control' &&
      annotation !== undefined && !!getString(annotation, 'id') && control !== undefined &&
      getString(target, 'tree') === scope.tree && (dispatch === true || dispatch === false) &&
      (dispatch !== true || (desktopTimelineOwnAnnotation(annotation, id, scope, message) &&
        getString(control, 'action') === intent && getString(control, 'delivery') === 'sending' &&
        getField(control, 'outcome') === null));
    if (!valid || annotation === undefined) {
      if (this.mounted) {
        this.actionStatus = reply.error?.message || this.resourceText($r('app.string.desktop_timeline_control_failed'));
        this.editBusy = false;
        await this.refreshEditedTimeline();
      }
      return;
    }
    this.controlAttempt = undefined;
    if (this.mounted) { this.rememberControl(annotation); }
    let deliveryConfirmed = true;
    let notified = true;
    if (dispatch === true) {
      notified = false;
      if (this.mounted && this.sessionId === session && this.writable) {
        const labels = this.noticeLabels();
        labels.header = this.resourceText($r('app.string.desktop_timeline_control_title'));
        labels.instructions = this.resourceText($r('app.string.desktop_timeline_control_instructions'));
        const text = desktopTimelineDiscussionNotice(scope, id, message, getRecord(reply.value, 'context'), labels, true);
        try { notified = (await this.onNotify(session, text)).length === 0; }
        catch (_) { notified = false; }
      }
      const delivery: Record<string, Object> = { 'action': 'delivery', 'sessionId': session, 'id': id,
        'delivery': notified ? 'accepted' : 'unknown' };
      const receipt = await host.editTimeline(delivery);
      deliveryConfirmed = receipt.ok && getString(receipt.value, 'action') === 'delivery';
    }
    if (!this.mounted) { return; }
    if (!deliveryConfirmed || !notified) {
      this.actionStatus = this.resourceText(!deliveryConfirmed ? $r('app.string.desktop_timeline_control_failed') :
        $r('app.string.desktop_timeline_delivery_unknown'));
    }
    await this.refreshEditedTimeline();
    if (this.mounted) { this.editBusy = false; }
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
    return scope.kind === 'task' ? this.playbackKey(scope) + ':' + (this.task(this.target())?.ownPriority ?? '') :
      desktopTimelineDiscussionKey(scope);
  }

  private canWrite(): boolean {
    return this.mounted && this.active && this.writable && !this.editBusy && !this.exportBusy &&
      this.host !== undefined && !!this.sessionId;
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
  private ControlButton(scope: DesktopTimelineDiscussionTarget, state: DesktopTimelinePlayback) {
    if (this.writable && (scope.kind === 'task' || state.available)) {
      Button(this.playbackLabel(scope, state), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(30).key(scope.kind === 'task' ? 'desktopTimelineTaskControl' : 'desktopTimelineTreeControl')
        .enabled(this.canWrite() && state.available && !state.waiting)
        .onClick((): void => { this.sendControl(scope); })
    }
  }

  @Builder
  private TreeControl(scope: DesktopTimelineDiscussionTarget) {
    ForEach([this.playbackKey(scope)], (_key: string): void => {
      this.ControlButton(scope, this.playback(scope))
    }, (key: string): string => key)
    if (this.actionStatus && this.actionScope === desktopTimelineDiscussionKey(scope)) {
      Text(this.actionStatus).key('desktopTimelineTreeControlStatus').width('100%')
        .fontSize(12).fontColor($r('sys.color.font_secondary'))
    }
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
            this.ControlButton(scope, this.playback(scope))
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
            Text(desktopTimelineStatus(task.status)).fontSize(11).fontColor($r('sys.color.font_secondary'))
            if (task.priority) { Text(task.priority).fontSize(11).fontColor($r('sys.color.brand')) }
            if (task.note) {
              Text(task.note).fontSize(11).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).padding(3).borderRadius(6).key('desktopTimelineTask-' + task.id)
        .accessibilityText(task.title).onClick((): void => { this.pushDetail(tree.id, task.id); })
      Text(desktopTimelinePercent(task.progress, this.progressDecimals) + '%').fontSize(11).fontColor($r('sys.color.font_secondary'))
    }.width('100%').padding({ left: 8 + Math.min(5, task.depth) * 10 })
  }

  private controlReceiptLabel(entry: Object): Resource {
    const control = getRecord(entry, 'control');
    switch (getString(getRecord(control, 'outcome'), 'status')) {
      case 'applied': return $r('app.string.desktop_timeline_control_applied');
      case 'completed': return $r('app.string.desktop_timeline_done');
      case 'unavailable': return $r('app.string.desktop_timeline_control_unavailable');
      case 'superseded': return $r('app.string.desktop_timeline_control_superseded');
      case 'answered': return $r('app.string.desktop_timeline_control_answered');
      default: return getString(control, 'delivery') === 'unknown' ? $r('app.string.desktop_timeline_delivery_unknown') :
        $r('app.string.desktop_timeline_control_waiting');
    }
  }

  @Builder
  private Discussions(kind: string, tree: string, id: string) {
    if (this.targetAnnotations(kind, tree, id).length > 0) {
      Text($r('app.string.desktop_timeline_discussions')).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
      ForEach(this.targetAnnotations(kind, tree, id), (entry: Object): void => {
        Column({ space: 6 }) {
          if (getRecord(entry, 'control') !== undefined) {
            Text(this.controlReceiptLabel(entry)).fontSize(11).fontColor($r('sys.color.font_secondary'))
              .key('desktopTimelineControlReceipt-' + (getString(entry, 'id') ?? ''))
          }
          Text(getString(entry, 'text') ?? '').fontSize(13).copyOption(CopyOptions.LocalDevice)
          if (getString(getRecord(entry, 'reply'), 'text')) {
            Text(getString(getRecord(entry, 'reply'), 'text') ?? '').fontSize(13)
              .fontColor($r('sys.color.font_secondary')).copyOption(CopyOptions.LocalDevice)
          }
        }.width('100%').padding(8).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.workspace_panel'))
      }, (entry: Object): string => (getString(entry, 'id') ?? '') + ':' +
        (getString(getRecord(entry, 'reply'), 'text') ?? '') + ':' +
        (getString(getRecord(entry, 'control'), 'delivery') ?? '') + ':' +
        (getString(getRecord(getRecord(entry, 'control'), 'outcome'), 'status') ?? ''))
    }
  }

  private canImport(): boolean { return this.canWrite() && !this.running; }

  private treeTransferOptions(tree: DesktopTimelineTree): MenuElement[] {
    const items: MenuElement[] = [];
    if (tree.tasks.some((task: DesktopTimelineTask): boolean => task.children > 0)) {
      items.push({ value: this.folded.length > 0 ? $r('app.string.desktop_timeline_expand_branches') :
        $r('app.string.desktop_timeline_collapse_branches'), action: (): void => {
        this.folded = this.folded.length > 0 ? [] : tree.tasks.filter((task: DesktopTimelineTask): boolean =>
          task.children > 0).map((task: DesktopTimelineTask): string => task.id);
      } });
    }
    if (this.writable) {
      items.push({ value: $r('app.string.desktop_timeline_import_tree'), enabled: this.canImport(),
        action: (): void => { this.openTransfer(); } });
    }
    items.push({ value: $r('app.string.desktop_timeline_export_tree'), enabled: !this.exportBusy,
      action: (): void => { this.exportTree(tree.id); } });
    if (this.writable) {
      items.push({ value: $r('app.string.desktop_timeline_remove_tree'), enabled: this.canImport(),
        action: (): void => { this.openTransfer(tree); } });
    }
    return items;
  }

  private async writeBackup(tree: DesktopTimelineTree, notes: Object[], owner: string): Promise<TimelineBackupResult> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return { saved: false, error: this.resourceText($r('app.string.desktop_timeline_transfer_export_failed')) };
    }
    try {
      const content = desktopTimelineCheckpoint(tree.raw, notes, owner, Date.now());
      if (content === undefined || previewDesktopTimelineCheckpoint(content) === undefined) {
        return { saved: false, error: this.resourceText($r('app.string.desktop_timeline_transfer_invalid')) };
      }
      return { saved: await saveDesktopTimelineCheckpoint(context, desktopTimelineCheckpointName(tree.title), content), error: '' };
    } catch (error) {
      return { saved: false, error: this.resourceText(error instanceof Error && error.message === 'limit' ?
        $r('app.string.desktop_timeline_transfer_limit') : $r('app.string.desktop_timeline_transfer_export_failed')) };
    }
  }

  private async exportTree(id: string): Promise<void> {
    const tree = this.view.trees.find((row: DesktopTimelineTree): boolean => row.id === id);
    if (!this.mounted || !this.active || tree === undefined || this.exportBusy) { return; }
    this.exportBusy = true;
    this.transferStatus = '';
    try {
      const result = await this.writeBackup(tree, this.view.annotations, this.sessionId);
      if (this.mounted) {
        this.transferStatus = result.saved ? this.resourceText($r('app.string.desktop_timeline_transfer_exported')) :
          result.error;
      }
    } finally {
      if (this.mounted) { this.exportBusy = false; }
    }
  }

  private async importTree(owner: string, version: number, request: DesktopTimelineImportRequest): Promise<string> {
    const host = this.host;
    if (!this.canImport() || owner !== this.sessionId || version !== this.transferVersion || host === undefined) {
      return this.resourceText($r('app.string.desktop_timeline_transfer_wait_idle'));
    }
    this.editBusy = true;
    this.transferStatus = '';
    const payload: Record<string, Object> = { 'action': 'import', 'sessionId': owner, 'id': request.id,
      'content': request.content, 'copy': request.copy, 'continue': request.proceed };
    try {
      const result = await host.editTimeline(payload);
      const tree = getString(result.value, 'tree');
      if (!this.mounted || !this.active || this.transferVersion !== version || owner !== this.sessionId) { return ''; }
      if (!result.ok || getString(result.value, 'action') !== 'import' || !tree) {
        return result.error?.message || this.resourceText($r('app.string.desktop_timeline_transfer_failed'));
      }
      this.selectTree(tree);
      this.transferStatus = this.resourceText(request.proceed && getField(result.value, 'notified') !== true ?
        $r('app.string.desktop_timeline_transfer_continue_unknown') : $r('app.string.desktop_timeline_transfer_imported'));
      await this.refreshEditedTimeline();
      return '';
    } finally {
      if (this.mounted) { this.editBusy = false; }
    }
  }

  private sameRemovalTarget(target: TimelineRemoveTarget): boolean {
    const tree = this.view.trees.find((row: DesktopTimelineTree): boolean => row.id === target.tree.id);
    return tree !== undefined && getNumber(tree.raw, 'createdAt') === getNumber(target.tree.raw, 'createdAt');
  }

  private async backupRemoval(owner: string, version: number, target: TimelineRemoveTarget): Promise<string> {
    if (!this.mounted || this.sessionId !== owner || version !== this.transferVersion) {
      return this.resourceText($r('app.string.desktop_timeline_remove_disabled'));
    }
    const latest = !this.removeStale && this.sameRemovalTarget(target) ?
      this.view.trees.find((row: DesktopTimelineTree): boolean => row.id === target.tree.id) : undefined;
    const result = await this.writeBackup(latest ?? target.tree,
      latest === undefined ? target.annotations : this.view.annotations, owner);
    return result.error;
  }

  private async removeTree(owner: string, version: number, target: TimelineRemoveTarget): Promise<string> {
    const host = this.host;
    const id = target.tree.id;
    if (!this.canImport() || this.removeStale || owner !== this.sessionId || version !== this.transferVersion ||
      host === undefined || !this.sameRemovalTarget(target)) {
      return this.resourceText($r('app.string.desktop_timeline_remove_disabled'));
    }
    this.editBusy = true;
    this.transferStatus = '';
    try {
      const payload: Record<string, Object> = { 'action': 'remove', 'sessionId': owner, 'tree': id };
      const reply = await host.editTimeline(payload);
      if (!this.mounted || !this.active || this.sessionId !== owner || version !== this.transferVersion) { return ''; }
      const removed = getField(reply.value, 'removed');
      if (!reply.ok || getString(reply.value, 'action') !== 'remove' || typeof removed !== 'boolean') {
        await this.refreshEditedTimeline();
        return reply.error?.message || this.resourceText($r('app.string.desktop_timeline_remove_failed'));
      }
      if (this.selectedTree()?.id === id) { this.selectTree(''); }
      this.taskTrail = this.taskTrail.filter((row: TimelineDetailTarget): boolean => row.tree !== id);
      this.acknowledgedControls = this.acknowledgedControls.filter((row: Object): boolean =>
        getString(getRecord(row, 'target'), 'tree') !== id);
      this.scheduleControlTimer();
      this.transferStatus = this.resourceText(removed && getField(reply.value, 'notified') !== true &&
        getField(reply.value, 'draft') !== true ? $r('app.string.desktop_timeline_remove_notice_unknown') :
        $r('app.string.desktop_timeline_removed'));
      await this.refreshEditedTimeline();
      return '';
    } finally {
      if (this.mounted) { this.editBusy = false; }
    }
  }

  @Builder
  private TransferContent(owner: string, version: number, removal?: TimelineRemoveTarget) {
    if (removal !== undefined) {
      DesktopTimelineRemoveDialog({ title: removal.tree.title, disabled: this.running || this.removeStale,
        onBusy: (busy: boolean): void => { if (this.transferVersion === version) { this.transferBusy = busy; } },
        onExport: (): Promise<string> => this.backupRemoval(owner, version, removal),
        onRemove: (): Promise<string> => this.removeTree(owner, version, removal),
        onClose: (): void => { if (this.transferVersion === version) { this.closeTransfer(); } } })
    } else {
      this.ImportContent(owner, version)
    }
  }

  @Builder
  private ImportContent(owner: string, version: number) {
    DesktopTimelineTransferDialog({ running: this.running, progressDecimals: this.progressDecimals,
      readOnly: (): boolean => !this.canImport() || owner !== this.sessionId || version !== this.transferVersion,
      onBusy: (busy: boolean): void => { if (this.transferVersion === version) { this.transferBusy = busy; } },
      onImport: (request: DesktopTimelineImportRequest): Promise<string> => this.importTree(owner, version, request),
      onClose: (): void => { if (this.transferVersion === version) { this.closeTransfer(); } } })
  }

  private async openTransfer(remove?: DesktopTimelineTree): Promise<void> {
    if (!this.canImport() || this.transferOpening || this.transferDialog >= 0) { return; }
    const owner = this.sessionId;
    const version = ++this.transferVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    this.transferOpening = true;
    this.transferBusy = false;
    const removal: TimelineRemoveTarget | undefined = remove === undefined ? undefined :
      { tree: remove, annotations: this.view.annotations };
    this.removeTarget = removal;
    this.removeStale = removal !== undefined && !this.sameRemovalTarget(removal);
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.TransferContent(owner, version, removal); },
        width: 420, alignment: DialogAlignment.Center, autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        cornerRadius: 22, onWillDismiss: (action): void => { if (!this.transferBusy) { action.dismiss(); } },
        onDidDisappear: (): void => {
          if (version === this.transferVersion) {
            this.transferDialog = -1;
            this.transferBusy = false;
            this.removeTarget = undefined;
            this.transferVersion++;
          }
        }
      });
      if (this.mounted && this.active && this.sessionId === owner && version === this.transferVersion) {
        this.transferDialog = id;
      } else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.mounted && version === this.transferVersion) {
        this.transferStatus = this.resourceText($r('app.string.desktop_timeline_transfer_failed'));
      }
    } finally {
      this.transferOpening = false;
    }
  }

  private closeTransfer(): void {
    if (this.transferDialog < 0 && !this.transferOpening) { return; }
    this.transferVersion++;
    const id = this.transferDialog;
    this.transferDialog = -1;
    this.transferBusy = false;
    this.removeTarget = undefined;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  @Builder
  private Tasks(tree?: DesktopTimelineTree) {
    if (tree === undefined) {
      Text($r('app.string.desktop_timeline_no_tasks')).width('100%').fontSize(13).fontColor($r('sys.color.font_secondary'))
      if (this.writable) {
        Button($r('app.string.desktop_timeline_import_tree'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTimelineTreeImport').enabled(this.canImport()).onClick((): void => { this.openTransfer(); })
      }
    } else {
      Row({ space: 8 }) {
        Button(tree.title, { buttonStyle: ButtonStyleMode.TEXTUAL }).layoutWeight(1).key('desktopTimelineTree')
          .bindMenu(this.treeOptions(), desktopMenuOptions(Placement.BottomLeft))
        Button('···', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(30).height(30).padding(0)
          .key('desktopTimelineTreeMenu').accessibilityText($r('app.string.desktop_timeline_tree_options'))
          .bindMenu(this.treeTransferOptions(tree), desktopMenuOptions(Placement.BottomRight))
        Text(desktopTimelinePercent(tree.progress, this.progressDecimals) + '%').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      DesktopTimelineProgressBar({ progress: tree.progress, status: tree.status,
        parts: this.segmentedProgress ? tree.parts : undefined, decimals: this.progressDecimals })
      if (tree.description) { Text(tree.description).fontSize(13).width('100%') }
      this.TreeControl({ kind: 'tree', tree: tree.id, id: '' })
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
        Text(desktopTimelineStatus(task.status)).fontSize(13).fontColor($r('sys.color.font_secondary'))
        DesktopTimelineProgressBar({ progress: task.progress, status: task.status,
          parts: this.segmentedProgress ? task.parts : undefined, decimals: this.progressDecimals })
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
      if (this.failed || this.linkLost) {
        Row({ space: 6 }) {
          Text($r('app.string.desktop_timeline_link_lost')).fontSize(12).layoutWeight(1)
          Button($r('app.string.desktop_experiment_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineRetry').onClick((): void => { this.onRetry(); this.refreshEditedTimeline(); })
        }.width('100%')
      }
      if (this.view.error) { Text(this.view.error).fontSize(12).fontColor($r('app.color.workspace_status_error')) }
      if (this.transferStatus) {
        Text(this.transferStatus).key('desktopTimelineTransferStatus').width('100%')
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      if (this.rulerVisited) {
        DesktopTimelineRuler({ host: this.host, active: this.active && this.rulerShown(), reports: this.view.reports,
          onOpen: (id: string): void => { this.pushDetail('', id); } })
          .visibility(this.rulerShown() ? Visibility.Visible : Visibility.None).layoutWeight(1)
      }
      if (!this.rulerShown()) {
        Scroll(this.scroll) {
          Column({ space: 9 }) {
            ForEach([this.viewRevision + ':' + this.treeId], (_revision: string): void => {
              if (this.tab === 'tasks') {
                if (this.target() === undefined) { this.Tasks(this.selectedTree()) }
                else { this.TaskDetail(this.task(this.target()), this.target()) }
              } else {
                this.ReportDetail(this.report(this.target()?.id ?? ''))
              }
            }, (revision: string): string => revision)
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
