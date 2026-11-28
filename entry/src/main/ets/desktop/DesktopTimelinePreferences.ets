import { getBoolean, getNumber } from 'connection';

export const DESKTOP_TIMELINE_NS: string = 'timeline-experimental';

export interface DesktopTimelinePreferences {
  decimals: number;
  autoOpenSidebar: boolean;
  segmentedProgress: boolean;
}

export const DEFAULT_DESKTOP_TIMELINE_PREFERENCES: DesktopTimelinePreferences = {
  decimals: 2, autoOpenSidebar: false, segmentedProgress: true
};

export function desktopTimelinePreferences(value?: Object): DesktopTimelinePreferences {
  const decimals = getNumber(value, 'progressDecimals') ?? 2;
  return { decimals: Number.isInteger(decimals) && decimals >= 0 && decimals <= 3 ? decimals : 2,
    autoOpenSidebar: getBoolean(value, 'autoOpenSidebar') === true,
    segmentedProgress: getBoolean(value, 'segmentedProgress') !== false };
}

export function desktopTimelinePercent(value: number, decimals: number): string {
  const percent = Math.max(0, Math.min(1, value)) * 100;
  return Math.min(percent, value < 1 ? 100 - Math.pow(10, -decimals) : 100).toFixed(decimals);
}
