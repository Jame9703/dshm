import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { getArray, getBoolean, getNumber, getRecord, getString, isStringArray, parseJson, toStringArray } from 'connection';

export interface DesktopQuestionDraft {
  id: string;
  selected: string[];
  custom: string;
  skipped: boolean;
}

export interface DesktopQuestionProgress {
  index: number;
  drafts: DesktopQuestionDraft[];
}

export interface SavedDesktopQuestion {
  key: string;
  progress?: DesktopQuestionProgress;
  held: boolean;
}

function readProgress(raw: Object | undefined): DesktopQuestionProgress | undefined {
  const index = getNumber(raw, 'index');
  const entries = getArray(raw, 'drafts');
  if (index === undefined || entries === undefined || !Number.isInteger(index) || index < 0 ||
    index >= entries.length) { return undefined; }
  const drafts: DesktopQuestionDraft[] = [];
  for (const entry of entries) {
    const id = getString(entry, 'id');
    const selected = getArray(entry, 'selected');
    const custom = getString(entry, 'custom');
    const skipped = getBoolean(entry, 'skipped');
    if (!id || selected === undefined || !isStringArray(selected) || custom === undefined || skipped === undefined) {
      return undefined;
    }
    drafts.push({ id: id, selected: toStringArray(selected), custom: custom, skipped: skipped });
  }
  return { index: index, drafts: drafts };
}

export class DesktopQuestionDrafts {
  private readonly path: string;
  private entries?: Map<string, SavedDesktopQuestion>;
  private timer: number = -1;
  private writing: boolean = false;
  private dirty: boolean = false;

  constructor(filesDir: string) { this.path = filesDir + '/desktop-question-drafts-v1.json'; }

  get(key: string): SavedDesktopQuestion | undefined { return this.load().get(key); }

  put(entry: SavedDesktopQuestion): void {
    this.load().set(entry.key, entry);
    this.scheduleWrite();
  }

  remove(key: string): void {
    if (this.load().delete(key)) { this.scheduleWrite(); }
  }

  private load(): Map<string, SavedDesktopQuestion> {
    if (this.entries !== undefined) { return this.entries; }
    const entries = new Map<string, SavedDesktopQuestion>();
    this.entries = entries;
    try {
      const saved = parseJson(fileIo.readTextSync(this.path));
      for (const raw of getArray(saved, 'entries') ?? []) {
        const key = getString(raw, 'key');
        const progress = readProgress(getRecord(raw, 'progress'));
        const held = getBoolean(raw, 'held') === true;
        if (key && (progress !== undefined || held)) {
          entries.set(key, { key: key, progress: progress, held: held });
        }
      }
    } catch (_) { /* This installation has no readable draft snapshot yet. */ }
    return entries;
  }

  private scheduleWrite(): void {
    this.dirty = true;
    if (this.writing || this.timer !== -1) { return; }
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.write();
    }, 150);
  }

  private async write(): Promise<void> {
    this.dirty = false;
    this.writing = true;
    const temp = this.path + '.tmp';
    try {
      const snapshot: Record<string, Object> = { 'entries': Array.from(this.load().values()) };
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(snapshot));
      const file = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        if (await fileIo.write(file.fd, bytes.buffer) !== bytes.byteLength) { return; }
      } finally {
        await fileIo.close(file);
      }
      await fileIo.rename(temp, this.path);
    } catch (_) { /* Keep the previous snapshot and the current in-memory drafts. */ }
    finally {
      this.writing = false;
      if (this.dirty) { this.scheduleWrite(); }
    }
  }
}

let desktopQuestionDrafts: DesktopQuestionDrafts | undefined;

export function localDesktopQuestionDrafts(filesDir?: string): DesktopQuestionDrafts | undefined {
  if (!filesDir) { return undefined; }
  const store = desktopQuestionDrafts ?? new DesktopQuestionDrafts(filesDir);
  desktopQuestionDrafts = store;
  return store;
}
