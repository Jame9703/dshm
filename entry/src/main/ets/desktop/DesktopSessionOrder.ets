import type { SessionListItem } from 'appstate';

export enum DesktopSessionGrouping {
  WORKSPACE = 'workspace',
  TREE = 'workspace-tree',
  FLAT = 'flat'
}

export enum DesktopSessionOrdering {
  UPDATED = 'updated',
  MANUAL = 'manual'
}

export interface DesktopWorkspaceGroup {
  id: string;
  path: string;
  title: ResourceStr;
  sessions: SessionListItem[];
}

export interface DesktopSidebarSection {
  group: DesktopWorkspaceGroup;
  depth: number;
  header: boolean;
}

export interface DesktopSessionInsertion {
  id: string;
  after: boolean;
}

export function desktopSessionAccount(grouping: DesktopSessionGrouping, workspaceId: string): string {
  return grouping === DesktopSessionGrouping.FLAT ? 'flat' : 'workspace:' + workspaceId;
}

function compareRecency(a: SessionListItem, b: SessionListItem): number {
  return b.updatedAt - a.updatedAt || (a.id < b.id ? -1 : Number(a.id !== b.id));
}

export function desktopSessionOrder(sessions: SessionListItem[], saved: string[] | undefined, pinned: string[],
  archived: Set<string>, currentId: string): SessionListItem[] {
  const recent = sessions.slice().sort(compareRecency);
  let base = recent;
  if (saved !== undefined) {
    const members = new Map<string, SessionListItem>();
    recent.forEach((item: SessionListItem): void => { members.set(item.id, item); });
    base = [];
    const append = (id: string): void => {
      const member = members.get(id);
      if (member !== undefined) {
        base.push(member);
        members.delete(id);
      }
    };
    const known = new Set<string>(saved);
    for (const id of pinned) {
      if (!archived.has(id) && !known.has(id)) { append(id); }
    }
    saved.forEach(append);
    recent.forEach((item: SessionListItem): void => { if (!archived.has(item.id)) { append(item.id); } });
    recent.forEach((item: SessionListItem): void => { append(item.id); });
  }
  const current = base.find((item: SessionListItem): boolean => item.blank && item.id === currentId);
  return current === undefined ? base : [current].concat(base.filter((item: SessionListItem): boolean => item.id !== currentId));
}

export function desktopSessionRows(sessions: SessionListItem[], saved: string[] | undefined, pinned: string[],
  archived: Set<string>, currentId: string): SessionListItem[] {
  const base = desktopSessionOrder(sessions, saved, pinned, archived, currentId);
  const pins = new Set<string>(pinned);
  const placeholders: SessionListItem[] = [];
  const leading: SessionListItem[] = [];
  const other: SessionListItem[] = [];
  for (const item of base) {
    if (item.blank && item.id === currentId) { placeholders.push(item); }
    else if (pins.has(item.id) && !archived.has(item.id)) { leading.push(item); }
    else { other.push(item); }
  }
  return placeholders.concat(leading, other);
}

export function desktopReorderSessions(order: SessionListItem[], visible: SessionListItem[], sourceId: string,
  target: DesktopSessionInsertion, pinned: Set<string>, archived: Set<string>): string[] | undefined {
  const source = visible.find((item: SessionListItem): boolean => item.id === sourceId);
  const anchor = visible.find((item: SessionListItem): boolean => item.id === target.id);
  if (source === undefined || anchor === undefined || source.id === anchor.id || source.blank || archived.has(source.id)) {
    return undefined;
  }
  const sourcePinned = pinned.has(source.id);
  const section = visible.filter((item: SessionListItem): boolean => (pinned.has(item.id) && !archived.has(item.id)) === sourcePinned);
  const sourceIndex = section.indexOf(source);
  const anchorIndex = section.indexOf(anchor);
  if (anchorIndex < 0) { return undefined; }
  const after = anchor.blank || target.after;
  const visiblePosition = anchorIndex + Number(after) - Number(sourceIndex < anchorIndex);
  if (visiblePosition === sourceIndex) { return undefined; }
  const next = order.map((item: SessionListItem): string => item.id);
  const from = next.indexOf(source.id);
  if (from < 0) { return undefined; }
  next.splice(from, 1);
  const to = next.indexOf(anchor.id);
  if (to < 0) { return undefined; }
  next.splice(to + Number(after), 0, source.id);
  return next;
}

export function desktopSessionOrdersEqual(a: Map<string, string[]>, b: Map<string, string[]>): boolean {
  if (a.size !== b.size) { return false; }
  for (const key of a.keys()) {
    const first = a.get(key);
    const second = b.get(key);
    if (first === undefined || second === undefined || first.length !== second.length ||
      first.some((id: string, index: number): boolean => id !== second[index])) { return false; }
  }
  return true;
}

function workspaceFolder(path: string): string {
  const separator = '\\';
  const windows = (path.charAt(1) === ':' && (path.charAt(2) === separator || path.charAt(2) === '/')) ||
    path.startsWith(separator + separator);
  return (windows ? path.split(separator).join('/') : path).replace(new RegExp('/+$'), '');
}

function appendWorkspaceSections(out: DesktopSidebarSection[], groups: DesktopWorkspaceGroup[],
  children: Map<string, DesktopWorkspaceGroup[]>, expanded: Set<string>, depth: number): void {
  for (const group of groups) {
    out.push({ group: group, depth: depth, header: true });
    if (!expanded.has(group.id)) { continue; }
    const nested = children.get(group.id);
    if (nested !== undefined) { appendWorkspaceSections(out, nested, children, expanded, depth + 1); }
    if (group.sessions.length > 0) { out.push({ group: group, depth: depth, header: false }); }
  }
}

export function desktopWorkspaceParents(groups: DesktopWorkspaceGroup[]): Map<string, string> {
  const folders = new Map<string, string>();
  for (const group of groups) {
    if (group.path.length > 0) { folders.set(group.id, workspaceFolder(group.path)); }
  }
  const owners = new Map<string, string>();
  folders.forEach((path: string, child: string): void => {
    let length = -1;
    folders.forEach((folder: string, id: string): void => {
      if (folder.length > length && folder !== path && path.startsWith(folder + '/')) {
        owners.set(child, id);
        length = folder.length;
      }
    });
  });
  return owners;
}

export function desktopSidebarSections(groups: DesktopWorkspaceGroup[], grouping: DesktopSessionGrouping,
  expandedIds: string[], searching: boolean): DesktopSidebarSection[] {
  if (grouping === DesktopSessionGrouping.FLAT) {
    return groups.map((group: DesktopWorkspaceGroup): DesktopSidebarSection => ({ group: group, depth: 0, header: false }));
  }
  const owners = grouping === DesktopSessionGrouping.TREE ? desktopWorkspaceParents(groups) : new Map<string, string>();
  const roots: DesktopWorkspaceGroup[] = [];
  const children = new Map<string, DesktopWorkspaceGroup[]>();
  for (const group of groups) {
    const owner = owners.get(group.id);
    if (owner === undefined) {
      roots.push(group);
    } else {
      const siblings = children.get(owner) ?? [];
      siblings.push(group);
      children.set(owner, siblings);
    }
  }
  const out: DesktopSidebarSection[] = [];
  const expanded = new Set<string>(searching ? groups.map((group: DesktopWorkspaceGroup): string => group.id) : expandedIds);
  appendWorkspaceSections(out, roots, children, expanded, 0);
  return out;
}
