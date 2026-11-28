import { common } from '@kit.AbilityKit';
import { taskpool } from '@kit.ArkTS';
import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { FilePreview, PreviewKind, previewKindOf, projectWorkspaceText } from 'appstate';
import { getArray, getBoolean, getField, getNumber, getRecord, getString, parseJson } from 'connection';
import { isSystemPreviewableName, mimeTypeForName, openFileLocation, openSystemPreview, uriFromPath } from 'platform';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopFileSearchPreferencePatch, DesktopFileSearchRule } from './DesktopFileSearchModel';
import { DesktopFileSearchPreferenceBook } from './DesktopFileSearchPreference';
import { DesktopFileNameSpan } from './DesktopFileSearchResults';
import { DesktopFileNavigatorMode, desktopFileNavigatorBounds,
  desktopFileNavigatorMode, desktopFileNavigatorRelativePath } from './DesktopFileNavigatorModel';
import { DESKTOP_FILE_REVEAL_PENDING, DesktopFileNavigator, DesktopFileNavigatorBook,
  DesktopFileNavigatorLink, DesktopFileNavigatorRow, DesktopFileNavigatorView,
  emptyDesktopFileNavigatorView } from './DesktopFileNavigator';
import { DesktopFileSearchSettings } from './DesktopFileSearchSettings';
import { desktopFileTypeIcon } from './DesktopFileType';
import { DESKTOP_TABLE_MAX_BYTES, DESKTOP_TABLE_MAX_CELLS, DESKTOP_TABLE_TIMEOUT_MS,
  DesktopDelimitedTable, desktopDelimitedFormat } from './DesktopDelimitedTable';
import { parseDesktopDelimitedBytes } from './DesktopDelimitedWorker';
import lazy { DesktopDelimitedPreview } from './DesktopDelimitedPreview';
import { DesktopWorkbook, desktopWorkbookFormat, readDesktopWorkbook } from './DesktopWorkbookModel';
import lazy { DesktopWorkbookPreview } from './DesktopWorkbookPreview';
import { DesktopFileContextAction, DesktopFileContextItem, desktopFileContextCopyPath, desktopFileContextPathItems,
  desktopFileContextTransferItems } from './DesktopFileContextModel';
import lazy { DesktopPdfPreview } from './DesktopPdfPreview';
import lazy { DesktopImageFilePreview } from './DesktopImageFilePreview';
import lazy { DesktopHtmlPreview } from './DesktopHtmlPreview';
import { DESKTOP_HTML_PACKAGE_BYTES, desktopIsHtmlFile, readDesktopHtmlFile } from './DesktopHtmlFile';
import type { DesktopHtmlFile } from './DesktopHtmlFile';
import type { DesktopDocumentViewState } from './DesktopDocumentZoomModel';
import { copyDesktopReferenceImage, openDesktopReferenceFile, saveDesktopReferenceFile } from './DesktopReferenceActions';
import { DesktopReferenceSource } from './DesktopReferenceActions';

export interface DesktopFileNavigation {
  path: string;
  name: string;
}

interface WorkspaceFileMenuTarget {
  key: string;
  path: string;
  name: string;
  directory: boolean;
}

interface WorkspaceFileMenu {
  target: WorkspaceFileMenuTarget;
  session: string;
  serial: number;
  authorized: string;
  copyPath: string;
  offset: Position;
}

const PREVIEW_LINES: number = 400;
const FILE_ROW_HEIGHT: number = 34;
const FILE_HEADER_HEIGHT: number = 42;

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
  navigatorBook?: DesktopFileNavigatorBook;
  @Prop @Watch('watchNavigator') navigatorLink: DesktopFileNavigatorLink | undefined = undefined;
  @Prop @Watch('searchVisibilityChanged') shown: boolean = true;
  @Prop @Watch('openRequested') requested: DesktopFileNavigation | undefined = undefined;
  @Prop previewOnly: boolean = false;
  @Prop interactiveHtml: boolean = false;
  @Prop viewportWidth: number = 768;
  @Prop focusScope: string = '';
  onHide: () => void = (): void => {};
  onOpenFile?: (path: string, name: string) => void;
  onOpenFileIn?: (path: string, name: string, floating: boolean) => void;
  @Prop canReferenceWorkspaceFile: boolean = false;
  readDocumentView?: () => DesktopDocumentViewState | undefined;
  onDocumentView?: (view: DesktopDocumentViewState) => void;
  onReferenceWorkspaceFile: (absolutePath: string) => void = (_absolutePath: string): void => {};

  @State private navigatorView: DesktopFileNavigatorView = emptyDesktopFileNavigatorView();
  @State private searchSettingsOpen: boolean = false;
  @State private draftSearchRules: DesktopFileSearchRule[] = [];
  @State private emptyHintOpen: boolean = false;
  @State private selected?: DesktopFileNavigatorRow = undefined;
  @State private preview?: FilePreview = undefined;
  @State private htmlFile?: DesktopHtmlFile = undefined;
  @State private delimitedTable?: DesktopDelimitedTable = undefined;
  @State private workbook?: DesktopWorkbook = undefined;
  @State private delimitedProblem: string = '';
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
  @State private navigatorRowWidth: number = 0;
  @State private navigatorCurrent: string = '';
  @State private fileMenu?: WorkspaceFileMenu = undefined;
  private fileMenuSerial: number = 0;
  private fileMenuRequestKey: string = '';
  private pendingFileAction?: DesktopFileContextAction;
  private readonly navigatorScroller: Scroller = new Scroller();
  private navigatorDragWidth: number = 0;
  private revealNavigatorPath: string = '';
  private active: boolean = false;
  private navigatorBinding?: DesktopFileNavigator;
  private navigatorRoot: string = '';
  private navigatorListening?: () => void;
  private navigatorRelease?: () => void;
  private navigatorHolding: boolean = false;
  private searchSettingsRoot: string = '';
  private draftChanged: boolean = false;
  private searchTriggerFocused: boolean = false;
  private previewRevision: number = 0;
  private delimitedTask?: taskpool.Task;
  private delimitedTimer: number = -1;
  private previewNeedsRefresh: boolean = false;
  private cancelPreviewWatch?: () => void;

  aboutToAppear(): void {
    this.active = true;
    this.reset();
  }

  aboutToDisappear(): void {
    this.stopNavigator();
    this.active = false;
    this.closePreview();
  }

  private reset(): void {
    this.stopNavigator();
    this.navigatorView = emptyDesktopFileNavigatorView();
    this.navigatorCurrent = '';
    this.revealNavigatorPath = '';
    this.closePreview();
    if (this.active && this.sessionId) {
      this.openRequested();
      this.watchNavigator();
    }
  }

  private openRequested(): void {
    const file = this.requested;
    if (this.active && file !== undefined && file.path.length > 0) {
      if (this.selected?.path === file.path && this.selected?.name === file.name) { return; }
      this.openPreview({ path: file.path, name: file.name, directory: false, depth: 0, expanded: false, loading: false });
      if (this.navigatorView.open) { this.locatePreviewInNavigator(); }
    }
  }

  private args(path: string): Record<string, Object> {
    return { 'workspaceFileScopeId': this.sessionId, 'path': path };
  }

  private fileRoot(): string { return this.navigatorLink?.root ?? ''; }

  private watchNavigator(): void {
    const link = this.navigatorLink;
    const book = this.navigatorBook;
    if (!this.active || !this.shown || link === undefined || !link.owner || !link.sessionId || book === undefined) {
      this.stopNavigator();
      return;
    }
    const navigator = book.get(link.owner, link.paneId, link.sessionId, this.host, this.preferenceBook);
    if (navigator === this.navigatorBinding) {
      if (this.navigatorRoot === link.root) { return; }
      if (this.searchSettingsOpen && this.searchSettingsRoot !== link.root) { this.closeSearchSettings(false); }
      this.navigatorRoot = link.root;
      navigator.setWorkspaceRoot(link.root);
      if (this.previewOnly && this.navigatorView.open) { this.locatePreviewInNavigator(); }
      return;
    }
    this.stopNavigator();
    this.navigatorBinding = navigator;
    this.navigatorRoot = link.root;
    navigator.setWorkspaceRoot(link.root);
    this.navigatorListening = navigator.subscribe((view: DesktopFileNavigatorView): void => { this.drawNavigator(view); });
    this.drawNavigator(navigator.snapshot());
  }

  private stopNavigator(): void {
    this.cancelFileMenu();
    this.closeSearchSettings(false);
    this.navigatorListening?.();
    this.navigatorListening = undefined;
    this.navigatorHolding = false;
    this.navigatorRelease?.();
    this.navigatorRelease = undefined;
    this.navigatorBinding = undefined;
    this.navigatorRoot = '';
  }

  private drawNavigator(view: DesktopFileNavigatorView): void {
    const previous = this.navigatorView;
    this.navigatorView = view;
    if (previous.query !== view.query || previous.found !== view.found) { this.emptyHintOpen = false; }
    const holding = this.navigatorBinding !== undefined && (view.open || !this.previewOnly);
    if (holding !== this.navigatorHolding) {
      this.navigatorHolding = holding;
      if (holding) {
        this.restoreNavigatorScroll(!!view.query.trim());
        this.navigatorRelease = this.navigatorBinding?.hold();
        if (this.previewOnly) { this.locatePreviewInNavigator(); }
      } else {
        this.navigatorRelease?.();
        this.navigatorRelease = undefined;
      }
    } else if (holding) {
      const searching = !!view.query.trim();
      if (!!previous.query.trim() !== searching || (searching && previous.searching && !view.searching)) {
        this.restoreNavigatorScroll(searching);
      }
    }
    this.revealPreviewFile();
  }

  private restoreNavigatorScroll(search: boolean): void {
    const navigator = this.navigatorBinding;
    if (navigator === undefined) { return; }
    const offset = navigator.scrollOffset(search);
    setTimeout((): void => {
      if (navigator === this.navigatorBinding && this.navigatorHolding && search === !!this.navigatorView.query.trim()) {
        this.navigatorScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
      }
    }, 0);
  }

  private captureNavigatorScroll(): void {
    if (this.navigatorHolding) {
      this.navigatorBinding?.saveScroll(!!this.navigatorView.query.trim(), this.navigatorScroller.currentOffset().yOffset);
    }
  }

  private refresh(): void { this.navigatorBinding?.refresh(); }

  private updateSearchPreferences(patch: DesktopFileSearchPreferencePatch): void {
    if (this.navigatorBinding?.updatePreferences(patch) === false) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_file_results_settings_failed') });
    }
  }

  private toggleSearchSettings(): void {
    if (this.searchSettingsOpen) { this.closeSearchSettings(true); return; }
    this.searchSettingsRoot = this.fileRoot();
    this.draftSearchRules = this.navigatorView.preferences.rules;
    this.draftChanged = false;
    this.searchSettingsOpen = true;
  }

  private closeSearchSettings(refocus: boolean): void {
    if (!this.searchSettingsOpen) { return; }
    this.searchSettingsOpen = false;
    if (this.draftChanged) {
      if (this.fileRoot() === this.searchSettingsRoot) {
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
    this.watchNavigator();
    if (this.shown && this.active && this.previewNeedsRefresh && this.selected !== undefined) {
      this.loadPreview(this.selected, this.previewOffset);
    }
  }

  private queueSearch(value: string, force: boolean = false): void {
    if (value !== this.navigatorView.query) { this.cancelFileMenu(); }
    this.navigatorBinding?.queueSearch(value, force);
  }

  private select(row: DesktopFileNavigatorRow): void {
    if (!row.directory) {
      this.openPreview(row);
      return;
    }
    if (!this.navigatorView.query.trim() && row.expanded) { this.revealNavigatorPath = ''; }
    this.navigatorBinding?.toggleDirectory(row.path);
  }

  private fileFocusId(key: string): string { return key + this.focusScope; }

  private togglePreviewNavigator(): void {
    this.cancelFileMenu();
    const open = !this.navigatorView.open;
    if (!open) { this.closeSearchSettings(false); }
    this.navigatorBinding?.setOpen(open);
    if (!open) {
      this.getUIContext().getFocusController().requestFocus(this.fileFocusId('desktopFilePreviewNavigatorToggle'));
    }
  }

  private locatePreviewInNavigator(): void {
    this.navigatorCurrent = desktopFileNavigatorRelativePath(this.selected?.path ?? '', this.fileRoot());
    this.revealNavigatorPath = this.navigatorCurrent;
    this.revealPreviewFile();
  }

  private revealPreviewFile(): void {
    const path = this.revealNavigatorPath;
    const navigator = this.navigatorBinding;
    if (!path || navigator === undefined || !this.shown || !this.navigatorView.open ||
      this.navigatorView.query.trim()) { return; }
    const index = navigator.reveal(path);
    if (index === DESKTOP_FILE_REVEAL_PENDING) { return; }
    this.revealNavigatorPath = '';
    if (index >= 0) {
      setTimeout((): void => {
        if (navigator === this.navigatorBinding && this.shown && this.navigatorView.open &&
          this.navigatorCurrent === path && !this.navigatorView.query.trim()) {
          const current = this.navigatorView.rows.findIndex((row: DesktopFileNavigatorRow): boolean => row.path === path);
          if (current >= 0) { this.navigatorScroller.scrollToIndex(current, false, ScrollAlign.AUTO); }
        }
      }, 0);
    }
  }

  private navigatorMode(): DesktopFileNavigatorMode {
    return desktopFileNavigatorMode(this.navigatorRowWidth, this.viewportWidth);
  }

  private navigatorPanelWidth(): number {
    return desktopFileNavigatorBounds(this.navigatorRowWidth, this.navigatorView.width).width;
  }

  private resizePreviewNavigator(width: number): void {
    this.navigatorBinding?.setWidth(desktopFileNavigatorBounds(this.navigatorRowWidth, width).width);
  }

  private navigatorResizeKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    const bounds = desktopFileNavigatorBounds(this.navigatorRowWidth, this.navigatorView.width);
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
    if (!this.navigatorView.open || this.searchSettingsOpen || event.type !== KeyType.Down ||
      event.keyCode !== KeyCode.KEYCODE_ESCAPE || event.getModifierKeyState?.(['Ctrl']) === true ||
      event.getModifierKeyState?.(['Alt']) === true || event.getModifierKeyState?.(['Shift']) === true) { return false; }
    if (this.navigatorView.query.trim()) {
      this.queueSearch('');
      this.getUIContext().getFocusController().requestFocus(this.fileFocusId('desktopFileSearchInput'));
    } else {
      this.togglePreviewNavigator();
    }
    return true;
  }

  private closePreview(): void {
    this.stopDelimitedTask();
    if (this.fileMenu?.target.key === 'preview') { this.cancelFileMenu(); }
    this.cancelPreviewWatch?.();
    this.cancelPreviewWatch = undefined;
    this.previewRevision++;
    this.selected = undefined;
    this.preview = undefined;
    this.htmlFile = undefined;
    this.delimitedTable = undefined;
    this.workbook = undefined;
    this.delimitedProblem = '';
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

  private openPreview(row: DesktopFileNavigatorRow): void {
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

  private async loadPreview(row: DesktopFileNavigatorRow, offset: number = 1): Promise<void> {
    const host = this.host;
    if (host === undefined) {
      return;
    }
    this.stopDelimitedTask();
    const revision = ++this.previewRevision;
    this.previewNeedsRefresh = false;
    const visualAsset = pdfName(row.name) || imageName(row.name);
    this.previewLoading = !visualAsset || !this.previewPath;
    this.previewError = '';
    if (desktopWorkbookFormat(row.name)) {
      this.delimitedProblem = '';
      this.workbook = undefined;
      this.preview = undefined;
      await this.loadWorkbook(host, row.path, revision);
      return;
    }
    const format = desktopDelimitedFormat(row.name);
    if (format) {
      this.delimitedProblem = '';
      this.delimitedTable = undefined;
      this.preview = undefined;
      await this.loadDelimited(host, row.path, format, revision);
      return;
    }
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

  private stopDelimitedTask(): void {
    clearTimeout(this.delimitedTimer);
    this.delimitedTimer = -1;
    const task = this.delimitedTask;
    this.delimitedTask = undefined;
    if (task !== undefined) {
      try { taskpool.cancel(task); } catch (_) {}
    }
  }

  private async loadDelimited(host: DesktopHostActions, path: string, format: string, revision: number): Promise<void> {
    const response = await host.readWorkspaceBytes(this.sessionId, path, DESKTOP_TABLE_MAX_BYTES)
      .catch((): undefined => undefined);
    if (!this.active || revision !== this.previewRevision) { return; }
    const metadata = getRecord(response?.value, 'metadata');
    const bytes = getField(response?.value, 'data');
    const length = getNumber(metadata, 'bytes');
    if (response?.ok !== true || !(bytes instanceof ArrayBuffer) || getNumber(metadata, 'offset') !== 0 ||
      getBoolean(metadata, 'eof') !== true || (length !== undefined && length !== bytes.byteLength)) {
      const stat = response?.error?.code !== 'workspace-file/too-large' ?
        await host.call('workspaceFiles/stat', this.args(path)).catch((): undefined => undefined) : undefined;
      if (!this.active || revision !== this.previewRevision) { return; }
      this.delimitedProblem = response?.error?.code === 'workspace-file/too-large' ||
        (getNumber(stat?.value, 'bytes') ?? 0) > DESKTOP_TABLE_MAX_BYTES ? 'tooLarge' : 'invalid';
      this.previewLoading = false;
      return;
    }
    const task = new taskpool.Task(parseDesktopDelimitedBytes, bytes, format === 'CSV' ? ',' : '\t',
      DESKTOP_TABLE_MAX_BYTES, DESKTOP_TABLE_MAX_CELLS);
    this.delimitedTask = task;
    this.delimitedTimer = setTimeout((): void => {
      if (this.delimitedTask !== task) { return; }
      this.stopDelimitedTask();
      this.delimitedProblem = 'timeout';
      this.previewLoading = false;
    }, DESKTOP_TABLE_TIMEOUT_MS);
    try {
      const result = await taskpool.execute(task);
      if (this.delimitedTask !== task || !this.active || revision !== this.previewRevision) { return; }
      const table = this.deserializeTable(getRecord(result, 'table'));
      this.delimitedTable = table;
      this.delimitedProblem = table === undefined ? getString(result, 'problem') || 'invalid' : '';
      this.previewAssetVersion++;
    } catch (_) {
      if (this.delimitedTask !== task || !this.active || revision !== this.previewRevision) { return; }
      this.delimitedProblem = 'invalid';
    } finally {
      if (this.delimitedTask === task) {
        this.delimitedTask = undefined;
        clearTimeout(this.delimitedTimer);
        this.delimitedTimer = -1;
        this.previewLoading = false;
      }
    }
  }

  private deserializeTable(table: Object | undefined): DesktopDelimitedTable | undefined {
    const rawRows = getArray(table, 'rows');
    const columns = getNumber(table, 'columns') ?? 0;
    if (rawRows === undefined || !Number.isSafeInteger(columns) || columns <= 0 || !rawRows.length ||
      rawRows.length * columns > DESKTOP_TABLE_MAX_CELLS) { return undefined; }
    const rows: string[][] = [];
    for (const rawRow of rawRows) {
      if (!Array.isArray(rawRow) || rawRow.length === 0 || rawRow.length > columns) { return undefined; }
      const row: string[] = [];
      for (let column = 0; column < rawRow.length; column++) {
        const value: Object = rawRow[column];
        if (typeof value !== 'string') { return undefined; }
        row.push(value);
      }
      rows.push(row);
    }
    return { rows: rows, columns: columns };
  }

  private delimitedNotice(): ResourceStr {
    switch (this.delimitedProblem) {
      case 'tooLarge': return $r('app.string.desktop_table_too_large');
      case 'timeout': return $r('app.string.desktop_table_timeout');
      case 'encoding': return $r('app.string.desktop_table_encoding');
      case 'busy': return $r('app.string.desktop_table_busy');
      default: return $r('app.string.desktop_table_invalid');
    }
  }

  private async loadWorkbook(host: DesktopHostActions, path: string, revision: number): Promise<void> {
    const response = await host.call('workspaceFiles/spreadsheet', this.args(path), 22000, 32 * 1024 * 1024 + 64 * 1024)
      .catch((): undefined => undefined);
    if (!this.active || revision !== this.previewRevision) { return; }
    this.workbook = response?.ok ? readDesktopWorkbook(response.value) : undefined;
    switch (response?.error?.code) {
      case 'spreadsheet/too-large':
      case 'workspace-file/too-large': this.delimitedProblem = 'tooLarge'; break;
      case 'spreadsheet/timeout': this.delimitedProblem = 'timeout'; break;
      case 'spreadsheet/busy': this.delimitedProblem = 'busy'; break;
      default: this.delimitedProblem = 'invalid'; break;
    }
    this.previewAssetVersion++;
    this.previewLoading = false;
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

  private async openSystem(row: DesktopFileNavigatorRow): Promise<void> {
    const ability = this.ability;
    const revision = this.previewRevision;
    let previewUri = this.previewUri;
    if (ability !== undefined && !previewUri && desktopWorkbookFormat(row.name)) {
      const result = await this.host?.call('workspaceFiles/stat', this.args(row.path))
        .catch((): undefined => undefined);
      if (!this.active || revision !== this.previewRevision) { return; }
      const path = result?.ok ? getString(result.value, 'absolutePath') ?? '' : '';
      if (path.startsWith('/') && !path.includes('\0')) { previewUri = uriFromPath(path); }
    }
    if (ability === undefined || !previewUri ||
      !(await openSystemPreview(ability, previewUri, row.name, mimeTypeForName(row.name)))) {
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

  private searchEmptyHint(): ResourceStr {
    const hidden = !this.navigatorView.preferences.showHidden;
    const excluded = this.navigatorView.preferences.rules.some((rule: DesktopFileSearchRule): boolean => rule.enabled);
    const ignored = this.navigatorView.preferences.respectGitignore;
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
      DesktopFileSearchSettings({ rules: this.draftSearchRules, respectGitignore: this.navigatorView.preferences.respectGitignore,
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
      TextInput({ text: this.navigatorView.query, placeholder: $r('app.string.desktop_file_results_placeholder') })
        .key('desktopFileSearchInput').id(this.fileFocusId('desktopFileSearchInput'))
        .height(32).layoutWeight(1).backgroundColor(Color.Transparent)
        .padding({ left: 1, right: 1 }).onChange((value: string): void => { this.queueSearch(value); })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE && this.navigatorView.query) {
            this.queueSearch('');
            return true;
          }
          return false;
        })
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image(this.navigatorView.preferences.showHidden ? $r('app.media.dsh_secret_eye') : $r('app.media.dsh_secret_eye_off'))
          .width(16).height(16).supportSvg2(true).accessibilityLevel('no')
      }.key('desktopFileSearchHidden').width(30).height(32).padding(0).borderRadius(7)
        .accessibilityText($r('app.string.desktop_file_results_hidden')).accessibilitySelected(this.navigatorView.preferences.showHidden)
        .focusOnTouch(false).onClick((): void => { this.updateSearchPreferences({ showHidden: !this.navigatorView.preferences.showHidden }); })
      if (this.navigatorView.query) {
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
    if (this.navigatorView.searchNotice) {
      Column({ space: 4 }) {
        Text($r('app.string.desktop_file_results_failed', this.navigatorView.searchNotice)).fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Button($r('app.string.desktop_file_results_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopFileSearchRetry').height(28).onClick((): void => { this.queueSearch(this.navigatorView.query, true); })
      }.alignItems(HorizontalAlign.Start).width('100%').padding(8)
    } else if (this.navigatorView.found !== undefined) {
      Text($r('app.string.desktop_file_results_count', String(this.navigatorView.found.count))).key('desktopFileSearchCount')
        .fontSize(12).fontColor($r('sys.color.font_secondary')).padding({ left: 10, top: 2, bottom: 3 })
      if (this.navigatorView.found.count === 0) {
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

  private fileTarget(row: DesktopFileNavigatorRow): WorkspaceFileMenuTarget {
    return { key: (row.spans === undefined ? 'tree:' : 'result:') + row.path,
      path: row.path, name: row.name, directory: row.directory };
  }

  private headerFileTarget(): WorkspaceFileMenuTarget {
    const file = this.selected;
    const root = this.fileRoot().replace(new RegExp('/+$'), '');
    return file === undefined ?
      { key: 'root', path: '.', name: root.slice(root.lastIndexOf('/') + 1) || this.fileRoot(), directory: true } :
      { key: 'preview', path: file.path, name: file.name, directory: false };
  }

  private async showFileMenu(target: WorkspaceFileMenuTarget, offset: Position): Promise<void> {
    if (!this.active || !this.shown || !this.sessionId || this.fileMenuRequestKey === target.key ||
      (target.key === 'root' && !this.fileRoot())) { return; }
    this.cancelFileMenu();
    this.fileMenuRequestKey = target.key;
    const serial = this.fileMenuSerial;
    const session = this.sessionId;
    const root = this.fileRoot();
    const metadata = await this.host?.call('workspaceFiles/stat', this.args(target.path)).catch((): undefined => undefined);
    if (serial !== this.fileMenuSerial || !this.active || !this.shown || session !== this.sessionId ||
      root !== this.fileRoot() || (target.key === 'preview' && target.path !== this.selected?.path)) {
      if (serial === this.fileMenuSerial) { this.cancelFileMenu(); }
      return;
    }
    const absolutePath = getString(metadata?.value, 'absolutePath') ?? '';
    const fallback = desktopFileContextCopyPath(root, target.path);
    let authorized = metadata?.ok && absolutePath.startsWith('/') && !absolutePath.includes('\0') ? absolutePath : '';
    if (target.directory && metadata?.error?.code === 'workspace-file/not-regular-file' &&
      getString(parseJson(metadata.error.details), 'kind') === 'directory') { authorized = fallback; }
    this.fileMenu = { target: target, session: session, serial: serial, authorized: authorized,
      copyPath: authorized || fallback, offset: offset };
  }

  private fileMenuMouse(event: MouseEvent, target: WorkspaceFileMenuTarget, height: number): void {
    if (event.button !== MouseButton.Right) { return; }
    if (event.action === MouseAction.Press) { event.stopPropagation(); }
    else if (event.action === MouseAction.Release) {
      event.stopPropagation();
      this.showFileMenu(target, { x: event.x, y: event.y - height });
    }
  }

  private fileMenuKey(event: KeyEvent, target: WorkspaceFileMenuTarget): boolean {
    if (event.type !== KeyType.Down || event.metaKey === 1 || event.getModifierKeyState?.(['Alt']) === true ||
      event.getModifierKeyState?.(['Ctrl']) === true || !(event.keyCode === KeyCode.KEYCODE_MENU ||
        (event.keyCode === KeyCode.KEYCODE_F10 && event.getModifierKeyState?.(['Shift']) === true))) {
      return false;
    }
    event.stopPropagation();
    this.showFileMenu(target, { x: 0, y: 0 });
    return true;
  }

  private fileMenuTouch(event: GestureEvent, target: WorkspaceFileMenuTarget, height: number): void {
    const point = event.fingerList[0];
    if (point !== undefined) { this.showFileMenu(target, { x: point.localX, y: point.localY - height }); }
  }

  private fileContextOptions(key: string): ContextMenuOptions {
    const options: MenuOptions = desktopMenuOptions(Placement.BottomLeft);
    const visible = this.fileMenu;
    if (visible?.target.key !== key) {
      return { placement: Placement.BottomLeft, systemMaterial: options.systemMaterial };
    }
    const serial = visible.serial;
    return { placement: Placement.BottomLeft, systemMaterial: options.systemMaterial,
      offset: visible.offset, onDisappear: (): void => { this.finishFileMenu(serial); } };
  }

  private cancelFileMenu(): void {
    this.fileMenuSerial++;
    this.fileMenuRequestKey = '';
    this.pendingFileAction = undefined;
    this.fileMenu = undefined;
  }

  private chooseFileAction(action: DesktopFileContextAction): void {
    if (this.fileMenu !== undefined) { this.pendingFileAction = action; }
  }

  private finishFileMenu(serial: number): void {
    const menu = this.fileMenu;
    if (menu === undefined || menu.serial !== serial) { return; }
    const action = this.pendingFileAction;
    this.cancelFileMenu();
    if (action !== undefined) { this.runFileAction(menu, action); }
  }

  private async runFileAction(menu: WorkspaceFileMenu, action: DesktopFileContextAction): Promise<void> {
    if (!this.active || !this.shown || menu.session !== this.sessionId) { return; }
    const ability = this.ability;
    const host = this.host;
    const source: DesktopReferenceSource | undefined = host === undefined || !menu.authorized ? undefined :
      { host: host, sessionId: menu.session, path: menu.target.path, absolutePath: menu.authorized };
    const toast = this.getUIContext().getPromptAction();
    try {
      switch (action) {
        case DesktopFileContextAction.SIDEBAR:
        case DesktopFileContextAction.FLOAT:
          if (menu.authorized) {
            this.onOpenFileIn?.(menu.target.path, menu.target.name, action === DesktopFileContextAction.FLOAT);
          }
          break;
        case DesktopFileContextAction.REVEAL:
          if (!menu.authorized || ability === undefined || openFileLocation(ability, menu.authorized) !== 'ok') {
            toast.showToast({ message: $r('app.string.desktop_file_context_reveal_failed') });
          }
          break;
        case DesktopFileContextAction.OPEN:
          if (ability === undefined || !menu.authorized ||
            !await openDesktopReferenceFile(ability, menu.authorized, menu.target.name)) {
            toast.showToast({ message: $r('app.string.desktop_file_context_open_failed') });
          }
          break;
        case DesktopFileContextAction.COPY_PATH:
          if (menu.copyPath) {
            const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, menu.copyPath);
            await pasteboard.getSystemPasteboard().setData(data);
            toast.showToast({ message: $r('app.string.desktop_file_context_copied') });
          }
          break;
        case DesktopFileContextAction.COPY_IMAGE:
          if (source !== undefined) {
            await copyDesktopReferenceImage(source);
            toast.showToast({ message: $r('app.string.desktop_file_context_copied') });
          }
          break;
        case DesktopFileContextAction.DOWNLOAD:
          if (ability !== undefined && source !== undefined && await saveDesktopReferenceFile(ability, source, menu.target.name)) {
            toast.showToast({ message: $r('app.string.desktop_file_context_downloaded') });
          }
          break;
        case DesktopFileContextAction.ADD_TO_CHAT:
          if (this.canReferenceWorkspaceFile && menu.copyPath) { this.onReferenceWorkspaceFile(menu.copyPath); }
          break;
      }
    } catch (_) {
      if (this.active && menu.session === this.sessionId) {
        toast.showToast({ message: action === DesktopFileContextAction.DOWNLOAD ?
          $r('app.string.desktop_file_context_download_failed') : $r('app.string.desktop_file_context_copy_failed') });
      }
    }
  }

  private pathFileItems(): DesktopFileContextItem[] {
    const menu = this.fileMenu;
    const verified = !!menu?.authorized;
    return desktopFileContextPathItems(menu?.target.directory === true, verified && this.ability !== undefined,
      verified && this.onOpenFileIn !== undefined, !!menu?.copyPath);
  }

  private fileTransferItems(): DesktopFileContextItem[] {
    const menu = this.fileMenu;
    const native = !!menu?.authorized && this.ability !== undefined && this.host !== undefined;
    return desktopFileContextTransferItems(mimeTypeForName(menu?.target.name ?? '').startsWith('image/'), native, native);
  }

  private fileContextTitle(action: DesktopFileContextAction): ResourceStr {
    switch (action) {
      case DesktopFileContextAction.SIDEBAR: return $r('app.string.desktop_file_context_sidebar');
      case DesktopFileContextAction.FLOAT: return $r('app.string.desktop_file_context_float');
      case DesktopFileContextAction.REVEAL: return $r('app.string.desktop_file_context_reveal');
      case DesktopFileContextAction.OPEN: return $r('app.string.desktop_file_context_open');
      case DesktopFileContextAction.COPY_PATH:
        return this.fileMenu?.target.directory ? $r('app.string.desktop_file_context_copy_folder') :
          $r('app.string.desktop_file_context_copy_file');
      case DesktopFileContextAction.COPY_IMAGE: return $r('app.string.desktop_file_preview_copy_image');
      case DesktopFileContextAction.DOWNLOAD: return $r('app.string.desktop_file_context_download');
      case DesktopFileContextAction.ADD_TO_CHAT: return $r('app.string.desktop_file_context_reference');
    }
  }

  private fileContextIcon(action: DesktopFileContextAction): Resource {
    switch (action) {
      case DesktopFileContextAction.SIDEBAR: return $r('app.media.dsh_file_context_sidebar');
      case DesktopFileContextAction.FLOAT:
      case DesktopFileContextAction.OPEN: return $r('app.media.dsh_reference_menu_right_up');
      case DesktopFileContextAction.REVEAL: return $r('app.media.dsh_reference_menu_folder_open');
      case DesktopFileContextAction.DOWNLOAD: return $r('app.media.dsh_session_download');
      case DesktopFileContextAction.ADD_TO_CHAT: return $r('app.media.dsh_reference_menu_plus');
      default: return $r('app.media.dsh_session_copy');
    }
  }

  @Builder
  private FileContextItem(action: DesktopFileContextAction, enabled: boolean) {
    MenuItem({ content: this.fileContextTitle(action), startIcon: this.fileContextIcon(action) })
      .key('desktopFileContext-' + action).enabled(enabled)
      .onChange((_selected: boolean): void => { this.chooseFileAction(action); })
  }

  @Builder
  private FileContextMenu() {
    Menu() {
      MenuItemGroup() {
        ForEach(this.pathFileItems(), (item: DesktopFileContextItem): void => {
          this.FileContextItem(item.action, item.enabled)
        }, (item: DesktopFileContextItem): string => item.action)
      }
      if (this.fileMenu?.target.directory !== true) {
        MenuItemGroup() {
          ForEach(this.fileTransferItems(), (item: DesktopFileContextItem): void => {
            this.FileContextItem(item.action, item.enabled)
          }, (item: DesktopFileContextItem): string => item.action)
        }
        MenuItemGroup() {
          this.FileContextItem(DesktopFileContextAction.ADD_TO_CHAT, this.canReferenceWorkspaceFile && !!this.fileMenu?.copyPath)
        }
      }
    }.width(216)
  }

  @Builder
  private FileContextHeading() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row() {
        Text(this.selected?.name || this.headerFileTarget().name || $r('app.string.desktop_dock_file_tab'))
          .fontSize(14).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
    }.layoutWeight(1).height(FILE_HEADER_HEIGHT).padding(0).borderRadius(8)
      .focusable(true).tabIndex(0).focusOnTouch(false)
      .key('desktopFileContextHeading-' + this.headerFileTarget().key)
      .onClick((): void => { this.showFileMenu(this.headerFileTarget(), { x: 0, y: 0 }); })
      .onMouse((event: MouseEvent): void => { this.fileMenuMouse(event, this.headerFileTarget(), FILE_HEADER_HEIGHT); })
      .onKeyEvent((event: KeyEvent): boolean => this.fileMenuKey(event, this.headerFileTarget()))
      .priorityGesture(LongPressGesture({ duration: 420 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
        .onAction((event: GestureEvent): void => { this.fileMenuTouch(event, this.headerFileTarget(), FILE_HEADER_HEIGHT); }))
      .bindContextMenu(this.fileMenu !== undefined && this.fileMenu.target.key === this.headerFileTarget().key,
        this.FileContextMenu(), this.fileContextOptions(this.headerFileTarget().key))
  }

  @Builder
  private FileLine(row: DesktopFileNavigatorRow) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 5 }) {
        if (row.directory) {
          Image(row.expanded ? $r('app.media.dsh_sidebar_folder_open') : $r('app.media.dsh_sidebar_workspace'))
            .width(16).height(16).supportSvg2(true).draggable(false).accessibilityLevel('no')
        } else {
          Image(desktopFileTypeIcon(row.name)).width(16).height(16).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
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
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (row.loading) {
          LoadingProgress().width(14).height(14)
        }
      }.width('100%')
    }
    .key((row.spans === undefined ? 'desktopWorkspaceFile-' : 'desktopFileSearchResult-') + row.path)
    .width('100%').constraintSize({ minHeight: FILE_ROW_HEIGHT }).padding({ left: 10 + Math.min(row.depth, 12) * 12, right: 8 })
    .borderRadius(8).backgroundColor(this.navigatorCurrent === row.path ?
      $r('app.color.workspace_selection') : Color.Transparent)
    .accessibilitySelected(this.navigatorCurrent === row.path).focusable(true).tabIndex(0).focusOnTouch(false)
    .onMouse((event: MouseEvent): void => { this.fileMenuMouse(event, this.fileTarget(row), FILE_ROW_HEIGHT); })
    .onKeyEvent((event: KeyEvent): boolean => this.fileMenuKey(event, this.fileTarget(row)))
    .priorityGesture(LongPressGesture({ duration: 420 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
      .onAction((event: GestureEvent): void => { this.fileMenuTouch(event, this.fileTarget(row), FILE_ROW_HEIGHT); }))
    .bindContextMenu(this.fileMenu?.target.key === this.fileTarget(row).key,
      this.FileContextMenu(), this.fileContextOptions(this.fileTarget(row).key))
    .onClick((): void => {
      this.cancelFileMenu();
      if (row.directory || this.onOpenFile === undefined) { this.select(row); }
      else { this.onOpenFile(row.path, row.name); }
    })
  }

  private rowKey(row: DesktopFileNavigatorRow): string {
    const view = row.spans === undefined ? '' : this.navigatorView.query.trim() + ':';
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
  private SpreadsheetProblem(systemFallback: boolean) {
    Column({ space: 6 }) {
      Text(this.delimitedNotice()).fontSize(13).fontColor($r('sys.color.warning')).width('100%')
        .key('desktopDelimitedProblem')
      Row({ space: 8 }) {
        Button($r('app.string.desktop_table_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopDelimitedRetry').onClick((): void => {
            if (this.selected !== undefined) { this.loadPreview(this.selected); }
          })
        if (systemFallback) {
          Button($r('app.string.desktop_file_preview_system'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopWorkbookOpenSystem').onClick((): void => {
              if (this.selected !== undefined) { this.openSystem(this.selected); }
            })
        }
      }.width('100%')
    }.width('100%').padding(14)
  }

  @Builder
  private PreviewBody() {
    if (this.previewLoading) {
      Row({ space: 8 }) {
        LoadingProgress().width(25).height(25)
        if (desktopDelimitedFormat(this.selected?.name ?? '') || desktopWorkbookFormat(this.selected?.name ?? '')) {
          Text($r('app.string.desktop_table_loading')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
      }.margin(15)
    } else if (this.previewError) {
      Text(this.previewError).fontSize(13).fontColor($r('sys.color.warning')).padding(12)
    } else if (desktopWorkbookFormat(this.selected?.name ?? '')) {
      if (this.workbook !== undefined) {
        Column() {
          ForEach([this.previewAssetVersion], (_version: number): void => {
            DesktopWorkbookPreview({ workbook: this.workbook, focusScope: this.focusScope })
          }, (version: number): string => String(version))
        }.width('100%').layoutWeight(1)
      } else {
        this.SpreadsheetProblem(true)
      }
    } else if (desktopDelimitedFormat(this.selected?.name ?? '')) {
      if (this.delimitedTable !== undefined) {
        Column() {
          ForEach([this.previewAssetVersion], (_version: number): void => {
            DesktopDelimitedPreview({ table: this.delimitedTable, format: desktopDelimitedFormat(this.selected?.name ?? ''),
              focusScope: this.focusScope })
          }, (version: number): string => String(version))
        }.width('100%').layoutWeight(1)
      } else {
        this.SpreadsheetProblem(false)
      }
    } else if (desktopIsHtmlFile(this.selected?.name ?? '') && !this.sourceHtml) {
      if (this.htmlFile === undefined) {
        Text($r('app.string.desktop_html_preview_failed')).key('desktopHtmlPreviewProblem')
          .fontSize(13).fontColor($r('sys.color.warning')).padding(14)
      } else if (this.shown) {
        Column() {
          ForEach([`${this.sessionId}:${this.fileRoot()}:${this.previewAssetVersion}:${this.interactiveHtml}`],
            (_key: string): void => {
              DesktopHtmlPreview({ host: this.host, file: this.htmlFile, sessionId: this.sessionId,
                workspaceRoot: this.fileRoot(), interactive: this.interactiveHtml })
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
      if (this.navigatorView.searching || (!this.navigatorView.query.trim() && this.navigatorView.rootLoading && this.navigatorView.rows.length === 0)) {
        LoadingProgress().width(22).height(22).margin(6)
      }
      if (this.navigatorView.query.trim()) {
        this.SearchStatus()
      } else if (this.navigatorView.notice) {
        Text(this.navigatorView.notice).fontSize(12).fontColor($r('sys.color.warning')).padding(8)
      }
      if (!this.navigatorView.query.trim() && this.navigatorView.rootTruncated) {
        Text('工作区文件列表已截断').fontSize(12).padding(8)
      }
      if (!this.navigatorView.query.trim() && !this.navigatorView.rootLoading && this.navigatorView.rows.length === 0 && !this.navigatorView.notice) {
        Text('工作区没有文件').fontSize(13).fontColor($r('sys.color.font_secondary')).padding(12)
      }
      List({ scroller: this.navigatorScroller }) {
        ForEach(this.navigatorView.query.trim() ? this.navigatorView.matches : this.navigatorView.rows, (row: DesktopFileNavigatorRow): void => {
          ListItem() { this.FileLine(row) }
        }, (row: DesktopFileNavigatorRow): string => this.rowKey(row))
        if (this.navigatorView.query.trim() && this.navigatorView.found?.truncated) {
          ListItem() {
            Text($r('app.string.desktop_file_results_truncated', String(this.navigatorView.found.count))).fontSize(12)
              .fontColor($r('sys.color.font_secondary')).padding(8)
          }
        }
        if (this.navigatorView.query.trim() && this.navigatorView.found?.incomplete) {
          ListItem() {
            Text($r('app.string.desktop_file_results_incomplete')).fontSize(12)
              .fontColor($r('sys.color.font_secondary')).padding(8)
          }
        }
      }.width('100%').layoutWeight(1).onScrollStop((): void => { this.captureNavigatorScroll(); })
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
          .width(this.navigatorView.open && this.navigatorMode() === DesktopFileNavigatorMode.PUSH ?
            this.navigatorRowWidth - this.navigatorPanelWidth() - 16 : '100%').height('100%')
          .visibility(this.navigatorView.open && this.navigatorMode() === DesktopFileNavigatorMode.FILL ?
            Visibility.Hidden : Visibility.Visible)
      }.width('100%').height('100%')
      if (this.navigatorView.open) {
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
        this.FileContextHeading()
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
          if ((this.workbook?.unsupported.length ?? 0) > 0) {
            Button($r('app.string.desktop_file_preview_system'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopWorkbookOpenSystem').onClick((): void => {
                if (this.selected !== undefined) { this.openSystem(this.selected); }
              })
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
          if (this.previewOnly && this.fileRoot()) {
            Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Image(this.navigatorView.open ? $r('app.media.dsh_sidebar_folder_open') : $r('app.media.dsh_sidebar_workspace'))
                .width(16).height(16).supportSvg2(true).accessibilityLevel('no')
            }.key('desktopFilePreviewNavigatorToggle').id(this.fileFocusId('desktopFilePreviewNavigatorToggle'))
              .width(30).height(30).padding(0).borderRadius(7).accessibilitySelected(this.navigatorView.open)
              .accessibilityText(this.navigatorView.open ? $r('app.string.desktop_file_navigator_hide') :
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
      .onKeyEvent((event: KeyEvent): boolean => this.fileMenuKey(event, this.headerFileTarget()))
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
