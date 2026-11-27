import { getBoolean, getField, getRecord, getString } from 'connection';
import { CREDENTIALS_DESCRIBE_ENDPOINT, CREDENTIALS_SET_ENDPOINT, SETTINGS_CONFLICT, SETTINGS_DESCRIBE_ENDPOINT,
  SETTINGS_MUTATE_ENDPOINT } from 'dshcompat';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { AGENT_LOOP_SETTINGS, BASH_SETTINGS, desktopPluginBillingLocked, desktopPluginField, desktopPluginPathOps,
  desktopPluginPositiveInteger, desktopWebProviders, PWSH_SETTINGS, readDesktopPluginConfiguration, readDesktopPluginDocument, WEB_API_SETTINGS,
  WEB_FETCH_API, WEB_LEGACY_SETTINGS, WEB_SEARCH_API, WEB_SEARCH_LEGACY, WEB_SETTINGS } from './DesktopPluginSettingsModel';
import type { DesktopPluginConfiguration, DesktopPluginDocument, DesktopPluginEdit, DesktopWebProvider } from './DesktopPluginSettingsModel';

const WEB_SCOPE: string[] = [WEB_API_SETTINGS, WEB_LEGACY_SETTINGS, WEB_SETTINGS];
const SEARCH: string = 'searchProvider';
const FETCH: string = 'fetchProvider';

@Component
export struct DesktopPluginSettings {
  host?: DesktopHostActions;
  @State private configuration: DesktopPluginConfiguration = { writable: false, documents: [] };
  @State private edits: DesktopPluginEdit[] = [];
  @State private providers?: Object = undefined;
  @State private keyDraft: string = '';
  @State private keyRef: string = '';
  @State private keyStatus: string = '';
  @State private keyWritable: boolean = false;
  @State private reading: boolean = false;
  @State private saving: boolean = false;
  @State private problem: string = '';
  @State private providerFailure: boolean = false;
  private active: boolean = false;
  private credentialRead: number = 0;

  aboutToAppear(): void { this.active = true; this.load(); }

  aboutToDisappear(): void {
    this.active = false;
    this.credentialRead++;
    this.keyDraft = '';
  }

  private document(namespace: string): DesktopPluginDocument | undefined {
    return this.configuration.documents.find((row: DesktopPluginDocument): boolean => row.id === namespace);
  }

  private foundEdit(namespace: string, field: string): DesktopPluginEdit | undefined {
    return this.edits.find((edit: DesktopPluginEdit): boolean => edit.namespace === namespace && edit.field === field);
  }

  private field(namespace: string, name: string): string {
    const document = this.document(namespace);
    const edit = this.foundEdit(namespace, name);
    if (edit === undefined) { return desktopPluginField(document, name); }
    if (edit.value !== undefined) { return String(edit.value); }
    const base = getField(document?.base, name);
    return typeof base === 'string' || typeof base === 'number' ? String(base) : '';
  }

  private overridden(namespace: string, field: string): boolean {
    const edit = this.foundEdit(namespace, field);
    return edit !== undefined ? edit.value !== undefined : getField(this.document(namespace)?.user, field) !== undefined;
  }

  private stage(namespace: string, field: string, value?: Object): void {
    const next = this.edits.filter((edit: DesktopPluginEdit): boolean => edit.namespace !== namespace || edit.field !== field);
    const document = this.document(namespace);
    const changed = value === undefined ? getField(document?.user, field) !== undefined :
      String(value) !== desktopPluginField(document, field);
    if (changed) { next.push({ namespace: namespace, field: field, value: value }); }
    this.edits = next;
  }

  private choose(namespace: string, field: string, value: string, fallback: string = ''): void {
    const base = getString(this.document(namespace)?.base, field) ?? fallback;
    this.stage(namespace, field, value && value !== base ? value : undefined);
    if (field === SEARCH) { this.loadCredential(); }
  }

  private async readConfiguration(): Promise<boolean> {
    const result = await this.host?.call(SETTINGS_DESCRIBE_ENDPOINT);
    if (!this.active) { return false; }
    if (result?.ok !== true) {
      this.problem = result === undefined ? '工作区尚未连接' : desktopHostProblem(result);
      this.configuration = { writable: false, documents: this.configuration.documents };
      return false;
    }
    this.configuration = readDesktopPluginConfiguration(result.value);
    return true;
  }

  private async load(): Promise<void> {
    if (this.reading || this.saving) { return; }
    this.problem = '';
    this.reading = true;
    if (await this.readConfiguration()) {
      if (this.document(WEB_SETTINGS) !== undefined) {
        const result = await this.host?.call('web/listProviders');
        if (!this.active) { return; }
        this.providerFailure = result?.ok !== true;
        this.providers = result?.ok === true ? result.value : undefined;
      }
      this.loadCredential();
    }
    if (this.active) { this.reading = false; }
  }

  private legacyRef(): string {
    return this.field(WEB_SETTINGS, SEARCH) === WEB_SEARCH_LEGACY && this.document(WEB_LEGACY_SETTINGS) !== undefined ?
      desktopPluginField(this.document(WEB_LEGACY_SETTINGS), 'apiKeyEnv') || 'DEEPSEEK_API_KEY' : '';
  }

  private async loadCredential(): Promise<void> {
    const ref = this.legacyRef();
    if (ref !== this.keyRef) { this.keyDraft = ''; }
    this.keyRef = ref;
    this.keyWritable = false;
    this.keyStatus = '';
    const revision = ++this.credentialRead;
    if (!ref) { return; }
    const result = await this.host?.call(CREDENTIALS_DESCRIBE_ENDPOINT, { 'refs': [ref] });
    if (!this.active || revision !== this.credentialRead) { return; }
    if (result?.ok !== true) { this.keyStatus = '无法读取密钥状态'; return; }
    const view = getRecord(result.value, ref);
    this.keyStatus = getBoolean(view, 'configured') === true ? '已配置密钥' : '未配置密钥';
    this.keyWritable = getBoolean(view, 'writable') !== false;
  }

  private canEdit(): boolean {
    return this.configuration.writable && !this.reading && !this.saving;
  }

  private normalized(edit: DesktopPluginEdit): DesktopPluginEdit | undefined {
    const raw = edit.value;
    if (raw === undefined || edit.namespace === WEB_SETTINGS || edit.field.endsWith('Billing')) { return edit; }
    const text = String(raw).trim();
    if (edit.field === 'baseURL') {
      return text && !new RegExp('^https?://[^\\s/]+(?:/[^\\s]*)?$', 'i').test(text) ? undefined :
        { namespace: edit.namespace, field: edit.field, value: text || undefined };
    }
    const number = desktopPluginPositiveInteger(text, edit.field === 'count' ? 50 : Number.MAX_SAFE_INTEGER);
    return text && number === undefined ? undefined :
      { namespace: edit.namespace, field: edit.field, value: number };
  }

  private hasDraft(namespaces: string[]): boolean {
    return this.edits.some((edit: DesktopPluginEdit): boolean => namespaces.includes(edit.namespace)) ||
      (namespaces.includes(WEB_SETTINGS) && !!this.keyDraft.trim());
  }

  private async save(namespaces: string[]): Promise<void> {
    const host = this.host;
    if (host === undefined || !this.canEdit() || !this.hasDraft(namespaces)) { return; }
    const pending: DesktopPluginEdit[] = [];
    this.problem = '';
    for (const edit of this.edits.filter((item: DesktopPluginEdit): boolean => namespaces.includes(item.namespace))) {
      if (edit.field.endsWith('Billing') && desktopPluginBillingLocked(this.document(WEB_API_SETTINGS), edit.field.slice(0, -7))) {
        this.problem = '高级配置已覆盖计费方式，请恢复该项后再保存。';
        return;
      }
      const value = this.normalized(edit);
      if (value === undefined) {
        this.problem = edit.field === 'baseURL' ? '请填写有效的 HTTP 或 HTTPS 地址。' :
          (edit.field === 'count' ? '请输入 1 至 50 的整数。' : '请输入正整数。');
        return;
      }
      pending.push(value);
    }
    const key = namespaces.includes(WEB_SETTINGS) ? this.keyDraft.trim() : '';
    const keyRef = this.keyRef;
    if (key && (!this.keyWritable || !keyRef || keyRef !== this.legacyRef())) { return; }
    this.saving = true;
    let problem = '';
    let needsRefresh = false;
    let conflict = false;
    for (const ns of namespaces) {
      if (ns === WEB_SETTINGS && key) {
        const result = await host.call(CREDENTIALS_SET_ENDPOINT, { 'ref': keyRef, 'value': key });
        if (!this.active) { return; }
        if (!result.ok) { problem = '无法保存 API Key，请重试。'; break; }
        this.keyDraft = '';
      }
      const ops = desktopPluginPathOps(pending, ns);
      const document = this.document(ns);
      if (ops.length === 0) { continue; }
      if (document === undefined) { problem = '该插件配置已不可用，请刷新。'; break; }
      const result = await host.call(SETTINGS_MUTATE_ENDPOINT, { 'ns': ns, 'expectedRevision': document.revision, 'ops': ops });
      if (!this.active) { return; }
      if (!result.ok) {
        conflict = result.error?.code === SETTINGS_CONFLICT;
        needsRefresh = needsRefresh || conflict;
        problem = desktopHostProblem(result);
        break;
      }
      const saved = readDesktopPluginDocument(result.value);
      if (saved === undefined || saved.id !== ns) {
        needsRefresh = true;
      } else {
        const documents = this.configuration.documents.map((row: DesktopPluginDocument): DesktopPluginDocument =>
          row.id === ns ? saved : row);
        this.configuration = { writable: this.configuration.writable, documents: documents };
      }
      this.edits = this.edits.filter((edit: DesktopPluginEdit): boolean => edit.namespace !== ns);
    }
    const read = !needsRefresh || await this.readConfiguration();
    if (!this.active) { return; }
    this.saving = false;
    if (read) { this.problem = conflict ? '设置已在其他客户端修改，已读取最新值。请核对后再保存。' : problem || '已保存'; }
    if (namespaces.includes(WEB_SETTINGS)) { this.loadCredential(); }
  }

  private providerChoices(capability: string, field: string): MenuElement[] {
    const items: MenuElement[] = [{ value: '自动选择', action: (): void => { this.choose(WEB_SETTINGS, field, ''); } }];
    for (const row of desktopWebProviders(this.providers, capability)) {
      items.push({ value: row.title, action: (): void => { this.choose(WEB_SETTINGS, field, row.id); } });
    }
    return items;
  }

  private providerName(capability: string, field: string): string {
    const selected = this.field(WEB_SETTINGS, field);
    if (!selected) { return '自动选择'; }
    const provider = desktopWebProviders(this.providers, capability)
      .find((row: DesktopWebProvider): boolean => row.id === selected);
    return provider?.title ?? (this.providerFailure ? selected : selected + '（未加载）');
  }

  private billingChoices(field: string): MenuElement[] {
    return [
      { value: '自动选择', action: (): void => { this.choose(WEB_API_SETTINGS, field, 'auto', 'auto'); } },
      { value: '已登录的 DeepSeek 账号', action: (): void => { this.choose(WEB_API_SETTINGS, field, 'account', 'auto'); } },
      { value: 'DeepSeek API Key', action: (): void => { this.choose(WEB_API_SETTINGS, field, 'api-key', 'auto'); } }
    ];
  }

  private billingLabel(field: string): string {
    const value = this.field(WEB_API_SETTINGS, field);
    return value === 'account' ? '已登录的 DeepSeek 账号' : value === 'api-key' ? 'DeepSeek API Key' : '自动选择';
  }

  @Builder
  private Field(namespace: string, field: string, label: string, number: boolean = true) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(label).fontSize(14).layoutWeight(1)
        if (this.overridden(namespace, field)) {
          Button('恢复默认', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).enabled(this.canEdit())
            .key('pluginSettingReset-' + field).onClick((): void => { this.stage(namespace, field); })
        }
      }.width('100%')
      TextInput({ text: this.field(namespace, field), placeholder: '使用默认值' })
        .key('pluginSetting-' + field).width('100%').height(36).fontSize(14).enabled(this.canEdit())
        .type(number ? InputType.Number : InputType.Normal)
        .onChange((text: string): void => {
          if (text !== this.field(namespace, field)) { this.stage(namespace, field, text); }
        })
      if (this.foundEdit(namespace, field) !== undefined) {
        Text('当前生效：' + (desktopPluginField(this.document(namespace), field) || '默认值'))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Save(namespaces: string[], key: string) {
    Row() {
      Blank()
      Button(this.saving ? '保存中…' : '保存').key(key).enabled(this.canEdit() && this.hasDraft(namespaces))
        .onClick((): void => { this.save(namespaces); })
    }.width('100%')
  }

  @Builder
  private Provider(capability: string, field: string, title: string) {
    Column({ space: 5 }) {
      Text(title).fontSize(14).width('100%')
      Button(this.providerName(capability, field), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('pluginSetting-' + field).enabled(this.canEdit())
        .bindMenu(this.providerChoices(capability, field), desktopMenuOptions(Placement.BottomLeft))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Billing(capability: string) {
    Row({ space: 8 }) {
      Text('计费方式').fontSize(14).layoutWeight(1)
      if (desktopPluginBillingLocked(this.document(WEB_API_SETTINGS), capability)) {
        Text('已由高级配置覆盖').fontSize(12).fontColor($r('sys.color.font_secondary'))
        if (this.foundEdit(WEB_API_SETTINGS, capability + 'Billing') !== undefined) {
          Button('撤销修改', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
            this.stage(WEB_API_SETTINGS, capability + 'Billing',
              desktopPluginField(this.document(WEB_API_SETTINGS), capability + 'Billing'));
          })
        }
      }
      Button(this.billingLabel(capability + 'Billing'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('pluginSetting-' + capability + 'Billing')
        .enabled(this.canEdit() && !desktopPluginBillingLocked(this.document(WEB_API_SETTINGS), capability))
        .bindMenu(this.billingChoices(capability + 'Billing'), desktopMenuOptions(Placement.BottomRight))
    }.width('100%')
  }

  @Builder
  private WebCard() {
    Column({ space: 12 }) {
      Text('网页搜索与获取').fontSize(17).fontWeight(FontWeight.Medium).width('100%')
      if (this.providerFailure) {
        Text('无法读取提供方列表').fontSize(13).fontColor($r('sys.color.warning'))
      }
      this.Provider('search', SEARCH, '网页搜索提供方')
      if (this.field(WEB_SETTINGS, SEARCH) === WEB_SEARCH_API && this.document(WEB_API_SETTINGS) !== undefined) {
        this.Billing('search')
        this.Field(WEB_API_SETTINGS, 'count', '每次搜索结果数（1–50）')
      } else if (this.legacyRef()) {
        Row({ space: 8 }) {
          Text('API Key').fontSize(14)
          Text(this.keyStatus).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.width('100%')
        TextInput({ text: this.keyDraft, placeholder: '输入新的 API Key' }).key('pluginSetting-legacyApiKey')
          .type(InputType.Password).showPasswordIcon(false).enabled(this.canEdit() && this.keyWritable)
          .onChange((value: string): void => { this.keyDraft = value; })
        this.Field(WEB_LEGACY_SETTINGS, 'baseURL', 'Base URL', false)
        this.Field(WEB_LEGACY_SETTINGS, 'maxUses', '单次请求最多搜索次数')
      }
      this.Provider('fetch', FETCH, '网页获取提供方')
      if (this.field(WEB_SETTINGS, FETCH) === WEB_FETCH_API && this.document(WEB_API_SETTINGS) !== undefined) {
        this.Billing('fetch')
      }
      this.Save(WEB_SCOPE, 'pluginSettingsSave-web')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(12)
      .backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private ShellCard(namespace: string) {
    Column({ space: 12 }) {
      Text('Shell').fontSize(17).fontWeight(FontWeight.Medium).width('100%')
      this.Field(namespace, 'timeoutMs', '命令超时（毫秒）')
      this.Field(namespace, 'maxOutputBytes', '每条输出流最大字节数')
      this.Save([namespace], 'pluginSettingsSave-shell')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(12)
      .backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('插件配置').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (this.reading) { LoadingProgress().width(20).height(20) }
        Button('刷新配置', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.reading && !this.saving)
          .onClick((): void => { this.load(); })
      }.width('100%')
      if (this.problem || (!this.configuration.writable && this.configuration.documents.length > 0)) {
        Text(this.problem || '本部署的设置为只读。').fontSize(13).fontColor($r('sys.color.font_secondary'))
          .key('pluginSettingsStatus').width('100%')
      }
      if (this.document(WEB_SETTINGS) !== undefined) { this.WebCard() }
      if (this.document(AGENT_LOOP_SETTINGS) !== undefined) {
        Column({ space: 12 }) {
          Text('Agent 循环').fontSize(17).fontWeight(FontWeight.Medium).width('100%')
          this.Field(AGENT_LOOP_SETTINGS, 'maxParallelToolCalls', '并行工具调用上限')
          this.Save([AGENT_LOOP_SETTINGS], 'pluginSettingsSave-agent-loop')
        }.width('100%').padding(16).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
      }
      if (this.document(PWSH_SETTINGS) !== undefined) { this.ShellCard(PWSH_SETTINGS) }
      else if (this.document(BASH_SETTINGS) !== undefined) { this.ShellCard(BASH_SETTINGS) }
      if (!this.reading && !this.problem && this.configuration.documents.length === 0) {
        Text('宿主未提供这些插件的配置。').fontSize(13).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
