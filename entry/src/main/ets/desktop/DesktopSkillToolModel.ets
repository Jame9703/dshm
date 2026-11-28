import { getArray, getBoolean, getRecord, getString, parseJson } from 'connection';

export type DesktopSkillToolState = 'preparing' | 'running' | 'complete' | 'failed' | 'stopped';

export interface DesktopSkillToolResult {
  output: string;
  failed: boolean;
  interrupted: boolean;
}

export interface DesktopSkillToolView {
  state: DesktopSkillToolState;
  summary: string;
  output: string;
}

const PREPARING_SKILL_TOOL: DesktopSkillToolView = { state: 'preparing', summary: '', output: '' };

export function desktopPreparingSkillTool(): DesktopSkillToolView { return PREPARING_SKILL_TOOL; }

function firstLine(value: string): string {
  const newline = value.indexOf('\n');
  return newline < 0 ? value : value.slice(0, newline);
}

export function readDesktopSkillToolResult(data: Object | undefined, nested: boolean): DesktopSkillToolResult {
  const message = nested ? data : getRecord(data, 'message');
  const error = getRecord(data, 'error') ?? getRecord(message, 'error');
  const code = getString(error, 'code') ?? '';
  const blocks = getArray(message, 'content') ?? [];
  const output = blocks.length > 0 ? blocks.map((block: Object): string =>
    getString(block, 'type') === 'text' ? getString(block, 'text') ?? '' : JSON.stringify(block, null, 2)).join('\n') :
    (error === undefined ? '' : [getString(error, 'name') ?? '', code].filter((part: string): boolean => !!part).join(': '));
  return { output: output, failed: getBoolean(message, 'isError') === true || error !== undefined,
    interrupted: code === 'interrupted' };
}

export function desktopSkillToolView(callId: string, argumentsText: string, result: DesktopSkillToolResult | undefined,
  closedWithoutResult: boolean): DesktopSkillToolView {
  const name = firstLine(getString(parseJson(argumentsText), 'name') || argumentsText || callId);
  const state: DesktopSkillToolState = result?.interrupted || closedWithoutResult ? 'stopped' :
    result === undefined ? 'running' : result.failed ? 'failed' : 'complete';
  const output = result?.output ?? '';
  return { state: state, summary: state === 'failed' && output ? firstLine(output) : name, output: output };
}
