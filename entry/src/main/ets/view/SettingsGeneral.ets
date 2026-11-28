/**
 * 设置 · 通用（P4-4：从 `SettingsPane` 拆出的第二个域组件）。
 *
 * ## 这一个域回答什么
 *
 * 官方 General 段的内容（矩阵 `settings-general` 行）：**用户面向的功能包设置**
 * （外观 / 语言 / 会话显示…）——由宿主按命名空间策展后传进来（白名单整组显示 +
 * "其他已修改项"归拢），以及**端侧的设备事实**（权限模式只读展示）。
 * 另外带上本地调试入口（连接诊断 + 协议往返验证，E96 合并）。
 *
 * ## 边界
 *
 *  · 设置分组与权限事实由宿主给；
 *  · 写入（改设置、恢复默认）由回调交回宿主 —— 组件不决定"写失败要不要提示"（回执由宿主统一显示）；
 *  · 行渲染复用 `SettingRow`（模型域也用同一份）。
 */

import { DesktopTranscriptPreferences, hasDesktopTranscriptPreferences, isDesktopTranscriptPreference }
  from '../desktop/DesktopTranscriptPreferences';
import { Fs, Radius, SettingGroup, SettingItem, Sp } from 'appstate';
import { SettingRow } from './SettingRow';
import { SettingsUsage } from './SettingsUsage';
import { DesktopShortcutSettingsRow } from '../desktop/DesktopShortcutDialog';
import { DesktopThemeSettings } from '../desktop/DesktopThemeSettings';
import { DESKTOP_THEME_NS } from '../desktop/DesktopTheme';
import { DesktopCodingToolsSnapshot, emptyDesktopCodingToolsSnapshot } from '../desktop/DesktopCodingTools';
import { getBoolean, getString } from 'connection';
import { SETTINGS_CONFLICT, SETTINGS_DESCRIBE_ENDPOINT } from 'dshcompat';
import { DesktopPermissionDefault } from '../desktop/DesktopPermissionDefault';
import { allowsDesktopPermissionDefault, DESKTOP_FULL_ACCESS_PRESET, desktopPermissionDefaultView, readDesktopGeneralHostDocuments,
  writeDesktopGeneralHostPreference } from '../desktop/DesktopGeneralHostPreferences';
import type { DesktopPermissionDefaultView } from '../desktop/DesktopGeneralHostPreferences';
import type { DesktopGeneralHostAccess } from '../desktop/DesktopGeneralHostPreferences';
import { readDesktopPluginDocument } from '../desktop/DesktopPluginSettingsModel';
import type { DesktopPluginDocument } from '../desktop/DesktopPluginSettingsModel';


/**
 * 模型目录按提供方分组后的一组（E96）。
 *
 * 【为什么要有这个类型】官方 Models 页以"提供方"为单位组织（密钥、端点、模型清单都挂它上面）；
 * 拉平成一个模型列表就看不出"这个模型要用哪把密钥"。
 */

/** 访问模式的中文名（官方译名，取自 `dsh-client-ui-permission-presets` 的 README） */
function permissionModeLabel(value: string): string {
  if (value === 'read-only') {
    return '仅可查看';
  }
  if (value === 'workspace-write') {
    return '工作区内修改';
  }
  if (value === 'danger-full-access') {
    return '完全权限';
  }
  return value;
}

@Component
export struct SettingsGeneral {

  /** 通用段的设置分组（宿主已按官方口径策展：白名单整组 + 其他已修改项） */
  @Prop groups: SettingGroup[] = [];
  /** 当前权限模式（只读展示：官方在 General 里给新会话默认，本仓端点还不支持切换） */
  @Prop permissionCurrent: string = '';
  /** 宿主给出的可选集合（只读展示） */
  @Prop permissionOptions: string[] = [];
  @Prop desktopShortcuts: boolean = false;
  @Prop codingTools: DesktopCodingToolsSnapshot = emptyDesktopCodingToolsSnapshot();
  settingsHost?: DesktopGeneralHostAccess;
  onOpenShortcuts: () => void = () => {};
  onCodingToolsChange: (enabled: boolean) => void = (_enabled: boolean): void => {};

  /** 打开本地调试（连接诊断 + 协议往返验证） */
  onOpenDiagnostics: () => void = () => {
  };
  /** 以下五个转给 `SettingRow` */
  onToggleSetting: (key: string, value: boolean) => void = () => {
  };
  onPickChoice: (key: string, current: string, selection?: string) => void = () => {
  };
  onEditText: (item: SettingItem) => void = () => {
  };
  onEditStruct: (item: SettingItem) => void = () => {
  };
  onResetSetting: (key: string) => void = () => {
  };

  @State private writable: boolean = false;
  @State private permissionServed: boolean = false;
  @State private permissionLoading: boolean = false;
  @State private permissionSaving: boolean = false;
  @State private permissionView?: DesktopPermissionDefaultView = undefined;
  @State private permissionProblem: ResourceStr = '';
  @State private uploadDocument?: DesktopPluginDocument = undefined;
  @State private uploadSaving: boolean = false;
  @State private uploadToggleEpoch: number = 0;
  private active: boolean = false;
  private loadEpoch: number = 0;

  aboutToAppear(): void {
    this.active = true;
    if (this.desktopShortcuts) { this.loadHostPreferences(); }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadEpoch++;
  }

  private async loadHostPreferences(): Promise<void> {
    const host = this.settingsHost;
    if (!this.active || host === undefined) { return; }
    const epoch = ++this.loadEpoch;
    this.permissionLoading = true;
    this.writable = false;
    try {
      const described = await host.call(SETTINGS_DESCRIBE_ENDPOINT);
      if (!this.active || epoch !== this.loadEpoch) { return; }
      const documents = readDesktopGeneralHostDocuments(described.ok ? described.value : undefined);
      this.writable = documents.writable;
      if (documents.uploads === undefined || documents.uploads.revision >= (this.uploadDocument?.revision ?? -1)) {
        this.uploadDocument = documents.uploads;
      }
      this.permissionServed = documents.permission !== undefined;
      if (documents.permission === undefined) { this.permissionView = undefined; return; }
      const catalog = await host.call('permissionPresets/catalog');
      if (!this.active || epoch !== this.loadEpoch) { return; }
      if (documents.permission.revision >= (this.permissionView?.document.revision ?? -1)) {
        this.permissionView = catalog.ok ? desktopPermissionDefaultView(documents.permission, catalog.value) : undefined;
      }
      if (this.permissionView === undefined) {
        this.permissionProblem = catalog.error?.message || $r('app.string.desktop_default_permission_unavailable');
      }
    } catch (_) {
      if (this.active && epoch === this.loadEpoch) {
        this.permissionProblem = $r('app.string.desktop_default_permission_unavailable');
      }
    } finally {
      if (epoch === this.loadEpoch) { this.permissionLoading = false; }
    }
  }

  private async savePermission(id: string, acknowledged: boolean): Promise<void> {
    const host = this.settingsHost;
    const view = this.permissionView;
    if (!this.active || host === undefined || view === undefined || !this.writable || this.permissionLoading ||
        this.permissionSaving || !allowsDesktopPermissionDefault(view, id, acknowledged)) { return; }
    this.permissionSaving = true;
    this.permissionProblem = '';
    try {
      if (id === DESKTOP_FULL_ACCESS_PRESET) {
        const authorization = await host.call(SETTINGS_DESCRIBE_ENDPOINT);
        if (!this.active) { return; }
        const current = readDesktopGeneralHostDocuments(authorization.ok ? authorization.value : undefined);
        if (!current.writable || current.permission === undefined) {
          this.writable = current.writable;
          this.permissionServed = current.permission !== undefined;
          this.permissionProblem = authorization.error?.message || $r('app.string.desktop_default_permission_unavailable');
          return;
        }
      }
      const catalog = await host.call('permissionPresets/catalog');
      if (!this.active || !this.writable) { return; }
      const fresh = catalog.ok ? desktopPermissionDefaultView(view.document, catalog.value) : undefined;
      if (!allowsDesktopPermissionDefault(fresh, id, acknowledged)) {
        this.permissionProblem = $r('app.string.desktop_default_permission_unavailable');
        await this.loadHostPreferences();
        return;
      }
      const result = await writeDesktopGeneralHostPreference(host, view.document, 'defaultPreset', id);
      if (!this.active) { return; }
      const accepted = result.ok ? readDesktopPluginDocument(result.value) : undefined;
      if (accepted?.id === view.document.id && accepted.revision >= view.document.revision &&
          getString(accepted.value, 'defaultPreset') === id) {
        if (accepted.revision >= (this.permissionView?.document.revision ?? -1)) {
          this.permissionView = desktopPermissionDefaultView(accepted, catalog.value);
        }
      } else {
        this.permissionProblem = result.error?.message || $r('app.string.desktop_general_preference_failed');
        if (result.error?.code === SETTINGS_CONFLICT || result.ok) { await this.loadHostPreferences(); }
      }
    } catch (_) {
      if (this.active) { this.permissionProblem = $r('app.string.desktop_general_preference_failed'); }
    } finally {
      if (this.active) { this.permissionSaving = false; }
    }
  }

  private async saveUpload(enabled: boolean): Promise<void> {
    const host = this.settingsHost;
    const document = this.uploadDocument;
    if (!this.active || host === undefined || document === undefined || !this.writable || this.uploadSaving ||
        enabled === getBoolean(document.value, 'enabled')) { return; }
    const prompt = this.getUIContext().getPromptAction();
    this.uploadSaving = true;
    this.uploadToggleEpoch++;
    let accepted = false;
    try {
      const result = await writeDesktopGeneralHostPreference(host, document, 'enabled', enabled);
      const saved = result.ok ? readDesktopPluginDocument(result.value) : undefined;
      if (saved?.id === document.id && saved.revision >= document.revision && getBoolean(saved.value, 'enabled') === enabled) {
        accepted = true;
        if (this.active && saved.revision >= (this.uploadDocument?.revision ?? -1)) { this.uploadDocument = saved; }
      } else if (this.active && (result.error?.code === SETTINGS_CONFLICT || result.ok)) {
        await this.loadHostPreferences();
      }
    } catch (_) {
      // Keep the accepted Host state and report the failed save.
    } finally {
      if (this.active) { this.uploadSaving = false; }
      try {
        prompt.showToast({ message: accepted ? $r('app.string.desktop_general_preference_saved') :
          $r('app.string.desktop_general_preference_failed') });
      } catch (_) {}
    }
  }

  @Builder
  private UploadPreference() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text($r('app.string.desktop_session_log_upload_title')).fontSize(14).width('100%')
        Text($r('app.string.desktop_session_log_upload_description')).fontSize(13).width('100%')
          .fontColor($r('sys.color.font_secondary'))
      }.layoutWeight(1)
      ForEach([this.uploadToggleEpoch], (_epoch: number): void => {
        Toggle({ type: ToggleType.Switch, isOn: getBoolean(this.uploadDocument?.value, 'enabled') === true })
          .key('desktopSessionLogUpload').accessibilityText($r('app.string.desktop_session_log_upload_title'))
          .enabled(this.writable && !this.uploadSaving).onChange((enabled: boolean): void => { this.saveUpload(enabled); })
      }, (epoch: number): string => epoch.toString())
    }.width('100%').constraintSize({ minHeight: 44 })
  }

  private themeItems(): SettingItem[] {
    if (!this.desktopShortcuts) { return []; }
    return this.groups.flatMap((group: SettingGroup): SettingItem[] =>
      group.items.filter((item: SettingItem): boolean => item.key.startsWith(DESKTOP_THEME_NS + '.')));
  }

  private otherGroups(): SettingGroup[] {
    const hasTheme = this.themeItems().length > 0;
    if (!this.desktopShortcuts && !hasTheme && !this.codingTools.available) { return this.groups; }
    return this.groups.map((group: SettingGroup): SettingGroup => ({ title: group.title,
      items: group.items.filter((item: SettingItem): boolean =>
        (!hasTheme || (!item.key.startsWith(DESKTOP_THEME_NS + '.') && item.key !== 'local.themeMode')) &&
        (!this.codingTools.available || item.key !== 'ui-settings.enabled') &&
        (!this.desktopShortcuts || (item.key !== 'permission.defaultPreset' && item.key !== 'session-log-deepseek.enabled')))
    })).filter((group: SettingGroup): boolean => group.items.length > 0);
  }

  // 【ArkUI 约束】组件的 build() 只能有一个根节点 ⇒ 多段内容包进 Column
  build() {
    Column({ space: Sp.L }) {
          if (this.themeItems().length > 0) { DesktopThemeSettings({ items: this.themeItems() }) }
          /* 用量统计（docs/178）：桌面卡片同源数据，应用内也能看四档 token 用量 */
          SettingsUsage()
          if (this.codingTools.available) { this.codingToolsRow() }
          if (this.desktopShortcuts) {
            DesktopShortcutSettingsRow({ onOpen: this.onOpenShortcuts })
          }
          /*
           * 【权限模式：只读说明，不给假档位（E116）】
           *
           * 官方在这三个标签下提供可切换的预设（仅可查看 / 工作区内修改 / 完全权限），
           * 但端侧**实测**：启用 `dsh-permission-presets` 会让整棵插件树启动失败——
           * 它需要 `shell` 服务，而 shell 只能由 bash/pwsh 沙箱提供，两者在鸿蒙上没有对应物
           * （无法创建进程，E15）。官方规则也写明"宿主没有权限组合时，选择器与设置行都不显示"。
           *
           * 于是这里既**不隐藏**（用户明确问过这三档，藏起来等于让他以为没有这个概念），
           * 也**不给可点的假档位**：只读地说明当前生效的是什么、另外两档为什么不可选。
           */
          if (this.desktopShortcuts && this.permissionServed) {
            DesktopPermissionDefault({ view: this.permissionView, writable: this.writable, loading: this.permissionLoading,
              saving: this.permissionSaving, problem: this.permissionProblem,
              onSelect: (id: string, acknowledged: boolean): void => { this.savePermission(id, acknowledged); } })
          } else if (!this.desktopShortcuts) {
          Column({ space: 2 }) {
            Row({ space: Sp.XS }) {
              Text('权限模式')
                .fontSize(Fs.BODY)
              Text(this.permissionCurrent.length > 0 ? '宿主报告' : '未报告')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(Radius.S)
                .backgroundColor($r('sys.color.background_primary'))
            }
            .width('100%')
            // E124：显示**宿主真正报告的**当前模式（此前这里是我写死的字符串）
            Text(this.permissionCurrent.length > 0
              ? `${permissionModeLabel(this.permissionCurrent)}（${this.permissionCurrent}）`
              : '宿主暂未报告当前访问模式')
              .fontSize(Fs.SECONDARY)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
            if (this.permissionOptions.length > 0) {
              Text(`宿主给出的可选集合：${this.permissionOptions.map((v: string) => permissionModeLabel(v)).join(' / ')}`)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            }
            Text('端侧暂不可切换：把这几档捆绑成可切换预设的插件需要 shell 服务，而鸿蒙不允许应用创建进程（E15）。这里显示的是宿主当前生效的访问模式。')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
          .width('100%')
          .padding(Sp.M)
          .borderRadius(Radius.M)
          .backgroundColor($r('sys.color.background_secondary'))
          }

          ForEach(this.otherGroups(), (group: SettingGroup) => {
            Column({ space: Sp.XS }) {
              Text(group.title)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
              if (this.desktopShortcuts && group.title === 'ui-chat' && hasDesktopTranscriptPreferences(group.items)) {
                DesktopTranscriptPreferences({ items: group.items, onPickChoice: this.onPickChoice })
              }
              ForEach(group.items, (item: SettingItem) => {
                if (!this.desktopShortcuts || group.title !== 'ui-chat' || !hasDesktopTranscriptPreferences(group.items) ||
                    !isDesktopTranscriptPreference(item.key)) {
                  SettingRow({
                      item: item,
                      onToggleSetting: (key: string, value: boolean) => {
                        this.onToggleSetting(key, value);
                      },
                      onPickChoice: (key: string, current: string, selection?: string) => {
                        this.onPickChoice(key, current, selection);
                      },
                      onEditText: (it: SettingItem) => {
                        this.onEditText(it);
                      },
                      onEditStruct: (it: SettingItem) => {
                        this.onEditStruct(it);
                      },
                      onResetSetting: (key: string) => {
                        this.onResetSetting(key);
                      }
                    })
                }
              }, (item: SettingItem) => item.key)
            }
            .width('100%')
          }, (group: SettingGroup): string => JSON.stringify(group))

          if (this.desktopShortcuts && this.uploadDocument !== undefined) { this.UploadPreference() }
          this.diagnosticsEntry()
    }
    .width('100%')
  }

  @Builder
  private codingToolsRow() {
    Row({ space: Sp.M }) {
      Column({ space: 4 }) {
        Text($r('app.string.desktop_coding_tools_title')).fontSize(Fs.BODY).width('100%')
        Text($r('app.string.desktop_coding_tools_description')).fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary')).width('100%')
        if (this.codingTools.error.length > 0) {
          Text($r('app.string.desktop_coding_tools_save_failed')).key('desktopCodingToolsError')
            .fontSize(Fs.CAPTION).fontColor($r('sys.color.warning')).width('100%')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.codingTools.enabled })
        .key('desktopCodingToolsSwitch').enabled(this.codingTools.writable && !this.codingTools.busy)
        .accessibilityText($r('app.string.desktop_coding_tools_title'))
        .accessibilityDescription($r('app.string.desktop_coding_tools_description'))
        .onChange((enabled: boolean): void => {
          if (this.codingTools.writable && !this.codingTools.busy && enabled !== this.codingTools.enabled) {
            this.onCodingToolsChange(enabled);
          }
        })
    }.key('desktopCodingToolsRow').width('100%').padding(Sp.M).borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  diagnosticsEntry() {
    Row({ space: Sp.S }) {
      SymbolGlyph($r('sys.symbol.bell')).fontSize(16)   // token-exempt: 行内图标尺寸（搬迁不改视觉）
        .fontColor([$r('sys.color.brand')])
      Column({ space: 2 }) {
        // 原「连接诊断」与「POC 协议验证」合并（E96）：它们都在回答"这台设备上的核心通不通"，
        // 一个给结论、一个给逐步证据；进同一个页面就能从结论下钻到证据。
        Text('本地调试')
          .fontSize(Fs.BODY)
          .width('100%')
        Text('连接诊断（五项判定）+ 协议往返验证（token → cookie → /api → WS 逐步证据）')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      .layoutWeight(1)
      Text('进入')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .onClick(() => {
      this.onOpenDiagnostics();


    })
  }
}
