import { getField, getNumber, getRecord, getString, stringifyJson } from 'connection';

export type DesktopTranscriptNoticeKind = 'retry' | 'turn-error' | 'turn-max-tokens';
export type DesktopTranscriptRetryState = 'scheduled' | 'started' | 'cancelled';

export interface DesktopTranscriptFailure {
  code: string;
  message: string;
}

export interface DesktopTranscriptRetryAttempt {
  sequence: number;
  step: number;
  number: number;
  delayMs: number;
  maximum?: number;
  failure: DesktopTranscriptFailure;
}

export interface DesktopTranscriptNotice {
  id: string;
  sequence: number;
  turn: number;
  kind: DesktopTranscriptNoticeKind;
  retry?: DesktopTranscriptRetryAttempt;
  retryState?: DesktopTranscriptRetryState;
  failure?: DesktopTranscriptFailure;
}

interface RetryChain {
  id: string;
  turn: number;
  first: number;
  step: number;
  current?: DesktopTranscriptRetryAttempt;
  started: Set<number>;
}

function displayFailure(raw: Object | undefined): DesktopTranscriptFailure {
  const code = getString(raw, 'code') ?? '';
  if (code === 'AUTH') { return { code: code, message: '' }; }
  const message = getString(raw, 'message') ??
    (typeof raw === 'string' ? raw : raw === undefined ? '' : stringifyJson(raw) ?? '');
  return { code: code, message: message };
}

function terminalNotice(turn: number, sequence: number, reason?: Object): DesktopTranscriptNotice | undefined {
  const kind = getString(reason, 'kind');
  const id = `turn-notice:${turn}`;
  if (kind === 'max-tokens') {
    return { id: id, sequence: sequence, turn: turn, kind: 'turn-max-tokens' };
  }

  let failure: DesktopTranscriptFailure | undefined = undefined;
  if (kind === 'error') {
    failure = displayFailure(getField(reason, 'error'));
  } else if (kind === 'interrupted') {
    failure = { code: 'INTERRUPTED', message: '' };
  } else if (kind === 'aborted') {
    const abort = getRecord(reason, 'reason');
    if (getString(abort, 'kind') === 'hook' && getString(abort, 'reason') === 'deepseek-account/signed-out') {
      failure = { code: 'ACCOUNT_SIGNED_OUT', message: '' };
    }
  }
  return failure === undefined ? undefined :
    { id: id, sequence: sequence, turn: turn, kind: 'turn-error', failure: failure };
}

export function desktopTranscriptNoticeSequence(notice: DesktopTranscriptNotice, closingMessageSequence: number = -1):
  number {
  if (notice.kind === 'turn-max-tokens' && closingMessageSequence >= 0 && closingMessageSequence < notice.sequence) {
    return closingMessageSequence + 0.05;
  }
  return notice.sequence;
}

export function desktopTranscriptRetrySeconds(milliseconds: number): number {
  return Math.max(1, Math.ceil(milliseconds / 1000));
}

/** Keep one visible row at the start of a producer-owned retry chain, even when history is prepended. */
export class DesktopTranscriptNoticeTimeline {
  private readonly chains: Map<string, RetryChain> = new Map<string, RetryChain>();
  private readonly retriesByTurn: Map<number, Set<string>> = new Map<number, Set<string>>();
  private readonly closedSteps: Map<number, Set<number>> = new Map<number, Set<number>>();
  private readonly closedTurns: Map<number, number> = new Map<number, number>();
  private readonly visible: Map<string, DesktopTranscriptNotice> = new Map<string, DesktopTranscriptNotice>();
  private snapshot: DesktopTranscriptNotice[] = [];
  private dirty: boolean = false;

  clear(): void {
    this.chains.clear();
    this.retriesByTurn.clear();
    this.closedSteps.clear();
    this.closedTurns.clear();
    if (this.visible.size > 0) { this.dirty = true; }
    this.visible.clear();
  }

  observe(record: Object): boolean {
    const event = getRecord(record, 'event');
    const type = getString(event, 'type');
    if (type !== 'llm/retry' && type !== 'llm/retry-started' && type !== 'step/end' && type !== 'turn/end') {
      return false;
    }
    const sequence = getNumber(event, 'seq') ?? -1;
    const data = getRecord(event, 'data');
    const turn = getNumber(data, 'turn') ?? -1;
    const step = getNumber(data, 'step') ?? -1;
    if (sequence < 0 || turn < 0 || (step < 0 && type !== 'turn/end')) { return false; }
    if (type === 'turn/end') { return this.closeTurn(turn, sequence, getRecord(data, 'reason')); }
    if (type === 'step/end') { return this.closeStep(turn, step); }
    return this.observeRetry(type === 'llm/retry-started', turn, step, sequence, data);
  }

  notices(): DesktopTranscriptNotice[] {
    if (this.dirty) {
      this.snapshot = Array.from(this.visible.values()).sort((a: DesktopTranscriptNotice, b: DesktopTranscriptNotice):
        number => a.sequence - b.sequence);
      this.dirty = false;
    }
    return this.snapshot;
  }

  private observeRetry(started: boolean, turn: number, step: number, sequence: number, data?: Object): boolean {
    const retryId = getString(data, 'retryId') ?? '';
    const retry = getNumber(data, 'retry') ?? -1;
    if (!retryId || retry < 1) { return false; }
    const delay = getNumber(data, 'delayMs') ?? -1;
    if (!started && (!Number.isFinite(delay) || delay < 0)) { return false; }
    let chain = this.chains.get(retryId);
    if (chain === undefined) {
      chain = { id: `model-retry:${retryId}`, turn: turn, step: step, first: -1, started: new Set<number>() };
      this.chains.set(retryId, chain);
      const turnRetries = this.retriesByTurn.get(turn) ?? new Set<string>();
      turnRetries.add(retryId);
      this.retriesByTurn.set(turn, turnRetries);
    }
    if (chain.turn !== turn || chain.step !== step) { return false; }
    if (started) {
      if (retry < (chain.current?.number ?? retry) || chain.started.has(retry)) { return false; }
      chain.started.add(retry);
    } else {
      if (retry === 1 && (chain.first < 0 || sequence < chain.first)) { chain.first = sequence; }
      if (sequence > (chain.current?.sequence ?? -1)) {
        chain.current = {
          sequence: sequence, step: step, number: retry, delayMs: delay,
          maximum: getString(data, 'mode') === 'normal' ? getNumber(data, 'maxRetries') : undefined,
          failure: displayFailure(getField(data, 'failure'))
        };
        for (const previous of chain.started) {
          if (previous < retry) { chain.started.delete(previous); }
        }
      }
    }
    return this.updateRetry(chain);
  }

  private updateRetry(chain: RetryChain): boolean {
    const attempt = chain.current;
    if (chain.first < 0 || attempt === undefined) { return false; }
    const stepClosed = this.closedSteps.get(chain.turn)?.has(attempt.step) === true;
    let state: DesktopTranscriptRetryState = stepClosed || this.closedTurns.has(chain.turn) ? 'cancelled' : 'scheduled';
    if (chain.started.has(attempt.number)) { state = 'started'; }
    const previous = this.visible.get(chain.id);
    if (previous?.sequence === chain.first && previous.retry === attempt && previous.retryState === state) { return false; }
    this.visible.set(chain.id, {
      id: chain.id, sequence: chain.first, turn: chain.turn, kind: 'retry', retry: attempt, retryState: state
    });
    this.dirty = true;
    return true;
  }

  private closeTurn(turn: number, sequence: number, reason?: Object): boolean {
    if (sequence <= (this.closedTurns.get(turn) ?? -1)) { return false; }
    this.closedTurns.set(turn, sequence);
    const notice = terminalNotice(turn, sequence, reason);
    let changed = this.refreshRetries(turn);
    if (notice === undefined) {
      changed = this.visible.delete(`turn-notice:${turn}`) || changed;
    } else {
      this.visible.set(notice.id, notice);
      changed = true;
    }
    this.dirty = this.dirty || changed;
    return changed;
  }

  private closeStep(turn: number, step: number): boolean {
    const steps = this.closedSteps.get(turn) ?? new Set<number>();
    if (steps.has(step)) { return false; }
    steps.add(step);
    this.closedSteps.set(turn, steps);
    return this.refreshRetries(turn, step);
  }

  private refreshRetries(turn: number, step: number = -1): boolean {
    let changed = false;
    const ids = this.retriesByTurn.get(turn);
    if (ids === undefined) { return false; }
    for (const id of ids) {
      const chain = this.chains.get(id);
      if (chain !== undefined && (step < 0 || chain.step === step)) { changed = this.updateRetry(chain) || changed; }
    }
    return changed;
  }
}
