import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { getArray, getBoolean, getNumber, getString, parseJson } from 'connection';
import { DESKTOP_HTML_ASSET_BYTES, DESKTOP_HTML_ASSET_COUNT, DESKTOP_HTML_PACKAGE_BYTES,
  desktopHtmlCanonicalDependency, desktopHtmlDependencyPath, readDesktopHtmlFile } from './DesktopHtmlFile';
import type { DesktopHtmlFile } from './DesktopHtmlFile';
import type { DesktopHostActions } from './DesktopHostActions';

interface DesktopHtmlAsset {
  kind: string;
  reference: string;
  data: string;
}

// Keep each command well below renderer IPC message limits. Only the trusted shell receives these chunks.
const SCRIPT_CHUNK: number = 48 * 1024;

@Component
export struct DesktopHtmlPreview {
  host?: DesktopHostActions;
  @Prop file?: DesktopHtmlFile = undefined;
  @Prop sessionId: string = '';
  @Prop workspaceRoot: string = '';
  @Prop interactive: boolean = false;
  @State private loaded: boolean = false;
  @State private problem: boolean = false;
  private active: boolean = false;
  private shell: string = '';
  private shellReady: boolean = false;
  private revision: number = 0;
  private dependencyWatches: (() => void)[] = [];
  private readonly controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.active = true;
    this.loadShell();
  }
  aboutToDisappear(): void {
    this.active = false;
    this.revision++;
    this.releaseWatches();
  }

  private loadShell(): void {
    if (!this.active) { return; }
    try {
      const bytes = this.getUIContext().getHostContext()?.resourceManager.getRawFileContentSync('dsh_html_preview.html');
      if (bytes === undefined) { this.problem = true; return; }
      this.shell = new util.Base64Helper().encodeToStringSync(bytes);
    } catch (_) { this.problem = true; }
  }

  private isShell(href: string): boolean {
    if (!this.shell || !href.startsWith('data:text/html;')) { return false; }
    const comma = href.indexOf(',');
    return comma > 0 && href.slice(0, comma).endsWith(';base64') && href.slice(comma + 1) === this.shell;
  }

  private handleNavigation(event: OnLoadInterceptEvent): boolean {
    const href = event.data.getRequestUrl();
    if (!event.data.isMainFrame()) { return href !== 'about:srcdoc'; }
    return href !== 'about:blank' && !this.isShell(href);
  }

  private handleResource(event: OnInterceptRequestEvent): WebResourceResponse | null {
    const href = event.request.getRequestUrl();
    if (href === 'about:srcdoc' || href === 'about:blank' || this.isShell(href) ||
      /^data:(?:text\/(?:css|javascript)|(?:image|font|audio|video)\/)/i.test(href)) { return null; }
    const denied = new WebResourceResponse();
    denied.setResponseCode(403);
    denied.setReasonMessage('Forbidden');
    denied.setResponseMimeType('text/plain');
    denied.setResponseData('');
    return denied;
  }

  private async pageReady(href: string): Promise<void> {
    if (!this.active || this.shellReady || !this.isShell(href)) { return; }
    try {
      const ready = await this.controller.runJavaScript('typeof window.dshHtmlPreview === "object"');
      if (ready !== 'true' || !this.active || this.shellReady) { return; }
      this.shellReady = true;
      this.prepare();
    } catch (_) {
      if (this.active && this.isShell(href)) { this.problem = true; }
    }
  }

  private current(run: number): boolean { return this.active && run === this.revision; }

  private async stage(value: string, run: number): Promise<boolean> {
    if (!this.current(run)) { return false; }
    await this.controller.runJavaScript('window.__dshHtmlChunks = []');
    for (let offset = 0; offset < value.length; offset += SCRIPT_CHUNK) {
      if (!this.current(run)) { return false; }
      const piece = JSON.stringify(value.slice(offset, offset + SCRIPT_CHUNK));
      await this.controller.runJavaScript(`window.__dshHtmlChunks.push(${piece})`);
    }
    return this.current(run);
  }

  private parseResult(text: string): Object | undefined {
    const value = parseJson(text);
    return typeof value === 'string' ? parseJson(value) : value;
  }

  private releaseWatches(): void {
    for (const stop of this.dependencyWatches) { stop(); }
    this.dependencyWatches = [];
  }

  private async prepare(): Promise<void> {
    const file = this.file;
    if (!this.active || !this.shellReady || file === undefined) { return; }
    const run = ++this.revision;
    const interactive = this.interactive;
    this.releaseWatches();
    this.loaded = false;
    this.problem = false;
    try {
      await this.controller.runJavaScript('window.dshHtmlPreview.clear()');
      if (!await this.stage(file.content, run)) { return; }
      const prepared = await this.controller.runJavaScript(
        'window.__dshHtmlSource = window.__dshHtmlChunks.join(\'\'); window.__dshHtmlChunks = []; true');
      if (!this.current(run) || prepared !== 'true') { return; }
      const paths = new Set<string>();
      const assets = interactive ? await this.readAssets(file, run, paths) : [];
      if (!this.current(run)) { return; }
      if (assets === undefined) { this.problem = true; return; }
      if (!await this.stage(JSON.stringify(assets), run)) { return; }
      const result = await this.controller.runJavaScript(
        `JSON.stringify(window.dshHtmlPreview.render(window.__dshHtmlSource, ${interactive}, JSON.parse(window.__dshHtmlChunks.join(''))))`);
      if (!this.current(run)) { return; }
      await this.controller.runJavaScript('window.__dshHtmlSource = \'\'; window.__dshHtmlChunks = []; true');
      if (!this.current(run)) { return; }
      this.loaded = getBoolean(this.parseResult(result), 'ok') === true;
      this.problem = !this.loaded;
      if (this.loaded) { this.watchAssets(paths); }
    } catch (_) { if (this.current(run)) { this.problem = true; } }
  }

  private async readAssets(file: DesktopHtmlFile, run: number, paths: Set<string>): Promise<DesktopHtmlAsset[] | undefined> {
    const host = this.host;
    if (host === undefined) { return undefined; }
    const result = await this.controller.runJavaScript('JSON.stringify(window.dshHtmlPreview.inspect(window.__dshHtmlSource))');
    if (!this.current(run)) { return undefined; }
    const report = this.parseResult(result);
    const dependencies = getArray(report, 'assets');
    if (getBoolean(report, 'ok') !== true || dependencies === undefined || dependencies.length > DESKTOP_HTML_ASSET_COUNT) {
      return undefined;
    }
    const assets: DesktopHtmlAsset[] = [];
    let total = file.bytes;
    for (const dependency of dependencies) {
      const kind = getString(dependency, 'kind') ?? '';
      const reference = getString(dependency, 'reference') ?? '';
      const path = desktopHtmlDependencyPath(this.workspaceRoot, file.path, reference);
      if (!path || !(kind === 'script' ? /\.js$/i.test(path) : kind === 'stylesheet' && /\.css$/i.test(path))) {
        return undefined;
      }
      const stat = await host.call('workspaceFiles/stat', { 'workspaceFileScopeId': this.sessionId, 'path': path },
        10000, undefined, true);
      if (!this.current(run)) { return undefined; }
      const absolute = stat.ok ? getString(stat.value, 'absolutePath') ?? '' : '';
      const length = getNumber(stat.value, 'bytes');
      const version = getString(stat.value, 'version');
      if (!desktopHtmlCanonicalDependency(this.workspaceRoot, path, absolute) || version === undefined ||
        length === undefined || !Number.isSafeInteger(length) || length < 0 || length > DESKTOP_HTML_ASSET_BYTES ||
        total + length > DESKTOP_HTML_PACKAGE_BYTES) { return undefined; }
      const asset = await readDesktopHtmlFile(host, this.sessionId, absolute, DESKTOP_HTML_ASSET_BYTES);
      if (!this.current(run) || asset === undefined || asset.path !== absolute || asset.version !== version ||
        asset.bytes !== length) { return undefined; }
      total += length;
      paths.add(absolute);
      assets.push({ kind: kind, reference: reference, data: asset.content });
    }
    return assets;
  }

  private watchAssets(paths: Set<string>): void {
    for (const path of paths) {
      const stop = this.host?.watch('workspaceFiles/changes', { 'workspaceFileScopeId': this.sessionId, 'path': path }, {
        onItem: (frame: Object): void => {
          if (this.active && this.loaded && getString(frame, 'kind') === 'change') { this.prepare(); }
        }, onError: (): void => {}, onEnd: (): void => {}
      });
      if (stop !== undefined) { this.dependencyWatches.push(stop); }
    }
  }

  build() {
    Stack() {
      Web({ src: 'data:text/html;base64,' + this.shell, controller: this.controller, incognitoMode: true })
        .key('desktopHtmlPreview')
        .width('100%').height('100%').opacity(this.loaded ? 1 : 0)
        .javaScriptAccess(true).domStorageAccess(false).databaseAccess(false).fileAccess(false).blockNetwork(true)
        .geolocationAccess(false).mixedMode(MixedMode.None).allowWindowOpenMethod(false).multiWindowAccess(false)
        .onPageEnd((event: OnPageEndEvent): void => { this.pageReady(event.url); })
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => this.handleNavigation(event))
        .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => this.handleResource(event))
        .onPermissionRequest((event: OnPermissionRequestEvent): void => { event.request.deny(); })
        .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => { event.result.handleFileList([]); return true; })
        .onAlert((event: OnAlertEvent): boolean => { event.result.handleCancel(); return true; })
        .onConfirm((event: OnConfirmEvent): boolean => { event.result.handleCancel(); return true; })
        .onPrompt((event: OnPromptEvent): boolean => { event.result.handleCancel(); return true; })
        .onErrorReceive((event: OnErrorReceiveEvent): void => {
          if (event.request.isMainFrame() && this.active) { this.problem = true; }
        })
      if (this.problem) {
        Text($r('app.string.desktop_html_preview_failed')).key('desktopHtmlPreviewProblem')
          .fontSize(13).fontColor($r('sys.color.warning')).padding(14)
      } else if (!this.loaded) {
        LoadingProgress().width(25).height(25)
      }
    }.width('100%').height('100%')
  }
}
