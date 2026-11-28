import type { PiAiModelRow } from 'appstate';
import { getArray } from 'connection';

export type DesktopPiAiCapacityField = 'contextWindow' | 'maxTokens';

const CAPACITY: RegExp = new RegExp('^(\\d+(?:\\.\\d+)?)([km])?$', 'i');

export function parseDesktopPiAiCapacity(text: string): number {
  const trimmed = text.trim();
  if (!trimmed) { return 0; }
  const match = CAPACITY.exec(trimmed);
  if (match === null) { return Number.NaN; }
  const suffix = match[2]?.toLowerCase();
  const scale = suffix === 'k' ? 1000 : suffix === 'm' ? 1000000 : 1;
  const count = Number(match[1]) * scale;
  const rounded = Math.round(count);
  const value = Math.abs(count - rounded) < 1e-6 ? rounded : count;
  return value > 0 ? value : Number.NaN;
}

export function formatDesktopPiAiCapacity(count: number): string {
  if (count === 0) { return ''; }
  if (!Number.isInteger(count) || count < 0) { return String(count); }
  if (count % 1000000 === 0) { return (count / 1000000).toString() + 'M'; }
  if (count % 1000 === 0) { return (count / 1000).toString() + 'K'; }
  return count.toString();
}

export function desktopPiAiCapacityText(model: PiAiModelRow, field: DesktopPiAiCapacityField): string {
  const text = field === 'contextWindow' ? model.contextWindowText : model.maxTokensText;
  const count = field === 'contextWindow' ? model.contextWindow : model.maxTokens;
  return text ?? formatDesktopPiAiCapacity(count);
}

export function cloneDesktopPiAiModel(model: PiAiModelRow): PiAiModelRow {
  return { id: model.id, name: model.name, contextWindow: model.contextWindow, maxTokens: model.maxTokens,
    contextWindowText: model.contextWindowText, maxTokensText: model.maxTokensText, extraFields: model.extraFields };
}

export function desktopPiAiEditedCapacity(model: PiAiModelRow, field: DesktopPiAiCapacityField, text: string): PiAiModelRow {
  const next = cloneDesktopPiAiModel(model);
  const count = parseDesktopPiAiCapacity(text);
  if (field === 'contextWindow') { next.contextWindow = count; next.contextWindowText = text; }
  else { next.maxTokens = count; next.maxTokensText = text; }
  return next;
}

export function desktopPiAiInputModes(model: PiAiModelRow, inherited?: string[]): string[] {
  const stored = getArray(model.extraFields, 'input');
  const selected: string[] = [];
  for (const mode of stored ?? []) {
    if (typeof mode === 'string' && (mode === 'text' || mode === 'image') && !selected.includes(mode)) {
      selected.push(mode);
    }
  }
  return selected.length > 0 ? selected : (inherited !== undefined && inherited.length > 0 ? inherited : ['text']);
}

export function desktopPiAiEditedInput(model: PiAiModelRow, inherited: string[] | undefined, modality: string,
  checked: boolean): PiAiModelRow {
  const selected = desktopPiAiInputModes(model, inherited);
  const input = ['text', 'image'].filter((mode: string): boolean => mode === modality ? checked : selected.includes(mode));
  if (input.length === 0 || (modality !== 'text' && modality !== 'image') || selected.includes(modality) === checked) {
    return model;
  }
  const fields: Record<string, Object> = {};
  const existing = model.extraFields;
  if (existing !== undefined) {
    for (const key of Object.keys(existing)) { fields[key] = existing[key]; }
  }
  fields['input'] = input;
  const next = cloneDesktopPiAiModel(model);
  next.extraFields = fields;
  return next;
}
