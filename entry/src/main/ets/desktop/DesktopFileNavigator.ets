import { FileNode, NodeKind, projectWorkspaceListing, WORKSPACE_ROOT_REQUEST_PATH } from 'appstate';
import { getString } from 'connection';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { DESKTOP_FILE_NAVIGATOR_DEFAULT_WIDTH } from './DesktopFileNavigatorModel';
import { defaultDesktopFileSearchPreferences, enabledDesktopFileSearchPaths } from './DesktopFileSearchModel';
import { DesktopFileSearchPreferencePatch, DesktopFileSearchPreferences } from './DesktopFileSearchModel';
import { DesktopFileSearchPreferenceBook } from './DesktopFileSearchPreference';
import { desktopFileSearchResults, desktopWorkspaceRelativePath } from './DesktopFileSearchResults';
import { DesktopFileNameSpan, DesktopFileSearchNode, DesktopFileSearchResults } from './DesktopFileSearchResults';

export interface DesktopFileNavigatorRow {
  path: string;
  name: string;
  directory: boolean;
  depth: number;
  expanded: boolean;
  loading: boolean;
  spans?: DesktopFileNameSpan[];
}

export interface DesktopFileNavigatorView {
  open: boolean;
  width: number;
  rows: DesktopFileNavigatorRow[];
  matches: DesktopFileNavigatorRow[];
  query: string;
  preferences: DesktopFileSearchPreferences;
  found?: DesktopFileSearchResults;
  searching: boolean;
  rootLoading: boolean;
  rootTruncated: boolean;
  notice: string;
  searchNotice: string;
}

export interface DesktopFileNavigatorLink {
  owner: string;
  paneId: string;
  sessionId: string;
  root: string;
}

interface Directory {
  children: FileNode[];
  loading: boolean;
  again: boolean;
  truncated: boolean;
  stop?: () => void;
}

type NavigatorListener = (view: DesktopFileNavigatorView) => void;

const ROOT: string = WORKSPACE_ROOT_REQUEST_PATH;
export const DESKTOP_FILE_REVEAL_PENDING: number = -2;

export function emptyDesktopFileNavigatorView(): DesktopFileNavigatorView {
  return { open: false, width: DESKTOP_FILE_NAVIGATOR_DEFAULT_WIDTH, rows: [], matches: [],
    query: '', preferences: defaultDesktopFileSearchPreferences(), searching: false, rootLoading: false,
    rootTruncated: false, notice: '', searchNotice: '' };
}

/** Shares one tree and search between the file views of a session's right pane. */
export class DesktopFileNavigator {
  private readonly host: DesktopHostActions | undefined;
  private readonly sessionId: string;
  private readonly preferenceBook: DesktopFileSearchPreferenceBook | undefined;
  private readonly directories = new Map<string, Directory>();
  private readonly listeners = new Set<NavigatorListener>();
  private readonly collapsedResults = new Set<string>();
  private readonly state: DesktopFileNavigatorView = emptyDesktopFileNavigatorView();
  private view: DesktopFileNavigatorView = emptyDesktopFileNavigatorView();
  private workspaceRoot: string = '';
  private holds: number = 0;
  private watching: boolean = false;
  private disposed: boolean = false;
  private searchTimer: number = -1;
  private searchRevision: number = 0;
  private searchKey: string = '';
  private treeScroll: number = 0;
  private searchScroll: number = 0;
  private stopSearchPreferences?: () => void;

  constructor(host: DesktopHostActions | undefined, sessionId: string,
    preferences: DesktopFileSearchPreferenceBook | undefined) {
    this.host = host;
    this.sessionId = sessionId;
    this.preferenceBook = preferences;
  }

  snapshot(): DesktopFileNavigatorView { return this.view; }

  subscribe(listener: NavigatorListener): () => void {
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }

  setWorkspaceRoot(root: string): void {
    if (this.disposed || this.workspaceRoot === root) { return; }
    this.stopWatches();
    this.directories.clear();
    this.stopSearchPreferences?.();
    this.stopSearchPreferences = undefined;
    clearTimeout(this.searchTimer);
    this.searchRevision++;
    this.searchKey = '';
    this.collapsedResults.clear();
    this.treeScroll = 0;
    this.searchScroll = 0;
    this.workspaceRoot = root;
    this.state.rows = [];
    this.state.matches = [];
    this.state.found = undefined;
    this.state.searching = false;
    this.state.notice = '';
    this.state.searchNotice = '';
    this.state.rootLoading = false;
    this.state.rootTruncated = false;
    this.state.preferences = this.preferenceBook?.get(root) ?? defaultDesktopFileSearchPreferences();
    if (root) {
      this.stopSearchPreferences = this.preferenceBook?.subscribe(root, (preferences: DesktopFileSearchPreferences): void => {
        if (!this.disposed && root === this.workspaceRoot) { this.applyPreferences(preferences); }
      });
    }
    if (this.holds > 0) { this.startWatches(); }
    this.emit();
  }

  hold(): () => void {
    if (this.disposed) { return (): void => {}; }
    this.holds++;
    this.startWatches();
    let held = true;
    return (): void => {
      if (!held) { return; }
      held = false;
      this.holds--;
      // The next drawing commits in the same turn when the user selects another tab.
      Promise.resolve().then((): void => {
        if (this.holds === 0) { this.stopWatches(); }
      });
    };
  }

  dispose(): void {
    this.disposed = true;
    this.stopWatches();
    this.stopSearchPreferences?.();
    this.stopSearchPreferences = undefined;
    this.listeners.clear();
    this.directories.clear();
    clearTimeout(this.searchTimer);
    this.searchRevision++;
  }

  setOpen(open: boolean): void {
    if (open === this.state.open) { return; }
    this.state.open = open;
    this.emit();
  }

  setWidth(width: number): void {
    if (width === this.state.width) { return; }
    this.state.width = width;
    this.emit();
  }

  scrollOffset(search: boolean): number { return search ? this.searchScroll : this.treeScroll; }

  saveScroll(search: boolean, offset: number): void {
    if (search) { this.searchScroll = offset; }
    else { this.treeScroll = offset; }
  }

  updatePreferences(patch: DesktopFileSearchPreferencePatch): boolean {
    const root = this.workspaceRoot;
    if (this.preferenceBook !== undefined && root) { return this.preferenceBook.update(root, patch); }
    const current = this.state.preferences;
    this.applyPreferences({ rules: patch.rules ?? current.rules, showHidden: patch.showHidden ?? current.showHidden,
      respectGitignore: patch.respectGitignore ?? current.respectGitignore });
    return true;
  }

  private applyPreferences(preferences: DesktopFileSearchPreferences): void {
    if (preferences.showHidden !== this.state.preferences.showHidden) {
      this.state.preferences = preferences;
      this.rebuildRows();
      this.assignMatches();
    } else {
      this.state.preferences = preferences;
    }
    this.queueSearch(this.state.query);
  }

  private emit(): void {
    const current = this.state;
    this.view = { open: current.open, width: current.width, rows: current.rows, matches: current.matches,
      query: current.query, preferences: current.preferences, found: current.found, searching: current.searching,
      rootLoading: current.rootLoading, rootTruncated: current.rootTruncated, notice: current.notice,
      searchNotice: current.searchNotice };
    const snapshot = this.view;
    this.listeners.forEach((listener: NavigatorListener): void => {
      if (snapshot === this.view) { listener(snapshot); }
    });
  }

  refresh(): void {
    if (this.state.query.trim()) { this.queueSearch(this.state.query, true); return; }
    for (const path of this.directories.keys()) {
      const directory = this.directories.get(path);
      if (directory !== undefined) { this.list(path, directory); }
    }
  }

  toggleDirectory(path: string): void {
    if (this.state.query.trim()) {
      if (this.collapsedResults.has(path)) { this.collapsedResults.delete(path); }
      else { this.collapsedResults.add(path); }
      this.assignMatches();
      this.emit();
    } else if (this.directories.has(path)) {
      this.collapse(path);
      this.rebuildRows();
      this.emit();
    } else {
      this.expand(path);
    }
  }

  reveal(path: string): number {
    if (!this.watching) { return DESKTOP_FILE_REVEAL_PENDING; }
    const parts = path.split('/');
    let parent = ROOT;
    for (let index = 0; index < parts.length - 1; index++) {
      const level = this.directories.get(parent);
      if (level === undefined || level.loading) { return DESKTOP_FILE_REVEAL_PENDING; }
      const directory = parts.slice(0, index + 1).join('/');
      if ((!this.state.preferences.showHidden && parts[index].startsWith('.')) ||
        !level.children.some((node: FileNode): boolean => node.path === directory && node.kind === NodeKind.DIRECTORY)) {
        return -1;
      }
      if (!this.directories.has(directory)) {
        this.expand(directory);
        return DESKTOP_FILE_REVEAL_PENDING;
      }
      parent = directory;
    }
    if (this.directories.get(parent)?.loading) { return DESKTOP_FILE_REVEAL_PENDING; }
    return this.state.rows.findIndex((row: DesktopFileNavigatorRow): boolean => row.path === path);
  }

  private startWatches(): void {
    if (this.watching || this.disposed || !this.workspaceRoot || !this.sessionId) { return; }
    this.watching = true;
    if (!this.directories.has(ROOT)) {
      this.expand(ROOT);
    } else {
      for (const path of this.directories.keys()) {
        const directory = this.directories.get(path);
        if (directory !== undefined) {
          this.watch(path, directory);
          this.list(path, directory);
        }
      }
    }
    if (this.state.query.trim()) { this.queueSearch(this.state.query); }
  }

  private stopWatches(): void {
    this.watching = false;
    for (const directory of this.directories.values()) {
      directory.stop?.();
      directory.stop = undefined;
      directory.again = false;
    }
  }

  private args(path: string): Record<string, Object> { return { 'workspaceFileScopeId': this.sessionId, 'path': path }; }

  private expand(path: string): void {
    const directory: Directory = { children: [], loading: false, again: false, truncated: false };
    this.directories.set(path, directory);
    this.watch(path, directory);
    this.list(path, directory);
  }

  private watch(path: string, directory: Directory): void {
    directory.stop = this.host?.watch('workspaceFiles/changes', this.args(path), {
      onItem: (value: Object): void => {
        if (this.watching && getString(value, 'kind') === 'change') { this.list(path, directory); }
      },
      onError: (): void => {}, onEnd: (): void => {}
    });
  }

  private collapse(path: string): void {
    for (const key of this.directories.keys()) {
      if (key === path || key.startsWith(path + '/')) {
        this.directories.get(key)?.stop?.();
        this.directories.delete(key);
      }
    }
  }

  private async list(path: string, directory: Directory): Promise<void> {
    const host = this.host;
    if (host === undefined || !this.watching || this.directories.get(path) !== directory) { return; }
    if (directory.loading) { directory.again = true; return; }
    directory.loading = true;
    this.rebuildRows();
    this.emit();
    const result = await host.call('workspaceFiles/list', this.args(path));
    if (this.directories.get(path) !== directory) { return; }
    directory.loading = false;
    if (result.ok) {
      const projection = projectWorkspaceListing(result.value, path === ROOT ? '' : path, []);
      directory.children = projection.nodes.filter((file: FileNode): boolean => desktopWorkspaceRelativePath(file.path));
      directory.truncated = projection.truncated;
      for (const key of this.directories.keys()) {
        const parent = key.lastIndexOf('/');
        if (key !== ROOT && (parent < 0 ? ROOT : key.slice(0, parent)) === path &&
          !directory.children.some((node: FileNode): boolean => node.path === key && node.kind === NodeKind.DIRECTORY)) {
          this.collapse(key);
        }
      }
      this.state.notice = '';
    } else {
      this.state.notice = desktopHostProblem(result);
    }
    if (directory.again && this.watching) {
      directory.again = false;
      this.list(path, directory);
    } else {
      this.rebuildRows();
      this.emit();
    }
  }

  private rebuildRows(): void {
    const rows: DesktopFileNavigatorRow[] = [];
    this.append(ROOT, 0, rows);
    this.state.rows = rows;
    this.state.rootLoading = this.directories.get(ROOT)?.loading ?? false;
    this.state.rootTruncated = this.directories.get(ROOT)?.truncated ?? false;
  }

  private append(path: string, depth: number, rows: DesktopFileNavigatorRow[]): void {
    for (const file of this.directories.get(path)?.children ?? []) {
      if (!this.state.preferences.showHidden && file.name.startsWith('.')) { continue; }
      const directory = this.directories.get(file.path);
      rows.push({ path: file.path, name: file.name, directory: file.kind === NodeKind.DIRECTORY, depth: depth,
        expanded: directory !== undefined, loading: directory?.loading ?? false });
      if (directory !== undefined) { this.append(file.path, depth + 1, rows); }
    }
  }

  queueSearch(value: string, force: boolean = false): void {
    this.state.query = value;
    const query = value.trim();
    const preferences = this.state.preferences;
    const request: Record<string, Object> = { 'query': query, 'excludedPaths': enabledDesktopFileSearchPaths(preferences.rules),
      'includeHidden': preferences.showHidden, 'respectGitignore': preferences.respectGitignore };
    const key = query ? JSON.stringify(request) : '';
    if (!this.watching || (!force && key === this.searchKey)) { this.emit(); return; }
    this.searchKey = key;
    this.collapsedResults.clear();
    this.searchScroll = 0;
    this.state.searchNotice = '';
    clearTimeout(this.searchTimer);
    const revision = ++this.searchRevision;
    this.state.searching = query.length > 0;
    if (query) {
      this.searchTimer = setTimeout((): void => { this.search(query, request, revision); }, 230);
    } else {
      this.state.found = undefined;
      this.state.matches = [];
    }
    this.emit();
  }

  private async search(query: string, request: Record<string, Object>, revision: number): Promise<void> {
    const host = this.host;
    if (this.disposed || host === undefined) { return; }
    const result = await host.call('workspaceFiles/search', { 'workspaceFileScopeId': this.sessionId, 'request': request });
    if (revision !== this.searchRevision) { return; }
    this.state.searching = false;
    this.searchScroll = 0;
    this.state.found = result.ok ? desktopFileSearchResults(result.value, query) : undefined;
    this.state.searchNotice = result.ok ? '' : desktopHostProblem(result);
    this.assignMatches();
    this.emit();
  }

  private assignMatches(): void {
    const matches: DesktopFileNavigatorRow[] = [];
    this.appendMatches(this.state.found?.nodes ?? [], 0, matches);
    this.state.matches = matches;
  }

  private appendMatches(nodes: DesktopFileSearchNode[], depth: number, rows: DesktopFileNavigatorRow[]): void {
    for (const node of nodes) {
      if (!this.state.preferences.showHidden && node.name.startsWith('.')) { continue; }
      const expanded = node.directory && !this.collapsedResults.has(node.path);
      rows.push({ path: node.path, name: node.name, directory: node.directory, depth: depth,
        expanded: expanded, loading: false, spans: node.spans });
      if (expanded) { this.appendMatches(node.children, depth + 1, rows); }
    }
  }
}

export function desktopFileNavigatorKey(paneId: string, sessionId: string): string {
  return JSON.stringify([paneId, sessionId]);
}

export class DesktopFileNavigatorBook {
  private readonly owners = new Map<string, Map<string, DesktopFileNavigator>>();

  has(owner: string): boolean { return this.owners.has(owner); }

  get(owner: string, paneId: string, sessionId: string, host: DesktopHostActions | undefined,
    preferences: DesktopFileSearchPreferenceBook | undefined): DesktopFileNavigator {
    let records = this.owners.get(owner);
    if (records === undefined) {
      records = new Map<string, DesktopFileNavigator>();
      this.owners.set(owner, records);
    }
    const key = desktopFileNavigatorKey(paneId, sessionId);
    const previous = records.get(key);
    if (previous !== undefined) { return previous; }
    const created = new DesktopFileNavigator(host, sessionId, preferences);
    records.set(key, created);
    return created;
  }

  retain(owner: string, valid: Set<string>): void {
    const records = this.owners.get(owner);
    if (records === undefined) { return; }
    records.forEach((navigator: DesktopFileNavigator, key: string): void => {
      if (!valid.has(key)) { navigator.dispose(); records.delete(key); }
    });
    if (records.size === 0) { this.owners.delete(owner); }
  }

  clear(): void {
    this.owners.forEach((records: Map<string, DesktopFileNavigator>): void => {
      records.forEach((navigator: DesktopFileNavigator): void => navigator.dispose());
    });
    this.owners.clear();
  }
}
