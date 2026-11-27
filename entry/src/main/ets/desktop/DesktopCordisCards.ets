import { ToolState } from 'appstate';
import { getArray, getRecord, getString, parseJson } from 'connection';
import type { DesktopCordisRow, DesktopCordisSnapshot } from './DesktopCordisRuntime';

export interface DesktopCordisCard {
  id: string;
  action: string;
  sequence: number;
  resultSequence: number;
  plugin: string;
  packageId: string;
  run: string;
  mode: string;
  name: string;
  purpose: string;
  hostCode: string;
  clientCode: string;
  output: string;
  error: string;
  state: string;
  superseded: boolean;
}

export function desktopCordisAction(name: string): string {
  switch (name) {
    case 'cordis_define': return 'define';
    case 'cordis_run': return 'run';
    case 'cordis_stop': return 'stop';
    case 'cordis_undefine': return 'remove';
    default: return '';
  }
}

export function desktopCordisCard(action: string, id: string, sequence: number, resultSequence: number,
  raw: string, result?: Object, state: ToolState = ToolState.RUNNING, problem: string = '',
  interrupted: boolean = false): DesktopCordisCard {
  const args = parseJson(raw);
  const code = getRecord(args, 'code');
  const meta = state === ToolState.SUCCESS ? getRecord(result, 'meta') : undefined;
  const message = getRecord(result, 'message') ?? result;
  const output = (getArray(message, 'content') ?? []).map((block: Object): string => {
    if (getString(block, 'type') === 'text') { return getString(block, 'text') ?? ''; }
    return JSON.stringify(block, undefined, 2) ?? '';
  }).join('\n') || problem;
  const failed = state === ToolState.FAILED || state === ToolState.REJECTED;
  return {
    action: action, id: id, sequence: sequence, resultSequence: resultSequence,
    plugin: getString(meta, 'pluginId') || (action === 'define' ? '' :
      getString(args, 'pluginId') || getString(args, 'id') || ''),
    packageId: getString(meta, 'packageId') || (action === 'run' ? getString(args, 'packageId') ?? '' : ''),
    run: getString(meta, 'pluginRunId') ?? '', mode: getString(args, 'mode') ?? '',
    name: getString(args, 'name') || (action === 'define' ? raw.split('\n')[0].slice(0, 140) : ''),
    purpose: getString(args, 'purpose') ?? '', hostCode: getString(code, 'host') ?? '',
    clientCode: getString(code, 'client') ?? '', output: output,
    error: failed && !interrupted ? output.split('\n')[0] : '',
    state: interrupted ? 'interrupted' : failed ? 'failed' : state === ToolState.SUCCESS ? 'completed' : 'running',
    superseded: false
  };
}

export function desktopCordisRunKey(card: DesktopCordisCard): string {
  return card.action === 'run' && card.state === 'completed' && card.plugin && card.packageId && card.run
    ? JSON.stringify([card.plugin, card.packageId]) : '';
}

export function desktopCordisOwner(snapshot: DesktopCordisSnapshot, session: string,
  plugin: string): DesktopCordisRow | undefined {
  return snapshot.rows.find((row: DesktopCordisRow): boolean => row.id === plugin && row.session === session);
}

export function desktopCordisCardStatus(card: DesktopCordisCard, owner: DesktopCordisRow | undefined,
  removed: boolean): string {
  if (card.action === 'remove' || card.action === 'stop' || card.state === 'interrupted') { return card.state; }
  if (removed) { return 'removed'; }
  if (card.superseded) { return 'superseded'; }
  if (card.state === 'failed') { return 'failed'; }
  const attempt = owner !== undefined && owner.target === card.packageId &&
    (card.run ? owner.attemptId === card.run : !card.mode || !owner.mode || owner.mode === card.mode);
  if (card.action === 'run' && attempt && owner?.status === 'awaiting-approval') { return 'approval'; }
  if (card.action === 'run' && attempt && owner?.status === 'failed') { return 'failed'; }
  if (card.state === 'running') { return 'running'; }
  if (owner !== undefined && card.packageId && owner.running === card.packageId &&
    (card.action === 'define' || !card.run || owner.runId === card.run)) {
    return owner.packages.some(item => item.id === card.packageId && item.hasClient) ? 'client' : 'active';
  }
  return 'idle';
}

export function desktopCordisCardTitle(action: string, mode: string = ''): Resource {
  switch (action) {
    case 'define': return $r('app.string.desktop_cordis_card_define');
    case 'stop': return $r('app.string.desktop_cordis_card_stop');
    case 'remove': return $r('app.string.desktop_cordis_card_remove');
    default: return mode === 'update' ? $r('app.string.desktop_cordis_card_update') :
      $r('app.string.desktop_cordis_card_run');
  }
}

export function desktopCordisCardIcon(action: string): Resource {
  switch (action) {
    case 'stop': return $r('app.media.dsh_cordis_stop_fill');
    case 'remove': return $r('app.media.dsh_dock_trash');
    default: return $r('app.media.dsh_cordis_code_outline');
  }
}
