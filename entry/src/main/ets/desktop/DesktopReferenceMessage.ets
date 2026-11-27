import { text } from '@kit.ArkGraphics2D';
import { mimeTypeForName } from 'platform';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopReferenceAction } from './DesktopReferenceActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopSecretRange, desktopSecretRanges } from './DesktopSecretMask';

export interface DesktopReferenceRun {
  kind: string;
  raw: string;
  label: string;
  path: string;
  start: number;
  masked?: string;
}

function textRun(raw: string, start: number): DesktopReferenceRun {
  return { kind: 'text', raw: raw, label: '', path: '', start: start };
}

export function desktopReferenceRuns(text: string, sessionLabels: string[]): DesktopReferenceRun[] {
  const runs: DesktopReferenceRun[] = [];
  const wire = /@\[((?:\\.|[^\\\]\r\n])+)\]\(dsh-session:[A-Za-z0-9_-]+\)/uy;
  const pathToken = /@"[^"\r\n]+"|@[^\s"]+/uy;
  const secrets: DesktopSecretRange[] = desktopSecretRanges(text);
  let secretIndex = 0;
  let emitted = 0;
  let next = text.indexOf('@');
  while (next >= 0 || secretIndex < secrets.length) {
    const secret = secrets[secretIndex];
    if (secret !== undefined && (next < 0 || secret.start <= next)) {
      if (secret.start > emitted) { runs.push(textRun(text.slice(emitted, secret.start), emitted)); }
      runs.push({ kind: 'secret', raw: text.slice(secret.start, secret.end), label: '', path: '',
        start: secret.start, masked: secret.masked });
      secretIndex++;
      emitted = secret.end;
      next = text.indexOf('@', emitted);
      continue;
    }
    wire.lastIndex = next;
    const explicit = wire.exec(text);
    let part: DesktopReferenceRun | undefined;
    if (explicit !== null) {
      part = { kind: 'session', raw: explicit[0], label: explicit[1].replace(/\\(.)/gu, '$1'), path: '', start: next };
    } else {
      let label = '';
      for (const candidate of sessionLabels) {
        if (candidate.length > label.length && text.startsWith(candidate, next + 1)) { label = candidate; }
      }
      if (label) {
        part = { kind: 'session', raw: '@' + label, label: label, path: '', start: next };
      } else if (next === 0 || /\s/u.test(text.charAt(next - 1))) {
        pathToken.lastIndex = next;
        const match = pathToken.exec(text);
        if (match !== null) {
          const quoted = match[0].startsWith('@"');
          const raw = quoted ? match[0] : match[0].replace(/[.,;:!?，。；：！？]+$/u, '');
          const path = quoted ? raw.slice(2, -1) : raw.slice(1);
          if (path) {
            const parts = path.split(/[\\/]/u).filter((item: string): boolean => item.length > 0);
            part = { kind: path.endsWith('/') ? 'folder' : 'file', raw: raw,
              label: parts[parts.length - 1] ?? path, path: path, start: next };
          }
        }
      }
    }
    // A reference overlapping a credential is plain text outside the credential's mask.
    // This also keeps the secret out of a workspace reference lookup.
    if (part === undefined || (secret !== undefined && next + part.raw.length > secret.start)) {
      next = text.indexOf('@', next + 1);
      continue;
    }
    if (next > emitted) { runs.push(textRun(text.slice(emitted, next), emitted)); }
    runs.push(part);
    emitted = next + part.raw.length;
    next = text.indexOf('@', emitted);
  }
  if (emitted < text.length) { runs.push(textRun(text.slice(emitted), emitted)); }
  return runs;
}

@Component
export struct DesktopReferenceMessage {
  @Prop @Watch('resetMessage') text: string = '';
  @Prop @Watch('refresh') referenceLabels: string[] = [];
  @Prop @Watch('resetMessage') sessionId: string = '';
  @Prop nodeKey: string = '';
  @Prop bodySize: number = 14;
  @Prop bodyFamily: string = '';
  @Prop codeFamily: string = 'monospace';
  host?: DesktopHostActions;
  onFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  @Prop canAddReference: boolean = false;
  onAction: (action: DesktopReferenceAction, path: string, name: string) => void =
    (_action: DesktopReferenceAction, _path: string, _name: string): void => {};
  @State private runs: DesktopReferenceRun[] = [];
  @State private revealed: number[] = [];
  @State private menuTarget: DesktopReferenceRun | undefined = undefined;
  @State private menuShown: boolean = false;
  @State private menuAnchor: Position = { x: 0, y: 0 };
  private readonly controller: TextController = new TextController();
  private readonly referenceGesture: string = 'fileReferenceContext';
  private pendingMenuAction?: DesktopReferenceAction;
  @State private confirmed: string[] = [];
  private active: boolean = false;
  private visible: boolean = false;
  private requested: boolean = false;
  private revision: number = 0;
  private messageRevision: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.refresh();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.visible = false;
    this.menuShown = false;
    this.pendingMenuAction = undefined;
    this.menuTarget = undefined;
    this.revealed = [];
    this.revision++;
  }

  private resetMessage(): void {
    this.messageRevision++;
    this.revealed = [];
    this.refresh();
  }

  private refresh(): void {
    if (!this.active) { return; }
    this.revision++;
    this.runs = desktopReferenceRuns(this.text, this.referenceLabels);
    this.confirmed = [];
    this.requested = false;
    this.resolvePaths();
  }

  private async resolvePaths(): Promise<void> {
    const host = this.host;
    if (!this.active || !this.visible || this.requested || host === undefined || !this.sessionId) { return; }
    const revision = this.revision;
    const session = this.sessionId;
    this.requested = true;
    const paths = new Set<string>();
    for (const item of this.runs) {
      if (item.path) { paths.add(item.path); }
    }
    for (const path of paths) {
      if (await host.referencePathExists(session, path)) {
        if (!this.active || this.revision !== revision) { return; }
        if (!this.confirmed.includes(path)) { this.confirmed = [...this.confirmed, path]; }
      }
      if (!this.active || this.revision !== revision || !this.visible) {
        if (this.active && this.revision === revision) { this.requested = false; }
        return;
      }
    }
  }

  private icon(kind: string): Resource {
    if (kind === 'session') { return $r('app.media.dsh_inline_reference_session'); }
    return kind === 'folder' ? $r('app.media.dsh_inline_reference_folder') : $r('app.media.dsh_inline_reference_file');
  }

  private open(run: DesktopReferenceRun): void {
    if (this.active && this.confirmed.includes(run.path)) { this.onFile(run.path, run.label); }
  }

  private showsChip(run: DesktopReferenceRun): boolean {
    return run.kind === 'session' || (run.path !== '' && this.confirmed.includes(run.path));
  }

  private isRevealed(run: DesktopReferenceRun): boolean { return this.revealed.includes(run.start); }

  private displaySecret(run: DesktopReferenceRun): string {
    return this.isRevealed(run) ? run.raw : run.masked ?? '';
  }

  private toggleSecret(run: DesktopReferenceRun): void {
    if (!this.active) { return; }
    this.controller.closeSelectionMenu();
    this.revealed = this.isRevealed(run) ?
      this.revealed.filter((start: number): boolean => start !== run.start) : this.revealed.concat(run.start);
  }

  private runKey(run: DesktopReferenceRun): string {
    // Never put a hidden secret in the identity of an ArkUI node.
    return run.kind === 'secret' ? String(run.start) + ':secret:' + this.messageRevision :
      String(run.start) + ':' + run.raw;
  }

  private fileAt(x: number, y: number): DesktopReferenceRun | undefined {
    if (!this.active) { return undefined; }
    const context = this.getUIContext();
    const pxX = context.vp2px(x);
    const pxY = context.vp2px(y);
    const layout = this.controller.getLayoutManager();
    let start = 0;
    for (const run of this.runs) {
      if (run.kind === 'secret') {
        start += this.displaySecret(run).length + 1;
        continue;
      }
      const chip = this.showsChip(run);
      // The inline image occupies one text position, followed by the label's leading space.
      const end = start + (chip ? run.label.length + 2 : run.raw.length);
      if (run.kind === 'file' && chip) {
        const boxes = layout.getRectsForRange({ start: start, end: end }, text.RectWidthStyle.TIGHT, text.RectHeightStyle.MAX);
        if (boxes.some((box: TextBox): boolean => pxX >= box.rect.left && pxX <= box.rect.right &&
          pxY >= box.rect.top && pxY <= box.rect.bottom)) {
          return run;
        }
      }
      start = end;
    }
    return undefined;
  }

  private showMenuAt(x: number, y: number): boolean {
    if (this.menuShown) { return false; }
    const target = this.fileAt(x, y);
    if (target === undefined) { return false; }
    this.controller.closeSelectionMenu();
    this.menuAnchor = { x: x, y: y };
    this.menuTarget = target;
    this.pendingMenuAction = undefined;
    this.menuShown = true;
    return true;
  }

  private invoke(action: DesktopReferenceAction): void {
    if (this.menuShown) {
      this.pendingMenuAction = action;
    } else {
      this.performMenuAction(action);
    }
  }

  private closeFileMenu(): void {
    this.menuShown = false;
    const action = this.pendingMenuAction;
    this.pendingMenuAction = undefined;
    if (action !== undefined) { this.performMenuAction(action); }
  }

  private performMenuAction(action: DesktopReferenceAction): void {
    const run = this.menuTarget;
    if (run !== undefined && this.active) { this.onAction(action, run.path, run.label); }
  }

  @Builder
  private FileMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: '在文件夹显示', startIcon: $r('app.media.dsh_reference_menu_folder_open') })
          .key('desktopReferenceReveal').onChange((_selected: boolean): void => { this.invoke(DesktopReferenceAction.REVEAL); })
        MenuItem({ content: '使用默认应用打开', startIcon: $r('app.media.dsh_reference_menu_right_up') })
          .key('desktopReferenceOpen').onChange((_selected: boolean): void => { this.invoke(DesktopReferenceAction.OPEN); })
        MenuItem({ content: '复制文件路径', startIcon: $r('app.media.dsh_session_copy') })
          .key('desktopReferenceCopyPath').onChange((_selected: boolean): void => { this.invoke(DesktopReferenceAction.COPY_PATH); })
      }
      MenuItemGroup() {
        if (mimeTypeForName(this.menuTarget?.label ?? '').startsWith('image/')) {
          MenuItem({ content: '复制图片', startIcon: $r('app.media.dsh_session_copy') })
            .key('desktopReferenceCopyImage').onChange((_selected: boolean): void => { this.invoke(DesktopReferenceAction.COPY_IMAGE); })
        }
        MenuItem({ content: '下载', startIcon: $r('app.media.dsh_session_download') })
          .key('desktopReferenceDownload').onChange((_selected: boolean): void => { this.invoke(DesktopReferenceAction.DOWNLOAD); })
      }
      MenuItem({ content: '添加到对话', startIcon: $r('app.media.dsh_reference_menu_plus') })
        .key('desktopReferenceAddToChat').enabled(this.canAddReference)
        .onChange((_selected: boolean): void => { this.invoke(DesktopReferenceAction.ADD_TO_CHAT); })
    }.width(216)
  }

  @Builder
  private Chip(run: DesktopReferenceRun) {
    if (run.kind === 'file') {
      ImageSpan(this.icon(run.kind)).size({ width: 15, height: 15 }).verticalAlign(ImageSpanAlignment.CENTER)
        .onClick((): void => { this.open(run); })
      Span('\u00a0' + run.label).fontColor($r('app.color.desktop_reference_text')).fontWeight(FontWeight.Medium)
        .onClick((): void => { this.open(run); })
    } else {
      ImageSpan(this.icon(run.kind)).size({ width: 15, height: 15 }).verticalAlign(ImageSpanAlignment.CENTER)
      Span('\u00a0' + run.label).fontColor($r('app.color.desktop_reference_text')).fontWeight(FontWeight.Medium)
    }
  }

  build() {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Text(undefined, { controller: this.controller }) {
          ForEach(this.runs, (run: DesktopReferenceRun): void => {
            if (run.kind === 'secret') {
              Span(this.isRevealed(run) ? run.raw : run.masked ?? '')
                .fontSize(this.bodySize * 0.875).fontFamily(this.codeFamily)
              ImageSpan(this.isRevealed(run) ? $r('app.media.dsh_secret_eye_off') : $r('app.media.dsh_secret_eye'))
                .size({ width: Math.max(14, this.bodySize * 0.875), height: Math.max(14, this.bodySize * 0.875) })
                .verticalAlign(ImageSpanAlignment.CENTER)
                .key(this.nodeKey + '-secretToggle-' + run.start)
                .accessibilityText(this.isRevealed(run) ? $r('app.string.desktop_secret_hide') :
                  $r('app.string.desktop_secret_reveal'))
                .onClick((): void => { this.toggleSecret(run); })
            } else if (this.showsChip(run)) {
              this.Chip(run)
            } else {
              Span(run.raw)
            }
          }, (run: DesktopReferenceRun): string => this.runKey(run))
        }.key(this.nodeKey).fontSize(this.bodySize).fontFamily(this.bodyFamily)
        .fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
          .onMouse((event: MouseEvent): void => {
            if (event.button !== MouseButton.Right) { return; }
            if (event.action === MouseAction.Press && this.fileAt(event.x, event.y) !== undefined) {
              event.stopPropagation();
            } else if (event.action === MouseAction.Release && this.showMenuAt(event.x, event.y)) {
              event.stopPropagation();
            }
          })
          .priorityGesture(LongPressGesture({ duration: 420 }).tag(this.referenceGesture).onAction((event: GestureEvent): void => {
            const point = event.fingerList[0];
            if (point !== undefined) { this.showMenuAt(point.localX, point.localY); }
          }))
          .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
            if (info.tag !== this.referenceGesture) { return GestureJudgeResult.CONTINUE; }
            const point = event.fingerList[0];
            return point !== undefined && this.fileAt(point.localX, point.localY) !== undefined ?
              GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
          })
          .onVisibleAreaChange([0.01], (visible: boolean): void => {
            this.visible = visible;
            if (visible) { this.resolvePaths(); }
          })
        Row().width(1).height(1).position(this.menuAnchor).hitTestBehavior(HitTestMode.None)
          .bindContextMenu(this.menuShown, this.FileMenu(), {
            placement: Placement.BottomLeft,
            systemMaterial: desktopMenuOptions(Placement.BottomLeft).systemMaterial,
            onDisappear: (): void => { this.closeFileMenu(); }
          })
      }.padding({ left: 14, right: 14, top: 10, bottom: 10 }).borderRadius(16)
        .backgroundColor($r('app.color.workspace_panel'))
      if (this.referenceLabels.length > 0) {
        Text('引用会话 · ' + this.referenceLabels.join('、')).fontSize(12).fontColor($r('sys.color.font_secondary'))
          .padding({ left: 4, right: 4 })
      }
    }.constraintSize({ maxWidth: '82%' }).alignItems(HorizontalAlign.End)
  }
}
