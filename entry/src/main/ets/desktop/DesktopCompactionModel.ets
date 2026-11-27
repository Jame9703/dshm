import { getArray, getField, getNumber, getRecord, getString } from 'connection';
import { observeDesktopCommand } from './DesktopCommands';
import type { DesktopCommandRecord } from './DesktopCommands';

export type DesktopCompactionStatus = 'running' | 'interrupted' | 'ended' | 'landed';

export interface DesktopCompactionRow {
  id: string;
  sequence: number;
  turn?: number;
  commandId?: string;
  status: DesktopCompactionStatus;
  error?: string;
  summarySequence?: number;
  shadowedItemCount?: number;
  shadowedTokenCount?: number;
  fallbackSummary?: string;
}

interface CompactionSummary {
  sequence: number;
  shadowedItemCount?: number;
  shadowedTokenCount?: number;
}

interface CompactionEvidence {
  id: string;
  commandId?: string;
  turn?: number;
  started: number;
  ended: number;
  checkpoint: number;
  summary?: CompactionSummary;
  error?: string;
}

function safeSequence(value?: number): boolean {
  return value !== undefined && Number.isSafeInteger(value) && value >= 0;
}

function summaryEvidence(sequence: number, data?: Object): CompactionSummary {
  const shadowed = getArray(data, 'shadowedSeqs');
  const tokens = getNumber(data, 'shadowedTokenCount');
  return {
    sequence: sequence,
    shadowedItemCount: shadowed?.every((value: Object): boolean =>
      typeof value === 'number' && safeSequence(value)) ? shadowed.length : undefined,
    shadowedTokenCount: safeSequence(tokens) ? tokens : undefined
  };
}

/** Read the requested Markdown using the exact log-only summary event from session/events. */
export function readDesktopCompactionSummary(records: Object[], summarySequence: number): string | undefined {
  if (!safeSequence(summarySequence)) { return undefined; }
  const record = records.find((entry: Object): boolean => getNumber(getRecord(entry, 'event'), 'seq') === summarySequence);
  const event = getRecord(record, 'event');
  if (getString(event, 'type') !== 'compaction/summary') { return undefined; }
  const blocks = getArray(getRecord(event, 'data'), 'summary');
  if (blocks === undefined) { return undefined; }
  const chunks: string[] = [];
  for (const block of blocks) {
    const kind = getField(block, 'type');
    if (kind === undefined) { return undefined; }
    if (kind !== 'text') { continue; }
    const text = getString(block, 'text');
    if (text === undefined) { return undefined; }
    chunks.push(text);
  }
  const markdown = chunks.join('');
  return markdown.trim().length > 0 ? markdown : undefined;
}

/** A replacement checkpoint commits a compaction. Lifecycle records alone are progress, even after a restart. */
export class DesktopCompactionTimeline {
  private readonly evidence: Map<string, CompactionEvidence> = new Map<string, CompactionEvidence>();
  private readonly commands: Map<string, DesktopCommandRecord> = new Map<string, DesktopCommandRecord>();
  private readonly compactionCommands: Set<string> = new Set<string>();
  private readonly activeTurns: Set<number> = new Set<number>();
  private readonly closedTurns: Set<number> = new Set<number>();
  private readonly manualCheckpoints: Set<string> = new Set<string>();
  private snapshot: DesktopCompactionRow[] = [];
  private dirty: boolean = false;

  clear(): void {
    this.evidence.clear();
    this.commands.clear();
    this.compactionCommands.clear();
    this.activeTurns.clear();
    this.closedTurns.clear();
    this.manualCheckpoints.clear();
    if (this.snapshot.length > 0) { this.snapshot = []; }
    this.dirty = false;
  }

  observe(record: Object): void {
    const event = getRecord(record, 'event');
    const type = getString(event, 'type');
    const checkpoint = type === 'user/message' && getString(getRecord(event, 'surfaceOp'), 'op') === 'replace';
    if (!checkpoint && type !== 'compaction/start' && type !== 'compaction/summary' && type !== 'compaction/end' &&
        type !== 'command/run' && type !== 'command/done' && type !== 'turn/end') { return; }
    const sequence = getNumber(event, 'seq') ?? -1;
    if (!safeSequence(sequence)) { return; }
    const data = getRecord(event, 'data');
    if (type === 'command/run' || type === 'command/done') {
      this.observeCommand(event, data);
      return;
    }
    const turn = getNumber(data, 'turn');
    if (type === 'turn/end') {
      if (turn !== undefined && safeSequence(turn) && !this.closedTurns.has(turn)) {
        this.closedTurns.add(turn);
        if (this.activeTurns.has(turn)) { this.dirty = true; }
      }
      return;
    }

    const source = checkpoint ? getRecord(data, 'source') : data;
    if (checkpoint && getString(source, 'kind') !== 'compact-checkpoint') { return; }
    const id = getString(source, 'compactionId') ?? '';
    if (!id) { return; }
    const commandId = getString(source, 'sourceCommandId') || undefined;
    const state: CompactionEvidence = this.evidence.get(id) ?? { id: id, started: -1, ended: -1, checkpoint: -1 };
    if (state.commandId !== undefined && commandId !== undefined && state.commandId !== commandId) { return; }
    if (checkpoint) {
      if (state.checkpoint >= sequence) { return; }
      state.checkpoint = sequence;
    } else if (type === 'compaction/start') {
      if (state.started >= 0 && state.started <= sequence) { return; }
      state.started = sequence;
    } else if (type === 'compaction/summary') {
      if ((state.summary?.sequence ?? -1) >= sequence) { return; }
      state.summary = summaryEvidence(sequence, data);
    } else if (type === 'compaction/end') {
      if (state.ended >= sequence) { return; }
      state.ended = sequence;
      state.error = getString(data, 'error');
    }
    if (turn !== undefined && safeSequence(turn) && state.turn === undefined) {
      state.turn = turn;
      this.activeTurns.add(turn);
    }
    if (state.commandId === undefined && commandId !== undefined) {
      state.commandId = commandId;
      this.compactionCommands.add(commandId);
    }
    this.evidence.set(id, state);
    this.dirty = true;
  }

  rows(): DesktopCompactionRow[] {
    if (this.dirty) {
      const rows: DesktopCompactionRow[] = [];
      const manual = new Map<string, DesktopCompactionRow>();
      this.manualCheckpoints.clear();
      this.evidence.forEach((state: CompactionEvidence): void => {
        const row = this.rowOf(state);
        if (row === undefined) { return; }
        if (row.commandId === undefined) { rows.push(row); return; }
        const previous = manual.get(row.commandId);
        const command = this.commands.get(row.commandId);
        const summary = command?.outcome === 'success' ? command.sourceSequence : -1;
        const matches = safeSequence(summary) && summary === row.summarySequence;
        const previousMatches = safeSequence(summary) && summary === previous?.summarySequence;
        if (previous === undefined || (matches && !previousMatches) ||
            (matches === previousMatches && row.sequence > previous.sequence)) {
          manual.set(row.commandId, row);
        }
      });
      manual.forEach((row: DesktopCompactionRow, commandId: string): void => {
        rows.push(row);
        this.manualCheckpoints.add(commandId);
      });
      rows.sort((a: DesktopCompactionRow, b: DesktopCompactionRow): number => a.sequence - b.sequence);
      this.snapshot = rows;
      this.dirty = false;
    }
    return this.snapshot;
  }

  hasManualCheckpoint(commandId: string): boolean {
    this.rows();
    return this.manualCheckpoints.has(commandId);
  }

  private observeCommand(event?: Object, data?: Object): void {
    const id = getString(data, 'commandId') ?? '';
    if (!id) { return; }
    const previous = this.commands.get(id);
    const name = previous?.name;
    const text = previous?.text;
    const outcome = previous?.outcome;
    const source = previous?.sourceSequence;
    observeDesktopCommand(this.commands, event);
    const next = this.commands.get(id);
    if (this.compactionCommands.has(id) && (name !== next?.name || text !== next?.text ||
        outcome !== next?.outcome || source !== next?.sourceSequence)) { this.dirty = true; }
  }

  private rowOf(state: CompactionEvidence): DesktopCompactionRow | undefined {
    const commandId = state.commandId;
    const id = commandId === undefined ? `compaction:${state.id}` : `compaction-command:${commandId}`;
    if (state.checkpoint >= 0) {
      const command = commandId === undefined ? undefined : this.commands.get(commandId);
      if (command?.name && command.name !== 'compact') { return undefined; }
      return {
        id: id, sequence: state.checkpoint, turn: state.turn, commandId: commandId, status: 'landed',
        summarySequence: state.summary?.sequence, shadowedItemCount: state.summary?.shadowedItemCount,
        shadowedTokenCount: state.summary?.shadowedTokenCount, fallbackSummary: command?.text
      };
    }
    if (commandId !== undefined) { return undefined; }
    const sequence = state.started >= 0 ? state.started : state.ended;
    if (sequence < 0) { return undefined; }
    const interrupted = state.turn !== undefined && this.closedTurns.has(state.turn);
    const status: DesktopCompactionStatus = state.ended >= 0 ? 'ended' : interrupted ? 'interrupted' : 'running';
    return { id: id, sequence: sequence, turn: state.turn, status: status, error: state.error };
  }
}
