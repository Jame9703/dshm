import type { DesktopTranscriptRow } from './DesktopTranscriptPresentation';

export interface DesktopTranscriptListItem {
  key: string;
  row: DesktopTranscriptRow;
}

/** The List retains visible nodes when history is prepended or the live tail grows. */
export class DesktopTranscriptListSource implements IDataSource {
  private items: DesktopTranscriptListItem[] = [];
  private readonly listeners = new Set<DataChangeListener>();

  totalCount(): number { return this.items.length; }
  getData(index: number): DesktopTranscriptListItem { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.add(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners.delete(listener); }

  replace(items: DesktopTranscriptListItem[], reset: boolean): void {
    const previous = this.items;
    this.items = items;
    if (previous.length === 0 && items.length === 0) { return; }
    if (reset) { this.notify([{ type: DataOperationType.RELOAD }]); return; }

    let first = 0;
    let oldEnd = previous.length;
    let newEnd = items.length;
    while (first < oldEnd && first < newEnd && previous[first].key === items[first].key) { first++; }
    while (oldEnd > first && newEnd > first && previous[oldEnd - 1].key === items[newEnd - 1].key) {
      oldEnd--;
      newEnd--;
    }
    const removed = oldEnd - first;
    const inserted = newEnd - first;
    if (removed === 0 && inserted === 0) { return; }
    if (removed === 0) {
      this.notify([{ type: DataOperationType.ADD, index: first, count: inserted }]);
    } else if (inserted === 0) {
      this.notify([{ type: DataOperationType.DELETE, index: first, count: removed }]);
    } else if (inserted === removed && inserted <= 32) {
      const operations: DataOperation[] = [];
      const previousKeys = new Set<string>();
      for (let index = first; index < oldEnd; index++) { previousKeys.add(previous[index].key); }
      for (let index = first; index < newEnd; index++) {
        if (previous[index].key !== items[index].key) {
          if (previousKeys.has(items[index].key)) { this.notify([{ type: DataOperationType.RELOAD }]); return; }
          operations.push({ type: DataOperationType.CHANGE, index: index, key: items[index].key });
        }
      }
      this.notify(operations);
    } else {
      this.notify([{ type: DataOperationType.RELOAD }]);
    }
  }

  private notify(operations: DataOperation[]): void {
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDatasetChange(operations); });
  }
}
