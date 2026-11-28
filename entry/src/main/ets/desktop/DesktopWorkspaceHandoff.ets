import { getArray, getBoolean, getField, getRecord, getString, parseJson } from 'connection';

export interface DesktopHandoffSubagent {
  parentSessionId: string;
  childSessionId: string;
  mode: string;
}

export interface DesktopPluginLocation {
  kind: 'list' | 'more' | 'item' | 'package' | 'row';
  name: string;
  rowId: string;
  entryId?: string;
}

export interface DesktopCordisWebLocation {
  pluginId: string;
  packageId: string;
  requestId: string;
}

export interface DesktopWebDestination {
  host: string;
  sessionId: string;
  workspaceId: string;
  action: string;
  bundle: string;
  plugin?: DesktopPluginLocation;
  cordis?: DesktopCordisWebLocation;
  subagent?: DesktopHandoffSubagent;
}

export interface DesktopNativeDestination {
  host: string;
  sessionId: string;
  parentId: string;
  mode: string;
  plugin?: DesktopPluginLocation;
  preserveSession?: boolean;
  ancestors?: DesktopHandoffSubagent[];
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

function readHandoffSubagent(value: Object | undefined, sessionId: string): DesktopHandoffSubagent | undefined {
  const parentId = getString(value, 'parentSessionId') ?? '';
  const mode = getString(value, 'mode') ?? '';
  if (!parentId || !sessionId || parentId === sessionId || getString(value, 'childSessionId') !== sessionId ||
    (mode !== 'one-shot' && mode !== 'continuable' && mode !== 'unknown')) { return undefined; }
  return { parentSessionId: parentId, childSessionId: sessionId, mode: mode };
}

function readHandoffAncestors(values: Object[] | undefined, childId: string, parentId: string): DesktopHandoffSubagent[] {
  const ancestors: DesktopHandoffSubagent[] = [];
  const visited = new Set<string>([childId, parentId]);
  let id = parentId;
  for (const value of values ?? []) {
    const ancestor = readHandoffSubagent(value, id);
    if (ancestor === undefined || visited.has(ancestor.parentSessionId)) { return []; }
    ancestors.push(ancestor);
    id = ancestor.parentSessionId;
    visited.add(id);
  }
  return ancestors;
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
  if (destination.action === 'cordis') {
    const cordis = getRecord(raw, 'cordis');
    const pluginId = getString(cordis, 'pluginId');
    if (!pluginId || !destination.sessionId) { return undefined; }
    destination.cordis = { pluginId: pluginId, packageId: getString(cordis, 'packageId') ?? '',
      requestId: getString(cordis, 'requestId') ?? '' };
  }
  if (getField(raw, 'subagent') !== undefined) {
    const child = readHandoffSubagent(getRecord(raw, 'subagent'), destination.sessionId);
    if (child === undefined) { return undefined; }
    destination.subagent = child;
  }
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
  if (destination.parentId) {
    if (!sessionId || destination.parentId === sessionId ||
      (destination.mode !== 'one-shot' && destination.mode !== 'continuable' && destination.mode !== 'unknown')) {
      return undefined;
    }
    const ancestors = readHandoffAncestors(getArray(raw, 'ancestors'), sessionId, destination.parentId);
    if (ancestors.length > 0) { destination.ancestors = ancestors; }
  }
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
    const address = readHandoffSubagent(child, sessionId);
    if (address === undefined) { return fallback; }
    destination.parentId = address.parentSessionId;
    destination.mode = address.mode;
    const ancestors = readHandoffAncestors(getArray(raw, 'ancestors'), sessionId, address.parentSessionId);
    if (ancestors.length > 0) { destination.ancestors = ancestors; }
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
    "  var readAncestors = globalThis.__DSHM_READ_WORKSPACE_SUBAGENT_ANCESTORS__;\n" +
    "  var ancestors;\n" +
    "  if (selection?.subagentAddress && typeof readAncestors === 'function') {\n" +
    "    try { ancestors = readAncestors(selection.subagentAddress); } catch (_) {}\n" +
    "  }\n" +
    "  return JSON.stringify({ appearance: document.documentElement.getAttribute('data-ds-theme-source'), selection, plugin, ancestors });\n" +
    "})()";
}

export function buildDesktopWorkspaceSessionScript(target: DesktopWebDestination): string {
  return `(function () {
    var id = ${JSON.stringify(target.sessionId)};
    var workspace = ${JSON.stringify(target.workspaceId)};
    var child = ${target.subagent === undefined ? 'null' : JSON.stringify(target.subagent)};
    var exactRow = function (key) {
      return document.querySelector('[data-row-key="' + CSS.escape(key) + '"]');
    };
    if (typeof globalThis.__DSHM_OPEN_WORKSPACE_SESSION__ === 'function') {
      if (!globalThis.__DSHM_OPEN_WORKSPACE_SESSION__(child || id)) return false;
      try {
        var selected = JSON.parse(localStorage.getItem('dsh.sessions.current'));
        var address = selected?.subagentAddress;
        return selected?.sessionId === id && (!child ||
          (address?.parentSessionId === child.parentSessionId && address.childSessionId === id &&
           address.mode === child.mode));
      } catch (_) { return false; }
    }
    if (child) return false;
    var row = exactRow('session:' + id);
    if (row) {
      if (row.getAttribute('aria-selected') === 'true') return true;
      row.click();
      return false;
    }
    var sidebar = globalThis.__DSHM_SIDEBAR__;
    if (sidebar && sidebar.state() === 'collapsed') {
      sidebar.toggle();
      return false;
    }
    var group = exactRow('workspace:' + workspace);
    if (group && group.getAttribute('aria-expanded') === 'false') {
      group.click();
      return false;
    }
    var more = exactRow('overflow:' + workspace);
    if (more && more.getAttribute('aria-expanded') === 'false') more.click();
    return false;
  })()`;
}

export function buildDesktopPluginDetailScript(bundle: string): string {
  return buildDesktopPluginViewScript({ kind: 'package', name: bundle, rowId: '' });
}

/** Reveal the same stock Cordis row and version. Execution stays behind WebUI controls. */
export function buildDesktopCordisPanelScript(location: DesktopCordisWebLocation, sessionId: string): string {
  return `(function () {
    var target = ${JSON.stringify(location)};
    var session = ${JSON.stringify(sessionId)};
    var selected;
    try { selected = JSON.parse(localStorage.getItem('dsh.sessions.current')); } catch (_) {}
    if (selected && selected.sessionId !== session) return false;
    if (!selected && !document.querySelector('[data-row-key="' + CSS.escape('session:' + session) +
      '"][aria-selected="true"]')) return false;
    var visible = function (el) { return el && el.getClientRects().length > 0; };
    var panel = document.querySelector('[data-cordis-panel]');
    if (!visible(panel)) {
      var trigger = document.querySelector('button[data-cordis-badge][aria-expanded="false"]');
      if (visible(trigger) && !trigger.disabled) trigger.click();
      return false;
    }
    var row = Array.from(panel.querySelectorAll('[data-cordis-row]')).find(function (el) {
      return visible(el) && el.getAttribute('data-cordis-row') === target.pluginId;
    });
    if (!row) return false;
    if (target.requestId) {
      var approval = Array.from(row.querySelectorAll('[data-cordis-approve]')).find(function (el) {
        return visible(el) && el.getAttribute('data-cordis-approve') === target.requestId;
      });
      if (!approval) return false;
    }
    var versions = row.querySelector('select');
    if (target.packageId && versions && versions.value !== target.packageId) {
      if (versions.disabled || !Array.from(versions.options).some(function (item) {
        return item.value === target.packageId && !item.disabled;
      })) return false;
      versions.value = target.packageId;
      versions.dispatchEvent(new Event('change', { bubbles: true }));
      return false;
    }
    row.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    return true;
  })()`;
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
