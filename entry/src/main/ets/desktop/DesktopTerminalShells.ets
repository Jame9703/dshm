import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { getString } from 'connection';
import { DesktopHostActions, desktopHostItems, desktopHostProblem } from './DesktopHostActions';

export interface DesktopShell {
  path: string;
  name: string;
}

export interface DesktopShellCatalog {
  choices: DesktopShell[];
  problem: string;
}

export interface DesktopTerminalLaunchRequest {
  sessionId: string;
  tabId: string;
  shellPath: string;
}

const PREFERENCES: string = 'dshm_terminal_shell';

export class DesktopTerminalShellPreference {
  private readonly context?: common.Context;
  private readonly origin: string;

  constructor(context: common.Context | undefined, origin: string) {
    this.context = context;
    this.origin = origin;
  }

  read(): string {
    try {
      if (this.context === undefined || !this.origin) { return ''; }
      const value = preferences.getPreferencesSync(this.context, { name: PREFERENCES }).getSync(this.origin, '');
      return typeof value === 'string' ? value : '';
    } catch (_) {
      return '';
    }
  }

  remember(path: string): void {
    try {
      if (this.context === undefined || !this.origin || !path) { return; }
      const store = preferences.getPreferencesSync(this.context, { name: PREFERENCES });
      if (store.getSync(this.origin, '') !== path) {
        store.putSync(this.origin, path);
        store.flush().catch((): void => {});
      }
    } catch (_) {}
  }
}

export function desktopTerminalLaunchShell(choices: DesktopShell[], previous: string): string {
  return choices.find((shell: DesktopShell): boolean => shell.path === previous)?.path ?? choices[0]?.path ?? '';
}

export async function readDesktopTerminalShells(host: DesktopHostActions, sessionId: string): Promise<DesktopShellCatalog> {
  const result = await host.call('terminal/shells', { 'agentId': sessionId });
  const choices: DesktopShell[] = [];
  const seen = new Set<string>();
  for (const item of desktopHostItems(result)) {
    const path = getString(item, 'path') ?? '';
    if (path && !seen.has(path)) {
      seen.add(path);
      choices.push({ path: path, name: getString(item, 'name') ?? path });
    }
  }
  return { choices: choices, problem: desktopHostProblem(result) };
}
