import { desktopMenuOptions } from './DesktopMenuOptions';
import type { DesktopVoicePreparationFailure, DesktopVoicePreparationStep, DesktopVoiceProvider } from './DesktopVoiceSettingsModel';
import type { DesktopHostActions } from './DesktopHostActions';

function stepLabel(kind: string, name: string): ResourceStr {
  switch (kind) {
    case 'check': return $r('app.string.desktop_voice_step_check');
    case 'model': return $r('app.string.desktop_voice_step_model');
    case 'vad': return $r('app.string.desktop_voice_step_vad');
    case 'verify': return $r('app.string.desktop_voice_step_verify');
    case 'load': return $r('app.string.desktop_voice_step_load', name);
    default: return kind;
  }
}

function stepStatus(status: string): ResourceStr {
  switch (status) {
    case 'pending': return $r('app.string.desktop_voice_step_pending');
    case 'running': return $r('app.string.desktop_voice_step_running');
    case 'complete': return $r('app.string.desktop_voice_step_complete');
    case 'failed': return $r('app.string.desktop_voice_preparation_failed');
    case 'cancelled': return $r('app.string.desktop_voice_step_cancelled');
    default: return status;
  }
}

function downloadFailure(download: DesktopVoicePreparationFailure): Resource {
  switch (download.reason) {
    case 'network': return $r('app.string.desktop_voice_download_network', download.resource);
    case 'dns': return $r('app.string.desktop_voice_download_dns', download.resource);
    case 'timeout': return $r('app.string.desktop_voice_download_timeout', download.resource);
    case 'certificate': return $r('app.string.desktop_voice_download_certificate', download.resource);
    case 'http': return $r('app.string.desktop_voice_download_http', download.resource, download.status.toString());
    case 'integrity': return $r('app.string.desktop_voice_download_integrity', download.resource);
    case 'storage': return $r('app.string.desktop_voice_download_storage', download.resource);
    default: return $r('app.string.desktop_voice_download_unknown', download.resource);
  }
}

function sourceLabel(source: string): ResourceStr {
  if (source === 'https://huggingface.co') { return 'Hugging Face'; }
  if (source === 'https://hf-mirror.com') { return $r('app.string.desktop_voice_source_mirror'); }
  return source || $r('app.string.desktop_voice_source_auto');
}

@Component
export struct DesktopVoiceSettingsPreparation {
  host?: DesktopHostActions;
  @Prop @Watch('updateClock') provider?: DesktopVoiceProvider = undefined;
  @Prop connected: boolean = false;
  onChange: () => void = (): void => {};
  @State private showSteps: boolean = false;
  @State private source: string = '';
  @State private working: boolean = false;
  @State private problem: ResourceStr = '';
  @State private clock: number = 0;
  private clockTimer: number = -1;
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.updateClock();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    clearInterval(this.clockTimer);
    this.clockTimer = -1;
  }

  private phase(): string { return this.provider?.preparation.phase ?? ''; }

  private canPrepare(): boolean { return ['unprepared', 'failed', 'cancelled'].includes(this.phase()); }

  private canCancel(): boolean { return ['checking', 'downloading', 'loading', 'cancelling'].includes(this.phase()); }

  private startedAt(): number {
    const state = this.provider?.preparation;
    return state?.steps.find((step: DesktopVoicePreparationStep): boolean => step.status === 'running')?.startedAt ||
      state?.startedAt || 0;
  }

  private updateClock(): void {
    const running = this.mounted && (this.canCancel() || this.phase() === 'waking') && this.startedAt() > 0;
    if (running && this.clockTimer < 0) {
      this.clock = Date.now();
      this.clockTimer = setInterval((): void => { this.clock = Date.now(); }, 1000);
    } else if (!running && this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private selectedSource(): string {
    const sources = this.provider?.downloadSources ?? [];
    if (sources.includes(this.source)) { return this.source; }
    return sources.length === 1 ? sources[0] : '';
  }

  private sourceChoices(): MenuElement[] {
    const source = this.selectedSource();
    const choices: MenuElement[] = [{
      value: sourceLabel(''), icon: !source ? $r('app.media.dsh_dock_check') : undefined,
      action: (): void => { this.source = ''; }
    }];
    for (const url of this.provider?.downloadSources ?? []) {
      choices.push({ value: sourceLabel(url), icon: url === source ? $r('app.media.dsh_dock_check') : undefined,
        action: (): void => { this.source = url; } });
    }
    return choices;
  }

  private summary(): ResourceStr {
    if (!this.connected) { return $r('app.string.desktop_voice_reconnecting'); }
    const runningStep = this.provider?.preparation.steps.find((step: DesktopVoicePreparationStep): boolean =>
      step.status === 'running');
    if (runningStep !== undefined) { return stepLabel(runningStep.kind, this.provider?.name ?? ''); }
    switch (this.phase()) {
      case 'unprepared': return $r('app.string.desktop_voice_unprepared');
      case 'checking': return $r('app.string.desktop_voice_step_check');
      case 'downloading': return $r('app.string.desktop_voice_downloading');
      case 'loading': return stepLabel('load', this.provider?.name ?? '');
      case 'waking': return $r('app.string.desktop_voice_waking');
      case 'ready': return this.provider?.location === 'cloud' ? $r('app.string.desktop_voice_cloud_ready') :
        $r('app.string.desktop_voice_local_ready');
      case 'standby': return $r('app.string.desktop_voice_standby');
      case 'failed': return $r('app.string.desktop_voice_preparation_failed');
      case 'cancelled': return $r('app.string.desktop_voice_preparation_cancelled');
      case 'cancelling': return $r('app.string.desktop_voice_cancelling');
      default: return $r('app.string.desktop_voice_catalog_failed');
    }
  }

  private async run(cancel: boolean): Promise<void> {
    const provider = this.provider;
    if (!this.connected || this.working || provider === undefined || this.host === undefined) { return; }
    if (cancel ? !this.canCancel() || this.phase() === 'cancelling' : !this.canPrepare()) { return; }
    this.working = true;
    this.problem = '';
    const source = this.selectedSource();
    const arguments_: Record<string, Object> = { 'providerId': provider.id };
    if (!cancel && source) {
      const options: Record<string, Object> = { 'downloadSource': source };
      arguments_['options'] = options;
    }
    try {
      const result = await this.host.call(cancel ? 'speech/cancelPreparation' : 'speech/prepare', arguments_);
      if (this.mounted) {
        if (result.ok) { this.onChange(); }
        else { this.problem = result.error?.message || $r('app.string.desktop_voice_preparation_failed'); }
      }
    } catch (_) {
      if (this.mounted) { this.problem = $r('app.string.desktop_voice_preparation_failed'); }
    } finally {
      if (this.mounted) { this.working = false; }
    }
  }

  @Builder
  private SourcePicker() {
    Row({ space: 12 }) {
      Text($r('app.string.desktop_voice_download_source')).fontSize(13).layoutWeight(1)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Text(sourceLabel(this.selectedSource())).fontSize(13).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12)
            .supportSvg2(true).accessibilityLevel('no')
        }
      }.height(34).constraintSize({ maxWidth: 250 }).borderRadius(8)
        .key('desktopVoicePreparationSource-' + (this.provider?.id ?? ''))
        .enabled(this.connected && !this.working && (this.provider?.downloadSources.length ?? 0) > 1)
        .bindMenu(this.sourceChoices(), desktopMenuOptions(Placement.BottomRight))
    }.width('100%')
    Text(this.selectedSource() ? $r('app.string.desktop_voice_source_manual_help') :
      $r('app.string.desktop_voice_source_auto_help')).fontSize(12).fontColor($r('sys.color.font_secondary'))
  }

  @Builder
  private Steps() {
    ForEach(this.provider?.preparation.steps ?? [], (step: DesktopVoicePreparationStep): void => {
      Row({ space: 8 }) {
        Text(stepLabel(step.kind, this.provider?.name ?? '')).fontSize(13).layoutWeight(1)
        Text(stepStatus(step.status)).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.width('100%').padding({ left: 14 })
        .key('desktopVoicePreparationStep-' + (this.provider?.id ?? '') + '-' + step.kind)
    }, (step: DesktopVoicePreparationStep): string => step.kind + ':' + step.status + ':' + step.startedAt)
  }

  @Builder
  private DownloadDetails() {
    if (this.phase() === 'downloading') {
      if ((this.provider?.preparation.totalBytes ?? 0) > 0) {
        Progress({ value: Math.min(this.provider?.preparation.completedBytes ?? 0, this.provider?.preparation.totalBytes ?? 0),
          total: this.provider?.preparation.totalBytes ?? 1, type: ProgressType.Linear })
          .width('100%').color($r('sys.color.brand')).key('desktopVoiceDownloadProgress-' + (this.provider?.id ?? ''))
        Text($r('app.string.desktop_voice_download_bytes',
          ((this.provider?.preparation.completedBytes ?? 0) / 1000000).toFixed(1),
          ((this.provider?.preparation.totalBytes ?? 0) / 1000000).toFixed(1)))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      } else {
        Text($r('app.string.desktop_voice_download_received',
          ((this.provider?.preparation.completedBytes ?? 0) / 1000000).toFixed(1)))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      if (this.provider?.preparation.resource) {
        Text(this.provider?.preparation.resource ?? '').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
    } else if ((this.canCancel() || this.phase() === 'waking') && this.startedAt() > 0) {
      Text($r('app.string.desktop_voice_elapsed', Math.max(0, Math.floor((this.clock - this.startedAt()) / 1000))))
        .fontSize(12).fontColor($r('sys.color.font_secondary'))
    }
  }

  @Builder
  private Estimates(provider: DesktopVoiceProvider) {
    Text($r('app.string.desktop_voice_setup_estimate',
      ((provider.estimate?.diskBytes ?? 0) / 1000000000).toString(),
      ((provider.estimate?.memoryBytes ?? 0) / 1000000000).toString(),
      (provider.estimate?.minimumMinutes ?? 0).toString(), (provider.estimate?.maximumMinutes ?? 0).toString()))
      .fontSize(12).fontColor($r('sys.color.font_secondary'))
  }

  @Builder
  private Failure(download?: DesktopVoicePreparationFailure) {
    if (download !== undefined) {
      Text(downloadFailure(download)).fontSize(13).fontColor($r('app.color.workspace_status_error'))
      if (download.source) {
        Text($r('app.string.desktop_voice_source_detail', download.source)).fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      if (download.code) {
        Text($r('app.string.desktop_voice_download_code', download.code)).fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
    } else if (this.provider?.preparation.message) {
      Text(this.provider?.preparation.message ?? '').fontSize(13).fontColor($r('app.color.workspace_status_error'))
    }
  }

  build() {
    Column({ space: 7 }) {
      Text(this.provider?.name ?? '').fontSize(15).fontWeight(FontWeight.Medium)
      if (this.phase() === 'unprepared' && this.provider !== undefined && this.provider.estimate !== undefined) {
        this.Estimates(this.provider)
      }
      Row({ space: 8 }) {
        Text(this.summary()).key('desktopVoiceProviderStatus-' + (this.provider?.id ?? '')).fontSize(13)
          .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        if ((this.provider?.preparation.steps.length ?? 0) > 0) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image(this.showSteps ? $r('app.media.dsh_queue_chevron_up_outline') :
              $r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14).supportSvg2(true)
              .accessibilityLevel('no')
          }.width(34).height(30).borderRadius(8).accessibilityText($r('app.string.desktop_voice_preparation_steps'))
            .key('desktopVoicePreparationSteps-' + (this.provider?.id ?? ''))
            .onClick((): void => { this.showSteps = !this.showSteps; })
        }
      }.width('100%')
      if (this.showSteps) { this.Steps() }
      this.DownloadDetails()
      if (this.phase() === 'failed') { this.Failure(this.provider?.preparation.download) }
      if (this.canPrepare()) {
        if ((this.provider?.downloadSources.length ?? 0) > 0) { this.SourcePicker() }
        Button(this.phase() === 'unprepared' ? $r('app.string.desktop_voice_prepare') :
          $r('app.string.desktop_voice_prepare_retry'), { buttonStyle: ButtonStyleMode.NORMAL })
          .key('desktopVoicePrepare-' + (this.provider?.id ?? '')).height(34).enabled(this.connected && !this.working)
          .onClick((): void => { this.run(false); })
      } else if (this.canCancel()) {
        Button($r('app.string.desktop_voice_prepare_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopVoiceCancelPreparation-' + (this.provider?.id ?? '')).height(34)
          .enabled(this.connected && !this.working && this.phase() !== 'cancelling')
          .onClick((): void => { this.run(true); })
      }
      if (this.problem !== '') {
        Text(this.problem).fontSize(13).fontColor($r('app.color.workspace_status_error'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12).borderRadius(10)
      .border({ width: 1, color: $r('app.color.workspace_border') })
  }
}
