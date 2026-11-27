import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { getString } from 'connection';
import { HMS_SAMPLE_RATE } from 'appstate';
import { DesktopVoiceCapture, DesktopVoiceMicrophoneUnavailable } from '../speech/DesktopVoiceCapture';
import { VOICE_WAV_HEADER_BYTES } from '../speech/VoiceWave';
import { desktopVoiceIsReady, desktopVoiceNeedsInstallation, desktopVoiceSelectedProvider,
  readDesktopVoiceCatalog } from './DesktopVoiceSettingsModel';
import { readDesktopVoiceMicrophone } from './DesktopVoiceSettingsPreferences';
import { showDesktopVoiceSetup } from './DesktopVoiceSettingsPrompt';
import type { DesktopComposerDraft } from './DesktopDraftReferences';
import type { DesktopHostActions } from './DesktopHostActions';

const MIC: Permissions = 'ohos.permission.MICROPHONE';
const PCM_BYTES_PER_SECOND = HMS_SAMPLE_RATE * 2;
const WAVEFORM_LENGTH = 15;

export interface DesktopVoiceInsertion {
  draft: DesktopComposerDraft;
  start: number;
  end: number;
}

@Component
export struct DesktopVoiceInput {
  host?: DesktopHostActions;
  @Prop @Watch('cancel') sessionId: string = '';
  @Prop locked: boolean = false;
  @StorageProp('dshDesktopVoiceForeground') @Watch('foregroundChanged') private foreground: boolean = true;
  onAnchor: () => DesktopVoiceInsertion | undefined = (): undefined => undefined;
  onInsert: (text: string, insertion?: DesktopVoiceInsertion) => boolean = (): boolean => false;
  onSettings: () => void = (): void => {};
  @State private phase: string = 'idle';
  @State private status: ResourceStr = '';
  @State private pending: string = '';
  @State private levels: number[] = [];
  private capture?: DesktopVoiceCapture;
  private provider: string = '';
  private language: string = '';
  private insertion?: DesktopVoiceInsertion;
  private timeout: number = -1;
  private generation: number = 0;

  aboutToDisappear(): void { this.cancel(); }

  private foregroundChanged(): void {
    if (!this.foreground && this.phase === 'recording') { this.cancel(); }
  }

  private cancel(): void {
    ++this.generation;
    this.stopTimer();
    this.capture?.cancel();
    this.capture = undefined;
    this.insertion = undefined;
    this.levels = [];
    this.pending = '';
    this.phase = 'idle';
  }

  private stopTimer(): void {
    if (this.timeout >= 0) { clearTimeout(this.timeout); this.timeout = -1; }
  }

  private fail(status: ResourceStr): void {
    this.cancel();
    this.status = status;
    this.phase = 'feedback';
  }

  private setup(install: boolean = false): void {
    this.cancel();
    showDesktopVoiceSetup(this.getUIContext(), install, this.onSettings);
  }

  private async start(): Promise<void> {
    if (this.locked || !this.sessionId || this.host === undefined) { return; }
    this.cancel();
    this.insertion = this.onAnchor();
    const generation = this.generation;
    this.phase = 'requesting';
    this.status = $r('app.string.desktop_voice_preparing');
    try {
      const result = await this.host.call('speech/catalog');
      if (this.generation !== generation) { return; }
      const catalog = result.ok ? readDesktopVoiceCatalog(result.value) : undefined;
      const provider = desktopVoiceSelectedProvider(catalog);
      if (catalog === undefined || !catalog.language || !desktopVoiceIsReady(provider?.preparation.phase)) {
        this.setup(desktopVoiceNeedsInstallation(provider));
        return;
      }
      const maxDuration = Math.min(120, catalog.maxDurationSeconds);
      const byteLimit = Math.min(4 * 1024 * 1024, catalog.maxAudioBytes);
      const maxBytes = Math.min(Math.floor(maxDuration * PCM_BYTES_PER_SECOND), byteLimit - VOICE_WAV_HEADER_BYTES);
      if (!Number.isFinite(maxBytes) || maxBytes < PCM_BYTES_PER_SECOND / 5) {
        this.fail($r('app.string.desktop_voice_failed'));
        return;
      }
      const ability = this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
      if (ability === undefined) { this.fail($r('app.string.desktop_voice_permission')); return; }
      this.status = $r('app.string.desktop_voice_requesting');
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(ability, [MIC]);
      if (this.generation !== generation) { return; }
      if (permission.authResults[0] !== 0) { this.fail($r('app.string.desktop_voice_permission')); return; }
      if (!this.foreground) { this.cancel(); return; }
      this.provider = catalog.providerId;
      this.language = catalog.language;
      this.levels = new Array<number>(WAVEFORM_LENGTH).fill(0);
      const capture = new DesktopVoiceCapture((microphoneLost?: boolean): void => {
        if (this.generation !== generation) { return; }
        if (microphoneLost) { this.fail($r('app.string.desktop_voice_device_lost')); }
        else { this.cancel(); }
      });
      this.capture = capture;
      const started = await capture.start(maxBytes, (value: number): void => {
        if (this.generation === generation && this.phase === 'recording') {
          this.levels = this.levels.slice(1).concat(value);
        }
      }, readDesktopVoiceMicrophone(ability));
      if (this.generation !== generation) { return; }
      if (!started) { this.fail($r('app.string.desktop_voice_busy')); return; }
      if (!this.foreground) { this.cancel(); return; }
      this.phase = 'recording';
      this.status = $r('app.string.desktop_voice_recording');
      this.timeout = setTimeout((): void => { this.finish(); }, maxBytes / PCM_BYTES_PER_SECOND * 1000);
    } catch (error) {
      if (this.generation === generation) {
        this.fail(error instanceof DesktopVoiceMicrophoneUnavailable ? $r('app.string.desktop_voice_device_lost') :
          $r('app.string.desktop_voice_failed'));
      }
    }
  }

  private async finish(): Promise<void> {
    const capture = this.capture;
    if (this.phase !== 'recording' || capture === undefined || this.host === undefined) { return; }
    const generation = this.generation;
    this.stopTimer();
    this.phase = 'transcribing';
    this.status = $r('app.string.desktop_voice_transcribing');
    try {
      const wave = await capture.finish();
      if (this.generation !== generation) { return; }
      this.capture = undefined;
      if (wave === undefined) { this.fail($r('app.string.desktop_voice_short')); return; }
      const encoded = await new util.Base64Helper().encodeToString(wave);
      if (this.generation !== generation) { return; }
      const result = await this.host.call('speech/transcribe',
        { 'providerId': this.provider, 'language': this.language, 'audioBase64': encoded }, 180000, undefined, true);
      if (this.generation !== generation) { return; }
      if (!result.ok) { this.fail(result.error?.message || $r('app.string.desktop_voice_failed')); return; }
      const text = getString(result.value, 'text')?.trim() ?? '';
      if (!text) { this.fail($r('app.string.desktop_voice_empty')); return; }
      if (this.insertion !== undefined && this.onInsert(text, this.insertion)) { this.cancel(); return; }
      this.pending = text;
      this.status = $r('app.string.desktop_voice_conflict');
      this.phase = 'feedback';
    } catch (_) {
      if (this.generation === generation) { this.fail($r('app.string.desktop_voice_failed')); }
    }
  }

  @Builder
  private Waveform() {
    Row({ space: 2 }) {
      ForEach(this.levels, (level: number, index: number): void => {
        Column().width(2).height(2 + Math.round(level * 14))
          .borderRadius(1).backgroundColor($r('sys.color.brand'))
      }, (level: number, index: number): string => index + ':' + level)
    }.height(22).alignItems(VerticalAlign.Center).accessibilityLevel('no')
  }

  @Builder
  private Action(icon: Resource, key: string, label: Resource, click: () => void, size: number = 16) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(icon).width(size).height(size).fillColor($r('sys.color.font_secondary'))
        .supportSvg2(true).draggable(false).accessibilityLevel('no')
    }.width(32).height(32).padding(0).focusOnTouch(false).key(key).accessibilityText(label).onClick(click)
  }

  build() {
    Row({ space: 2 }) {
      if (this.phase === 'idle') {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_voice_microphone_outline')).width(18).height(18)
            .fillColor($r('sys.color.font_secondary')).supportSvg2(true).draggable(false).accessibilityLevel('no')
        }.width(32).height(32).padding(0).focusOnTouch(false).enabled(!this.locked && this.host !== undefined)
          .key('desktopVoiceStart').accessibilityText($r('app.string.desktop_voice_start'))
          .onClick((): void => { this.start(); })
      } else {
        this.Action($r('app.media.dsh_dock_close'), 'desktopVoiceCancel',
          $r('app.string.desktop_voice_cancel'), (): void => { this.cancel(); })
        if (this.phase === 'recording') {
          this.Waveform()
        }
        Text(this.status).key('desktopVoiceStatus').fontSize(12).fontColor($r('sys.color.font_secondary'))
          .constraintSize({ maxWidth: 138 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.phase === 'recording') {
          this.Action($r('app.media.dsh_cordis_stop_fill'), 'desktopVoiceFinish',
            $r('app.string.desktop_voice_finish'), (): void => { this.finish(); }, 14)
        } else if (this.phase === 'feedback' && this.pending.length > 0) {
          Button($r('app.string.desktop_voice_insert'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(30).padding({ left: 4, right: 4 }).borderRadius(7).fontSize(12).focusOnTouch(false)
            .key('desktopVoiceInsert').enabled(!this.locked).onClick((): void => {
              if (this.onInsert(this.pending)) { this.cancel(); }
            })
        } else if (this.phase === 'feedback') {
          this.Action($r('app.media.dsh_voice_microphone_outline'), 'desktopVoiceRetry',
            $r('app.string.desktop_voice_retry'), (): void => { this.start(); }, 18)
        }
      }
    }.height(34).onVisibleAreaChange([0], (visible: boolean): void => {
      if (!visible && this.phase !== 'idle') { this.cancel(); }
    })
  }
}
