import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import {
  CLOUD_ACTION_DISABLE, CLOUD_ACTION_ENABLE, CLOUD_ACTION_LOGIN, CLOUD_ACTION_PULL, CLOUD_ACTION_RESTORE,
  CLOUD_ACTION_SIGNOUT, CLOUD_ACTION_UPLOAD, KindStat, TaskProgress, decideCloudAction, dialogMaterial, initialProgress,
  progressRatio
} from 'platform';
import { DesktopCloudSyncActivity, DesktopCloudSyncOverview, DesktopCloudSyncPort, DesktopCloudPlugin,
  createDesktopCloudSyncPort } from './DesktopCloudSyncPort';
import { DesktopCloudSyncRestore } from './DesktopCloudSyncRestore';

function bytesText(bytes: number): string {
  if (bytes < 1024) { return bytes.toString() + ' B'; }
  if (bytes < 1048576) { return (bytes / 1024).toFixed(1) + ' KB'; }
  if (bytes < 1073741824) { return (bytes / 1048576).toFixed(1) + ' MB'; }
  return (bytes / 1073741824).toFixed(2) + ' GB';
}

function taskTitle(task: string): Resource {
  switch (task) {
    case 'upload': return $r('app.string.desktop_cloud_progress_upload');
    case 'pull': return $r('app.string.desktop_cloud_progress_pull');
    case 'import': return $r('app.string.desktop_cloud_progress_import');
    case 'plugins': return $r('app.string.desktop_cloud_progress_plugins');
    default: return $r('app.string.desktop_cloud_progress');
  }
}

function stageTitle(stage: string): ResourceStr {
  switch (stage) {
    case 'scan': return $r('app.string.desktop_cloud_stage_scan');
    case 'stage_file': return $r('app.string.desktop_cloud_stage_file');
    case 'write_db': return $r('app.string.desktop_cloud_stage_db');
    case 'cloud_sync': return $r('app.string.desktop_cloud_stage_sync');
    case 'verify': return $r('app.string.desktop_cloud_stage_verify');
    case 'discover': return $r('app.string.desktop_cloud_stage_discover');
    case 'fetch_meta': return $r('app.string.desktop_cloud_stage_meta');
    case 'fetch_asset': return $r('app.string.desktop_cloud_stage_asset');
    case 'ready': return $r('app.string.desktop_cloud_stage_ready');
    case 'map_workspace': return $r('app.string.desktop_cloud_stage_map');
    case 'stage': return $r('app.string.desktop_cloud_stage_staging');
    case 'commit': return $r('app.string.desktop_cloud_stage_commit');
    case 'verify_usable': return $r('app.string.desktop_cloud_stage_usable');
    case 'done': return $r('app.string.desktop_cloud_stage_done');
    default: return stage;
  }
}

@Component
export struct DesktopCloudSyncSettings {
  @StorageProp('dshDesktopVoiceForeground') @Watch('syncPolling') private foreground: boolean = true;
  @State private view?: DesktopCloudSyncOverview = undefined;
  @State private progress: TaskProgress = initialProgress('upload');
  @State private busy: boolean = false;
  @State private loginBusy: boolean = false;
  @State private running: boolean = false;
  @State private notice: ResourceStr = '';
  @State private noticeError: boolean = false;
  private port?: DesktopCloudSyncPort;
  private alive: boolean = false;
  private visible: boolean = false;
  private statsInFlight: boolean = false;
  private loginPrompt: boolean = false;
  private timer: number = -1;
  private observedGeneration: number = -1;
  private restoreDialogId: number = -1;
  private restoreOpening: boolean = false;
  private viewWidth: number = 400;

  aboutToAppear(): void {
    this.alive = true;
    const context = this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
    this.port = context === undefined ? undefined : createDesktopCloudSyncPort(context);
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.syncPolling();
    this.closeRestore();
  }

  private load(): void {
    const port = this.port;
    if (!this.alive || port === undefined) { return; }
    this.observedGeneration = port.generation();
    this.view = port.overview();
    this.updateActivity(port.activity());
    this.syncPolling();
    if (!this.view.signedIn || this.statsInFlight) { return; }
    this.statsInFlight = true;
    const generation = port.generation();
    port.refreshStats().then((): void => {
      if (this.alive && port.generation() === generation) { this.view = port.overview(); }
    }).catch((): void => {}).finally((): void => {
      this.statsInFlight = false;
    });
  }

  private updateActivity(activity: DesktopCloudSyncActivity): void {
    this.running = activity.running;
    if (activity.running) {
      const p = activity.progress;
      // Some engine phases update the same object in place. The view owns a snapshot.
      this.progress = {
        task: p.task, stage: p.stage, total: p.total, succeeded: p.succeeded, failed: p.failed, skipped: p.skipped,
        currentUnitId: p.currentUnitId, note: p.note, preparedBytes: p.preparedBytes, finished: p.finished
      };
    }
  }

  private syncPolling(): void {
    if (!this.alive || !this.visible || !this.foreground || this.port === undefined) {
      if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
      return;
    }
    if (this.timer >= 0) { return; }
    this.timer = setInterval((): void => { this.tick(); }, 1500);
    this.tick();
  }

  private tick(): void {
    const port = this.port;
    if (port === undefined) { return; }
    if (port.generation() !== this.observedGeneration) { this.load(); return; }
    if (this.view?.signedIn !== true) { return; }
    const activity = port.activity();
    const finished = this.running && !activity.running;
    this.updateActivity(activity);
    if (finished) { this.load(); }
  }

  private showNotice(value: ResourceStr, error: boolean = false): void {
    if (!this.alive) { return; }
    this.notice = value;
    this.noticeError = error;
  }

  private allows(action: string, port: DesktopCloudSyncPort): boolean {
    const state = port.overview();
    const decision = decideCloudAction(action, {
      signedIn: state.signedIn, enabled: state.enabled, running: port.activity().running
    });
    if (!decision.ok) { this.showNotice(decision.message, true); }
    return decision.ok;
  }

  private confirmLogin(): void {
    if (!this.alive || this.loginBusy || this.loginPrompt || this.port === undefined ||
      !this.allows(CLOUD_ACTION_LOGIN, this.port)) { return; }
    this.loginPrompt = true;
    try {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.desktop_cloud_login'),
        message: $r('app.string.desktop_cloud_login_confirm'),
        autoCancel: true, systemMaterial: dialogMaterial(),
        primaryButton: { value: $r('app.string.desktop_cloud_cancel'), action: (): void => {} },
        secondaryButton: {
          value: $r('app.string.desktop_cloud_login_submit'),
          action: (): void => { this.signIn(); }
        },
        onDidDisappear: (): void => { this.loginPrompt = false; }
      });
    } catch (_) {
      this.loginPrompt = false;
      this.showNotice($r('app.string.desktop_cloud_open_failed'), true);
    }
  }

  private async signIn(): Promise<void> {
    const port = this.port;
    if (!this.alive || this.loginBusy || port === undefined) { return; }
    this.loginBusy = true;
    this.notice = '';
    try {
      const result = await port.signIn((): void => {
        if (this.alive) { this.view = port.overview(); }
      });
      if (result.kind === 'success') { this.showNotice($r('app.string.desktop_cloud_login_done')); }
      if (result.kind === 'error') { this.showNotice(result.reason || $r('app.string.desktop_cloud_login_failed'), true); }
    } catch (_) {
      this.showNotice($r('app.string.desktop_cloud_login_failed'), true);
    } finally {
      if (this.alive) { this.loginBusy = false; this.load(); }
    }
  }

  private signOut(): void {
    const port = this.port;
    if (!this.alive || port === undefined || !this.allows(CLOUD_ACTION_SIGNOUT, port)) { return; }
    port.signOut();
    this.showNotice($r('app.string.desktop_cloud_signout_done'));
    this.load();
  }

  private async setEnabled(on: boolean): Promise<void> {
    const port = this.port;
    if (!this.alive || this.busy || this.running || port === undefined || on === this.view?.enabled ||
      !this.allows(on ? CLOUD_ACTION_ENABLE : CLOUD_ACTION_DISABLE, port)) { return; }
    this.busy = true;
    try {
      const message = await port.setEnabled(on);
      if (message) { this.showNotice(message, true); }
      else {
        this.showNotice(on ? $r('app.string.desktop_cloud_enabled') : $r('app.string.desktop_cloud_disabled'));
      }
    } catch (_) {
      this.showNotice($r('app.string.desktop_cloud_action_failed'), true);
    } finally {
      if (this.alive) { this.busy = false; this.load(); }
    }
  }

  private async sync(upload: boolean): Promise<void> {
    const port = this.port;
    if (!this.alive || this.busy || port === undefined ||
      !this.allows(upload ? CLOUD_ACTION_UPLOAD : CLOUD_ACTION_PULL, port)) { return; }
    const generation = port.generation();
    this.busy = true;
    this.showNotice(upload ? $r('app.string.desktop_cloud_upload_started') : $r('app.string.desktop_cloud_pull_started'));
    try {
      const result = upload ? port.upload() : port.pull();
      this.tick();
      const message = await result;
      if (generation === port.generation()) {
        if (message) { this.showNotice(message, true); }
        else {
          this.showNotice(upload ? $r('app.string.desktop_cloud_upload_done') : $r('app.string.desktop_cloud_pull_done'));
        }
      }
    } catch (_) {
      if (generation === port.generation()) { this.showNotice($r('app.string.desktop_cloud_action_failed'), true); }
    } finally {
      if (this.alive) { this.busy = false; this.load(); }
    }
  }

  @Builder
  private RestoreContents(port: DesktopCloudSyncPort) {
    DesktopCloudSyncRestore({ port: port, onClose: (): void => { this.closeRestore(); } })
  }

  private async openRestore(): Promise<void> {
    const port = this.port;
    if (!this.alive || this.restoreOpening || this.restoreDialogId >= 0 || port === undefined ||
      !this.allows(CLOUD_ACTION_RESTORE, port)) { return; }
    this.restoreOpening = true;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.RestoreContents(port); },
        alignment: DialogAlignment.Center,
        width: Math.max(180, Math.min(540, this.viewWidth + 24)),
        height: '70%',
        isModal: true, autoCancel: true, cornerRadius: 20,
        systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => { this.restoreDialogId = -1; this.load(); }
      });
      if (this.alive) { this.restoreDialogId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      this.showNotice($r('app.string.desktop_cloud_open_failed'), true);
    } finally {
      this.restoreOpening = false;
    }
  }

  private closeRestore(): void {
    if (this.restoreDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.restoreDialogId);
    }
  }

  private unitText(kind: string, empty: ResourceStr): ResourceStr {
    const unit = this.view?.units.find((row: KindStat): boolean => row.kind === kind);
    if (unit === undefined) { return empty; }
    return unit.count > 0 ? $r('app.string.desktop_cloud_synced_count', unit.count, bytesText(unit.bytes)) :
      $r('app.string.desktop_cloud_unsynced');
  }

  private pluginText(): ResourceStr {
    const state = this.view;
    if (state === undefined || state.pluginCount === 0) { return $r('app.string.desktop_cloud_no_plugins'); }
    const names = state.plugins.map((plugin: DesktopCloudPlugin): string => plugin.name).join(' · ');
    return state.pluginCount > state.plugins.length ?
      $r('app.string.desktop_cloud_plugin_more', names, state.pluginCount - state.plugins.length) : names;
  }

  @Builder
  private Heading(title: ResourceStr) {
    Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
  }

  @Builder
  private Fact(title: ResourceStr, hint: ResourceStr, value: ResourceStr = '', color: ResourceColor = $r('sys.color.font_secondary')) {
    Row({ space: 16 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(14).fontColor($r('sys.color.font_primary'))
        if (hint !== '') { Text(hint).fontSize(12).fontColor($r('sys.color.font_tertiary')) }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (value !== '') { Text(value).fontSize(14).fontColor(color) }
    }.width('100%').constraintSize({ minHeight: 44 }).padding({ top: 4, bottom: 4 })
  }

  @Builder
  private Scopes() {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(6) } }) {
      Text($r('app.string.desktop_cloud_scope_sessions')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.desktop_cloud_scope_skills')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.desktop_cloud_scope_plugins')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      Text($r('app.string.desktop_cloud_scope_runtime')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
      Text($r('app.string.desktop_cloud_scope_secrets')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
      Text($r('app.string.desktop_cloud_scope_paths')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    }.width('100%')
  }

  @Builder
  private Account() {
    this.Heading($r('app.string.desktop_cloud_account'))
    if (this.view?.signedIn === true) {
      this.Fact(this.view?.displayName ?? '',
        $r('app.string.desktop_cloud_account_label', this.view?.accountLabel ?? ''),
        this.view?.cloudBadge ?? '', this.view?.cloudOk ? $r('sys.color.confirm') : $r('sys.color.warning'))
      Button($r('app.string.desktop_cloud_signout'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopCloudSignOut').fontSize(13).height(32).onClick((): void => { this.signOut(); })
    } else {
      this.Fact($r('app.string.desktop_cloud_signed_out'), $r('app.string.desktop_cloud_signed_out_hint'))
      Button(this.loginBusy ? $r('app.string.desktop_cloud_signing_in') : $r('app.string.desktop_cloud_login'))
        .key('desktopCloudSignIn').fontSize(13).height(34).enabled(!this.loginBusy)
        .onClick((): void => { this.confirmLogin(); })
    }
  }

  @Builder
  private Progress() {
    Column({ space: 6 }) {
      this.Fact(taskTitle(this.progress.task), this.progress.note, stageTitle(this.progress.stage))
      Progress({ value: progressRatio(this.progress) * 100, total: 100, type: ProgressType.Linear })
        .width('100%').color(this.progress.failed > 0 ? $r('sys.color.warning') : $r('sys.color.confirm'))
      Text($r('app.string.desktop_cloud_progress_counts', this.progress.succeeded, this.progress.failed,
        this.progress.skipped, this.progress.succeeded + this.progress.failed + this.progress.skipped,
        this.progress.total)).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    }.key('desktopCloudProgress').width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Actions() {
    this.Heading($r('app.string.desktop_cloud_sync_section'))
    this.Fact($r('app.string.desktop_cloud_enable'), this.view?.enabled ? $r('app.string.desktop_cloud_enable_hint') :
      $r('app.string.desktop_cloud_disable_hint'), this.view?.enabled ? $r('app.string.desktop_cloud_enabled') :
      $r('app.string.desktop_cloud_disabled'), this.view?.enabled ? $r('sys.color.confirm') : $r('sys.color.font_secondary'))
    Toggle({ type: ToggleType.Switch, isOn: this.view?.enabled === true }).key('desktopCloudToggle')
      .accessibilityText($r('app.string.desktop_cloud_enable')).enabled(!this.busy && !this.running)
      .onChange((on: boolean): void => { this.setEnabled(on); })
    this.Fact($r('app.string.desktop_cloud_service'), this.view?.cloudText ?? '', this.view?.cloudBadge ?? '',
      this.view?.cloudOk ? $r('sys.color.confirm') : $r('sys.color.warning'))
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(6) } }) {
      Button(this.running ? $r('app.string.desktop_cloud_working') : $r('app.string.desktop_cloud_upload'))
        .key('desktopCloudUpload').fontSize(13).height(34).enabled(!this.busy && !this.running && this.view?.enabled === true)
        .onClick((): void => { this.sync(true); })
      Button(this.running ? $r('app.string.desktop_cloud_working') : $r('app.string.desktop_cloud_pull'),
        { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopCloudPull').fontSize(13).height(34).enabled(!this.busy && !this.running)
        .onClick((): void => { this.sync(false); })
    }.width('100%')
    Text(this.view?.lastSyncText ? $r('app.string.desktop_cloud_last_sync', this.view?.lastSyncText ?? '') :
      $r('app.string.desktop_cloud_never_synced')).fontSize(12).fontColor($r('sys.color.font_tertiary'))
    if (this.running && (this.progress.stage || this.progress.note)) { this.Progress() }
  }

  @Builder
  private Contents() {
    this.Heading($r('app.string.desktop_cloud_contents'))
    this.Fact($r('app.string.desktop_cloud_sessions'), this.unitText('session', $r('app.string.desktop_cloud_sessions_hint')),
      (this.view?.pendingSessions ?? 0) > 0 ? $r('app.string.desktop_cloud_pending', this.view?.pendingSessions ?? 0,
        bytesText(this.view?.pendingBytes ?? 0)) : '—')
    this.Fact($r('app.string.desktop_cloud_skills'), this.unitText('skill', $r('app.string.desktop_cloud_skills_hint')))
    this.Fact($r('app.string.desktop_cloud_plugins'), this.pluginText(),
      this.unitText('plugin_manifest', (this.view?.pluginCount ?? 0) > 0 ?
        $r('app.string.desktop_cloud_plugin_count', this.view?.pluginCount ?? 0) : $r('app.string.desktop_cloud_no_plugins')))
    Button($r('app.string.desktop_cloud_restore'), { buttonStyle: ButtonStyleMode.TEXTUAL })
      .key('desktopCloudRestore').height(32).fontSize(13).onClick((): void => { this.openRestore(); })
    this.Scopes()
  }

  build() {
    Column({ space: 9 }) {
      if (this.view === undefined) {
        Text($r('app.string.desktop_cloud_not_ready')).fontSize(13).fontColor($r('sys.color.font_tertiary'))
      } else {
        if (this.notice !== '') {
          Text(this.notice).key('desktopCloudNotice').fontSize(13).width('100%').padding(8).borderRadius(7)
            .fontColor(this.noticeError ? $r('sys.color.warning') : $r('sys.color.font_secondary'))
            .backgroundColor($r('app.color.workspace_panel'))
        }
        this.Account()
        Divider().color($r('app.color.workspace_border')).margin({ top: 8, bottom: 8 })
        if (this.view.signedIn) {
          this.Actions()
          Divider().color($r('app.color.workspace_border')).margin({ top: 8, bottom: 8 })
          this.Contents()
        } else {
          this.Heading($r('app.string.desktop_cloud_scope_intro'))
          this.Scopes()
        }
      }
    }.key('desktopCloudSync').width('100%').alignItems(HorizontalAlign.Start)
      .onAreaChange((_: Area, next: Area): void => {
        const width = Number(next.width);
        if (Number.isFinite(width) && width > 0) { this.viewWidth = width; }
      })
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; this.syncPolling(); })
  }
}
