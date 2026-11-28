import { dialogMaterial } from 'platform';
import { DesktopAccountOnboarding } from './DesktopAccountOnboarding';
import { emptyDesktopOnboardingView } from './DesktopAccountOnboardingState';
import type { DesktopAccountOnboardingState, DesktopOnboardingView, DesktopOnboardingProcess,
  DesktopOnboardingPurpose } from './DesktopAccountOnboardingState';

type OnboardingConfirmation = 'credit' | 'credit-skip' | 'skip';

@Component
export struct DesktopAccountOnboardingLayer {
  @Prop view: DesktopOnboardingView = emptyDesktopOnboardingView();
  @Prop contentWidth: number = 0;
  @Prop localePreference: string = 'system';
  controller?: DesktopAccountOnboardingState;
  onTopUp: (href: string) => void = (_href: string): void => {};
  private active: boolean = false;
  private confirmationId: number = -1;
  private confirmationEpoch: number = 0;
  private opening: boolean = false;

  aboutToAppear(): void { this.active = true; }

  aboutToDisappear(): void {
    this.active = false;
    this.closeConfirmation();
  }

  private later(): void {
    if (this.view.zeroBalance) { this.confirm('credit'); }
    else { this.controller?.next(); }
  }

  private closeConfirmation(): void {
    this.confirmationEpoch++;
    if (this.confirmationId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.confirmationId);
      this.confirmationId = -1;
    }
  }

  private async confirm(kind: OnboardingConfirmation): Promise<void> {
    if (!this.active || this.view.busy || this.confirmationId >= 0 || this.opening) { return; }
    this.opening = true;
    const epoch = ++this.confirmationEpoch;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({ builder: (): void => { this.Confirmation(kind); },
        width: Math.max(220, Math.min(420, this.contentWidth - 32)), alignment: DialogAlignment.Center,
        autoCancel: true, cornerRadius: 16, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (epoch === this.confirmationEpoch) { this.confirmationId = -1; }
        }
      });
      if (this.active && epoch === this.confirmationEpoch) { this.confirmationId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.active) { prompt.showToast({ message: $r('app.string.desktop_account_onboarding_confirm_failed') }); }
    } finally { this.opening = false; }
  }

  @Builder
  private Confirmation(kind: OnboardingConfirmation) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(kind === 'skip' ? $r('app.string.desktop_account_onboarding_skip_title') :
          $r('app.string.desktop_account_onboarding_no_credit_title')).fontSize(18).fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true).draggable(false)
            .fillColor($r('sys.color.font_secondary')).accessibilityLevel('no')
        }.key('desktopAccountOnboardingConfirmClose').width(28).height(28).padding(0).borderRadius(6)
        .accessibilityText($r('app.string.desktop_account_onboarding_confirm_close'))
        .onClick((): void => { this.closeConfirmation(); })
      }.width('100%')
      Text(kind === 'skip' ? $r('app.string.desktop_account_onboarding_skip_description') :
        $r('app.string.desktop_account_onboarding_no_credit_description')).fontSize(14)
        .fontColor($r('sys.color.font_secondary')).width('100%')
      Row({ space: 8 }) {
        Button(kind === 'skip' ? $r('app.string.desktop_account_onboarding_keep_setting') :
          $r('app.string.desktop_account_onboarding_understood'), { buttonStyle: ButtonStyleMode.NORMAL })
          .key('desktopAccountOnboardingConfirmSecondary').layoutWeight(1).onClick((): void => {
            this.closeConfirmation();
            if (kind === 'credit') { this.controller?.next(); }
            else if (kind === 'credit-skip') { this.controller?.skip(); }
          })
        Button(kind === 'skip' ? $r('app.string.desktop_account_onboarding_confirm_enter') :
          $r('app.string.desktop_account_onboarding_go_top_up')).key('desktopAccountOnboardingConfirmPrimary')
          .layoutWeight(1).enabled(kind === 'skip' || this.view.topUpUrl.length > 0).onClick((): void => {
            this.closeConfirmation();
            if (kind === 'skip') { this.controller?.skip(); }
            else { this.onTopUp(this.view.topUpUrl); }
          })
      }.width('100%')
    }.key('desktopAccountOnboardingConfirm').width('100%').padding(18).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Blank().height(38)
      if (this.view.loading) {
        Column({ space: 12 }) {
          if (this.view.error) {
            Text($r('app.string.desktop_account_onboarding_save_failed')).fontColor($r('sys.color.font_secondary'))
            Button($r('app.string.desktop_account_onboarding_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopAccountOnboardingRetry').enabled(!this.view.busy).onClick((): void => { this.controller?.retry(); })
          } else {
            LoadingProgress().width(24).height(24)
            Text($r('app.string.desktop_account_onboarding_loading')).fontColor($r('sys.color.font_secondary'))
          }
        }.key('desktopAccountOnboardingLoading').width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.view.step !== 'done') {
        Column() {
          DesktopAccountOnboarding({ step: this.view.step, purpose: this.view.purpose, process: this.view.process,
            finishing: this.view.busy, error: this.view.error, funded: this.view.funded,
            canTopUp: this.view.topUpUrl.length > 0, localePreference: this.localePreference,
            onContinue: (): void => { this.controller?.next(); },
            onBack: (): void => { this.controller?.back(); },
            onSkip: (): void => { this.confirm(this.view.step === 'credit' ? 'credit-skip' : 'skip'); },
            onLater: (): void => { this.later(); },
            onTopUp: (): void => { this.onTopUp(this.view.topUpUrl); },
            onPurpose: (value: DesktopOnboardingPurpose): void => { this.controller?.choosePurpose(value); },
            onProcess: (value: DesktopOnboardingProcess): void => { this.controller?.chooseProcess(value); },
            onRetry: (): void => { this.controller?.retry(); }
          })
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
  }
}
