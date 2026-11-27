import { getArray, getNumber, getRecord, getString } from 'connection';

export interface DesktopTracePrompt {
  system?: string;
  tools?: Object[];
}

export interface DesktopTracePromptChange {
  current: DesktopTracePrompt;
  previous?: DesktopTracePrompt;
}

/** Replays system-only surface state over the ordered, loaded log window. */
export class DesktopTracePrompts {
  private readonly system: Map<number, string> = new Map();
  private readonly replacements: Map<number, number> = new Map();
  private readonly firstLoaded: number;
  private seenSystem: boolean = false;
  private uncertain: boolean = false;
  private current?: DesktopTracePrompt;

  constructor(firstLoaded: number) { this.firstLoaded = firstLoaded; }

  observe(type: string, sequence: number, data?: Object, op?: Object): DesktopTracePromptChange | undefined {
    const before = this.current;
    if (type === 'request/header') {
      const header = getRecord(data, 'header');
      if (header === undefined) { return undefined; }
      const next: DesktopTracePrompt = { system: before?.system, tools: getArray(header, 'tools') ?? [] };
      return this.save(next);
    }

    const replaced = getString(op, 'op') === 'replace';
    if (!replaced && type !== 'system/message') { return undefined; }
    const position = replaced ? this.replace(sequence, op) : sequence;
    if (type === 'system/message') {
      this.seenSystem = true;
      const blocks = getArray(getRecord(data, 'message'), 'content') ?? [];
      const text = blocks.filter((item: Object): boolean => getString(item, 'type') === 'text')
        .map((item: Object): string => (getString(item, 'text') ?? '').trim())
        .filter((part: string): boolean => part.length > 0).join('\n\n');
      if (!this.uncertain) { this.system.set(position, text); }
    }
    const effective = this.uncertain || !this.seenSystem ? undefined :
      Array.from(this.system.keys()).sort((a: number, b: number): number => a - b)
        .map((at: number): string => this.system.get(at) ?? '').filter((text: string): boolean => text.length > 0).join('\n\n');
    if (type !== 'system/message' && before?.system === effective) { return undefined; }
    return this.save({ system: effective, tools: before?.tools });
  }

  private replace(sequence: number, op?: Object): number {
    const start = getNumber(op, 'startSeq');
    const end = getNumber(op, 'endSeq');
    const first = start === undefined ? undefined : this.replacements.get(start) ?? start;
    const last = end === undefined ? undefined : this.replacements.get(end) ?? end;
    if (first === undefined || last === undefined || first < this.firstLoaded || last < first) {
      this.uncertain = true;
      this.system.clear();
      this.replacements.clear();
      return sequence;
    }
    this.system.forEach((_text: string, position: number): void => {
      if (position >= first && position <= last) { this.system.delete(position); }
    });
    this.replacements.forEach((position: number, key: number): void => {
      if (position >= first && position <= last) { this.replacements.delete(key); }
    });
    this.replacements.set(sequence, first);
    return first;
  }

  private save(next: DesktopTracePrompt): DesktopTracePromptChange {
    const before = this.current;
    this.current = next;
    if (before === undefined) { return { current: next }; }
    const systemChanged = before.system !== undefined && next.system !== undefined && before.system !== next.system;
    const toolsChanged = before.tools !== undefined && next.tools !== undefined &&
      JSON.stringify(before.tools) !== JSON.stringify(next.tools);
    return { current: next, previous: systemChanged || toolsChanged ? before : undefined };
  }
}
