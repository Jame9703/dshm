import { SessionHub } from 'appstate';
import { desktopHostProblem } from '../desktop/DesktopHostActions';
import type { DesktopHostActions } from '../desktop/DesktopHostActions';
import { desktopAddProviderDocument } from '../desktop/DesktopProviderAddModel';
import type { DesktopAddProviderDocument, DesktopCatalogCandidate } from '../desktop/DesktopProviderAddModel';
import { DesktopAddModelProvider, DesktopAddModelProviderMode } from './DesktopAddModelProvider';
import type { DesktopAddModelProviderOption } from './DesktopAddModelProvider';
import { DesktopPiAiAddProfile } from './DesktopPiAiAddProfile';

@Component
export struct DesktopModelProviderAddFlow {
  host?: DesktopHostActions;
  @State private document: DesktopAddProviderDocument = desktopAddProviderDocument(undefined, []);
  @State private open: boolean = false;
  @State private loading: boolean = true;
  @State private failure: string = '';
  @State private saved: boolean = false;
  @State private mode: DesktopAddModelProviderMode = DesktopAddModelProviderMode.CATALOG;
  @State private selected: DesktopCatalogCandidate | undefined = undefined;
  @State private catalogBusy: boolean = false;
  @State private customBusy: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void { this.load(); }

  aboutToDisappear(): void { this.generation++; }

  private async load(): Promise<void> {
    const generation = ++this.generation;
    this.loading = true;
    this.failure = '';
    const hub = SessionHub.shared();
    try {
      const settingsRequest = hub.readSettingsDescription();
      const directoryRequest = hub.configurableModelProviders();
      const registeredRequest = hub.registeredModelProviders();
      const settings = await settingsRequest;
      const entries = await directoryRequest;
      const registered = await registeredRequest;
      if (generation !== this.generation) { return; }
      if (!settings.ok) { this.failure = desktopHostProblem(settings); return; }
      this.document = desktopAddProviderDocument(settings.value, entries, registered);
    } finally {
      if (generation === this.generation) { this.loading = false; }
    }
  }

  private show(): void {
    if (this.loading || !this.document.writable) { return; }
    this.saved = false;
    this.selected = this.document.candidates[0];
    this.mode = this.selected !== undefined ? DesktopAddModelProviderMode.CATALOG : DesktopAddModelProviderMode.CUSTOM;
    this.open = true;
  }

  private choose(route: string): void {
    if (this.catalogBusy || this.customBusy) { return; }
    this.selected = this.document.candidates.find((entry: DesktopCatalogCandidate): boolean => entry.provider === route);
  }

  private close(saved: boolean): void {
    this.open = false;
    this.catalogBusy = false;
    this.customBusy = false;
    this.selected = undefined;
    if (saved) { this.saved = true; this.load(); }
  }

  private options(): DesktopAddModelProviderOption[] {
    return this.document.candidates.map((candidate: DesktopCatalogCandidate): DesktopAddModelProviderOption => ({
      provider: candidate.provider, displayName: candidate.displayName }));
  }

  @Builder
  private CatalogEditor() {
    if (this.selected !== undefined) {
      ForEach([this.selected], (candidate: DesktopCatalogCandidate): void => {
        DesktopPiAiAddProfile({ document: this.document, candidate: candidate, host: this.host,
          onBusy: (value: boolean): void => { this.catalogBusy = value; },
          onCancel: (): void => { this.close(false); }, onSaved: (): void => { this.close(true); } })
      }, (candidate: DesktopCatalogCandidate): string => candidate.provider)
    }
  }

  @Builder
  private CustomEditor() {
    DesktopPiAiAddProfile({ document: this.document, host: this.host,
      onBusy: (value: boolean): void => { this.customBusy = value; },
      onCancel: (): void => { this.close(false); }, onSaved: (): void => { this.close(true); } })
  }

  build() {
    Column({ space: 8 }) {
      if (this.failure) {
        Text(this.failure).fontSize(12).fontColor($r('sys.color.alert')).width('100%')
        Button($r('app.string.desktop_deepseek_reload'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => { this.load(); })
      }
      if (this.saved) {
        Text($r('app.string.desktop_catalog_provider_saved')).key('desktopCatalogProviderSaved').fontSize(12)
          .fontColor($r('sys.color.font_secondary')).width('100%')
      }
      DesktopAddModelProvider({ addOpen: this.open, mode: this.mode,
        canOpen: this.document.writable && !this.loading,
        catalogOffered: this.document.catalogOffered, catalogEnabled: this.document.candidates.length > 0,
        customOffered: this.document.customOffered,
        customEnabled: this.document.customRevision >= 0 && this.document.protocols.length > 0,
        catalogBusy: this.catalogBusy, customBusy: this.customBusy, options: this.options(),
        selectedProvider: this.selected?.provider ?? '', selectedDisplayName: this.selected?.displayName ?? '',
        catalogDraftVisible: this.selected !== undefined,
        catalogEditor: (): void => { this.CatalogEditor(); }, customEditor: (): void => { this.CustomEditor(); },
        onOpen: (): void => { this.show(); }, onCancel: (): void => { this.close(false); },
        onModeChange: (value: DesktopAddModelProviderMode): void => { this.mode = value; },
        onProviderChange: (provider: string): void => { this.choose(provider); } })
    }.width('100%')
  }
}
