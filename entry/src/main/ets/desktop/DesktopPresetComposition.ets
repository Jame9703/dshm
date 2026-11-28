import { getString } from 'connection';
import { AGENT_PRESETS_READ_ENDPOINT } from 'dshcompat';
import type { DesktopHostActions } from './DesktopHostActions';

export interface DesktopPresetComposition {
  yaml?: string;
  problem: string;
}

export async function readDesktopPresetComposition(host: DesktopHostActions,
  id: string): Promise<DesktopPresetComposition> {
  const reply = await host.call(AGENT_PRESETS_READ_ENDPOINT, { 'agentPreset': id });
  if (!reply.ok) { return { problem: reply.error?.message ?? '' }; }
  const yaml = getString(reply.value, 'agentPreset') === id ? getString(reply.value, 'content') : undefined;
  return { yaml: yaml, problem: '' };
}
