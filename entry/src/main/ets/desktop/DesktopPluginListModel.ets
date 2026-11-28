export interface DesktopPluginListInput {
  id: string;
  official: boolean;
  enabled: boolean;
  installed: boolean;
  listedByDefault?: boolean;
  hasError: boolean;
  rowsRunning: boolean;
}

export interface DesktopPluginListGroups {
  listed: string[];
  mine: string[];
  extensions: string[];
  more: string[];
}

interface DesktopPluginListOrder {
  row: DesktopPluginListInput;
  shortName: string;
  position: number;
}

const HARNESS_PREFIX = new RegExp('^dsh-(?:host-|client-)?');

// Plugin Manager catalog policy from @deepseek-ai/dsh-official-bundles.
const HIDDEN_BUNDLES = new Set<string>([
  '@deepseek-ai/dsh-base',
  '@deepseek-ai/dsh-web-app',
  '@deepseek-ai/dsh-headless',
  '@deepseek-ai/dsh-sdk-app',
  '@deepseek-ai/dsh-acp-app',
  '@deepseek-ai/dsh-sdk-minimal',
  '@deepseek-ai/dsh-experimental-tool-worktree',
  '@deepseek-ai/dsh-cua-mcp'
]);

const EXTENSION_BUNDLES: string[] = [
  '@deepseek-ai/dsh-experimental-voice-input-bundle',
  '@deepseek-ai/dsh-experimental-plugin-market-bundle',
  '@deepseek-ai/dsh-experimental-auto-review'
];

const MORE_BUNDLES: string[] = [
  '@deepseek-ai/dsh-experimental-inspector-profile',
  '@deepseek-ai/dsh-cua-bundle',
  '@deepseek-ai/dsh-timeline',
  '@deepseek-ai/dsh-experimental-terminal-bundle',
  '@deepseek-ai/dsh-experimental-cot-translation-bundle',
  '@deepseek-ai/dsh-experimental-session-search',
  '@deepseek-ai/dsh-experimental-session-titles-bundle',
  '@deepseek-ai/dsh-experimental-badge-skill-bundle',
  '@deepseek-ai/dsh-experimental-ralph-bundle',
  '@deepseek-ai/dsh-deepseek-chat-import',
  '@deepseek-ai/dsh-subagent-codex',
  '@deepseek-ai/dsh-subagent-claude-code'
];

function orderedRows(rows: DesktopPluginListInput[]): DesktopPluginListOrder[] {
  return rows.map((row: DesktopPluginListInput, position: number): DesktopPluginListOrder => {
    const name = row.id.startsWith('@') ? row.id.slice(row.id.indexOf('/') + 1) : row.id;
    return { row: row, shortName: name.replace(HARNESS_PREFIX, ''), position: position };
  }).sort((first: DesktopPluginListOrder, second: DesktopPluginListOrder): number =>
    first.shortName.localeCompare(second.shortName) || first.position - second.position);
}

/** Apply the manager store's name order before ranking the official catalog. */
export function desktopPluginList(rows: DesktopPluginListInput[]): DesktopPluginListGroups {
  const listed: string[] = [];
  const mine: string[] = [];
  const unranked: string[] = [];
  const seen = new Set<string>();
  const official = new Set<string>();
  const pinned = new Set<string>();
  for (const item of orderedRows(rows)) {
    const row = item.row;
    const id = row.id;
    if (!id || HIDDEN_BUNDLES.has(id) || seen.has(id) || !(row.installed || row.official || row.hasError) ||
        (row.listedByDefault === false && !row.enabled && !row.installed && !row.rowsRunning)) { continue; }
    seen.add(id);
    listed.push(id);
    if (!row.official) {
      mine.push(id);
      continue;
    }
    official.add(id);
    const heldBack = MORE_BUNDLES.includes(id);
    if (!heldBack || row.enabled) { pinned.add(id); }
    if (!heldBack && !EXTENSION_BUNDLES.includes(id)) { unranked.push(id); }
  }
  const first = EXTENSION_BUNDLES.filter((id: string): boolean => official.has(id));
  const last = MORE_BUNDLES.filter((id: string): boolean => official.has(id));
  const more = first.concat(unranked, last);
  const extensions = more.filter((id: string): boolean => pinned.has(id));
  return { listed: listed, mine: mine, extensions: extensions, more: more };
}
