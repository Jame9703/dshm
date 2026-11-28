import { getArray, getBoolean, getString } from 'connection';
import { PIAI_SETTINGS_NS } from 'appstate';

/** Match the installed catalog entry, including its exact settings address. */
export function isDesktopPiAiCatalogRoute(providers: Object[], route: string): boolean {
  return providers.some((entry: Object): boolean => {
    const path = getArray(entry, 'settingsPath');
    return getString(entry, 'provider') === route && getString(entry, 'settingsNs') === PIAI_SETTINGS_NS &&
      getBoolean(entry, 'declared') === false && path !== undefined && path.length === 2 &&
      path[0] === 'providers' && path[1] === route;
  });
}
