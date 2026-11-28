import { getArray, getBoolean, getString } from 'connection';

export interface DesktopSkill {
  name: string;
  description: string;
  path?: string;
  modelInvocable: boolean;
}

export interface DesktopSkillReference {
  name: string;
  start: number;
  end: number;
  path?: string;
}

export function readDesktopSkills(value?: Object): DesktopSkill[] | undefined {
  const values = getArray(value, 'skills');
  if (values === undefined) { return undefined; }
  const skills: DesktopSkill[] = [];
  const seen = new Set<string>();
  for (const row of values) {
    const name = getString(row, 'name') ?? '';
    if (!name || seen.has(name)) { continue; }
    seen.add(name);
    skills.push({ name: name, description: getString(row, 'description') ?? '',
      path: getString(row, 'path'), modelInvocable: getBoolean(row, 'modelInvocable') === true });
  }
  return skills;
}

function normalizeSkillSearch(value: string): string {
  return value.normalize('NFKD').replace(new RegExp('[\\u0300-\\u036f]', 'g'), '')
    .normalize('NFKC');
}

function skillNameScore(name: string, term: string): number {
  const normalized = normalizeSkillSearch(name);
  const folded = normalized.toLowerCase();
  if (folded.startsWith(term)) { return 3; }
  if (folded.includes(term)) { return 2; }
  const boundary = new RegExp('[^\\p{L}\\p{N}]', 'u');
  for (let start = 0; start < folded.length; start++) {
    if (folded[start] !== term[0] || (start > 0 && !boundary.test(folded[start - 1]) &&
      !(normalized.charAt(start) !== folded.charAt(start) && normalized.charAt(start - 1) === folded.charAt(start - 1)))) {
      continue;
    }
    let at = start;
    for (let index = 1; index < term.length && at >= 0; index++) {
      at = folded.indexOf(term[index], at + 1);
    }
    if (at >= 0) { return 1; }
  }
  return 0;
}

interface ScoredSkill {
  skill: DesktopSkill;
  score: number;
}

export function desktopSkillCandidates(skills: DesktopSkill[], query: string): DesktopSkill[] {
  const needle = normalizeSkillSearch(query).toLowerCase().trim();
  if (!needle) { return skills; }
  const terms = needle.split(new RegExp('\\s+'));
  const matches: ScoredSkill[] = [];
  for (const skill of skills) {
    const scores = terms.map((term: string): number => skillNameScore(skill.name, term));
    if (scores.every((score: number): boolean => score > 0)) {
      matches.push({ skill: skill, score: scores.reduce((total: number, score: number): number => total + score, 0) });
    }
  }
  return matches.sort((left: ScoredSkill, right: ScoredSkill): number => right.score - left.score)
    .map((match: ScoredSkill): DesktopSkill => match.skill);
}

export function desktopMayHaveSkillReference(value: string): boolean {
  return new RegExp('(?<!\\S)/[\\w-]+(?!\\S)', 'u').test(value);
}

export function desktopSkillReferences(value: string, skills: DesktopSkill[]): DesktopSkillReference[] {
  if (skills.length === 0) { return []; }
  const byName = new Map<string, DesktopSkill>();
  for (const skill of skills) { byName.set(skill.name, skill); }
  const tokens = new RegExp('(?<!\\S)/([\\w-]+)(?!\\S)', 'gu');
  const references: DesktopSkillReference[] = [];
  let token = tokens.exec(value);
  while (token !== null) {
    const skill = byName.get(token[1]);
    if (skill !== undefined) {
      references.push({ name: skill.name, start: token.index, end: token.index + token[0].length, path: skill.path });
    }
    token = tokens.exec(value);
  }
  return references;
}
