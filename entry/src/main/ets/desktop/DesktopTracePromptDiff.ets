import { diffLines, DiffLineKind } from 'appstate';
import type { DiffLine } from 'appstate';
import type { DesktopTracePromptChange } from './DesktopTracePrompts';

export interface DesktopPromptHunk {
  header: string;
  lines: DiffLine[];
}

export interface DesktopPromptDiffSection {
  id: string;
  hunks: DesktopPromptHunk[];
}

interface LineRange {
  start: number;
  end: number;
}

function hunks(before: string, after: string): DesktopPromptHunk[] {
  const lines = diffLines(before.length > 0 ? before : null, after);
  const ranges: LineRange[] = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].kind === DiffLineKind.CONTEXT) { continue; }
    const start = Math.max(0, i - 3);
    const end = Math.min(lines.length, i + 4);
    const last = ranges[ranges.length - 1];
    if (last !== undefined && start <= last.end) { last.end = end; }
    else { ranges.push({ start: start, end: end }); }
  }
  const result: DesktopPromptHunk[] = [];
  let index = 0;
  let oldLine = 1;
  let newLine = 1;
  for (const range of ranges) {
    while (index < range.start) {
      if (lines[index].kind !== DiffLineKind.ADDED) { oldLine++; }
      if (lines[index].kind !== DiffLineKind.REMOVED) { newLine++; }
      index++;
    }
    const oldStart = oldLine;
    const newStart = newLine;
    while (index < range.end) {
      if (lines[index].kind !== DiffLineKind.ADDED) { oldLine++; }
      if (lines[index].kind !== DiffLineKind.REMOVED) { newLine++; }
      index++;
    }
    const oldCount = oldLine - oldStart;
    const newCount = newLine - newStart;
    result.push({
      header: `@@ -${oldCount === 0 ? oldStart - 1 : oldStart},${oldCount} +${newCount === 0 ? newStart - 1 : newStart},${newCount} @@`,
      lines: lines.slice(range.start, range.end)
    });
  }
  return result;
}

export function desktopTracePromptDiff(change?: DesktopTracePromptChange): DesktopPromptDiffSection[] {
  const before = change?.previous;
  const after = change?.current;
  if (before === undefined || after === undefined) { return []; }
  const result: DesktopPromptDiffSection[] = [];
  if (before.system !== undefined && after.system !== undefined && before.system !== after.system) {
    result.push({ id: 'system', hunks: hunks(before.system, after.system) });
  }
  if (before.tools !== undefined && after.tools !== undefined) {
    const from = JSON.stringify(before.tools, undefined, 2) ?? '';
    const to = JSON.stringify(after.tools, undefined, 2) ?? '';
    if (from !== to) { result.push({ id: 'tools', hunks: hunks(from, to) }); }
  }
  return result;
}
