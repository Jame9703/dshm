import { followSessionAddress, projectSessionPage } from 'appstate';
import { getBoolean, getNumber, getRecord, getString, parseJson } from 'connection';
import { SESSION_PAGE_ENDPOINT } from 'dshcompat';
import type { DesktopHostActions } from './DesktopHostActions';

export interface DesktopPlanDocument {
  callId: string;
  title: string;
  markdown: string;
  sequence: number;
}

export interface DesktopPlanReview {
  document: DesktopPlanDocument;
  questionId: string;
  approve: string;
  summary: string;
}

export function desktopPlanTitle(markdown: string): string {
  const first = markdown.trim().split('\n', 1)[0] ?? '';
  return first.replace(new RegExp('^#{1,6}\\s+'), '').trim() || '计划';
}

export function desktopPlanMode(projection?: Object): boolean | undefined {
  const plan = getRecord(getRecord(projection, 'values'), 'plan');
  const active = getBoolean(plan, 'active');
  return active === undefined ? undefined : (getBoolean(plan, 'pending') === true ? !active : active);
}

export function desktopSubmittedPlan(event?: Object): DesktopPlanDocument | undefined {
  const kind = getString(event, 'type');
  if (kind !== 'tool/call' && kind !== 'tool/ptc-dispatch-start' && kind !== 'tool/ptc-dispatch') {
    return undefined;
  }
  const data = getRecord(event, 'data');
  if (getString(data, 'name') !== 'exit_plan_mode') {
    return undefined;
  }
  const callId = getString(data, kind === 'tool/call' ? 'callId' : 'subCallId') ?? '';
  const args = kind === 'tool/call' ? parseJson(getString(data, 'arguments') ?? '') : getRecord(data, 'arguments');
  const markdown = getString(args, 'plan') ?? '';
  const sequence = getNumber(event, 'seq') ?? -1;
  if (!callId || sequence < 0 || !new RegExp('^#\\s+\\S').test(markdown.trim())) {
    return undefined;
  }
  return { callId: callId, title: desktopPlanTitle(markdown), markdown: markdown, sequence: sequence };
}

export async function readDesktopPlan(host: DesktopHostActions, sessionId: string,
  target: DesktopPlanDocument): Promise<string> {
  const result = await host.call(SESSION_PAGE_ENDPOINT, {
    'address': followSessionAddress(sessionId), 'throughSeq': target.sequence, 'maxMessages': 1
  });
  if (!result.ok) { return ''; }
  for (const row of projectSessionPage(result.value).records) {
    const plan = desktopSubmittedPlan(getRecord(row, 'event'));
    if (plan?.callId === target.callId && plan.sequence === target.sequence) { return plan.markdown; }
  }
  return '';
}
