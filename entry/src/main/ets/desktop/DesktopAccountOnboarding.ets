import { KeyCode } from '@kit.InputKit';
import { desktopAccountLocale } from './DesktopAccountClient';

export type DesktopAccountOnboardingStep = 'welcome' | 'credit' | 'purpose' | 'process';
export type DesktopAccountOnboardingPurpose = '' | 'office' | 'development' | 'both';
export type DesktopAccountOnboardingProcess = '' | 'compact' | 'standard' | 'detailed';

interface OnboardingChoice {
  id: string;
  key: string;
  title: Resource;
  description: Resource;
  icon: Resource;
  accent: string;
}

const PURPOSES: OnboardingChoice[] = [
  { id: 'office', key: 'desktopAccountOnboardingPurposeOffice',
    title: $r('app.string.desktop_account_onboarding_office'),
    description: $r('app.string.desktop_account_onboarding_office_description'),
    icon: $r('app.media.dsh_account_onboarding_office'), accent: '#8370F1' },
  { id: 'development', key: 'desktopAccountOnboardingPurposeDevelopment',
    title: $r('app.string.desktop_account_onboarding_development'),
    description: $r('app.string.desktop_account_onboarding_development_description'),
    icon: $r('app.media.dsh_account_onboarding_code'), accent: '#3B86FF' }
];

const PROCESSES: OnboardingChoice[] = [
  { id: 'compact', key: 'desktopAccountOnboardingProcessCompact',
    title: $r('app.string.desktop_account_onboarding_compact'),
    description: $r('app.string.desktop_account_onboarding_compact_description'),
    icon: $r('app.media.dsh_account_onboarding_compact'), accent: '#8370F1' },
  { id: 'standard', key: 'desktopAccountOnboardingProcessStandard',
    title: $r('app.string.desktop_account_onboarding_standard'),
    description: $r('app.string.desktop_account_onboarding_standard_description'),
    icon: $r('app.media.dsh_account_onboarding_standard'), accent: '#3B86FF' },
  { id: 'detailed', key: 'desktopAccountOnboardingProcessDetailed',
    title: $r('app.string.desktop_account_onboarding_detailed'),
    description: $r('app.string.desktop_account_onboarding_detailed_description'),
    icon: $r('app.media.dsh_account_onboarding_detailed'), accent: '#2DA7AF' }
];
const PROCESS_CARD_WIDTH: string = '31.8%';
const PURPOSE_CARD_WIDTH: string = '48.8%';
const CONTINUE_KEY: string = 'desktopAccountOnboardingContinue';
const RECHARGE_KEY: string = 'desktopAccountOnboardingRecharge';

/** First-run desktop presentation. Artwork and copy from dsh-client-ui-settings-account (MIT). */
@Component
export struct DesktopAccountOnboarding {
  @Prop step: DesktopAccountOnboardingStep = 'welcome';
  @Prop amount: string = '';
  @Prop amountLabel: string = '';
  @Prop finishing: boolean = false;
  @Prop funded: boolean = false;
  @Prop canTopUp: boolean = false;
  @Prop purpose: DesktopAccountOnboardingPurpose = '';
  @Prop process: DesktopAccountOnboardingProcess = '';
  @Prop localePreference: string = 'system';
  @Prop error: boolean = false;
  onContinue: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onSkip: () => void = (): void => {};
  onTopUp: () => void = (): void => {};
  onLater: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  onPurpose: (value: DesktopAccountOnboardingPurpose) => void = (_value: DesktopAccountOnboardingPurpose): void => {};
  onProcess: (value: DesktopAccountOnboardingProcess) => void = (_value: DesktopAccountOnboardingProcess): void => {};

  @State private viewportWidth: number = 1000;
  @State private viewportHeight: number = 640;
  @State private hoveredCard: string = '';

  private wide(): boolean { return this.viewportWidth >= 760; }

  private illustration(): Resource {
    const chinese = desktopAccountLocale(this.localePreference).toLowerCase().startsWith('zh');
    if (this.step === 'welcome') {
      return chinese ? $r('app.media.dsh_account_onboarding_welcome_zh') :
        $r('app.media.dsh_account_onboarding_welcome_en');
    }
    return chinese ? $r('app.media.dsh_account_onboarding_recharge_zh') :
      $r('app.media.dsh_account_onboarding_recharge_en');
  }

  private chosen(id: string, radio: boolean): boolean {
    return radio ? this.process === id : this.purpose === id || this.purpose === 'both';
  }

  private togglePurpose(id: string): void {
    const office = id === 'office' ? !this.chosen('office', false) : this.chosen('office', false);
    const development = id === 'development' ? !this.chosen('development', false) :
      this.chosen('development', false);
    const next: DesktopAccountOnboardingPurpose = office && development ? 'both' :
      office ? 'office' : development ? 'development' : '';
    this.onPurpose(next);
  }

  private chooseProcess(id: string): void {
    if (id === 'compact' || id === 'standard' || id === 'detailed') { this.onProcess(id); }
  }

  private processKey(card: OnboardingChoice, event: KeyEvent): boolean {
    if (this.finishing || event.type !== KeyType.Down) { return false; }
    const key = event.keyCode;
    const direction = key === KeyCode.KEYCODE_DPAD_RIGHT || key === KeyCode.KEYCODE_DPAD_DOWN ? 1 :
      key === KeyCode.KEYCODE_DPAD_LEFT || key === KeyCode.KEYCODE_DPAD_UP ? -1 : 0;
    if (direction === 0) { return false; }
    const index = PROCESSES.findIndex((item: OnboardingChoice): boolean => item.id === card.id);
    const next = (index + direction + PROCESSES.length) % PROCESSES.length;
    this.chooseProcess(PROCESSES[next].id);
    try { this.getUIContext().getFocusController().requestFocus(PROCESSES[next].key); } catch (_) {}
    return true;
  }

  @Builder
  private Heading(title: Resource, description: Resource, centered: boolean) {
    Column({ space: centered ? 15 : 22 }) {
      Text(title).key('desktopAccountOnboardingTitle').width('100%').fontSize(28).lineHeight(40)
        .fontWeight(300).textAlign(centered ? TextAlign.Center : TextAlign.Start)
        .fontColor($r('sys.color.font_primary'))
      Text(description).width('100%').fontSize(16).lineHeight(centered ? 23 : 28)
        .fontWeight(300).textAlign(centered ? TextAlign.Center : TextAlign.Start)
        .fontColor($r('sys.color.font_secondary'))
    }.width('100%')
  }

  @Builder
  private Action(label: Resource, key: string, primary: boolean, enabled: boolean, onAction: () => void) {
    Button(label, { type: ButtonType.Normal, buttonStyle: primary ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL })
      .key(key).width('100%').height(44).fontSize(14).fontWeight(FontWeight.Medium)
      .backgroundColor(primary ? $r('sys.color.brand') : $r('app.color.workspace_panel'))
      .border({ width: primary ? 0 : 0.5, color: $r('app.color.workspace_border') })
      .borderRadius(12)
      .fontColor(primary ? Color.White : $r('sys.color.font_primary'))
      .enabled(enabled && !this.finishing).onClick(onAction)
  }

  @Builder
  private Artwork() {
    Image(this.illustration()).width('100%').height(this.wide() ? 400 : 186)
      .objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
  }

  @Builder
  private CreditActions() {
    Row({ space: 15 }) {
      Column() {
        if (this.funded) {
          this.Action($r('app.string.desktop_account_onboarding_continue'), CONTINUE_KEY, true, true, this.onContinue)
        } else {
          this.Action($r('app.string.desktop_account_onboarding_recharge'), RECHARGE_KEY, true, this.canTopUp, this.onTopUp)
        }
      }.layoutWeight(1)
      Column() {
        if (this.funded) {
          this.Action($r('app.string.desktop_account_onboarding_recharge'), RECHARGE_KEY, false, this.canTopUp, this.onTopUp)
        } else {
          this.Action($r('app.string.desktop_account_onboarding_later'), 'desktopAccountOnboardingLater', false, true, this.onLater)
        }
      }.layoutWeight(1)
    }.width('100%').constraintSize({ maxWidth: 345 })
  }

  @Builder
  private HeroCopy() {
    Column({ space: this.wide() ? 34 : 20 }) {
      if (this.step === 'welcome') {
        this.Heading($r('app.string.desktop_account_onboarding_welcome_title'),
          $r('app.string.desktop_account_onboarding_intro'), false)
        Column() {
          this.Action($r('app.string.desktop_account_onboarding_start'), CONTINUE_KEY, true, true, this.onContinue)
        }.width('100%').constraintSize({ maxWidth: 240 })
      } else {
        this.Heading($r('app.string.desktop_account_onboarding_credit_title'),
          $r('app.string.desktop_account_onboarding_credit_description'), false)
        if (this.amount) {
          Row({ space: 8 }) {
            if (this.amountLabel) {
              Text(this.amountLabel).fontSize(13).fontColor($r('sys.color.font_secondary'))
            }
            Text(this.amount).key('desktopAccountOnboardingAmount').fontSize(16).fontWeight(FontWeight.Medium)
          }
        }
        this.CreditActions()
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Hero() {
    if (this.wide()) {
      Row({ space: 32 }) {
        if (this.step === 'credit') {
          Column() { this.Artwork() }.layoutWeight(1.14)
        }
        Column() { this.HeroCopy() }.layoutWeight(1)
        if (this.step === 'welcome') {
          Column() { this.Artwork() }.layoutWeight(1.16)
        }
      }.width('100%').constraintSize({ maxWidth: 1160 }).alignItems(VerticalAlign.Center)
    } else {
      Column({ space: 18 }) {
        this.Artwork()
        this.HeroCopy()
      }.width('100%').constraintSize({ maxWidth: 520 })
    }
  }

  @Builder
  private Choice(card: OnboardingChoice, radio: boolean, width: string) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 8 }) {
        Row() {
          Image(card.icon).width(40).height(40).supportSvg2(true).draggable(false).accessibilityLevel('no')
          Blank()
          if (!radio) {
            Stack({ alignContent: Alignment.Center }) {
              if (this.chosen(card.id, false)) {
                Image($r('app.media.dsh_dock_check')).width(14).height(14).supportSvg2(true)
                  .fillColor(Color.White).accessibilityLevel('no')
              }
            }.width(22).height(22).borderRadius(6).accessibilityLevel('no')
            .border({ width: 1, color: this.chosen(card.id, false) ? card.accent : $r('app.color.workspace_border') })
            .backgroundColor(this.chosen(card.id, false) ? card.accent : Color.Transparent)
          }
        }.width('100%')
        Text(card.title).width('100%').fontSize(20).lineHeight(28).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(card.description).width('100%').fontSize(15).lineHeight(21)
          .fontColor($r('sys.color.font_tertiary'))
      }.width('100%').padding(this.wide() ? 27 : 16).alignItems(HorizontalAlign.Start)
    }.key(card.key).id(card.key).width(width).constraintSize({ minHeight: this.wide() ? 176 : 116 })
    .padding(0).borderRadius(this.wide() ? 28 : 18).focusOnTouch(false)
    .backgroundColor(this.hoveredCard === card.key ? $r('app.color.workspace_selection') : $r('app.color.workspace_panel'))
    .border({ width: this.chosen(card.id, radio) ? 2 : 0.5,
      color: this.chosen(card.id, radio) ? card.accent : $r('app.color.workspace_border') })
    .accessibilityGroup(true).accessibilityText(card.title)
    .accessibilityDescription(this.getUIContext().getHostContext()?.resourceManager.getStringSync(card.description.id) ?? '')
    .accessibilityRole(radio ? AccessibilityRoleType.RADIO : AccessibilityRoleType.CHECKBOX)
    .accessibilitySelected(this.chosen(card.id, radio))
    .tabIndex(!radio || this.chosen(card.id, radio) || (!this.process && card.id === 'compact') ? 0 : -1)
    .enabled(!this.finishing)
    .onHover((hovered: boolean): void => { this.hoveredCard = hovered ? card.key : ''; })
    .onKeyEvent((event: KeyEvent): boolean => radio && this.processKey(card, event))
    .onClick((): void => {
      if (!radio) { this.togglePurpose(card.id); }
      else { this.chooseProcess(card.id); }
    })
  }

  @Builder
  private Choices(radio: boolean) {
    Column({ space: this.wide() ? 36 : 22 }) {
      if (radio) {
        this.Heading($r('app.string.desktop_account_onboarding_process_title'),
          $r('app.string.desktop_account_onboarding_process_description'), true)
      } else {
        this.Heading($r('app.string.desktop_account_onboarding_purpose_title'),
          $r('app.string.desktop_account_onboarding_purpose_description'), true)
      }
      if (this.wide()) {
        Row() {
          ForEach(radio ? PROCESSES : PURPOSES, (card: OnboardingChoice): void => {
            this.Choice(card, radio, radio ? PROCESS_CARD_WIDTH : PURPOSE_CARD_WIDTH)
          }, (card: OnboardingChoice): string => card.id)
        }.justifyContent(FlexAlign.SpaceBetween).width('100%').alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 10 }) {
          ForEach(radio ? PROCESSES : PURPOSES, (card: OnboardingChoice): void => {
            this.Choice(card, radio, '100%')
          }, (card: OnboardingChoice): string => card.id)
        }.width('100%')
      }
      if (radio ? this.process !== '' : this.purpose !== '') {
        Column() {
          this.Action(radio ? $r('app.string.desktop_account_onboarding_enter') :
            $r('app.string.desktop_account_onboarding_continue'), CONTINUE_KEY, true, true, this.onContinue)
        }.width('100%').constraintSize({ maxWidth: 240 })
      }
    }.width('100%').constraintSize({ maxWidth: radio ? 1080 : 830 })
  }

  @Builder
  private Footer() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 10 }) {
          Image($r('app.media.dsh_account_onboarding_back')).width(17).height(14).supportSvg2(true)
            .fillColor($r('sys.color.font_secondary')).accessibilityLevel('no')
          Text($r('app.string.desktop_account_onboarding_back')).fontSize(15).fontColor($r('sys.color.font_secondary'))
        }
      }.key('desktopAccountOnboardingBack').height(40).borderRadius(8).enabled(!this.finishing)
      .accessibilityText($r('app.string.desktop_account_onboarding_back')).onClick(this.onBack)
      Blank()
      Button($r('app.string.desktop_account_onboarding_skip'),
        { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopAccountOnboardingSkip').height(40).borderRadius(8).fontSize(15)
        .fontColor($r('sys.color.font_secondary')).enabled(!this.finishing).onClick(this.onSkip)
    }.width('100%').height(52).constraintSize({ maxWidth: 1210 }).padding({ left: 16, right: 16 })
  }

  build() {
    Column() {
      ForEach([this.step], (_step: DesktopAccountOnboardingStep): void => {
        Scroll() {
          Column({ space: 18 }) {
            if (this.step === 'welcome' || this.step === 'credit') { this.Hero() }
            else { this.Choices(this.step === 'process') }
            if (this.error) {
              Row({ space: 8 }) {
                Text($r('app.string.desktop_account_onboarding_save_failed')).fontSize(13)
                  .fontColor($r('app.color.workspace_status_error'))
                Button($r('app.string.desktop_account_onboarding_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .key('desktopAccountOnboardingRetry').height(32).enabled(!this.finishing).onClick(this.onRetry)
              }
            }
          }.width('100%').constraintSize({ minHeight: Math.max(0, this.viewportHeight - (this.step === 'welcome' ? 0 : 52)) })
          .padding({ left: this.wide() ? 40 : 20, right: this.wide() ? 40 : 20, top: 22, bottom: 22 })
          .justifyContent(FlexAlign.Center)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.None)
      }, (step: DesktopAccountOnboardingStep): string => step)
      if (this.step !== 'welcome') { this.Footer() }
    }.key('desktopAccountOnboarding').width('100%').height('100%')
    .backgroundColor($r('app.color.workspace_canvas'))
    .onAreaChange((_previous: Area, area: Area): void => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width > 0 && this.viewportWidth !== width) { this.viewportWidth = width; }
      if (height > 0 && this.viewportHeight !== height) { this.viewportHeight = height; }
    })
  }
}
