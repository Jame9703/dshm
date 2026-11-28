import { readPiAiReasoningEntries } from 'appstate';
import type { PiAiModelRow, PiAiReasoningEntry, PiAiReasoningProblem, PiAiReasoningProtocol } from 'appstate';
import { cloneDesktopPiAiModel } from './DesktopPiAiModelFields';

const INITIAL_LEVELS: string[] = ['off', 'low', 'medium', 'high'];

export function desktopPiAiReasoningLabel(problem: PiAiReasoningProblem): ResourceStr {
  switch (problem) {
    case 'levels-only': return $r('app.string.desktop_model_reasoning_levels_only');
    case 'missing-value': return $r('app.string.desktop_model_reasoning_needs_value');
    case 'missing-level': return $r('app.string.desktop_model_reasoning_needs_level');
    default: return '';
  }
}

function defaultWire(level: string): Object | null { return level === 'off' ? null : level; }

export function desktopPiAiReasoningEnabled(model: PiAiModelRow, enabled: boolean, levels: string[]): PiAiModelRow {
  return desktopPiAiReasoningModel(model, enabled ? INITIAL_LEVELS.filter((level: string): boolean => levels.includes(level))
    .map((level: string): PiAiReasoningEntry => ({ level: level, wire: defaultWire(level) })) : undefined);
}

export function desktopPiAiReasoningModel(model: PiAiModelRow, entries?: PiAiReasoningEntry[]): PiAiModelRow {
  const next = cloneDesktopPiAiModel(model);
  const fields: Record<string, Object> = {};
  const existing = model.extraFields;
  if (existing !== undefined) {
    for (const key of Object.keys(existing)) {
      if (key !== 'reasoningEfforts') { fields[key] = existing[key]; }
    }
  }
  if (entries !== undefined) {
    const wire: Record<string, Object | null> = {};
    for (const entry of entries) {
      if (entry.level !== '__proto__' && entry.level !== 'constructor' && entry.level !== 'prototype') {
        wire[entry.level] = entry.wire ?? null;
      }
    }
    fields['reasoningEfforts'] = wire;
  }
  next.extraFields = Object.keys(fields).length > 0 ? fields : undefined;
  return next;
}

export function desktopPiAiReasoningChoices(entries: PiAiReasoningEntry[], level: string, levels: string[]): string[] {
  const used = new Set<string>(entries.map((entry: PiAiReasoningEntry): string => entry.level));
  const available = levels.filter((choice: string): boolean => choice === level || !used.has(choice));
  return levels.includes(level) ? available : [level, ...available];
}

export function desktopPiAiAddReasoningLevel(model: PiAiModelRow, levels: string[]): PiAiModelRow {
  const entries = readPiAiReasoningEntries(model);
  if (entries === undefined) { return model; }
  const used = entries.map((entry: PiAiReasoningEntry): string => entry.level);
  const highest = Math.max(-1, ...used.map((id: string): number => levels.indexOf(id)));
  const next = levels.find((id: string, index: number): boolean => index > highest && !used.includes(id)) ??
    levels.find((id: string): boolean => !used.includes(id));
  return next === undefined ? model : desktopPiAiReasoningModel(model, [...entries, { level: next, wire: defaultWire(next) }]);
}

export function desktopPiAiChangeReasoningLevel(model: PiAiModelRow, index: number, level: string,
  protocol: PiAiReasoningProtocol): PiAiModelRow {
  const entries = readPiAiReasoningEntries(model);
  const previous = entries?.[index];
  if (entries === undefined || previous === undefined || level === previous.level ||
      !desktopPiAiReasoningChoices(entries, previous.level, protocol.levels).includes(level)) { return model; }
  const carries = !protocol.levelsOnly && typeof previous.wire === 'string' && previous.wire.length > 0 &&
    previous.wire !== previous.level && previous.level !== 'off' && level !== 'off';
  const next: PiAiReasoningEntry = { level: level, wire: carries ? previous.wire : defaultWire(level) };
  return desktopPiAiReasoningModel(model, entries.map((entry: PiAiReasoningEntry, at: number): PiAiReasoningEntry =>
    at === index ? next : entry));
}

export function desktopPiAiChangeReasoningWire(model: PiAiModelRow, index: number, text: string): PiAiModelRow {
  const entries = readPiAiReasoningEntries(model);
  if (entries === undefined || entries[index] === undefined) { return model; }
  const next = entries.map((entry: PiAiReasoningEntry, at: number): PiAiReasoningEntry => at === index ?
    { level: entry.level, wire: text.trim() || defaultWire(entry.level) } : entry);
  return desktopPiAiReasoningModel(model, next);
}
