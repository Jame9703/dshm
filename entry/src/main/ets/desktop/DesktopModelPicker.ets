import { KeyCode } from '@kit.InputKit';
import type { ModelOption, ModelSelection } from 'appstate';
import { desktopLocalizedText } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { desktopFilterModelGroups, desktopModelEffort, desktopModelMatches } from './DesktopModelCatalog';
import type { DesktopModelCatalog, DesktopModelFailure, DesktopModelGroup } from './DesktopModelCatalog';

@Component
export struct DesktopModelPicker {
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @Prop @Watch('catalogChanged') catalog: DesktopModelCatalog | undefined = undefined;
  @Prop selection: ModelSelection | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop problem: string = '';
  @Prop busy: boolean = false;
  @Prop placement: Placement = Placement.TopLeft;
  @Prop hasTeam: boolean = false;
  @Prop teamEnabled: boolean = false;
  @Prop teamReady: boolean = false;
  @Prop teamUsed: boolean = false;
  @Prop teamSaving: boolean = false;
  @Prop teamProblem: string = '';
  onLoad: (refresh: boolean) => void = (): void => {};
  onSettings: () => void = (): void => {};
  onTeamMode: (enabled: boolean) => void = (): void => {};
  onSelect: (selection: ModelSelection) => Promise<string> = (): Promise<string> => Promise.resolve('');

  @State private opened: boolean = false;
  @State private pane: string = 'root';
  @State private query: string = '';
  @State private groups: DesktopModelGroup[] = [];
  @State private highlighted: number = -1;
  @State private saving: boolean = false;
  private rows: ModelOption[] = [];
  private chooseVersion: number = 0;
  private keyboard: boolean = false;
  private focusTimer: number = -1;
  private readonly scroller: ListScroller = new ListScroller();

  aboutToDisappear(): void {
    this.chooseVersion++;
    clearTimeout(this.focusTimer);
  }

  private pickerKey(part: string): string { return 'desktopModelPicker-' + part + '-' + this.sessionId; }

  private sessionChanged(): void {
    this.chooseVersion++;
    this.saving = false;
    this.close();
  }

  private selectedModel(): ModelOption | undefined {
    const selected = this.selection;
    return selected === undefined ? undefined : this.catalog?.byProvider.get(selected.provider)?.get(selected.modelId);
  }

  private supportsEffort(): boolean { return this.selectedModel()?.supportsReasoning === true; }

  private effortName(id: string): string {
    const model = this.selectedModel();
    return model === undefined ? id : desktopModelEffort(model, id);
  }

  private effortCaption(): ResourceStr {
    const model = this.selectedModel();
    if (model === undefined) { return ''; }
    const id = this.selection?.effort || model.defaultEffort;
    return id ? desktopModelEffort(model, id) : $r('app.string.desktop_chat_effort_default');
  }

  private modelCaption(): ResourceStr {
    return this.selectedModel()?.modelName || (this.loading ? $r('app.string.desktop_chat_model_loading') :
      $r('app.string.desktop_chat_select_model'));
  }

  private canSearch(): boolean { return (this.catalog?.models.length ?? 0) > 4; }

  private providerName(id: string, name: string): ResourceStr {
    return id === 'deepseek-account' ? $r('app.string.desktop_chat_model_account_provider') : name;
  }

  private catalogChanged(): void {
    if (this.opened && this.pane === 'models') { this.updateResults(this.query); }
  }

  private updateResults(query: string): void {
    this.query = this.canSearch() ? query : '';
    this.groups = desktopFilterModelGroups(this.catalog?.groups ?? [], this.query);
    this.rows = this.groups.flatMap((group: DesktopModelGroup): ModelOption[] => group.models);
    const selected = this.rows.findIndex((row: ModelOption): boolean => desktopModelMatches(row, this.selection));
    this.highlighted = this.rows.length === 0 ? -1 : (!this.query && selected >= 0 ? selected : 0);
  }

  private show(keyboard: boolean): void {
    if (this.opened) { this.close(keyboard); return; }
    this.keyboard = keyboard;
    this.pane = this.selectedModel() === undefined ? 'models' : 'root';
    if (this.pane === 'models') { this.updateResults(''); }
    this.opened = true;
    this.onLoad(false);
  }

  private close(restoreFocus: boolean = false): void {
    clearTimeout(this.focusTimer);
    this.opened = false;
    if (restoreFocus) { this.focusAfterRender('trigger'); }
  }

  private focusAfterRender(part: string): void {
    clearTimeout(this.focusTimer);
    const id = this.pickerKey(part);
    this.focusTimer = setTimeout((): void => { this.getUIContext().getFocusController().requestFocus(id); }, 30);
  }

  private drill(pane: string): void {
    this.pane = pane;
    if (pane === 'models') { this.updateResults(''); }
    if (this.keyboard) { this.focusCurrentPane(); }
  }

  private focusCurrentPane(): void {
    const part = this.pane === 'models' ? (this.canSearch() ? 'search' : this.rowPart(this.rows[this.highlighted])) :
      this.pane === 'effort' ? 'effort-' + (this.selection?.effort || this.selectedModel()?.defaultEffort || 'default') :
        this.pane === 'team' ? 'team-switch' : 'models-entry';
    this.focusAfterRender(part);
  }

  private rowPart(row?: ModelOption): string { return row === undefined ? 'back' : `row-${row.provider}-${row.modelId}`; }

  private indexOfRow(row: ModelOption): number {
    return this.rows.findIndex((candidate: ModelOption): boolean =>
      candidate.provider === row.provider && candidate.modelId === row.modelId);
  }

  private isHighlighted(row: ModelOption): boolean {
    const active = this.rows[this.highlighted];
    return active?.provider === row.provider && active?.modelId === row.modelId;
  }

  private groupModels(id: string): ModelOption[] {
    return this.groups.find((group: DesktopModelGroup): boolean => group.id === id)?.models ?? [];
  }

  private back(): void {
    if (this.pane !== 'root' && (this.selectedModel() !== undefined || this.hasTeam)) {
      const from = this.pane;
      this.pane = 'root';
      if (this.keyboard) { this.focusAfterRender(from + '-entry'); }
    } else { this.close(this.keyboard); }
  }

  private moveModel(step: number): void {
    if (this.rows.length === 0) { return; }
    this.highlighted = (this.highlighted + this.rows.length + step) % this.rows.length;
    let at = this.highlighted;
    for (let group = 0; group < this.groups.length; group++) {
      const count = this.groups[group].models.length;
      if (at < count) {
        this.scroller.scrollToItemInGroup(group, at, false, ScrollAlign.AUTO);
        break;
      }
      at -= count;
    }
    if (!this.canSearch()) { this.focusAfterRender(this.rowPart(this.rows[this.highlighted])); }
  }

  private popupKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || !this.opened) { return false; }
    this.keyboard = true;
    const key = event.keyCode;
    if (key === KeyCode.KEYCODE_ESCAPE || (key === KeyCode.KEYCODE_TAB && event.getModifierKeyState?.(['Shift']))) {
      this.back();
      return true;
    }
    if (this.pane !== 'models' || this.saving) { return false; }
    if (key === KeyCode.KEYCODE_DPAD_UP || key === KeyCode.KEYCODE_DPAD_DOWN) {
      this.moveModel(key === KeyCode.KEYCODE_DPAD_UP ? -1 : 1);
      return true;
    }
    if ((key === KeyCode.KEYCODE_ENTER || key === KeyCode.KEYCODE_TAB) && this.highlighted >= 0) {
      this.chooseModel(this.rows[this.highlighted]);
      return true;
    }
    return false;
  }

  private chooseModel(model?: ModelOption): void {
    if (model === undefined) { return; }
    if (desktopModelMatches(model, this.selection)) { this.close(this.keyboard); return; }
    this.submit({ provider: model.provider, modelId: model.modelId, effort: '' });
  }

  private chooseEffort(id: string): void {
    const selection = this.selection;
    if (selection === undefined) { return; }
    if ((selection.effort || this.selectedModel()?.defaultEffort || '') === id) { this.close(this.keyboard); return; }
    this.submit({ provider: selection.provider, modelId: selection.modelId, effort: id });
  }

  private async submit(selection: ModelSelection): Promise<void> {
    if (this.saving || this.busy) { return; }
    const version = ++this.chooseVersion;
    this.saving = true;
    let problem: string;
    try { problem = await this.onSelect(selection); } catch (_) { problem = '无法切换模型'; }
    if (version !== this.chooseVersion) { return; }
    this.saving = false;
    if (!problem) { this.close(this.keyboard); }
    else { this.getUIContext().getPromptAction().showToast({ message: problem }); }
  }

  @Builder
  private Badge(model?: ModelOption) {
    if (desktopLocalizedText(model?.badge, 'text')) {
      Text(desktopLocalizedText(model?.badge, 'text')).fontSize(10).padding({ left: 5, right: 5, top: 2, bottom: 2 })
        .maxLines(1).borderRadius(4).backgroundColor($r('app.color.workspace_selection'))
        .fontColor($r('sys.color.font_secondary'))
    }
  }

  @Builder
  private DrillRow(id: string, label: ResourceStr, value: ResourceStr) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        Text(label).fontSize(14).fontColor($r('sys.color.font_primary'))
        Text(value).fontSize(13).layoutWeight(1).maxLines(1).textAlign(TextAlign.End)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_secondary'))
        Image($r('app.media.dsh_browser_chevron_right_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
      }.width('100%')
    }.key(this.pickerKey(id + '-entry')).width('100%').height(36).padding({ left: 10, right: 8 }).borderRadius(8)
      .focusable(true).defaultFocus(id === 'models').enabled(!this.saving && !this.busy).onClick((): void => { this.drill(id); })
  }

  @Builder
  private PaneTitle(title: ResourceStr) {
    if (this.selectedModel() !== undefined || this.hasTeam) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Image($r('app.media.dsh_browser_chevron_left_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
          Text(title).fontSize(13).fontWeight(FontWeight.Medium)
        }.width('100%')
      }.key(this.pickerKey('back')).width('100%').height(30).padding({ left: 6, right: 6 })
        .accessibilityText($r('app.string.desktop_chat_model_back')).onClick((): void => { this.back(); })
    }
  }

  @Builder
  private ProviderHeading(group: DesktopModelGroup) {
    Text(this.providerName(group.id, group.name)).fontSize(11).width('100%').height(23).padding({ left: 8 })
      .fontColor($r('sys.color.font_secondary')).backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private ModelRow(row: ModelOption) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 6 }) {
        Text(row.modelName).fontSize(14).fontColor($r('sys.color.font_primary')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.Badge(row)
        Blank()
        if (desktopModelMatches(row, this.selection)) {
          Image($r('app.media.dsh_dock_check')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }
      }.width('100%')
    }.key(this.pickerKey(this.rowPart(row))).width('100%').height(34).borderRadius(7).padding({ left: 8, right: 8 })
      .backgroundColor(this.isHighlighted(row) ? $r('app.color.workspace_selection') : Color.Transparent)
      .accessibilitySelected(desktopModelMatches(row, this.selection)).enabled(!this.saving && !this.busy)
      .onHover((hovered: boolean): void => { if (hovered) { this.highlighted = this.indexOfRow(row); } })
      .onFocus((): void => { if (!this.canSearch()) { this.highlighted = this.indexOfRow(row); } })
      .onClick((): void => { this.chooseModel(row); })
  }

  @Builder
  private CatalogIssue(name: ResourceStr, message: string) {
    Row({ space: 5 }) {
      Column({ space: 3 }) {
        Text(name).fontSize(12).fontWeight(FontWeight.Medium)
        Text(message).fontSize(11).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button($r('app.string.desktop_chat_model_reload'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(30).enabled(!this.loading && !this.saving).onClick((): void => { this.onLoad(true); })
    }.width('100%').padding(6).borderRadius(7).backgroundColor($r('app.color.workspace_selection'))
  }

  @Builder
  private ModelList() {
    this.PaneTitle($r('app.string.desktop_chat_model'))
    if (this.canSearch()) {
      Row({ space: 4 }) {
        TextInput({ text: this.query, placeholder: $r('app.string.desktop_chat_model_search') })
          .key(this.pickerKey('search')).height(32).layoutWeight(1).fontSize(13).enabled(!this.saving)
          .onChange((query: string): void => { this.updateResults(query); })
          .onKeyPreIme((event: KeyEvent): boolean => this.popupKey(event))
        if (this.query) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_dock_close')).width(12).height(12).accessibilityLevel('no')
          }.key(this.pickerKey('clear')).width(30).height(30).padding(0)
            .accessibilityText($r('app.string.desktop_chat_model_search_clear'))
            .onClick((): void => { this.updateResults(''); this.focusAfterRender('search'); })
        }
      }.width('100%')
    }
    if (this.loading) { Text($r('app.string.desktop_chat_model_loading')).fontSize(12).padding(8) }
    if (this.problem) { this.CatalogIssue($r('app.string.desktop_chat_model_unavailable'), this.problem) }
    if (this.groups.length > 0) {
      List({ scroller: this.scroller }) {
        ForEach(this.groups, (group: DesktopModelGroup): void => {
          ListItemGroup({ header: this.ProviderHeading(group) }) {
            ForEach(this.groupModels(group.id), (row: ModelOption): void => { ListItem() { this.ModelRow(row) } },
              (row: ModelOption): string => row.modelId + ':' + row.modelName + ':' + desktopLocalizedText(row.badge, 'text'))
          }
        }, (group: DesktopModelGroup): string => group.id + ':' + group.name)
      }.width('100%').height(Math.min(245, this.rows.length * 34 + this.groups.length * 23))
        .sticky(StickyStyle.Header).scrollBar(BarState.Auto)
    } else if (!this.loading) {
      Text(this.query ? $r('app.string.desktop_chat_model_search_empty') : $r('app.string.desktop_chat_model_empty'))
        .fontSize(13).padding(8).fontColor($r('sys.color.font_secondary'))
    }
    if ((this.catalog?.failures.length ?? 0) > 0) {
      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.catalog?.failures ?? [], (entry: DesktopModelFailure): void => {
            this.CatalogIssue(this.providerName(entry.id, entry.name), entry.message)
          }, (entry: DesktopModelFailure): string => entry.id + entry.message)
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 104 }).scrollBar(BarState.Auto)
    }
    if (!this.catalog?.models.length) {
      Button($r('app.string.desktop_chat_model_settings'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key(this.pickerKey('settings')).onClick((): void => { this.close(); this.onSettings(); })
    }
  }

  @Builder
  private EffortRow(id: string, label: ResourceStr) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row() {
        Text(label).fontSize(14).layoutWeight(1).fontColor($r('sys.color.font_primary'))
        if ((this.selection?.effort || this.selectedModel()?.defaultEffort || '') === id) {
          Image($r('app.media.dsh_dock_check')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }
      }.width('100%')
    }.key(this.pickerKey('effort-' + (id || 'default'))).width('100%').height(34).borderRadius(7).padding({ left: 8, right: 8 })
      .accessibilitySelected((this.selection?.effort || this.selectedModel()?.defaultEffort || '') === id)
      .enabled(!this.saving && !this.busy).onClick((): void => { this.chooseEffort(id); })
  }

  @Builder
  private TeamPane() {
    this.PaneTitle('智能体团队协作')
    Row({ space: 8 }) {
      Text('开启智能体团队协作').fontSize(14).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.teamEnabled }).key(this.pickerKey('team-switch'))
        .accessibilityText('开启智能体团队协作').enabled(this.teamReady && !this.busy && !this.teamSaving)
        .onChange((enabled: boolean): void => {
          if (!enabled && this.teamUsed) { this.close(); }
          this.onTeamMode(enabled);
        })
    }.width('100%').padding(6)
    Text('通过共享任务板协调多个智能体的分工与进度，复杂任务表现更佳，token 开销也相应更高。')
      .fontSize(13).padding(6).fontColor($r('sys.color.font_secondary'))
    if (this.teamProblem) { Text(this.teamProblem).fontSize(12).padding(6).fontColor($r('sys.color.warning')) }
  }

  @Builder
  private Popup() {
    Column({ space: 4 }) {
      if (this.pane === 'root') {
        this.DrillRow('models', $r('app.string.desktop_chat_model'), this.modelCaption())
        if (this.supportsEffort()) {
          this.DrillRow('effort', $r('app.string.desktop_chat_effort'), this.effortCaption())
        }
        if (this.hasTeam) { this.DrillRow('team', '智能体团队协作', this.teamEnabled ? '开启' : '关闭') }
      } else if (this.pane === 'models') {
        this.ModelList()
      } else if (this.pane === 'effort') {
        this.PaneTitle($r('app.string.desktop_chat_effort'))
        if (!this.selectedModel()?.defaultEffort) { this.EffortRow('', $r('app.string.desktop_chat_effort_default')) }
        ForEach(this.selectedModel()?.efforts ?? [], (id: string): void => {
          this.EffortRow(id, this.effortName(id))
        }, (id: string): string => id)
      } else {
        this.TeamPane()
      }
    }.key(this.pickerKey('popup')).width(280).padding(6).alignItems(HorizontalAlign.Start)
      .onAppear((): void => { if (this.keyboard) { this.focusCurrentPane(); } })
      .onKeyEvent((event: KeyEvent): boolean => this.popupKey(event))
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 5 }) {
        Image($r('app.media.dsh_model_data_outline')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
        this.Badge(this.selectedModel())
        Text(this.modelCaption()).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary')).constraintSize({ maxWidth: 160 })
        if (this.supportsEffort() || (this.selectedModel() !== undefined && this.selection?.effort)) {
          Text(this.supportsEffort() ? this.effortCaption() : this.selection?.effort ?? '').fontSize(12)
            .maxLines(1).fontColor($r('sys.color.font_secondary'))
        }
        if (this.saving) { LoadingProgress().width(13).height(13) }
        else {
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true)
            .rotate({ angle: this.opened ? 180 : 0 }).accessibilityLevel('no')
        }
      }
    }.key(this.pickerKey('trigger')).height(30).padding({ left: 7, right: 6 }).borderRadius(8).focusOnTouch(false)
      .backgroundColor(this.opened ? $r('app.color.workspace_selection') : Color.Transparent)
      .enabled(!this.busy || this.opened).accessibilitySelected(this.opened)
      .onClick((): void => { this.show(false); })
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type === KeyType.Down && (event.keyCode === KeyCode.KEYCODE_ENTER ||
          event.keyCode === KeyCode.KEYCODE_SPACE || event.keyCode === KeyCode.KEYCODE_DPAD_DOWN)) {
          this.show(true);
          return true;
        }
        return false;
      })
      .bindPopup(this.opened, { builder: this.Popup(), placement: this.placement, focusable: true, mask: false,
        enableArrow: false, systemMaterial: desktopMenuOptions(this.placement).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible) { this.opened = false; } } })
  }
}
