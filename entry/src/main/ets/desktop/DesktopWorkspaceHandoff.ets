import { getBoolean, getField, getRecord, getString, parseJson } from 'connection';

export interface DesktopPluginLocation {
  kind: 'list' | 'more' | 'item' | 'package' | 'row';
  name: string;
  rowId: string;
  entryId?: string;
}

export interface DesktopWebDestination {
  host: string;
  sessionId: string;
  workspaceId: string;
  action: string;
  bundle: string;
  plugin?: DesktopPluginLocation;
}

export interface DesktopNativeDestination {
  host: string;
  sessionId: string;
  parentId: string;
  mode: string;
  plugin?: DesktopPluginLocation;
  preserveSession?: boolean;
}

export interface DesktopWebContext {
  appearance: string;
  destination?: DesktopNativeDestination;
}

function readPluginLocation(value?: Object): DesktopPluginLocation | undefined {
  const kind = getString(value, 'kind');
  if (kind === 'list' || kind === 'more') { return { kind: kind, name: '', rowId: '' }; }
  const name = getString(value, 'name') ?? '';
  if (!name) { return undefined; }
  if (kind === 'item' || kind === 'package') { return { kind: kind, name: name, rowId: '' }; }
  const rowId = getString(value, 'rowId') ?? '';
  if (kind !== 'row' || !rowId) { return undefined; }
  return { kind: kind, name: name, rowId: rowId, entryId: getString(value, 'entryId') };
}

export function readDesktopWebDestination(value: string): DesktopWebDestination | undefined {
  if (!value) { return undefined; }
  const raw = parseJson(value);
  const host = getString(raw, 'host');
  if (!host) { return undefined; }
  const destination: DesktopWebDestination = { host: host, sessionId: getString(raw, 'sessionId') ?? '',
    workspaceId: getString(raw, 'workspaceId') ?? '', action: getString(raw, 'action') ?? '',
    bundle: getString(raw, 'bundle') ?? '' };
  const plugin = readPluginLocation(getRecord(raw, 'plugin'));
  if (plugin !== undefined) { destination.plugin = plugin; }
  return destination;
}

export function readDesktopNativeDestination(value: string): DesktopNativeDestination | undefined {
  if (!value) { return undefined; }
  const raw = parseJson(value);
  const host = getString(raw, 'host');
  const sessionId = getString(raw, 'sessionId');
  if (!host || sessionId === undefined) { return undefined; }
  const destination: DesktopNativeDestination = { host: host, sessionId: sessionId,
    parentId: getString(raw, 'parentId') ?? '', mode: getString(raw, 'mode') ?? '' };
  const plugin = readPluginLocation(getRecord(raw, 'plugin'));
  if (plugin !== undefined) { destination.plugin = plugin; }
  if (getBoolean(raw, 'preserveSession') === true) { destination.preserveSession = true; }
  return destination;
}

export function readDesktopWebContext(value: string, host: string): DesktopWebContext {
  const decoded = parseJson(value);
  const raw = typeof decoded === 'string' ? parseJson(decoded) : decoded;
  const preference = getString(raw, 'appearance');
  const appearance = preference === 'light' || preference === 'dark' ? preference : 'system';
  const plugin = readPluginLocation(getRecord(raw, 'plugin'));
  const fallback: DesktopWebContext = { appearance: appearance };
  if (plugin !== undefined) {
    fallback.destination = { host: host, sessionId: '', parentId: '', mode: '', plugin: plugin, preserveSession: true };
  }
  const selection = getRecord(raw, 'selection');
  if (selection === undefined) { return fallback; }
  const sessionId = getString(selection, 'sessionId') ?? '';
  const child = getRecord(selection, 'subagentAddress');
  if ((getField(selection, 'sessionId') !== undefined && !sessionId) ||
    (getField(selection, 'subagentAddress') !== undefined && child === undefined)) {
    return fallback;
  }
  const destination: DesktopNativeDestination = { host: host, sessionId: sessionId, parentId: '', mode: '' };
  if (child !== undefined) {
    const parentId = getString(child, 'parentSessionId') ?? '';
    const mode = getString(child, 'mode') ?? '';
    if (!parentId || !sessionId || parentId === sessionId || getString(child, 'childSessionId') !== sessionId ||
      (mode !== 'one-shot' && mode !== 'continuable' && mode !== 'unknown')) { return fallback; }
    destination.parentId = parentId;
    destination.mode = mode;
  }
  if (plugin !== undefined) { destination.plugin = plugin; }
  return { appearance: appearance, destination: destination };
}

export function buildDesktopWebContextScript(page: string): string {
  return "(function () {\n" +
    "  if (window !== window.top || location.origin + location.pathname !== " + JSON.stringify(page) + ") return null;\n" +
    "  var selection = null;\n" +
    "  try { selection = JSON.parse(localStorage.getItem('dsh.sessions.current')); } catch (_) {}\n" +
    "  var plugin, panel = document.querySelector('[data-plugin-panel]');\n" +
    "  if (panel && panel.getClientRects().length) {\n" +
    "    var loc = function (key) {\n" +
    "      var el = panel.querySelector('[' + key + ']');\n" +
    "      return el && el.getClientRects().length ? el.getAttribute(key) : '';\n" +
    "    };\n" +
    "    var row = loc('data-plugin-row-detail'), item = loc('data-plugin-item-detail'), name = loc('data-plugin-detail');\n" +
    "    var split = row ? row.indexOf('#') : -1;\n" +
    "    if (split > 0) plugin = {kind:'row',name:row.slice(0,split),rowId:row.slice(split+1)};\n" +
    "    else if (item) plugin = {kind:'item',name:item};\n" +
    "    else if (name) plugin = {kind:'package',name};\n" +
    "    else plugin = {kind:panel.querySelector('[data-plugin-group=more]') ? 'more' : 'list'};\n" +
    "  }\n" +
    "  return JSON.stringify({ appearance: document.documentElement.getAttribute('data-ds-theme-source'), selection, plugin });\n" +
    "})()";
}

export function buildDesktopPluginDetailScript(bundle: string): string {
  return buildDesktopPluginViewScript({ kind: 'package', name: bundle, rowId: '' });
}

export function buildDesktopPluginViewScript(location: DesktopPluginLocation): string {
  return "(function () {\n" +
    "  var target = " + JSON.stringify(location) + ";\n" +
    "  var visible = function (el) { return el && el.getClientRects().length > 0; };\n" +
    "  var click = function (el) { if (visible(el) && !el.disabled) el.click(); return false; };\n" +
    "  var panel = document.querySelector('[data-plugin-panel]');\n" +
    "  if (!visible(panel)) {\n" +
    "    var tab = Array.from(document.querySelectorAll('nav button[aria-label]')).find(function (el) {\n" +
    "      return visible(el) && ['插件', 'Plugins'].includes(el.getAttribute('aria-label'));\n" +
    "    });\n" +
    "    if (tab) return click(tab);\n" +
    "    var sidebar = globalThis.__DSHM_SIDEBAR__;\n" +
    "    if (sidebar && sidebar.state() === 'collapsed') { sidebar.toggle(); return false; }\n" +
    "    var menuItem = Array.from(document.querySelectorAll('[role=menuitem]')).find(function (el) {\n" +
    "      return visible(el) && ['插件', 'Plugins'].includes((el.textContent || '').trim());\n" +
    "    });\n" +
    "    if (menuItem) return click(menuItem);\n" +
    "    return click(document.querySelector('nav button[aria-haspopup=menu][aria-expanded=false]'));\n" +
    "  }\n" +
    "  var rowDetail = panel.querySelector('[data-plugin-row-detail]');\n" +
    "  var itemDetail = panel.querySelector('[data-plugin-item-detail]');\n" +
    "  var detail = panel.querySelector('[data-plugin-detail]');\n" +
    "  var back = function (el) { return click(el.querySelector(':scope > div[data-window-drag] > button[type=button]')); };\n" +
    "  if (visible(rowDetail)) {\n" +
    "    if (target.kind === 'row' && rowDetail.getAttribute('data-plugin-row-detail') === target.name + '#' + target.rowId) return true;\n" +
    "    return back(rowDetail);\n" +
    "  }\n" +
    "  if (visible(itemDetail)) {\n" +
    "    if (target.kind === 'item' && itemDetail.getAttribute('data-plugin-item-detail') === target.name) return true;\n" +
    "    return back(itemDetail);\n" +
    "  }\n" +
    "  if (visible(detail)) {\n" +
    "    var same = detail.getAttribute('data-plugin-detail') === target.name &&\n" +
    "      detail.querySelector('[data-plugin-name]')?.textContent === target.name;\n" +
    "    if (same && target.kind === 'package') return true;\n" +
    "    if (same && target.kind === 'row') {\n" +
    "      var rows = Array.from(detail.querySelectorAll('li[data-plugin-row]'));\n" +
    "      var row = rows.find(function (el) {\n" +
    "        return visible(el) && el.getAttribute('data-plugin-row') === (target.entryId || target.rowId);\n" +
    "      }) || rows.find(function (el) {\n" +
    "        return visible(el) && Array.from(el.querySelectorAll('code')).some(function (code) { return code.textContent === target.rowId; });\n" +
    "      });\n" +
    "      return row ? click(row.querySelector(':scope > div:first-child > div:first-of-type > button[type=button]')) : false;\n" +
    "    }\n" +
    "    return back(detail);\n" +
    "  }\n" +
    "  var installed = panel.querySelector('[role=tab][id$=\"-installed\"][aria-selected=\"false\"]');\n" +
    "  if (visible(installed)) return click(installed);\n" +
    "  var more = visible(panel.querySelector('[data-plugin-group=more]'));\n" +
    "  if (target.kind === 'list' || target.kind === 'item') {\n" +
    "    if (more) return click(panel.querySelector(':scope > header[data-window-drag] > button[type=button]'));\n" +
    "    if (target.kind === 'list') return panel.getAttribute('aria-busy') === 'false';\n" +
    "  }\n" +
    "  if (more && target.kind === 'more') return true;\n" +
    "  var attribute = target.kind === 'item' ? 'data-plugin-item' : 'data-plugin-package';\n" +
    "  var card = Array.from(panel.querySelectorAll('li[' + attribute + ']')).find(function (el) {\n" +
    "    return visible(el) && el.getAttribute(attribute) === target.name;\n" +
    "  });\n" +
    "  if (card) return click(card.querySelector(':scope > div:first-child > div:first-of-type > div:first-child > button[type=\"button\"]'));\n" +
    "  if (target.kind !== 'item' && !more && panel.getAttribute('aria-busy') === 'false') {\n" +
    "    return click(panel.querySelector('[data-plugin-group=\"extensions\"] > div:first-child > button'));\n" +
    "  }\n" +
    "  return false;\n" +
    "})()";
}
