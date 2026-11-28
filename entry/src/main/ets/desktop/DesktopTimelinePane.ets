import { dialogMaterial } from 'platform';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { StartupFrameCallback } from '../common/DesktopStartup';
import { getArray, getField, getNumber, getRecord, getString, randomUuid } from 'connection';
import type { RpcResult } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopTimelineRuler } from './DesktopTimelineRuler';
import { DesktopTimelineViewport } from './DesktopTimelineViewport';
import type { DesktopTimelineDetailTarget, DesktopTimelineRulerViewport } from './DesktopTimelineViewport';
import { desktopTimelineCheckpoint, desktopTimelineCheckpointName, previewDesktopTimelineCheckpoint } from './DesktopTimelineCheckpoint';
import { saveDesktopTimelineCheckpoint } from './DesktopTimelineTransferIO';
import { DesktopTimelineTransferDialog } from './DesktopTimelineTransferDialog';
import { DesktopTimelineRemoveDialog } from './DesktopTimelineRemoveDialog';
import type { DesktopTimelineImportRequest } from './DesktopTimelineTransferDialog';
import { desktopTimelineControlDeadline, desktopTimelinePlayback } from './DesktopTimelineControl';
import type { DesktopTimelinePlayback } from './DesktopTimelineControl';
import { desktopTimelineDiscussionKey, desktopTimelineDiscussionNotice, desktopTimelineDiscussionPayload,
  desktopTimelineOwnAnnotation, TIMELINE_DISCUSSION_LIMIT } from './DesktopTimelineActions';
import type { DesktopTimelineDiscussionTarget, DesktopTimelineNoticeLabels } from './DesktopTimelineActions';
import { EMPTY_TIMELINE_DISCUSSION } from './DesktopTimelineDiscussionDrafts';
import type { DesktopTimelineDiscussionDraft, DesktopTimelineDiscussionDrafts } from './DesktopTimelineDiscussionDrafts';
import { desktopTimelineStatus, emptyDesktopTimelineBrowse, readDesktopTimeline } from './DesktopTimelineModel';
import { desktopTimelinePercent } from './DesktopTimelinePreferences';
import { DesktopTimelineProgressBar } from './DesktopTimelineProgressBar';
import { DesktopTimelineOverview } from './DesktopTimelineOverview';
import { DesktopTimelineTaskMetrics } from './DesktopTimelineTaskMetrics';
import { DesktopTimelinePriorityControl } from './DesktopTimelinePriorityControl';
import { desktopTimelineDuration, desktopTimelinePeriodLabel, desktopTimelineWeight } from './DesktopTimelineMetricsModel';
import type { DesktopTimelineBrowseState, DesktopTimelineLocation, DesktopTimelineReport, DesktopTimelineSource, DesktopTimelineTask, DesktopTimelineTree,
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

@Component
export struct DesktopTimelinePane {
  host?: DesktopHostActions;
  draftBook?: DesktopTimelineDiscussionDrafts;
  viewportMemory: DesktopTimelineViewport = new DesktopTimelineViewport();
  @Prop sessionId: string = '';
  @Prop @Watch('openingChanged') opening?: DesktopTimelineSource = undefined;
  @Prop @Watch('applyLocation') location?: DesktopTimelineLocation = undefined;
  @Prop @Watch('activeChanged') active: boolean = false;
  @Prop writable: boolean = false;
  @Prop running: boolean = false;
  @Prop @Watch('savedBrowseChanged') savedBrowse: DesktopTimelineBrowseState = emptyDesktopTimelineBrowse();
  onBrowse: (session: string, state: DesktopTimelineBrowseState) => void = (): void => {};
  @Prop progressDecimals: number = 2;
  @Prop segmentedProgress: boolean = true;
  @Prop linkLost: boolean = false;
  onRetry: () => void = (): void => {};
  onTaskRoot: (session: string, tree: string) => void = (): void => {};
  onWeb: () => void = (): void => {};
  onLink: (href: string) => void = (): void => {};
  onNotify: (sessionId: string, text: string) => Promise<string> =
    (_sessionId: string, _text: string): Promise<string> => Promise.resolve('unavailable');

  @State private view: DesktopTimelineView = readDesktopTimeline();
  @State private viewRevision: number = 0;
  @State private tab: string = 'tasks';
  @State private browse: DesktopTimelineBrowseState = emptyDesktopTimelineBrowse();
  @State private rulerVisited: boolean = false;
  @State private taskTrail: DesktopTimelineDetailTarget[] = [];
  @State private reportTrail: DesktopTimelineDetailTarget[] = [];
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
  @State private discussionDraft: DesktopTimelineDiscussionDraft = EMPTY_TIMELINE_DISCUSSION;
  private draftKey: string = '';
  private discussionFocus: number = -1;
  private stopDraftWatch?: () => void;
  @State private controlNow: number = 0;
  @State private historyKey: string = '';
  @State private acknowledgedControls: Object[] = [];
  private controlTimer: number = -1;
  private controlAttempt?: TimelineControlAttempt;
  private actionScope: string = '';
  private readonly scroll = new Scroller();
  private reportById: Map<string, DesktopTimelineReport> = new Map();
  private mounted: boolean = false;
  private generation: number = 0;
  private sequence: number = -2;
  private scrollVersion: number = 0;
  private viewportLease: number = 0;
  private scrollMeasured: boolean = false;
  private pendingScroll?: number;
  private scheduledScroll: number = -1;

  aboutToAppear(): void {
    this.mounted = true;
    const session = this.sessionId;
    this.stopDraftWatch = this.draftBook?.watch(session, (key: string, draft: DesktopTimelineDiscussionDraft): void => {
      if (this.mounted && this.active && this.sessionId === session && key === this.draftKey) {
        this.applyDiscussionDraft(key, draft);
      }
    });
    this.savedBrowseChanged();
    this.restoreViewport();
    this.openingChanged();
    this.activeChanged();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.stopDraftWatch?.();
    this.stopDraftWatch = undefined;
    this.stopDiscussionFocus();
    this.closeTransfer();
    this.stop();
  }

  private activeChanged(): void {
    if (this.mounted && this.active) {
      this.restoreViewport();
      this.applyLocation();
      this.scheduleScrollRestore();
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
    this.scheduleScrollRestore();
    this.publishTaskRoot();
  }

  private applyLocation(): void {
    const location = this.location;
    if (!this.mounted || !this.active || !this.ready || location === undefined ||
        location.session !== this.sessionId || !this.ownsViewport() ||
        location.revision <= this.viewportMemory.locationRevision) { return; }
    if (location.tree && !this.view.trees.some((tree: DesktopTimelineTree): boolean => tree.id === location.tree)) { return; }
    if (location.task && this.task({ tree: location.tree, id: location.task, scroll: 0 }) === undefined) { return; }
    this.viewportMemory.locationRevision = location.revision;
    this.selectTab('tasks');
    if (location.resetReportDetails) { this.reportTrail = []; this.viewportMemory.reportScroll = 0; }
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
      this.saveNavigation();
      this.restoreDiscussion();
      const tree = this.tab === 'tasks' && this.taskTrail.length === 0 ? this.selectedTree()?.id ?? '' : '';
      this.onTaskRoot(this.sessionId, tree);
    }
  }

  private savedBrowseChanged(): void {
    if (this.browse !== this.savedBrowse) { this.browse = this.savedBrowse; }
  }

  private saveBrowse(state: DesktopTimelineBrowseState): void {
    this.browse = state;
    this.onBrowse(this.sessionId, state);
  }

  private selectedTree(): DesktopTimelineTree | undefined {
    return this.view.trees.find((tree: DesktopTimelineTree): boolean => tree.id === (this.browse.tree || this.view.activeTree));
  }

  private treeOptions(): MenuElement[] {
    return this.view.trees.map((tree: DesktopTimelineTree): MenuElement => ({
      value: tree.title, action: (): void => { this.selectTree(tree.id); }
    }));
  }

  private selectTree(id: string): void {
    if (this.browse.tree !== id) {
      this.saveBrowse({ tree: id, folded: this.browse.folded, discussionOpen: this.browse.discussionOpen });
    }
    this.taskTrail = [];
    this.moveScroll(0);
    this.publishTaskRoot();
  }

  private treeIndex(tree?: DesktopTimelineTree): number {
    return this.view.trees.findIndex((row: DesktopTimelineTree): boolean => row.id === tree?.id);
  }

  private selectAdjacent(index: number): void {
    const tree = this.view.trees[index];
    if (tree !== undefined) { this.selectTree(tree.id); }
  }

  private isFolded(id: string): boolean {
    const tree = this.browse.tree || this.view.activeTree;
    return this.browse.folded.get(tree)?.includes(id) ?? false;
  }

  private setFolded(tree: string, tasks: string[]): void {
    const folded = new Map<string, string[]>(this.browse.folded);
    if (tasks.length === 0) { folded.delete(tree); }
    else { folded.set(tree, tasks); }
    this.saveBrowse({ tree: this.browse.tree, folded: folded, discussionOpen: this.browse.discussionOpen });
  }

  private fold(id: string): void {
    const tree = this.browse.tree || this.view.activeTree;
    const tasks = this.browse.folded.get(tree) ?? [];
    this.setFolded(tree, tasks.includes(id) ? tasks.filter((item: string): boolean => item !== id) : [...tasks, id]);
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

  private task(target?: DesktopTimelineDetailTarget): DesktopTimelineTask | undefined {
    return this.view.trees.find((tree: DesktopTimelineTree): boolean => tree.id === target?.tree)?.tasks
      .find((task: DesktopTimelineTask): boolean => task.id === target?.id);
  }

  private trail(): DesktopTimelineDetailTarget[] { return this.tab === 'tasks' ? this.taskTrail : this.reportTrail; }

  private target(): DesktopTimelineDetailTarget | undefined { return this.trail()[this.trail().length - 1]; }

  private ownsViewport(): boolean {
    return this.viewportLease > 0 && this.viewportMemory.lease === this.viewportLease;
  }

  private restoreViewport(): void {
    if (!this.active || this.ownsViewport()) { return; }
    const memory = this.viewportMemory;
    this.viewportLease = ++memory.lease;
    this.tab = memory.tab;
    this.taskTrail = memory.taskTrail;
    this.reportTrail = memory.reportTrail;
    if (this.tab === 'reports') { this.rulerVisited = true; }
    this.moveScroll(this.tab === 'tasks' ? memory.taskScroll : memory.reportScroll);
  }

  private saveNavigation(): void {
    if (!this.ownsViewport()) { return; }
    this.viewportMemory.tab = this.tab;
    this.viewportMemory.taskTrail = this.taskTrail;
    this.viewportMemory.reportTrail = this.reportTrail;
  }

  private detailSceneKey(): string {
    const target = this.target();
    return JSON.stringify([this.viewRevision, this.tab, this.browse.tree, target?.tree ?? '', target?.id ?? '']);
  }

  private recordedScrollOffset(): number {
    if (this.pendingScroll !== undefined) { return this.pendingScroll; }
    try { return this.scroll.currentOffset().yOffset; }
    catch (_) { return this.tab === 'tasks' ? this.viewportMemory.taskScroll : this.viewportMemory.reportScroll; }
  }

  private saveScroll(offset: number): void {
    if (!this.ownsViewport() || this.rulerShown() || !Number.isFinite(offset)) { return; }
    if (this.tab === 'tasks') { this.viewportMemory.taskScroll = Math.max(0, offset); }
    else { this.viewportMemory.reportScroll = Math.max(0, offset); }
  }

  private moveScroll(offset: number): void {
    this.pendingScroll = Math.max(0, offset);
    this.scrollVersion++;
    this.saveScroll(this.pendingScroll);
    this.scheduleScrollRestore();
  }

  private scheduleScrollRestore(): void {
    if (this.pendingScroll === undefined || !this.scrollMeasured || !this.ready || this.rulerShown() ||
        !this.mounted || !this.active || !this.ownsViewport() || this.scheduledScroll === this.scrollVersion) { return; }
    const revision = this.scrollVersion;
    this.scheduledScroll = revision;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      if (this.scheduledScroll === revision) { this.scheduledScroll = -1; }
      const offset = this.pendingScroll;
      if (offset === undefined || revision !== this.scrollVersion || !this.mounted || !this.active ||
          !this.ownsViewport() || !this.scrollMeasured || this.rulerShown()) { return; }
      try {
        this.scroll.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
        this.pendingScroll = undefined;
        this.saveScroll(this.recordedScrollOffset());
      } catch (_) {
        // The next layout of the scroll content can retry if the native scroller is still being attached.
      }
    }));
  }

  private rulerShown(): boolean { return this.tab === 'reports' && this.reportTrail.length === 0; }

  private selectTab(tab: string): void {
    if (tab === this.tab) { return; }
    this.saveScroll(this.recordedScrollOffset());
    if (tab === 'reports') { this.rulerVisited = true; }
    this.tab = tab;
    this.scheduleControlTimer();
    this.moveScroll(tab === 'tasks' ? this.viewportMemory.taskScroll : this.viewportMemory.reportScroll);
    this.publishTaskRoot();
  }

  private pushDetail(tree: string, id: string): void {
    if (this.trail().some((row: DesktopTimelineDetailTarget): boolean => row.id === id && row.tree === tree)) { return; }
    const target: DesktopTimelineDetailTarget = { tree: tree, id: id, scroll: this.rulerShown() ? 0 : this.recordedScrollOffset() };
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
    const notify = this.onNotify;
    const labels = this.noticeLabels();
    labels.header = this.resourceText($r('app.string.desktop_timeline_control_title'));
    labels.instructions = this.resourceText($r('app.string.desktop_timeline_control_instructions'));
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
      const text = desktopTimelineDiscussionNotice(scope, id, message, getRecord(reply.value, 'context'), labels, true);
      try { notified = (await notify(session, text)).length === 0; } catch (_) { notified = false; }
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
    return scope === undefined ? '' : desktopTimelineDiscussionKey(scope);
  }

  private canWrite(): boolean {
    return this.mounted && this.active && this.writable && !this.editBusy && !this.exportBusy &&
      this.host !== undefined && !!this.sessionId;
  }

  private applyDiscussionDraft(key: string, draft: DesktopTimelineDiscussionDraft): void {
    this.draftKey = key;
    if (this.discussionDraft !== draft) { this.discussionDraft = draft; }
  }

  private focusDiscussion(scope: DesktopTimelineDiscussionTarget): void {
    const key = desktopTimelineDiscussionKey(scope);
    this.stopDiscussionFocus();
    this.discussionFocus = setTimeout((): void => {
      this.discussionFocus = -1;
      if (this.canWrite() && key === this.draftKey && this.discussionDraft.open && !this.discussionDraft.busy) {
        try { this.getUIContext().getFocusController().requestFocus('desktopTimelineDiscussionText'); } catch (_) {}
      }
    }, 30);
  }

  private stopDiscussionFocus(): void {
    if (this.discussionFocus >= 0) {
      clearTimeout(this.discussionFocus);
      this.discussionFocus = -1;
    }
  }

  private restoreDiscussion(): void {
    const key = this.actionKey();
    this.applyDiscussionDraft(key, this.draftBook?.read(this.sessionId, key) ?? EMPTY_TIMELINE_DISCUSSION);
  }

  private isDiscussionOpen(scope: DesktopTimelineDiscussionTarget): boolean {
    return this.discussionDraft.open && desktopTimelineDiscussionKey(scope) === this.draftKey;
  }

  private toggleDiscussion(scope: DesktopTimelineDiscussionTarget): void {
    if (!this.canWrite()) { return; }
    const key = desktopTimelineDiscussionKey(scope);
    if (key !== this.draftKey || this.discussionDraft.busy) { return; }
    const draft = this.discussionDraft;
    this.draftBook?.write(this.sessionId, key, {
      open: !draft.open, text: draft.text, id: draft.id, busy: false, notice: draft.notice
    });
  }

  private editDiscussion(scope: DesktopTimelineDiscussionTarget, value: string): void {
    if (!this.canWrite() || !this.isDiscussionOpen(scope) || this.discussionDraft.busy ||
        value === this.discussionDraft.text) { return; }
    this.draftBook?.write(this.sessionId, this.draftKey, { open: true, text: value, id: '', busy: false, notice: '' });
  }

  private cancelDiscussion(scope: DesktopTimelineDiscussionTarget): void {
    if (!this.isDiscussionOpen(scope) || this.discussionDraft.busy) { return; }
    this.draftBook?.write(this.sessionId, this.draftKey, EMPTY_TIMELINE_DISCUSSION);
  }

  private parentPriority(scope: DesktopTimelineDiscussionTarget): string {
    const tree = this.view.trees.find((row: DesktopTimelineTree): boolean => row.id === scope.tree);
    const task = tree?.tasks.find((row: DesktopTimelineTask): boolean => row.id === scope.id);
    return tree?.tasks.find((row: DesktopTimelineTask): boolean => row.id === task?.parent)?.priority ?? '';
  }

  private priorityMenuKey(scope: DesktopTimelineDiscussionTarget): string {
    const task = this.task(this.target());
    return (task?.ownPriority ?? '') + ':' + (task?.priority ?? '') + ':' + this.parentPriority(scope);
  }

  private async refreshEditedTimeline(): Promise<void> {
    const host = this.host;
    if (host !== undefined && this.active && this.mounted) {
      await this.readBaseline(host, { 'sessionId': this.sessionId }, this.generation);
    }
  }

  private async setPriority(scope: DesktopTimelineDiscussionTarget, priority: string | null): Promise<void> {
    const host = this.host;
    const task = this.task(this.target());
    if (!this.canWrite() || host === undefined || this.actionKey() !== desktopTimelineDiscussionKey(scope) ||
      scope.kind !== 'task' || task === undefined ||
      task.ownPriority === (priority ?? '')) { return; }
    this.editBusy = true;
    this.actionStatus = '';
    this.actionScope = desktopTimelineDiscussionKey(scope);
    const payload: Record<string, Object | null> = {
      'action': 'priority', 'sessionId': this.sessionId, 'tree': scope.tree, 'task': scope.id, 'priority': priority
    };
    const reply = await host.editTimeline(payload);
    if (!this.mounted) { return; }
    if (!reply.ok || getString(reply.value, 'action') !== 'priority') {
      this.actionStatus = this.resourceText($r('app.string.desktop_timeline_priority_unconfirmed'));
    }
    await this.refreshEditedTimeline();
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
    const drafts = this.draftBook;
    const draft = this.discussionDraft;
    const message = draft.text.trim();
    if (!this.canWrite() || host === undefined || drafts === undefined || !this.isDiscussionOpen(scope) ||
      draft.busy || !message || message.length > TIMELINE_DISCUSSION_LIMIT) { return; }
    const session = this.sessionId;
    const key = desktopTimelineDiscussionKey(scope);
    const id = draft.id || randomUuid();
    const labels = this.noticeLabels();
    const notify = this.onNotify;
    const failed = this.resourceText($r('app.string.desktop_timeline_edit_failed'));
    const saved = this.resourceText($r('app.string.desktop_timeline_discussion_saved'));
    const unconfirmed = this.resourceText($r('app.string.desktop_timeline_discussion_notify_unknown'));
    const payload: Record<string, Object> = {
      'action': 'annotate', 'sessionId': session, 'id': id,
      'target': desktopTimelineDiscussionPayload(scope), 'text': message
    };
    drafts.write(session, key, { open: true, text: draft.text, id: id, busy: true, notice: '' });
    let result: RpcResult | undefined;
    try { result = await host.editTimeline(payload); } catch (_) {}
    const annotation = getRecord(result?.value, 'annotation');
    const pendingReply = getField(annotation, 'reply') === null;
    if (!result?.ok || getString(result.value, 'action') !== 'annotate' ||
      !desktopTimelineOwnAnnotation(annotation, id, scope, message) ||
      (!pendingReply && getRecord(annotation, 'reply') === undefined)) {
      drafts.write(session, key, { open: true, text: draft.text, id: id, busy: false,
        notice: result?.error?.message || failed });
      return;
    }
    let notified = true;
    if (pendingReply) {
      const text = desktopTimelineDiscussionNotice(scope, id, message, getRecord(result.value, 'context'), labels);
      try { notified = (await notify(session, text)).length === 0; } catch (_) { notified = false; }
    }
    drafts.write(session, key, { open: false, text: '', id: '', busy: false, notice: notified ? saved : unconfirmed });
    if (this.mounted && this.sessionId === session) { await this.refreshEditedTimeline(); }
  }

  private playbackHint(state: DesktopTimelinePlayback): Resource {
    if (this.editBusy) { return $r('app.string.desktop_timeline_control_sending'); }
    if (state.waiting) {
      return getString(getRecord(state.receipt, 'control'), 'delivery') === 'unknown' ?
        $r('app.string.desktop_timeline_delivery_unknown') : $r('app.string.desktop_timeline_control_waiting_hint');
    }
    if (state.retry) { return $r('app.string.desktop_timeline_control_unconfirmed_hint'); }
    return $r('app.string.desktop_timeline_control_hint');
  }

  private playbackIcon(state: DesktopTimelinePlayback): Resource {
    if (state.complete) { return $r('app.media.dsh_dock_check'); }
    return state.intent === 'pause' ? $r('app.media.dsh_dock_pause') : $r('app.media.dsh_dock_play');
  }

  @Builder
  private ControlButton(scope: DesktopTimelineDiscussionTarget, state: DesktopTimelinePlayback) {
    if (this.writable && (scope.kind === 'task' || state.available)) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 5 }) {
          Image(this.playbackIcon(state)).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
          Text(this.playbackLabel(scope, state)).fontSize(12)
        }
      }.height(30).key(scope.kind === 'task' ? 'desktopTimelineTaskControl' : 'desktopTimelineTreeControl')
        .enabled(this.canWrite() && state.available && !state.waiting)
        .accessibilityText(this.playbackLabel(scope, state)).accessibilityDescription(this.playbackHint(state))
        .bindTips(this.playbackHint(state), { appearingTime: 480, enableArrow: false,
          systemMaterial: desktopMenuOptions(Placement.Top).systemMaterial })
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
          Text($r('app.string.desktop_timeline_discussion_add')).width('100%').fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
          TextArea({ text: this.discussionDraft.text, placeholder: $r('app.string.desktop_timeline_discussion_placeholder') })
            .key('desktopTimelineDiscussionText').height(94).width('100%').fontSize(13)
            .maxLength(TIMELINE_DISCUSSION_LIMIT).enabled(this.canWrite() && !this.discussionDraft.busy)
            .onAppear((): void => { this.focusDiscussion(scope); })
            .onChange((value: string): void => { this.editDiscussion(scope, value); })
          Row({ space: 6 }) {
            Text($r('app.string.desktop_timeline_count', this.discussionDraft.text.length, TIMELINE_DISCUSSION_LIMIT))
              .fontSize(10).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            Button($r('app.string.desktop_timeline_discussion_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopTimelineDiscussionCancel').height(30).enabled(!this.discussionDraft.busy)
              .onClick((): void => { this.cancelDiscussion(scope); })
            Button($r('app.string.desktop_timeline_save'), { buttonStyle: ButtonStyleMode.NORMAL })
              .key('desktopTimelineDiscussionSave').height(30)
              .enabled(this.canWrite() && !this.discussionDraft.busy && this.discussionDraft.text.trim().length > 0)
              .onClick((): void => { this.saveDiscussion(scope); })
          }.width('100%')
        }
        Row({ space: 6 }) {
          if (scope.kind === 'task') {
            ForEach([this.priorityMenuKey(scope)], (_key: string): void => {
              DesktopTimelinePriorityControl({ current: this.task(this.target())?.priority ?? '',
                own: this.task(this.target())?.ownPriority ?? '', inherited: this.parentPriority(scope),
                allowed: this.canWrite(),
                onSelect: (priority: string | null): void => { this.setPriority(scope, priority); } })
            }, (key: string): string => key)
            ForEach([this.playbackKey(scope)], (_key: string): void => {
              this.ControlButton(scope, this.playback(scope))
            }, (key: string): string => key)
          }
          Button($r('app.string.desktop_timeline_discussion_add'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineDiscuss').height(30).enabled(this.canWrite() && !this.discussionDraft.busy)
            .accessibilitySelected(this.isDiscussionOpen(scope)).onClick((): void => { this.toggleDiscussion(scope); })
          if (this.editBusy || this.discussionDraft.busy) { LoadingProgress().width(16).height(16) }
        }.width('100%')
        if (this.discussionDraft.notice) {
          Text(this.discussionDraft.notice).key('desktopTimelineDiscussionStatus').width('100%')
            .fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        if (this.actionStatus && this.actionScope === desktopTimelineDiscussionKey(scope)) {
          Text(this.actionStatus).key('desktopTimelineEditStatus').width('100%')
            .fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
      }.width('100%').padding({ top: 6 }).alignItems(HorizontalAlign.Start)
        .borderWidth({ top: 0.5 }).borderColor($r('sys.color.comp_divider'))
    }
  }

  private time(value: number): string { return new Date(value).toLocaleString(); }

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
      Row() {
        DesktopTimelineProgressBar({ progress: task.progress, status: task.status, label: task.title, thickness: 4,
          parts: this.segmentedProgress ? task.parts : undefined, decimals: this.progressDecimals,
          progressKey: 'desktopTimelineTaskProgress-' + task.id })
      }.width(40)
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

  private annotationKey(entry: Object): string {
    const control = getRecord(entry, 'control');
    const reply = getRecord(entry, 'reply');
    return (getString(entry, 'id') ?? '') + ':' + (getString(reply, 'text') ?? '') + ':' +
      (getString(control, 'delivery') ?? '') + ':' + (getString(getRecord(control, 'outcome'), 'status') ?? '');
  }

  private discussionHistory(): Object[] {
    return this.controlAnnotations().slice().reverse().sort((left: Object, right: Object): number =>
      (getNumber(right, 'createdAt') ?? 0) - (getNumber(left, 'createdAt') ?? 0));
  }

  private annotationTargetLabel(entry: Object): ResourceStr {
    const target = getRecord(entry, 'target');
    const kind = getString(target, 'kind');
    if (kind === 'report') {
      const report = this.report(getString(target, 'report') ?? '');
      if (report !== undefined) {
        return $r('app.string.desktop_timeline_discussion_report', report.level + 1,
          desktopTimelinePeriodLabel(report.savedPeriod ?? report.end - report.start),
          this.time(report.start), this.time(report.end));
      }
      return $r('app.string.desktop_timeline_missing_detail');
    }
    const tree = this.view.trees.find((row: DesktopTimelineTree): boolean => row.id === getString(target, 'tree'));
    const missing = this.resourceText($r('app.string.desktop_timeline_missing_detail'));
    if (kind === 'tree') { return $r('app.string.desktop_timeline_discussion_tree', tree?.title ?? missing); }
    const task = getArray(tree?.raw, 'tasks')?.find((row: Object): boolean => getString(row, 'id') === getString(target, 'task'));
    return $r('app.string.desktop_timeline_discussion_task', tree?.title ?? '', getString(task, 'title') ?? missing);
  }

  private annotationStatus(entry: Object): Resource {
    if (getRecord(entry, 'control') !== undefined) { return this.controlReceiptLabel(entry); }
    return getRecord(entry, 'reply') === undefined ? $r('app.string.desktop_timeline_discussion_waiting') :
      $r('app.string.desktop_timeline_discussion_replied');
  }

  @Builder
  private Annotation(entry: Object, withTarget: boolean) {
    Column({ space: 6 }) {
      if (withTarget) {
        Text(this.annotationTargetLabel(entry)).width('100%').fontSize(12).fontWeight(FontWeight.Medium)
          .key('desktopTimelineDiscussionTarget-' + (getString(entry, 'id') ?? ''))
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        Text(getRecord(entry, 'control') === undefined ? $r('app.string.desktop_timeline_discussion_user') :
          $r('app.string.desktop_timeline_discussion_request')).fontSize(12).fontWeight(FontWeight.Medium)
          .margin({ right: 6 })
        if (getNumber(entry, 'createdAt') !== undefined) {
          Text(this.time(getNumber(entry, 'createdAt') ?? 0)).fontSize(11).fontColor($r('sys.color.font_secondary'))
            .margin({ right: 6 })
        }
        Text(this.annotationStatus(entry)).fontSize(11).fontColor($r('sys.color.font_secondary'))
          .key((getRecord(entry, 'control') === undefined ? 'desktopTimelineDiscussionStatus-' :
            'desktopTimelineControlReceipt-') + (getString(entry, 'id') ?? ''))
      }.width('100%')
      if (getString(entry, 'text')) { MarkdownRenderer({ text: getString(entry, 'text') ?? '', onLink: this.onLink }) }
      if (getRecord(entry, 'reply') !== undefined) {
        Column({ space: 5 }) {
          Row({ space: 8 }) {
            Text($r('app.string.desktop_timeline_discussion_agent')).fontSize(12).fontWeight(FontWeight.Medium)
            if (getNumber(getRecord(entry, 'reply'), 'createdAt') !== undefined) {
              Text(this.time(getNumber(getRecord(entry, 'reply'), 'createdAt') ?? 0)).fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
            }
          }.width('100%')
          MarkdownRenderer({ text: getString(getRecord(entry, 'reply'), 'text') ?? '', onLink: this.onLink })
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 8, top: 4, bottom: 4 })
          .border({ width: { left: 2 }, color: $r('app.color.workspace_timeline_done') })
      }
    }.key('desktopTimelineDiscussionRow-' + (getString(entry, 'id') ?? ''))
      .width('100%').padding(9).alignItems(HorizontalAlign.Start).borderRadius(8)
      .border({ width: 0.5, color: $r('app.color.workspace_border') })
  }

  @Builder
  private DiscussionRows(entries: Object[], withTarget: boolean) {
    Column({ space: 8 }) {
      ForEach(entries, (entry: Object): void => { this.Annotation(entry, withTarget) },
        (entry: Object): string => this.annotationKey(entry))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Discussions(kind: string, tree: string, id: string) {
    Column({ space: 7 }) {
      Text($r('app.string.desktop_timeline_discussion_count', this.targetAnnotations(kind, tree, id).length))
        .width('100%').fontSize(14).fontWeight(FontWeight.Medium)
      if (this.targetAnnotations(kind, tree, id).length > 0) {
        this.DiscussionRows(this.targetAnnotations(kind, tree, id), false)
      } else {
        Text($r('app.string.desktop_timeline_discussion_empty')).width('100%').fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SessionDiscussions(reportRoot: boolean) {
    if (this.controlAnnotations().length > 0) {
      Column({ space: 8 }) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 7 }) {
            Image($r('app.media.dsh_browser_chevron_right_outline')).width(12).height(12).supportSvg2(true)
              .rotate({ angle: this.browse.discussionOpen ? 90 : 0 }).accessibilityLevel('no')
            Text($r('app.string.desktop_timeline_discussion_history', this.controlAnnotations().length)).fontSize(13)
          }
        }.key('desktopTimelineDiscussionHistoryToggle').height(34).borderRadius(7)
          .onClick((): void => { this.saveBrowse({ tree: this.browse.tree, folded: this.browse.folded,
            discussionOpen: !this.browse.discussionOpen }); })
        if (this.browse.discussionOpen) {
          if (reportRoot) {
            Scroll() {
              this.DiscussionRows(this.discussionHistory(), true)
            }.width('100%').height(185).key('desktopTimelineDiscussionHistory')
          } else {
            Column() {
              this.DiscussionRows(this.discussionHistory(), true)
            }.width('100%').key('desktopTimelineDiscussionHistory')
          }
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 6 })
        .border({ width: { top: 0.5 }, color: $r('app.color.workspace_border') })
    }
  }

  private canImport(): boolean { return this.canWrite() && !this.running; }

  private treeTransferOptions(tree: DesktopTimelineTree): MenuElement[] {
    const items: MenuElement[] = [];
    if (tree.tasks.some((task: DesktopTimelineTask): boolean => task.children > 0)) {
      items.push({ value: $r('app.string.desktop_timeline_expand_branches'),
        action: (): void => { this.setFolded(tree.id, []); } });
      items.push({ value: $r('app.string.desktop_timeline_collapse_branches'), action: (): void => {
        this.setFolded(tree.id, tree.tasks.filter((task: DesktopTimelineTask): boolean => task.children > 0)
          .map((task: DesktopTimelineTask): string => task.id));
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
      if (this.browse.folded.has(id)) { this.setFolded(id, []); }
      this.taskTrail = this.taskTrail.filter((row: DesktopTimelineDetailTarget): boolean => row.tree !== id);
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
  private TreeArrow(previous: boolean, index: number) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(previous ? $r('app.media.dsh_browser_chevron_left_outline') : $r('app.media.dsh_browser_chevron_right_outline'))
        .width(18).height(18).supportSvg2(true).accessibilityLevel('no')
    }.width(30).height(30).padding(0).key(previous ? 'desktopTimelineTreePrevious' : 'desktopTimelineTreeNext')
      .enabled(index >= 0 && index < this.view.trees.length)
      .accessibilityText(previous ? $r('app.string.desktop_timeline_previous_tree') :
        $r('app.string.desktop_timeline_next_tree'))
      .onClick((): void => { this.selectAdjacent(index); })
  }

  @Builder
  private TreeNavigation(tree?: DesktopTimelineTree) {
    if (this.view.trees.length > 0 && (tree !== undefined || !this.browse.tree)) {
      Row({ space: 4 }) {
        if (this.view.trees.length > 1 || tree === undefined) { this.TreeArrow(true, this.treeIndex(tree) - 1) }
        Column({ space: 2 }) {
          if (tree !== undefined) {
            Button(tree.title, { buttonStyle: ButtonStyleMode.TEXTUAL }).width('100%').key('desktopTimelineTree')
              .bindMenu(this.treeOptions(), desktopMenuOptions(Placement.BottomLeft))
          } else {
            Button($r('app.string.desktop_timeline_choose_tree'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .width('100%').key('desktopTimelineTree').bindMenu(this.treeOptions(), desktopMenuOptions(Placement.BottomLeft))
          }
          if (this.view.trees.length > 1 || tree === undefined) {
            Text((this.treeIndex(tree) + 1) + ' / ' + this.view.trees.length)
              .key('desktopTimelineTreePosition').fontSize(11).fontColor($r('sys.color.font_secondary'))
          }
        }.layoutWeight(1)
        if (this.view.trees.length > 1 || tree === undefined) { this.TreeArrow(false, this.treeIndex(tree) + 1) }
        if (tree !== undefined) {
          Button('···', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(30).height(30).padding(0)
            .key('desktopTimelineTreeMenu').accessibilityText($r('app.string.desktop_timeline_tree_options'))
            .bindMenu(this.treeTransferOptions(tree), desktopMenuOptions(Placement.BottomRight))
        }
      }.width('100%')
    }
  }

  @Builder
  private Tasks(tree?: DesktopTimelineTree) {
    this.TreeNavigation(tree)
    if (tree === undefined) {
      if (this.browse.tree) {
        Text($r('app.string.desktop_timeline_tree_unavailable')).width('100%').fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
        if (this.view.activeTree) {
          Button($r('app.string.desktop_timeline_open_active_tree'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick((): void => { this.selectTree(''); })
        }
      } else {
        Text($r('app.string.desktop_timeline_no_tasks')).width('100%').fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
        if (this.writable) {
          Button($r('app.string.desktop_timeline_import_tree'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineTreeImport').enabled(this.canImport()).onClick((): void => { this.openTransfer(); })
        }
      }
    } else {
      DesktopTimelineOverview({ tree: tree, active: this.active, running: this.running,
        decimals: this.progressDecimals, segmented: this.segmentedProgress })
      if (tree.description) { Text(tree.description).fontSize(13).width('100%') }
      this.TreeControl({ kind: 'tree', tree: tree.id, id: '' })
      ForEach(this.visibleTasks(tree), (task: DesktopTimelineTask): void => { this.TaskRow(tree, task) },
        (task: DesktopTimelineTask): string => tree.id + ':' + task.id + ':' + task.status + ':' + task.progress + ':' +
          task.title + ':' + task.note + ':' + task.priority + ':' + task.depth + ':' + task.children)
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

  private revisionProgress(row: Object): string {
    const progress = desktopTimelinePercent(getNumber(row, 'progress') ?? 0, this.progressDecimals);
    const previous = getNumber(row, 'previousProgress');
    const before = previous === undefined ? progress : desktopTimelinePercent(previous, this.progressDecimals);
    return before === progress ? progress + '%' : before + '% → ' + progress + '%';
  }

  @Builder
  private TaskHistory(task: DesktopTimelineTask, key: string) {
    Column({ space: 8 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 7 }) {
          Image($r('app.media.dsh_browser_chevron_right_outline')).width(12).height(12).supportSvg2(true)
            .rotate({ angle: this.historyKey === key ? 90 : 0 }).accessibilityLevel('no')
          Text($r('app.string.desktop_timeline_task_history')).fontSize(13)
          Text(String(task.history.length)).fontSize(11).fontColor($r('sys.color.font_secondary'))
        }
      }.key('desktopTimelineTaskHistoryToggle').borderRadius(6).height(34)
      .onClick((): void => { this.historyKey = this.historyKey === key ? '' : key; })
      if (this.historyKey === key) {
        if (task.history.length === 0) {
          Text($r('app.string.desktop_timeline_metric_history_empty')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        ForEach(task.history.slice().reverse(), (row: Object, index: number): void => {
          this.HistoryRevision(task.title, row, index)
        }, (row: Object, index: number): string => String(getNumber(row, 'at') ?? 0) + ':' + index)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 9 })
      .border({ width: { top: 0.5 }, color: $r('app.color.workspace_border') })
  }

  @Builder
  private HistoryRevision(currentTitle: string, row: Object, index: number) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(this.time(getNumber(row, 'at') ?? 0)).fontSize(11).fontColor($r('sys.color.font_secondary'))
        Text(desktopTimelineStatus(getString(row, 'status') ?? 'pending')).fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      if (getString(row, 'title') && getString(row, 'title') !== currentTitle) {
        Text(getString(row, 'title') ?? '').fontSize(13).width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        this.RevisionMetric($r('app.string.desktop_timeline_metric_progress'), this.revisionProgress(row),
          'desktopTimelineTaskHistoryProgress-' + index)
        this.RevisionMetric($r('app.string.desktop_timeline_metric_weight'), desktopTimelineWeight(getNumber(row, 'weight') ?? 1),
          'desktopTimelineTaskHistoryWeight-' + index)
      }.width('100%')
      if (getString(row, 'description')) { MarkdownRenderer({ text: getString(row, 'description') ?? '', onLink: this.onLink }) }
      if (getString(row, 'note')) { MarkdownRenderer({ text: getString(row, 'note') ?? '', onLink: this.onLink }) }
      if (getString(row, 'details')) { MarkdownRenderer({ text: getString(row, 'details') ?? '', onLink: this.onLink }) }
    }.width('100%').padding(9).alignItems(HorizontalAlign.Start).borderRadius(8)
      .border({ width: 0.5, color: $r('app.color.workspace_border') })
  }

  @Builder
  private RevisionMetric(label: Resource, value: string, id: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(11).fontColor($r('sys.color.font_secondary'))
      Text(value).fontSize(14).fontWeight(FontWeight.Medium).key(id)
    }.padding(8).margin({ right: 6, bottom: 6 }).constraintSize({ minWidth: 92 }).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.workspace_panel')).borderRadius(8)
  }

  @Builder
  private TaskDetail(task?: DesktopTimelineTask, target?: DesktopTimelineDetailTarget) {
    Column({ space: 9 }) {
      if (task !== undefined && target !== undefined) {
        Row({ space: 8 }) {
          Text(task.title).layoutWeight(1).fontSize(18).fontWeight(FontWeight.Medium)
          Text(desktopTimelineStatus(task.status)).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }.width('100%')
        Text(this.view.trees.find((row: DesktopTimelineTree): boolean => row.id === target.tree)?.title ?? '')
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
        if (task.description) { MarkdownRenderer({ text: task.description, onLink: this.onLink }) }
        if (task.note) { MarkdownRenderer({ text: task.note, onLink: this.onLink }) }
        DesktopTimelineTaskMetrics({ task: task, decimals: this.progressDecimals })
        if (task.details) { MarkdownRenderer({ text: task.details, onLink: this.onLink }) }
        this.Discussions('task', target.tree, target.id)
        this.TaskHistory(task, target.tree + ':' + target.id)
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
          Text($r('app.string.desktop_timeline_saved_period', desktopTimelineDuration(report.savedPeriod))).fontSize(12)
        }
        if (report.workMs !== undefined && report.workMs !== report.savedPeriod) {
          Text($r('app.string.desktop_timeline_work_duration', desktopTimelineDuration(report.workMs))).fontSize(12)
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
          savedViewport: this.viewportMemory.ruler,
          onViewport: (value: DesktopTimelineRulerViewport): void => {
            if (this.active && this.ownsViewport()) { this.viewportMemory.ruler = value; }
          },
          onOpen: (id: string): void => { this.pushDetail('', id); } })
          .visibility(this.rulerShown() ? Visibility.Visible : Visibility.None).layoutWeight(1)
      }
      if (this.rulerShown()) { this.SessionDiscussions(true) }
      if (!this.rulerShown()) {
        Scroll(this.scroll) {
          Column({ space: 9 }) {
            ForEach([this.detailSceneKey()], (_revision: string): void => {
              if (this.tab === 'tasks') {
                if (this.target() === undefined) {
                  this.Tasks(this.selectedTree())
                  this.SessionDiscussions(false)
                }
                else { this.TaskDetail(this.task(this.target()), this.target()) }
              } else {
                this.ReportDetail(this.report(this.target()?.id ?? ''))
              }
            }, (revision: string): string => revision)
          }.width('100%').alignItems(HorizontalAlign.Start)
            .onAreaChange((_old: Area, area: Area): void => {
              this.scrollMeasured = Number(area.height) > 0;
              this.scheduleScrollRestore();
            })
        }.key('desktopTimelineDetailViewport').layoutWeight(1).width('100%').align(Alignment.TopStart)
          .onDidScroll((_offset: number, _state: ScrollState): void => {
            if (this.active && this.scrollMeasured && this.pendingScroll === undefined) {
              this.saveScroll(this.recordedScrollOffset());
            }
          })
          .onDisAppear((): void => { this.scrollMeasured = false; })
      }
      if (this.writable && this.actionKey()) {
        ForEach([this.actionKey()], (_key: string): void => { this.EditFooter(this.writeScope()) },
          (key: string): string => key)
      }
    }.key('desktopTimelinePane').width('100%').height('100%').padding(10).alignItems(HorizontalAlign.Start)
  }
}
