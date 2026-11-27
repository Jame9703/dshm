import { KeyCode } from '@kit.InputKit';
import {
  DesktopFileSearchRule, addDesktopFileSearchRule, defaultDesktopFileSearchRules,
  isDefaultDesktopFileSearchRules, removeDesktopFileSearchRule, setDesktopFileSearchRuleEnabled
} from './DesktopFileSearchModel';
import { desktopMenuOptions } from './DesktopMenuOptions';

const SEARCH_RULE_INPUT_KEY: string = 'desktopFileSearchRuleInput';

@Component
struct DesktopFileSearchSettingsTool {
  @Prop toolKey: string = '';
  @Prop icon: Resource = $r('app.media.dsh_dock_close');
  @Prop label: Resource = $r('app.string.desktop_file_search_settings_close');

  onAction: () => void = () => {};
  onPanelFocus: () => void = () => {};
  onPanelBlur: () => void = () => {};
  onPanelKey: (event: KeyEvent) => boolean = () => false;

  @State private tipVisible: boolean = false;
  private hovered: boolean = false;
  private focused: boolean = false;
  private tipTimer: number = -1;

  aboutToDisappear(): void {
    this.dismissTip();
  }

  private dismissTip(): void {
    if (this.tipTimer !== -1) {
      clearTimeout(this.tipTimer);
      this.tipTimer = -1;
    }
    this.tipVisible = false;
  }

  private syncTip(): void {
    if (!this.hovered && !this.focused) {
      this.dismissTip();
    } else if (!this.tipVisible && this.tipTimer === -1) {
      this.tipTimer = setTimeout((): void => {
        this.tipTimer = -1;
        this.tipVisible = true;
      }, 220);
    }
  }

  @Builder
  private Tip() {
    Text(this.label).fontSize(12).fontColor($r('sys.color.font_primary'))
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(this.icon).width(15).height(15).supportSvg2(true).draggable(false).accessibilityLevel('no')
    }.key(this.toolKey).width(28).height(28).padding(0).borderRadius(6)
      .focusOnTouch(false).accessibilityText(this.label)
      .onFocus((): void => { this.focused = true; this.onPanelFocus(); this.syncTip(); })
      .onBlur((): void => { this.focused = false; this.onPanelBlur(); this.syncTip(); })
      .onHover((hovered: boolean): void => { this.hovered = hovered; this.syncTip(); })
      .onKeyEvent(this.onPanelKey)
      .onClick((): void => { this.dismissTip(); this.onAction(); })
      .bindPopup(this.tipVisible, { builder: this.Tip(), placement: Placement.Bottom,
        targetSpace: 6, enableArrow: false, focusable: false, mask: false, autoCancel: false,
        systemMaterial: desktopMenuOptions(Placement.Bottom).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible) { this.dismissTip(); } } })
  }
}

@Component
export struct DesktopFileSearchSettings {
  @Prop rules: DesktopFileSearchRule[] = [];
  @Prop respectGitignore: boolean = true;
  @Prop inputKey: string = SEARCH_RULE_INPUT_KEY;
  @Prop maxListHeight: number = 320;

  onChange: (rules: DesktopFileSearchRule[]) => void = () => {};
  onRespectGitignore: (value: boolean) => void = () => {};
  onClose: (refocus: boolean) => void = () => {};
  isTriggerFocused: () => boolean = () => false;

  @State private draft: string = '';
  @State private invalid: string = '';
  @State private inputFocused: boolean = false;
  private focusTimer: number = -1;
  private blurTimer: number = -1;

  aboutToAppear(): void {
    this.focusTimer = setTimeout((): void => {
      this.focusTimer = -1;
      this.focusInput();
    }, 30);
  }

  aboutToDisappear(): void {
    if (this.focusTimer !== -1) {
      clearTimeout(this.focusTimer);
      this.focusTimer = -1;
    }
    this.focusWithin();
  }

  private focusInput(): void {
    try {
      this.getUIContext().getFocusController().requestFocus(this.inputKey);
    } catch (_) {
      // Default focus also requests the field when the popup's focus scope attaches.
    }
  }

  private focusWithin(): void {
    if (this.blurTimer !== -1) {
      clearTimeout(this.blurTimer);
      this.blurTimer = -1;
    }
  }

  private checkFocusExit(): void {
    this.focusWithin();
    this.blurTimer = setTimeout((): void => {
      this.blurTimer = -1;
      if (!this.isTriggerFocused()) { this.onClose(false); }
    }, 24);
  }

  private dismissFromKeyboard(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
    this.focusWithin();
    this.onClose(true);
    return true;
  }

  private submit(): void {
    const result = addDesktopFileSearchRule(this.rules, this.draft);
    if (result.kind === 'invalid') {
      this.invalid = result.reason ?? 'empty';
      return;
    }
    this.onChange(result.rules);
    this.draft = '';
    this.invalid = '';
  }

  private errorLabel(): Resource {
    switch (this.invalid) {
      case 'nul': return $r('app.string.desktop_file_search_settings_invalid_nul');
      case 'absolute': return $r('app.string.desktop_file_search_settings_invalid_absolute');
      case 'parent': return $r('app.string.desktop_file_search_settings_invalid_parent');
      case 'glob': return $r('app.string.desktop_file_search_settings_invalid_glob');
      default: return $r('app.string.desktop_file_search_settings_invalid_empty');
    }
  }

  @Builder
  private Tool(toolKey: string, icon: Resource, label: Resource, action: () => void) {
    DesktopFileSearchSettingsTool({
      toolKey: toolKey, icon: icon, label: label, onAction: action,
      onPanelFocus: (): void => { this.focusWithin(); },
      onPanelBlur: (): void => { this.checkFocusExit(); },
      onPanelKey: (event: KeyEvent): boolean => this.dismissFromKeyboard(event)
    })
  }

  @Builder
  private CheckBox(checkKey: string, value: boolean, label: Resource, change: (value: boolean) => void) {
    Checkbox({ name: checkKey }).key(checkKey).width(14).height(14).padding(0)
      .shape(CheckBoxShape.ROUNDED_SQUARE).selectedColor($r('sys.color.brand')).select(value)
      .accessibilityText(label).focusOnTouch(false)
      .onFocus((): void => { this.focusWithin(); })
      .onBlur((): void => { this.checkFocusExit(); })
      .onKeyEvent((event: KeyEvent): boolean => this.dismissFromKeyboard(event))
      .onChange(change)
  }

  @Builder
  private Rule(rule: DesktopFileSearchRule) {
    Row({ space: 6 }) {
      this.CheckBox('desktopFileSearchRuleToggle-' + rule.path, rule.enabled,
        $r('app.string.desktop_file_search_settings_toggle', rule.path),
        (enabled: boolean): void => { this.onChange(setDesktopFileSearchRuleEnabled(this.rules, rule.path, enabled)); })
      Text(rule.path).fontSize(13).layoutWeight(1).padding({ top: 6, bottom: 6 }).wordBreak(WordBreak.BREAK_ALL)
        .fontColor(rule.enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        .accessibilityLevel('no')
        .onClick((): void => {
          this.onChange(setDesktopFileSearchRuleEnabled(this.rules, rule.path, !rule.enabled));
        })
      this.Tool('desktopFileSearchRuleRemove-' + rule.path, $r('app.media.dsh_dock_trash'),
        $r('app.string.desktop_file_search_settings_remove', rule.path), (): void => {
          this.focusInput();
          this.onChange(removeDesktopFileSearchRule(this.rules, rule.path));
        })
    }.key('desktopFileSearchRule-' + rule.path).constraintSize({ minHeight: 32 }).width('100%').padding({ left: 2 })
      .borderWidth({ top: 0.5 }).borderColor($r('sys.color.comp_divider'))
  }

  build() {
    Column() {
      Row({ space: 2 }) {
        Text($r('app.string.desktop_file_search_settings_title')).key('desktopFileSearchSettingsTitle')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        if (!isDefaultDesktopFileSearchRules(this.rules)) {
          this.Tool('desktopFileSearchRestore', $r('app.media.dsh_browser_refresh_outline'),
            $r('app.string.desktop_file_search_settings_restore'), (): void => {
              this.focusInput();
              this.onChange(defaultDesktopFileSearchRules());
            })
        }
        this.Tool('desktopFileSearchClose', $r('app.media.dsh_dock_close'),
          $r('app.string.desktop_file_search_settings_close'), (): void => {
            this.focusWithin();
            this.onClose(true);
          })
      }.width('100%')
      Text($r('app.string.desktop_file_search_settings_description')).width('100%')
        .fontSize(12).lineHeight(18).fontColor($r('sys.color.font_tertiary')).margin({ bottom: 4, right: 6 })
      Row({ space: 6 }) {
        this.CheckBox('desktopFileSearchGitignore', this.respectGitignore,
          $r('app.string.desktop_file_search_settings_gitignore'), this.onRespectGitignore)
        Text($r('app.string.desktop_file_search_settings_gitignore')).fontSize(13).layoutWeight(1)
          .padding({ top: 6, bottom: 6, right: 6 }).accessibilityLevel('no')
          .onClick((): void => { this.onRespectGitignore(!this.respectGitignore); })
      }.constraintSize({ minHeight: 32 }).width('100%').padding({ left: 2 })
      Row({ space: 6 }) {
        Image($r('app.media.dsh_reference_menu_plus')).width(14).height(14)
          .supportSvg2(true).draggable(false).accessibilityLevel('no')
        TextInput({ text: this.draft, placeholder: $r('app.string.desktop_file_search_settings_add') })
          .key(this.inputKey).fontSize(13).height(31).padding(0).layoutWeight(1)
          .backgroundColor(Color.Transparent).defaultFocus(true).enterKeyType(EnterKeyType.Done)
          .accessibilityText($r('app.string.desktop_file_search_settings_add'))
          .accessibilityDescription(this.invalid.length > 0 ? this.errorLabel() :
            $r('app.string.desktop_file_search_settings_add'))
          .onFocus((): void => { this.inputFocused = true; this.focusWithin(); })
          .onBlur((): void => { this.inputFocused = false; this.checkFocusExit(); })
          .onKeyEvent((event: KeyEvent): boolean => this.dismissFromKeyboard(event))
          .onChange((text: string): void => { this.draft = text; this.invalid = ''; })
          .onSubmit((_key: EnterKeyType, event: SubmitEvent): void => {
            event.keepEditableState();
            this.submit();
          })
      }.width('100%').padding({ left: 2, right: 6 }).borderWidth({ top: 0.5 })
        .borderColor(this.inputFocused ? $r('sys.color.brand') : $r('sys.color.comp_divider'))
      if (this.invalid.length > 0) {
        Text(this.errorLabel()).key('desktopFileSearchInvalid').width('100%').fontSize(12).lineHeight(18)
          .fontColor($r('app.color.workspace_status_error')).margin({ bottom: 4 })
      }
      Scroll() {
        Column() {
          ForEach(this.rules, (rule: DesktopFileSearchRule): void => {
            this.Rule(rule)
          }, (rule: DesktopFileSearchRule): string => rule.path)
        }.width('100%')
      }.key('desktopFileSearchRuleList').width('100%').constraintSize({ maxHeight: this.maxListHeight })
        .edgeEffect(EdgeEffect.None).scrollBar(BarState.Auto)
    }.key('desktopFileSearchSettings').width('100%').padding({ top: 6, bottom: 6, left: 10, right: 4 })
      .alignItems(HorizontalAlign.Start)
  }
}
