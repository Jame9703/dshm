import { SettingChoice, SettingItem } from 'appstate';
import { desktopMenuOptions } from './DesktopMenuOptions';
import {
  DESKTOP_COLLAPSE_TIMING_KEY, DESKTOP_FOLDED_REPLIES_KEY, DESKTOP_TRANSCRIPT_VIEW_KEY,
  desktopTranscriptPreferenceValue, showDesktopFoldedReplies
} from './DesktopTranscriptPreferencesModel';

export { hasDesktopTranscriptPreferences, isDesktopTranscriptPreference } from './DesktopTranscriptPreferencesModel';

interface DesktopTranscriptChoice {
  value: string;
  label: Resource;
}

interface DesktopTranscriptControl {
  settingKey: string;
  controlKey: string;
  title: Resource;
  hint: Resource;
  choices: DesktopTranscriptChoice[];
}

const VIEW_CONTROL: DesktopTranscriptControl = {
  settingKey: DESKTOP_TRANSCRIPT_VIEW_KEY,
  controlKey: 'desktopTranscriptView',
  title: $r('app.string.desktop_transcript_work_details'),
  hint: $r('app.string.desktop_transcript_work_details_hint'),
  choices: [
    { value: 'compact', label: $r('app.string.desktop_transcript_view_compact') },
    { value: 'standard', label: $r('app.string.desktop_transcript_view_standard') },
    { value: 'detailed', label: $r('app.string.desktop_transcript_view_detailed') },
    { value: 'verbose', label: $r('app.string.desktop_transcript_view_verbose') }
  ]
};
const TIMING_CONTROL: DesktopTranscriptControl = {
  settingKey: DESKTOP_COLLAPSE_TIMING_KEY,
  controlKey: 'desktopCollapseTiming',
  title: $r('app.string.desktop_transcript_collapse_timing'),
  hint: $r('app.string.desktop_transcript_collapse_timing_hint'),
  choices: [
    { value: 'completion', label: $r('app.string.desktop_transcript_collapse_completion') },
    { value: 'next-input', label: $r('app.string.desktop_transcript_collapse_next_input') }
  ]
};
const REPLIES_CONTROL: DesktopTranscriptControl = {
  settingKey: DESKTOP_FOLDED_REPLIES_KEY,
  controlKey: 'desktopFoldedReplies',
  title: $r('app.string.desktop_transcript_folded_replies'),
  hint: $r('app.string.desktop_transcript_folded_replies_hint'),
  choices: [
    { value: 'all', label: $r('app.string.desktop_transcript_folded_all') },
    { value: 'final', label: $r('app.string.desktop_transcript_folded_final') }
  ]
};

@Component
struct DesktopTranscriptPreferenceRow {
  @Prop item: SettingItem;
  @Prop control: DesktopTranscriptControl = VIEW_CONTROL;
  onPickChoice: (key: string, current: string, selection: string) => void = () => {
  };

  private value(): string {
    return desktopTranscriptPreferenceValue(this.item.key, this.item.textValue);
  }

  private valueLabel(): Resource {
    const current: string = this.value();
    return this.control.choices.find((choice: DesktopTranscriptChoice): boolean => choice.value === current)?.label ??
      this.control.choices[0].label;
  }

  private choices(): DesktopTranscriptChoice[] {
    return this.control.choices.filter((choice: DesktopTranscriptChoice): boolean =>
      this.item.choices.some((hostChoice: SettingChoice): boolean => hostChoice.value === choice.value));
  }

  @Builder
  private ChoiceMenu() {
    Menu() {
      ForEach(this.choices(), (choice: DesktopTranscriptChoice): void => {
        MenuItem({ content: choice.label })
          .key(this.control.controlKey + '-' + choice.value)
          .selectIcon(true)
          .selected(this.value() === choice.value)
          .onChange((): void => {
            const current: string = this.value();
            if (this.item.hostWritable && !this.item.readOnly && current !== choice.value) {
              this.onPickChoice(this.item.key, current, choice.value);
            }
          })
      }, (choice: DesktopTranscriptChoice): string => choice.value)
    }
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.control.title).fontSize(14).fontColor($r('sys.color.font_primary')).width('100%')
        Text(this.control.hint).fontSize(12).fontColor($r('sys.color.font_tertiary')).width('100%')
        if (!this.item.hostWritable) {
          Text($r('app.string.desktop_transcript_readonly')).fontSize(12)
            .fontColor($r('sys.color.font_tertiary')).width('100%')
        }
      }.layoutWeight(1)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL }) {
        Row({ space: 12 }) {
          Text(this.valueLabel()).fontSize(14).fontColor($r('sys.color.font_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12)
            .supportSvg2(true).accessibilityLevel('no')
        }
      }.key(this.control.controlKey).height(36).padding({ left: 14, right: 14 }).borderRadius(8)
        .constraintSize({ maxWidth: '48%' })
        .accessibilityText(this.control.title).accessibilityDescription(this.valueLabel())
        .enabled(this.item.hostWritable && !this.item.readOnly && this.choices().length > 0)
        .bindMenu(this.ChoiceMenu, desktopMenuOptions(Placement.BottomRight))
    }.width('100%').padding({ top: 16, bottom: 16 })
      .borderWidth({ bottom: 0.5 }).borderColor($r('sys.color.comp_divider'))
  }
}

@Component
export struct DesktopTranscriptPreferences {
  @Prop items: SettingItem[] = [];
  onPickChoice: (key: string, current: string, selection: string) => void = () => {
  };

  private itemsFor(control: DesktopTranscriptControl): SettingItem[] {
    return this.items.filter((item: SettingItem): boolean => item.key === control.settingKey);
  }

  @Builder
  private Preference(control: DesktopTranscriptControl) {
    ForEach(this.itemsFor(control), (item: SettingItem): void => {
      DesktopTranscriptPreferenceRow({ item: item, control: control, onPickChoice: this.onPickChoice })
    }, (item: SettingItem): string => item.key)
  }

  build() {
    Column() {
      this.Preference(VIEW_CONTROL)
      this.Preference(TIMING_CONTROL)
      if (showDesktopFoldedReplies(this.items)) {
        this.Preference(REPLIES_CONTROL)
      }
    }.width('100%')
  }
}
