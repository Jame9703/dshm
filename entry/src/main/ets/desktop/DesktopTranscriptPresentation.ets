import { Speaker, ToolState, TrajectoryKind } from 'appstate';
import { getArray, getNumber, getRecord, getString } from 'connection';
import type { DesktopTranscriptItem } from './DesktopConversation';
import type { DesktopToolStep } from './DesktopToolLog';
import {
  readDesktopTranscriptCollapseTiming, readDesktopTranscriptFoldedReplies, readDesktopTranscriptMode
} from './DesktopTranscriptPreferencesModel';
import type {
  DesktopTranscriptCollapseTiming, DesktopTranscriptFoldedReplies, DesktopTranscriptMode
} from './DesktopTranscriptPreferencesModel';

export type DesktopTranscriptStepGrouping = 'collapsed' | 'history' | 'none';

export interface DesktopTranscriptPolicy {
  displayMode: DesktopTranscriptMode;
  collapseTiming: DesktopTranscriptCollapseTiming;
  foldedReplies: DesktopTranscriptFoldedReplies;
  stepGrouping: DesktopTranscriptStepGrouping;
  liveProcessDetail: boolean;
  settledReasoningPreview: boolean;
  foldCompletedTurns: boolean;
}

export function readDesktopTranscriptPolicy(chatValue?: Object): DesktopTranscriptPolicy {
  const mode = readDesktopTranscriptMode(getString(chatValue, 'transcriptView'));
  return {
    displayMode: mode,
    collapseTiming: readDesktopTranscriptCollapseTiming(getString(chatValue, 'collapseTiming')),
    foldedReplies: readDesktopTranscriptFoldedReplies(getString(chatValue, 'foldedReplies')),
    stepGrouping: mode === 'verbose' ? 'none' : mode === 'detailed' ? 'history' : 'collapsed',
    liveProcessDetail: mode === 'standard' || mode === 'detailed',
    settledReasoningPreview: mode !== 'compact',
    foldCompletedTurns: mode !== 'verbose'
  };
}

export const DEFAULT_DESKTOP_TRANSCRIPT_POLICY: DesktopTranscriptPolicy = readDesktopTranscriptPolicy();

export interface DesktopTranscriptTurn {
  turn: number;
  startSequence: number;
  endSequence: number;
  startTime: number;
  endTime: number;
  endReason: string;
  inputSequences: number[];
  latestStep: number;
  assistantSequence: number;
  answerSequence: number;
}

function providesFinalReply(data?: Object): boolean {
  const content = getArray(getRecord(data, 'message'), 'content') ?? [];
  if (content.some((block: Object): boolean => getString(block, 'type') === 'tool-call')) { return false; }
  return content.some((block: Object): boolean => {
    const kind = getString(block, 'type');
    if (kind === 'text') { return (getString(block, 'text') ?? '').trim().length > 0; }
    return kind !== undefined && kind !== 'reasoning';
  });
}

/** The host stream can replay or prepend records. Only changed boundaries replace the public snapshot. */
export class DesktopTranscriptTurnTimeline {
  private readonly byTurn: Map<number, DesktopTranscriptTurn> = new Map<number, DesktopTranscriptTurn>();
  private snapshot: DesktopTranscriptTurn[] = [];
  private dirty: boolean = false;

  clear(): void {
    if (this.byTurn.size === 0) { return; }
    this.byTurn.clear();
    this.dirty = true;
  }

  observe(record: Object): void {
    const event = getRecord(record, 'event');
    const type = getString(event, 'type');
    const assistantMessage = type === 'assistant/message' && getString(event, 'surfaceOp') === 'append';
    const stepEvent = assistantMessage || type === 'step/start' || type === 'step/end';
    if (!stepEvent && type !== 'turn/start' && type !== 'turn/end' && type !== 'user/message') { return; }
    const data = getRecord(event, 'data');
    const sequence = getNumber(event, 'seq') ?? -1;
    const turn = getNumber(data, 'turn') ?? -1;
    const step = stepEvent ? (getNumber(data, 'step') ?? -1) : -1;
    if (sequence < 0 || turn < 0 || (stepEvent && step < 0)) { return; }
    const source = getString(getRecord(data, 'source'), 'kind');
    if (type === 'user/message' && source !== undefined && source !== 'user') { return; }

    const previous = this.byTurn.get(turn);
    const current: DesktopTranscriptTurn = {
      turn: turn, startSequence: previous?.startSequence ?? -1, endSequence: previous?.endSequence ?? -1,
      startTime: previous?.startTime ?? -1, endTime: previous?.endTime ?? -1,
      endReason: previous?.endReason ?? '', inputSequences: previous?.inputSequences ?? [],
      latestStep: previous?.latestStep ?? -1, assistantSequence: previous?.assistantSequence ?? -1,
      answerSequence: previous?.answerSequence ?? -1
    };
    const time = getNumber(event, 'time') ?? -1;
    if (type === 'turn/start') {
      if (current.startSequence >= 0 && sequence > current.startSequence) { return; }
      if (sequence === current.startSequence && time === current.startTime) { return; }
      current.startSequence = sequence;
      current.startTime = time;
    } else if (type === 'turn/end') {
      if (sequence < current.endSequence) { return; }
      const reason = getString(getRecord(data, 'reason'), 'kind') ?? '';
      if (sequence === current.endSequence && time === current.endTime && reason === current.endReason) { return; }
      current.endSequence = sequence;
      current.endTime = time;
      current.endReason = reason;
    } else if (type === 'user/message') {
      if (current.inputSequences.includes(sequence)) { return; }
      current.inputSequences = current.inputSequences.concat([sequence]);
    } else {
      if (step < current.latestStep) { return; }
      if (step > current.latestStep) {
        current.latestStep = step;
        current.assistantSequence = -1;
        current.answerSequence = -1;
      } else if (!assistantMessage || sequence <= current.assistantSequence) {
        return;
      }
      if (assistantMessage) {
        current.assistantSequence = sequence;
        current.answerSequence = providesFinalReply(data) ? sequence : -1;
      }
    }
    this.byTurn.set(turn, current);
    this.dirty = true;
  }

  turns(): DesktopTranscriptTurn[] {
    if (this.dirty) {
      this.snapshot = Array.from(this.byTurn.values()).sort((a: DesktopTranscriptTurn, b: DesktopTranscriptTurn): number =>
        a.turn - b.turn);
      this.dirty = false;
    }
    return this.snapshot;
  }
}

export type DesktopTranscriptStatus = 'completed' | 'failed' | 'stopped';

export interface DesktopTranscriptDisclosure {
  turn: number;
  anchorSequence: number;
  status: DesktopTranscriptStatus;
  elapsedMs: number;
  open: boolean;
  canToggle: boolean;
}

export interface DesktopTranscriptRow {
  key: string;
  item?: DesktopTranscriptItem;
  process?: DesktopTranscriptDisclosure;
  turn?: number;
  showReasoning: boolean;
  previewReasoning: boolean;
  groupProcess: boolean;
  liveProcessDetail: boolean;
}

interface TurnPresentation {
  boundary: DesktopTranscriptTurn;
  firstAnchor?: DesktopTranscriptItem;
  lastReply?: DesktopTranscriptItem;
  lastInputSequence: number;
  firstProcessSequence: number;
  protected: boolean;
  hasHiddenContent: boolean;
  grouped: boolean;
  disclosure?: DesktopTranscriptDisclosure;
}

function itemTurn(item: DesktopTranscriptItem): number | undefined {
  return item.turn ?? item.process?.turn ?? item.replyTail?.turn ?? item.artifacts?.turn;
}

function assistant(item: DesktopTranscriptItem): boolean {
  return item.message?.speaker === Speaker.ASSISTANT && item.message?.kind !== TrajectoryKind.ERROR;
}

function userInput(item: DesktopTranscriptItem): boolean {
  return item.message?.speaker === Speaker.USER || item.questionReply !== undefined;
}

function reply(item: DesktopTranscriptItem): boolean {
  return assistant(item) && (item.message?.body.trim().length ?? 0) > 0;
}

function hasReasoning(item: DesktopTranscriptItem): boolean {
  return assistant(item) && ((item.message?.reasoning.length ?? 0) > 0 || item.message?.kind === TrajectoryKind.REASONING);
}

function keepVisible(item: DesktopTranscriptItem): boolean {
  return (item.attachments?.length ?? 0) > 0 || item.plan !== undefined || item.artifacts !== undefined ||
    item.cordis !== undefined || item.command !== undefined || item.workflow !== undefined || item.replyTail !== undefined ||
    item.message?.kind === TrajectoryKind.ERROR || (item.notice !== undefined && item.notice.kind !== 'retry');
}

function needsOpen(step: DesktopToolStep): boolean {
  return step.interrupted || step.error.length > 0 || step.item.toolState === ToolState.PENDING ||
    step.item.toolState === ToolState.RUNNING || step.item.toolState === ToolState.FAILED ||
    step.item.toolState === ToolState.REJECTED || step.item.toolName === 'ask_user_question';
}

function hidesItem(item: DesktopTranscriptItem, turn: TurnPresentation, policy: DesktopTranscriptPolicy): boolean {
  if (keepVisible(item)) { return false; }
  if (item.contextMessage?.kind === 'context') {
    return turn.lastReply === undefined ? item.sequence >= turn.firstProcessSequence : item.sequence < turn.lastReply.sequence;
  }
  if (item.process !== undefined || item.notice?.kind === 'retry') {
    return item.sequence < (turn.lastReply?.sequence ?? Infinity);
  }
  if (!assistant(item) || item === turn.lastReply) { return false; }
  if (!reply(item)) { return hasReasoning(item); }
  return policy.foldedReplies === 'final' && item.sequence < (turn.lastReply?.sequence ?? Infinity);
}

function statusOf(reason: string): DesktopTranscriptStatus {
  if (reason === 'aborted' || reason === 'interrupted') { return 'stopped'; }
  return reason === 'error' ? 'failed' : 'completed';
}

/** Display rows preserve source order and never modify the durable transcript or the user's override map. */
export function desktopTranscriptRows(items: DesktopTranscriptItem[], turns: DesktopTranscriptTurn[],
  policy: DesktopTranscriptPolicy, overrides: Map<number, boolean>, pendingTranscriptInput: boolean = false):
  DesktopTranscriptRow[] {
  const summaries = new Map<number, TurnPresentation>();
  const rowTurns = new Map<string, TurnPresentation>();
  const started = turns.filter((row: DesktopTranscriptTurn): boolean => row.startSequence >= 0)
    .sort((a: DesktopTranscriptTurn, b: DesktopTranscriptTurn): number => a.startSequence - b.startSequence);
  let current = -1;
  let lastInputSequence = -1;
  let lastInputTurn: number | undefined = undefined;
  let latestClosedTurn = -1;
  for (const row of turns) {
    if (row.endSequence >= 0) { latestClosedTurn = Math.max(latestClosedTurn, row.turn); }
    const summary: TurnPresentation = {
      boundary: row, lastInputSequence: -1, firstProcessSequence: Infinity,
      protected: false, hasHiddenContent: false, grouped: false
    };
    for (const sequence of row.inputSequences) {
      summary.lastInputSequence = Math.max(summary.lastInputSequence, sequence);
      if (sequence > lastInputSequence) {
        lastInputSequence = sequence;
        lastInputTurn = row.turn;
      }
    }
    summaries.set(row.turn, summary);
  }

  for (const item of items) {
    while (current + 1 < started.length && started[current + 1].startSequence <= item.sequence) { current++; }
    const range = current < 0 ? undefined : started[current];
    const inRange = range !== undefined && (range.endSequence < 0 || item.sequence <= range.endSequence);
    const turn = itemTurn(item) ?? (inRange ? range?.turn : undefined);
    const summary = turn === undefined ? undefined : summaries.get(turn);
    if (userInput(item) && item.sequence > lastInputSequence) {
      lastInputSequence = item.sequence;
      lastInputTurn = turn;
    }
    if (summary === undefined) { continue; }
    rowTurns.set(item.id, summary);
    if (userInput(item)) {
      summary.lastInputSequence = Math.max(summary.lastInputSequence, item.sequence);
    }
    if (assistant(item) || item.process !== undefined || item.notice?.kind === 'retry' ||
        item.message?.kind === TrajectoryKind.ERROR) {
      summary.firstAnchor = summary.firstAnchor ?? item;
      summary.firstProcessSequence = Math.min(summary.firstProcessSequence, item.sequence);
    }
    const step = summary.boundary;
    if ((step.latestStep < 0 || item.sequence === step.answerSequence) && reply(item)) {
      summary.lastReply = item;
    }
    if (!summary.protected && (item.message?.kind === TrajectoryKind.ERROR ||
        item.process?.steps.some((step: DesktopToolStep): boolean => needsOpen(step)) === true)) {
      summary.protected = true;
    }
  }

  if (policy.foldCompletedTurns) {
    for (const item of items) {
      const summary = rowTurns.get(item.id);
      if (summary !== undefined && !summary.hasHiddenContent && !summary.protected &&
          summary.boundary.endSequence >= 0 && (hasReasoning(item) || hidesItem(item, summary, policy))) {
        summary.hasHiddenContent = true;
      }
    }
  }

  const deferCollapse = policy.collapseTiming === 'next-input' && !pendingTranscriptInput;
  summaries.forEach((summary: TurnPresentation, turn: number): void => {
    const row = summary.boundary;
    const closed = row.endSequence >= 0;
    const waitForInput = closed && deferCollapse && (lastInputTurn === turn ||
      (lastInputTurn === undefined && turn === latestClosedTurn && lastInputSequence < row.endSequence));
    summary.grouped = policy.stepGrouping === 'collapsed' ||
      (policy.stepGrouping === 'history' && closed && !waitForInput);
    if (!closed || summary.firstAnchor === undefined) { return; }
    const status = statusOf(row.endReason);
    const hasInterleavedInput = summary.lastInputSequence > summary.firstProcessSequence &&
      summary.lastInputSequence < row.endSequence;
    const canToggle = policy.foldCompletedTurns && status === 'completed' && summary.hasHiddenContent &&
      !summary.protected && !hasInterleavedInput;
    const elapsedMs = row.startTime >= 0 && row.endTime >= row.startTime && status === 'completed' ?
      Math.max(1000, row.endTime - row.startTime) : 0;
    summary.disclosure = {
      turn: turn, anchorSequence: summary.firstAnchor.sequence, status: status, elapsedMs: elapsedMs,
      open: !canToggle || (overrides.get(turn) ?? waitForInput), canToggle: canToggle
    };
  });

  const rows: DesktopTranscriptRow[] = [];
  for (const item of items) {
    const summary = rowTurns.get(item.id);
    const turn = summary?.boundary.turn;
    const disclosure = summary?.disclosure;
    if (disclosure !== undefined && summary?.firstAnchor === item) {
      rows.push({ key: `process-disclosure:${disclosure.turn}`, process: disclosure, turn: turn,
        showReasoning: false, previewReasoning: false, groupProcess: false, liveProcessDetail: false });
    }
    const folded = disclosure?.open === false;
    if (folded && summary !== undefined && hidesItem(item, summary, policy)) { continue; }
    const closed = (summary?.boundary.endSequence ?? -1) >= 0;
    rows.push({ key: item.id, item: item, turn: turn, showReasoning: !folded,
      previewReasoning: !closed || policy.settledReasoningPreview,
      groupProcess: summary?.grouped ?? policy.stepGrouping === 'collapsed',
      liveProcessDetail: !closed && policy.liveProcessDetail });
  }
  return rows;
}
