import { invalidPiAiCapacity } from 'appstate';
import type { PiAiModelRow } from 'appstate';
import { getArray } from 'connection';
import { cloneDesktopPiAiModel } from './DesktopPiAiModelFields';

export function desktopDeepSeekModelInput(model: PiAiModelRow): string[] {
  const stored = getArray(model.extraFields, 'inputModalities');
  const selected: string[] = [];
  for (const mode of stored ?? []) {
    if (typeof mode === 'string' && (mode === 'text' || mode === 'image') && !selected.includes(mode)) {
      selected.push(mode);
    }
  }
  return selected.length > 0 ? selected : ['text'];
}

export function desktopDeepSeekEditedInput(model: PiAiModelRow, modality: string, checked: boolean): PiAiModelRow {
  const current = desktopDeepSeekModelInput(model);
  if ((modality !== 'text' && modality !== 'image') || current.includes(modality) === checked) { return model; }
  const selected = ['text', 'image'].filter((mode: string): boolean => mode === modality ? checked : current.includes(mode));
  if (selected.length === 0) { return model; }
  const fields = desktopDeepSeekModelFields(model, selected.includes('image'));
  fields['inputModalities'] = selected;
  const next = cloneDesktopPiAiModel(model);
  next.extraFields = fields;
  return next;
}

function desktopDeepSeekModelFields(model: PiAiModelRow, keepImageLimits: boolean = true): Record<string, Object> {
  const fields: Record<string, Object> = {};
  const existing = model.extraFields;
  if (existing !== undefined) {
    for (const key of Object.keys(existing)) {
      if (keepImageLimits || (key !== 'imagePixelBudget' && key !== 'imageTargetBytes')) {
        fields[key] = existing[key];
      }
    }
  }
  return fields;
}

/** Empty arrays are valid user overrides, and undefined capacities inherit the adapter default. */
export function desktopDeepSeekCatalogProblem(models: PiAiModelRow[]): ResourceStr {
  const ids = new Set<string>();
  for (let index = 0; index < models.length; index++) {
    const model = models[index];
    const row = (index + 1).toString();
    const id = model.id.trim();
    if (id.length === 0) { return $r('app.string.desktop_deepseek_catalog_id_required', row); }
    if (ids.has(id)) { return $r('app.string.desktop_deepseek_catalog_id_duplicate', row); }
    if (invalidPiAiCapacity(model.contextWindow)) { return $r('app.string.desktop_deepseek_catalog_context_invalid', row); }
    if (invalidPiAiCapacity(model.maxTokens)) { return $r('app.string.desktop_deepseek_catalog_output_invalid', row); }
    ids.add(id);
  }
  return '';
}

/** Serialize the catalog as one adapter-owned array, retaining its unexposed fields. */
export function desktopDeepSeekCatalogPayload(models: PiAiModelRow[]): Object[] {
  return models.map((model: PiAiModelRow): Object => {
    const fields = desktopDeepSeekModelFields(model);
    fields['id'] = model.id.trim();
    if (model.name.length > 0) { fields['name'] = model.name; }
    if (model.contextWindow > 0) { fields['contextWindow'] = model.contextWindow; }
    if (model.maxTokens > 0) { fields['maxTokens'] = model.maxTokens; }
    return fields;
  });
}
