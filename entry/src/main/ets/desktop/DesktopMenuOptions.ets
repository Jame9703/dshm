import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { immersiveMaterialOf } from 'platform';

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
