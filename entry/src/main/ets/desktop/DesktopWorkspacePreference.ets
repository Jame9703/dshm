import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { parseTarget } from 'connection';

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

export function desktopWorkspaceSelectionHost(url: string): string {
  // Connection configures RPCs against this base URL. Launch tokens and paths are outside its identity.
  return parseTarget(url)?.address.baseUrl.toLowerCase() ?? '';
}

export function readDesktopWorkspaceSelection(context: common.Context, host: string): string {
  try {
    const value = preferences.getPreferencesSync(context, { name: PREFERENCES }).getSync('selectedSession:' + host, '');
    return typeof value === 'string' ? value : '';
  } catch (_) {
    return '';
  }
}

export async function saveDesktopWorkspaceSelection(context: common.Context, host: string, sessionId: string): Promise<boolean> {
  try {
    const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES });
    const key = 'selectedSession:' + host;
    if (sessionId) { prefs.putSync(key, sessionId); }
    else { prefs.deleteSync(key); }
    await prefs.flush();
    return true;
  } catch (_) {
    return false;
  }
}
