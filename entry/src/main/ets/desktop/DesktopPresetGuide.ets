import { KeyCode } from '@kit.InputKit';
import { MarkdownRenderer } from '../view/MarkdownRenderer';

export interface DesktopPresetGuideCopy {
  id: string;
  intro: Resource;
  explanation: Resource;
  usage: Resource;
}

interface DesktopPresetGuideExample {
  title: string;
  markdown: string;
}

const GUIDES: DesktopPresetGuideCopy[] = [
  { id: 'standard', intro: $r('app.string.desktop_preset_guide_standard_intro'),
    explanation: $r('app.string.desktop_preset_guide_standard_explanation'),
    usage: $r('app.string.desktop_preset_guide_standard_usage') },
  { id: 'ptc', intro: $r('app.string.desktop_preset_guide_ptc_intro'),
    explanation: $r('app.string.desktop_preset_guide_ptc_explanation'),
    usage: $r('app.string.desktop_preset_guide_ptc_usage') },
  { id: 'minimal', intro: $r('app.string.desktop_preset_guide_minimal_intro'),
    explanation: $r('app.string.desktop_preset_guide_minimal_explanation'),
    usage: $r('app.string.desktop_preset_guide_minimal_usage') },
  { id: 'cordis', intro: $r('app.string.desktop_preset_guide_cordis_intro'),
    explanation: $r('app.string.desktop_preset_guide_cordis_explanation'),
    usage: $r('app.string.desktop_preset_guide_cordis_usage') }
];

export function desktopPresetGuideCopy(id: string): DesktopPresetGuideCopy | undefined {
  return GUIDES.find((guide: DesktopPresetGuideCopy): boolean => guide.id === id);
}

export function desktopPresetGuideExamples(text: string): DesktopPresetGuideExample[] {
  const examples: DesktopPresetGuideExample[] = [];
  for (const section of text.split(new RegExp('^### ', 'm')).slice(1)) {
    const end = section.indexOf('\n');
    if (end >= 0) { examples.push({ title: section.slice(0, end), markdown: section.slice(end + 1).trim() }); }
  }
  return examples;
}

@Component
export struct DesktopPresetGuide {
  @Prop presetName: string = '';
  @Prop initialUsage: boolean = false;
  copy?: DesktopPresetGuideCopy;
  onClose: () => void = (): void => {};
  @State private showingUsage: boolean = false;
  @State private explanation: string = '';
  @State private examples: DesktopPresetGuideExample[] = [];

  aboutToAppear(): void {
    this.showingUsage = this.initialUsage;
    const copy = this.copy;
    const resources = this.getUIContext().getHostContext()?.resourceManager;
    if (copy === undefined || resources === undefined) { return; }
    this.explanation = resources.getStringSync(copy.explanation);
    this.examples = desktopPresetGuideExamples(resources.getStringSync(copy.usage));
  }

  private tabKey(usage: boolean): string {
    return usage ? 'desktopPresetGuideUsage' : 'desktopPresetGuideExplanation';
  }

  @Builder
  private GuideTab(usage: boolean) {
    Button(usage ? $r('app.string.desktop_preset_guide_usage') : $r('app.string.desktop_preset_guide_explanation'),
      { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
      .key(this.tabKey(usage)).id(this.tabKey(usage)).defaultFocus(this.initialUsage === usage)
      .height(32).fontSize(14).fontColor($r('sys.color.font_primary')).borderRadius(8)
      .backgroundColor(this.showingUsage === usage ? $r('app.color.workspace_selection') : Color.Transparent)
      .accessibilitySelected(this.showingUsage === usage)
      .onClick((): void => { this.showingUsage = usage; })
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type !== KeyType.Down || (event.keyCode !== KeyCode.KEYCODE_DPAD_LEFT &&
            event.keyCode !== KeyCode.KEYCODE_DPAD_RIGHT)) { return false; }
        event.stopPropagation();
        this.showingUsage = !usage;
        this.getUIContext().getFocusController().requestFocus(this.tabKey(!usage));
        return true;
      })
  }

  @Builder
  private Example(example: DesktopPresetGuideExample) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(example.title).fontSize(16).fontWeight(FontWeight.Medium).flexShrink(1)
        Row({ space: 4 }) {
          Image($r('app.media.dsh_preset_guide_example')).width(12).height(12).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
          Text($r('app.string.desktop_preset_guide_example')).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.height(22).padding({ left: 8, right: 8 }).borderRadius(6).backgroundColor($r('app.color.workspace_selection'))
      }.width('100%')
      MarkdownRenderer({ text: example.markdown })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Column({ space: 8 }) {
        Row({ space: 16 }) {
          Text(this.presetName).key('desktopPresetGuideTitle').fontSize(20).lineHeight(28)
            .fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_settings_close')).width(18).height(18).supportSvg2(true)
              .draggable(false).accessibilityLevel('no')
          }.key('desktopPresetGuideClose').width(32).height(32).padding(0).borderRadius(12)
            .accessibilityText($r('app.string.desktop_preset_view_close')).onClick(this.onClose)
        }.width('100%')
        if (this.copy !== undefined) {
          Text(this.copy.intro).fontSize(14).lineHeight(22).fontColor($r('sys.color.font_secondary')).width('100%')
        }
      }.width('100%').padding({ top: 24, left: 28, right: 24, bottom: 20 })
      Row({ space: 4 }) {
        this.GuideTab(false)
        this.GuideTab(true)
      }.key('desktopPresetGuideTabs').width('100%').padding({ left: 28, right: 28, bottom: 22 })
        .accessibilityDescription($r('app.string.desktop_preset_guide_sections'))
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          MarkdownRenderer({ text: this.explanation }).padding({ left: 28, right: 24, bottom: 24 })
        }.key('desktopPresetGuideExplanationPage').width('100%').height('100%').scrollBar(BarState.Auto)
          .visibility(this.showingUsage ? Visibility.Hidden : Visibility.Visible)
          .focusable(!this.showingUsage).align(Alignment.TopStart).edgeEffect(EdgeEffect.None)
        Scroll() {
          Column({ space: 28 }) {
            ForEach(this.examples, (example: DesktopPresetGuideExample): void => { this.Example(example); },
              (example: DesktopPresetGuideExample): string => example.title)
          }.width('100%').padding({ left: 28, right: 24, bottom: 24 })
        }.key('desktopPresetGuideUsagePage').width('100%').height('100%').scrollBar(BarState.Auto)
          .visibility(this.showingUsage ? Visibility.Visible : Visibility.Hidden)
          .focusable(this.showingUsage).align(Alignment.TopStart).edgeEffect(EdgeEffect.None)
      }.width('100%').layoutWeight(1)
    }.key('desktopPresetGuide').width('100%').height('100%')
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
        event.stopPropagation();
        this.onClose();
        return true;
      })
  }
}
