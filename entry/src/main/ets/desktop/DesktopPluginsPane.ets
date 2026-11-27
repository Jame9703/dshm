import { getArray, getBoolean, getNumber, getRecord, getString } from 'connection';
import type { RpcResult } from 'connection';
import { dialogMaterial } from 'platform';
import { DesktopHostActions, desktopHostItems, desktopHostProblem, desktopLocalizedText } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopPluginSettings } from './DesktopPluginSettings';
import { DesktopPluginInstall } from './DesktopPluginInstall';
import { DesktopPluginInstallDialog } from './DesktopPluginInstallDialog';
import { MarkdownRenderer } from '../view/MarkdownRenderer';

const MARKET_BUNDLE: string = '@deepseek-ai/dsh-experimental-plugin-market-bundle';

interface DesktopPluginRow {
  id: string;
  title: string;
  description: string;
  enabled: boolean;
  toggle: boolean;
  removable: boolean;
  update: boolean;
  installSpec: string;
}

interface DesktopMarketSource {
  url: string;
  title: string;
}

function pluginRows(result: RpcResult, bundle: boolean): DesktopPluginRow[] {
  const rows: DesktopPluginRow[] = [];
  for (const value of desktopHostItems(result)) {
      const id = getString(value, bundle ? 'name' : 'entryId') ?? '';
      const enabled = getBoolean(value, 'enabled') === true;
      const optional = getBoolean(value, 'optional') === true;
      const installed = getBoolean(value, 'installed') === true;
      if (id.length === 0 || (bundle && !enabled && !optional && !installed &&
        getBoolean(value, 'listedByDefault') !== true)) {
        continue;
      }
      const target = getRecord(value, 'installTarget');
      rows.push({
        id: id,
        title: bundle ? id : getString(value, 'moduleName') ?? id,
        description: getString(value, bundle ? 'version' : 'phase') ?? '',
        enabled: enabled,
        toggle: !getString(value, 'readOnlyReason') && (bundle ?
          enabled || optional || installed : !!getString(value, 'patchId')),
        removable: bundle && getBoolean(value, 'removable') === true,
        update: bundle && getString(value, 'update') === 'registry',
        installSpec: getString(target, 'spec') ?? ''
      });
  }
  return rows;
}

@Component
export struct DesktopPluginsPane {
  host?: DesktopHostActions;
  @ObjectLink installer: DesktopPluginInstall;
  @Prop @Watch('requestedBundleChanged') requestedBundle: string = '';
  @Prop requestedTitle: string = '';
  @Prop requestedDescription: string = '';
  onWeb: () => void = (): void => {};
  @State private detailName: string = '';
  @State private detailText: string = '';
  @State private detailError: string = '';
  @State private detailLoading: boolean = false;
  @State private tab: string = 'bundles';
  @State private settingsVisited: boolean = false;
  @State private bundles: DesktopPluginRow[] = [];
  @State private plugins: DesktopPluginRow[] = [];
  @State private sources: DesktopMarketSource[] = [];
  @State private source: string = '';
  @State private sourceInput: string = '';
  @State private editSources: boolean = false;
  @State private marketError: string = '';
  @State private query: string = '';
  @State private nextOffset: number = -1;
  @State private fetchedAt: number = 0;
  @State private market: Object[] = [];
  @State private status: string = '';
  @State private catalogError: string = '';
  @State private catalogBusy: boolean = false;
  @State private paneWidth: number = 500;
  @State private busy: boolean = false;
  @State private versionOwner: string = '';
  @State private versions: string[] = [];
  private active: boolean = false;
  private detailRead: number = 0;
  private refreshAgain: boolean = false;
  private stopCatalog?: () => void;
  private installDialog: number = -1;
  private installOpening: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.stopCatalog = this.installer.watchCatalog((): void => { this.refresh(); });
    this.refresh();
    this.requestedBundleChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.stopCatalog?.();
    this.stopCatalog = undefined;
    this.closeInstall();
  }

  private requestedBundleChanged(): void {
    if (this.requestedBundle) { this.openBundle(this.requestedBundle); }
    else { this.closeBundle(); }
  }

  private closeBundle(): void {
    this.detailRead++;
    this.detailName = '';
  }

  private async openBundle(name: string): Promise<void> {
    this.tab = 'bundles';
    this.detailName = name;
    this.detailText = '';
    this.detailError = '';
    this.detailLoading = true;
    const version = ++this.detailRead;
    const result = await this.host?.call('pluginManager/readBundleDetail', { 'name': name, 'language': 'zh-CN' });
    if (!this.active || version !== this.detailRead) { return; }
    this.detailLoading = false;
    if (!result?.ok) { this.detailError = result?.error?.message || '无法读取插件详情'; }
    else if (getString(result.value, 'status') === 'found') { this.detailText = getString(result.value, 'markdown') ?? ''; }
  }

  private async refresh(): Promise<void> {
    const host = this.host;
    if (host === undefined || !this.active) { return; }
    if (this.catalogBusy) { this.refreshAgain = true; return; }
    this.catalogBusy = true;
    do {
      this.refreshAgain = false;
      await this.loadCatalog(host);
    } while (this.active && this.refreshAgain);
    this.catalogBusy = false;
  }

  private async loadCatalog(host: DesktopHostActions): Promise<void> {
    const results = await Promise.all([
      host.call('pluginManager/listBundles'),
      host.call('pluginManager/listPlugins'),
      host.call('pluginMarket/listIndexes')
    ]);
    if (!this.active) {
      return;
    }
    this.bundles = pluginRows(results[0], true);
    this.plugins = pluginRows(results[1], false);
    this.marketError = desktopHostProblem(results[2]);
    if (results[2].ok) {
      const sources: DesktopMarketSource[] = [];
      for (const item of desktopHostItems(results[2])) {
        const url = getString(item, 'url') ?? '';
        if (url.length > 0) {
          sources.push({ url: url, title: desktopLocalizedText(item, 'title') || url });
        }
      }
      this.sources = sources;
      if (!sources.some((row: DesktopMarketSource): boolean => row.url === this.source)) {
        this.source = sources[0]?.url ?? '';
        this.market = [];
        this.nextOffset = -1;
      }
    }
    this.catalogError = desktopHostProblem(results[0]) || desktopHostProblem(results[1]);
  }

  private async saveSources(urls: string[]): Promise<void> {
    if (this.host === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.host.call('pluginMarket/setIndexes', { 'urls': urls });
    if (!this.active) {
      return;
    }
    this.busy = false;
    const error = desktopHostProblem(result);
    if (error.length > 0) {
      this.status = error;
      return;
    }
    this.sourceInput = '';
    await this.refresh();
  }

  private addSource(): void {
    const url = this.sourceInput.trim();
    if (!(/^(?:https?:\/\/|git\+)/i.test(url)) || this.sources.some((row: DesktopMarketSource): boolean => row.url === url)) {
      this.status = '请填写尚未添加的 HTTP、HTTPS 或 Git 索引地址';
      return;
    }
    this.saveSources([...this.sources.map((row: DesktopMarketSource): string => row.url), url]);
  }

  private async searchMarket(append: boolean): Promise<void> {
    if (this.host === undefined || this.busy || this.source.length === 0 || (append && this.nextOffset < 0)) {
      return;
    }
    this.busy = true;
    const sort: Record<string, Object> = { 'kind': 'relevance' };
    const query: Record<string, Object> = {
      'text': this.query.trim(), 'offset': append ? this.nextOffset : 0, 'limit': 30, 'sort': sort
    };
    if (append) {
      query['fetchedAt'] = this.fetchedAt;
    }
    const result = await this.host.call('pluginMarket/search', { 'url': this.source, 'query': query });
    if (!this.active) {
      return;
    }
    this.busy = false;
    this.status = desktopHostProblem(result);
    if (result.ok) {
      const entries = getArray(result.value, 'entries') ?? [];
      const fetchedAt = getNumber(result.value, 'fetchedAt') ?? 0;
      if (append && fetchedAt !== this.fetchedAt) {
        this.status = '市场目录已变化，请重新搜索';
        this.nextOffset = -1;
        return;
      }
      this.market = append ? [...this.market, ...entries] : entries;
      this.fetchedAt = fetchedAt;
      this.nextOffset = getNumber(result.value, 'nextOffset') ?? -1;
    }
  }

  private async mutate(endpoint: string, payload: Record<string, Object>): Promise<void> {
    if (this.host === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.status = '正在等待宿主处理…';
    const result = await this.host.call(endpoint, payload, 180000);
    if (!this.active) {
      return;
    }
    this.busy = false;
    const value = getRecord(result.value, 'result') ?? result.value;
    const outcome: RpcResult = { ok: result.ok, value: value, error: result.error };
    const problem = desktopHostProblem(outcome);
    await this.refresh();
    this.status = problem || (getString(value, 'application') === 'restart-required' ?
      '已保存，重启核心后生效' : '操作已完成');
  }

  @Builder
  private InstallDialog() {
    DesktopPluginInstallDialog({ installer: this.installer, onClose: (): void => { this.closeInstall(); } })
  }

  private async openInstall(spec: string = '', registry: string = ''): Promise<void> {
    if (!this.active || this.installOpening || this.installDialog >= 0) { return; }
    this.installOpening = true;
    this.installer.offer(spec, registry);
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({ builder: (): void => { this.InstallDialog(); },
        alignment: DialogAlignment.Center, width: Math.max(240, Math.min(496, this.paneWidth - 28)),
        isModal: true, autoCancel: true, cornerRadius: 22, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          this.installDialog = -1;
          this.installer.closeInspection();
        }
      });
      if (this.active) { this.installDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.active) { prompt.showToast({ message: $r('app.string.desktop_plugin_install_open_failed') }); }
    } finally {
      this.installOpening = false;
    }
  }

  private closeInstall(): void {
    if (this.installDialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(this.installDialog); }
  }

  private async listVersions(row: DesktopPluginRow): Promise<void> {
    if (this.host === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.host.call('pluginManager/listVersions', { 'name': row.id });
    if (!this.active) {
      return;
    }
    this.busy = false;
    this.versionOwner = row.id;
    this.versions = (getArray(result.value, 'versions') ?? [])
      .filter((value: Object): boolean => getBoolean(value, 'bundle') === true &&
        getRecord(value, 'incompatible') === undefined)
      .map((value: Object): string => getString(value, 'version') ?? '')
      .filter((value: string): boolean => value.length > 0);
    this.status = desktopHostProblem(result) || getString(result.value, 'reason') ||
      (this.versions.length === 0 ? '没有可用更新' : '');
  }

  private confirm(title: string, message: string, action: () => void): void {
    this.getUIContext().getPromptAction().showDialog({
      title: title, message: message,
      buttons: [{ 'text': '取消', color: '#777777' }, { 'text': title, color: '#3165D7' }]
    }).then((result): void => {
      if (result.index === 1 && this.active) {
        action();
      }
    }).catch((): void => {});
  }

  private rowActions(row: DesktopPluginRow): MenuElement[] {
    const result: MenuElement[] = [];
    if (row.toggle) {
      result.push({ value: row.enabled ? '停用' : '启用', action: (): void => {
        if (this.tab === 'bundles') {
          this.mutate('pluginManager/setBundleEnabled', { 'name': row.id, 'enabled': !row.enabled });
        } else {
          this.mutate('pluginManager/setPluginEnabled', { 'id': row.id, 'enabled': !row.enabled });
        }
      } });
    }
    if (row.installSpec.length > 0) {
      result.push({ value: '安装', action: (): void => { this.openInstall(row.installSpec); } });
    }
    if (row.update) {
      result.push({ value: '检查更新', action: (): void => { this.listVersions(row); } });
    }
    if (row.removable) {
      result.push({ value: '移除', action: (): void => {
        this.confirm('移除插件包', row.title, (): void => {
          this.mutate('pluginManager/removeBundle', { 'name': row.id });
        });
      } });
    }
    return result;
  }

  private marketActions(entry: Object): MenuElement[] {
    return (getArray(entry, 'versions') ?? []).flatMap((row: Object): MenuElement[] => {
      const install = getRecord(row, 'install');
      const compatibility = getRecord(row, 'compatibility');
      const spec = getString(install, 'spec') ?? '';
      const version = getString(row, 'version') ?? '';
      const registry = getString(install, 'registry') ?? '';
      if (spec.length === 0 || version.length === 0 ||
        (getBoolean(compatibility, 'compatible') !== true && getBoolean(compatibility, 'exempted') !== true)) {
        return [];
      }
      return [{ value: version, action: (): void => { this.openInstall(spec, registry); } }];
    });
  }

  @Builder
  private PluginRow(row: DesktopPluginRow, navigable: boolean = false) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(row.title).fontSize(15).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text([row.enabled ? '已启用' : '未启用', row.description].filter((item: string): boolean =>
          item.length > 0).join(' · ')).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (navigable) {
        Button('查看详情', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.openBundle(row.id); })
      }
      if (this.versionOwner === row.id && this.versions.length > 0) {
        Button('选择更新版本', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(!this.busy)
          .bindMenu(this.versions.map((version: string): MenuElement => {
            return { value: version, action: (): void => {
              this.confirm('更新插件', row.title + ' → ' + version, (): void => {
                this.mutate('pluginManager/updateBundle', { 'name': row.id, 'version': version });
              });
            } };
          }), desktopMenuOptions(Placement.BottomRight))
      }
      if (this.rowActions(row).length > 0) {
        Button('更多', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .accessibilityText('管理 ' + row.title).enabled(!this.busy)
          .bindMenu(this.rowActions(row), desktopMenuOptions(Placement.BottomRight))
      }
    }
    .width('100%').constraintSize({ minHeight: 60 }).padding(10)
    .borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private BundleDetail() {
    Column({ space: 12 }) {
      Button('返回插件包', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopPluginDetailBack')
        .onClick((): void => { this.closeBundle(); })
      Text((this.detailName === this.requestedBundle ? this.requestedTitle : '') || this.detailName)
        .key('desktopPluginDetailTitle').fontSize(22).fontWeight(FontWeight.Medium)
      if (this.detailName === this.requestedBundle && this.requestedDescription) {
        Text(this.requestedDescription).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      ForEach(this.bundles.filter((row: DesktopPluginRow): boolean => row.id === this.detailName), (row: DesktopPluginRow): void => {
        this.PluginRow(row)
      }, (row: DesktopPluginRow): string => JSON.stringify(row))
      if (this.detailLoading) {
        LoadingProgress().width(22).height(22)
      } else if (this.detailError) {
        Text(this.detailError).fontSize(13).fontColor($r('app.color.workspace_status_error'))
        Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.openBundle(this.detailName); })
      } else if (this.detailText) {
        MarkdownRenderer({ text: this.detailText })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private canEnableMarket(): boolean {
    return this.bundles.some((row: DesktopPluginRow): boolean =>
      row.id === MARKET_BUNDLE && row.toggle && !row.enabled);
  }

  @Builder
  private Discover() {
    Row({ space: 8 }) {
      Button(this.sources.find((row: DesktopMarketSource): boolean => row.url === this.source)?.title || '索引来源',
        { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(!this.busy && this.sources.length > 0)
        .bindMenu(this.sources.map((row: DesktopMarketSource): MenuElement => {
          return { value: row.title, action: (): void => {
            this.source = row.url;
            this.market = [];
            this.nextOffset = -1;
            this.searchMarket(false);
          } };
        }), desktopMenuOptions(Placement.BottomLeft))
      TextInput({ 'text': this.query, placeholder: '搜索市场插件' }).layoutWeight(1)
        .onChange((value: string): void => { this.query = value; })
        .onSubmit((): void => { this.searchMarket(false); })
      Button('搜索').enabled(!this.busy && this.source.length > 0).onClick((): void => { this.searchMarket(false); })
      Button('管理索引', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(this.marketError.length === 0 && !this.busy)
        .onClick((): void => { this.editSources = !this.editSources; })
    }
    .width('100%')
    if (this.marketError.length > 0) {
      if (this.canEnableMarket()) {
        Row({ space: 8 }) {
          Text('当前核心未启用插件市场').fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          Button('启用插件市场', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .onClick((): void => {
              this.mutate('pluginManager/setBundleEnabled', { 'name': MARKET_BUNDLE, 'enabled': true });
            })
        }
        .width('100%')
      } else {
        Text(this.marketError).fontColor($r('sys.color.warning'))
      }
    } else if (this.sources.length === 0 && !this.editSources) {
      Text('未配置可用的市场索引').fontColor($r('sys.color.font_secondary'))
    }
    if (this.editSources) {
      Row({ space: 8 }) {
        TextInput({ text: this.sourceInput, placeholder: '索引 URL' }).layoutWeight(1)
          .onChange((value: string): void => { this.sourceInput = value; })
        Button('添加索引').enabled(!this.busy && this.sourceInput.trim().length > 0)
          .onClick((): void => { this.addSource(); })
      }
      .width('100%')
      ForEach(this.sources, (row: DesktopMarketSource) => {
        Row({ space: 8 }) {
          Text(row.title).layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('移除索引', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .onClick((): void => {
              this.confirm('移除索引', row.url, (): void => {
                this.saveSources(this.sources.filter((source: DesktopMarketSource): boolean => source.url !== row.url)
                  .map((source: DesktopMarketSource): string => source.url));
              });
            })
        }
        .width('100%').padding(8)
      }, (row: DesktopMarketSource): string => row.url)
    }
    ForEach(this.market, (entry: Object) => {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(desktopLocalizedText(entry, 'title') || getString(entry, 'name') || '').fontSize(15)
          Text(desktopLocalizedText(entry, 'description')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.marketActions(entry).length > 0) {
          Button('选择版本', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .bindMenu(this.marketActions(entry), desktopMenuOptions(Placement.BottomRight))
        }
      }
      .width('100%').padding(10).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
    }, (entry: Object): string => getString(entry, 'name') ?? '')
    if (this.nextOffset >= 0) {
      Button('加载更多', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .onClick((): void => { this.searchMarket(true); })
    }
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('插件').fontSize(26).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy && !this.catalogBusy)
          .onClick((): void => { this.refresh(); })
        Button('在 WebUI 打开', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy).onClick(this.onWeb)
      }
      .width('100%')
      if (!this.detailName) {
        Row({ space: 8 }) {
          Button(this.tab === 'bundles' ? '插件包' : this.tab === 'entries' ? '运行中的插件' :
            this.tab === 'settings' ? '配置' : '插件市场',
            { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopPluginsView').enabled(!this.busy)
            .bindMenu([
              { value: '插件包', action: (): void => { this.tab = 'bundles'; } },
              { value: '运行中的插件', action: (): void => { this.tab = 'entries'; } },
              { value: '配置', action: (): void => { this.settingsVisited = true; this.tab = 'settings'; } },
              { value: '插件市场', action: (): void => {
                this.tab = 'market';
                if (this.market.length === 0) {
                  this.searchMarket(false);
                }
              } }
            ], desktopMenuOptions(Placement.BottomLeft))
          Blank()
          if (this.tab === 'bundles' || this.installer.phase !== 'idle') {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL }) {
              Row({ space: 6 }) {
                Image($r('app.media.dsh_reference_menu_plus')).width(16).height(16).supportSvg2(true)
                  .draggable(false).accessibilityLevel('no')
                Text(this.installer.phase === 'idle' ? $r('app.string.desktop_plugin_install_add') :
                  $r('app.string.desktop_plugin_install_task')).fontSize(14).fontColor($r('sys.color.font_primary'))
              }
            }.height(34).borderRadius(8).padding({ left: 10, right: 10 }).key('desktopPluginOpenInstall')
            .onClick((): void => { this.openInstall(); })
          }
          if (this.busy || this.catalogBusy) {
            LoadingProgress().width(24).height(24)
          }
        }.width('100%')
      }
      if (this.status || this.catalogError) {
        Text(this.status || this.catalogError).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
      }
      Scroll() {
        Column({ space: 8 }) {
          if (this.detailName) {
            this.BundleDetail()
          } else {
            if (this.settingsVisited) {
              DesktopPluginSettings({ host: this.host }).visibility(this.tab === 'settings' ? Visibility.Visible : Visibility.None)
            }
            if (this.tab === 'market') {
              this.Discover()
            } else if (this.tab !== 'settings') {
              ForEach(this.tab === 'bundles' ? this.bundles : this.plugins, (row: DesktopPluginRow) => {
                this.PluginRow(row, this.tab === 'bundles')
              }, (row: DesktopPluginRow): string => JSON.stringify(row))
              if (!this.busy && !this.catalogBusy && (this.tab === 'bundles' ? this.bundles.length : this.plugins.length) === 0) {
                Text('暂无插件').fontColor($r('sys.color.font_secondary'))
              }
            }
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').layoutWeight(1).align(Alignment.TopStart)
    }
    .padding(20).height('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
    .onAreaChange((_previous: Area, current: Area): void => { this.paneWidth = Number(current.width); })
  }
}
