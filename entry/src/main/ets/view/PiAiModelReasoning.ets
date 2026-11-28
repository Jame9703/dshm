import { checkPiAiModelReasoning, emptyModelRow, piAiReasoningWireValid, readPiAiReasoningEntries } from 'appstate';
import type { PiAiModelRow, PiAiReasoningEntry, PiAiReasoningProtocol } from 'appstate';
import { desktopMenuOptions } from '../desktop/DesktopMenuOptions';
import { desktopPiAiAddReasoningLevel, desktopPiAiChangeReasoningLevel, desktopPiAiChangeReasoningWire,
  desktopPiAiReasoningChoices, desktopPiAiReasoningEnabled, desktopPiAiReasoningLabel, desktopPiAiReasoningModel }
  from '../desktop/DesktopPiAiReasoning';

@Component
export struct PiAiModelReasoning {
  @Prop model: PiAiModelRow = emptyModelRow();
  @Prop rowIndex: number = 0;
  @Prop protocol: PiAiReasoningProtocol = { levels: [], levelsOnly: false };
  @Prop editingEnabled: boolean = true;
  onChange: (model: PiAiModelRow) => void = (_model: PiAiModelRow): void => {};
  @State private typingLevel: string = '';
  @State private typingText: string = '';
  @State private helpVisible: boolean = false;

  private entries(): PiAiReasoningEntry[] { return readPiAiReasoningEntries(this.model) ?? []; }

  private reasoningOn(): boolean { return readPiAiReasoningEntries(this.model) !== undefined; }

  private levelAt(index: number): string { return this.entries()[index]?.level ?? ''; }

  private wireAt(index: number): string {
    const entry = this.entries()[index];
    if (entry === undefined) { return ''; }
    if (!this.protocol.levelsOnly && this.typingLevel === entry.level) { return this.typingText; }
    return typeof entry.wire === 'string' ? entry.wire : '';
  }

  private changeOn(enabled: boolean): void {
    if (!this.editingEnabled || enabled === this.reasoningOn()) { return; }
    this.typingLevel = '';
    this.onChange(desktopPiAiReasoningEnabled(this.model, enabled, this.protocol.levels));
  }

  private levelMenu(index: number): MenuElement[] {
    const selected = this.levelAt(index);
    return desktopPiAiReasoningChoices(this.entries(), selected, this.protocol.levels).map((level: string): MenuElement => ({
      value: level, icon: level === selected ? $r('app.media.dsh_dock_check') : undefined,
      action: (): void => {
        if (!this.editingEnabled) { return; }
        this.typingLevel = '';
        this.onChange(desktopPiAiChangeReasoningLevel(this.model, index, level, this.protocol));
      }
    }));
  }

  private canEditWire(index: number): boolean {
    return this.editingEnabled && !this.protocol.levelsOnly && this.levelAt(index) !== 'off';
  }

  private editWire(index: number, value: string): void {
    if (!this.canEditWire(index)) { return; }
    this.typingLevel = this.levelAt(index);
    this.typingText = value;
    this.onChange(desktopPiAiChangeReasoningWire(this.model, index, value));
  }

  private leaveWire(index: number): void {
    this.typingLevel = '';
    const entry = this.entries()[index];
    if (this.canEditWire(index) && entry !== undefined && !piAiReasoningWireValid(entry)) {
      this.onChange(desktopPiAiChangeReasoningWire(this.model, index, ''));
    }
  }

  private removeLevel(index: number): void {
    if (!this.editingEnabled) { return; }
    this.typingLevel = '';
    this.onChange(desktopPiAiReasoningModel(this.model, this.entries()
      .filter((_entry: PiAiReasoningEntry, at: number): boolean => at !== index)));
  }

  private canAddLevel(): boolean {
    const used = new Set<string>(this.entries().map((entry: PiAiReasoningEntry): string => entry.level));
    return this.editingEnabled && this.protocol.levels.some((level: string): boolean => !used.has(level));
  }

  private keyFor(action: string, index: number): string { return 'desktopPiAiReasoning-' + action + '-' + this.rowIndex + '-' + index; }

  @Builder
  private Help() {
    Column() {
      Text($r('app.string.desktop_model_reasoning_help_text')).fontSize(13).lineHeight(20)
        .fontColor($r('sys.color.font_primary')).width('100%')
    }.key('desktopPiAiReasoningHelp-' + this.rowIndex).width(300).padding(12)
  }

  @Builder
  private EffortRow(index: number) {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Text(this.levelAt(index)).fontSize(13).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true).accessibilityLevel('no')
        }.width('100%')
      }.key(this.keyFor('level', index)).layoutWeight(1).height(32).borderRadius(8)
        .accessibilityText($r('app.string.desktop_model_reasoning_level_at', (index + 1).toString()))
        .enabled(this.editingEnabled).bindMenu(this.levelMenu(index), desktopMenuOptions(Placement.BottomLeft))
      TextInput({ text: this.wireAt(index), placeholder: this.levelAt(index) === 'off' ?
        $r('app.string.desktop_model_reasoning_off') : this.levelAt(index) })
        .key(this.keyFor('wire', index)).fontSize(13).height(34).layoutWeight(1)
        .accessibilityText($r('app.string.desktop_model_reasoning_wire_for', this.levelAt(index)))
        .enabled(this.canEditWire(index)).onChange((value: string): void => { this.editWire(index, value); })
        .onBlur((): void => { this.leaveWire(index); })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_dock_trash')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
      }.key(this.keyFor('remove', index)).width(28).height(28).padding(0).borderRadius(8)
        .accessibilityText($r('app.string.desktop_model_reasoning_remove', this.levelAt(index)))
        .enabled(this.editingEnabled).onClick((): void => { this.removeLevel(index); })
    }.width('100%')
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text($r('app.string.desktop_model_reasoning_title')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        Button('?', { type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).padding(0)
          .key('desktopPiAiReasoningHelpButton-' + this.rowIndex).width(22).height(22)
          .accessibilityText($r('app.string.desktop_model_reasoning_help'))
          .onClick((): void => { this.helpVisible = !this.helpVisible; })
          .bindPopup(this.helpVisible, { builder: this.Help(), placement: Placement.Right, enableArrow: false,
            systemMaterial: desktopMenuOptions(Placement.Right).systemMaterial,
            onStateChange: (event): void => { if (!event.isVisible) { this.helpVisible = false; } } })
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.reasoningOn() })
          .key('desktopPiAiReasoningToggle-' + this.rowIndex)
          .accessibilityText($r('app.string.desktop_model_reasoning_title_at', (this.rowIndex + 1).toString()))
          .enabled(this.editingEnabled).onChange((enabled: boolean): void => { this.changeOn(enabled); })
      }.width('100%')
      if (this.reasoningOn()) {
        if (this.entries().length > 0) {
          Row({ space: 6 }) {
            Text($r('app.string.desktop_model_reasoning_level')).fontSize(12).layoutWeight(1)
            Text($r('app.string.desktop_model_reasoning_wire')).fontSize(12).layoutWeight(1)
            Blank().width(28)
          }.width('100%')
        }
        ForEach(this.entries(), (_entry: PiAiReasoningEntry, index: number): void => {
          this.EffortRow(index)
        }, (_entry: PiAiReasoningEntry, index: number): string => index.toString())
        if (checkPiAiModelReasoning(this.model, this.protocol) !== '') {
          Text(desktopPiAiReasoningLabel(checkPiAiModelReasoning(this.model, this.protocol)))
            .key('desktopPiAiReasoningError-' + this.rowIndex).fontSize(12).width('100%')
            .fontColor($r('app.color.workspace_status_error'))
        }
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Image($r('app.media.dsh_reference_menu_plus')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
            Text($r('app.string.desktop_model_reasoning_add')).fontSize(13)
          }
        }.key('desktopPiAiReasoningAdd-' + this.rowIndex).height(34).width('100%').borderRadius(8)
          .enabled(this.canAddLevel()).onClick((): void => {
            if (this.canAddLevel()) { this.onChange(desktopPiAiAddReasoningLevel(this.model, this.protocol.levels)); }
          })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
