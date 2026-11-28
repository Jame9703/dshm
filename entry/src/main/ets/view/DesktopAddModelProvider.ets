import { desktopMenuOptions } from '../desktop/DesktopMenuOptions';

export interface DesktopAddModelProviderOption {
  provider: string;
  displayName: string;
}

export enum DesktopAddModelProviderMode {
  CATALOG = 'catalog',
  CUSTOM = 'custom'
}

@Builder
function emptyProviderEditor() {}

@Component
export struct DesktopAddModelProvider {
  @Prop @Watch('syncVisits') addOpen: boolean = false;
  @Prop @Watch('syncVisits') mode: DesktopAddModelProviderMode = DesktopAddModelProviderMode.CATALOG;
  @Prop @Watch('syncVisits') catalogOffered: boolean = false;
  @Prop @Watch('syncVisits') customOffered: boolean = false;
  @Prop catalogEnabled: boolean = false;
  @Prop customEnabled: boolean = false;
  @Prop canOpen: boolean = false;
  @Prop catalogBusy: boolean = false;
  @Prop customBusy: boolean = false;
  @Prop options: DesktopAddModelProviderOption[] = [];
  @Prop selectedProvider: string = '';
  @Prop selectedDisplayName: string = '';
  @Prop catalogDraftVisible: boolean = false;
  @BuilderParam catalogEditor: () => void = emptyProviderEditor;
  @BuilderParam customEditor: () => void = emptyProviderEditor;
  onOpen: () => void = (): void => {};
  onModeChange: (mode: DesktopAddModelProviderMode) => void = (): void => {};
  onProviderChange: (provider: string) => void = (): void => {};
  onCancel: () => void = (): void => {};
  @State private catalogVisited: boolean = false;
  @State private customVisited: boolean = false;

  aboutToAppear(): void { this.syncVisits(); }

  private activeMode(): DesktopAddModelProviderMode {
    if (this.catalogOffered && this.customOffered) { return this.mode; }
    return this.customOffered ? DesktopAddModelProviderMode.CUSTOM : DesktopAddModelProviderMode.CATALOG;
  }

  private isCatalog(): boolean { return this.activeMode() === DesktopAddModelProviderMode.CATALOG; }

  private busy(): boolean { return this.catalogBusy || this.customBusy; }

  private syncVisits(): void {
    if (!this.addOpen) {
      this.catalogVisited = false;
      this.customVisited = false;
    } else if (this.isCatalog()) {
      this.catalogVisited = true;
    } else {
      this.customVisited = true;
    }
  }

  private openEnabled(): boolean {
    return this.canOpen && ((this.catalogOffered && this.catalogEnabled) || (this.customOffered && this.customEnabled));
  }

  private open(): void {
    if (this.openEnabled()) { this.onOpen(); }
  }

  private modeLabel(mode: DesktopAddModelProviderMode): Resource {
    return mode === DesktopAddModelProviderMode.CATALOG ? $r('app.string.desktop_model_add_catalog') :
      $r('app.string.desktop_model_add_custom');
  }

  private modeEnabled(mode: DesktopAddModelProviderMode): boolean {
    if (this.busy()) { return false; }
    return mode === DesktopAddModelProviderMode.CATALOG ? this.catalogEnabled : this.customEnabled;
  }

  private changeMode(mode: DesktopAddModelProviderMode): void {
    if (this.addOpen && this.catalogOffered && this.customOffered && this.modeEnabled(mode) && mode !== this.mode) {
      this.onModeChange(mode);
    }
  }

  private choose(provider: string): void {
    if (this.addOpen && this.isCatalog() && !this.catalogBusy && provider !== this.selectedProvider &&
      this.options.some((option: DesktopAddModelProviderOption): boolean => option.provider === provider)) {
      this.onProviderChange(provider);
    }
  }

  @Builder
  private ModeButton(mode: DesktopAddModelProviderMode, key: string, unavailable: Resource) {
    Button(this.modeLabel(mode), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
      .key(key).height(28).padding({ left: 9, right: 9 }).borderRadius(7)
      .fontSize(13).fontWeight(this.activeMode() === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.activeMode() === mode ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .backgroundColor(this.activeMode() === mode ? $r('sys.color.background_primary') : Color.Transparent)
      .accessibilitySelected(this.activeMode() === mode)
      .accessibilityDescription((mode === DesktopAddModelProviderMode.CATALOG ?
        this.catalogEnabled : this.customEnabled) ? '' :
        (this.getUIContext().getHostContext()?.resourceManager.getStringSync(unavailable) ?? ''))
      .enabled(this.modeEnabled(mode)).onClick((): void => { this.changeMode(mode); })
  }

  @Builder
  private ModeHeader() {
    Column({ space: 8 }) {
      if (this.catalogOffered && this.customOffered) {
        Row({ space: 2 }) {
          this.ModeButton(DesktopAddModelProviderMode.CATALOG, 'desktopModelProviderAddModeCatalog',
            $r('app.string.desktop_model_add_catalog_exhausted'))
          this.ModeButton(DesktopAddModelProviderMode.CUSTOM, 'desktopModelProviderAddModeCustom',
            $r('app.string.desktop_model_add_custom_unavailable'))
        }.padding(3).borderRadius(10).backgroundColor($r('app.color.workspace_selection'))
          .accessibilityDescription($r('app.string.desktop_model_add_mode'))
      } else {
        Text(this.modeLabel(this.activeMode())).fontSize(14).fontWeight(FontWeight.Medium)
      }
      Text(this.isCatalog() ? $r('app.string.desktop_model_add_catalog_hint') :
        $r('app.string.desktop_model_add_custom_hint'))
        .fontSize(12).lineHeight(18).fontColor($r('sys.color.font_secondary')).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private catalogMenu(): MenuElement[] {
    return this.options.map((option: DesktopAddModelProviderOption): MenuElement => ({
      value: option.displayName,
      icon: this.selectedProvider === option.provider ? $r('app.media.dsh_dock_check') : undefined,
      action: (): void => { this.choose(option.provider); }
    }));
  }

  @Builder
  private CatalogPicker() {
    Column({ space: 6 }) {
      Text($r('app.string.desktop_model_add_provider')).fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Text(this.selectedDisplayName || this.selectedProvider).fontSize(14).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_primary'))
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
        }.width('100%')
      }.key('desktopModelProviderAddCatalogSelect').width('100%').height(36)
        .borderRadius(10).padding({ left: 10, right: 10 }).backgroundColor($r('sys.color.background_primary'))
        .accessibilityGroup(true).accessibilityDescription($r('app.string.desktop_model_add_provider'))
        .enabled(!this.catalogBusy && this.options.length > 0)
        .bindMenu(this.catalogMenu(), desktopMenuOptions(Placement.BottomLeft))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private AddCard() {
    Column({ space: 14 }) {
      this.ModeHeader()
      if (this.catalogOffered && this.catalogDraftVisible && (this.isCatalog() || this.catalogVisited)) {
        Column({ space: 14 }) {
          this.CatalogPicker()
          this.catalogEditor()
        }.key('desktopModelProviderAddCatalogPanel').width('100%').alignItems(HorizontalAlign.Start)
          .visibility(this.isCatalog() ? Visibility.Visible : Visibility.None)
      }
      if (this.customOffered && (!this.isCatalog() || this.customVisited)) {
        Column() { this.customEditor() }
          .key('desktopModelProviderAddCustomPanel').width('100%').alignItems(HorizontalAlign.Start)
          .visibility(this.isCatalog() ? Visibility.None : Visibility.Visible)
      }
      if (this.isCatalog() && !this.catalogDraftVisible) {
        Row() {
          Blank().layoutWeight(1)
          Button($r('app.string.desktop_model_add_cancel'),
            { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopModelProviderAddCancel').height(36).borderRadius(10).enabled(!this.busy())
            .onClick((): void => { if (!this.busy()) { this.onCancel(); } })
        }.width('100%')
      }
    }.key('desktopModelProviderAddCard').width('100%').alignItems(HorizontalAlign.Start)
      .padding({ top: 14, bottom: 14, left: 16, right: 16 }).borderRadius(16)
      .backgroundColor($r('sys.color.background_secondary'))
  }

  build() {
    Column() {
      if (this.addOpen) {
        this.AddCard()
      } else if (this.catalogOffered || this.customOffered) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Image($r('app.media.dsh_reference_menu_plus')).width(14).height(14).supportSvg2(true)
              .draggable(false).accessibilityLevel('no')
            Text($r('app.string.desktop_model_add_entry')).fontSize(14).lineHeight(22)
              .fontColor($r('sys.color.font_primary'))
          }
        }.key('desktopModelAddProvider').width('100%').height(44).borderRadius(16)
          .border({ width: 1, style: BorderStyle.Dashed, color: $r('app.color.workspace_border') })
          .enabled(this.openEnabled()).onClick((): void => { this.open(); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
