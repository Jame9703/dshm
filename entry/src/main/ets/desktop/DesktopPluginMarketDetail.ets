import { i18n } from '@kit.LocalizationKit';
import { getArray, getBoolean, getRecord, getString } from 'connection';
import { openExternalUrl } from 'platform';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopHostActions, desktopHostProblem, desktopLocalizedText } from './DesktopHostActions';

interface DesktopMarketDetailVersion {
  version: string;
  spec: string;
  registry: string;
  source?: Object;
  compatible: boolean;
  exempted: boolean;
  runtime: string;
  requiredRuntime: string;
  update: boolean;
}

function marketVersions(entry?: Object): DesktopMarketDetailVersion[] {
  const versions: DesktopMarketDetailVersion[] = [];
  const seen = new Set<string>();
  for (const row of getArray(entry, 'versions') ?? []) {
    const version = getString(row, 'version') ?? '';
    if (!version || seen.has(version)) { continue; }
    seen.add(version);
    const install = getRecord(row, 'install');
    const compatibility = getRecord(row, 'compatibility');
    versions.push({ version: version, spec: getString(install, 'spec') ?? '', registry: getString(install, 'registry') ?? '',
      source: getRecord(row, 'source'), compatible: getBoolean(compatibility, 'compatible') === true,
      exempted: getBoolean(compatibility, 'exempted') === true, runtime: getString(compatibility, 'runtimeVersion') ?? '',
      requiredRuntime: getString(getRecord(compatibility, 'requirements'), 'engines.dsh') ?? '',
      update: getBoolean(row, 'update') === true });
  }
  return versions;
}

function marketInstallable(version: DesktopMarketDetailVersion): boolean {
  return !!version.spec && (version.compatible || version.exempted);
}

@Component
export struct DesktopPluginMarketDetail {
  host?: DesktopHostActions;
  @Prop @Watch('documentChanged') source: string = '';
  @Prop @Watch('documentChanged') entry?: Object = undefined;
  @Prop @Watch('documentChanged') localePreference: string = 'system';
  @Prop busy: boolean = false;
  @Prop installed: boolean = false;
  @Prop installedVersion: string = '';
  onBack: () => void = (): void => {};
  onOpenInstalled: (name: string) => void = (_name: string): void => {};
  onInstall: (spec: string, registry: string) => void = (_spec: string, _registry: string): void => {};
  onUpdate: (name: string, title: string, from: string, to: string, spec: string) => void =
    (_name: string, _title: string, _from: string, _to: string, _spec: string): void => {};

  @State private markdown: string = '';
  @State private problem: string = '';
  @State private loading: boolean = false;
  private active: boolean = false;
  private epoch: number = 0;
  private documentKey: string = '';

  aboutToAppear(): void { this.active = true; this.documentChanged(); }

  aboutToDisappear(): void {
    this.active = false;
    this.epoch++;
    this.documentKey = '';
  }

  private language(): string {
    const language = this.localePreference === 'system' || !this.localePreference ?
      i18n.System.getSystemLanguage() : this.localePreference;
    return language.replace(/_/g, '-') || 'en-US';
  }

  private localized(field: string): string {
    const language = this.language();
    const map = getRecord(this.entry, field);
    return getString(this.entry, field) || getString(map, language) || getString(map, language.split('-')[0]) ||
      desktopLocalizedText(this.entry, field);
  }

  private name(): string { return getString(this.entry, 'name') ?? ''; }

  private title(): string { return this.localized('title') || this.name(); }

  private isInstalled(): boolean {
    const status = getString(getRecord(this.entry, 'installation'), 'status');
    return this.installed || (!!status && status !== 'not-installed');
  }

  private currentVersion(): string {
    return this.installedVersion || getString(getRecord(this.entry, 'installation'), 'installedVersion') || '';
  }

  private presentedVersion(versions: DesktopMarketDetailVersion[]): DesktopMarketDetailVersion | undefined {
    const preferred = getString(this.entry, 'defaultVersion');
    return versions.find((row: DesktopMarketDetailVersion): boolean => row.version === preferred) ?? versions[0];
  }

  private documentChanged(): void { if (this.active) { this.readDocument(false); } }

  private async readDocument(refresh: boolean): Promise<void> {
    const name = this.name();
    const source = this.source;
    const version = this.presentedVersion(marketVersions(this.entry))?.version ?? '';
    const language = this.language();
    const key = JSON.stringify([source, name, version, language]);
    if (!refresh && this.documentKey === key) { return; }
    this.documentKey = key;
    const epoch = ++this.epoch;
    this.markdown = '';
    this.problem = '';
    this.loading = false;
    if (!this.active || !source || !name || !version) { return; }
    if (this.host === undefined) { this.problem = '工作区尚未连接'; return; }
    this.loading = true;
    const options: Record<string, Object> = refresh ? { 'refresh': true } : {};
    const result = await this.host.call('pluginMarket/readEntryDetail', {
      'url': source, 'name': name, 'version': version, 'language': language, 'options': options
    });
    if (!this.active || epoch !== this.epoch) { return; }
    this.loading = false;
    if (!result.ok) {
      this.problem = desktopHostProblem(result) || '无法读取插件说明';
    } else if (getString(result.value, 'status') === 'found') {
      this.markdown = getString(result.value, 'markdown') ?? '';
    }
  }

  private updateAllowed(version: DesktopMarketDetailVersion): boolean {
    return this.isInstalled() && !!this.currentVersion() && version.version !== this.currentVersion() &&
      version.update && marketInstallable(version);
  }

  private versionCaption(version: DesktopMarketDetailVersion): string {
    const notes: string[] = [];
    if (version.version === getString(this.entry, 'defaultVersion')) { notes.push('默认版本'); }
    if (version.version === this.currentVersion()) { notes.push('已安装'); }
    if (!version.compatible) {
      if (version.exempted) { notes.push('已获兼容性豁免'); }
      else if (version.requiredRuntime && version.runtime) {
        notes.push(`要求 DSH ${version.requiredRuntime}，当前 ${version.runtime}`);
      } else { notes.push('与当前运行环境不兼容'); }
    }
    return notes.join(' · ');
  }

  @Builder
  private Version(row: DesktopMarketDetailVersion) {
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Text(row.version).fontSize(14).fontWeight(FontWeight.Medium)
        if (this.versionCaption(row)) {
          Text(this.versionCaption(row)).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (this.updateAllowed(row)) {
        Button('更新', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginMarketDetailUpdate-' + row.version)
          .enabled(!this.busy)
          .onClick((): void => this.onUpdate(this.name(), this.title(), this.currentVersion(), row.version, row.spec))
      } else if (!this.isInstalled() && marketInstallable(row)) {
        Button('安装', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginMarketDetailInstall-' + row.version)
          .enabled(!this.busy).onClick((): void => this.onInstall(row.spec, row.registry))
      }
    }.key('desktopPluginMarketDetailVersion-' + row.version).width('100%').padding(10).borderRadius(10)
      .backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private Fact(label: string, value: string, link: boolean = false) {
    if (value) {
      Row({ space: 8 }) {
        Text(label).fontSize(12).fontColor($r('sys.color.font_secondary'))
        if (link && /^https?:\/\//i.test(value)) {
          Button(value, { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).layoutWeight(1)
            .onClick((): void => { openExternalUrl(value); })
        } else {
          Text(value).fontSize(12).layoutWeight(1).copyOption(CopyOptions.LocalDevice)
        }
      }.width('100%').alignItems(VerticalAlign.Top)
    }
  }

  @Builder
  private SourceFacts(version: DesktopMarketDetailVersion | undefined) {
    if (version?.source !== undefined && getString(version.source, 'type') === 'npm') {
      this.Fact('包名', this.name() + '@' + version.version)
      this.Fact('安装仓库', getString(version.source, 'registry') ?? '')
    } else if (version?.source !== undefined) {
      this.Fact('仓库', getString(version.source, 'url') ?? '', true)
      this.Fact('提交', getString(version.source, 'commit') ?? '')
      this.Fact('目录', getString(version.source, 'path') ?? '')
    }
  }

  build() {
    Column({ space: 12 }) {
      Button('返回插件市场', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginMarketDetailBack')
        .onClick(this.onBack)
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.title()).key('desktopPluginMarketDetailTitle').fontSize(22).fontWeight(FontWeight.Medium)
          if (this.title() !== this.name()) {
            Text(this.name()).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.isInstalled()) {
          Button('查看已安装插件', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginMarketDetailInstalled')
            .enabled(!this.busy).onClick((): void => this.onOpenInstalled(this.name()))
        }
      }.width('100%')
      if (this.localized('description')) { Text(this.localized('description')).fontSize(14) }
      if (this.loading) {
        LoadingProgress().key('desktopPluginMarketDetailLoading').width(22).height(22)
      } else if (this.problem) {
        Text(this.problem).fontSize(13).fontColor($r('app.color.workspace_status_error'))
        Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginMarketDetailRetry')
          .onClick((): void => { this.readDocument(true); })
      } else if (this.markdown) {
        MarkdownRenderer({ text: this.markdown }).key('desktopPluginMarketDetailMarkdown')
      }
      if (marketVersions(this.entry).length > 0) {
        Text('版本').fontSize(17).fontWeight(FontWeight.Medium)
        ForEach(marketVersions(this.entry), (row: DesktopMarketDetailVersion): void => {
          this.Version(row)
        }, (row: DesktopMarketDetailVersion): string =>
          `${row.version}:${row.spec}:${row.registry}:${row.compatible}:${row.exempted}:${row.runtime}:${row.requiredRuntime}:${row.update}`)
      }
      Text('来源').fontSize(17).fontWeight(FontWeight.Medium)
      this.Fact('作者', getString(this.entry, 'author') ?? '')
      this.Fact('主页', getString(this.entry, 'homepage') ?? '', true)
      this.Fact('源码', getString(getRecord(this.entry, 'repository'), 'url') ?? '', true)
      this.SourceFacts(this.presentedVersion(marketVersions(this.entry)))
      this.Fact('市场索引', this.source)
    }.key('desktopPluginMarketDetail').width('100%').alignItems(HorizontalAlign.Start)
  }
}
