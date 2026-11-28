import { baseURLPlaceholder, buildRouteProfile, checkBaseURL, checkModels, checkPiAiModelReasoning, checkProtocol,
  checkRoute, deriveKeyRef, emptyModelRow, emptyProviderView, invalidPiAiCapacity, modelsDiffer, PIAI_SETTINGS_NS, piAiReasoningProtocol,
  SessionHub, SettingsWriteOutcome, Sp } from 'appstate';
import type { PiAiModelRow, PiAiProviderView } from 'appstate';
import { getArray, getNumber, getString } from 'connection';
import { deepSeekApiKeyProblem } from '../desktop/DesktopDeepSeekProviderModel';
import { desktopDeepSeekCatalogProblem } from '../desktop/DesktopDeepSeekCatalog';
import type { DesktopHostActions } from '../desktop/DesktopHostActions';
import { desktopCatalogActivationOperations } from '../desktop/DesktopProviderAddModel';
import type { DesktopAddProviderDocument, DesktopCatalogCandidate } from '../desktop/DesktopProviderAddModel';
import { desktopPiAiAdoptedKeys, desktopPiAiModelInsertionIndex } from '../desktop/DesktopPiAiModelOrder';
import { desktopPiAiReasoningLabel } from '../desktop/DesktopPiAiReasoning';
import { desktopPiAiEditOperations } from '../desktop/DesktopPiAiEditModel';
import type { DesktopPiAiExistingProfile } from '../desktop/DesktopPiAiEditModel';
import { readDesktopRetryDocument } from '../desktop/DesktopRetryPolicyModel';
import type { DesktopRetryChange, DesktopRetryDocument } from '../desktop/DesktopRetryPolicyModel';
import { PiAiProviderSheet, PiAiSheetMode } from './PiAiProviderSheet';

@Component
export struct DesktopPiAiAddProfile {
  @Prop document: DesktopAddProviderDocument;
  @Prop candidate: DesktopCatalogCandidate | undefined = undefined;
  @Prop existing: DesktopPiAiExistingProfile | undefined = undefined;
  @Prop existingWritable: boolean = false;
  @Prop inlineViewport: Area | undefined = undefined;
  inlineScroller?: Scroller;
  host?: DesktopHostActions;
  onCancel: () => void = (): void => {};
  onSaved: () => void = (): void => {};
  onBusy: (busy: boolean) => void = (): void => {};

  @State private draft: PiAiProviderView = emptyProviderView('');
  @State private modelKeys: number[] = [];
  @State private keyDraft: string = '';
  @State private keyClearPending: boolean = false;
  @State private keyClearApplied: boolean = false;
  @State private saving: boolean = false;
  @State private discovering: boolean = false;
  @State private committed: boolean = false;
  @State private conflict: boolean = false;
  @State private keyFailure: ResourceStr = '';
  @State private modelOverride: boolean = false;
  @State private retry: DesktopRetryChange = { operations: [], problem: '', problemField: '' };
  private nextKey: number = 0;
  private mounted: boolean = false;
  private revision: number = -1;
  private retryDocument?: DesktopRetryDocument;

  aboutToAppear(): void {
    this.mounted = true;
    const candidate = this.candidate;
    if (this.existing !== undefined) {
      const original = this.existing.original;
      this.draft = { route: original.route, displayName: original.displayName, baseURL: original.baseURL,
        api: original.api, apiKeyEnv: original.apiKeyEnv, defaultInput: original.defaultInput,
        models: original.models.slice(), modelLayer: original.modelLayer };
      this.modelKeys = this.draft.models.map((_model: PiAiModelRow): number => ++this.nextKey);
      this.modelOverride = original.modelLayer?.userOverride === true;
      this.revision = this.existing.row.revision;
      this.retryDocument = readDesktopRetryDocument(this.document.describe, this.existing.row.namespace, this.retryPath());
      return;
    }
    const draft = emptyProviderView(candidate === undefined ? this.document.protocols[0] ?? '' : '');
    draft.route = candidate?.provider ?? '';
    draft.models = [];
    this.draft = draft;
    this.revision = candidate?.revision ?? this.document.customRevision;
    if (candidate !== undefined) {
      this.retryDocument = readDesktopRetryDocument(this.document.describe, candidate.namespace, this.retryPath());
    }
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.keyDraft = '';
    if (this.saving || this.discovering) { this.onBusy(false); }
  }

  private retryPath(): string[] { return [...(this.existing?.row.path ?? this.candidate?.path ?? []), 'retryPolicy']; }

  private keyRef(): string {
    return this.existing?.row.credentialRef || (this.draft.route.trim() ? deriveKeyRef(this.draft.route.trim()) : '');
  }

  private canWrite(): boolean { return this.existing === undefined ? this.document.writable : this.existingWritable; }

  private canClearExistingKey(): boolean {
    const record = this.existing?.row.credential;
    return record?.configured === true && record.writable && record.source === 'file' && !this.keyClearApplied;
  }

  private unavailableMessage(): Resource {
    return $r('app.string.desktop_catalog_provider_unavailable', this.candidate?.provider ?? '');
  }

  private keyHint(): ResourceStr {
    if (this.existing !== undefined) {
      const credential = this.existing.row.credential;
      if (!this.keyClearPending && !this.keyClearApplied && credential?.configured && credential.source === 'file') {
        return credential.masked || '••••••••';
      }
    }
    const env = this.candidate?.nativeEnv[0];
    return env === undefined ? '' : $r('app.string.desktop_catalog_provider_env', env);
  }

  private endpointHint(): string {
    if (this.existing !== undefined) { return this.existing.endpointPlaceholder || baseURLPlaceholder(this.draft.api); }
    return this.candidate === undefined ? baseURLPlaceholder(this.draft.api) :
      this.candidate.endpoint || this.candidate.endpointEnv.join(' / ');
  }

  private validation(): ResourceStr {
    const key = deepSeekApiKeyProblem(this.keyDraft);
    if (key) { return key === 'blank' ? $r('app.string.desktop_deepseek_key_blank') :
      $r('app.string.desktop_deepseek_key_format'); }
    if (this.committed) { return ''; }
    const existing = this.existing;
    if (existing !== undefined) {
      if (this.draft.api !== existing.original.api && this.draft.api.length > 0) {
        const api = checkProtocol(this.draft.api, this.document.protocols);
        if (!api.ok) { return api.message; }
      }
      if (this.draft.api === 'google-generative-ai' && !existing.row.credentialRef && !this.keyDraft.trim()) {
        return $r('app.string.desktop_catalog_provider_required_key');
      }
    } else if (this.candidate === undefined) {
      const route = checkRoute(this.draft.route, this.document.taken);
      if (!route.ok) { return route.message; }
      if (this.draft.api === 'google-generative-ai' && !this.keyDraft.trim()) {
        return $r('app.string.desktop_catalog_provider_required_key');
      }
      const api = checkProtocol(this.draft.api, this.document.protocols);
      if (!api.ok) { return api.message; }
      const models = checkModels(this.draft.models);
      if (!models.ok) { return models.message; }
    }
    if ((existing === undefined && this.candidate === undefined) ||
        (this.draft.baseURL.trim() && this.draft.baseURL !== existing?.original.baseURL)) {
      const endpoint = checkBaseURL(this.draft.baseURL);
      if (!endpoint.ok) { return endpoint.message; }
    }
    const models = desktopDeepSeekCatalogProblem(this.draft.models);
    if (models !== '') { return models; }
    const protocol = piAiReasoningProtocol(this.draft.api, this.document.reasoningLevels);
    for (const model of this.draft.models) {
      const problem = checkPiAiModelReasoning(model, protocol);
      if (problem) { return desktopPiAiReasoningLabel(problem); }
    }
    return '';
  }

  private modelChanged(index: number, row: PiAiModelRow): void {
    const previous = this.draft.models[index];
    if (previous === undefined) { return; }
    if (modelsDiffer([previous], [row]) || invalidPiAiCapacity(row.contextWindow) ||
      invalidPiAiCapacity(row.maxTokens)) { this.modelOverride = true; }
    this.draft.models = this.draft.models.map((item: PiAiModelRow, at: number): PiAiModelRow => at === index ? row : item);
  }

  private adoptModels(models: PiAiModelRow[]): void {
    this.modelKeys = desktopPiAiAdoptedKeys(this.draft.models, this.modelKeys, models, (): number => ++this.nextKey);
    this.draft.models = models;
    this.modelOverride = true;
  }

  private moveModel(source: number, target: number, after: boolean): void {
    const from = this.modelKeys.indexOf(source);
    const to = desktopPiAiModelInsertionIndex(this.modelKeys, source, target, after);
    if (from < 0 || to < 0) { return; }
    const models = this.draft.models.slice();
    const keys = this.modelKeys.slice();
    const row = models[from];
    models.splice(from, 1);
    keys.splice(from, 1);
    models.splice(to, 0, row);
    keys.splice(to, 0, source);
    this.draft.models = models;
    this.modelKeys = keys;
    this.modelOverride = true;
  }

  private operations(key: string, ref: string): Record<string, Object>[] {
    if (this.existing !== undefined) {
      return desktopPiAiEditOperations(this.existing, this.draft, this.modelOverride, key.length > 0,
        this.keyClearPending || this.keyClearApplied, this.retry.operations);
    }
    if (this.candidate !== undefined) {
      return desktopCatalogActivationOperations(this.candidate, this.draft.baseURL.trim(), key, this.modelOverride,
        this.draft.models, this.retry.operations);
    }
    const profile = buildRouteProfile(this.draft, key.length > 0, ref);
    return [{ 'op': 'set', 'path': ['providers', this.draft.route.trim()], 'value': profile }];
  }

  private async save(): Promise<void> {
    if (this.saving || this.discovering || !this.canWrite() || this.conflict || this.revision < 0 ||
      this.validation() !== '' || this.retry.problem || this.candidate?.editable === false) { return; }
    const candidate = this.candidate;
    const ref = this.keyRef();
    const key = this.keyDraft.trim();
    const hub = SessionHub.shared();
    this.keyFailure = '';
    this.saving = true;
    this.onBusy(true);
    try {
      const operations = this.committed ? [] : this.operations(key, ref);
      if (this.existing !== undefined && ((this.keyClearPending && !this.keyClearApplied) || (key && operations.length === 0))) {
        const description = await hub.readSettingsDescription();
        if (!this.mounted) { return; }
        const namespace = getArray(description.value, 'namespaces')?.find((entry: Object): boolean =>
          getString(entry, 'ns') === this.existing?.row.namespace);
        if (!description.ok || getNumber(namespace, 'revision') !== this.revision) {
          this.conflict = description.ok;
          this.keyFailure = $r('app.string.desktop_model_provider_edit_conflict');
          return;
        }
      }
      if (this.keyClearPending && !this.keyClearApplied) {
        const cleared = await hub.unsetCredential(ref);
        if (!this.mounted) { return; }
        if (!cleared.ok) { this.keyFailure = cleared.message; return; }
        this.keyClearApplied = true;
      }
      if (!this.committed) {
        if (operations.length > 0) {
          const reply = await hub.mutateSettingPaths(this.existing?.row.namespace ?? candidate?.namespace ?? PIAI_SETTINGS_NS,
            operations, this.revision);
          if (!this.mounted) { return; }
          if (reply.outcome !== SettingsWriteOutcome.OK) {
            this.conflict = reply.outcome === SettingsWriteOutcome.CONFLICT;
            this.keyFailure = reply.message;
            return;
          }
          this.revision = reply.actualRevision;
          this.committed = true;
        }
      }
      if (key) {
        const reply = await hub.setCredential(ref, key);
        if (!this.mounted) { return; }
        if (!reply.ok) {
          this.keyFailure = this.committed ? $r('app.string.desktop_deepseek_key_after_settings', reply.message) : reply.message;
          return;
        }
      }
      this.keyDraft = '';
      this.onSaved();
    } catch (_) {
      if (this.mounted) { this.keyFailure = $r('app.string.desktop_catalog_provider_save_failed'); }
    } finally {
      if (this.mounted) {
        this.saving = false;
        this.onBusy(this.discovering);
      }
    }
  }

  private restoreModels(): void {
    const inherited = this.existing?.original.modelLayer?.inherited ?? [];
    this.draft.models = inherited.slice();
    this.modelKeys = inherited.map((_model: PiAiModelRow): number => ++this.nextKey);
    this.modelOverride = false;
  }

  build() {
    Column({ space: Sp.S }) {
      if (this.candidate?.editable === false) {
        Text(this.unavailableMessage())
          .key('desktopCatalogProviderUnavailable').width('100%').fontSize(13).fontColor($r('sys.color.alert'))
        Button($r('app.string.desktop_deepseek_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPiAiProviderCancel').onClick(this.onCancel)
      } else {
        PiAiProviderSheet({ inline: true, mode: this.existing !== undefined ? PiAiSheetMode.EDIT :
          this.candidate === undefined ? PiAiSheetMode.CREATE : PiAiSheetMode.CATALOG,
          existingDeclared: this.existing?.row.declared === true, existingDisplayName: this.existing?.row.displayName ?? '',
          existingDisplayNamePlaceholder: this.existing?.namePlaceholder ?? '', inlineScroller: this.inlineScroller,
          inlineViewport: this.inlineViewport, existingKeyCanClear: this.canClearExistingKey(),
          existingKeyClearPending: this.keyClearPending, existingKeyClearApplied: this.keyClearApplied,
          onExistingKeyClear: (): void => {
            if (this.canWrite() && this.canClearExistingKey() && !this.saving && !this.discovering && !this.committed) {
              this.keyClearPending = !this.keyClearPending;
            }
          },
          locked: !this.canWrite() || this.conflict, profileCommitted: this.committed,
          submitBlocked: this.validation() !== '', draft: this.draft, modelKeys: this.modelKeys,
          catalogStandard: this.candidate !== undefined || this.existing?.catalog === true, catalogWritable: this.canWrite(),
          modelsOverridden: this.modelOverride, protocols: this.document.protocols,
          reasoningLevels: this.document.reasoningLevels, baseURLPlaceholder: this.endpointHint(),
          hideKey: this.candidate?.keyless === true || this.existing?.keyless === true, keyDraft: this.keyDraft, keyRef: this.keyRef(),
          keyPlaceholder: this.keyHint(), busy: this.saving, notice: this.keyFailure || this.validation(),
          retryPath: this.retryPath(), retryDocument: this.retryDocument, retryValid: !this.retry.problem,
          retryHost: this.host,
          onRetryOperations: (value: DesktopRetryChange): void => { this.retry = value; },
          onDiscoveryBusy: (value: boolean): void => { this.discovering = value; this.onBusy(value || this.saving); },
          onRouteChange: (value: string): void => { this.draft.route = value; },
          onDisplayNameChange: (value: string): void => { this.draft.displayName = value; },
          onBaseURLChange: (value: string): void => { this.draft.baseURL = value; },
          onApiChange: (value: string): void => { this.draft.api = value; },
          onKeyChange: (value: string): void => { this.keyDraft = value; if (value) { this.keyClearPending = false; } },
          onModelChange: (at: number, row: PiAiModelRow): void => { this.modelChanged(at, row); },
          onAddModel: (): void => {
            this.draft.models = [...this.draft.models, emptyModelRow()];
            this.modelKeys = [...this.modelKeys, ++this.nextKey];
            this.modelOverride = true;
          },
          onRemoveModel: (at: number): void => {
            this.draft.models = this.draft.models.filter((_row: PiAiModelRow, index: number): boolean => index !== at);
            this.modelKeys = this.modelKeys.filter((_key: number, index: number): boolean => index !== at);
            this.modelOverride = true;
          },
          onRestoreModels: (): void => { this.restoreModels(); },
          onAdoptModels: (value: PiAiModelRow[]): void => { this.adoptModels(value); },
          onMoveModel: (source: number, target: number, after: boolean): void => { this.moveModel(source, target, after); },
          onClose: this.onCancel, onSubmit: (): void => { this.save(); } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
