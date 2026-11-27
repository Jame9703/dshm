import { getArray, getBoolean, getString } from 'connection';

export interface DesktopFileNameSpan {
  text: string;
  highlight: boolean;
}

export interface DesktopFileSearchNode {
  path: string;
  name: string;
  directory: boolean;
  spans: DesktopFileNameSpan[];
  children: DesktopFileSearchNode[];
}

export interface DesktopFileSearchResults {
  nodes: DesktopFileSearchNode[];
  count: number;
  truncated: boolean;
  incomplete: boolean;
}

export function desktopWorkspaceRelativePath(path: string): boolean {
  return path.length > 0 && !path.includes('\x00') && !path.includes('\\') && !path.startsWith('/') &&
    !new RegExp('^[A-Za-z]:').test(path) &&
    path.split('/').every((part: string): boolean => part !== '' && part !== '.' && part !== '..');
}

function splitName(name: string, pattern: RegExp): DesktopFileNameSpan[] {
  const parts: DesktopFileNameSpan[] = [];
  let previous = 0;
  pattern.lastIndex = 0;
  let match = pattern.exec(name);
  while (match !== null) {
    if (match.index > previous) { parts.push({ text: name.slice(previous, match.index), highlight: false }); }
    parts.push({ text: match[0], highlight: true });
    previous = match.index + match[0].length;
    match = pattern.exec(name);
  }
  if (previous < name.length) { parts.push({ text: name.slice(previous), highlight: false }); }
  return parts;
}

/** Build the result tree once per host reply. Its ancestors have no independent listing or watcher. */
export function desktopFileSearchResults(value: Object | undefined, query: string): DesktopFileSearchResults {
  const escaped = query.replace(new RegExp('[.*+?^\x24{}()|\\[\\]\\\\]', 'g'), '\\$&');
  const pattern = new RegExp(escaped || '(?!)', 'giu');
  const roots: DesktopFileSearchNode[] = [];
  const branches: DesktopFileSearchNode[][] = [roots];
  const nodes = new Map<string, DesktopFileSearchNode>();
  const matches = new Set<string>();
  for (const row of getArray(value, 'matches') ?? []) {
    const path = getString(row, 'path') ?? '';
    if (!desktopWorkspaceRelativePath(path)) { continue; }
    matches.add(path);
    const segments = path.split('/');
    let branch = roots;
    let prefix = '';
    for (let depth = 0; depth < segments.length; depth++) {
      const name = segments[depth];
      prefix = depth === 0 ? name : prefix + '/' + name;
      const directory = depth < segments.length - 1 || getString(row, 'type') === 'directory';
      let node = nodes.get(prefix);
      if (node === undefined) {
        node = { path: prefix, name: name, directory: directory, spans: splitName(name, pattern), children: [] };
        nodes.set(prefix, node);
        branch.push(node);
        branches.push(node.children);
      } else if (directory) {
        node.directory = true;
      }
      branch = node.children;
    }
  }
  for (const branch of branches) {
    branch.sort((left: DesktopFileSearchNode, right: DesktopFileSearchNode): number =>
      left.directory === right.directory ? left.name.localeCompare(right.name, undefined, { numeric: true, sensitivity: 'base' }) :
        left.directory ? -1 : 1);
  }
  return { nodes: roots, count: matches.size, truncated: getBoolean(value, 'truncated') === true,
    incomplete: getBoolean(value, 'incomplete') === true };
}
