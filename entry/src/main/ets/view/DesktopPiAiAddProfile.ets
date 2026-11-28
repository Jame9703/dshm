import { baseURLPlaceholder, buildRouteProfile, checkBaseURL, checkModels, checkPiAiModelReasoning, checkProtocol,
  checkRoute, deriveKeyRef, emptyModelRow, emptyProviderView, invalidPiAiCapacity, modelsDiffer, PIAI_SETTINGS_NS, piAiReasoningProtocol,
  SessionHub, SettingsWriteOutcome, Sp } from 'appstate';
import type { PiAiModelRow, PiAiProviderView } from 'appstate';
import { deepSeekApiKeyProblem } from '../desktop/DesktopDeepSeekProviderModel';
import { desktopDeepSeekCatalogProblem } from '../desktop/DesktopDeepSeekCatalog';
import type { DesktopHostActions } from '../desktop/DesktopHostActions';
import { desktopCatalogActivationOperations } from '../desktop/DesktopProviderAddModel';
import type { DesktopAddProviderDocument, DesktopCatalogCandidate } from '../desktop/DesktopProviderAddModel';
import { desktopPiAiAdoptedKeys, desktopPiAiModelInsertionIndex } from '../desktop/DesktopPiAiModelOrder';
import { desktopPiAiReasoningLabel } from '../desktop/DesktopPiAiReasoning';
import { readDesktopRetryDocument } from '../desktop/DesktopRetryPolicyModel';
import type { DesktopRetryChange, DesktopRetryDocument } from '../desktop/DesktopRetryPolicyModel';
import { PiAiProviderSheet, PiAiSheetMode } from './PiAiProviderSheet';

@Component
export struct DesktopPiAiAddProfile {
  @Prop document: DesktopAddProviderDocument;
  @Prop candidate: DesktopCatalogCandidate | undefined = undefined;
  host?: DesktopHostActions;
  onCancel: () => void = (): void => {};
  onSaved: () => void = (): void => {};
  onBusy: (busy: boolean) => void = (): void => {};

  @State private draft: PiAiProviderView = emptyProviderView('');
  @State private modelKeys: number[] = [];
  @State private keyDraft: string = '';
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
  }

  private retryPath(): string[] { return [...(this.candidate?.path ?? []), 'retryPolicy']; }

  private keyRef(): string { return this.draft.route.trim() ? deriveKeyRef(this.draft.route.trim()) : ''; }

  private unavailableMessage(): Resource {
    return $r('app.string.desktop_catalog_provider_unavailable', this.candidate?.provider ?? '');
  }

  private keyHint(): ResourceStr {
    const env = this.candidate?.nativeEnv[0];
    return env === undefined ? '' : $r('app.string.desktop_catalog_provider_env', env);
  }

  private endpointHint(): string {
    return this.candidate === undefined ? baseURLPlaceholder(this.draft.api) :
      this.candidate.endpoint || this.candidate.endpointEnv.join(' / ');
  }

  private validation(): ResourceStr {
    const key = deepSeekApiKeyProblem(this.keyDraft);
    if (key) { return key === 'blank' ? $r('app.string.desktop_deepseek_key_blank') :
      $r('app.string.desktop_deepseek_key_format'); }
    if (this.committed) { return ''; }
    if (this.candidate === undefined) {
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
    if (this.candidate === undefined || this.draft.baseURL.trim()) {
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
    if (this.candidate !== undefined) {
      return desktopCatalogActivationOperations(this.candidate, this.draft.baseURL.trim(), key, this.modelOverride,
        this.draft.models, this.retry.operations);
    }
    const profile = buildRouteProfile(this.draft, key.length > 0, ref);
    return [{ 'op': 'set', 'path': ['providers', this.draft.route.trim()], 'value': profile }];
  }

  private async save(): Promise<void> {
    if (this.saving || this.discovering || !this.document.writable || this.conflict || this.revision < 0 ||
      this.validation() !== '' || this.retry.problem || this.candidate?.editable === false) { return; }
    const candidate = this.candidate;
    const ref = this.keyRef();
    const key = this.keyDraft.trim();
    const hub = SessionHub.shared();
    this.keyFailure = '';
    this.saving = true;
    this.onBusy(true);
    try {
      if (!this.committed) {
        const reply = await hub.mutateSettingPaths(candidate?.namespace ?? PIAI_SETTINGS_NS,
          this.operations(key, ref), this.revision);
        if (!this.mounted) { return; }
        if (reply.outcome !== SettingsWriteOutcome.OK) {
          this.conflict = reply.outcome === SettingsWriteOutcome.CONFLICT;
          this.keyFailure = reply.message;
          return;
        }
        this.committed = true;
      }
      if (key) {
        const reply = await hub.setCredential(ref, key);
        if (!this.mounted) { return; }
        if (!reply.ok) {
          this.keyFailure = $r('app.string.desktop_deepseek_key_after_settings', reply.message);
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

  build() {
    Column({ space: Sp.S }) {
      if (this.candidate?.editable === false) {
        Text(this.unavailableMessage())
          .key('desktopCatalogProviderUnavailable').width('100%').fontSize(13).fontColor($r('sys.color.alert'))
        Button($r('app.string.desktop_deepseek_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPiAiProviderCancel').onClick(this.onCancel)
      } else {
        PiAiProviderSheet({ inline: true, mode: this.candidate === undefined ? PiAiSheetMode.CREATE : PiAiSheetMode.CATALOG,
          locked: !this.document.writable || this.conflict, profileCommitted: this.committed,
          submitBlocked: this.validation() !== '', draft: this.draft, modelKeys: this.modelKeys,
          catalogStandard: this.candidate !== undefined, catalogWritable: this.document.writable,
          modelsOverridden: this.modelOverride, protocols: this.document.protocols,
          reasoningLevels: this.document.reasoningLevels, baseURLPlaceholder: this.endpointHint(),
          hideKey: this.candidate?.keyless === true, keyDraft: this.keyDraft, keyRef: this.keyRef(),
          keyPlaceholder: this.keyHint(), busy: this.saving, notice: this.keyFailure || this.validation(),
          retryPath: this.retryPath(), retryDocument: this.retryDocument, retryValid: !this.retry.problem,
          retryHost: this.host,
          onRetryOperations: (value: DesktopRetryChange): void => { this.retry = value; },
          onDiscoveryBusy: (value: boolean): void => { this.discovering = value; this.onBusy(value || this.saving); },
          onRouteChange: (value: string): void => { this.draft.route = value; },
          onDisplayNameChange: (value: string): void => { this.draft.displayName = value; },
          onBaseURLChange: (value: string): void => { this.draft.baseURL = value; },
          onApiChange: (value: string): void => { this.draft.api = value; },
          onKeyChange: (value: string): void => { this.keyDraft = value; },
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
          onRestoreModels: (): void => { this.draft.models = []; this.modelKeys = []; this.modelOverride = false; },
          onAdoptModels: (value: PiAiModelRow[]): void => { this.adoptModels(value); },
          onMoveModel: (source: number, target: number, after: boolean): void => { this.moveModel(source, target, after); },
          onClose: this.onCancel, onSubmit: (): void => { this.save(); } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
