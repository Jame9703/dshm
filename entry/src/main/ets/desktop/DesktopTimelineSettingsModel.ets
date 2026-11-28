import { getArray, getNumber, getString } from 'connection';
import { DESKTOP_TIMELINE_NS } from './DesktopTimelinePreferences';
import type { DesktopPluginEdit } from './DesktopPluginSettingsModel';

export const DESKTOP_TIMELINE_BUNDLE: string = '@deepseek-ai/dsh-timeline';
export { DESKTOP_TIMELINE_NS } from './DesktopTimelinePreferences';
export const TIMELINE_MINUTE_MS: number = 60000;
export const TIMELINE_HOUR_MS: number = 60 * TIMELINE_MINUTE_MS;
export const TIMELINE_DAY_MS: number = 24 * TIMELINE_HOUR_MS;
export const TIMELINE_HISTORY_MS: number = 7 * TIMELINE_DAY_MS;
export const TIMELINE_PROMPT_LIMIT: number = 32768;
export const TIMELINE_MAX_LEVELS: number = 5;
export const TIMELINE_LANGUAGES: string[] = ['ui', 'chat', 'en', 'zh-CN', 'ja', 'es', 'fr', 'de', 'ru', 'pt'];
export const TIMELINE_DEFAULT_TASK: string = "Use short, outcome-based titles. Break deliverables into checkable child actions. State the result or blocker in note. Use details for evidence, limits, and the effect on the goal. Explain unfamiliar names and what meaningful measurements show. Include counts only when they answer the user's question.";
export const TIMELINE_DEFAULT_SUMMARY: string = "Focus on what changed and why it matters to the user's goal. Lead with a concrete result or finding. Add useful evidence, consequences, and remaining gaps when the record supports them.";

export interface DesktopTimelinePeriod {
  id: number;
  text: string;
  hour: boolean;
  prompt: string;
}

export function desktopTimelinePeriod(id: number, ms: number, prompt: string, hour: boolean =
  ms >= TIMELINE_HOUR_MS && ms % TIMELINE_HOUR_MS === 0): DesktopTimelinePeriod {
  return { id: id, text: String(ms / (hour ? TIMELINE_HOUR_MS : TIMELINE_MINUTE_MS)), hour: hour, prompt: prompt };
}

export function desktopTimelinePeriods(value?: Object): DesktopTimelinePeriod[] {
  let previous = getNumber(value, 'intervalMs') ?? 15 * TIMELINE_MINUTE_MS;
  const factors = getArray(value, 'rollupFactors') ?? [4, 4];
  const prompts = getArray(value, 'levelPrompts') ?? [];
  const levels = [desktopTimelinePeriod(0, previous, typeof prompts[0] === 'string' ? String(prompts[0]) : '')];
  for (const factor of factors) {
    if (typeof factor !== 'number' || !Number.isFinite(factor) || levels.length >= TIMELINE_MAX_LEVELS) { break; }
    previous = Math.round(previous * factor);
    const prompt = prompts[levels.length];
    levels.push(desktopTimelinePeriod(levels.length, previous, typeof prompt === 'string' ? String(prompt) : ''));
  }
  return levels;
}

export function desktopTimelineMilliseconds(period: DesktopTimelinePeriod): number {
  if (!period.text.trim()) { return 0; }
  return Math.round(Number(period.text) * (period.hour ? TIMELINE_HOUR_MS : TIMELINE_MINUTE_MS));
}

export function desktopTimelineValidPeriods(levels: DesktopTimelinePeriod[]): boolean {
  if (levels.length === 0 || levels.length > TIMELINE_MAX_LEVELS) { return false; }
  let previous = 0;
  for (const level of levels) {
    const ms = desktopTimelineMilliseconds(level);
    if (!Number.isSafeInteger(ms) || ms < TIMELINE_MINUTE_MS || ms <= previous ||
      ms > (previous === 0 ? TIMELINE_DAY_MS : TIMELINE_HISTORY_MS) || level.prompt.length > TIMELINE_PROMPT_LIMIT) {
      return false;
    }
    previous = ms;
  }
  return true;
}

export function desktopTimelinePeriodEdits(value: Object | undefined, levels: DesktopTimelinePeriod[]): DesktopPluginEdit[] {
  const prior = desktopTimelinePeriods(value);
  const periods = levels.map(desktopTimelineMilliseconds);
  const changedPeriods = JSON.stringify(periods) !== JSON.stringify(prior.map(desktopTimelineMilliseconds));
  const prompts = levels.map((row: DesktopTimelinePeriod): string => row.prompt);
  const changedPrompts = JSON.stringify(prompts) !== JSON.stringify(prior.map((row: DesktopTimelinePeriod): string => row.prompt));
  const edits: DesktopPluginEdit[] = [];
  if (changedPeriods) {
    edits.push({ namespace: DESKTOP_TIMELINE_NS, field: 'intervalMs', value: periods[0] },
      { namespace: DESKTOP_TIMELINE_NS, field: 'rollupFactors',
        value: periods.slice(1).map((ms: number, index: number): number => ms / periods[index]) });
  }
  if (changedPeriods || changedPrompts) {
    edits.push({ namespace: DESKTOP_TIMELINE_NS, field: 'levelPrompts', value: prompts });
  }
  return edits;
}

export function desktopTimelineTask(value?: Object): string {
  return getString(value, 'taskPrompt') ?? TIMELINE_DEFAULT_TASK;
}

export function desktopTimelineSummary(value?: Object): string {
  return getString(value, 'summaryPrompt') ?? TIMELINE_DEFAULT_SUMMARY;
}
