import type { DesktopTimelineReport } from './DesktopTimelineModel';

export const TIMELINE_RULER_HOUR: number = 3600000;
export const TIMELINE_RULER_MINUTE: number = 60000;
export const TIMELINE_RULER_DAY: number = 24 * TIMELINE_RULER_HOUR;
export const TIMELINE_RULER_WEEK: number = 7 * TIMELINE_RULER_DAY;
export const TIMELINE_RULER_MAX_ZOOM: number = 6;
const CHUNK_SIZE: number = 64;
const MIN_BAR: number = 8;

export interface DesktopTimelineRulerBlock {
  report: DesktopTimelineReport;
  top: number;
  height: number;
}

interface DesktopTimelineReportChunk {
  reports: DesktopTimelineReport[];
  oldestStart: number;
  latestEnd: number;
}

export interface DesktopTimelineRulerTick {
  time: number;
  position: number;
  major: boolean;
}

export interface DesktopTimelineRulerWindow {
  zoom: number;
  offset: number;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export class DesktopTimelineScale {
  readonly anchor: number;
  readonly density: number;
  readonly height: number;

  constructor(anchor: number, density: number) {
    this.anchor = anchor;
    this.density = density;
    this.height = TIMELINE_RULER_WEEK / TIMELINE_RULER_HOUR * density;
  }

  position(time: number): number {
    return clamp((this.anchor - time) / TIMELINE_RULER_HOUR * this.density, 0, this.height);
  }

  time(position: number): number {
    return this.anchor - clamp(position, 0, this.height) / this.density * TIMELINE_RULER_HOUR;
  }

  offset(position: number, viewport: number): number {
    return clamp(position, 0, Math.max(0, this.height - viewport));
  }
}

function zoomStops(viewport: number): number[] {
  return [2, 24, 120, 360, 1200, 3600, Math.max(3600, viewport * 60)];
}

export function desktopTimelineDensity(zoom: number, viewport: number): number {
  const stops = zoomStops(viewport);
  const step = clamp(zoom, 0, TIMELINE_RULER_MAX_ZOOM);
  const lower = stops[Math.floor(step)];
  const higher = stops[Math.ceil(step)];
  return Math.max(viewport / 168, lower * Math.pow(higher / lower, step - Math.floor(step)));
}

function zoomFor(density: number, viewport: number): number {
  const stops = zoomStops(viewport);
  for (let i = 0; i < stops.length; i++) {
    if (density <= stops[i]) {
      if (i === 0) { return 0; }
      return i - 1 + Math.log(density / stops[i - 1]) / Math.log(stops[i] / stops[i - 1]);
    }
  }
  return TIMELINE_RULER_MAX_ZOOM;
}

export function desktopTimelineScale(anchor: number, zoom: number, viewport: number): DesktopTimelineScale {
  return new DesktopTimelineScale(anchor, desktopTimelineDensity(zoom, viewport));
}

export function desktopTimelineZoomOffset(prior: DesktopTimelineScale, next: DesktopTimelineScale,
  offset: number, pointer: number, viewport: number): number {
  const fixed = prior.time(offset + pointer);
  return next.offset(next.position(fixed) - pointer, viewport);
}

export function desktopTimelineLiveAnchor(now: number, reports: DesktopTimelineReport[]): number {
  const minute = Math.floor(now / TIMELINE_RULER_MINUTE) * TIMELINE_RULER_MINUTE;
  for (const row of reports) {
    if (row.end <= minute) { break; }
    if (row.end < minute + TIMELINE_RULER_MINUTE) { return row.end; }
  }
  return minute;
}

export function desktopTimelineReportInWeek(row: DesktopTimelineReport, anchor: number): boolean {
  return row.end > anchor - TIMELINE_RULER_WEEK && row.start < anchor;
}

export function desktopTimelineRulerFit(reports: DesktopTimelineReport[], level: number, span: number, anchor: number,
  viewport: number, near: number, target?: DesktopTimelineReport): DesktopTimelineRulerWindow {
  const rows = reports.filter((row: DesktopTimelineReport): boolean =>
    row.level === level && desktopTimelineReportInWeek(row, anchor));
  let nearest = target;
  if (nearest === undefined) {
    let distance = Infinity;
    for (const row of rows) {
      const next = Math.max(row.start - near, near - row.end, 0);
      if (next < distance) { nearest = row; distance = next; }
    }
  }
  const index = nearest === undefined ? 0 : rows.indexOf(nearest);
  const first = Math.max(0, Math.min(index - 1, rows.length - 3));
  const durations = rows.slice(first, first + 3)
    .map((row: DesktopTimelineReport): number => row.end - row.start).sort((a: number, b: number): number => a - b);
  const duration = Math.max(TIMELINE_RULER_MINUTE, target === undefined ?
    (durations[Math.floor(durations.length / 2)] ?? span) : target.end - target.start);
  const fit = viewport * TIMELINE_RULER_HOUR / (duration * (target === undefined ? (durations.length || 3) + 0.5 : 1.25));
  const readable = target === undefined ? 0 : 92 * TIMELINE_RULER_HOUR / Math.max(1, target.end - target.start);
  const zoom = zoomFor(Math.max(viewport / 168, Math.min(viewport * 60, Math.max(fit, readable))), viewport);
  const scale = desktopTimelineScale(anchor, zoom, viewport);
  return { zoom: zoom, offset: scale.offset(scale.position(nearest?.end ?? anchor) - viewport * 0.08, viewport) };
}

export class DesktopTimelineRulerIndex {
  private readonly chunks: DesktopTimelineReportChunk[] = [];
  constructor(reports: DesktopTimelineReport[]) {
    for (let i = 0; i < reports.length; i += CHUNK_SIZE) {
      const slice = reports.slice(i, i + CHUNK_SIZE);
      let oldest = Infinity;
      for (const row of slice) { oldest = Math.min(oldest, row.start); }
      this.chunks.push({ reports: slice, oldestStart: oldest, latestEnd: slice[0].end });
    }
  }

  visible(scale: DesktopTimelineScale, offset: number, viewport: number): DesktopTimelineRulerBlock[] {
    const before = Math.max(0, offset - viewport);
    const after = Math.min(scale.height, offset + 2 * viewport);
    const newest = scale.time(before);
    const oldest = scale.time(after);
    const result: DesktopTimelineRulerBlock[] = [];
    const tiny = new Set<string>();
    for (const chunk of this.chunks) {
      if (chunk.latestEnd <= oldest) { break; }
      if (chunk.oldestStart >= newest) { continue; }
      for (const report of chunk.reports) {
        if (report.end <= oldest || report.start >= newest) { continue; }
        const top = Math.max(before, scale.position(report.end));
        const height = Math.min(after, scale.position(report.start)) - top;
        if (height <= 0) { continue; }
        if (height < MIN_BAR) {
          const block = String(report.level) + ':' + Math.floor(top / MIN_BAR);
          if (tiny.has(block)) { continue; }
          tiny.add(block);
        }
        result.push({ report: report, top: top, height: Math.min(scale.height - top, Math.max(MIN_BAR, height)) });
      }
    }
    return result;
  }
}

const TICK_MINUTES: number[] = [1, 2, 5, 10, 15, 30, 60, 120, 180, 360, 720, 1440, 2880, 10080];

function tickInterval(density: number, spacing: number): number {
  const required = spacing * 60 / density;
  return (TICK_MINUTES.find((minutes: number): boolean => minutes >= required) ?? 10080) * TIMELINE_RULER_MINUTE;
}

export function desktopTimelineRulerTicks(scale: DesktopTimelineScale, offset: number,
  viewport: number): DesktopTimelineRulerTick[] {
  const before = Math.max(0, offset - viewport);
  const after = Math.min(scale.height, offset + viewport * 2);
  const newest = scale.time(before);
  const oldest = scale.time(after);
  const major = tickInterval(scale.density, 78);
  const minor = tickInterval(scale.density, 28);
  const zone = new Date(scale.anchor).getTimezoneOffset() * TIMELINE_RULER_MINUTE;
  const result: DesktopTimelineRulerTick[] = [];
  for (let time = Math.floor((newest - zone) / major) * major + zone; time >= oldest && result.length < 150; time -= major) {
    if (time < scale.anchor) { result.push({ time: time, position: scale.position(time), major: true }); }
  }
  const prominent = result.slice();
  for (let time = Math.floor((newest - zone) / minor) * minor + zone; time >= oldest && result.length < 220; time -= minor) {
    const position = scale.position(time);
    if (time < scale.anchor && !prominent.some((tick: DesktopTimelineRulerTick): boolean => Math.abs(tick.position - position) < 14)) {
      result.push({ time: time, position: position, major: false });
    }
  }
  return result;
}
