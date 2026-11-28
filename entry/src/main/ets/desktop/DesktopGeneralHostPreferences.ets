import { getArray, getBoolean, getString } from 'connection';
import type { RpcResult } from 'connection';
import { SETTINGS_MUTATE_ENDPOINT } from 'dshcompat';
import { desktopPluginPathOps, readDesktopPluginDocument } from './DesktopPluginSettingsModel';
import type { DesktopPluginDocument, DesktopPluginEdit } from './DesktopPluginSettingsModel';

export const DESKTOP_PERMISSION_SETTINGS_NS: string = 'permission';
export const DESKTOP_SESSION_LOG_SETTINGS_NS: string = 'session-log-deepseek';
export const DESKTOP_FULL_ACCESS_PRESET: string = 'danger-full-access';

export interface DesktopGeneralHostAccess {
  call: (endpoint: string, body?: Record<string, Object | null>) => Promise<RpcResult>;
}

export interface DesktopPermissionDefaultOption {
  id: string;
  name: string;
}

export interface DesktopPermissionDefaultView {
  document: DesktopPluginDocument;
  current: string;
  options: DesktopPermissionDefaultOption[];
}

export interface DesktopGeneralHostDocuments {
  writable: boolean;
  permission?: DesktopPluginDocument;
  uploads?: DesktopPluginDocument;
}

export function readDesktopGeneralHostDocuments(value?: Object): DesktopGeneralHostDocuments {
  const out: DesktopGeneralHostDocuments = { writable: getBoolean(value, 'writable') === true };
  for (const row of getArray(value, 'namespaces') ?? []) {
    const document = readDesktopPluginDocument(row);
    if (document?.id === DESKTOP_PERMISSION_SETTINGS_NS) { out.permission = document; }
    if (document?.id === DESKTOP_SESSION_LOG_SETTINGS_NS && getBoolean(document.value, 'enabled') !== undefined) {
      out.uploads = document;
    }
  }
  return out;
}

export function desktopPermissionDefaultView(document: DesktopPluginDocument, catalog?: Object):
  DesktopPermissionDefaultView | undefined {
  const options: DesktopPermissionDefaultOption[] = [];
  for (const row of getArray(catalog, 'defaultOptions') ?? []) {
    const id = getString(row, 'value') ?? '';
    if (id && !options.some((option: DesktopPermissionDefaultOption): boolean => option.id === id)) {
      options.push({ id: id, name: getString(row, 'name') || id });
    }
  }
  const current = getString(document.value, 'defaultPreset') ?? getString(catalog, 'defaultPreset') ?? '';
  return options.some((option: DesktopPermissionDefaultOption): boolean => option.id === current) ?
    { document: document, current: current, options: options } : undefined;
}

export function allowsDesktopPermissionDefault(view: DesktopPermissionDefaultView | undefined, id: string,
  acknowledged: boolean): boolean {
  return view !== undefined && id !== view.current && (id !== DESKTOP_FULL_ACCESS_PRESET || acknowledged) &&
    view.options.some((option: DesktopPermissionDefaultOption): boolean => option.id === id);
}

export function writeDesktopGeneralHostPreference(host: DesktopGeneralHostAccess, document: DesktopPluginDocument,
  field: string, value: Object): Promise<RpcResult> {
  const edit: DesktopPluginEdit = { namespace: document.id, field: field, value: value };
  return host.call(SETTINGS_MUTATE_ENDPOINT, { 'ns': document.id,
    'ops': desktopPluginPathOps([edit], document.id), 'expectedRevision': document.revision });
}
