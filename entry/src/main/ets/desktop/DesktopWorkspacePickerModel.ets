export interface DesktopWorkspacePickerRow {
  id: string;
  title: string;
  path: string;
}

export interface DesktopWorkspacePickerEntry {
  row: DesktopWorkspacePickerRow;
  suffix: string;
}

function trailingPath(parts: string[], count: number): string {
  return parts.slice(-(2 * count - 1)).join('');
}

export function desktopWorkspacePickerEntries(rows: DesktopWorkspacePickerRow[]): DesktopWorkspacePickerEntry[] {
  const separator = new RegExp('([\\\\/])');
  const byTitle = new Map<string, DesktopWorkspacePickerRow[]>();
  for (const row of rows) {
    const peers = byTitle.get(row.title) ?? [];
    peers.push(row);
    byTitle.set(row.title, peers);
  }
  return rows.map((row: DesktopWorkspacePickerRow): DesktopWorkspacePickerEntry => {
    const peers = (byTitle.get(row.title) ?? []).filter((other: DesktopWorkspacePickerRow): boolean =>
      other.id !== row.id).map((other: DesktopWorkspacePickerRow): string[] => other.path.split(separator));
    if (peers.length === 0) { return { row: row, suffix: '' }; }
    const parts = row.path.split(separator);
    let count = 1;
    let suffix = trailingPath(parts, count);
    while (2 * count - 1 < parts.length && (!suffix || peers.some((other: string[]): boolean =>
      trailingPath(other, count) === suffix))) {
      suffix = trailingPath(parts, ++count);
    }
    return { row: row, suffix: suffix };
  });
}

function titleContains(term: string, title: string): boolean {
  let next = 0;
  for (const letter of term) {
    const position = title.indexOf(letter, next);
    if (position < 0) { return false; }
    next = position + 1;
  }
  return true;
}

export function filterDesktopWorkspacePicker(entries: DesktopWorkspacePickerEntry[], query: string):
  DesktopWorkspacePickerEntry[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) { return entries; }
  const terms = normalized.split(new RegExp('\\s+'));
  return entries.filter((entry: DesktopWorkspacePickerEntry): boolean => {
    const title = entry.row.title.toLowerCase();
    const path = entry.row.path.toLowerCase();
    return terms.every((term: string): boolean => path.includes(term) || titleContains(term, title));
  });
}
