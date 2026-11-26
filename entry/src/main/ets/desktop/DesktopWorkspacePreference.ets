import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export const DESKTOP_WORKSPACE_PAGE: string = 'pages/DesktopWorkspace';
export const WEB_WORKSPACE_PAGE: string = 'pages/WebApp';
const PREFERENCES: string = 'dshm_desktop_workspace';
const KEY_ENABLED: string = 'enabled';

export function desktopWorkspaceEnabled(context: common.Context): boolean {
  try {
    return preferences.getPreferencesSync(context, { name: PREFERENCES }).getSync(KEY_ENABLED, false) === true;
  } catch (_) {
    return false;
  }
}

export async function setDesktopWorkspaceEnabled(context: common.Context, enabled: boolean): Promise<void> {
  const prefs = await preferences.getPreferences(context, { name: PREFERENCES });
  await prefs.put(KEY_ENABLED, enabled);
  await prefs.flush();
}
