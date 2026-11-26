import { getArray, getField, getNumber, getRecord, getString } from 'connection';

export interface DesktopGoalRef {
  id: string;
  revision: number;
}

export interface DesktopGoal extends DesktopGoalRef {
  objective: string;
  phase: string;
  blocker: string;
  activation: string;
}

export enum DesktopGoalAction {
  EDIT = 'edit',
  CLEAR = 'clear',
  PAUSE = 'pause',
  RESUME = 'resume'
}

interface DesktopGoalActivation extends DesktopGoalRef {
  activation: string;
}

function goalRef(value?: Object): DesktopGoalRef | undefined {
  const id = getString(value, 'id') ?? '';
  const revision = getNumber(value, 'revision') ?? 0;
  return id && Number.isInteger(revision) && revision > 0 ? { id: id, revision: revision } : undefined;
}

function sameRef(left?: DesktopGoalRef, right?: DesktopGoalRef): boolean {
  return left?.id === right?.id && left?.revision === right?.revision;
}

export class DesktopGoalState {
  goal?: DesktopGoal;
  private sequence: number = -1;
  private live?: DesktopGoalActivation;
  private version: number = 0;

  reset(): void {
    this.goal = undefined;
    this.sequence = -1;
    this.live = undefined;
    this.version++;
  }

  readVersion(): number {
    return this.version;
  }

  observeProjection(projection?: Object): boolean {
    return this.apply(getNumber(projection, 'asOfSeq') ?? -1, getRecord(projection, 'values'));
  }

  observeDelta(frame: Object): boolean {
    return this.apply(getNumber(frame, 'seq') ?? -1, getRecord(frame, 'changes'));
  }

  private apply(sequence: number, values?: Object): boolean {
    const value = getField(values, 'goal');
    if (sequence < this.sequence || sequence < 0 || value === undefined) { return false; }
    if (value === null) { return this.setGoal(sequence, undefined); }
    const raw = getRecord(value, 'goal');
    const ref = goalRef(raw);
    const objective = getString(raw, 'objective') ?? '';
    const phase = getString(raw, 'phase') ?? '';
    if (ref === undefined || !objective || !['active', 'paused', 'blocked', 'complete'].includes(phase)) {
      return false;
    }
    const goal: DesktopGoal = { id: ref.id, revision: ref.revision, objective: objective, phase: phase,
      blocker: getString(getRecord(raw, 'blockedReason'), 'message') ?? '',
      activation: sameRef(ref, this.live) ? this.live?.activation ?? '' : '' };
    return this.setGoal(sequence, goal);
  }

  private setGoal(sequence: number, goal?: DesktopGoal): boolean {
    this.sequence = sequence;
    if (sameRef(goal, this.goal) && goal?.activation === this.goal?.activation) { return false; }
    this.goal = goal;
    return true;
  }

  observeEvent(frame: Object, sessionId: string): boolean {
    const event = getArray(frame, 'args')?.[0];
    if (!sessionId || getString(event, 'sessionId') !== sessionId) { return false; }
    return this.observeActivation(getRecord(event, 'goal'));
  }

  observeRead(version: number, expected: DesktopGoalRef, live?: Object): boolean {
    if (version !== this.version || !sameRef(this.goal, expected) || !sameRef(expected, goalRef(live))) { return false; }
    return this.observeActivation(live);
  }

  private observeActivation(value?: Object): boolean {
    const ref = goalRef(value);
    const activation = getString(value, 'activation') ?? '';
    if (ref !== undefined && activation !== 'armed' && activation !== 'disarmed') { return false; }
    if (ref !== undefined && ref.id === this.goal?.id && ref.revision < this.goal.revision) { return false; }
    this.version++;
    this.live = ref === undefined ? undefined : { id: ref.id, revision: ref.revision, activation: activation };
    const goal = this.goal;
    if (ref !== undefined && !sameRef(goal, ref)) { return false; }
    const next = activation;
    if (goal === undefined || goal.activation === next) { return false; }
    this.goal = { id: goal.id, revision: goal.revision, objective: goal.objective, phase: goal.phase,
      blocker: goal.blocker, activation: next };
    return true;
  }
}
