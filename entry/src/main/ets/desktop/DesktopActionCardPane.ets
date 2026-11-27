import { preferences } from '@kit.ArkData';
import { getBoolean, getString } from 'connection';
import { DesktopHostActions, desktopLocalizedText } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { PAGE_CARD, PLUGIN_CARD } from './DesktopActionCards';
import type { DesktopActionCard } from './DesktopActionCards';

const PLACES: string[] = ['sidebar-right', 'page', 'sidebar-left', 'custom'];
const PLACE_LABELS: string[] = ['右侧栏', '会话 Tab', '全局页面', '自行撰写'];
const PLACE_HINTS: string[] = ['在当前会话旁查看', '与「对话」「轨迹」并列', '从左侧入口打开', '描述你希望放在哪里'];
const PAGE_RETRY: string[] = ['cancelled', 'failed', 'interrupted', 'unconfirmed'];
const PLUGIN_RETRY: string[] = ['failed', 'unconfirmed'];
const PREFS: string = 'dshm_desktop_action_cards';
const INFO_DISMISSED: string = 'creationInfoDismissed';

const PAGE_PHASES: Record<string, string> = {
  'dismissed': '已忽略', 'creating': '正在后台创建', 'installing': '正在安装…', 'cancelled': '已取消',
  'installed': '已安装', 'kept': '已保留', 'removed': '已移除', 'failed': '创建失败，可重试',
  'interrupted': '创建中断，可重试', 'unconfirmed': '结果待确认，请重试'
};
const PAGE_APPLICATION: Record<string, string> = {
  'restart-required': '变更已保存，重启 DSH 后生效', 'overridden': '其他配置覆盖了本次变更',
  'failed': '上一步更改未生效，请到插件页查看', 'cancelled': '上一步更改已取消'
};
const PLUGIN_PHASES: Record<string, string> = {
  'dismissed': '已忽略', 'already-enabled': '已在插件页开启，可查看详情了解运行状态', 'enabled': '已启用',
  'failed': '启用失败。可重试或在插件页检查。', 'unconfirmed': '无法确认插件是否已启用，可重试确认。'
};
const ACTION_ERRORS: Record<string, string> = {
  'unknown': '这条推荐已不可用', 'access-denied': '当前连接没有修改插件的权限',
  'not-live-root': '请打开原会话后使用这张卡片', 'closing': '服务正在重载，请稍后重试',
  'invalid-location': '请选择位置，或填写不超过 1,000 字的位置说明',
  'read-only': '当前会话为只读模式，创建页面需要切换权限预设', 'source-missing': '页面文件已不在，需要重新提案',
  'unavailable': '暂时无法执行，请到插件页面查看'
};

function placeLabel(key: string): string {
  return PLACE_LABELS[PLACES.indexOf(key)] ?? PLACE_LABELS[0];
}

@Component
export struct DesktopActionCardPane {
  host?: DesktopHostActions;
  @Prop sessionId: string = '';
  @Prop @Watch('phaseChanged') card: DesktopActionCard;
  onPlugin: (name: string, title: string, description: string) => void = (): void => {};
  onWeb: () => void = (): void => {};
  @State private busy: string = '';
  @State private problem: string = '';
  @State private selected: string = '';
  @State private custom: string | undefined = undefined;
  @State private infoOpen: boolean = false;
  @State private briefExpanded: boolean = false;
  @State private contentExpanded: boolean = false;
  @State private lookup: string = '';
  @State private pluginTitle: string = '';
  @State private pluginDescription: string = '';
  @State private pluginEnabled: boolean = false;
  private active: boolean = false;
  private visible: boolean = false;
  private lookedUpPhase?: string;

  aboutToAppear(): void {
    this.active = true;
    if (this.isPage() && this.pageOffered()) {
      try { this.infoOpen = this.notice()?.getSync(INFO_DISMISSED, false) !== true; } catch (_) { this.infoOpen = true; }
    }
  }

  aboutToDisappear(): void { this.active = false; this.visible = false; }

  private notice(): preferences.Preferences | undefined {
    const context = this.getUIContext().getHostContext();
    return context === undefined ? undefined : preferences.getPreferencesSync(context, { name: PREFS });
  }

  private dismissInfo(): void {
    this.infoOpen = false;
    try {
      const store = this.notice();
      store?.putSync(INFO_DISMISSED, true);
      store?.flush().catch((): void => {});
    } catch (_) { }
  }

  private isPage(): boolean {
    const slot = getString(this.card.details, 'slot') ?? '';
    return this.card.action === PAGE_CARD && PLACES.indexOf(slot) >= 0 && slot !== 'custom';
  }

  private isPlugin(): boolean {
    return this.card.action === PLUGIN_CARD && !!getString(this.card.details, 'name');
  }

  private pageOffered(): boolean { return !this.card.phase || PAGE_RETRY.includes(this.card.phase); }
  private pluginOffered(): boolean {
    return !this.pluginEnabled && (!this.card.phase || PLUGIN_RETRY.includes(this.card.phase));
  }

  private savedSlot(): string {
    return getString(this.card.data, 'slot') ?? getString(this.card.details, 'slot') ?? PLACES[0];
  }

  private location(): string {
    return this.selected || (getString(this.card.data, 'customLocation') !== undefined ? 'custom' : this.savedSlot());
  }

  private customLocation(): string { return this.custom ?? getString(this.card.data, 'customLocation') ?? ''; }

  private phaseChanged(): void {
    if (this.lookedUpPhase !== this.card.phase && this.visible && this.isPlugin()) { this.describe(); }
  }

  private async describe(): Promise<void> {
    const host = this.host;
    if (host === undefined || !this.sessionId || this.lookup === 'loading') { return; }
    const phase = this.card.phase;
    this.lookedUpPhase = phase;
    this.lookup = 'loading';
    const result = await host.call('pluginRecommendations/describe', { 'agentId': this.sessionId, 'cardId': this.card.id });
    if (!this.active) { return; }
    if (getString(result.value, 'status') === 'available') {
      this.pluginTitle = desktopLocalizedText(result.value, 'title');
      this.pluginDescription = desktopLocalizedText(result.value, 'description');
      this.pluginEnabled = getBoolean(result.value, 'enabled') === true;
      this.lookup = 'available';
    } else {
      const reason = getString(result.value, 'reason') ?? '';
      this.lookup = getString(ACTION_ERRORS, reason) ?? '无法读取插件信息，请重试。';
    }
    if (phase !== this.card.phase) { this.describe(); }
  }

  private async act(verb: string): Promise<void> {
    const host = this.host;
    if (host === undefined || !this.canAct(verb)) { return; }
    const request: Record<string, Object> = { 'agentId': this.sessionId, 'cardId': this.card.id, 'verb': verb };
    if (this.isPage() && (verb === 'create' || verb === 'dismiss')) {
      const location = this.location();
      const payload: Record<string, Object> = { 'slot': location === 'custom' ? this.savedSlot() : location };
      if (location === 'custom') { payload['customLocation'] = this.customLocation().trim(); }
      request['payload'] = payload;
      this.dismissInfo();
    }
    this.busy = verb;
    this.problem = '';
    const result = await host.call('actionCards/act', request);
    if (!this.active) { return; }
    const status = getString(result.value, 'status');
    this.busy = '';
    if (status === 'refused' || status === 'unconfirmed') {
      this.problem = getString(ACTION_ERRORS, getString(result.value, 'reason') ?? '') ?? ACTION_ERRORS['unavailable'];
    } else if (!result.ok || (status !== 'accepted' && status !== 'settled')) {
      this.problem = '暂时无法确认结果，请重新连接并查看卡片状态后再重试';
    }
  }

  private canAct(verb: string): boolean {
    if (!this.sessionId || this.busy) { return false; }
    if (verb === 'create') { return this.location() !== 'custom' || !!this.customLocation().trim(); }
    if (verb === 'enable') { return this.lookup === 'available'; }
    return verb !== 'dismiss' || !this.isPlugin() || (!!this.lookup && this.lookup !== 'loading');
  }

  private actionTitle(verb: string): string {
    if (this.busy === verb) {
      if (verb === 'create') { return '开始创建…'; }
      if (verb === 'cancel') { return '正在取消…'; }
      if (verb === 'restore') { return '恢复中…'; }
      return '正在处理…';
    }
    switch (verb) {
      case 'enable': return this.card.phase ? '重试启用' : '启用';
      case 'create': return this.card.phase ? '重新创建' : '创建';
      case 'cancel': return '取消创建';
      case 'undo': return '撤销';
      case 'restore': return '恢复';
      default: return '暂不需要';
    }
  }

  private expanded(prefilled: boolean): boolean { return prefilled ? this.contentExpanded : this.briefExpanded; }

  private foldable(text: string): boolean { return text.length > 100 || text.split('\n').length > 2; }

  @Builder
  private Folded(text: string, prefilled: boolean = false) {
    Text(text).width('100%').fontSize(14).fontColor($r('sys.color.font_secondary'))
      .maxLines(this.expanded(prefilled) || !this.foldable(text) ? 10000 : 2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    if (this.foldable(text)) {
      Button((this.expanded(prefilled) ? '收起' : '展开') + (prefilled ? '内容' : ''), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(28).fontSize(12).onClick((): void => {
          if (prefilled) { this.contentExpanded = !this.contentExpanded; }
          else { this.briefExpanded = !this.briefExpanded; }
        })
    }
  }

  @Builder
  private LocationMenu() {
    Menu() {
      ForEach(PLACES, (place: string, index: number): void => {
        MenuItem({ content: PLACE_LABELS[index], labelInfo: PLACE_HINTS[index] })
          .key('desktopActionCardPlace-' + place).selectIcon(true).selected(this.location() === place)
          .onChange((): void => { this.selected = place; })
      }, (place: string): string => place)
    }
  }

  @Builder
  private Summary() {
    Text(this.card.title).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
    this.Folded(this.card.brief)
  }

  @Builder
  private Page() {
    Row({ space: 6 }) {
      Text('个性化页面').fontSize(13).fontWeight(FontWeight.Medium)
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_action_card_warning')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
      }.key('desktopActionCardCreationInfo').width(28).height(28).padding(0)
        .accessibilityText('创建方式与 token 消耗').accessibilitySelected(this.infoOpen)
        .onClick((): void => { if (this.infoOpen) { this.dismissInfo(); } else { this.infoOpen = true; } })
      Blank()
      Text(getString(PAGE_PHASES, this.card.phase) ?? '').key('desktopActionCardPhase').fontSize(12)
    }.width('100%')
    if (this.infoOpen) {
      Text('用创造模式制作新页面，可随时移除\n创建可能耗时较长，并消耗大量 token\n点击「创建」后在后台运行，你可以继续聊天' +
        (getString(this.card.data, 'bundleName') ? '\n撤销后，源码仍保留在原工作区的 .dsh-created-plugins/ 文件夹中' : ''))
        .width('100%').padding(8).borderRadius(8).backgroundColor($r('app.color.workspace_selection')).fontSize(13)
    }
    this.Summary()
    if (getString(this.card.details, 'initialContent') !== undefined) {
      Text('预填内容').fontSize(12).fontColor($r('sys.color.font_secondary'))
      this.Folded(getString(this.card.details, 'initialContent') ?? '', true)
    }
    if (this.card.phase !== 'failed' && getString(PAGE_APPLICATION, getString(this.card.data, 'application') ?? '')) {
      Text(getString(PAGE_APPLICATION, getString(this.card.data, 'application') ?? '')).fontSize(13)
    }
    if (this.pageOffered()) {
      Row({ space: 8 }) {
        Text('添加到').fontSize(13)
        Button({ buttonStyle: ButtonStyleMode.NORMAL }) {
          Row({ space: 6 }) {
            Text(placeLabel(this.location())).fontSize(13)
            Image($r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
          }
        }.key('desktopActionCardLocation').height(32).enabled(!this.busy)
          .accessibilityText('添加到 ' + placeLabel(this.location()))
          .bindMenu(this.LocationMenu, desktopMenuOptions(Placement.BottomLeft))
      }
      if (this.location() === 'custom') {
        Text('你希望放在哪里？').fontSize(13)
        TextArea({ text: this.customLocation(), placeholder: '例如：在左侧加一个入口，打开全屏日历' })
          .key('desktopActionCardCustomLocation').maxLength(1000).height(70).enabled(!this.busy)
          .onChange((value: string): void => { this.custom = value; })
      }
      Row({ space: 8 }) {
        this.Action('dismiss')
        this.Action('create', true)
      }.width('100%').justifyContent(FlexAlign.End)
    } else {
      Row({ space: 8 }) {
        Text('添加到 · ' + (getString(this.card.data, 'customLocation') ?? placeLabel(this.savedSlot())))
          .fontSize(13).layoutWeight(1)
        if (this.card.phase === 'creating') { this.Action('cancel') }
        if (this.card.phase === 'installed' || this.card.phase === 'kept') { this.Action('undo') }
        if (this.card.phase === 'removed') { this.Action('restore', true) }
      }.width('100%')
      if (this.card.phase === 'installed' || this.card.phase === 'kept') {
        Button('在 WebUI 查看页面', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(13).onClick(this.onWeb)
      }
    }
  }

  @Builder
  private Plugin() {
    Row({ space: 8 }) {
      Text('推荐插件').fontSize(13).fontWeight(FontWeight.Medium)
      Text('官方').fontSize(11).fontColor($r('sys.color.font_secondary'))
    }
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 4 }) {
        Text(this.pluginTitle || this.card.title).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
        if (this.pluginDescription) { Text(this.pluginDescription).fontSize(13).width('100%') }
        if (!this.lookup || this.lookup === 'loading') { LoadingProgress().width(18).height(18) }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.key('desktopActionCardPluginDetails').width('100%').padding(4).borderRadius(6)
      .accessibilityText('查看详情 ' + (this.pluginTitle || this.card.title))
      .onClick((): void => { this.onPlugin(getString(this.card.details, 'name') ?? '',
        this.pluginTitle || this.card.title, this.pluginDescription); })
    if (this.card.phase || this.pluginEnabled) {
      Text(this.card.phase === 'enabled' && getString(this.card.data, 'application') === 'restart-required' ?
        '已保存，重启 DSH 后生效' : getString(PLUGIN_PHASES, this.card.phase || 'already-enabled') ?? '')
        .key('desktopActionCardPhase').fontSize(13)
    }
    if (this.card.phase === 'failed' && getString(this.card.data, 'errorCode')) {
      Text(getString(this.card.data, 'errorCode') === 'incompatible-version' ?
        '插件与当前 DSH 版本不兼容，请更新 DSH 后重试。' : '无法启用插件，请打开详情检查错误后重试。').fontSize(13)
    }
    if (this.pluginOffered()) {
      if (this.lookup && this.lookup !== 'loading' && this.lookup !== 'available') { Text(this.lookup).fontSize(13) }
      Row({ space: 8 }) {
        Text('启用后可在所有会话中使用').fontSize(12).layoutWeight(1).fontColor($r('sys.color.font_secondary'))
        if (this.lookup && this.lookup !== 'loading' && this.lookup !== 'available') {
          Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopActionCardRetryLookup')
            .enabled(!this.busy).onClick((): void => { this.describe(); })
        }
        this.Action('dismiss')
        if (!this.lookup || this.lookup === 'loading' || this.lookup === 'available') {
          this.Action('enable', true)
        }
      }.width('100%')
    }
  }

  @Builder
  private Action(verb: string, primary: boolean = false) {
    Button(this.actionTitle(verb), { buttonStyle: primary ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.TEXTUAL })
      .key('desktopActionCard-' + verb).constraintSize({ minHeight: 30 }).fontSize(13)
      .enabled(!!this.host && this.canAct(verb)).onClick((): void => { this.act(verb); })
  }

  build() {
    Column({ space: 8 }) {
      if (this.isPage()) {
        this.Page()
      } else if (this.isPlugin()) {
        this.Plugin()
      } else {
        this.Summary()
        if (this.card.phase === 'dismissed') { Text('已忽略').fontSize(13) }
        if (!this.card.phase) { this.Action('dismiss') }
      }
      if (this.problem) { Text(this.problem).fontSize(13).fontColor($r('app.color.workspace_status_error')) }
    }.key('desktopActionCard-' + this.card.id).width('100%').padding(12).alignItems(HorizontalAlign.Start)
      .borderRadius(12).border({ width: 1, color: $r('app.color.workspace_border') })
      .backgroundColor($r('app.color.workspace_panel'))
      .onVisibleAreaChange([0.01], (visible: boolean): void => {
        this.visible = visible;
        if (visible && this.isPlugin() && this.lookedUpPhase !== this.card.phase) { this.describe(); }
      })
  }
}
