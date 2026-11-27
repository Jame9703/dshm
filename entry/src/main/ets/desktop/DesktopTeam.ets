import { getArray, getBoolean, getRecord, getString } from 'connection';

export interface DesktopTeamTask {
  id: string;
  subject: string;
  description: string;
  status: string;
  owner: string;
  blocked: boolean;
}

export interface DesktopTeam {
  enabled: boolean;
  tasks: DesktopTeamTask[];
  progress: string;
  failure: string;
}

export function desktopReadTeam(value: Object | undefined): DesktopTeam | undefined {
  const enabled = getBoolean(value, 'enabled');
  if (enabled === undefined) { return undefined; }
  const active: DesktopTeamTask[] = [];
  const pending: DesktopTeamTask[] = [];
  const completed: DesktopTeamTask[] = [];
  if (enabled) {
    for (const raw of getArray(value, 'tasks') ?? []) {
      const id = getString(raw, 'id') ?? '';
      const status = getString(raw, 'status') ?? '';
      if (!id || (status !== 'pending' && status !== 'in_progress' && status !== 'completed')) { continue; }
      const row: DesktopTeamTask = { id: id, subject: getString(raw, 'subject') || id,
        description: getString(raw, 'description') ?? '', status: status,
        owner: getString(raw, 'ownerName') || getString(raw, 'ownerId') || '未分配',
        blocked: status === 'pending' && getBoolean(raw, 'ready') === false };
      (status === 'in_progress' ? active : status === 'pending' ? pending : completed).push(row);
    }
  }
  const counts: string[] = [];
  if (completed.length > 0) { counts.push(`${completed.length} 已完成`); }
  if (active.length > 0) { counts.push(`${active.length} 进行中`); }
  if (pending.length > 0) { counts.push(`${pending.length} 待处理`); }
  return { enabled: enabled, tasks: active.concat(pending, completed.reverse()),
    progress: counts.join(' · '), failure: getString(value, 'failure') ?? '' };
}

export function desktopTeamBoardVisible(team?: DesktopTeam): boolean {
  return team?.enabled === true && (team.tasks.length > 0 || !!team.failure);
}

export class DesktopTeamState {
  view?: DesktopTeam;
  modelReady: boolean = false;
  lastModelUsed: boolean = false;
  private teamSequence: number = -1;
  private modelSequence: number = -1;

  clear(): void {
    this.view = undefined;
    this.modelReady = false;
    this.lastModelUsed = false;
    this.teamSequence = -1;
    this.modelSequence = -1;
  }

  observe(values: Object | undefined, sequence: number): boolean {
    let changed = false;
    const raw = getRecord(values, 'agentTeam');
    if (raw !== undefined && sequence > this.teamSequence) {
      this.teamSequence = sequence;
      this.view = desktopReadTeam(raw);
      changed = true;
    }
    const model = getRecord(values, 'modelSelection');
    if (model !== undefined && sequence > this.modelSequence) {
      this.modelSequence = sequence;
      const used = getRecord(model, 'lastUsed') !== undefined;
      changed = changed || !this.modelReady || this.lastModelUsed !== used;
      this.modelReady = true;
      this.lastModelUsed = used;
    }
    return changed;
  }
}
