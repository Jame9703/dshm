import { projectDefaultSelection, projectModelCatalog } from 'appstate';
import type { ModelOption, ModelSelection } from 'appstate';
import { getArray, getString } from 'connection';

export interface DesktopModelGroup {
  id: string;
  name: string;
  models: ModelOption[];
}

export interface DesktopModelFailure {
  id: string;
  name: string;
  message: string;
}

export interface DesktopModelCatalog {
  models: ModelOption[];
  groups: DesktopModelGroup[];
  byProvider: Map<string, Map<string, ModelOption>>;
  failures: DesktopModelFailure[];
  defaultModel?: ModelSelection;
}

export interface DesktopModelCatalogResult {
  catalog?: DesktopModelCatalog;
  problem: string;
}

function providerOrder(id: string): number {
  return id === 'deepseek-account' ? 0 : id === 'deepseek-official' ? 1 : 2;
}

export function desktopModelCatalog(value: Object | undefined): DesktopModelCatalog {
  const groupsById = new Map<string, DesktopModelGroup>();
  const byProvider = new Map<string, Map<string, ModelOption>>();
  for (const model of projectModelCatalog(value)) {
    let group = groupsById.get(model.provider);
    if (group === undefined) {
      group = { id: model.provider, name: model.providerName, models: [] };
      groupsById.set(group.id, group);
    }
    group.models.push(model);
    let choices = byProvider.get(model.provider);
    if (choices === undefined) {
      choices = new Map<string, ModelOption>();
      byProvider.set(model.provider, choices);
    }
    if (!choices.has(model.modelId)) { choices.set(model.modelId, model); }
  }
  const groups = Array.from(groupsById.values()).sort((a: DesktopModelGroup, b: DesktopModelGroup): number =>
    providerOrder(a.id) - providerOrder(b.id));
  const failures: DesktopModelFailure[] = [];
  for (const item of getArray(value, 'failures') ?? []) {
    const id = getString(item, 'id') ?? '';
    const message = getString(item, 'message') ?? '';
    if (id && message) { failures.push({ id: id, name: getString(item, 'name') || id, message: message }); }
  }
  return { models: groups.flatMap((group: DesktopModelGroup): ModelOption[] => group.models), groups: groups,
    byProvider: byProvider,
    failures: failures, defaultModel: projectDefaultSelection(value) };
}

export function desktopModelMatches(choice: ModelOption, selection?: ModelSelection): boolean {
  return choice.provider === selection?.provider && choice.modelId === selection?.modelId;
}

export function desktopModelEffort(choice: ModelOption, effort: string): string {
  return choice.effortLabels?.[choice.efforts.indexOf(effort)] || effort;
}

function fold(text: string): string {
  return text.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

function nameScore(name: string, query: string): number {
  if (name.startsWith(query)) { return 0; }
  const position = name.indexOf(query);
  if (position >= 0) { return 1 + position; }
  let first = -1;
  let last = -1;
  for (const letter of query) {
    last = name.indexOf(letter, last + 1);
    if (last < 0) { return Number.POSITIVE_INFINITY; }
    if (first < 0) { first = last; }
  }
  return 129 + first + last - query.length;
}

interface ScoredModel {
  row: ModelOption;
  score: number;
}

export function desktopFilterModelGroups(groups: DesktopModelGroup[], query: string): DesktopModelGroup[] {
  const terms = fold(query.trim()).split(/\s+/).filter((term: string): boolean => term.length > 0);
  if (terms.length === 0) { return groups; }
  const matches: DesktopModelGroup[] = [];
  for (const group of groups) {
    const rows: ScoredModel[] = [];
    for (const row of group.models) {
      const name = fold(row.modelName);
      const id = fold(row.modelId);
      const description = fold(row.description);
      let score = 0;
      for (const term of terms) {
        score += Math.min(nameScore(name, term), nameScore(id, term),
          description.includes(term) ? 256 : Number.POSITIVE_INFINITY);
      }
      if (Number.isFinite(score)) { rows.push({ row: row, score: score }); }
    }
    if (rows.length > 0) {
      rows.sort((a: ScoredModel, b: ScoredModel): number => a.score - b.score);
      matches.push({ id: group.id, name: group.name, models: rows.map((entry: ScoredModel): ModelOption => entry.row) });
    }
  }
  return matches;
}
