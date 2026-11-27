import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopVoiceSettingsMicrophone } from './DesktopVoiceSettingsMicrophone';
import { DesktopVoiceSettingsPreparation } from './DesktopVoiceSettingsPreparation';
import { desktopVoiceProviderPatch, desktopVoiceSelectedProvider, readDesktopVoiceCatalog } from './DesktopVoiceSettingsModel';
import type { DesktopVoiceCatalog, DesktopVoiceProvider } from './DesktopVoiceSettingsModel';
import type { DesktopHostActions } from './DesktopHostActions';

export { DESKTOP_VOICE_BUNDLE } from './DesktopVoiceSettingsModel';

function languageName(language: string): ResourceStr {
  switch (language) {
    case 'auto': return $r('app.string.desktop_voice_language_auto');
    case 'zh': return $r('app.string.desktop_voice_language_zh');
    case 'en': return $r('app.string.desktop_voice_language_en');
    case 'yue': return $r('app.string.desktop_voice_language_yue');
    case 'ja': return $r('app.string.desktop_voice_language_ja');
    case 'es': return $r('app.string.desktop_voice_language_es');
    case 'fr': return $r('app.string.desktop_voice_language_fr');
    case 'de': return $r('app.string.desktop_voice_language_de');
    case 'ru': return $r('app.string.desktop_voice_language_ru');
    case 'pt': return $r('app.string.desktop_voice_language_pt');
    case 'ko': return $r('app.string.desktop_voice_language_ko');
    default: return language || $r('app.string.desktop_voice_not_selected');
  }
}

@Component
export struct DesktopVoiceSettings {
  host?: DesktopHostActions;
  @State private catalog?: DesktopVoiceCatalog = undefined;
  @State private connected: boolean = false;
  @State private saving: boolean = false;
  @State private connectionProblem: ResourceStr = '';
  @State private configurationProblem: ResourceStr = '';
  private mounted: boolean = false;
  private streamGeneration: number = 0;
  private catalogRevision: number = 0;
  private requestGeneration: number = 0;
  private retryTimer: number = -1;
  private stopFollow?: () => void;

  aboutToAppear(): void {
    this.mounted = true;
    this.connect();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    ++this.streamGeneration;
    ++this.requestGeneration;
    this.stopFollow?.();
    this.stopFollow = undefined;
    clearTimeout(this.retryTimer);
    this.retryTimer = -1;
  }

  private connect(): void {
    if (!this.mounted) { return; }
    clearTimeout(this.retryTimer);
    this.retryTimer = -1;
    const generation = ++this.streamGeneration;
    this.stopFollow?.();
    this.stopFollow = this.host?.watch('speech/follow', {}, {
      onItem: (frame: Object): void => {
        if (generation === this.streamGeneration && this.mounted && this.acceptCatalog(frame)) {
          ++this.catalogRevision;
        }
      },
      onError: (_: string, message: string): void => { this.disconnected(generation, message); },
      onEnd: (): void => { this.disconnected(generation); }
    });
    if (this.stopFollow === undefined) { this.retry(); }
    this.refresh();
  }

  private disconnected(generation: number, message: string = ''): void {
    if (generation !== this.streamGeneration || !this.mounted) { return; }
    this.connected = false;
    this.connectionProblem = message || $r('app.string.desktop_voice_reconnecting');
    this.retry();
  }

  private retry(): void {
    if (this.retryTimer < 0 && this.host !== undefined) {
      this.retryTimer = setTimeout((): void => { this.connect(); }, 2400);
    }
  }

  private acceptCatalog(frame?: Object): boolean {
    const catalog = readDesktopVoiceCatalog(frame);
    if (catalog === undefined) { return false; }
    this.catalog = catalog;
    this.connected = true;
    this.connectionProblem = '';
    return true;
  }

  private async refresh(): Promise<void> {
    const generation = ++this.requestGeneration;
    const revision = this.catalogRevision;
    const result = await this.host?.call('speech/catalog');
    if (!this.mounted || generation !== this.requestGeneration || revision !== this.catalogRevision) { return; }
    if (result?.ok && this.acceptCatalog(result.value)) { return; }
    this.connected = false;
    this.connectionProblem = result?.error?.message || $r('app.string.desktop_voice_catalog_failed');
  }

  private async configure(patch: Record<string, Object>): Promise<void> {
    if (!this.connected || this.saving || this.host === undefined) { return; }
    this.saving = true;
    this.configurationProblem = '';
    const result = await this.host.call('speech/configure', { 'patch': patch });
    if (!this.mounted) { return; }
    this.saving = false;
    if (result.ok) { this.refresh(); }
    else { this.configurationProblem = result.error?.message || $r('app.string.desktop_voice_config_failed'); }
  }

  private providerChoices(): MenuElement[] {
    const catalog = this.catalog;
    if (catalog === undefined) { return []; }
    return catalog.providers.map((provider: DesktopVoiceProvider): MenuElement => {
      return {
        value: provider.name,
        icon: provider.id === catalog.providerId ? $r('app.media.dsh_dock_check') : undefined,
        action: (): void => {
          if (provider.id !== this.catalog?.providerId) {
            this.configure(desktopVoiceProviderPatch(provider, this.catalog?.language ?? ''));
          }
        }
      };
    });
  }

  private languageChoices(): MenuElement[] {
    return desktopVoiceSelectedProvider(this.catalog)?.languages.map((language: string): MenuElement => {
      return {
        value: languageName(language),
        icon: language === this.catalog?.language ? $r('app.media.dsh_dock_check') : undefined,
        action: (): void => {
          if (language !== this.catalog?.language) { this.configure({ 'language': language }); }
        }
      };
    }) ?? [];
  }

  private providerName(): ResourceStr {
    return desktopVoiceSelectedProvider(this.catalog)?.name ?? $r('app.string.desktop_voice_not_selected');
  }

  private providerById(id: string): DesktopVoiceProvider | undefined {
    return this.catalog?.providers.find((provider: DesktopVoiceProvider): boolean => provider.id === id);
  }

  @Builder
  private Selector(label: Resource, value: ResourceStr, choices: MenuElement[], key: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Text(value).fontSize(14).fontColor($r('sys.color.font_primary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12)
            .supportSvg2(true).accessibilityLevel('no')
        }
      }.key(key).height(34).borderRadius(8).constraintSize({ maxWidth: 250 })
        .enabled(this.connected && !this.saving && choices.length > 0)
        .bindMenu(choices, desktopMenuOptions(Placement.BottomRight))
    }.width('100%')
  }

  build() {
    Column({ space: 10 }) {
      if (this.catalog !== undefined) {
        DesktopVoiceSettingsMicrophone()
        this.Selector($r('app.string.desktop_voice_recognition_provider'), this.providerName(),
          this.providerChoices(), 'desktopVoiceProvider')
        this.Selector($r('app.string.desktop_voice_recognition_language'), languageName(this.catalog.language),
          this.languageChoices(), 'desktopVoiceLanguage')
        if (desktopVoiceSelectedProvider(this.catalog)?.location === 'cloud') {
          Text($r('app.string.desktop_voice_recognition_cloud')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        } else if (desktopVoiceSelectedProvider(this.catalog)?.location === 'host-local') {
          Text($r('app.string.desktop_voice_recognition_local')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        if (this.configurationProblem !== '') {
          Text(this.configurationProblem).key('desktopVoiceConfigureError').fontSize(13)
            .fontColor($r('app.color.workspace_status_error'))
        }
        ForEach(this.catalog.providers, (provider: DesktopVoiceProvider): void => {
          DesktopVoiceSettingsPreparation({ host: this.host, provider: this.providerById(provider.id), connected: this.connected,
            onChange: (): void => { this.refresh(); } })
        }, (provider: DesktopVoiceProvider): string => provider.id)
        if (this.catalog.providers.length === 0) {
          Text($r('app.string.desktop_voice_no_providers')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
      } else if (this.connectionProblem === '') {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text($r('app.string.desktop_voice_preparing')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
      }
      if (this.connectionProblem !== '') {
        Row({ space: 8 }) {
          Text(this.connectionProblem).key('desktopVoiceCatalogError').fontSize(13).layoutWeight(1)
            .fontColor($r('app.color.workspace_status_error'))
          Button($r('app.string.desktop_voice_catalog_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopVoiceCatalogRetry').onClick((): void => { this.connect(); })
        }.width('100%')
      }
    }.width('100%').padding(14).borderRadius(12).alignItems(HorizontalAlign.Start)
      .key('desktopVoiceSettings').backgroundColor($r('app.color.workspace_panel'))
  }
}
