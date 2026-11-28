import { emptyModelRow, Fs, invalidPiAiCapacity, Radius, Sp, Sz } from 'appstate';
import type { PiAiModelRow, PiAiReasoningProtocol } from 'appstate';
import { PiAiModelReasoning } from './PiAiModelReasoning';
import { desktopDeepSeekEditedInput, desktopDeepSeekModelInput } from '../desktop/DesktopDeepSeekCatalog';
import { DesktopPiAiReorderHandle } from '../desktop/DesktopPiAiReorderHandle';
import { cloneDesktopPiAiModel, desktopPiAiCapacityText, desktopPiAiEditedCapacity, desktopPiAiEditedInput,
  desktopPiAiInputModes, formatDesktopPiAiCapacity } from '../desktop/DesktopPiAiModelFields';
import type { DesktopPiAiCapacityField } from '../desktop/DesktopPiAiModelFields';

@Component
export struct PiAiModelSettingsRow {
  @Prop @Watch('modelChanged') initialModel: PiAiModelRow = emptyModelRow();
  @Prop rowIndex: number = 0;
  @Prop reorderHandleId: string = '';
  @Prop removable: boolean = false;
  @Prop editingEnabled: boolean = true;
  @Prop deepSeekMode: boolean = false;
  @Prop defaultContextWindow: number = 0;
  @Prop defaultMaxTokens: number = 0;
  @Prop defaultInput?: string[] = undefined;
  @Prop reasoning: PiAiReasoningProtocol = { levels: [], levelsOnly: false };
  onChange: (row: PiAiModelRow) => void = (_row: PiAiModelRow): void => {};
  onRemove: () => void = (): void => {};
  onOrderStep: (direction: number) => void = (): void => {};
  onOrderHold: (pressed: boolean) => void = (): void => {};
  onOrderBegin: (event: GestureEvent, handle: Area) => void = (): void => {};
  onOrderUpdate: (event: GestureEvent) => void = (): void => {};
  onOrderEnd: (event: GestureEvent) => void = (): void => {};
  onOrderCancel: () => void = (): void => {};
  @State private model: PiAiModelRow = emptyModelRow();
  @State private expanded: boolean = false;

  aboutToAppear(): void { this.model = this.initialModel; }

  private modelChanged(): void { this.model = this.initialModel; }

  private update(next: PiAiModelRow): void {
    if (!this.editingEnabled || next === this.model) { return; }
    this.model = next;
    this.onChange(next);
  }

  private fieldLabel(field: DesktopPiAiCapacityField): Resource {
    return field === 'contextWindow' ? $r('app.string.desktop_model_option_context') : $r('app.string.desktop_model_option_output');
  }

  private invalidCapacity(field: DesktopPiAiCapacityField): boolean {
    return invalidPiAiCapacity(field === 'contextWindow' ? this.model.contextWindow : this.model.maxTokens);
  }

  private fieldKey(deepSeek: string, piAi: string): string {
    return (this.deepSeekMode ? 'desktopDeepSeekModel' + deepSeek : 'desktopPiAi' + piAi) + '-' + this.rowIndex;
  }

  private capacityPlaceholder(field: DesktopPiAiCapacityField): ResourceStr {
    if (!this.deepSeekMode) { return field === 'contextWindow' ? '1M' : '128K'; }
    const fallback = field === 'contextWindow' ? this.defaultContextWindow : this.defaultMaxTokens;
    return fallback > 0 ? formatDesktopPiAiCapacity(fallback) : $r('app.string.desktop_deepseek_catalog_capacity_inherited');
  }

  private updateCapacity(field: DesktopPiAiCapacityField, text: string): void {
    if (text !== desktopPiAiCapacityText(this.model, field)) {
      this.update(desktopPiAiEditedCapacity(this.model, field, text));
    }
  }

  private settleCapacity(field: DesktopPiAiCapacityField): void {
    if (!this.deepSeekMode) { return; }
    const count = field === 'contextWindow' ? this.model.contextWindow : this.model.maxTokens;
    const typed = field === 'contextWindow' ? this.model.contextWindowText : this.model.maxTokensText;
    if (typed === undefined || Number.isNaN(count)) { return; }
    const next = cloneDesktopPiAiModel(this.model);
    if (field === 'contextWindow') { next.contextWindowText = undefined; }
    else { next.maxTokensText = undefined; }
    this.model = next;
  }

  private updateIdentity(field: 'id' | 'name', value: string): void {
    if (value === (field === 'id' ? this.model.id : this.model.name)) { return; }
    const next = cloneDesktopPiAiModel(this.model);
    if (field === 'id') { next.id = value; }
    else { next.name = value; }
    this.update(next);
  }

  private inputModes(): string[] {
    return this.deepSeekMode ? desktopDeepSeekModelInput(this.model) : desktopPiAiInputModes(this.model, this.defaultInput);
  }

  private inputSelected(modality: string): boolean { return this.inputModes().includes(modality); }

  private updateInput(modality: string, checked: boolean): void {
    this.update(this.deepSeekMode ? desktopDeepSeekEditedInput(this.model, modality, checked) :
      desktopPiAiEditedInput(this.model, this.defaultInput, modality, checked));
  }

  private canToggleInput(modality: string): boolean {
    const selected = this.inputModes();
    return this.editingEnabled && (selected.length > 1 || !selected.includes(modality));
  }

  @Builder
  private CapacityField(field: DesktopPiAiCapacityField) {
    Column({ space: 4 }) {
      Text(this.fieldLabel(field)).fontSize(Fs.CAPTION).width('100%').fontColor($r('sys.color.font_secondary'))
      TextInput({ text: desktopPiAiCapacityText(this.model, field), placeholder: this.capacityPlaceholder(field) })
        .key(this.fieldKey('Capacity-' + field, 'ModelCapacity-' + field))
        .accessibilityText(this.fieldLabel(field)).fontSize(Fs.SECONDARY).height(Sz.TOUCH_MIN).width('100%')
        .enabled(this.editingEnabled).onChange((text: string): void => { this.updateCapacity(field, text); })
        .onBlur((): void => { this.settleCapacity(field); })
      if (!this.deepSeekMode && this.invalidCapacity(field)) {
        Text(field === 'contextWindow' ? $r('app.string.desktop_model_option_context_invalid') :
          $r('app.string.desktop_model_option_output_invalid'))
          .key('desktopPiAiModelCapacityError-' + field + '-' + this.rowIndex)
          .fontSize(Fs.CAPTION).width('100%').fontColor($r('app.color.workspace_status_error'))
      }
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private InputChoice(modality: string, label: Resource) {
    Row({ space: 4 }) {
      Checkbox({ name: modality, group: this.fieldKey('Input', 'ModelInput') })
        .key(this.fieldKey('Input-' + modality, 'ModelInput-' + modality)).accessibilityText(label)
        .select(this.inputSelected(modality)).enabled(this.canToggleInput(modality))
        .onChange((checked: boolean): void => { this.updateInput(modality, checked); })
      Text(label).fontSize(Fs.SECONDARY).onClick((): void => {
        if (this.canToggleInput(modality)) {
          this.updateInput(modality, !this.inputSelected(modality));
        }
      })
    }
  }

  build() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.XS }) {
        DesktopPiAiReorderHandle({ handleId: this.reorderHandleId, rowPosition: this.rowIndex + 1,
          enabledForEdit: this.editingEnabled, onStep: this.onOrderStep, onDragBegin: this.onOrderBegin,
          onPointerHold: this.onOrderHold,
          onDragUpdate: this.onOrderUpdate, onPanFinished: this.onOrderEnd, onDragCancel: this.onOrderCancel })
        TextInput({ text: this.model.id, placeholder: $r('app.string.desktop_model_option_id') })
          .key(this.fieldKey('Id', 'ProviderModel')).fontSize(Fs.SECONDARY).height(Sz.TOUCH_MIN).layoutWeight(1)
          .enabled(this.editingEnabled).onChange((value: string): void => { this.updateIdentity('id', value); })
          .onBlur((): void => {
            if (this.deepSeekMode) { this.updateIdentity('id', this.model.id.trim()); }
          })
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image(this.expanded ? $r('app.media.dsh_queue_chevron_down_outline') :
            $r('app.media.dsh_browser_chevron_right_outline')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
        }.key(this.fieldKey('Options', 'ModelOptions')).width(32).height(32).padding(0).borderRadius(8)
          .accessibilityText($r('app.string.desktop_model_option_title', (this.rowIndex + 1).toString()))
          .accessibilitySelected(this.expanded).onClick((): void => { this.expanded = !this.expanded; })
        if (this.removable) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_dock_trash')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
          }.key(this.fieldKey('Remove', 'ModelRemove')).width(32).height(32).padding(0).borderRadius(8)
            .accessibilityText($r('app.string.desktop_model_option_remove', (this.rowIndex + 1).toString()))
            .enabled(this.editingEnabled).onClick(this.onRemove)
        }
      }.width('100%')
      TextInput({ text: this.model.name, placeholder: $r('app.string.desktop_model_option_name') })
        .key(this.fieldKey('Name', 'ModelName')).fontSize(Fs.SECONDARY).height(Sz.TOUCH_MIN).width('100%')
        .enabled(this.editingEnabled).onChange((value: string): void => { this.updateIdentity('name', value); })
      if (this.expanded) {
        Row({ space: 8 }) {
          this.CapacityField('contextWindow')
          this.CapacityField('maxTokens')
        }.width('100%').alignItems(VerticalAlign.Top)
        Text($r('app.string.desktop_model_option_input')).fontSize(Fs.CAPTION).fontColor($r('sys.color.font_secondary'))
          .width('100%')
        Row({ space: 12 }) {
          this.InputChoice('text', $r('app.string.desktop_model_option_text'))
          this.InputChoice('image', $r('app.string.desktop_model_option_image'))
        }.width('100%')
        if (this.reasoning.levels.length > 0) {
          PiAiModelReasoning({ model: this.model, rowIndex: this.rowIndex, protocol: this.reasoning,
            editingEnabled: this.editingEnabled, onChange: (model: PiAiModelRow): void => { this.update(model); } })
        }
      }
    }.width('100%').padding(Sp.S).borderRadius(Radius.S).backgroundColor($r('sys.color.background_primary'))
  }
}
