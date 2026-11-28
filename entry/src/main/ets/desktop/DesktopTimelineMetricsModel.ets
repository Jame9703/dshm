export const DESKTOP_TIMELINE_MINUTE: number = 60000;

export function desktopTimelineDuration(ms: number): string {
  const minutes = Math.floor(ms / DESKTOP_TIMELINE_MINUTE);
  if (minutes < 1) { return '<1m'; }
  const hours = Math.floor(minutes / 60);
  return hours > 0 ? String(hours) + 'h ' + (minutes % 60) + 'm' : String(minutes) + 'm';
}

export function desktopTimelineElapsed(createdAt: number, latestActivityAt: number, now: number,
  working: boolean): number {
  const observation = working ? Math.floor(now / DESKTOP_TIMELINE_MINUTE) * DESKTOP_TIMELINE_MINUTE :
    Math.max(createdAt, latestActivityAt);
  return Math.max(0, observation - createdAt);
}

export function desktopTimelineEstimate(elapsed: number, progress: number): string {
  if (progress <= 0) { return ''; }
  const minutes = Math.round(elapsed * (1 - progress) / progress / DESKTOP_TIMELINE_MINUTE);
  return '≈' + desktopTimelineDuration(Math.max(1, minutes) * DESKTOP_TIMELINE_MINUTE);
}

export function desktopTimelinePeriodLabel(ms: number): string {
  const minutes = ms / DESKTOP_TIMELINE_MINUTE;
  if (minutes >= 1440) { return Number((minutes / 1440).toFixed(2)) + 'd'; }
  if (minutes >= 60) { return Number((minutes / 60).toFixed(2)) + 'h'; }
  return Number(minutes.toFixed(2)) + 'm';
}

export function desktopTimelineWeight(weight: number): string {
  return String(Number(weight.toFixed(2)));
}
