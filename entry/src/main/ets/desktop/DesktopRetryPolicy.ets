import type { RpcResult } from 'connection';
import { SETTINGS_CONFLICT, SETTINGS_DESCRIBE_ENDPOINT, SETTINGS_MUTATE_ENDPOINT } from 'dshcompat';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { desktopNewRetryPolicy, desktopRetryChange, desktopRetryDraft, desktopRetryMode, readDesktopRetryDocument,
  switchDesktopRetryMode } from './DesktopRetryPolicyModel';
import type { DesktopRetryChange, DesktopRetryDocument, DesktopRetryDraft,
  DesktopNewRetryPolicy, DesktopRetryField } from './DesktopRetryPolicyModel';

function modeLabel(id: string): ResourceStr {
  if (id === 'normal') { return $r('app.string.desktop_model_retry_normal'); }
  if (id === 'always') { return $r('app.string.desktop_model_retry_always'); }
  return id;
}

function fieldLabel(id: string): ResourceStr {
  switch (id) {
    case 'maxRetries': return $r('app.string.desktop_model_retry_max_retries');
    case 'backoff.initialDelayMs': return $r('app.string.desktop_model_retry_initial_delay');
    case 'backoff.maxDelayMs': return $r('app.string.desktop_model_retry_max_delay');
    case 'backoff.jitterRatio': return $r('app.string.desktop_model_retry_jitter');
    default: return id;
  }
}

function codeLabel(id: string): ResourceStr {
  switch (id) {
    case 'EMPTY_RESPONSE': return $r('app.string.desktop_model_retry_code_empty');
    case 'RATE_LIMIT': return $r('app.string.desktop_model_retry_code_limit');
    case 'SERVER': return $r('app.string.desktop_model_retry_code_server');
    case 'TIMEOUT': return $r('app.string.desktop_model_retry_code_timeout');
    case 'TRANSPORT': return $r('app.string.desktop_model_retry_code_network');
    case 'STREAM_CLOSED': return $r('app.string.desktop_model_retry_code_stream');
    case 'MALFORMED_RESPONSE': return $r('app.string.desktop_model_retry_code_malformed');
    case 'QUOTA': return $r('app.string.desktop_model_retry_code_quota');
    default: return id;
  }
}

@Component
export struct DesktopRetryPolicy {
  host?: DesktopHostActions;
  @Prop namespace: string = '';
  @Prop path: string[] = [];
  @Prop draftOnly: boolean = false;
  @Prop parentBusy: boolean = false;
  onSaved: () => void = (): void => {};
  onDraft?: (value: DesktopNewRetryPolicy) => void;
  onFallback?: () => void;
  @State private document?: DesktopRetryDocument = undefined;
  @State private draft: DesktopRetryDraft = desktopRetryDraft();
  @State private loading: boolean = false;
  @State private saving: boolean = false;
  @State private conflict: boolean = false;
  @State private unsupported: boolean = false;
  @State private failure: string = '';
  @State private customCode: string = '';
  @State private backoffOpen: boolean = false;
  private revision: number = 0;

  aboutToAppear(): void { this.load(); }

  aboutToDisappear(): void { this.revision++; }

  private async load(): Promise<void> {
    const host = this.host;
    if (host === undefined || this.loading || this.saving) { return; }
    const revision = ++this.revision;
    this.loading = true;
    this.failure = '';
    this.unsupported = false;
    const response = await host.call(SETTINGS_DESCRIBE_ENDPOINT);
    if (revision !== this.revision) { return; }
    this.loading = false;
    if (!response.ok) { this.failure = desktopHostProblem(response); return; }
    const document = readDesktopRetryDocument(response.value, this.namespace, this.path);
    this.unsupported = document === undefined;
    this.conflict = false;
    this.document = document;
    this.draft = desktopRetryDraft(document);
    this.customCode = '';
    this.backoffOpen = ['backoff.initialDelayMs', 'backoff.maxDelayMs', 'backoff.jitterRatio']
      .some((key: string): boolean => !!this.draft.texts[key]);
  }

  private canEdit(): boolean {
    return this.document?.writable === true && !this.parentBusy && !this.loading && !this.saving && !this.conflict;
  }

  private currentChange(): DesktopRetryChange {
    const document = this.document;
    return document === undefined ? { operations: [], problem: '', problemField: '' } :
      desktopRetryChange(document, this.path, this.draft);
  }

  private chooseMode(id: string): void {
    const document = this.document;
    if (document === undefined || !this.canEdit() || id === this.draft.mode) { return; }
    this.updateDraft(switchDesktopRetryMode(document, this.draft, id));
    this.customCode = '';
    this.failure = '';
  }

  private updateDraft(draft: DesktopRetryDraft): void {
    this.draft = draft;
    const document = this.document;
    if (this.draftOnly && document !== undefined) { this.onDraft?.(desktopNewRetryPolicy(document, draft)); }
  }

  private modeItems(): MenuElement[] {
    const items: MenuElement[] = [{ value: this.modeText(''), action: (): void => { this.chooseMode(''); },
      icon: this.draft.mode === '' ? $r('app.media.dsh_dock_check') : undefined }];
    for (const mode of this.document?.modes ?? []) {
      items.push({ value: modeLabel(mode.id), action: (): void => { this.chooseMode(mode.id); },
        icon: this.draft.mode === mode.id ? $r('app.media.dsh_dock_check') : undefined });
    }
    return items;
  }

  private modeText(id: string): ResourceStr {
    if (id) { return modeLabel(id); }
    const mode = modeLabel(this.document?.inheritedMode ?? '');
    const resolved = typeof mode === 'string' ? mode :
      this.getUIContext().getHostContext()?.resourceManager.getStringSync(mode) ?? this.document?.inheritedMode ?? '';
    return $r('app.string.desktop_model_retry_inherit', resolved);
  }

  private addCode(): void {
    const value = this.customCode.trim();
    if (!value || !this.canEdit()) { return; }
    this.customCode = '';
    if (this.draft.codes.includes(value)) { return; }
    this.updateDraft({ mode: this.draft.mode, texts: this.draft.texts, codesEdited: true,
      codes: [...this.draft.codes, value],
      knownCodes: this.draft.knownCodes.includes(value) ? this.draft.knownCodes : [...this.draft.knownCodes, value] });
  }

  private chooseCode(id: string, enabled: boolean): void {
    const current = this.draft.codes;
    if (!this.canEdit() || enabled === current.includes(id) || (!enabled && current.length === 1)) { return; }
    this.updateDraft({ mode: this.draft.mode, texts: this.draft.texts, knownCodes: this.draft.knownCodes, codesEdited: true,
      codes: enabled ? [...current, id] : current.filter((code: string): boolean => code !== id) });
  }

  private changeText(id: string, value: string): void {
    const texts: Record<string, string> = {};
    for (const key of Object.keys(this.draft.texts)) { texts[key] = this.draft.texts[key]; }
    texts[id] = value;
    this.updateDraft({ mode: this.draft.mode, texts: texts, codes: this.draft.codes,
      knownCodes: this.draft.knownCodes, codesEdited: this.draft.codesEdited });
  }

  private async save(): Promise<void> {
    const host = this.host;
    const document = this.document;
    const change = this.currentChange();
    if (host === undefined || document === undefined || this.draftOnly ||
      !this.canEdit() || change.problem || !change.operations.length) {
      return;
    }
    const revision = ++this.revision;
    this.saving = true;
    this.failure = '';
    const reply: RpcResult = await host.call(SETTINGS_MUTATE_ENDPOINT,
      { 'ns': this.namespace, 'ops': change.operations, 'expectedRevision': document.revision });
    if (revision !== this.revision) { return; }
    this.saving = false;
    if (!reply.ok) {
      this.conflict = reply.error?.code === SETTINGS_CONFLICT;
      this.failure = desktopHostProblem(reply);
      return;
    }
    this.onSaved();
    const view = reply.value;
    if (view === undefined) { this.load(); return; }
    const envelope: Record<string, Object> = { 'namespaces': [view], 'writable': document.writable };
    const updated = readDesktopRetryDocument(envelope, this.namespace, this.path);
    if (updated === undefined) { this.load(); }
    else {
      this.document = updated;
      this.draft = desktopRetryDraft(updated);
      this.customCode = '';
    }
  }

  private accessibilityLabel(label: ResourceStr): string {
    return typeof label === 'string' ? label :
      this.getUIContext().getHostContext()?.resourceManager.getStringSync(label) ?? '';
  }

  private policyFields(backoff: boolean): DesktopRetryField[] {
    return desktopRetryMode(this.document, this.draft.mode)?.fields.filter(
      (field: DesktopRetryField): boolean => (field.path.length > 1) === backoff) ?? [];
  }

  private warning(): ResourceStr {
    const change = this.currentChange();
    const field = desktopRetryMode(this.document, this.draft.mode)?.fields
      .find((row: DesktopRetryField): boolean => row.key === change.problemField);
    switch (change.problem) {
      case 'number': return $r('app.string.desktop_model_retry_number');
      case 'integer': return $r('app.string.desktop_model_retry_integer');
      case 'positive': return $r('app.string.desktop_model_retry_positive');
      case 'range': return $r('app.string.desktop_model_retry_range',
        String(field?.minimum ?? ''), String(field?.maximum ?? ''));
      case 'delay': return $r('app.string.desktop_model_retry_delay_order');
      case 'codes': return $r('app.string.desktop_model_retry_valid_codes');
      default: return $r('app.string.desktop_model_retry_unavailable');
    }
  }

  @Builder
  private NumberField(field: DesktopRetryField) {
    Column({ space: 4 }) {
      Text(fieldLabel(field.key)).fontSize(13).width('100%')
      TextInput({ text: this.draft.texts[field.key] ?? '',
        placeholder: field.fallback === undefined ? '' : String(field.fallback) })
        .key('desktopRetryPolicyField-' + field.key).fontSize(14).width('100%').height(36)
        .enabled(this.canEdit()).accessibilityText(this.accessibilityLabel(fieldLabel(field.key)))
        .onChange((value: string): void => { this.changeText(field.key, value); })
    }.width('100%')
  }

  @Builder
  private CodeFields() {
    Column({ space: 6 }) {
      Text($r('app.string.desktop_model_retry_codes')).fontSize(13).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.draft.knownCodes, (code: string): void => {
          Row({ space: 4 }) {
            Checkbox().select(this.draft.codes.includes(code)).width(20).height(20)
              .key('desktopRetryPolicyCode-' + code).accessibilityText(this.accessibilityLabel(codeLabel(code)))
              .enabled(this.canEdit() && (this.draft.codes.length > 1 || !this.draft.codes.includes(code)))
              .onChange((enabled: boolean): void => { this.chooseCode(code, enabled); })
            Text(codeLabel(code)).fontSize(13)
          }.height(32).padding({ right: 12 })
        }, (code: string): string => code)
      }.width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.customCode, placeholder: $r('app.string.desktop_model_retry_custom_code') })
          .key('desktopRetryPolicyCodeInput').height(36).layoutWeight(1).enabled(this.canEdit())
          .onChange((value: string): void => { this.customCode = value; }).onSubmit((): void => { this.addCode(); })
        Button($r('app.string.desktop_model_retry_add_code'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopRetryPolicyCodeAdd').enabled(this.canEdit() && this.customCode.trim().length > 0)
          .onClick((): void => { this.addCode(); })
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private PolicyFields() {
    ForEach(this.policyFields(false),
      (field: DesktopRetryField): void => {
        if (field.type === 'number') { this.NumberField(field) }
        else { this.CodeFields() }
      }, (field: DesktopRetryField): string => field.key)
    if (this.policyFields(true).length > 0) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Image(this.backoffOpen ? $r('app.media.dsh_queue_chevron_up_outline') :
            $r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12)
          Text($r('app.string.desktop_model_retry_backoff')).fontSize(13)
        }
      }.key('desktopRetryPolicyBackoff').onClick((): void => { this.backoffOpen = !this.backoffOpen; })
      if (this.backoffOpen) {
        Column({ space: 6 }) {
          ForEach(this.policyFields(true),
            (field: DesktopRetryField): void => { if (field.type === 'number') { this.NumberField(field) } },
            (field: DesktopRetryField): string => field.key)
        }.width('100%')
      }
    }
  }

  build() {
    Column({ space: 8 }) {
      Text($r('app.string.desktop_model_retry_title')).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
      if (this.document !== undefined && !this.unsupported) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 8 }) {
            Text(this.modeText(this.draft.mode)).fontSize(14).layoutWeight(1).textAlign(TextAlign.Start)
            Image($r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14)
          }.width('100%')
        }.key('desktopRetryPolicyMode').enabled(this.canEdit()).height(36).width('100%')
          .bindMenu(this.modeItems(), desktopMenuOptions(Placement.BottomLeft))
        if (this.draft.mode === 'always') {
          Text($r('app.string.desktop_model_retry_always_hint')).fontSize(12)
            .fontColor($r('sys.color.font_secondary')).width('100%')
        }
        this.PolicyFields()
        if (this.currentChange().problem) {
          Text(this.warning()).key('desktopRetryPolicyValidation').fontSize(12)
            .fontColor($r('sys.color.warning')).width('100%')
        }
        if (this.document?.writable === true && !this.draftOnly) {
          Button($r('app.string.desktop_model_retry_save'), { buttonStyle: ButtonStyleMode.EMPHASIZED })
            .key('desktopRetryPolicySave')
            .enabled(this.canEdit() && !this.currentChange().problem && this.currentChange().operations.length > 0)
            .onClick((): void => { this.save(); })
        }
      } else if (this.unsupported) {
        Text($r('app.string.desktop_model_retry_unavailable')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        if (this.onFallback !== undefined) {
          Button($r('app.string.desktop_model_retry_open_value'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick((): void => { this.onFallback?.(); })
        }
      }
      if (this.loading || this.saving) { LoadingProgress().width(20).height(20) }
      if (this.failure) {
        Text(this.failure).key('desktopRetryPolicyError').fontSize(12)
          .fontColor($r('sys.color.warning')).width('100%')
        if (!this.loading && (this.conflict || this.document === undefined)) {
          Button($r('app.string.desktop_model_retry_reload'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopRetryPolicyReload').onClick((): void => { this.load(); })
        }
      }
    }.key('desktopRetryPolicy').width('100%').alignItems(HorizontalAlign.Start)
  }
}
