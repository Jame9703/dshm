import { dialogMaterial } from 'platform';

export function showDesktopVoiceSetup(context: UIContext, install: boolean, onSettings: () => void): void {
  context.showAlertDialog({
    title: install ? $r('app.string.desktop_voice_setup_install_title') : $r('app.string.desktop_voice_setup_unavailable_title'),
    message: install ? $r('app.string.desktop_voice_setup_install_body') : $r('app.string.desktop_voice_setup_unavailable_body'),
    systemMaterial: dialogMaterial(),
    autoCancel: true,
    primaryButton: { value: $r('app.string.desktop_voice_setup_later'), action: (): void => {} },
    secondaryButton: {
      value: install ? $r('app.string.desktop_voice_setup_open') : $r('app.string.desktop_voice_setup_details'),
      action: onSettings
    }
  });
}
