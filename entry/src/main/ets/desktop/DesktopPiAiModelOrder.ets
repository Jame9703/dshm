import type { PiAiModelRow } from 'appstate';

export interface DesktopPiAiModelBand {
  key: number;
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface DesktopPiAiModelInsertion {
  key: number;
  after: boolean;
}

/** Remove the source before inserting on the indicated side of the target. */
export function desktopPiAiModelInsertionIndex(keys: number[], source: number, target: number, after: boolean): number {
  const from = keys.indexOf(source);
  const to = keys.indexOf(target);
  if (from < 0 || to < 0 || from === to) { return -1; }
  const gap = to + (after ? 1 : 0);
  const insertion = gap > from ? gap - 1 : gap;
  return insertion === from ? -1 : insertion;
}

export function desktopPiAiModelDrop(bands: DesktopPiAiModelBand[], x: number, y: number,
  source: number): DesktopPiAiModelInsertion | undefined {
  for (const band of bands) {
    if (band.key !== source && x >= band.left && x < band.left + band.width &&
      y >= band.top && y < band.top + band.height) {
      return { key: band.key, after: y >= band.top + band.height / 2 };
    }
  }
  return undefined;
}

/** Keep the identities of models retained by discovery, including repeated draft IDs. */
export function desktopPiAiAdoptedKeys(oldRows: PiAiModelRow[], oldKeys: number[], rows: PiAiModelRow[],
  newKey: () => number): number[] {
  const used = new Set<number>();
  return rows.map((row: PiAiModelRow): number => {
    const index = oldRows.findIndex((old: PiAiModelRow, position: number): boolean =>
      row.id === old.id && position < oldKeys.length && !used.has(position));
    if (index < 0) { return newKey(); }
    used.add(index);
    return oldKeys[index];
  });
}
