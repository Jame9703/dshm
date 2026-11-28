import { CREDENTIALS_SET_ENDPOINT } from 'dshcompat';
import { readDesktopDeepSeekKeyTarget } from './DesktopDeepSeekKeySetup';
import type { DesktopDeepSeekKeyTarget } from './DesktopDeepSeekKeySetup';
import { deepSeekApiKeyProblem } from './DesktopDeepSeekProviderModel';
import type { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';

@Component
export struct DesktopDeepSeekKeyDialog {
  host?: DesktopHostActions;
  initialTarget?: DesktopDeepSeekKeyTarget;
  @Prop compact: boolean = false;
  @Prop availableHeight: number = 480;
  onLater: () => void = (): void => {};

  @State private target?: DesktopDeepSeekKeyTarget = undefined;
  @State private draft: string = '';
  @State private revealed: boolean = false;
  @State private busy: boolean = false;
  @State private inputFocused: boolean = false;
  @State private helpOpen: boolean = false;
  @State private failure: ResourceStr = '';
  private active: boolean = false;
  private refreshVersion: number = 0;
  private refreshTimer: number = -1;
  private stopProviderWatch?: () => void;

  aboutToAppear(): void {
    this.active = true;
    this.target = this.initialTarget;
    const host = this.host;
    if (host !== undefined) {
      this.stopProviderWatch = host.watchModelProviders((): void => { this.scheduleTargetRefresh(host); });
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.refreshVersion++;
    clearTimeout(this.refreshTimer);
    this.refreshTimer = -1;
    this.stopProviderWatch?.();
    this.stopProviderWatch = undefined;
    this.draft = '';
    this.revealed = false;
  }

  private validation(): ResourceStr {
    const issue = deepSeekApiKeyProblem(this.draft);
    if (issue === 'blank') { return $r('app.string.desktop_deepseek_setup_key_required'); }
    return issue === 'format' ? $r('app.string.desktop_deepseek_setup_key_invalid') : '';
  }

  private canSave(): boolean {
    return this.target !== undefined && !this.busy && this.draft.trim().length > 0 && this.validation() === '';
  }

  private scheduleTargetRefresh(host: DesktopHostActions): void {
    if (!this.active || this.refreshTimer >= 0) { return; }
    this.refreshTimer = setTimeout((): void => {
      this.refreshTimer = -1;
      this.refreshTarget(host);
    }, 80);
  }

  private async refreshTarget(host: DesktopHostActions): Promise<void> {
    const version = ++this.refreshVersion;
    try {
      const target = await readDesktopDeepSeekKeyTarget(host);
      if (!this.active || version !== this.refreshVersion) { return; }
      if (target === undefined) { this.onLater(); }
      else { this.target = target; }
    } catch (_) {}
  }

  private async save(): Promise<void> {
    const host = this.host;
    const target = this.target;
    if (host === undefined || target === undefined || !this.active || !this.canSave()) { return; }
    const value = this.draft.trim();
    this.busy = true;
    this.failure = '';
    this.revealed = false;
    this.helpOpen = false;
    try {
      const reply = await host.call(CREDENTIALS_SET_ENDPOINT, { 'ref': target.reference, 'value': value },
        15000, undefined, true);
      if (!this.active) { return; }
      if (!reply.ok) {
        const message = reply.error?.message ?? '';
        this.failure = message && !message.includes(value) ? message : $r('app.string.desktop_deepseek_save_failed');
        return;
      }
      this.draft = '';
      host.modelCatalogChanged();
    } catch (_) {
      if (this.active) { this.failure = $r('app.string.desktop_deepseek_save_failed'); }
    } finally {
      if (this.active) { this.busy = false; }
    }
  }

  @Builder
  private Help() {
    Text($r('app.string.desktop_deepseek_setup_key_help', this.target?.helpReference ?? ''))
      .fontSize(12).fontColor($r('sys.color.font_primary')).padding(12).constraintSize({ maxWidth: 310 })
  }

  @Builder
  private FieldLabel() {
    Row({ space: 10 }) {
      Text($r('app.string.desktop_deepseek_key_label')).fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary')).lineHeight(18)
      if (this.target?.helpReference) {
        Button('?', { type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopDeepSeekKeyHelp')
          .width(16).height(16).padding(0).fontSize(11).fontColor($r('sys.color.font_tertiary'))
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .accessibilityText($r('app.string.desktop_deepseek_setup_auth_help'))
          .onClick((): void => { this.helpOpen = true; })
          .onHover((inside: boolean): void => { this.helpOpen = inside; })
          .onFocus((): void => { this.helpOpen = true; }).onBlur((): void => { this.helpOpen = false; })
          .bindPopup(this.helpOpen, { builder: this.Help(), placement: Placement.Right, enableArrow: false,
            systemMaterial: desktopMenuOptions(Placement.Right).systemMaterial,
            onStateChange: (event): void => { if (!event.isVisible) { this.helpOpen = false; } } })
      }
    }.width('100%').height(18)
  }

  @Builder
  private Field() {
    Column({ space: 6 }) {
      this.FieldLabel()
      Stack({ alignContent: Alignment.End }) {
        TextInput({ text: this.draft, placeholder: $r('app.string.desktop_deepseek_setup_key_placeholder') })
          .key('desktopDeepSeekKeyInput').type(this.revealed ? InputType.Normal : InputType.Password)
          .showPasswordIcon(false).enableAutoFill(false).defaultFocus(true).enabled(!this.busy)
          .width('100%').height(32).fontSize(14).backgroundColor($r('app.color.workspace_panel'))
          .border({ width: 0.5, color: this.inputFocused ? $r('sys.color.brand') : $r('sys.color.comp_divider') })
          .borderRadius(8).onFocus((): void => { this.inputFocused = true; })
          .onBlur((): void => { this.inputFocused = false; })
          .padding({ left: 10, right: this.draft.length > 0 && !this.busy ? 40 : 10 })
          .accessibilityText($r('app.string.desktop_deepseek_key_label'))
          .onChange((value: string): void => {
            if (value === this.draft) { return; }
            this.draft = value;
            this.revealed = false;
            this.failure = '';
          })
        if (this.draft.length > 0 && !this.busy) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image(this.revealed ? $r('app.media.dsh_secret_eye_off') : $r('app.media.dsh_secret_eye'))
              .width(16).height(16).supportSvg2(true).draggable(false).accessibilityLevel('no')
          }.key('desktopDeepSeekKeyReveal').width(32).height(30).padding(0).borderRadius(7)
            .accessibilityText(this.revealed ? $r('app.string.desktop_deepseek_setup_key_hide') :
              $r('app.string.desktop_deepseek_setup_key_reveal')).accessibilitySelected(this.revealed)
            .onClick((): void => { this.revealed = !this.revealed; })
        }
      }.width('100%')
      if (this.validation() !== '' || this.failure !== '') {
        Text(this.validation() !== '' ? this.validation() : this.failure).key('desktopDeepSeekKeyFeedback')
          .width('100%').fontSize(12).fontColor($r('app.color.workspace_status_error'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column() {
        Text($r('app.string.desktop_deepseek_setup_title')).fontSize(20).lineHeight(28).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text($r('app.string.desktop_deepseek_setup_description')).fontSize(14).lineHeight(24).margin({ top: 8 })
          .fontColor($r('sys.color.font_secondary'))
        Column() { this.Field() }.width('100%').margin({ top: this.compact ? 20 : 24 })
        Row({ space: 8 }) {
          Button($r('app.string.desktop_deepseek_setup_later'),
            { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopDeepSeekKeyLater').height(36).fontSize(14).padding({ left: 14, right: 14 })
            .fontColor($r('sys.color.font_primary')).border({ width: 0.5, color: $r('sys.color.comp_divider') })
            .borderRadius(8).enabled(!this.busy)
            .onClick((): void => { if (!this.busy) { this.onLater(); } })
          Button(this.busy ? $r('app.string.desktop_deepseek_setup_saving') : $r('app.string.desktop_deepseek_setup_save'),
            { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED })
            .key('desktopDeepSeekKeySave').height(36).fontSize(14).padding({ left: 14, right: 14 }).borderRadius(8)
            .enabled(this.canSave()).onClick((): void => { this.save(); })
        }.width('100%').justifyContent(FlexAlign.End).margin({ top: 24 })
      }.width('100%').alignItems(HorizontalAlign.Start).padding(this.compact ? 24 : 28)
    }.key('desktopDeepSeekKeyDialog').width('100%').align(Alignment.TopStart)
      .scrollBar(BarState.Auto).constraintSize({ maxHeight: this.availableHeight })
      .accessibilityRole(AccessibilityRoleType.DIALOG)
  }
}
