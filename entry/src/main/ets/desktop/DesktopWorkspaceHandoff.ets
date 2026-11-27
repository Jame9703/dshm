import { getField, getRecord, getString, parseJson } from 'connection';

export interface DesktopWebDestination {
  host: string;
  sessionId: string;
  workspaceId: string;
  action: string;
  bundle: string;
}

export interface DesktopNativeDestination {
  host: string;
  sessionId: string;
  parentId: string;
  mode: string;
}

export interface DesktopWebContext {
  appearance: string;
  destination?: DesktopNativeDestination;
}

export function readDesktopWebDestination(value: string): DesktopWebDestination | undefined {
  if (!value) { return undefined; }
  const raw = parseJson(value);
  const host = getString(raw, 'host');
  if (!host) { return undefined; }
  return { host: host, sessionId: getString(raw, 'sessionId') ?? '', workspaceId: getString(raw, 'workspaceId') ?? '',
    action: getString(raw, 'action') ?? '', bundle: getString(raw, 'bundle') ?? '' };
}

export function readDesktopNativeDestination(value: string): DesktopNativeDestination | undefined {
  if (!value) { return undefined; }
  const raw = parseJson(value);
  const host = getString(raw, 'host');
  const sessionId = getString(raw, 'sessionId');
  if (!host || sessionId === undefined) { return undefined; }
  return { host: host, sessionId: sessionId, parentId: getString(raw, 'parentId') ?? '',
    mode: getString(raw, 'mode') ?? '' };
}

export function readDesktopWebContext(value: string, host: string): DesktopWebContext {
  const decoded = parseJson(value);
  const raw = typeof decoded === 'string' ? parseJson(decoded) : decoded;
  const preference = getString(raw, 'appearance');
  const appearance = preference === 'light' || preference === 'dark' ? preference : 'system';
  const selection = getRecord(raw, 'selection');
  if (selection === undefined) { return { appearance: appearance }; }
  const sessionId = getString(selection, 'sessionId') ?? '';
  const child = getRecord(selection, 'subagentAddress');
  if ((getField(selection, 'sessionId') !== undefined && !sessionId) ||
    (getField(selection, 'subagentAddress') !== undefined && child === undefined)) {
    return { appearance: appearance };
  }
  if (child === undefined) {
    return { appearance: appearance, destination: { host: host, sessionId: sessionId, parentId: '', mode: '' } };
  }
  const parentId = getString(child, 'parentSessionId') ?? '';
  const mode = getString(child, 'mode') ?? '';
  if (!parentId || !sessionId || parentId === sessionId || getString(child, 'childSessionId') !== sessionId ||
    (mode !== 'one-shot' && mode !== 'continuable' && mode !== 'unknown')) { return { appearance: appearance }; }
  return { appearance: appearance, destination: { host: host, sessionId: sessionId, parentId: parentId, mode: mode } };
}

export function buildDesktopWebContextScript(page: string): string {
  return "(function () {\n" +
    "  if (window !== window.top || location.origin + location.pathname !== " + JSON.stringify(page) + ") return null;\n" +
    "  var selection = null;\n" +
    "  try { selection = JSON.parse(localStorage.getItem('dsh.sessions.current')); } catch (_) {}\n" +
    "  return JSON.stringify({ appearance: document.documentElement.getAttribute('data-ds-theme-source'), selection });\n" +
    "})()";
}

export function buildDesktopPluginDetailScript(bundle: string): string {
  return "(function () {\n" +
    "  var bundle = " + JSON.stringify(bundle) + ";\n" +
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
    "  var detail = panel.querySelector('[data-plugin-detail]');\n" +
    "  if (visible(detail)) {\n" +
    "    return detail.getAttribute('data-plugin-detail') === bundle &&\n" +
    "      detail.querySelector('[data-plugin-name]')?.textContent === bundle;\n" +
    "  }\n" +
    "  var installed = panel.querySelector('[role=tab][id$=\"-installed\"][aria-selected=\"false\"]');\n" +
    "  if (visible(installed)) return click(installed);\n" +
    "  var card = Array.from(panel.querySelectorAll('li[data-plugin-package]')).find(function (el) {\n" +
    "    return visible(el) && el.getAttribute('data-plugin-package') === bundle;\n" +
    "  });\n" +
    "  if (card) return click(card.querySelector(':scope > div:first-child > div:first-of-type > div:first-child > button[type=\"button\"]'));\n" +
    "  if (panel.getAttribute('aria-busy') === 'false' && !panel.querySelector('[data-plugin-group=\"more\"]')) {\n" +
    "    return click(panel.querySelector('[data-plugin-group=\"extensions\"] > div:first-child > button'));\n" +
    "  }\n" +
    "  return false;\n" +
    "})()";
}
