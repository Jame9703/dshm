import { CLOUD_ACTION_RESTORE, decideCloudAction, progressRatio } from 'platform';
import {
  DesktopCloudPlugin, DesktopCloudPluginList, DesktopCloudSyncPort
} from './DesktopCloudSyncPort';

@Component
export struct DesktopCloudSyncRestore {
  port?: DesktopCloudSyncPort;
  onClose: () => void = (): void => {};
  @State private candidates: DesktopCloudPlugin[] = [];
  @State private picked: string[] = [];
  @State private detail: ResourceStr = $r('app.string.desktop_cloud_restore_check_hint');
  @State private notice: ResourceStr = '';
  @State private noticeError: boolean = false;
  @State private busy: boolean = false;
  @State private percent: number = 0;
  @State private progressNote: string = '';
  private alive: boolean = false;
  private timer: number = -1;
  private checkedGeneration: number = -1;

  aboutToAppear(): void {
    this.alive = true;
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.stopProgress();
  }

  private stopProgress(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
  }

  private setNotice(text: ResourceStr, error: boolean = false): void {
    this.notice = text;
    this.noticeError = error;
  }

  private mayRun(port: DesktopCloudSyncPort): boolean {
    const state = port.overview();
    const activity = port.activity();
    const decision = decideCloudAction(CLOUD_ACTION_RESTORE, {
      signedIn: state.signedIn, enabled: state.enabled, running: activity.running
    });
    if (!decision.ok) { this.setNotice(decision.message, true); return false; }
    if (activity.running) { this.setNotice($r('app.string.desktop_cloud_restore_busy'), true); return false; }
    return true;
  }

  private setCandidates(result: DesktopCloudPluginList, generation: number): void {
    this.candidates = result.missing;
    this.picked = result.missing.map((plugin: DesktopCloudPlugin): string => plugin.name);
    this.checkedGeneration = generation;
    if (!result.present) {
      this.detail = $r('app.string.desktop_cloud_restore_no_manifest');
    } else if (result.missing.length === 0) {
      this.detail = result.differing > 0 ? $r('app.string.desktop_cloud_restore_already_diff', result.differing) :
        $r('app.string.desktop_cloud_restore_already');
    } else {
      this.detail = result.differing > 0 ?
        $r('app.string.desktop_cloud_restore_missing_diff', result.missing.length, result.differing) :
        $r('app.string.desktop_cloud_restore_missing', result.missing.length);
    }
  }

  private async check(): Promise<void> {
    const port = this.port;
    if (!this.alive || this.busy || port === undefined || !this.mayRun(port)) { return; }
    this.busy = true;
    this.candidates = [];
    this.picked = [];
    this.checkedGeneration = -1;
    this.setNotice($r('app.string.desktop_cloud_restore_checking'));
    const generation = port.generation();
    try {
      const result = await port.checkPlugins();
      if (this.alive && generation === port.generation()) {
        this.setCandidates(result, generation);
        this.setNotice('');
      }
    } catch (_) {
      if (this.alive) { this.setNotice($r('app.string.desktop_cloud_action_failed'), true); }
    } finally {
      if (this.alive) { this.busy = false; }
    }
  }

  private pick(name: string, on: boolean): void {
    if (on && !this.picked.includes(name)) { this.picked = this.picked.concat(name); }
    if (!on) { this.picked = this.picked.filter((item: string): boolean => item !== name); }
  }

  private async install(): Promise<void> {
    const port = this.port;
    if (!this.alive || this.busy || port === undefined || !this.mayRun(port)) { return; }
    if (this.checkedGeneration !== port.generation()) {
      this.candidates = [];
      this.picked = [];
      this.detail = $r('app.string.desktop_cloud_restore_check_hint');
      this.setNotice($r('app.string.desktop_cloud_restore_recheck'), true);
      return;
    }
    const selected = this.candidates.filter((plugin: DesktopCloudPlugin): boolean => this.picked.includes(plugin.name));
    if (selected.length === 0) { return; }
    this.busy = true;
    this.setNotice($r('app.string.desktop_cloud_restore_installing', selected.length));
    const generation = port.generation();
    this.timer = setInterval((): void => {
      const activity = port.activity();
      if (this.alive && activity.running && activity.progress.task === 'plugins') {
        this.percent = progressRatio(activity.progress) * 100;
        this.progressNote = activity.progress.note;
      }
    }, 450);
    try {
      const result = await port.installPlugins(selected);
      if (!this.alive || generation !== port.generation()) { return; }
      this.setNotice(result.needsRestart ? $r('app.string.desktop_cloud_restore_restart', result.summary) : result.summary,
        !result.ok);
      if (result.ok) {
        this.candidates = this.candidates.filter((plugin: DesktopCloudPlugin): boolean =>
          !selected.some((installed: DesktopCloudPlugin): boolean => installed.name === plugin.name));
        this.picked = [];
        if (this.candidates.length === 0) { this.detail = $r('app.string.desktop_cloud_restore_already'); }
      }
    } catch (_) {
      if (this.alive) { this.setNotice($r('app.string.desktop_cloud_action_failed'), true); }
    } finally {
      this.stopProgress();
      if (this.alive) {
        this.busy = false;
        this.percent = 0;
        this.progressNote = '';
      }
    }
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text($r('app.string.desktop_cloud_restore')).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button($r('app.string.desktop_cloud_close'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopCloudRestoreClose').height(34).onClick(this.onClose)
      }.width('100%')
      Scroll() {
        Column({ space: 10 }) {
          Text(this.detail).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
          Button($r('app.string.desktop_cloud_restore_check'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopCloudRestoreCheck').height(34).enabled(!this.busy).onClick((): void => { this.check(); })
          ForEach(this.candidates, (plugin: DesktopCloudPlugin): void => {
            Row({ space: 8 }) {
              Checkbox({ name: plugin.name, group: 'desktopCloudRestore' })
                .key('desktopCloudRestorePlugin-' + plugin.name)
                .accessibilityText(plugin.name)
                .select(this.picked.includes(plugin.name)).enabled(!this.busy)
                .onChange((selected: boolean): void => { this.pick(plugin.name, selected); })
              Text(plugin.name).fontSize(14).layoutWeight(1)
            }.width('100%').constraintSize({ minHeight: 38 })
          }, (plugin: DesktopCloudPlugin): string => plugin.name)
          if (this.candidates.length > 0) {
            Button($r('app.string.desktop_cloud_restore_install')).key('desktopCloudRestoreInstall').height(34)
              .enabled(!this.busy && this.picked.length > 0).onClick((): void => { this.install(); })
          }
          if (this.progressNote !== '') {
            Text(this.progressNote).fontSize(12).fontColor($r('sys.color.font_secondary'))
            Progress({ value: this.percent, total: 100, type: ProgressType.Linear }).width('100%')
          }
          if (this.notice !== '') {
            Text(this.notice).key('desktopCloudRestoreNotice').fontSize(13).width('100%')
              .fontColor(this.noticeError ? $r('sys.color.warning') : $r('sys.color.font_secondary'))
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.key('desktopCloudRestoreDialog').width('100%').height('100%').padding(20)
      .alignItems(HorizontalAlign.Start)
  }
}
