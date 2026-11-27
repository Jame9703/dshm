import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { DesktopVoiceCapture, DesktopVoiceMicrophoneUnavailable, describeDesktopVoiceMicrophone,
  resolveDesktopVoiceMicrophone } from '../speech/DesktopVoiceCapture';
import type { DesktopVoiceMicrophone } from '../speech/DesktopVoiceCapture';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { readDesktopVoiceMicrophone, saveDesktopVoiceMicrophone } from './DesktopVoiceSettingsPreferences';

const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const SEGMENTS: number[] = [0, 1, 2, 3, 4, 5, 6, 7];
const MIC_USAGE: audio.DeviceUsage = audio.DeviceUsage.MEDIA_INPUT_DEVICES;

@Component
export struct DesktopVoiceSettingsMicrophone {
  @StorageProp('dshDesktopVoiceForeground') @Watch('foregroundChanged') private foreground: boolean = true;
  @State private devices: DesktopVoiceMicrophone[] = [];
  @State private selected?: DesktopVoiceMicrophone = undefined;
  @State private matchedId: number = -1;
  @State private defaultName: string = '';
  @State private live: boolean = false;
  @State private level: number = 0;
  @State private problem: ResourceStr = '';
  @State private saving: boolean = false;
  private context?: common.UIAbilityContext;
  private routing?: audio.AudioSessionManager;
  private visible: boolean = true;
  private mounted: boolean = false;
  private capture?: DesktopVoiceCapture;
  private releasing: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private permission?: Promise<boolean>;
  private readonly deviceChanged = (_: audio.DeviceChangeAction): void => {
    const before = this.matchedId;
    this.readDevices();
    if (this.selected !== undefined && before !== this.matchedId) { this.preview(); }
  };

  aboutToAppear(): void {
    this.mounted = true;
    this.context = this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
    if (this.context !== undefined) { this.selected = readDesktopVoiceMicrophone(this.context); }
    try {
      this.routing = audio.getAudioManager().getSessionManager();
      this.routing.on('availableDeviceChange', MIC_USAGE, this.deviceChanged);
    } catch (_) {}
    this.readDevices();
    this.preview();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.releasePreview();
    try { this.routing?.off('availableDeviceChange', this.deviceChanged); } catch (_) {}
  }

  private readDevices(): void {
    if (!this.mounted) { return; }
    try {
      const devices = this.routing?.getAvailableDevices(MIC_USAGE) ?? [];
      this.devices = devices.map((device: audio.AudioDeviceDescriptor): DesktopVoiceMicrophone =>
        describeDesktopVoiceMicrophone(device));
      const matched = this.selected === undefined ? undefined : resolveDesktopVoiceMicrophone(devices, this.selected);
      this.matchedId = matched?.id ?? -1;
      if (this.selected === undefined) {
        const details: audio.AudioCapturerInfo = { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 };
        const current = audio.getAudioManager().getRoutingManager().getPreferredInputDeviceForCapturerInfoSync(details);
        this.defaultName = current[0]?.displayName || current[0]?.name || '';
      }
    } catch (_) {}
  }

  private foregroundChanged(): void {
    if (this.foreground) { this.preview(); }
    else { this.releasePreview(); }
  }

  private releasePreview(): number {
    const generation = ++this.generation;
    if (this.capture !== undefined) {
      this.releasing = this.capture.cancel();
      this.capture = undefined;
    }
    this.live = false;
    this.level = 0;
    return generation;
  }

  private requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    if (this.permission !== undefined) { return this.permission; }
    this.permission = abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [MICROPHONE_PERMISSION])
      .then((result: PermissionRequestResult): boolean => result.authResults[0] === 0)
      .catch((): boolean => false)
      .finally((): void => { this.permission = undefined; });
    return this.permission;
  }

  private async preview(): Promise<void> {
    const generation = this.releasePreview();
    const context = this.context;
    this.problem = '';
    if (!this.mounted || !this.foreground || !this.visible || context === undefined || this.unavailable()) { return; }
    try {
      await this.releasing;
      if (generation !== this.generation) { return; }
      const allowed = await this.requestPermission(context);
      if (generation !== this.generation) { return; }
      if (!allowed) { this.problem = $r('app.string.desktop_voice_permission'); return; }
      this.readDevices();
      if (this.unavailable()) { return; }
      const capture = new DesktopVoiceCapture((microphoneLost?: boolean): void => {
        if (generation === this.generation) {
          this.releasePreview();
          this.problem = microphoneLost ? $r('app.string.desktop_voice_device_lost') :
            $r('app.string.desktop_voice_preview_failed');
        }
      });
      this.capture = capture;
      const started = await capture.start(0, (level: number): void => {
        if (generation === this.generation) {
          const decibels = 20 * Math.log10(Math.max(0.00001, level));
          this.level = Math.ceil(Math.max(0, Math.min(1, (decibels + 60) / 60)) * SEGMENTS.length);
        }
      }, this.selected);
      if (generation !== this.generation) { return; }
      if (!started) {
        this.releasePreview();
        this.problem = $r('app.string.desktop_voice_busy');
        return;
      }
      this.live = true;
    } catch (error) {
      if (generation === this.generation) {
        this.releasePreview();
        this.problem = error instanceof DesktopVoiceMicrophoneUnavailable ?
          $r('app.string.desktop_voice_device_lost') : $r('app.string.desktop_voice_preview_failed');
      }
    }
  }

  private async select(device?: DesktopVoiceMicrophone): Promise<void> {
    const context = this.context;
    if (context === undefined || this.saving) { return; }
    this.saving = true;
    const saved = await saveDesktopVoiceMicrophone(context, device);
    if (!this.mounted) { return; }
    this.saving = false;
    if (!saved) { this.problem = $r('app.string.desktop_voice_device_save_failed'); return; }
    this.selected = device;
    this.readDevices();
    this.preview();
  }

  private unavailable(): boolean { return this.selected !== undefined && this.matchedId < 0; }

  private deviceLabel(device?: DesktopVoiceMicrophone): ResourceStr {
    if (device === undefined) {
      return this.defaultName ? $r('app.string.desktop_voice_system_microphone_named', this.defaultName) :
        $r('app.string.desktop_voice_system_microphone');
    }
    const index = this.devices.findIndex((item: DesktopVoiceMicrophone): boolean => item.id === device.id);
    return device.name || (index < 0 ? $r('app.string.desktop_voice_unnamed_microphone') :
      $r('app.string.desktop_voice_numbered_microphone', index + 1));
  }

  private microphoneChoices(): MenuElement[] {
    const choices: MenuElement[] = [{
      value: this.deviceLabel(),
      icon: this.selected === undefined ? $r('app.media.dsh_dock_check') : undefined,
      action: (): void => { this.select(); }
    }];
    for (const device of this.devices) {
      choices.push({ value: this.deviceLabel(device),
        icon: device.id === this.matchedId ? $r('app.media.dsh_dock_check') : undefined,
        action: (): void => { this.select(device); } });
    }
    return choices;
  }

  build() {
    Column({ space: 5 }) {
      Row({ space: 12 }) {
        Text($r('app.string.desktop_voice_input_device')).fontSize(14)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 8 }) {
            Text(this.deviceLabel(this.selected)).fontSize(14).maxLines(1)
              .fontColor($r('sys.color.font_primary')).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.live) {
              Row({ space: 2 }) {
                ForEach(SEGMENTS, (segment: number): void => {
                  Blank().width(2).height(10).borderRadius(1)
                    .backgroundColor(segment < this.level ? $r('sys.color.brand') : $r('app.color.workspace_border'))
                }, (segment: number): string => segment.toString())
              }.key('desktopVoiceMicLevel').accessibilityText($r('app.string.desktop_voice_input_level'))
            }
            Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true)
              .accessibilityLevel('no')
          }
        }.height(34).borderRadius(8).constraintSize({ maxWidth: 250 })
          .key('desktopVoiceMicrophone').enabled(!this.saving && this.context !== undefined)
          .bindMenu(this.microphoneChoices(), desktopMenuOptions(Placement.BottomRight))
      }.width('100%')
      if (this.unavailable()) {
        Text($r('app.string.desktop_voice_device_lost')).key('desktopVoiceMicrophoneUnavailable')
          .fontSize(12).fontColor($r('app.color.workspace_status_error'))
      } else if (this.problem !== '') {
        Row({ space: 8 }) {
          Text(this.problem).fontSize(12).fontColor($r('app.color.workspace_status_error')).layoutWeight(1)
          Button($r('app.string.desktop_voice_preview_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopVoicePreviewRetry').onClick((): void => { this.preview(); })
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .onVisibleAreaChange([0], (visible: boolean): void => {
        if (this.visible === visible) { return; }
        this.visible = visible;
        if (visible) { this.preview(); }
        else { this.releasePreview(); }
      })
  }
}
