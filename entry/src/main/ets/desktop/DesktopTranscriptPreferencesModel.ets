import { SettingItem, SettingKind } from 'appstate';

export type DesktopTranscriptMode = 'compact' | 'standard' | 'detailed' | 'verbose';
export type DesktopTranscriptCollapseTiming = 'completion' | 'next-input';
export type DesktopTranscriptFoldedReplies = 'all' | 'final';

export const DESKTOP_TRANSCRIPT_VIEW_KEY: string = 'ui-chat.transcriptView';
export const DESKTOP_COLLAPSE_TIMING_KEY: string = 'ui-chat.collapseTiming';
export const DESKTOP_FOLDED_REPLIES_KEY: string = 'ui-chat.foldedReplies';

const PREFERENCE_KEYS: string[] = [
  DESKTOP_TRANSCRIPT_VIEW_KEY, DESKTOP_COLLAPSE_TIMING_KEY, DESKTOP_FOLDED_REPLIES_KEY
];

export function isDesktopTranscriptPreference(key: string): boolean {
  return PREFERENCE_KEYS.includes(key);
}

export function hasDesktopTranscriptPreferences(items: SettingItem[]): boolean {
  return PREFERENCE_KEYS.every((key: string): boolean =>
    items.some((item: SettingItem): boolean =>
      item.key === key && item.kind === SettingKind.CHOICE && item.choices.length > 0));
}

export function readDesktopTranscriptMode(value?: string): DesktopTranscriptMode {
  if (value === 'normal' || value === 'expanded') { return 'detailed'; }
  if (value === 'compact' || value === 'detailed' || value === 'verbose') { return value; }
  return 'standard';
}

export function readDesktopTranscriptCollapseTiming(value?: string): DesktopTranscriptCollapseTiming {
  return value === 'next-input' ? value : 'completion';
}

export function readDesktopTranscriptFoldedReplies(value?: string): DesktopTranscriptFoldedReplies {
  return value === 'final' ? value : 'all';
}

export function desktopTranscriptPreferenceValue(key: string, value: string): string {
  if (key === DESKTOP_TRANSCRIPT_VIEW_KEY) { return readDesktopTranscriptMode(value); }
  if (key === DESKTOP_COLLAPSE_TIMING_KEY) { return readDesktopTranscriptCollapseTiming(value); }
  return readDesktopTranscriptFoldedReplies(value);
}

export function showDesktopFoldedReplies(items: SettingItem[]): boolean {
  const mode: SettingItem | undefined = items.find((item: SettingItem): boolean =>
    item.key === DESKTOP_TRANSCRIPT_VIEW_KEY);
  return readDesktopTranscriptMode(mode?.textValue) !== 'verbose';
}
