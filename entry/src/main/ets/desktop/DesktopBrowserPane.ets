import { webview } from '@kit.ArkWeb';
import { openExternalUrl } from 'platform';
import { desktopBrowserAddress, workspaceBrowserRequest } from './DesktopBrowserAddress';

@Component
struct DesktopBrowserTool {
  icon: Resource = $r('app.media.dsh_browser_globe_outline');
  label: Resource = $r('app.string.desktop_browser_title');
  nodeKey: string = '';
  @Prop usable: boolean = false;
  activate: () => void = (): void => {};

  build() {
    Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image(this.icon).width(15).height(15).supportSvg2(true).accessibilityLevel('no')
    }.key(this.nodeKey).width(24).height(28).padding(0).borderRadius(6)
      .accessibilityText(this.label).enabled(this.usable).onClick(this.activate)
  }
}

@Component
export struct DesktopBrowserPane {
  @Prop address: string = '';
  @Prop restore: boolean = false;
  @Prop workspaceOrigin: string = '';
  onNavigated: (href: string, title: string) => void = (_href: string, _title: string): void => {};
  @State private source: string = '';
  @State private current: string = '';
  @State private draft: string = '';
  @State private loading: boolean = false;
  @State private problem: string = '';
  @State private canBack: boolean = false;
  @State private canForward: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.draft = this.address;
    if (this.address && !this.restore) { this.navigate(); }
  }

  private navigate(): void {
    const page = desktopBrowserAddress(this.draft, this.workspaceOrigin);
    this.problem = page.problem;
    if (!page.href) { return; }
    this.draft = page.href;
    this.current = page.href;
    this.loading = true;
    if (!this.source) {
      this.source = page.href;
    } else {
      this.controller.loadUrl(page.href);
    }
  }

  private finished(href: string): void {
    const page = desktopBrowserAddress(href, this.workspaceOrigin, false);
    if (!page.href) { return; }
    this.loading = false;
    this.current = page.href;
    this.draft = page.href;
    this.canBack = this.controller.accessBackward();
    this.canForward = this.controller.accessForward();
    this.onNavigated(page.href, page.title);
  }

  private intercept(event: OnLoadInterceptEvent): boolean {
    const href = event.data.getRequestUrl();
    if (href === 'about:blank') { return false; }
    const target = desktopBrowserAddress(href, this.workspaceOrigin, false);
    if (target.href) { return false; }
    if (event.data.isMainFrame()) {
      this.loading = false;
      this.problem = target.problem;
    }
    return true;
  }

  private interceptWorkspace(event: OnInterceptRequestEvent): WebResourceResponse | null {
    if (!workspaceBrowserRequest(event.request.getRequestUrl(), this.workspaceOrigin)) { return null; }
    const response = new WebResourceResponse();
    response.setResponseCode(403);
    response.setReasonMessage('Forbidden');
    response.setResponseMimeType('text/plain');
    response.setResponseData('Forbidden');
    return response;
  }

  build() {
    Column() {
      Row({ space: 2 }) {
        DesktopBrowserTool({ icon: $r('app.media.dsh_browser_chevron_left_outline'), label: $r('app.string.desktop_browser_back'),
          nodeKey: 'desktopBrowserBack', usable: this.canBack, activate: (): void => { this.controller.backward(); } })
        DesktopBrowserTool({ icon: $r('app.media.dsh_browser_chevron_right_outline'), label: $r('app.string.desktop_browser_forward'),
          nodeKey: 'desktopBrowserForward', usable: this.canForward, activate: (): void => { this.controller.forward(); } })
        DesktopBrowserTool({ icon: $r('app.media.dsh_browser_refresh_outline'), label: $r('app.string.desktop_browser_reload'),
          nodeKey: 'desktopBrowserReload', usable: !!this.source, activate: (): void => { this.controller.refresh(); } })
        Row() {
          TextInput({ text: this.draft, placeholder: $r('app.string.desktop_browser_address') }).key('desktopBrowserAddress')
            .layoutWeight(1).height(28).fontSize(13).padding({ left: 7, right: 3 })
            .backgroundColor(Color.Transparent).enterKeyType(EnterKeyType.Go)
            .onChange((text: string): void => { this.draft = text; })
            .onSubmit((): void => { this.navigate(); })
          DesktopBrowserTool({ icon: $r('app.media.dsh_browser_link_outline'), label: $r('app.string.desktop_browser_go'),
            nodeKey: 'desktopBrowserGo', usable: !!this.draft.trim(), activate: (): void => { this.navigate(); } })
        }.layoutWeight(1).borderRadius(6).backgroundColor($r('app.color.workspace_selection'))
        DesktopBrowserTool({ icon: $r('app.media.dsh_browser_right_up_outline'), label: $r('app.string.desktop_browser_external'),
          nodeKey: 'desktopBrowserExternal', usable: !!(this.current || this.address), activate: (): void => {
            openExternalUrl(this.current || this.address).then((ok: boolean): void => {
              if (!ok) { this.problem = '无法打开系统浏览器'; }
            });
          } })
      }.width('100%').padding(5)
      if (this.problem) {
        Text(this.problem).key('desktopBrowserProblem').fontSize(12).width('100%').padding(7)
          .fontColor($r('sys.color.font_secondary'))
      }
      if (this.source) {
        if (this.loading) { Progress({ value: 25, total: 100, type: ProgressType.Linear }).width('100%') }
        Web({ src: this.source, controller: this.controller, incognitoMode: true }).key('desktopBrowserPage')
          .width('100%').layoutWeight(1)
          .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).geolocationAccess(false)
          .onLoadIntercept((event: OnLoadInterceptEvent): boolean => this.intercept(event))
          .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => this.interceptWorkspace(event))
          .onPageBegin((): void => { this.problem = ''; this.loading = true; })
          .onPageEnd((event: OnPageEndEvent): void => { this.finished(event.url); })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            if (event.request.isMainFrame()) {
              this.loading = false;
              this.problem = '页面加载失败；请刷新重试或在系统浏览器中打开。';
            }
          })
      } else {
        Column({ space: 8 }) {
          if (this.restore && this.address) {
            Text($r('app.string.desktop_browser_previous')).fontWeight(FontWeight.Medium)
            Text(this.address).fontSize(12).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            Button($r('app.string.desktop_browser_restore'), { buttonStyle: ButtonStyleMode.NORMAL })
              .key('desktopBrowserRestore').onClick((): void => { this.draft = this.address; this.navigate(); })
          } else {
            Text($r('app.string.desktop_browser_start')).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(12)
      }
    }.width('100%').height('100%')
  }
}
