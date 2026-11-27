import { getArray, getBoolean, getField, getString } from 'connection';
import { SETTINGS_CONFLICT, SETTINGS_DESCRIBE_ENDPOINT, SETTINGS_MUTATE_ENDPOINT } from 'dshcompat';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { desktopPluginInteger, desktopPluginPathOps, readDesktopPluginDocument } from './DesktopPluginSettingsModel';
import type { DesktopPluginDocument, DesktopPluginEdit } from './DesktopPluginSettingsModel';
import { DESKTOP_TIMELINE_NS, desktopTimelineMilliseconds, desktopTimelinePeriod, desktopTimelinePeriodEdits,
  desktopTimelinePeriods, desktopTimelineSummary, desktopTimelineTask, desktopTimelineValidPeriods, TIMELINE_DEFAULT_SUMMARY,
  TIMELINE_DEFAULT_TASK, TIMELINE_HISTORY_MS, TIMELINE_LANGUAGES, TIMELINE_MAX_LEVELS,
  TIMELINE_PROMPT_LIMIT } from './DesktopTimelineSettingsModel';
import type { DesktopTimelinePeriod } from './DesktopTimelineSettingsModel';

@Component
export struct DesktopTimelineSettings {
  host?: DesktopHostActions;
  @State private document?: DesktopPluginDocument = undefined;
  @State private writable: boolean = false;
  @State private reading: boolean = false;
  @State private saving: boolean = false;
  @State private conflict: boolean = false;
  @State private saved: boolean = false;
  @State private error: string = '';
  @State private edits: DesktopPluginEdit[] = [];
  @State private periods: DesktopTimelinePeriod[] = [];
  @State private level: number = -1;
  private active: boolean = false;
  private nextId: number = 0;

  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }

  private async load(): Promise<void> {
    if (this.reading || !this.active) { return; }
    this.reading = true;
    this.error = '';
    this.saved = false;
    const result = await this.host?.call(SETTINGS_DESCRIBE_ENDPOINT);
    if (!this.active) { return; }
    this.reading = false;
    if (!result?.ok) {
      this.error = result === undefined ? '' : desktopHostProblem(result);
      this.writable = false;
      return;
    }
    this.writable = getBoolean(result.value, 'writable') === true;
    const raw = (getArray(result.value, 'namespaces') ?? []).find((item: Object): boolean =>
      getString(item, 'ns') === DESKTOP_TIMELINE_NS);
    this.accept(readDesktopPluginDocument(raw));
  }

  private accept(document?: DesktopPluginDocument): void {
    this.document = document;
    this.edits = [];
    this.periods = desktopTimelinePeriods(document?.value).map((row: DesktopTimelinePeriod): DesktopTimelinePeriod => {
      return { id: this.nextId++, text: row.text, hour: row.hour, prompt: row.prompt };
    });
    this.level = -1;
    this.conflict = false;
  }

  private canEdit(): boolean { return this.document !== undefined && this.writable && !this.reading && !this.saving; }

  private baseline(field: string): Object {
    const value = getField(this.document?.value, field);
    if (value !== undefined) { return value; }
    switch (field) {
      case 'language': return 'ui';
      case 'progressDecimals': return 2;
      case 'reminderIterations': return 24;
      case 'allowTodo': return false;
      case 'taskPrompt': return desktopTimelineTask(this.document?.value);
      case 'summaryPrompt': return desktopTimelineSummary(this.document?.value);
      default: return true;
    }
  }

  private value(field: string): Object {
    return this.edits.find((edit: DesktopPluginEdit): boolean => edit.field === field)?.value ?? this.baseline(field);
  }

  private markEdited(): void {
    this.saved = false;
    if (!this.conflict) { this.error = ''; }
  }

  private stage(field: string, value: Object): void {
    if (!this.canEdit()) { return; }
    const next = this.edits.filter((edit: DesktopPluginEdit): boolean => edit.field !== field);
    if (String(value) !== String(this.baseline(field))) {
      next.push({ namespace: DESKTOP_TIMELINE_NS, field: field, value: value });
    }
    this.edits = next;
    this.markEdited();
  }

  private replacePeriod(id: number, text: string, hour: boolean, prompt: string): void {
    if (!this.canEdit()) { return; }
    const next: DesktopTimelinePeriod = { id: id, text: text, hour: hour, prompt: prompt };
    this.periods = this.periods.map((row: DesktopTimelinePeriod): DesktopTimelinePeriod => row.id === id ? next : row);
    this.markEdited();
  }

  private onPeriodText(id: number, text: string): void {
    const row = this.periods.find((item: DesktopTimelinePeriod): boolean => item.id === id);
    if (row !== undefined && text !== row.text) { this.replacePeriod(id, text, row.hour, row.prompt); }
  }

  private changeUnit(id: number, hour: boolean): void {
    const row = this.periods.find((item: DesktopTimelinePeriod): boolean => item.id === id);
    if (row === undefined || row.hour === hour) { return; }
    const ms = desktopTimelineMilliseconds(row);
    const text = Number.isFinite(ms) ? desktopTimelinePeriod(id, ms, row.prompt, hour).text : row.text;
    this.replacePeriod(id, text, hour, row.prompt);
  }

  private addPeriod(): void {
    if (!this.canEdit() || !this.canAddPeriod()) { return; }
    const last = desktopTimelineMilliseconds(this.periods[this.periods.length - 1]);
    const id = this.nextId++;
    const next = desktopTimelinePeriod(id, Math.min(last * 2, TIMELINE_HISTORY_MS), '');
    this.periods = [...this.periods, next];
    this.level = id;
    this.markEdited();
  }

  private canAddPeriod(): boolean {
    return this.periods.length < TIMELINE_MAX_LEVELS && this.valid() &&
      desktopTimelineMilliseconds(this.periods[this.periods.length - 1]) < TIMELINE_HISTORY_MS;
  }

  private removePeriod(id: number): void {
    if (!this.canEdit() || this.periods.length < 2) { return; }
    this.periods = this.periods.filter((row: DesktopTimelinePeriod): boolean => row.id !== id);
    if (this.level === id) { this.level = -1; }
    this.markEdited();
  }

  private selectedPrompt(): string {
    return this.periods.find((row: DesktopTimelinePeriod): boolean => row.id === this.level)?.prompt ??
      String(this.value('summaryPrompt'));
  }

  private setSelectedPrompt(prompt: string): void {
    const row = this.periods.find((entry: DesktopTimelinePeriod): boolean => entry.id === this.level);
    if (row === undefined) { this.stage('summaryPrompt', prompt); }
    else { this.replacePeriod(row.id, row.text, row.hour, prompt); }
  }

  private valid(): boolean {
    const summary = String(this.value('summaryPrompt'));
    const decimals = Number(this.value('progressDecimals'));
    return desktopTimelineValidPeriods(this.periods) && TIMELINE_LANGUAGES.includes(String(this.value('language'))) &&
      Number.isInteger(decimals) && decimals >= 0 && decimals <= 3 &&
      desktopPluginInteger(String(this.value('reminderIterations'))) !== undefined &&
      !!summary.trim() && summary.length <= TIMELINE_PROMPT_LIMIT &&
      String(this.value('taskPrompt')).length <= TIMELINE_PROMPT_LIMIT;
  }

  private dirty(): boolean {
    return this.edits.length > 0 || desktopTimelinePeriodEdits(this.document?.value, this.periods).length > 0;
  }

  private async save(): Promise<void> {
    const host = this.host;
    const document = this.document;
    if (host === undefined || document === undefined || !this.canEdit() || this.conflict || !this.dirty() || !this.valid()) {
      return;
    }
    const changes = this.edits.map((edit: DesktopPluginEdit): DesktopPluginEdit => ({
      namespace: DESKTOP_TIMELINE_NS, field: edit.field,
      value: edit.field === 'reminderIterations' ? Number(edit.value) : edit.value
    })).concat(desktopTimelinePeriodEdits(document.value, this.periods));
    this.saving = true;
    this.error = '';
    const result = await host.call(SETTINGS_MUTATE_ENDPOINT, { 'ns': DESKTOP_TIMELINE_NS,
      'expectedRevision': document.revision, 'ops': desktopPluginPathOps(changes, DESKTOP_TIMELINE_NS) });
    if (!this.active) { return; }
    this.saving = false;
    if (!result.ok) {
      this.conflict = result.error?.code === SETTINGS_CONFLICT;
      this.error = this.conflict ? '' : desktopHostProblem(result);
      return;
    }
    const updated = readDesktopPluginDocument(result.value);
    if (updated?.id === DESKTOP_TIMELINE_NS) { this.accept(updated); }
    else { await this.load(); }
    if (this.active && !this.error) { this.saved = true; }
  }

  private discard(): void {
    if (this.conflict) { this.load(); }
    else {
      this.accept(this.document);
      this.error = '';
      this.saved = false;
    }
  }

  private languageLabel(id: string): ResourceStr {
    switch (id) {
      case 'ui': return $r('app.string.desktop_timeline_language_ui');
      case 'chat': return $r('app.string.desktop_timeline_language_chat');
      case 'zh-CN': return '简体中文';
      case 'ja': return '日本語';
      case 'es': return 'Español';
      case 'fr': return 'Français';
      case 'de': return 'Deutsch';
      case 'ru': return 'Русский';
      case 'pt': return 'Português';
      default: return 'English';
    }
  }

  private languageOptions(): MenuElement[] {
    return TIMELINE_LANGUAGES.map((id: string): MenuElement => ({
      value: this.languageLabel(id), action: (): void => { this.stage('language', id); }
    }));
  }

  private decimalOptions(): MenuElement[] {
    return [0, 1, 2, 3].map((value: number): MenuElement => ({
      value: String(value), action: (): void => { this.stage('progressDecimals', value); }
    }));
  }

  @Builder
  private SwitchField(field: string, title: Resource, invert: boolean = false) {
    Row({ space: 10 }) {
      Text(title).layoutWeight(1).fontSize(14)
      Toggle({ type: ToggleType.Switch, isOn: this.value(field) === !invert }).enabled(this.canEdit())
        .key('desktopTimelineSetting-' + field).accessibilityText(title)
        .onChange((value: boolean): void => { this.stage(field, invert ? !value : value); })
    }.width('100%')
  }

  @Builder
  private Period(row: DesktopTimelinePeriod, index: number) {
    Row({ space: 6 }) {
      Button($r('app.string.desktop_timeline_level', index + 1),
        { buttonStyle: this.level === row.id ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL })
        .key('desktopTimelineSelectLevel-' + index).accessibilitySelected(this.level === row.id)
        .onClick((): void => { this.level = row.id; })
      TextInput({ text: row.text }).type(InputType.NUMBER_DECIMAL).layoutWeight(1).height(36)
        .key('desktopTimelinePeriod-' + index).enabled(this.canEdit())
        .accessibilityText($r('app.string.desktop_timeline_period', index + 1))
        .onChange((text: string): void => { this.onPeriodText(row.id, text); })
      Button(row.hour ? $r('app.string.desktop_timeline_hours') : $r('app.string.desktop_timeline_minutes'),
        { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(this.canEdit()).key('desktopTimelinePeriodUnit-' + index).bindMenu([
          { value: $r('app.string.desktop_timeline_minutes'), action: (): void => { this.changeUnit(row.id, false); } },
          { value: $r('app.string.desktop_timeline_hours'), action: (): void => { this.changeUnit(row.id, true); } }
        ], desktopMenuOptions(Placement.BottomLeft))
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_dock_trash')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
      }.width(32).padding(0).enabled(this.canEdit() && this.periods.length > 1)
        .key('desktopTimelineRemovePeriod-' + index)
        .accessibilityText($r('app.string.desktop_timeline_remove_level', index + 1))
        .onClick((): void => { this.removePeriod(row.id); })
    }.width('100%')
  }

  @Builder
  private Prompts() {
    Row({ space: 8 }) {
      Text(this.level < 0 ? $r('app.string.desktop_timeline_global_prompt') : $r('app.string.desktop_timeline_level_prompt'))
        .fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
      Button($r('app.string.desktop_timeline_reset_prompt'), { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(this.canEdit())
        .onClick((): void => { this.setSelectedPrompt(this.level < 0 ? TIMELINE_DEFAULT_SUMMARY : ''); })
    }.width('100%')
    TextArea({ text: this.selectedPrompt(), placeholder: $r('app.string.desktop_timeline_level_prompt_placeholder') })
      .height(112).width('100%').maxLength(TIMELINE_PROMPT_LIMIT).enabled(this.canEdit()).key('desktopTimelineSummaryPrompt')
      .onChange((text: string): void => { if (text !== this.selectedPrompt()) { this.setSelectedPrompt(text); } })
    Text($r('app.string.desktop_timeline_count', this.selectedPrompt().length, TIMELINE_PROMPT_LIMIT))
      .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%').textAlign(TextAlign.End)
    Row({ space: 8 }) {
      Text($r('app.string.desktop_timeline_task_prompt')).fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
      Button($r('app.string.desktop_timeline_reset_prompt'), { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(this.canEdit())
        .onClick((): void => { this.stage('taskPrompt', TIMELINE_DEFAULT_TASK); })
    }.width('100%')
    TextArea({ text: String(this.value('taskPrompt')) }).height(112).width('100%').maxLength(TIMELINE_PROMPT_LIMIT)
      .enabled(this.canEdit()).key('desktopTimelineTaskPrompt')
      .onChange((text: string): void => { if (text !== this.value('taskPrompt')) { this.stage('taskPrompt', text); } })
    Text($r('app.string.desktop_timeline_count', String(this.value('taskPrompt')).length, TIMELINE_PROMPT_LIMIT))
      .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%').textAlign(TextAlign.End)
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_timeline_settings')).fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (this.document !== undefined && this.dirty()) {
          Button($r('app.string.desktop_timeline_discard'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineDiscard').enabled(!this.saving && !this.reading)
            .onClick((): void => { this.discard(); })
        }
        if (this.document !== undefined) {
          Button(this.saving ? $r('app.string.desktop_timeline_saving') : $r('app.string.desktop_timeline_save'))
            .key('desktopTimelineSave').enabled(this.canEdit() && this.dirty() && this.valid() && !this.conflict)
            .onClick((): void => { this.save(); })
        }
      }.width('100%')
      if (this.reading) { LoadingProgress().width(22).height(22) }
      if (this.conflict) {
        Text($r('app.string.desktop_timeline_conflict')).fontSize(13).key('desktopTimelineConflict')
          .fontColor($r('app.color.workspace_status_error'))
      } else if (this.error) {
        Text(this.error).fontSize(13).fontColor($r('app.color.workspace_status_error'))
      } else if (this.saved) {
        Text($r('app.string.desktop_timeline_saved')).fontSize(13).key('desktopTimelineSaved')
      }
      if (this.document === undefined && !this.reading) {
        Text($r('app.string.desktop_timeline_unavailable')).fontSize(13)
        Button($r('app.string.desktop_experiment_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => { this.load(); })
      }
      if (this.document !== undefined) {
        Text($r('app.string.desktop_timeline_general')).fontSize(16).fontWeight(FontWeight.Medium)
        Row({ space: 8 }) {
          Text($r('app.string.desktop_timeline_language')).fontSize(14).layoutWeight(1)
          Button(this.languageLabel(String(this.value('language'))), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineLanguage').enabled(this.canEdit())
            .bindMenu(this.languageOptions(), desktopMenuOptions(Placement.BottomLeft))
        }.width('100%')
        Row({ space: 8 }) {
          Text($r('app.string.desktop_timeline_decimals')).fontSize(14).layoutWeight(1)
          Button(String(this.value('progressDecimals')), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopTimelineDecimals').enabled(this.canEdit())
            .bindMenu(this.decimalOptions(), desktopMenuOptions(Placement.BottomLeft))
        }.width('100%')
        this.SwitchField('segmentedProgress', $r('app.string.desktop_timeline_segmented'))
        Text($r('app.string.desktop_timeline_task_tracking')).fontSize(16).fontWeight(FontWeight.Medium)
        this.SwitchField('allowTodo', $r('app.string.desktop_timeline_replace_todo'), true)
        this.SwitchField('autoOpenSidebar', $r('app.string.desktop_timeline_open_sidebar'))
        Row({ space: 8 }) {
          Text($r('app.string.desktop_timeline_reminder')).fontSize(14).layoutWeight(1)
          TextInput({ text: String(this.value('reminderIterations')) }).type(InputType.Number)
            .width(112).height(36).key('desktopTimelineReminder').enabled(this.canEdit())
            .onChange((text: string): void => {
              if (text !== String(this.value('reminderIterations'))) { this.stage('reminderIterations', text); }
            })
        }.width('100%')
        Text($r('app.string.desktop_timeline_reports')).fontSize(16).fontWeight(FontWeight.Medium)
        this.SwitchField('reportsEnabled', $r('app.string.desktop_timeline_enable_reports'))
        Button($r('app.string.desktop_timeline_global_prompt'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTimelineSelectGlobal').accessibilitySelected(this.level < 0)
          .onClick((): void => { this.level = -1; })
        ForEach(this.periods, (row: DesktopTimelinePeriod, index: number): void => {
          this.Period(row, index)
        }, (row: DesktopTimelinePeriod, index: number): string => String(row.id) + ':' + index + ':' + row.hour)
        Button($r('app.string.desktop_timeline_add_level'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopTimelineAddPeriod').enabled(this.canEdit() && this.canAddPeriod())
          .onClick((): void => { this.addPeriod(); })
        if (!this.valid() && this.dirty()) {
          Text($r('app.string.desktop_timeline_invalid')).fontSize(13).fontColor($r('app.color.workspace_status_error'))
        }
        if (!this.writable) { Text($r('app.string.desktop_timeline_readonly')).fontSize(13) }
        this.Prompts()
      }
    }.key('desktopTimelineSettings').width('100%').padding(16).borderRadius(12)
      .backgroundColor($r('app.color.workspace_panel')).alignItems(HorizontalAlign.Start)
  }
}
