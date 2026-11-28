import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { FileNode, FilePreview, NodeKind, PreviewKind, previewKindOf, projectWorkspaceListing,
  projectWorkspaceText, WORKSPACE_ROOT_REQUEST_PATH } from 'appstate';
import { getBoolean, getNumber, getString } from 'connection';
import { isSystemPreviewableName, mimeTypeForName, openFileLocation, openSystemPreview, uriFromPath } from 'platform';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { defaultDesktopFileSearchPreferences, enabledDesktopFileSearchPaths } from './DesktopFileSearchModel';
import type { DesktopFileSearchPreferencePatch, DesktopFileSearchPreferences, DesktopFileSearchRule } from './DesktopFileSearchModel';
import type { DesktopFileSearchPreferenceBook } from './DesktopFileSearchPreference';
import { desktopFileSearchResults, desktopWorkspaceRelativePath } from './DesktopFileSearchResults';
import type { DesktopFileNameSpan, DesktopFileSearchNode, DesktopFileSearchResults } from './DesktopFileSearchResults';
import { DESKTOP_FILE_NAVIGATOR_DEFAULT_WIDTH, DesktopFileNavigatorMode, desktopFileNavigatorBounds,
  desktopFileNavigatorMode, desktopFileNavigatorRelativePath } from './DesktopFileNavigatorModel';
import { DesktopFileSearchSettings } from './DesktopFileSearchSettings';
import lazy { DesktopPdfPreview } from './DesktopPdfPreview';
import lazy { DesktopImageFilePreview } from './DesktopImageFilePreview';
import lazy { DesktopHtmlPreview } from './DesktopHtmlPreview';
import { DESKTOP_HTML_PACKAGE_BYTES, desktopIsHtmlFile, readDesktopHtmlFile } from './DesktopHtmlFile';
import type { DesktopHtmlFile } from './DesktopHtmlFile';
import type { DesktopDocumentViewState } from './DesktopDocumentZoomModel';
import { copyDesktopReferenceImage, saveDesktopReferenceFile } from './DesktopReferenceActions';

interface FileRow {
  path: string;
  name: string;
  directory: boolean;
  depth: number;
  expanded: boolean;
  loading: boolean;
  spans?: DesktopFileNameSpan[];
}

export interface DesktopFileNavigation {
  path: string;
  name: string;
}

interface Directory {
  children: FileNode[];
  loading: boolean;
  again: boolean;
  truncated: boolean;
  stop?: () => void;
}

const ROOT: string = WORKSPACE_ROOT_REQUEST_PATH;
const PREVIEW_LINES: number = 400;

function imageName(name: string): boolean {
  return previewKindOf(name, 0) === PreviewKind.IMAGE || name.toLowerCase().endsWith('.bmp');
}

function pdfName(name: string): boolean { return name.toLowerCase().endsWith('.pdf'); }

@Component
export struct DesktopFilesPane {
  host?: DesktopHostActions;
  ability?: common.UIAbilityContext;
  preferenceBook?: DesktopFileSearchPreferenceBook;
  @Prop @Watch('reset') sessionId: string = '';
  @Prop @Watch('bindSearchPreferences') workspaceRoot: string = '';
  @Prop @Watch('searchVisibilityChanged') shown: boolean = true;
  @Prop @Watch('openRequested') requested: DesktopFileNavigation | undefined = undefined;
  @Prop previewOnly: boolean = false;
  @Prop interactiveHtml: boolean = false;
  @Prop viewportWidth: number = 768;
  @Prop focusScope: string = '';
  onHide: () => void = (): void => {};
  onOpenFile?: (path: string, name: string) => void;
  readDocumentView?: () => DesktopDocumentViewState | undefined;
  onDocumentView?: (view: DesktopDocumentViewState) => void;
  onReferenceWorkspaceFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  onAttachWorkspaceFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};

  @State private rows: FileRow[] = [];
  @State private matches: FileRow[] = [];
  @State private query: string = '';
  @State private searchPreferences: DesktopFileSearchPreferences = defaultDesktopFileSearchPreferences();
  @State private searchSettingsOpen: boolean = false;
  @State private draftSearchRules: DesktopFileSearchRule[] = [];
  @State private found: DesktopFileSearchResults | undefined = undefined;
  @State private emptyHintOpen: boolean = false;
  @State private searching: boolean = false;
  @State private rootLoading: boolean = false;
  @State private notice: string = '';
  @State private searchNotice: string = '';
  @State private selected?: FileRow = undefined;
  @State private preview?: FilePreview = undefined;
  @State private htmlFile?: DesktopHtmlFile = undefined;
  @State private sourceHtml: boolean = false;
  @State private previewUri: string = '';
  @State private previewPath: string = '';
  @State private previewAssetVersion: number = 0;
  @State private documentViewState: DesktopDocumentViewState | undefined = undefined;
  @State private previewLoading: boolean = false;
  @State private previewError: string = '';
  @State private rawMarkdown: boolean = false;
  @State private previewWrap: boolean = true;
  @State private previewOffset: number = 1;
  @State private previewLines: number = 0;
  @State private navigatorOpen: boolean = false;
  @State private navigatorRowWidth: number = 0;
  @State private navigatorWidth: number = DESKTOP_FILE_NAVIGATOR_DEFAULT_WIDTH;
  @State private navigatorCurrent: string = '';
  private readonly navigatorScroller: Scroller = new Scroller();
  private navigatorDragWidth: number = 0;
  private revealNavigatorPath: string = '';
  private readonly directories: Map<string, Directory> = new Map<string, Directory>();
  private active: boolean = false;
  private searchTimer: number = -1;
  private searchRevision: number = 0;
  private searchRequestKey: string = '';
  private searchSettingsRoot: string = '';
  private draftChanged: boolean = false;
  private searchTriggerFocused: boolean = false;
  private stopSearchPreferences?: () => void;
  private boundSearchRoot?: string;
  private readonly collapsedResults = new Set<string>();
  private previewRevision: number = 0;
  private previewNeedsRefresh: boolean = false;
  private cancelPreviewWatch?: () => void;

  aboutToAppear(): void {
    this.active = true;
    this.bindSearchPreferences();
    this.reset();
  }

  aboutToDisappear(): void {
    this.closeSearchSettings(false);
    this.active = false;
    this.stopSearchPreferences?.();
    this.stopSearchPreferences = undefined;
    this.boundSearchRoot = undefined;
    this.reset();
  }

  private reset(): void {
    this.closeSearchSettings(false);
    for (const directory of this.directories.values()) {
      directory.stop?.();
    }
    this.directories.clear();
    this.searchRevision++;
    clearTimeout(this.searchTimer);
    this.query = '';
    this.searching = false;
    this.searchNotice = '';
    this.searchRequestKey = '';
    this.found = undefined;
    this.emptyHintOpen = false;
    this.collapsedResults.clear();
    this.rows = [];
    this.matches = [];
    this.rootLoading = false;
    this.notice = '';
    this.navigatorOpen = false;
    this.navigatorCurrent = '';
    this.revealNavigatorPath = '';
    this.closePreview();
    if (this.active && this.sessionId.length > 0) {
      if (!this.previewOnly) { this.expand(ROOT); }
      this.openRequested();
    }
  }

  private openRequested(): void {
    const file = this.requested;
    if (this.active && file !== undefined && file.path.length > 0) {
      if (this.selected?.path === file.path && this.selected?.name === file.name) { return; }
      this.openPreview({ path: file.path, name: file.name, directory: false, depth: 0, expanded: false, loading: false });
      if (this.navigatorOpen) { this.locatePreviewInNavigator(); }
    }
  }

  private args(path: string): Record<string, Object> {
    return { 'workspaceFileScopeId': this.sessionId, 'path': path };
  }

  private expand(path: string): void {
    const directory: Directory = { children: [], loading: false, again: false, truncated: false };
    this.directories.set(path, directory);
    this.watchDirectory(path, directory);
    this.list(path, directory);
  }

  private watchDirectory(path: string, directory: Directory): void {
    directory.stop = this.host?.watch('workspaceFiles/changes', this.args(path), {
      onItem: (value: Object): void => {
        if (getString(value, 'kind') === 'change') {
          this.list(path, directory);
        }
      },
      onError: (): void => {},
      onEnd: (): void => {}
    });
  }

  private collapse(path: string): void {
    for (const key of this.directories.keys()) {
      if (key === path || key.startsWith(path + '/')) {
        this.directories.get(key)?.stop?.();
        this.directories.delete(key);
      }
    }
    this.rebuild();
  }

  private async list(path: string, directory: Directory): Promise<void> {
    const host = this.host;
    if (host === undefined || this.directories.get(path) !== directory) {
      return;
    }
    if (directory.loading) {
      directory.again = true;
      return;
    }
    directory.loading = true;
    this.rebuild();
    const result = await host.call('workspaceFiles/list', this.args(path));
    if (this.directories.get(path) !== directory) {
      return;
    }
    directory.loading = false;
    if (result.ok) {
      const projection = projectWorkspaceListing(result.value, path === ROOT ? '' : path, []);
      directory.children = projection.nodes.filter((file: FileNode): boolean => desktopWorkspaceRelativePath(file.path));
      directory.truncated = projection.truncated;
      const removed: string[] = [];
      for (const key of this.directories.keys()) {
        const parent = key.lastIndexOf('/');
        if (key !== ROOT && (parent < 0 ? ROOT : key.slice(0, parent)) === path &&
          !directory.children.some((node: FileNode): boolean => node.path === key && node.kind === NodeKind.DIRECTORY)) {
          removed.push(key);
        }
      }
      removed.forEach((key: string): void => { this.collapse(key); });
      this.notice = '';
    } else {
      this.notice = desktopHostProblem(result);
    }
    this.rebuild();
    if (directory.again) {
      directory.again = false;
      this.list(path, directory);
    }
    this.revealPreviewFile();
  }

  private append(path: string, depth: number, into: FileRow[]): void {
    const children = this.directories.get(path)?.children ?? [];
    for (const child of children) {
      if (!this.searchPreferences.showHidden && child.name.startsWith('.')) {
        continue;
      }
      const directory = this.directories.get(child.path);
      into.push({
        name: child.name, path: child.path, directory: child.kind === NodeKind.DIRECTORY,
        depth: depth, expanded: directory !== undefined, loading: directory?.loading ?? false
      });
      if (directory !== undefined) {
        this.append(child.path, depth + 1, into);
      }
    }
  }

  private rebuild(): void {
    const next: FileRow[] = [];
    this.append(ROOT, 0, next);
    this.rows = next;
    this.rootLoading = this.directories.get(ROOT)?.loading ?? false;
  }

  private refresh(): void {
    if (this.query.trim()) {
      this.queueSearch(this.query, true);
      return;
    }
    for (const path of this.directories.keys()) {
      const directory = this.directories.get(path);
      if (directory !== undefined) {
        this.list(path, directory);
      }
    }
  }

  private bindSearchPreferences(): void {
    if (!this.active || this.boundSearchRoot === this.workspaceRoot) { return; }
    this.closeSearchSettings(false);
    this.stopSearchPreferences?.();
    this.boundSearchRoot = this.workspaceRoot;
    const root = this.workspaceRoot;
    const book = this.preferenceBook;
    this.applySearchPreferences(book?.get(root) ?? defaultDesktopFileSearchPreferences());
    this.stopSearchPreferences = book?.subscribe(root, (preferences: DesktopFileSearchPreferences): void => {
      if (this.active && this.boundSearchRoot === root) { this.applySearchPreferences(preferences); }
    });
  }

  private applySearchPreferences(preferences: DesktopFileSearchPreferences): void {
    const changedVisibility = preferences.showHidden !== this.searchPreferences.showHidden;
    this.searchPreferences = preferences;
    if (changedVisibility) { this.rebuild(); }
    if (this.query.trim()) { this.queueSearch(this.query); }
  }

  private updateSearchPreferences(patch: DesktopFileSearchPreferencePatch): void {
    const root = this.workspaceRoot;
    if (this.preferenceBook !== undefined && root) {
      if (!this.preferenceBook.update(root, patch)) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_file_results_settings_failed') });
      }
      this.applySearchPreferences(this.preferenceBook.get(root));
    } else {
      this.applySearchPreferences({ rules: patch.rules ?? this.searchPreferences.rules,
        showHidden: patch.showHidden ?? this.searchPreferences.showHidden,
        respectGitignore: patch.respectGitignore ?? this.searchPreferences.respectGitignore });
    }
  }

  private toggleSearchSettings(): void {
    if (this.searchSettingsOpen) { this.closeSearchSettings(true); return; }
    this.searchSettingsRoot = this.workspaceRoot;
    this.draftSearchRules = this.searchPreferences.rules;
    this.draftChanged = false;
    this.searchSettingsOpen = true;
  }

  private closeSearchSettings(refocus: boolean): void {
    if (!this.searchSettingsOpen) { return; }
    this.searchSettingsOpen = false;
    if (this.draftChanged) {
      if (this.workspaceRoot === this.searchSettingsRoot) {
        this.updateSearchPreferences({ rules: this.draftSearchRules });
      } else if (this.searchSettingsRoot) {
        this.preferenceBook?.update(this.searchSettingsRoot, { rules: this.draftSearchRules });
      }
    }
    if (refocus && this.active && this.shown) {
      this.getUIContext().getFocusController().requestFocus(this.fileFocusId('desktopFileSearchSettingsToggle'));
    }
  }

  private searchVisibilityChanged(): void {
    if (this.previewOnly && this.navigatorOpen) {
      if (this.shown) { this.resumePreviewNavigator(); }
      else { this.suspendPreviewNavigator(); }
    } else if (!this.shown) {
      this.closeSearchSettings(false);
      clearTimeout(this.searchTimer);
      this.searchRevision++;
      this.searching = false;
      this.searchRequestKey = '';
    } else if (this.active && this.query.trim() && !this.searchRequestKey) {
      this.queueSearch(this.query);
    }
    if (this.shown && this.active && this.previewNeedsRefresh && this.selected !== undefined) {
      this.loadPreview(this.selected, this.previewOffset);
    }
  }

  private queueSearch(value: string, force: boolean = false): void {
    this.query = value;
    if (!this.active || !this.shown || (this.previewOnly && !this.navigatorOpen)) { return; }
    const query = value.trim();
    const paths = enabledDesktopFileSearchPaths(this.searchPreferences.rules);
    const request: Record<string, Object> = { 'query': query, 'excludedPaths': paths,
      'includeHidden': this.searchPreferences.showHidden, 'respectGitignore': this.searchPreferences.respectGitignore };
    const key = query ? JSON.stringify(request) : '';
    if (!force && key === this.searchRequestKey) { return; }
    this.searchRequestKey = key;
    this.matches = [];
    this.found = undefined;
    this.emptyHintOpen = false;
    this.collapsedResults.clear();
    this.searchNotice = '';
    clearTimeout(this.searchTimer);
    const revision = ++this.searchRevision;
    this.searching = query.length > 0;
    if (query.length > 0) {
      this.searchTimer = setTimeout((): void => { this.search(query, request, revision); }, 230);
    } else if (this.navigatorOpen) {
      this.revealPreviewFile();
    }
  }

  private async search(query: string, request: Record<string, Object>, revision: number): Promise<void> {
    const host = this.host;
    if (!this.active || host === undefined) {
      return;
    }
    const result = await host.call('workspaceFiles/search', { 'workspaceFileScopeId': this.sessionId, 'request': request });
    if (revision !== this.searchRevision) {
      return;
    }
    this.searching = false;
    if (!result.ok) {
      this.searchNotice = desktopHostProblem(result);
      return;
    }
    this.found = desktopFileSearchResults(result.value, query);
    this.rebuildMatches();
  }

  private appendMatches(nodes: DesktopFileSearchNode[], depth: number, rows: FileRow[]): void {
    for (const node of nodes) {
      if (!this.searchPreferences.showHidden && node.name.startsWith('.')) { continue; }
      const expanded = node.directory && !this.collapsedResults.has(node.path);
      rows.push({ path: node.path, name: node.name, directory: node.directory,
        depth: depth, expanded: expanded, loading: false, spans: node.spans });
      if (expanded) { this.appendMatches(node.children, depth + 1, rows); }
    }
  }

  private rebuildMatches(): void {
    const rows: FileRow[] = [];
    this.appendMatches(this.found?.nodes ?? [], 0, rows);
    this.matches = rows;
  }

  private select(row: FileRow): void {
    if (!row.directory) {
      this.openPreview(row);
      return;
    }
    if (this.query.trim()) {
      if (this.collapsedResults.has(row.path)) { this.collapsedResults.delete(row.path); }
      else { this.collapsedResults.add(row.path); }
      this.rebuildMatches();
    } else if (this.directories.has(row.path)) {
      this.revealNavigatorPath = '';
      this.collapse(row.path);
    } else {
      this.expand(row.path);
    }
  }

  private fileFocusId(key: string): string { return key + this.focusScope; }

  private togglePreviewNavigator(): void {
    this.navigatorOpen = !this.navigatorOpen;
    if (this.navigatorOpen) {
      this.resumePreviewNavigator();
    } else {
      this.suspendPreviewNavigator();
      this.getUIContext().getFocusController().requestFocus(this.fileFocusId('desktopFilePreviewNavigatorToggle'));
    }
  }

  private resumePreviewNavigator(): void {
    if (!this.active || !this.shown || !this.workspaceRoot) { return; }
    if (!this.directories.has(ROOT)) {
      this.expand(ROOT);
    } else {
      for (const path of this.directories.keys()) {
        const directory = this.directories.get(path);
        if (directory === undefined || directory.stop !== undefined) { continue; }
        this.watchDirectory(path, directory);
        this.list(path, directory);
      }
    }
    if (this.query.trim() && !this.searchRequestKey) { this.queueSearch(this.query); }
    this.locatePreviewInNavigator();
  }

  private suspendPreviewNavigator(): void {
    this.closeSearchSettings(false);
    clearTimeout(this.searchTimer);
    this.searchRevision++;
    this.searching = false;
    this.searchRequestKey = '';
    for (const directory of this.directories.values()) {
      directory.stop?.();
      directory.stop = undefined;
      directory.again = false;
    }
  }

  private locatePreviewInNavigator(): void {
    this.navigatorCurrent = desktopFileNavigatorRelativePath(this.selected?.path ?? '', this.workspaceRoot);
    this.revealNavigatorPath = this.navigatorCurrent;
    this.revealPreviewFile();
  }

  private revealPreviewFile(): void {
    const path = this.revealNavigatorPath;
    if (!path || !this.active || !this.shown || !this.navigatorOpen || this.query.trim()) { return; }
    const parts = path.split('/');
    let parent = ROOT;
    for (let index = 0; index < parts.length - 1; index++) {
      const level = this.directories.get(parent);
      if (level === undefined || level.loading) { return; }
      const directory = parts.slice(0, index + 1).join('/');
      if ((!this.searchPreferences.showHidden && parts[index].startsWith('.')) ||
        !level.children.some((node: FileNode): boolean => node.path === directory && node.kind === NodeKind.DIRECTORY)) {
        this.revealNavigatorPath = '';
        return;
      }
      if (!this.directories.has(directory)) {
        this.expand(directory);
        return;
      }
      parent = directory;
    }
    if (this.directories.get(parent)?.loading) { return; }
    const index = this.rows.findIndex((row: FileRow): boolean => row.path === path);
    this.revealNavigatorPath = '';
    if (index >= 0) {
      setTimeout((): void => {
        if (this.shown && this.navigatorOpen && this.navigatorCurrent === path && !this.query.trim()) {
          const current = this.rows.findIndex((row: FileRow): boolean => row.path === path);
          if (current >= 0) { this.navigatorScroller.scrollToIndex(current, false, ScrollAlign.AUTO); }
        }
      }, 0);
    }
  }

  private navigatorMode(): DesktopFileNavigatorMode {
    return desktopFileNavigatorMode(this.navigatorRowWidth, this.viewportWidth);
  }

  private navigatorPanelWidth(): number {
    return desktopFileNavigatorBounds(this.navigatorRowWidth, this.navigatorWidth).width;
  }

  private resizePreviewNavigator(width: number): void {
    this.navigatorWidth = desktopFileNavigatorBounds(this.navigatorRowWidth, width).width;
  }

  private navigatorResizeKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    const bounds = desktopFileNavigatorBounds(this.navigatorRowWidth, this.navigatorWidth);
    switch (event.keyCode) {
      case KeyCode.KEYCODE_DPAD_LEFT: this.resizePreviewNavigator(bounds.width + 20); break;
      case KeyCode.KEYCODE_DPAD_RIGHT: this.resizePreviewNavigator(bounds.width - 20); break;
      case KeyCode.KEYCODE_MOVE_HOME: this.resizePreviewNavigator(bounds.minimum); break;
      case KeyCode.KEYCODE_MOVE_END: this.resizePreviewNavigator(bounds.maximum); break;
      default: return false;
    }
    return true;
  }

  private previewNavigatorKey(event: KeyEvent): boolean {
    if (!this.navigatorOpen || this.searchSettingsOpen || event.type !== KeyType.Down ||
      event.keyCode !== KeyCode.KEYCODE_ESCAPE || event.getModifierKeyState?.(['Ctrl']) === true ||
      event.getModifierKeyState?.(['Alt']) === true || event.getModifierKeyState?.(['Shift']) === true) { return false; }
    if (this.query.trim()) {
      this.queueSearch('');
      this.getUIContext().getFocusController().requestFocus(this.fileFocusId('desktopFileSearchInput'));
    } else {
      this.togglePreviewNavigator();
    }
    return true;
  }

  private closePreview(): void {
    this.cancelPreviewWatch?.();
    this.cancelPreviewWatch = undefined;
    this.previewRevision++;
    this.selected = undefined;
    this.preview = undefined;
    this.htmlFile = undefined;
    this.sourceHtml = false;
    this.previewUri = '';
    this.previewPath = '';
    this.previewNeedsRefresh = false;
    this.documentViewState = undefined;
    this.previewError = '';
    this.previewLoading = false;
    this.previewOffset = 1;
    this.previewLines = 0;
  }

  private openPreview(row: FileRow): void {
    this.closePreview();
    this.rawMarkdown = false;
    this.previewWrap = true;
    this.selected = row;
    this.loadPreview(row);
    this.cancelPreviewWatch = this.host?.watch('workspaceFiles/changes', this.args(row.path), {
      onItem: (value: Object): void => {
        if (this.selected?.path === row.path && getString(value, 'kind') === 'change') {
          if (this.shown) { this.loadPreview(row, this.previewOffset); }
          else { this.previewNeedsRefresh = true; }
        }
      },
      onError: (): void => {},
      onEnd: (): void => {}
    });
  }

  private async loadPreview(row: FileRow, offset: number = 1): Promise<void> {
    const host = this.host;
    if (host === undefined) {
      return;
    }
    const revision = ++this.previewRevision;
    this.previewNeedsRefresh = false;
    const visualAsset = pdfName(row.name) || imageName(row.name);
    this.previewLoading = !visualAsset || !this.previewPath;
    this.previewError = '';
    if (desktopIsHtmlFile(row.name) && !this.sourceHtml) {
      this.preview = undefined;
      this.htmlFile = undefined;
      await this.loadHtml(host, row.path, revision);
      return;
    }
    if (visualAsset || (previewKindOf(row.name, 0) === PreviewKind.BINARY && isSystemPreviewableName(row.name))) {
      const result = await host.call('workspaceFiles/stat', this.args(row.path));
      if (revision === this.previewRevision) {
        const path = result.ok ? getString(result.value, 'absolutePath') ?? '' : '';
        this.previewPath = path.startsWith('/') && !path.includes('\0') ? path : '';
        this.previewUri = this.previewPath ? uriFromPath(this.previewPath) : '';
        this.previewAssetVersion++;
        this.previewLoading = false;
        this.previewError = result.ok ? ((pdfName(row.name) ? this.previewPath : this.previewUri) ?
          '' : '系统无法访问此文件') : desktopHostProblem(result);
      }
      return;
    }
    const range: Record<string, Object> = { 'limit': PREVIEW_LINES, 'offset': offset };
    const result = await host.call('workspaceFiles/read', {
      'workspaceFileScopeId': this.sessionId, 'path': row.path, 'range': range
    });
    if (revision === this.previewRevision) {
      this.previewLoading = false;
      if (result.ok) {
        this.previewOffset = offset;
        this.previewLines = getNumber(result.value, 'lines') ?? 0;
        this.preview = projectWorkspaceText(result.value, row.path, row.name, 0);
      } else {
        this.preview = undefined;
        this.previewError = desktopHostProblem(result);
      }
    }
  }

  private async loadHtml(host: DesktopHostActions, path: string, revision: number): Promise<void> {
    let file: DesktopHtmlFile | undefined;
    try { file = await readDesktopHtmlFile(host, this.sessionId, path, DESKTOP_HTML_PACKAGE_BYTES); } catch (_) {}
    if (!this.active || revision !== this.previewRevision) { return; }
    this.htmlFile = file;
    this.previewAssetVersion++;
    this.previewLoading = false;
  }

  private toggleHtmlSource(): void {
    const selected = this.selected;
    if (selected === undefined) { return; }
    this.sourceHtml = !this.sourceHtml;
    this.htmlFile = undefined;
    this.preview = undefined;
    this.loadPreview(selected);
  }

  private async openSystem(row: FileRow): Promise<void> {
    const ability = this.ability;
    if (ability === undefined || !(await openSystemPreview(ability, this.previewUri, row.name, mimeTypeForName(row.name)))) {
      this.getUIContext().getPromptAction().showToast({ message: '系统未能打开此文件的预览' });
    }
  }

  private documentView(): DesktopDocumentViewState | undefined {
    return this.readDocumentView?.() ?? this.documentViewState;
  }

  private saveDocumentView(view: DesktopDocumentViewState): void {
    if (this.shown && this.selected !== undefined) {
      this.documentViewState = view;
      this.onDocumentView?.(view);
    }
  }

  private async previewFileAction(row: FileRow, copyImage: boolean): Promise<void> {
    const session = this.sessionId;
    const ability = this.ability;
    if (ability === undefined || !this.active) { return; }
    const stat = await this.host?.call('workspaceFiles/stat', this.args(row.path));
    if (!this.active || this.sessionId !== session) { return; }
    const path = stat?.ok ? getString(stat.value, 'absolutePath') ?? '' : '';
    if (!path.startsWith('/') || path.includes('\0')) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_file_preview_action_failed') });
      return;
    }
    try {
      if (copyImage) { await copyDesktopReferenceImage(path); }
      else { await saveDesktopReferenceFile(ability, path, row.name); }
    } catch (_) {
      if (this.active && this.sessionId === session) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_file_preview_action_failed') });
      }
    }
  }

  private searchEmptyHint(): ResourceStr {
    const hidden = !this.searchPreferences.showHidden;
    const excluded = this.searchPreferences.rules.some((rule: DesktopFileSearchRule): boolean => rule.enabled);
    const ignored = this.searchPreferences.respectGitignore;
    if (hidden && excluded) {
      return ignored ? $r('app.string.desktop_file_results_hint_all') : $r('app.string.desktop_file_results_hint_both');
    }
    if (hidden) {
      return ignored ? $r('app.string.desktop_file_results_hint_hidden_ignored') : $r('app.string.desktop_file_results_hint_hidden');
    }
    if (excluded) {
      return ignored ? $r('app.string.desktop_file_results_hint_excluded_ignored') : $r('app.string.desktop_file_results_hint_excluded');
    }
    return ignored ? $r('app.string.desktop_file_results_hint_ignored') : '';
  }

  @Builder
  private SearchSettingsPopup() {
    Column() {
      DesktopFileSearchSettings({ rules: this.draftSearchRules, respectGitignore: this.searchPreferences.respectGitignore,
        maxListHeight: 310, onChange: (rules: DesktopFileSearchRule[]): void => {
          this.draftSearchRules = rules;
          this.draftChanged = true;
        }, onRespectGitignore: (value: boolean): void => { this.updateSearchPreferences({ respectGitignore: value }); },
        onClose: (refocus: boolean): void => { this.closeSearchSettings(refocus); },
        isTriggerFocused: (): boolean => this.searchTriggerFocused })
    }.width(328).constraintSize({ maxWidth: '100%' })
  }

  @Builder
  private SearchBar() {
    Row({ space: 3 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_workspace_search_outline')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
      }.key('desktopFileSearchSettingsToggle').id(this.fileFocusId('desktopFileSearchSettingsToggle'))
        .width(30).height(32).padding(0).borderRadius(7)
        .accessibilityText($r('app.string.desktop_file_search_settings_trigger')).accessibilitySelected(this.searchSettingsOpen)
        .onFocus((): void => { this.searchTriggerFocused = true; })
        .onBlur((): void => { this.searchTriggerFocused = false; })
        .focusOnTouch(false).onClick((): void => { this.toggleSearchSettings(); })
        .bindPopup(this.searchSettingsOpen, { builder: this.SearchSettingsPopup(), placement: Placement.BottomLeft,
          enableArrow: false, focusable: true, autoCancel: true, mask: false,
          systemMaterial: desktopMenuOptions(Placement.BottomLeft).systemMaterial,
          onStateChange: (event): void => { if (!event.isVisible) { this.closeSearchSettings(false); } } })
      TextInput({ text: this.query, placeholder: $r('app.string.desktop_file_results_placeholder') })
        .key('desktopFileSearchInput').id(this.fileFocusId('desktopFileSearchInput'))
        .height(32).layoutWeight(1).backgroundColor(Color.Transparent)
        .padding({ left: 1, right: 1 }).onChange((value: string): void => { this.queueSearch(value); })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE && this.query) {
            this.queueSearch('');
            return true;
          }
          return false;
        })
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image(this.searchPreferences.showHidden ? $r('app.media.dsh_secret_eye') : $r('app.media.dsh_secret_eye_off'))
          .width(16).height(16).supportSvg2(true).accessibilityLevel('no')
      }.key('desktopFileSearchHidden').width(30).height(32).padding(0).borderRadius(7)
        .accessibilityText($r('app.string.desktop_file_results_hidden')).accessibilitySelected(this.searchPreferences.showHidden)
        .focusOnTouch(false).onClick((): void => { this.updateSearchPreferences({ showHidden: !this.searchPreferences.showHidden }); })
      if (this.query) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_workspace_search_clear')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.key('desktopFileSearchClear').width(28).height(32).padding(0).borderRadius(7)
          .accessibilityText($r('app.string.desktop_file_results_clear')).focusOnTouch(false)
          .onClick((): void => {
            this.queueSearch('');
            this.getUIContext().getFocusController().requestFocus(this.fileFocusId('desktopFileSearchInput'));
          })
      }
    }.width('100%').padding({ left: 2, right: 2 }).borderRadius(8)
      .backgroundColor($r('app.color.workspace_panel'))
  }

  @Builder
  private EmptyHintPopup() {
    Text(this.searchEmptyHint()).fontSize(12).padding(10).constraintSize({ maxWidth: 280 })
      .fontColor($r('sys.color.font_primary'))
  }

  @Builder
  private SearchStatus() {
    if (this.searchNotice) {
      Column({ space: 4 }) {
        Text($r('app.string.desktop_file_results_failed', this.searchNotice)).fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Button($r('app.string.desktop_file_results_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopFileSearchRetry').height(28).onClick((): void => { this.queueSearch(this.query, true); })
      }.alignItems(HorizontalAlign.Start).width('100%').padding(8)
    } else if (this.found !== undefined) {
      Text($r('app.string.desktop_file_results_count', String(this.found.count))).key('desktopFileSearchCount')
        .fontSize(12).fontColor($r('sys.color.font_secondary')).padding({ left: 10, top: 2, bottom: 3 })
      if (this.found.count === 0) {
        Row({ space: 6 }) {
          Text($r('app.string.desktop_file_results_empty')).key('desktopFileSearchEmpty')
            .fontSize(13).fontColor($r('sys.color.font_secondary'))
          if (this.searchEmptyHint() !== '') {
            Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Image($r('app.media.dsh_file_search_info')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
            }.key('desktopFileSearchEmptyHint').width(26).height(26).padding(0).borderRadius(6)
              .accessibilityText($r('app.string.desktop_file_results_hint_label')).focusOnTouch(false)
              .onClick((): void => { this.emptyHintOpen = !this.emptyHintOpen; })
              .bindPopup(this.emptyHintOpen, { builder: this.EmptyHintPopup(), placement: Placement.Bottom,
                enableArrow: false, systemMaterial: desktopMenuOptions(Placement.Bottom).systemMaterial,
                onStateChange: (event): void => { if (!event.isVisible) { this.emptyHintOpen = false; } } })
          }
        }.padding({ left: 10, top: 6 })
      }
    }
  }

  private fileOptions(row: FileRow): MenuElement[] {
    const items: MenuElement[] = [
      { value: '复制相对路径', action: (): void => {
        pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, row.path))
          .catch((): void => { this.getUIContext().getPromptAction().showToast({ message: '无法复制路径' }); });
      } }
    ];
    if (!row.directory) {
      items.push({ value: '添加到对话', action: (): void => { this.onReferenceWorkspaceFile(row.path, row.name); } });
      items.push({ value: '添加为附件', action: (): void => { this.onAttachWorkspaceFile(row.path, row.name); } });
    }
    if (!row.directory && this.ability !== undefined) {
      items.push({ value: '在文件夹中显示', action: (): void => { this.revealFile(row); } });
      if (this.selected?.path === row.path && this.previewUri) {
        items.push({ value: $r('app.string.desktop_file_preview_system'), action: (): void => { this.openSystem(row); } });
        items.push({ value: $r('app.string.desktop_file_preview_save'), action: (): void => { this.previewFileAction(row, false); } });
        if (imageName(row.name)) {
          items.push({ value: $r('app.string.desktop_file_preview_copy_image'), action: (): void => {
            this.previewFileAction(row, true);
          } });
        }
      }
    }
    return items;
  }

  private async revealFile(row: FileRow): Promise<void> {
    const result = await this.host?.call('workspaceFiles/stat', this.args(row.path));
    const path = getString(result?.value, 'absolutePath') ?? '';
    if (!path.startsWith('/') || !this.active || this.ability === undefined ||
      openFileLocation(this.ability, path) !== 'ok') {
      this.getUIContext().getPromptAction().showToast({ message: '无法在系统文件中定位' });
    }
  }

  @Builder
  private FileLine(row: FileRow) {
    Row({ space: 5 }) {
      if (row.directory) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11)
          .rotate({ angle: row.expanded ? 90 : 0 }).fontColor([$r('sys.color.font_secondary')])
        SymbolGlyph($r('sys.symbol.folder')).fontSize(15).fontColor([$r('sys.color.font_secondary')])
      } else {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(15).fontColor([$r('sys.color.font_secondary')])
      }
      Column({ space: 2 }) {
        if (row.spans !== undefined) {
          Text() {
            ForEach(row.spans, (span: DesktopFileNameSpan): void => {
              if (span.highlight) {
                Span(span.text).textBackgroundStyle({ color: $r('app.color.workspace_selection'), radius: 3 })
              } else {
                Span(span.text)
              }
            }, (_span: DesktopFileNameSpan, index: number): string => String(index))
          }.fontSize(14).fontColor($r('sys.color.font_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        } else {
          Text(row.name).fontSize(14).fontColor($r('sys.color.font_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (row.loading) {
        LoadingProgress().width(14).height(14)
      }
      Button('⋯', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(30).height(30).padding(0)
        .accessibilityText(row.name + '操作').bindMenu(this.fileOptions(row), desktopMenuOptions(Placement.BottomRight))
    }
    .key((row.spans === undefined ? 'desktopWorkspaceFile-' : 'desktopFileSearchResult-') + row.path)
    .width('100%').constraintSize({ minHeight: 34 }).padding({ left: 10 + Math.min(row.depth, 12) * 12, right: 8 })
    .borderRadius(8).backgroundColor(this.navigatorCurrent === row.path ?
      $r('app.color.workspace_selection') : Color.Transparent)
    .accessibilitySelected(this.navigatorCurrent === row.path)
    .onClick((): void => {
      if (row.directory || this.onOpenFile === undefined) { this.select(row); }
      else { this.onOpenFile(row.path, row.name); }
    })
  }

  private rowKey(row: FileRow): string {
    const view = row.spans === undefined ? '' : this.query.trim() + ':';
    return `${view}${row.path}:${row.depth}:${row.directory}:${row.expanded}:${row.loading}`;
  }

  @Builder
  private PreviewPager() {
    Row({ space: 6 }) {
      Button('上一页', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(this.previewOffset > 1)
        .onClick((): void => {
          const row = this.selected;
          if (row !== undefined) {
            this.loadPreview(row, Math.max(1, this.previewOffset - PREVIEW_LINES));
          }
        })
      Text(this.previewLines > 0 ? '第 ' + this.previewOffset + '–' +
        (this.previewOffset + this.previewLines - 1) + ' 行' : '无内容')
        .fontSize(12).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      Button('下一页', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(this.preview?.truncated === true && this.previewLines > 0).onClick((): void => {
          const row = this.selected;
          if (row !== undefined) {
            this.loadPreview(row, this.previewOffset + this.previewLines);
          }
        })
    }
    .width('100%').padding({ left: 8, right: 8 })
  }

  @Builder
  private PreviewBody() {
    if (this.previewLoading) {
      LoadingProgress().width(25).height(25).margin(15)
    } else if (this.previewError) {
      Text(this.previewError).fontSize(13).fontColor($r('sys.color.warning')).padding(12)
    } else if (desktopIsHtmlFile(this.selected?.name ?? '') && !this.sourceHtml) {
      if (this.htmlFile === undefined) {
        Text($r('app.string.desktop_html_preview_failed')).key('desktopHtmlPreviewProblem')
          .fontSize(13).fontColor($r('sys.color.warning')).padding(14)
      } else if (this.shown) {
        Column() {
          ForEach([`${this.sessionId}:${this.workspaceRoot}:${this.previewAssetVersion}:${this.interactiveHtml}`],
            (_key: string): void => {
              DesktopHtmlPreview({ host: this.host, file: this.htmlFile, sessionId: this.sessionId,
                workspaceRoot: this.workspaceRoot, interactive: this.interactiveHtml })
            }, (key: string): string => key)
        }.width('100%').layoutWeight(1)
      }
    } else if (this.previewPath && pdfName(this.selected?.name ?? '')) {
      Column() {
        DesktopPdfPreview({ path: this.previewPath, active: this.shown, initialView: this.documentView(),
          ownerKey: this.sessionId + ':' + this.previewAssetVersion,
          onViewChange: (view: DesktopDocumentViewState): void => { this.saveDocumentView(view); }, onOpenSystem: (): void => {
            if (this.selected !== undefined) { this.openSystem(this.selected); }
          } })
      }.width('100%').layoutWeight(1)
    } else if (this.previewUri && imageName(this.selected?.name ?? '')) {
      Column() {
        DesktopImageFilePreview({ source: this.previewUri, name: this.selected?.name ?? '', active: this.shown,
          revision: this.previewAssetVersion, initialView: this.documentView(),
          onViewChange: (view: DesktopDocumentViewState): void => { this.saveDocumentView(view); } })
      }.width('100%').layoutWeight(1)
    } else if (this.previewUri) {
      Button($r('app.string.desktop_file_preview_system'), { buttonStyle: ButtonStyleMode.TEXTUAL }).margin(10)
        .onClick((): void => {
          const row = this.selected;
          if (row !== undefined) {
            this.openSystem(row);
          }
        })
    } else if (this.preview !== undefined) {
      if (this.preview.truncated || this.previewOffset > 1) {
        this.PreviewPager()
      }
      Scroll() {
        Column({ space: 8 }) {
          if (this.preview.kind === PreviewKind.MARKDOWN && !this.rawMarkdown) {
            MarkdownRenderer({ text: this.preview.text })
          } else if (this.previewWrap) {
            Text(this.preview.text).fontSize(13).fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
              .key('desktopFilePreviewWrapped').width('100%')
          } else {
            Scroll() {
              Text(this.preview.text).fontSize(13).fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
            }.key('desktopFilePreviewUnwrapped').width('100%').scrollable(ScrollDirection.Horizontal)
              .align(Alignment.TopStart).scrollBar(BarState.Auto)
          }
        }
        .alignItems(HorizontalAlign.Start).padding(12).width('100%')
      }
      .align(Alignment.TopStart).width('100%').layoutWeight(1)
    }
  }

  @Builder
  private FileNavigatorContents() {
    Column() {
      Column() { this.SearchBar() }.width('100%').padding(8)
      if (this.searching || (!this.query.trim() && this.rootLoading && this.rows.length === 0)) {
        LoadingProgress().width(22).height(22).margin(6)
      }
      if (this.query.trim()) {
        this.SearchStatus()
      } else if (this.notice) {
        Text(this.notice).fontSize(12).fontColor($r('sys.color.warning')).padding(8)
      }
      if (!this.query.trim() && this.directories.get(ROOT)?.truncated) {
        Text('工作区文件列表已截断').fontSize(12).padding(8)
      }
      if (!this.query.trim() && !this.rootLoading && this.rows.length === 0 && !this.notice) {
        Text('工作区没有文件').fontSize(13).fontColor($r('sys.color.font_secondary')).padding(12)
      }
      List({ scroller: this.navigatorScroller }) {
        ForEach(this.query.trim() ? this.matches : this.rows, (row: FileRow): void => {
          ListItem() { this.FileLine(row) }
        }, (row: FileRow): string => this.rowKey(row))
        if (this.query.trim() && this.found?.truncated) {
          ListItem() {
            Text($r('app.string.desktop_file_results_truncated', String(this.found.count))).fontSize(12)
              .fontColor($r('sys.color.font_secondary')).padding(8)
          }
        }
        if (this.query.trim() && this.found?.incomplete) {
          ListItem() {
            Text($r('app.string.desktop_file_results_incomplete')).fontSize(12)
              .fontColor($r('sys.color.font_secondary')).padding(8)
          }
        }
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%')
  }

  @Builder
  private PreviewNavigatorResize() {
    Column().width(8).height('100%').backgroundColor(Color.Transparent).focusable(true)
      .key('desktopFilePreviewNavigatorResize').accessibilityText($r('app.string.desktop_file_navigator_resize'))
      .onKeyEvent((event: KeyEvent): boolean => this.navigatorResizeKey(event))
      .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart((): void => { this.navigatorDragWidth = this.navigatorPanelWidth(); })
        .onActionUpdate((event: GestureEvent): void => {
          this.resizePreviewNavigator(this.navigatorDragWidth - event.offsetX);
        }))
  }

  @Builder
  private PreviewWithNavigator() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row() {
        Column() { this.PreviewBody() }
          .width(this.navigatorOpen && this.navigatorMode() === DesktopFileNavigatorMode.PUSH ?
            this.navigatorRowWidth - this.navigatorPanelWidth() - 16 : '100%').height('100%')
          .visibility(this.navigatorOpen && this.navigatorMode() === DesktopFileNavigatorMode.FILL ?
            Visibility.Hidden : Visibility.Visible)
      }.width('100%').height('100%')
      if (this.navigatorOpen) {
        Row() {
          if (this.navigatorMode() !== DesktopFileNavigatorMode.FILL) {
            this.PreviewNavigatorResize()
          }
          Column() { this.FileNavigatorContents() }
            .key('desktopFilePreviewNavigator').height('100%')
            .width(this.navigatorMode() === DesktopFileNavigatorMode.FILL ? '100%' : this.navigatorPanelWidth())
            .backgroundColor(this.navigatorMode() === DesktopFileNavigatorMode.FILL ?
              $r('app.color.workspace_canvas') : $r('app.color.workspace_panel'))
            .borderRadius(this.navigatorMode() === DesktopFileNavigatorMode.FILL ? 0 : 12)
            .border({ width: this.navigatorMode() === DesktopFileNavigatorMode.FILL ? 0 : 1,
              color: $r('app.color.workspace_border') })
            .shadow(this.navigatorMode() === DesktopFileNavigatorMode.FILL ?
              { radius: 0 } : { radius: 15, color: '#33000000', offsetY: 4 })
        }.height('100%')
          .padding(this.navigatorMode() === DesktopFileNavigatorMode.FILL ? 0 : { top: 8, right: 8, bottom: 8 })
      }
    }.width('100%').layoutWeight(1).onSizeChange((_previous: SizeOptions, current: SizeOptions): void => {
      const next = Number(current.width);
      if (next > 0 && next !== this.navigatorRowWidth) { this.navigatorRowWidth = next; }
    }).onKeyEvent((event: KeyEvent): boolean => this.previewNavigatorKey(event))
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        if (this.selected !== undefined && !this.previewOnly) {
          Button('‹', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(32).padding(0)
            .accessibilityText('返回文件列表').onClick((): void => { this.closePreview(); })
        }
        Text(this.selected?.name ?? '工作区文件').fontSize(14).fontWeight(FontWeight.Medium)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.selected !== undefined) {
          if (desktopIsHtmlFile(this.selected.name)) {
            Button(this.sourceHtml ? $r('app.string.desktop_html_preview_rendered') :
              $r('app.string.desktop_html_preview_source'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopHtmlPreviewSource').onClick((): void => { this.toggleHtmlSource(); })
          }
          if (this.preview?.kind === PreviewKind.MARKDOWN) {
            Button(this.rawMarkdown ? '预览' : '源码', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick((): void => { this.rawMarkdown = !this.rawMarkdown; })
          }
          if (this.preview !== undefined && (this.preview.kind !== PreviewKind.MARKDOWN || this.rawMarkdown)) {
            Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Image(this.previewWrap ? $r('app.media.dsh_file_preview_nowrap') : $r('app.media.dsh_file_preview_wrap'))
                .width(15).height(15).supportSvg2(true).accessibilityLevel('no')
            }.key('desktopFilePreviewWrap').width(30).height(30).padding(0).borderRadius(7)
              .accessibilityText($r('app.string.desktop_file_preview_wrap')).accessibilitySelected(this.previewWrap)
              .onClick((): void => { this.previewWrap = !this.previewWrap; })
          }
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_browser_refresh_outline')).width(15).height(15).supportSvg2(true).accessibilityLevel('no')
          }.key('desktopFilePreviewReload').width(30).height(30).padding(0).borderRadius(7).enabled(!this.previewLoading)
            .accessibilityText($r('app.string.desktop_file_preview_reload')).onClick((): void => {
              if (this.selected !== undefined) { this.loadPreview(this.selected, this.previewOffset); }
            })
          Button('⋯', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(36).padding(0)
            .bindMenu(this.fileOptions(this.selected), desktopMenuOptions(Placement.BottomRight))
          if (this.previewOnly && this.workspaceRoot) {
            Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Image(this.navigatorOpen ? $r('app.media.dsh_sidebar_folder_open') : $r('app.media.dsh_sidebar_workspace'))
                .width(16).height(16).supportSvg2(true).accessibilityLevel('no')
            }.key('desktopFilePreviewNavigatorToggle').id(this.fileFocusId('desktopFilePreviewNavigatorToggle'))
              .width(30).height(30).padding(0).borderRadius(7).accessibilitySelected(this.navigatorOpen)
              .accessibilityText(this.navigatorOpen ? $r('app.string.desktop_file_navigator_hide') :
                $r('app.string.desktop_file_navigator_show'))
              .onClick((): void => { this.togglePreviewNavigator(); })
          }
        } else {
          Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.refresh(); })
        }
        Button('×', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(32).padding(0)
          .accessibilityText('关闭文件面板').onClick(this.onHide)
      }
      .height(42).padding({ left: 9, right: 4 }).width('100%')
      .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      if (this.selected !== undefined) {
        if (this.previewOnly) { this.PreviewWithNavigator() }
        else { this.PreviewBody() }
      } else {
        Column() { this.FileNavigatorContents() }.width('100%').layoutWeight(1)
      }
    }
    .height('100%').width('100%').backgroundColor($r('app.color.workspace_canvas'))
    .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }
}
