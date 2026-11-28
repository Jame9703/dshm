import { SETTINGS_UPDATE_ENDPOINT } from 'dshcompat';
import type { DesktopHostActions } from './DesktopHostActions';

export type DesktopPresetDefaultSync = (id: string) => Promise<string>;

const saving = new WeakSet<DesktopHostActions>();

export async function writeDesktopPresetDefault(host: DesktopHostActions, id: string,
  reload: () => Promise<string | undefined>, sync?: DesktopPresetDefaultSync): Promise<ResourceStr> {
  if (saving.has(host)) { return ''; }
  saving.add(host);
  try {
    const patch: Record<string, Object> = { 'selectedDefault': id };
    const result = await host.call(SETTINGS_UPDATE_ENDPOINT, { 'ns': 'agent-preset-registry', 'patch': patch });
    const selected = await reload();
    if (!result.ok) { return result.error?.message || $r('app.string.desktop_preset_default_save_failed'); }
    if (selected && sync !== undefined) { return await sync(selected); }
    return '';
  } finally {
    saving.delete(host);
  }
}
