import { DesktopHostActions } from './DesktopHostActions';

export interface DesktopReferenceRun {
  kind: string;
  raw: string;
  label: string;
  path: string;
  start: number;
}

function textRun(raw: string, start: number): DesktopReferenceRun {
  return { kind: 'text', raw: raw, label: '', path: '', start: start };
}

export function desktopReferenceRuns(text: string, sessionLabels: string[]): DesktopReferenceRun[] {
  const runs: DesktopReferenceRun[] = [];
  const wire = /@\[((?:\\.|[^\\\]\r\n])+)\]\(dsh-session:[A-Za-z0-9_-]+\)/uy;
  const pathToken = /@"[^"\r\n]+"|@[^\s"]+/uy;
  let emitted = 0;
  let next = text.indexOf('@');
  while (next >= 0) {
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
    if (part === undefined) {
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
  @Prop @Watch('refresh') text: string = '';
  @Prop @Watch('refresh') referenceLabels: string[] = [];
  @Prop @Watch('refresh') sessionId: string = '';
  @Prop nodeKey: string = '';
  host?: DesktopHostActions;
  onFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  @State private runs: DesktopReferenceRun[] = [];
  @State private confirmed: string[] = [];
  private active: boolean = false;
  private visible: boolean = false;
  private requested: boolean = false;
  private revision: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.refresh();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.visible = false;
    this.revision++;
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
      Text() {
        ForEach(this.runs, (run: DesktopReferenceRun): void => {
          if (run.kind === 'session' || (run.path && this.confirmed.includes(run.path))) {
            this.Chip(run)
          } else {
            Span(run.raw)
          }
        }, (run: DesktopReferenceRun): string => String(run.start) + ':' + run.raw)
      }.key(this.nodeKey).fontSize(15).fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 }).borderRadius(16)
        .backgroundColor($r('app.color.workspace_panel'))
        .onVisibleAreaChange([0.01], (visible: boolean): void => {
          this.visible = visible;
          if (visible) { this.resolvePaths(); }
        })
      if (this.referenceLabels.length > 0) {
        Text('引用会话 · ' + this.referenceLabels.join('、')).fontSize(12).fontColor($r('sys.color.font_secondary'))
          .padding({ left: 4, right: 4 })
      }
    }.constraintSize({ maxWidth: '82%' }).alignItems(HorizontalAlign.End)
  }
}
