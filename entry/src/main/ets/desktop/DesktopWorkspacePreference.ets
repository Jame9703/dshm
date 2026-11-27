import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export const DESKTOP_WORKSPACE_PAGE: string = 'pages/DesktopWorkspace';
export const WEB_WORKSPACE_PAGE: string = 'pages/WebApp';
const PREFERENCES: string = 'dshm_desktop_workspace';
const KEY_ENABLED: string = 'enabled';
const KEY_APPEARANCE: string = 'appearance';

export function desktopWorkspaceEnabled(context: common.Context): boolean {
  try {
    return preferences.getPreferencesSync(context, { name: PREFERENCES }).getSync(KEY_ENABLED, false) === true;
  } catch (_) {
    return false;
  }
}

export function desktopWorkspaceAppearance(context: common.Context): string {
  try {
    const value = preferences.getPreferencesSync(context, { name: PREFERENCES }).getSync(KEY_APPEARANCE, 'system');
    return value === 'light' || value === 'dark' ? value : 'system';
  } catch (_) {
    return 'system';
  }
}

export async function setDesktopWorkspaceEnabled(context: common.Context, enabled: boolean,
  appearance?: string): Promise<void> {
  const prefs = await preferences.getPreferences(context, { name: PREFERENCES });
  await prefs.put(KEY_ENABLED, enabled);
  if (appearance !== undefined) {
    await prefs.put(KEY_APPEARANCE, appearance);
  }
  await prefs.flush();
}

export async function saveDesktopWorkspaceAppearance(context: common.Context, appearance: string): Promise<void> {
  const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES });
  prefs.putSync(KEY_APPEARANCE, appearance);
  await prefs.flush();
}
