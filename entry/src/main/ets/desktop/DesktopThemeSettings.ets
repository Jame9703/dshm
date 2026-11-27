import { SessionHub, SettingsWriteOutcome } from 'appstate';
import type { SettingItem } from 'appstate';
import { DESKTOP_CODE_SIZE, DESKTOP_TERMINAL_SIZE, DESKTOP_TEXT_SIZE, DESKTOP_THEME_NS,
  desktopAppearance, desktopFontDocumentValue, desktopFontSize } from './DesktopTheme';
import type { DesktopFontSizeSpec } from './DesktopTheme';

@Component
struct DesktopFontFamilyRow {
  @Prop @Watch('syncDraft') current: string = '';
  @Prop locked: boolean = false;
  @Prop field: string = '';
  label: Resource = $r('app.string.desktop_theme_text_family');
  hint: Resource = $r('app.string.desktop_theme_family_hint');
  onCommit: (value: string) => void = (_value: string): void => {};
  @State private draft: string = '';

  aboutToAppear(): void { this.syncDraft(); }

  private syncDraft(): void { this.draft = this.current; }

  private commit(): void {
    if (this.locked || this.draft === this.current) { return; }
    this.draft = desktopFontDocumentValue(this.draft);
    if (this.draft !== this.current) { this.onCommit(this.draft); }
  }

  build() {
    Column({ space: 5 }) {
      Text(this.label).fontSize(14)
      Text(this.hint).fontSize(12).fontColor($r('sys.color.font_secondary'))
      TextInput({ text: this.draft, placeholder: $r('app.string.desktop_theme_font_default') })
        .key('desktopThemeField-' + this.field).width('100%').height(36).borderRadius(8).maxLength(200)
        .fontSize(14).enabled(!this.locked).accessibilityText(this.label)
        .onChange((value: string): void => { this.draft = value; })
        .onBlur((): void => { this.commit(); })
        .onSubmit((): void => { this.commit(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct DesktopThemeSettings {
  @Prop items: SettingItem[] = [];
  @State private expanded: boolean = false;
  @State private writing: string = '';
  @State private problem: string = '';

  private item(field: string): SettingItem | undefined {
    return this.items.find((item: SettingItem): boolean => item.key === `${DESKTOP_THEME_NS}.${field}`);
  }

  private canWrite(field: string): boolean {
    const item = this.item(field);
    return item !== undefined && item.hostWritable && !item.readOnly && !this.writing;
  }

  private currentSize(spec: DesktopFontSizeSpec): number {
    return desktopFontSize(Number(this.item(spec.field)?.textValue), spec);
  }

  private async write(field: string, value: string | number): Promise<void> {
    if (!this.canWrite(field) || this.item(field)?.textValue === String(value)) { return; }
    this.writing = field;
    this.problem = '';
    try {
      const result = await SessionHub.shared().writeSettingPath(DESKTOP_THEME_NS, [field], value);
      if (result.outcome !== SettingsWriteOutcome.OK) { this.problem = result.message; }
    } finally {
      this.writing = '';
    }
  }

  private step(spec: DesktopFontSizeSpec, delta: number): void {
    const size = this.currentSize(spec) + delta;
    if (size >= spec.minimum && size <= spec.maximum) { this.write(spec.field, size); }
  }

  private appearanceValue(): string { return desktopAppearance(this.item('preference')?.textValue); }

  @Builder
  private AppearanceOption(value: string, label: Resource, icon: Resource) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 4 }) {
        Image(icon).width(16).height(16).supportSvg2(true).draggable(false).accessibilityLevel('no')
        Text(label).fontSize(14).fontColor($r('sys.color.font_primary')).maxLines(1)
      }
    }
    .key('desktopThemeAppearance-' + value).layoutWeight(1).height(82).padding(6).borderRadius(12)
    .borderWidth(0.5).borderColor(this.appearanceValue() === value ? $r('sys.color.brand') : $r('app.color.workspace_border'))
    .backgroundColor(this.appearanceValue() === value ? $r('app.color.workspace_selection') : Color.Transparent)
    .accessibilityText(label).accessibilitySelected(this.appearanceValue() === value)
    .enabled(this.canWrite('preference') && this.item('preference')?.options.includes(value) === true)
    .onClick((): void => { this.write('preference', value); })
  }

  @Builder
  private FontStep(spec: DesktopFontSizeSpec, delta: number, label: Resource) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(delta > 0 ? $r('app.media.dsh_queue_chevron_up_outline') :
        $r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true).draggable(false)
        .accessibilityLevel('no')
    }.key('desktopThemeStep-' + spec.field + (delta > 0 ? '-increase' : '-decrease'))
    .width(27).height(21).padding(0).borderRadius(5).accessibilityText(label)
    .enabled(this.canWrite(spec.field) && (delta > 0 ? this.currentSize(spec) < spec.maximum :
      this.currentSize(spec) > spec.minimum))
    .onClick((): void => { this.step(spec, delta); })
  }

  @Builder
  private SizeRow(spec: DesktopFontSizeSpec, title: Resource, hint: Resource, up: Resource, down: Resource) {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(14)
        Text(hint).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Row({ space: 4 }) {
        Text(String(this.currentSize(spec))).key('desktopThemeSize-' + spec.field).fontSize(14).textAlign(TextAlign.Center)
          .width(26)
        Column() {
          this.FontStep(spec, 1, up)
          this.FontStep(spec, -1, down)
        }
      }.borderRadius(8).backgroundColor($r('app.color.workspace_selection'))
      Text('px').fontSize(12).fontColor($r('sys.color.font_secondary'))
      if (spec.field === DESKTOP_TEXT_SIZE.field) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image(this.expanded ? $r('app.media.dsh_queue_chevron_up_outline') :
            $r('app.media.dsh_queue_chevron_down_outline')).width(16).height(16).supportSvg2(true).draggable(false)
            .accessibilityLevel('no')
        }.width(32).height(32).padding(0).borderRadius(7).key('desktopThemeMoreFonts')
        .accessibilityText($r('app.string.desktop_theme_more_fonts')).accessibilitySelected(this.expanded)
        .onClick((): void => { this.expanded = !this.expanded; })
      }
    }.width('100%')
  }

  @Builder
  private FamilyRow(field: string, label: Resource, hint: Resource) {
    if (this.item(field) !== undefined) {
      DesktopFontFamilyRow({ current: this.item(field)?.textValue ?? '', locked: !this.canWrite(field),
        field: field, label: label, hint: hint, onCommit: (value: string): void => { this.write(field, value); } })
    }
  }

  build() {
    Column({ space: 10 }) {
      if (this.item('preference') !== undefined) {
        Column({ space: 8 }) {
          Text($r('app.string.desktop_theme_appearance')).fontSize(14)
          Row({ space: 8 }) {
            this.AppearanceOption('light', $r('app.string.desktop_theme_light'), $r('app.media.dsh_theme_light_outline'))
            this.AppearanceOption('dark', $r('app.string.desktop_theme_dark'), $r('app.media.dsh_theme_dark_outline'))
            this.AppearanceOption('system', $r('app.string.desktop_theme_system'),
              $r('app.media.dsh_theme_followsystem_outline'))
          }.width('100%').key('desktopThemeAppearance')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (this.item(DESKTOP_TEXT_SIZE.field) !== undefined) {
        this.SizeRow(DESKTOP_TEXT_SIZE, $r('app.string.desktop_theme_text_size'), $r('app.string.desktop_theme_text_size_hint'),
          $r('app.string.desktop_theme_text_up'), $r('app.string.desktop_theme_text_down'))
      }
      if (this.expanded) {
        this.FamilyRow('textFontFamily', $r('app.string.desktop_theme_text_family'), $r('app.string.desktop_theme_family_hint'))
        this.FamilyRow('codeFontFamily', $r('app.string.desktop_theme_code_family'), $r('app.string.desktop_theme_family_hint'))
        if (this.item(DESKTOP_CODE_SIZE.field) !== undefined) {
          this.SizeRow(DESKTOP_CODE_SIZE, $r('app.string.desktop_theme_code_size'), $r('app.string.desktop_theme_code_size_hint'),
            $r('app.string.desktop_theme_code_up'), $r('app.string.desktop_theme_code_down'))
        }
        this.FamilyRow('terminalFontFamily', $r('app.string.desktop_theme_terminal_family'),
          $r('app.string.desktop_theme_family_hint'))
        if (this.item(DESKTOP_TERMINAL_SIZE.field) !== undefined) {
          this.SizeRow(DESKTOP_TERMINAL_SIZE, $r('app.string.desktop_theme_terminal_size'),
            $r('app.string.desktop_theme_terminal_size_hint'), $r('app.string.desktop_theme_terminal_up'),
            $r('app.string.desktop_theme_terminal_down'))
        }
      }
      if (this.problem) {
        Text(this.problem).fontSize(12).fontColor($r('app.color.workspace_status_error'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12).borderRadius(12)
    .backgroundColor($r('app.color.workspace_panel'))
  }
}
