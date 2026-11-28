import { checkBaseURL, Radius, SessionHub, SettingsWriteOutcome, Sp } from 'appstate';
import type { CredentialItem, PiAiModelRow } from 'appstate';
import { desktopHostProblem } from '../desktop/DesktopHostActions';
import { desktopMenuOptions } from '../desktop/DesktopMenuOptions';
import { DesktopRetryPolicy } from '../desktop/DesktopRetryPolicy';
import { readDesktopRetryDocument } from '../desktop/DesktopRetryPolicyModel';
import type { DesktopRetryChange, DesktopRetryDocument } from '../desktop/DesktopRetryPolicyModel';
import { desktopDeepSeekCatalogProblem } from '../desktop/DesktopDeepSeekCatalog';
import { DEEPSEEK_SETTINGS_NS, deepSeekApiKeyProblem, deepSeekCatalogEqual, deepSeekProviderOperations,
  readDesktopDeepSeekCredential, readDesktopDeepSeekProvider } from '../desktop/DesktopDeepSeekProviderModel';
import type { DesktopDeepSeekCredential, DesktopDeepSeekProviderDocument } from '../desktop/DesktopDeepSeekProviderModel';
import { DesktopDeepSeekModelsEditor } from './DesktopDeepSeekModelsEditor';

const RETRY_PATH: string[] = ['retryPolicy'];

@Component
export struct DesktopDeepSeekProvider {
  @Prop credentials: CredentialItem[] = [];
  @State private isOpen: boolean = false;
  @State private loading: boolean = false;
  @State private busy: boolean = false;
  @State private conflict: boolean = false;
  @State private notice: ResourceStr = '';
  @State private advanced: boolean = false;
  @State private original: DesktopDeepSeekProviderDocument | undefined = undefined;
  @State private credential: DesktopDeepSeekCredential | undefined = undefined;
  @State private keyDraft: string = '';
  @State private keyClearPending: boolean = false;
  @State private keyClearApplied: boolean = false;
  @State private endpoint: string = '';
  @State private models: PiAiModelRow[] = [];
  @State private modelsOverridden: boolean = false;
  @State private draftVersion: number = 0;
  @State private retryDocument: DesktopRetryDocument | undefined = undefined;
  @State private retryChange: DesktopRetryChange = { operations: [], problem: '', problemField: '' };
  @State private authHelp: boolean = false;
  private generation: number = 0;

  aboutToDisappear(): void { this.closeEditor(); }

  private closeEditor(): void {
    this.generation++;
    this.keyDraft = '';
    this.keyClearPending = false;
    this.keyClearApplied = false;
    this.authHelp = false;
    this.isOpen = false;
    this.loading = false;
    this.busy = false;
    this.advanced = false;
    this.conflict = false;
    this.notice = '';
    this.original = undefined;
    this.credential = undefined;
    this.retryDocument = undefined;
    this.retryChange = { operations: [], problem: '', problemField: '' };
  }

  private async openEditor(): Promise<void> {
    this.closeEditor();
    const generation = this.generation;
    this.isOpen = true;
    this.loading = true;
    const hub = SessionHub.shared();
    try {
      const reply = await hub.readSettingsDescription();
      if (generation !== this.generation) { return; }
      const document = reply.ok ? readDesktopDeepSeekProvider(reply.value) : undefined;
      if (document === undefined) {
        this.notice = reply.ok ? $r('app.string.desktop_deepseek_unavailable') : desktopHostProblem(reply);
        return;
      }
      this.endpoint = document.userEndpoint;
      this.models = (document.userModels ?? document.inheritedModels).slice();
      this.modelsOverridden = document.userModels !== undefined;
      this.draftVersion++;
      this.retryDocument = readDesktopRetryDocument(reply.value, DEEPSEEK_SETTINGS_NS, RETRY_PATH);
      const credential = await hub.readCredentialDescription(document.credentialRef);
      if (generation !== this.generation) { return; }
      this.credential = credential.ok ? readDesktopDeepSeekCredential(credential.value, document.credentialRef) : undefined;
      this.original = document;
    } catch (_) {
      if (generation === this.generation) { this.notice = $r('app.string.desktop_deepseek_unavailable'); }
    } finally {
      if (generation === this.generation) { this.loading = false; }
    }
  }

  private canEdit(): boolean { return this.original?.writable === true && !this.loading && !this.busy && !this.conflict; }

  private changeModels(models: PiAiModelRow[]): void {
    if (!this.canEdit()) { return; }
    if (deepSeekCatalogEqual(this.models, models) && desktopDeepSeekCatalogProblem(models) === '') { return; }
    this.models = models;
    this.modelsOverridden = true;
  }

  private restoreModels(): void {
    if (!this.canEdit() || this.original === undefined) { return; }
    this.models = this.original.inheritedModels.slice();
    this.modelsOverridden = false;
    this.draftVersion++;
  }

  private keyProblem(): ResourceStr {
    const problem = deepSeekApiKeyProblem(this.keyDraft);
    if (problem === 'blank') { return $r('app.string.desktop_deepseek_key_blank'); }
    return problem ? $r('app.string.desktop_deepseek_key_format') : '';
  }

  private credentialRef(): string { return this.original?.credentialRef ?? ''; }

  private keyPlaceholder(): ResourceStr {
    if (this.credential?.configured === true && this.credential.source === 'file' && !this.keyClearPending) {
      return this.credential.masked || '••••••••';
    }
    return $r('app.string.desktop_deepseek_key_placeholder', this.credentialRef());
  }

  private endpointPlaceholder(): ResourceStr {
    return this.original?.inheritedEndpoint || $r('app.string.desktop_deepseek_endpoint_placeholder');
  }

  private async save(): Promise<void> {
    const original = this.original;
    if (!this.canEdit() || original === undefined) { return; }
    this.notice = '';
    if (this.modelsOverridden && desktopDeepSeekCatalogProblem(this.models) !== '') {
      this.advanced = true;
      return;
    }
    const endpoint = this.endpoint === original.userEndpoint ? this.endpoint : this.endpoint.trim();
    if (endpoint && endpoint !== original.userEndpoint && !checkBaseURL(endpoint).ok) {
      this.advanced = true;
      this.notice = $r('app.string.desktop_deepseek_endpoint_invalid');
      return;
    }
    if (this.keyProblem() !== '' || this.retryChange.problem) { return; }
    const operations = deepSeekProviderOperations(original, endpoint, this.modelsOverridden, this.models,
      this.retryChange.operations);
    const generation = this.generation;
    const hub = SessionHub.shared();
    this.busy = true;
    try {
      if (this.keyClearPending && !this.keyClearApplied) {
        const cleared = await hub.unsetCredential(original.credentialRef);
        if (generation !== this.generation) { return; }
        if (!cleared.ok) { this.notice = cleared.message; return; }
        this.keyClearApplied = true;
      }
      if (operations.length > 0) {
        const write = await hub.mutateSettingPaths(DEEPSEEK_SETTINGS_NS, operations, original.revision);
        if (generation !== this.generation) { return; }
        if (write.outcome !== SettingsWriteOutcome.OK) {
          this.conflict = write.outcome === SettingsWriteOutcome.CONFLICT;
          this.notice = write.message;
          return;
        }
        this.original = { revision: write.actualRevision, writable: original.writable,
          credentialRef: original.credentialRef, userEndpoint: endpoint, inheritedEndpoint: original.inheritedEndpoint,
          contextCapacity: original.contextCapacity, outputCapacity: original.outputCapacity,
          inheritedModels: original.inheritedModels, userModels: this.modelsOverridden ? this.models.slice() : undefined };
        this.retryChange = { operations: [], problem: '', problemField: '' };
      }
      const key = this.keyDraft.trim();
      if (key.length > 0) {
        const credential = await hub.setCredential(original.credentialRef, key);
        if (generation !== this.generation) { return; }
        if (!credential.ok) {
          this.notice = operations.length > 0 ? $r('app.string.desktop_deepseek_key_after_settings', credential.message) :
            credential.message;
          if (operations.length > 0 && this.retryDocument !== undefined) {
            const current = await hub.readSettingsDescription();
            if (generation === this.generation && current.ok) {
              const document = readDesktopRetryDocument(current.value, DEEPSEEK_SETTINGS_NS, RETRY_PATH);
              if (document?.revision === this.original?.revision) { this.retryDocument = document; }
            }
          }
          return;
        }
      }
      this.closeEditor();
    } catch (_) {
      if (generation === this.generation) { this.notice = $r('app.string.desktop_deepseek_save_failed'); }
    } finally {
      if (generation === this.generation) { this.busy = false; }
    }
  }

  @Builder
  private CredentialHelp() {
    Text($r('app.string.desktop_deepseek_key_help', this.credentialRef())).fontSize(12)
      .padding(12).constraintSize({ maxWidth: 300 }).fontColor($r('sys.color.font_primary'))
  }

  @Builder
  private Credential() {
    Row({ space: 6 }) {
      Text($r('app.string.desktop_deepseek_key_label')).fontSize(13)
      Button('?', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(24).height(24).padding(0)
        .accessibilityText($r('app.string.desktop_deepseek_auth_help'))
        .onClick((): void => { this.authHelp = !this.authHelp; })
        .bindPopup(this.authHelp, { builder: this.CredentialHelp(), placement: Placement.Right, enableArrow: false,
          systemMaterial: desktopMenuOptions(Placement.Right).systemMaterial,
          onStateChange: (event): void => { if (!event.isVisible) { this.authHelp = false; } } })
    }.width('100%')
    TextInput({ text: this.keyDraft, placeholder: this.keyPlaceholder() })
      .key('desktopDeepSeekProviderKey').type(InputType.Password).showPasswordIcon(true)
      .accessibilityText($r('app.string.desktop_deepseek_key_label'))
      .enabled(this.canEdit() && !this.keyClearApplied && this.credential?.writable !== false)
      .onChange((value: string): void => {
        if (value === this.keyDraft) { return; }
        this.keyDraft = value;
        this.keyClearPending = false;
      })
    if (this.keyProblem() !== '') {
      Text(this.keyProblem()).fontSize(12).fontColor($r('app.color.workspace_status_error')).width('100%')
    }
    if (this.credential?.source === 'file' && this.credential?.configured === true && this.credential?.writable === true) {
      if (this.keyDraft.length === 0 && !this.keyClearApplied) {
        Button(this.keyClearPending ? $r('app.string.desktop_deepseek_key_keep') :
          $r('app.string.desktop_deepseek_key_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopDeepSeekProviderKeyClear').enabled(this.canEdit())
          .onClick((): void => { this.keyClearPending = !this.keyClearPending; })
      }
      Text(this.keyClearApplied ? $r('app.string.desktop_deepseek_key_removed') : this.keyClearPending ?
        $r('app.string.desktop_deepseek_key_queued') : this.keyDraft.length > 0 ?
        $r('app.string.desktop_deepseek_key_replace') : $r('app.string.desktop_deepseek_key_saved'))
        .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
    }
  }

  @Builder
  private Editor() {
    Column({ space: Sp.S }) {
      this.Credential()
      Button($r('app.string.desktop_deepseek_advanced'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopDeepSeekProviderAdvanced').accessibilitySelected(this.advanced)
        .onClick((): void => { this.advanced = !this.advanced; })
      Column({ space: Sp.S }) {
        Text($r('app.string.desktop_deepseek_endpoint')).fontSize(13).width('100%')
        TextInput({ text: this.endpoint, placeholder: this.endpointPlaceholder() })
          .key('desktopDeepSeekProviderEndpoint').enabled(this.canEdit()).onChange((value: string): void => {
            this.endpoint = value;
          })
        Text($r('app.string.desktop_deepseek_endpoint_hint')).fontSize(12).width('100%')
          .fontColor($r('sys.color.font_secondary'))
        if (this.retryDocument !== undefined) {
          DesktopRetryPolicy({ namespace: DEEPSEEK_SETTINGS_NS, path: RETRY_PATH, suppliedDocument: this.retryDocument,
            draftOnly: true, parentBusy: !this.canEdit(), onOperations: (change: DesktopRetryChange): void => {
              this.retryChange = change;
            } })
        }
        DesktopDeepSeekModelsEditor({ models: this.models, overridden: this.modelsOverridden, disabled: !this.canEdit(),
          draftVersion: this.draftVersion, defaultContextWindow: this.original?.contextCapacity ?? 0,
          defaultMaxTokens: this.original?.outputCapacity ?? 0,
          onChange: (models: PiAiModelRow[]): void => { this.changeModels(models); },
          onReset: (): void => { this.restoreModels(); } })
      }.width('100%').alignItems(HorizontalAlign.Start).visibility(this.advanced ? Visibility.Visible : Visibility.None)
      if (this.notice !== '') {
        Text(this.notice).key('desktopDeepSeekProviderError').fontSize(12).width('100%')
          .fontColor($r('app.color.workspace_status_error'))
      }
      if (!this.advanced && this.modelsOverridden && desktopDeepSeekCatalogProblem(this.models) !== '') {
        Text(desktopDeepSeekCatalogProblem(this.models)).fontSize(12).width('100%')
          .fontColor($r('app.color.workspace_status_error'))
      }
      Row({ space: Sp.S }) {
        Blank()
        Button($r('app.string.desktop_deepseek_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopDeepSeekProviderCancel').enabled(!this.busy).onClick((): void => { this.closeEditor(); })
        Button($r('app.string.desktop_deepseek_save'), { buttonStyle: ButtonStyleMode.EMPHASIZED })
          .key('desktopDeepSeekProviderSave').enabled(this.canEdit() && this.keyProblem() === '' &&
            !this.retryChange.problem && (!this.modelsOverridden || desktopDeepSeekCatalogProblem(this.models) === ''))
          .onClick((): void => { this.save(); })
      }.width('100%')
    }.key('desktopDeepSeekProviderEditor').width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: Sp.S }) {
      Row({ space: Sp.S }) {
        Column({ space: 4 }) {
          Text($r('app.string.desktop_deepseek_provider')).fontSize(16)
          Text($r('app.string.desktop_deepseek_route')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (!this.isOpen) {
          if (this.credentials.some((entry: CredentialItem): boolean => entry.namespace === DEEPSEEK_SETTINGS_NS &&
              entry.configured)) {
            Text($r('app.string.desktop_deepseek_key_configured')).fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          Button($r('app.string.desktop_deepseek_edit'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopDeepSeekProviderEdit').onClick((): void => { this.openEditor(); })
        }
      }.width('100%')
      if (this.loading) {
        LoadingProgress().width(22).height(22)
      } else if (this.original !== undefined) {
        this.Editor()
      } else if (this.isOpen) {
        Text(this.notice).fontSize(12).width('100%').fontColor($r('app.color.workspace_status_error'))
        Row({ space: Sp.S }) {
          Button($r('app.string.desktop_deepseek_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopDeepSeekProviderCancel').onClick((): void => { this.closeEditor(); })
          Button($r('app.string.desktop_deepseek_reload'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick((): void => { this.openEditor(); })
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(Sp.M).borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
  }
}
