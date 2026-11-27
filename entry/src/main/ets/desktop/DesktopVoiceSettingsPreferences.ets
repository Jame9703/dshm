import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { getNumber, getString, parseJson } from 'connection';
import type { DesktopVoiceMicrophone } from '../speech/DesktopVoiceCapture';

const PREFERENCES: string = 'dshm_desktop_workspace';
const MICROPHONE: string = 'voiceMicrophone';

export function readDesktopVoiceMicrophone(context: common.Context): DesktopVoiceMicrophone | undefined {
  try {
    const value = preferences.getPreferencesSync(context, { name: PREFERENCES }).getSync(MICROPHONE, '');
    if (typeof value !== 'string' || !value) { return undefined; }
    const parsed = parseJson(value);
    const id = getNumber(parsed, 'id');
    const type = getNumber(parsed, 'type');
    const name = getString(parsed, 'name');
    if (id !== undefined && id >= 0 && type !== undefined && type > 0 && name !== undefined) {
      return { id: id, type: type, name: name };
    }
  } catch (_) {}
  return undefined;
}

export async function saveDesktopVoiceMicrophone(context: common.Context,
  microphone?: DesktopVoiceMicrophone): Promise<boolean> {
  try {
    const store = preferences.getPreferencesSync(context, { name: PREFERENCES });
    store.putSync(MICROPHONE, microphone === undefined ? '' : JSON.stringify(microphone));
    await store.flush();
    return true;
  } catch (_) {
    return false;
  }
}
