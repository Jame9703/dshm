import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { FileNode, FilePreview, NodeKind, PreviewKind, previewKindOf, projectWorkspaceListing,
  projectWorkspaceText, WORKSPACE_ROOT_REQUEST_PATH } from 'appstate';
import { getArray, getBoolean, getNumber, getString } from 'connection';
import { isSystemPreviewableName, mimeTypeForName, openFileLocation, openSystemPreview, uriFromPath } from 'platform';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';

interface FileRow {
  path: string;
  name: string;
  directory: boolean;
  depth: number;
  expanded: boolean;
  loading: boolean;
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
const DEFAULT_EXCLUSIONS: string[] = [
  '.git', '.hg', '.next', '.pnpm-store', '.svn', '.turbo', '.yarn', 'build', 'coverage', 'dist', 'node_modules',
  '.DS_Store', '.Spotlight-V100', '.Trashes', '.fseventsd', 'Thumbs.db', 'desktop.ini', '$RECYCLE.BIN',
  'System Volume Information'
];

function relativePath(path: string): boolean {
  if (path.length === 0 || path.includes('\x00') || path.includes('\\') || path.startsWith('/') ||
    new RegExp('^[A-Za-z]:').test(path)) {
    return false;
  }
  return path.split('/').every((part: string): boolean => part !== '' && part !== '.' && part !== '..');
}

function imageName(name: string): boolean {
  return previewKindOf(name, 0) === PreviewKind.IMAGE || name.toLowerCase().endsWith('.bmp');
}

@Component
export struct DesktopFilesPane {
  host?: DesktopHostActions;
  ability?: common.UIAbilityContext;
  @Prop @Watch('reset') sessionId: string = '';
  onHide: () => void = (): void => {};
  onAttachWorkspaceFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};

  @State private rows: FileRow[] = [];
  @State private matches: FileRow[] = [];
  @State private query: string = '';
  @State private includeHidden: boolean = false;
  @State private respectGitignore: boolean = true;
  @State private defaultExclusions: boolean = true;
  @State private searching: boolean = false;
  @State private rootLoading: boolean = false;
  @State private notice: string = '';
  @State private searchNotice: string = '';
  @State private selected?: FileRow = undefined;
  @State private preview?: FilePreview = undefined;
  @State private previewUri: string = '';
  @State private previewLoading: boolean = false;
  @State private previewError: string = '';
  @State private rawMarkdown: boolean = false;
  @State private previewOffset: number = 1;
  @State private previewLines: number = 0;
  private readonly directories: Map<string, Directory> = new Map<string, Directory>();
  private active: boolean = false;
  private searchTimer: number = -1;
  private searchRevision: number = 0;
  private previewRevision: number = 0;
  private cancelPreviewWatch?: () => void;

  aboutToAppear(): void {
    this.active = true;
    this.reset();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.reset();
  }

  private reset(): void {
    for (const directory of this.directories.values()) {
      directory.stop?.();
    }
    this.directories.clear();
    this.searchRevision++;
    clearTimeout(this.searchTimer);
    this.query = '';
    this.rows = [];
    this.matches = [];
    this.notice = '';
    this.closePreview();
    if (this.active && this.sessionId.length > 0) {
      this.expand(ROOT);
    }
  }

  private args(path: string): Record<string, Object> {
    return { 'workspaceFileScopeId': this.sessionId, 'path': path };
  }

  private expand(path: string): void {
    const directory: Directory = { children: [], loading: false, again: false, truncated: false };
    this.directories.set(path, directory);
    directory.stop = this.host?.watch('workspaceFiles/changes', this.args(path), {
      onItem: (value: Object): void => {
        if (getString(value, 'kind') === 'change') {
          this.list(path, directory);
        }
      },
      onError: (): void => {},
      onEnd: (): void => {}
    });
    this.list(path, directory);
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
      directory.children = projection.nodes.filter((file: FileNode): boolean => relativePath(file.path));
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
  }

  private append(path: string, depth: number, into: FileRow[]): void {
    const children = this.directories.get(path)?.children ?? [];
    for (const child of children) {
      if (!this.includeHidden && child.name.startsWith('.')) {
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
      this.queueSearch(this.query);
      return;
    }
    for (const path of this.directories.keys()) {
      const directory = this.directories.get(path);
      if (directory !== undefined) {
        this.list(path, directory);
      }
    }
  }

  private queueSearch(value: string): void {
    this.query = value;
    this.matches = [];
    this.searchNotice = '';
    clearTimeout(this.searchTimer);
    const revision = ++this.searchRevision;
    const query = value.trim();
    this.searching = query.length > 0;
    if (query.length > 0) {
      this.searchTimer = setTimeout((): void => { this.search(query, revision); }, 230);
    }
  }

  private async search(query: string, revision: number): Promise<void> {
    const host = this.host;
    if (!this.active || host === undefined) {
      return;
    }
    const request: Record<string, Object> = {
      'query': query, 'excludedPaths': this.defaultExclusions ? DEFAULT_EXCLUSIONS : [],
      'includeHidden': this.includeHidden, 'respectGitignore': this.respectGitignore
    };
    const result = await host.call('workspaceFiles/search', { 'workspaceFileScopeId': this.sessionId, 'request': request });
    if (revision !== this.searchRevision) {
      return;
    }
    this.searching = false;
    if (!result.ok) {
      this.searchNotice = desktopHostProblem(result);
      return;
    }
    const matches: FileRow[] = [];
    for (const value of getArray(result.value, 'matches') ?? []) {
      const path = getString(value, 'path') ?? '';
      if (relativePath(path)) {
        matches.push({
          name: path.slice(path.lastIndexOf('/') + 1), path: path, directory: getString(value, 'type') === 'directory',
          depth: 0, expanded: false, loading: false
        });
      }
    }
    this.matches = matches;
    if (getBoolean(result.value, 'truncated') || getBoolean(result.value, 'incomplete')) {
      this.searchNotice = '仅显示部分搜索结果';
    }
  }

  private select(row: FileRow): void {
    if (!row.directory) {
      this.openPreview(row);
      return;
    }
    if (this.query.trim()) {
      this.queueSearch('');
      let path = '';
      for (const part of row.path.split('/')) {
        path = path.length === 0 ? part : path + '/' + part;
        if (!this.directories.has(path)) {
          this.expand(path);
        }
      }
    } else if (this.directories.has(row.path)) {
      this.collapse(row.path);
    } else {
      this.expand(row.path);
    }
  }

  private closePreview(): void {
    this.cancelPreviewWatch?.();
    this.cancelPreviewWatch = undefined;
    this.previewRevision++;
    this.selected = undefined;
    this.preview = undefined;
    this.previewUri = '';
    this.previewError = '';
    this.previewLoading = false;
    this.previewOffset = 1;
    this.previewLines = 0;
  }

  private openPreview(row: FileRow): void {
    this.closePreview();
    this.rawMarkdown = false;
    this.selected = row;
    this.loadPreview(row);
    this.cancelPreviewWatch = this.host?.watch('workspaceFiles/changes', this.args(row.path), {
      onItem: (value: Object): void => {
        if (this.selected?.path === row.path && getString(value, 'kind') === 'change') {
          this.loadPreview(row, this.previewOffset);
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
    this.previewLoading = true;
    this.previewError = '';
    if (imageName(row.name) || (previewKindOf(row.name, 0) === PreviewKind.BINARY && isSystemPreviewableName(row.name))) {
      const result = await host.call('workspaceFiles/stat', this.args(row.path));
      if (revision === this.previewRevision) {
        const path = getString(result.value, 'absolutePath') ?? '';
        this.previewUri = path.startsWith('/') ? uriFromPath(path) : '';
        this.previewLoading = false;
        this.previewError = result.ok ? (this.previewUri ? '' : '系统无法访问此文件') : desktopHostProblem(result);
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

  private async openSystem(row: FileRow): Promise<void> {
    const ability = this.ability;
    if (ability === undefined || !(await openSystemPreview(ability, this.previewUri, row.name, mimeTypeForName(row.name)))) {
      this.getUIContext().getPromptAction().showToast({ message: '系统未能打开此文件的预览' });
    }
  }

  private searchOptions(): MenuElement[] {
    return [
      { value: (this.includeHidden ? '✓ ' : '') + '显示隐藏文件', action: (): void => {
        this.includeHidden = !this.includeHidden;
        this.rebuild();
        this.queueSearch(this.query);
      } },
      { value: (this.respectGitignore ? '✓ ' : '') + '遵循 .gitignore', action: (): void => {
        this.respectGitignore = !this.respectGitignore;
        this.queueSearch(this.query);
      } },
      { value: (this.defaultExclusions ? '✓ ' : '') + '排除构建和依赖目录', action: (): void => {
        this.defaultExclusions = !this.defaultExclusions;
        this.queueSearch(this.query);
      } }
    ];
  }

  private fileOptions(row: FileRow): MenuElement[] {
    const items: MenuElement[] = [
      { value: '复制相对路径', action: (): void => {
        pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, row.path))
          .catch((): void => { this.getUIContext().getPromptAction().showToast({ message: '无法复制路径' }); });
      } }
    ];
    if (!row.directory) {
      items.push({ value: '添加为附件', action: (): void => { this.onAttachWorkspaceFile(row.path, row.name); } });
    }
    if (!row.directory && this.ability !== undefined) {
      items.push({ value: '在文件夹中显示', action: (): void => { this.revealFile(row); } });
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
        Text(row.name).fontSize(14).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (this.query.trim() && row.path !== row.name) {
          Text(row.path).fontSize(11).fontColor($r('sys.color.font_secondary'))
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
    .width('100%').constraintSize({ minHeight: 34 }).padding({ left: 10 + Math.min(row.depth, 12) * 12, right: 8 })
    .borderRadius(8).backgroundColor(Color.Transparent)
    .onClick((): void => { this.select(row); })
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
    } else if (this.previewUri) {
      if (imageName(this.selected?.name ?? '')) {
        Image(this.previewUri).objectFit(ImageFit.Contain).width('100%').layoutWeight(1)
      }
      Button('系统预览', { buttonStyle: ButtonStyleMode.TEXTUAL }).margin(10)
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
          } else {
            Text(this.preview.text).fontSize(13).fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start).padding(12).width('100%')
      }
      .align(Alignment.TopStart).width('100%').layoutWeight(1)
    }
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        if (this.selected !== undefined) {
          Button('‹', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(32).padding(0)
            .accessibilityText('返回文件列表').onClick((): void => { this.closePreview(); })
        }
        Text(this.selected?.name ?? '工作区文件').fontSize(14).fontWeight(FontWeight.Medium)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.selected !== undefined) {
          if (this.preview?.kind === PreviewKind.MARKDOWN) {
            Button(this.rawMarkdown ? '预览' : '源码', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick((): void => { this.rawMarkdown = !this.rawMarkdown; })
          }
          Button('⋯', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(36).padding(0)
            .bindMenu(this.fileOptions(this.selected), desktopMenuOptions(Placement.BottomRight))
        } else {
          Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.refresh(); })
        }
        Button('×', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(32).padding(0)
          .accessibilityText('关闭文件面板').onClick(this.onHide)
      }
      .height(42).padding({ left: 9, right: 4 }).width('100%')
      .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      if (this.selected !== undefined) {
        this.PreviewBody()
      } else {
        Row({ space: 4 }) {
          TextInput({ text: this.query, placeholder: '搜索工作区文件' }).height(32).layoutWeight(1)
            .onChange((value: string): void => { this.queueSearch(value); })
          Button('搜索设置', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .bindMenu(this.searchOptions(), desktopMenuOptions(Placement.BottomRight))
        }
        .width('100%').padding(8)
        if (this.searching || (!this.query.trim() && this.rootLoading && this.rows.length === 0)) {
          LoadingProgress().width(22).height(22).margin(6)
        }
        if (this.query.trim() ? this.searchNotice : this.notice) {
          Text(this.query.trim() ? this.searchNotice : this.notice)
            .fontSize(12).fontColor($r('sys.color.warning')).padding(8)
        }
        if (!this.query.trim() && this.directories.get(ROOT)?.truncated) {
          Text('工作区文件列表已截断').fontSize(12).padding(8)
        }
        if (!this.searching && !this.rootLoading && (this.query.trim() ?
          this.matches.length === 0 && !this.searchNotice : this.rows.length === 0 && !this.notice)) {
          Text(this.query.trim() ? '没有匹配文件' : '工作区没有文件')
            .fontSize(13).fontColor($r('sys.color.font_secondary')).padding(12)
        }
        List() {
          ForEach(this.query.trim() ? this.matches : this.rows, (row: FileRow): void => {
            ListItem() { this.FileLine(row) }
          }, (row: FileRow): string => JSON.stringify(row))
        }
        .width('100%').layoutWeight(1)
      }
    }
    .height('100%').width('100%').backgroundColor($r('app.color.workspace_canvas'))
    .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }
}
