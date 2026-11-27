import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { getArray, getString, parseJson, toStringArray } from 'connection';
import { DesktopArchiveFilter } from './DesktopSessionArchive';
import { DesktopSessionGrouping, DesktopSessionOrdering } from './DesktopSessionOrder';

const PREFERENCES: string = 'dshm_desktop_workspace';
const KEY_SIDEBAR_VIEW: string = 'sidebarView';

interface DesktopSavedOrder {
  account: string;
  ids: string[];
}

export interface DesktopSidebarView {
  grouping: DesktopSessionGrouping;
  ordering: DesktopSessionOrdering;
  archiveFilter: DesktopArchiveFilter;
  expanded?: string[];
  orders: Map<string, string[]>;
}

export function decodeDesktopSidebarView(text: string): DesktopSidebarView {
  const raw = parseJson(text);
  const group = getString(raw, 'grouping');
  const archive = getString(raw, 'archiveFilter');
  const orders = new Map<string, string[]>();
  for (const entry of getArray(raw, 'orders') ?? []) {
    const account = getString(entry, 'account');
    if (account !== undefined) { orders.set(account, toStringArray(getArray(entry, 'ids') ?? [])); }
  }
  const expanded = getArray(raw, 'expanded');
  return {
    grouping: group === DesktopSessionGrouping.FLAT ? DesktopSessionGrouping.FLAT :
      group === DesktopSessionGrouping.TREE ? DesktopSessionGrouping.TREE : DesktopSessionGrouping.WORKSPACE,
    ordering: getString(raw, 'ordering') === DesktopSessionOrdering.MANUAL ?
      DesktopSessionOrdering.MANUAL : DesktopSessionOrdering.UPDATED,
    archiveFilter: archive === DesktopArchiveFilter.ONLY ? DesktopArchiveFilter.ONLY :
      archive === DesktopArchiveFilter.ALL ? DesktopArchiveFilter.ALL : DesktopArchiveFilter.HIDE,
    expanded: expanded === undefined ? undefined : toStringArray(expanded), orders: orders
  };
}

export function encodeDesktopSidebarView(view: DesktopSidebarView): string {
  const orders: DesktopSavedOrder[] = [];
  view.orders.forEach((ids: string[], account: string): void => { orders.push({ account: account, ids: ids }); });
  return JSON.stringify({ grouping: view.grouping, ordering: view.ordering, archiveFilter: view.archiveFilter,
    expanded: view.expanded, orders: orders });
}

export function readDesktopSidebarView(context: common.Context): DesktopSidebarView {
  try {
    const raw = preferences.getPreferencesSync(context, { name: PREFERENCES }).getSync(KEY_SIDEBAR_VIEW, '');
    return decodeDesktopSidebarView(typeof raw === 'string' ? raw : '');
  } catch (_) {
    return decodeDesktopSidebarView('');
  }
}

export function saveDesktopSidebarView(context: common.Context, view: DesktopSidebarView): void {
  try {
    const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES });
    prefs.putSync(KEY_SIDEBAR_VIEW, encodeDesktopSidebarView(view));
    prefs.flush().catch((): void => {});
  } catch (_) {}
}
