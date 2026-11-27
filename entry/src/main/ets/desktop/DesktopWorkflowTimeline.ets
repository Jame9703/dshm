import { getNumber, getRecord, getString } from 'connection';

export enum DesktopWorkflowStatus {
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
  INTERRUPTED = 'interrupted'
}

export interface DesktopWorkflowMember {
  sequence: number;
  label: string;
  childId: string;
  status: DesktopWorkflowStatus;
}

export interface DesktopWorkflowPhase {
  key: string;
  label?: string;
  members: DesktopWorkflowMember[];
}

export interface DesktopWorkflowView {
  name: string;
  status: DesktopWorkflowStatus;
  phases: DesktopWorkflowPhase[];
  memberCount: number;
}

export class DesktopWorkflowRun {
  id: string;
  sequence: number;
  view: DesktopWorkflowView;

  constructor(id: string, sequence: number, view: DesktopWorkflowView) {
    this.id = id;
    this.sequence = sequence;
    this.view = view;
  }
}

interface RecordedMember {
  eventSequence: number;
  label: string;
  phase?: string;
  childId: string;
}

interface WorkflowOutcome {
  sequence: number;
  status: DesktopWorkflowStatus;
}

class RecordedWorkflow {
  start: number = -1;
  name: string = '';
  end?: WorkflowOutcome;
  members: Map<number, RecordedMember> = new Map();
  outcomes: Map<number, WorkflowOutcome> = new Map();
}

interface TurnBoundary {
  sequence: number;
  start: boolean;
  interrupted: boolean;
}

function terminalStatus(value?: string): DesktopWorkflowStatus | undefined {
  if (value === 'completed') { return DesktopWorkflowStatus.COMPLETED; }
  if (value === 'cancelled') { return DesktopWorkflowStatus.CANCELLED; }
  if (value === 'error' || value === 'failed') { return DesktopWorkflowStatus.FAILED; }
  return undefined;
}

export function desktopWorkflowAbnormal(status: DesktopWorkflowStatus): boolean {
  return status !== DesktopWorkflowStatus.RUNNING && status !== DesktopWorkflowStatus.COMPLETED;
}

export class DesktopWorkflowTimeline {
  private readonly workflows: Map<string, RecordedWorkflow> = new Map();
  private readonly rows: Map<string, DesktopWorkflowRun> = new Map();
  private readonly turns: Map<number, TurnBoundary> = new Map();
  private boundaries: TurnBoundary[] = [];
  private readonly changed: Set<string> = new Set<string>();
  private turnsChanged: boolean = false;

  clear(): void {
    this.workflows.clear();
    this.rows.clear();
    this.turns.clear();
    this.boundaries = [];
    this.changed.clear();
    this.turnsChanged = false;
  }

  observe(event?: Object): void {
    const type = getString(event, 'type');
    if (type === undefined || (type !== 'turn/start' && type !== 'turn/end' && !type.startsWith('tool-workflow/'))) {
      return;
    }
    const sequence = getNumber(event, 'seq') ?? -1;
    if (sequence < 0) { return; }
    const data = getRecord(event, 'data');
    if (type === 'turn/start' || type === 'turn/end') {
      if (!this.turns.has(sequence)) {
        const reason = getString(getRecord(data, 'reason'), 'kind');
        this.turns.set(sequence, { sequence: sequence, start: type === 'turn/start',
          interrupted: reason === 'interrupted' || reason === 'forked' });
        this.turnsChanged = true;
      }
      return;
    }
    const rawId = getNumber(data, 'runId');
    const id = getString(data, 'runId') ?? (rawId === undefined ? '' : String(rawId));
    if (!id) { return; }
    const record = this.workflows.get(id) ?? new RecordedWorkflow();
    if (type === 'tool-workflow/run-start') {
      const name = getString(data, 'name');
      if (name === undefined || (record.start >= 0 && record.start <= sequence)) { return; }
      record.start = sequence;
      record.name = name;
    } else if (type === 'tool-workflow/run-end') {
      const status = terminalStatus(getString(data, 'stopReason'));
      if (status === undefined || (record.end?.sequence ?? -1) >= sequence) { return; }
      record.end = { sequence: sequence, status: status };
    } else {
      const member = getNumber(data, 'seq') ?? -1;
      if (member < 0) { return; }
      if (type === 'tool-workflow/agent-start') {
        const child = getString(data, 'childId') ?? '';
        const label = getString(data, 'label');
        if (label === undefined || !child || record.members.has(member)) { return; }
        record.members.set(member, { eventSequence: sequence, childId: child, label: label, phase: getString(data, 'phase') });
      } else if (type === 'tool-workflow/agent-end') {
        const status = terminalStatus(getString(data, 'outcome'));
        if (status === undefined || (record.outcomes.get(member)?.sequence ?? -1) >= sequence) { return; }
        record.outcomes.set(member, { sequence: sequence, status: status });
      } else {
        return;
      }
    }
    this.workflows.set(id, record);
    this.changed.add(id);
  }

  runs(): DesktopWorkflowRun[] {
    if (this.turnsChanged) {
      this.turnsChanged = false;
      this.boundaries = Array.from(this.turns.values()).sort((a: TurnBoundary, b: TurnBoundary): number => a.sequence - b.sequence);
      this.workflows.forEach((record: RecordedWorkflow, id: string): void => {
        if (record.end === undefined) { this.changed.add(id); }
      });
    }
    this.changed.forEach((id: string): void => {
      const record = this.workflows.get(id);
      if (record === undefined || record.start < 0) { return; }
      const view = this.project(record);
      const row = this.rows.get(id);
      if (row === undefined) {
        this.rows.set(id, new DesktopWorkflowRun(id, record.start, view));
      } else if (row.sequence !== record.start || JSON.stringify(row.view) !== JSON.stringify(view)) {
        row.sequence = record.start;
        row.view = view;
      }
    });
    this.changed.clear();
    return Array.from(this.rows.values());
  }

  private interrupted(anchor: number): boolean {
    let low = 0;
    let high = this.boundaries.length;
    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      if (this.boundaries[mid].sequence < anchor) { low = mid + 1; } else { high = mid; }
    }
    const previous = this.boundaries[low - 1];
    const next = this.boundaries[low];
    return next?.interrupted === true && !next.start && (previous === undefined || previous.start);
  }

  private project(record: RecordedWorkflow): DesktopWorkflowView {
    const interrupted = record.end === undefined && this.interrupted(record.start);
    const running = interrupted ? DesktopWorkflowStatus.INTERRUPTED : DesktopWorkflowStatus.RUNNING;
    const indexedMembers = Array.from(record.members.entries()).sort((a, b): number =>
      a[1].eventSequence - b[1].eventSequence);
    const phases: Map<string, DesktopWorkflowPhase> = new Map();
    for (const entry of indexedMembers) {
      const member = entry[1];
      const key = member.phase === undefined ? 'missing' : 'value:' + member.phase;
      const phase: DesktopWorkflowPhase = phases.get(key) ?? { key: key, label: member.phase, members: [] };
      phase.members.push({ sequence: entry[0], label: member.label, childId: member.childId,
        status: record.outcomes.get(entry[0])?.status ?? running });
      phases.set(key, phase);
    }
    return { name: record.name, status: record.end?.status ?? running, phases: Array.from(phases.values()),
      memberCount: record.members.size };
  }
}
