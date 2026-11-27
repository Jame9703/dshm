import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { immersiveMaterialOf } from 'platform';

export function desktopPluginEntryItems(browse: (() => void) | undefined, create: () => void): MenuElement[] {
  const items: MenuElement[] = [];
  if (browse !== undefined) {
    items.push({ value: $r('app.string.desktop_plugin_entry_browse'), icon: $r('app.media.dsh_plugin_pinwheel_outline'),
      action: browse });
  }
  items.push({ value: $r('app.string.desktop_plugin_entry_create'), icon: $r('app.media.dsh_reference_menu_plus'),
    action: create });
  return items;
}

export function desktopMenuOptions(placement: Placement): MenuOptions {
  if (deviceInfo.sdkApiVersion >= 26) {
    try {
      return { placement: placement, systemMaterial: immersiveMaterialOf(uiMaterial.ImmersiveStyle.THICK, false) };
    } catch (_) {
      return { placement: placement };
    }
  }
  return { placement: placement };
}
