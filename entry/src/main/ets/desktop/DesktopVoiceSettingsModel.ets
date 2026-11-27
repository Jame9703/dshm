import { getArray, getNumber, getRecord, getString } from 'connection';

export const DESKTOP_VOICE_BUNDLE: string = '@deepseek-ai/dsh-experimental-voice-input-bundle';

export interface DesktopVoiceSetupEstimate {
  diskBytes: number;
  memoryBytes: number;
  minimumMinutes: number;
  maximumMinutes: number;
}

export interface DesktopVoicePreparationStep {
  kind: string;
  status: string;
  startedAt: number;
}

export interface DesktopVoicePreparationFailure {
  resource: string;
  source: string;
  reason: string;
  code: string;
  status: number;
}

export interface DesktopVoicePreparation {
  phase: string;
  resource: string;
  completedBytes: number;
  totalBytes: number;
  startedAt: number;
  message: string;
  download?: DesktopVoicePreparationFailure;
  steps: DesktopVoicePreparationStep[];
}

export interface DesktopVoiceProvider {
  id: string;
  name: string;
  location: string;
  languages: string[];
  downloadSources: string[];
  preparation: DesktopVoicePreparation;
  estimate?: DesktopVoiceSetupEstimate;
}

export interface DesktopVoiceCatalog {
  providers: DesktopVoiceProvider[];
  providerId: string;
  language: string;
  maxAudioBytes: number;
  maxDurationSeconds: number;
}

function readEstimate(data?: Object): DesktopVoiceSetupEstimate | undefined {
  if (data === undefined) { return undefined; }
  return {
    diskBytes: getNumber(data, 'recommendedDiskBytes') ?? 0,
    memoryBytes: getNumber(data, 'expectedMemoryBytes') ?? 0,
    minimumMinutes: getNumber(data, 'minimumMinutes') ?? 0,
    maximumMinutes: getNumber(data, 'maximumMinutes') ?? 0
  };
}

function readFailure(data?: Object): DesktopVoicePreparationFailure | undefined {
  if (data === undefined) { return undefined; }
  return {
    resource: getString(data, 'resource') ?? '',
    source: getString(data, 'source') ?? '',
    reason: getString(data, 'reason') ?? 'unknown',
    code: getString(data, 'code') ?? '',
    status: getNumber(data, 'status') ?? 0
  };
}

function readPreparation(data?: Object): DesktopVoicePreparation {
  const steps: DesktopVoicePreparationStep[] = [];
  for (const step of getArray(data, 'steps') ?? []) {
    const kind = getString(step, 'kind');
    const status = getString(step, 'status');
    if (kind && status) { steps.push({ kind: kind, status: status, startedAt: getNumber(step, 'startedAt') ?? 0 }); }
  }
  return {
    phase: getString(data, 'phase') ?? 'unknown',
    resource: getString(data, 'resource') ?? '',
    completedBytes: Math.max(0, getNumber(data, 'completedBytes') ?? 0),
    totalBytes: Math.max(0, getNumber(data, 'totalBytes') ?? 0),
    startedAt: getNumber(data, 'startedAt') ?? 0,
    message: getString(data, 'message') ?? '',
    download: readFailure(getRecord(data, 'download')),
    steps: steps
  };
}

function readStrings(data: Object, key: string): string[] {
  const strings: string[] = [];
  for (const item of getArray(data, key) ?? []) {
    if (typeof item === 'string' && item && !strings.includes(item)) { strings.push(item); }
  }
  return strings;
}

export function readDesktopVoiceCatalog(data?: Object): DesktopVoiceCatalog | undefined {
  const rows = getArray(data, 'providers');
  const selection = getRecord(data, 'selection');
  if (rows === undefined || selection === undefined) { return undefined; }
  const providers: DesktopVoiceProvider[] = [];
  for (const row of rows) {
    const id = getString(row, 'id');
    if (!id) { continue; }
    providers.push({
      id: id,
      name: getString(row, 'name') || id,
      location: getString(row, 'location') ?? '',
      languages: readStrings(row, 'languages'),
      downloadSources: readStrings(row, 'downloadSources'),
      preparation: readPreparation(getRecord(row, 'preparation')),
      estimate: readEstimate(getRecord(row, 'setupEstimate'))
    });
  }
  return {
    providers: providers,
    providerId: getString(selection, 'providerId') ?? '',
    language: getString(selection, 'language') ?? '',
    maxAudioBytes: getNumber(data, 'maxAudioBytes') ?? 4 * 1024 * 1024,
    maxDurationSeconds: getNumber(data, 'maxDurationSeconds') ?? 120
  };
}

export function desktopVoiceSelectedProvider(catalog?: DesktopVoiceCatalog): DesktopVoiceProvider | undefined {
  if (catalog === undefined) { return undefined; }
  return catalog.providers.find((provider: DesktopVoiceProvider): boolean => provider.id === catalog.providerId);
}

export function desktopVoiceNeedsInstallation(provider?: DesktopVoiceProvider): boolean {
  return provider?.location === 'host-local' && provider.preparation.phase === 'unprepared';
}

export function desktopVoiceIsReady(phase?: string): boolean {
  return phase === 'ready' || phase === 'standby' || phase === 'waking';
}

export function desktopVoiceProviderPatch(provider: DesktopVoiceProvider, language: string): Record<string, Object> {
  const patch: Record<string, Object> = { 'providerId': provider.id };
  if (provider.languages.length > 0 && !provider.languages.includes(language)) {
    patch['language'] = provider.languages.includes('auto') ? 'auto' : provider.languages[0];
  }
  return patch;
}
