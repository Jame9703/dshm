import { window } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { LLM_DISCOVER_MODELS_ENDPOINT } from 'dshcompat';
import { dialogMaterial } from 'platform';
import type { PiAiModelRow } from 'appstate';
import type { DesktopHostActions } from './DesktopHostActions';
import { desktopAdoptDiscoveredModels, desktopFilterDiscoveredModels, desktopInitialDiscoveredModelIds,
  desktopPiAiProbeProblem, desktopPiAiProbeRequest, readDesktopDiscoveredPiAiModels } from './DesktopPiAiDiscoveryModel';

@Component
export struct DesktopPiAiModelDiscovery {
  host?: DesktopHostActions;
  @Prop @Watch('probeChanged') provider: string = '';
  @Prop @Watch('probeChanged') endpoint: string = '';
  @Prop @Watch('probeChanged') api: string = '';
  @Prop @Watch('probeChanged') keyReference: string = '';
  @Prop @Watch('probeChanged') keyDraft: string = '';
  @Prop models: PiAiModelRow[] = [];
  @Prop unavailable: boolean = false;
  onAdopt: (models: PiAiModelRow[]) => void = (_models: PiAiModelRow[]): void => {};
  onFetchingChange: (fetching: boolean) => void = (_fetching: boolean): void => {};
  @State private probing: boolean = false;
  @State private probeError: ResourceStr = '';
  @State private candidates: PiAiModelRow[] = [];
  @State private selected: string[] = [];
  @State private query: string = '';
  private active: boolean = false;
  private requestVersion: number = 0;
  private dialogVersion: number = 0;
  private dialogId: number = -1;

  aboutToAppear(): void { this.active = true; }

  aboutToDisappear(): void {
    this.active = false;
    this.requestVersion++;
    this.closePicker();
  }

  private probeChanged(): void {
    if (!this.active) { return; }
    this.requestVersion++;
    this.setFetching(false);
    this.closePicker();
    this.probeError = '';
  }

  private setFetching(fetching: boolean): void {
    this.probing = fetching;
    this.onFetchingChange(fetching);
  }

  private blockedLabel(): ResourceStr {
    switch (desktopPiAiProbeProblem(this.provider, this.endpoint, this.api, this.keyReference, this.keyDraft)) {
      case 'needs-endpoint': return $r('app.string.desktop_model_discover_needs_url');
      case 'invalid-endpoint': return $r('app.string.desktop_model_discover_invalid_url');
      case 'required-key': return $r('app.string.desktop_model_discover_required_key');
      case 'blank-key': return $r('app.string.desktop_model_discover_blank_key');
      case 'invalid-key': return $r('app.string.desktop_model_discover_invalid_key');
      default: return '';
    }
  }

  private blockedDescription(): string {
    const label = this.blockedLabel();
    return typeof label === 'string' ? label :
      this.getUIContext().getHostContext()?.resourceManager.getStringSync(label) ?? '';
  }

  private async fetchModels(): Promise<void> {
    const host = this.host;
    if (!this.active || host === undefined || this.unavailable || this.probing || this.candidates.length > 0 ||
        this.blockedLabel() !== '') { return; }
    const requestVersion = ++this.requestVersion;
    this.setFetching(true);
    this.probeError = '';
    const key = this.keyDraft.trim();
    try {
      const request = desktopPiAiProbeRequest(this.provider, this.endpoint.trim(), this.api, key);
      const reply = await host.call(LLM_DISCOVER_MODELS_ENDPOINT, request, 15000, undefined, true);
      if (!this.active || requestVersion !== this.requestVersion || this.host !== host) { return; }
      if (!reply.ok) {
        const problem = reply.error?.message ?? '';
        this.probeError = (key ? problem.split(key).join('••••') : problem) ||
          $r('app.string.desktop_model_discover_failed');
        return;
      }
      const candidates = readDesktopDiscoveredPiAiModels(reply.value);
      if (candidates.length === 0) { this.probeError = $r('app.string.desktop_model_discover_empty'); return; }
      this.candidates = candidates;
      this.selected = desktopInitialDiscoveredModelIds(this.models, candidates);
      this.query = '';
      await this.openPicker();
    } catch (_) {
      if (this.active && requestVersion === this.requestVersion) {
        this.probeError = $r('app.string.desktop_model_discover_failed');
      }
    } finally {
      if (this.active && requestVersion === this.requestVersion) { this.setFetching(false); }
    }
  }

  private async openPicker(): Promise<void> {
    const version = ++this.dialogVersion;
    const ui = this.getUIContext();
    const prompt = ui.getPromptAction();
    const material = dialogMaterial();
    let width = 520;
    const name = ui.getWindowName();
    if (name) {
      try { width = Math.min(width, Math.max(1, ui.px2vp(window.findWindow(name).getWindowProperties().windowRect.width) - 32)); }
      catch (_) {}
    }
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.Picker(); },
        alignment: DialogAlignment.Center, width: width, autoCancel: true, cornerRadius: 28, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.desktop_settings_surface') : undefined,
        onDidDisappear: (): void => {
          if (version === this.dialogVersion) {
            this.dialogId = -1;
            this.closePicker();
          }
        } });
      if (this.active && version === this.dialogVersion) { this.dialogId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.dialogVersion) {
        this.closePicker();
        this.probeError = $r('app.string.desktop_model_discover_failed');
      }
    }
  }

  private closePicker(): void {
    this.dialogVersion++;
    const id = this.dialogId;
    this.dialogId = -1;
    this.candidates = [];
    this.selected = [];
    this.query = '';
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private visibleCandidates(): PiAiModelRow[] { return desktopFilterDiscoveredModels(this.candidates, this.query); }

  private allVisibleSelected(): boolean {
    const visible = this.visibleCandidates();
    return visible.length > 0 && visible.every((row: PiAiModelRow): boolean => this.selected.includes(row.id));
  }

  private selectVisible(): void {
    const visible = this.visibleCandidates();
    const checked = !this.allVisibleSelected();
    const selected = new Set<string>(this.selected);
    for (const model of visible) {
      if (checked) { selected.add(model.id); } else { selected.delete(model.id); }
    }
    this.selected = Array.from(selected);
  }

  private applySelection(): void {
    if (!this.active || this.candidates.length === 0) { return; }
    const rows = desktopAdoptDiscoveredModels(this.models, this.candidates, this.selected);
    if (this.models.length > 0 && rows.length === 0) { return; }
    this.onAdopt(rows);
    this.closePicker();
  }

  private wouldClear(): boolean {
    return this.models.length > 0 && desktopAdoptDiscoveredModels(this.models, this.candidates, this.selected).length === 0;
  }

  @Builder
  private Picker() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_model_discover_title')).fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_settings_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.key('desktopModelDiscoveryClose').width(28).height(28).padding(0).borderRadius(8)
          .accessibilityText($r('app.string.desktop_settings_close')).onClick((): void => { this.closePicker(); })
      }.width('100%')
      Text($r('app.string.desktop_model_discover_description')).fontSize(14).lineHeight(22).width('100%')
        .fontColor($r('sys.color.font_secondary'))
      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: $r('app.string.desktop_model_discover_search') })
          .key('desktopModelDiscoverySearch').defaultFocus(true).height(34).fontSize(14).layoutWeight(1)
          .accessibilityText($r('app.string.desktop_model_discover_search')).onChange((text: string): void => { this.query = text; })
        Button(this.allVisibleSelected() ? $r('app.string.desktop_model_discover_deselect_all') :
          $r('app.string.desktop_model_discover_select_all'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopModelDiscoverySelectVisible').height(34).fontSize(13)
          .enabled(this.visibleCandidates().length > 0).onClick((): void => { this.selectVisible(); })
      }.width('100%')
      if (this.visibleCandidates().length === 0) {
        Text($r('app.string.desktop_model_discover_no_matches')).fontSize(13).width('100%').padding(12)
          .fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.visibleCandidates(), (model: PiAiModelRow): void => {
            ListItem() {
              Row({ space: 8 }) {
                Checkbox({ name: model.id, group: 'desktop-discover-models' })
                  .key('desktopModelDiscoveryOption-' + model.id).select(this.selected.includes(model.id))
                  .accessibilityText(model.id).accessibilityDescription(model.name)
                  .onChange((checked: boolean): void => { this.selectModel(model.id, checked); })
                Text(model.id).fontFamily('monospace').fontSize(13).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  .onClick((): void => { this.selectModel(model.id, !this.selected.includes(model.id)); })
              }.width('100%').height(34).padding({ left: 8, right: 8 }).borderRadius(12)
            }
          }, (model: PiAiModelRow): string => model.id)
        }.width('100%').height(Math.min(320, this.visibleCandidates().length * 36)).scrollBar(BarState.Auto)
      }
      if (this.wouldClear()) {
        Text($r('app.string.desktop_model_discover_keep_one')).fontSize(13).width('100%')
          .fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: 8 }) {
        Button($r('app.string.desktop_model_discover_cancel'), { buttonStyle: ButtonStyleMode.NORMAL })
          .key('desktopModelDiscoveryCancel').height(36).borderRadius(12).onClick((): void => { this.closePicker(); })
        Button($r('app.string.desktop_model_discover_apply'), { buttonStyle: ButtonStyleMode.NORMAL })
          .key('desktopModelDiscoveryApply').enabled(!this.wouldClear()).height(36).borderRadius(12)
          .onClick((): void => { this.applySelection(); })
      }.width('100%').justifyContent(FlexAlign.End)
    }.key('desktopModelDiscoveryDialog').width('100%').padding(24)
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
        event.stopPropagation();
        this.closePicker();
        return true;
      })
  }

  private selectModel(id: string, checked: boolean): void {
    const selected = new Set<string>(this.selected);
    if (checked) { selected.add(id); } else { selected.delete(id); }
    this.selected = Array.from(selected);
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Button(this.probing ? $r('app.string.desktop_model_discover_loading') : $r('app.string.desktop_model_discover_fetch'),
          { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopModelDiscoveryFetch').fontSize(13).height(32)
          .accessibilityDescription(this.blockedDescription())
          .enabled(this.host !== undefined && !this.unavailable && !this.probing && this.blockedLabel() === '')
          .onClick((): void => { this.fetchModels(); })
      }.width('100%').justifyContent(FlexAlign.End)
      if (this.probeError !== '') {
        Text(this.probeError).key('desktopModelDiscoveryError').fontSize(13).width('100%')
          .fontColor($r('app.color.workspace_status_error'))
      }
    }.width('100%')
  }
}
