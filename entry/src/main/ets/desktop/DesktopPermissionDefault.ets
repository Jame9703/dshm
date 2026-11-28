import { dialogMaterial } from 'platform';
import { KeyCode } from '@kit.InputKit';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { allowsDesktopPermissionDefault, DESKTOP_FULL_ACCESS_PRESET } from './DesktopGeneralHostPreferences';
import type { DesktopPermissionDefaultOption, DesktopPermissionDefaultView } from './DesktopGeneralHostPreferences';

function optionLabel(option: DesktopPermissionDefaultOption): ResourceStr {
  const value = option.id;
  const name = option.name;
  if (value === 'read-only' && (name === value || name === 'Read Only')) {
    return $r('app.string.desktop_default_permission_read_only');
  }
  if (value === 'workspace-write' && (name === value || name === 'Workspace Write')) {
    return $r('app.string.desktop_default_permission_workspace');
  }
  if (value === DESKTOP_FULL_ACCESS_PRESET && (name === value || name === 'Full access')) {
    return $r('app.string.desktop_default_permission_full');
  }
  if (!new RegExp('^[a-z0-9]+(-[a-z0-9]+)*$').test(name)) { return name; }
  return name.split('-').map((word: string): string => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
}

@Component
export struct DesktopPermissionDefault {
  @Prop view?: DesktopPermissionDefaultView = undefined;
  @Prop @Watch('availabilityChanged') writable: boolean = false;
  @Prop loading: boolean = false;
  @Prop saving: boolean = false;
  @Prop problem: ResourceStr = '';
  onSelect: (id: string, acknowledged: boolean) => void = (_id: string, _acknowledged: boolean): void => {};
  @State private confirming: boolean = false;
  @State private acknowledged: boolean = false;
  private active: boolean = false;
  private dialogId: number = -1;
  private dialogVersion: number = 0;

  aboutToAppear(): void { this.active = true; }

  aboutToDisappear(): void {
    this.active = false;
    this.closeConfirmation();
  }

  private availabilityChanged(): void {
    if (!this.writable && this.confirming) { this.closeConfirmation(); }
  }

  private canChooseDefault(): boolean {
    return this.writable && !this.loading && !this.saving && !this.confirming && this.view !== undefined;
  }

  private selectedLabel(): ResourceStr {
    const match = this.view?.options.find((option: DesktopPermissionDefaultOption): boolean => option.id === this.view?.current);
    if (match !== undefined) { return optionLabel(match); }
    return this.loading ? $r('app.string.desktop_default_permission_loading') : $r('app.string.desktop_default_permission_unavailable');
  }

  private choices(): MenuElement[] {
    return (this.view?.options ?? []).map((option: DesktopPermissionDefaultOption): MenuElement => ({
      value: optionLabel(option), action: (): void => { this.pick(option.id); },
      icon: option.id === this.view?.current ? $r('app.media.dsh_dock_check') : undefined
    }));
  }

  private pick(id: string): void {
    if (!this.active || !this.canChooseDefault() || id === this.view?.current) { return; }
    if (id === DESKTOP_FULL_ACCESS_PRESET) {
      if (this.view?.options.some((option: DesktopPermissionDefaultOption): boolean => option.id === id) === true) {
        this.openConfirmation();
      }
    } else if (allowsDesktopPermissionDefault(this.view, id, false)) {
      this.onSelect(id, false);
    }
  }

  private closeConfirmation(): void {
    this.dialogVersion++;
    this.confirming = false;
    this.acknowledged = false;
    if (this.dialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId);
      this.dialogId = -1;
    }
  }

  private confirmFullAccess(): void {
    if (!this.active || !this.confirming || !this.writable || this.saving ||
        !allowsDesktopPermissionDefault(this.view, DESKTOP_FULL_ACCESS_PRESET, this.acknowledged)) { return; }
    this.closeConfirmation();
    this.onSelect(DESKTOP_FULL_ACCESS_PRESET, true);
  }

  private async openConfirmation(): Promise<void> {
    const version = ++this.dialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    this.acknowledged = false;
    this.confirming = true;
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({ builder: (): void => { this.Confirmation(); },
        alignment: DialogAlignment.Center, width: 440, cornerRadius: 20, autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.desktop_settings_surface') : undefined,
        onDidDisappear: (): void => {
          if (version === this.dialogVersion) {
            this.dialogVersion++;
            this.confirming = false;
            this.acknowledged = false;
            this.dialogId = -1;
          }
        }
      });
      if (this.active && version === this.dialogVersion && this.confirming) { this.dialogId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.dialogVersion) { this.closeConfirmation(); }
    }
  }

  @Builder
  private Confirmation() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_default_permission_confirm_title')).fontSize(18).fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_settings_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.key('desktopDefaultPermissionRiskClose').width(28).height(28).padding(0).borderRadius(8)
          .accessibilityText($r('app.string.desktop_settings_close')).onClick((): void => { this.closeConfirmation(); })
      }.width('100%')
      Text($r('app.string.desktop_default_permission_confirm_description')).fontSize(14).lineHeight(22)
        .width('100%').fontColor($r('sys.color.font_secondary'))
      Row({ space: 8 }) {
        Checkbox({ name: 'desktop-default-permission', group: 'desktop-default-permission-risk' })
          .key('desktopDefaultPermissionRiskAck').select(this.acknowledged)
          .accessibilityText($r('app.string.desktop_default_permission_confirm_ack'))
          .onChange((checked: boolean): void => { this.acknowledged = checked; })
        Text($r('app.string.desktop_default_permission_confirm_ack')).fontSize(14).layoutWeight(1)
          .onClick((): void => { this.acknowledged = !this.acknowledged; })
      }.width('100%')
      Row({ space: 8 }) {
        Button($r('app.string.desktop_default_permission_cancel'), { buttonStyle: ButtonStyleMode.NORMAL })
          .key('desktopDefaultPermissionRiskCancel').defaultFocus(true).height(36).borderRadius(12)
          .onClick((): void => { this.closeConfirmation(); })
        Button($r('app.string.desktop_default_permission_confirm_enable'), { buttonStyle: ButtonStyleMode.EMPHASIZED })
          .key('desktopDefaultPermissionRiskConfirm').height(36).borderRadius(12)
          .enabled(this.acknowledged && this.writable && !this.saving)
          .onClick((): void => { this.confirmFullAccess(); })
      }.width('100%').justifyContent(FlexAlign.End)
    }.key('desktopDefaultPermissionRisk').width('100%').padding(24)
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
        event.stopPropagation();
        this.closeConfirmation();
        return true;
      })
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text($r('app.string.desktop_default_permission_title')).fontSize(14).width('100%')
        Text(this.problem || $r('app.string.desktop_default_permission_description')).fontSize(13)
          .key('desktopDefaultPermissionDescription').width('100%')
          .fontColor(this.problem ? $r('app.color.workspace_status_error') : $r('sys.color.font_secondary'))
      }.layoutWeight(1)
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Text(this.selectedLabel()).fontSize(14)
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true).accessibilityLevel('no')
        }
      }.key('desktopDefaultPermission').height(34).borderRadius(12).enabled(this.canChooseDefault())
        .bindMenu(this.choices(), desktopMenuOptions(Placement.BottomRight))
    }.width('100%').constraintSize({ minHeight: 44 })
  }
}
