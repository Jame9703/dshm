import { DesktopCordisRuntime } from './DesktopCordisRuntime';
import type { DesktopCordisPackage, DesktopCordisRow, DesktopCordisSnapshot } from './DesktopCordisRuntime';
import { desktopMenuOptions } from './DesktopMenuOptions';

@Component
export struct DesktopCordisControl {
  runtime?: DesktopCordisRuntime;
  @Prop sessionId: string = '';
  @Prop collapsed: boolean = false;
  onWeb: (session: string) => void = (): void => {};
  @State private rows: DesktopCordisRow[] = [];
  @State private problem: string = '';
  @State private opened: boolean = false;
  @State private versions: Map<string, string> = new Map();
  @State private pending: Set<string> = new Set();
  @State private errors: Map<string, string> = new Map();
  private approvals: Set<string> = new Set();
  private stopWatch?: () => void;
  private dismissedAt: number = 0;

  aboutToAppear(): void {
    this.stopWatch = this.runtime?.watch((snapshot: DesktopCordisSnapshot): void => {
      const approvals = new Set<string>();
      snapshot.rows.forEach((row: DesktopCordisRow): void => {
        if (row.approval) { approvals.add(row.approval); }
      });
      const previous = this.approvals;
      this.approvals = approvals;
      this.problem = snapshot.problem;
      this.rows = snapshot.rows;
      if (this.rows.length === 0) { this.opened = false; }
      if (Array.from(approvals).some((id: string): boolean => !previous.has(id))) { this.opened = true; }
    });
  }

  aboutToDisappear(): void { this.stopWatch?.(); }

  private group(current: boolean): DesktopCordisRow[] {
    const rows = this.rows.filter((row: DesktopCordisRow): boolean => (row.session === this.sessionId) === current);
    return rows.sort((left: DesktopCordisRow, right: DesktopCordisRow): number =>
      Number(right.approval.length > 0) - Number(left.approval.length > 0));
  }

  private packageOf(row: DesktopCordisRow, id: string): DesktopCordisPackage | undefined {
    return row.packages.find((pkg: DesktopCordisPackage): boolean => pkg.id === id);
  }

  private selected(row: DesktopCordisRow): DesktopCordisPackage | undefined {
    return this.packageOf(row, row.approval ? row.target : this.versions.get(row.id) ?? '') ??
      this.packageOf(row, row.next) ?? this.packageOf(row, row.current) ?? row.packages[row.packages.length - 1];
  }

  private runningCount(): number {
    return this.rows.filter((row: DesktopCordisRow): boolean =>
      row.running.length > 0 && this.packageOf(row, row.running)?.hasClient === false).length;
  }

  private status(row: DesktopCordisRow): ResourceStr {
    if (row.approval) { return $r('app.string.desktop_cordis_pending'); }
    if (row.status === 'failed' && row.target === this.selected(row)?.id) {
      return $r('app.string.desktop_cordis_failed');
    }
    if (row.running) {
      return this.packageOf(row, row.running)?.hasClient === true ?
        $r('app.string.desktop_cordis_client_pending') : $r('app.string.desktop_cordis_running');
    }
    return $r('app.string.desktop_cordis_idle');
  }

  private versionMenu(row: DesktopCordisRow): MenuElement[] {
    return row.packages.map((pkg: DesktopCordisPackage): MenuElement => ({
      value: pkg.name + ' · ' + pkg.id,
      action: (): void => { this.versions = new Map(this.versions).set(row.id, pkg.id); }
    }));
  }

  private async act(row: DesktopCordisRow, action: (runtime: DesktopCordisRuntime) => Promise<string>): Promise<void> {
    const runtime = this.runtime;
    if (runtime === undefined || this.pending.has(row.id)) { return; }
    const pending = new Set(this.pending);
    pending.add(row.id);
    this.pending = pending;
    const errors = new Map(this.errors);
    errors.delete(row.id);
    this.errors = errors;
    const error = await action(runtime);
    if (error) { this.errors = new Map(this.errors).set(row.id, error); }
    const remaining = new Set(this.pending);
    remaining.delete(row.id);
    this.pending = remaining;
  }

  private run(row: DesktopCordisRow, pkg?: DesktopCordisPackage): void {
    if (pkg === undefined) { return; }
    if (pkg.hasClient) { this.openWeb(row.session); }
    else { this.act(row, (runtime: DesktopCordisRuntime): Promise<string> => runtime.run(row, pkg)); }
  }

  private openWeb(session: string): void {
    this.opened = false;
    this.onWeb(session);
  }

  @Builder
  private Action(label: Resource, key: string, disabled: boolean, action: () => void, icon?: Resource) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      if (icon !== undefined) {
        Image(icon).width(14).height(14).supportSvg2(true)
      } else {
        Text(label).fontSize(12).fontColor($r('sys.color.font_primary'))
      }
    }
      .key(key).fontSize(12).height(30).padding({ left: 8, right: 8 }).borderRadius(6)
      .focusOnTouch(false).accessibilityText(label).enabled(!disabled).onClick(action)
  }

  @Builder
  private Plugin(row: DesktopCordisRow) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(row.id).fontSize(11).fontColor($r('sys.color.font_tertiary')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 114 })
        Text(this.selected(row)?.name ?? row.id).fontSize(13).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Circle().width(6).height(6)
          .fill(row.status === 'failed' && row.target === this.selected(row)?.id ? $r('sys.color.warning') :
            row.approval || row.running ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
        Text(this.status(row)).fontSize(11).fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      if (row.packages.length > 1) {
        Row({ space: 6 }) {
          Text($r('app.string.desktop_cordis_version')).fontSize(12).fontColor($r('sys.color.font_secondary'))
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 6 }) {
              Text(this.selected(row)?.id ?? '').fontSize(12).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true)
            }
          }
          .key('desktopCordisVersions-' + row.id).height(28).borderRadius(6)
          .enabled(!row.approval && !this.pending.has(row.id))
          .bindMenu(this.versionMenu(row), desktopMenuOptions(Placement.BottomLeft))
        }
      }
      if (this.selected(row)?.purpose) {
        Text(this.selected(row)?.purpose ?? '').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: 4 }) {
        if (row.approval) {
          this.Action($r('app.string.desktop_cordis_open_web'), 'desktopCordisWeb-' + row.id,
            this.pending.has(row.id), (): void => this.openWeb(row.session))
          this.Action($r('app.string.desktop_cordis_decline'), 'desktopCordisDecline-' + row.id,
            this.pending.has(row.id), (): void => {
              this.act(row, (runtime: DesktopCordisRuntime): Promise<string> => runtime.decline(row));
            }, $r('app.media.dsh_dock_close'))
        } else {
          if (this.selected(row) !== undefined &&
            (this.selected(row)?.id !== row.running || this.selected(row)?.hasClient === true)) {
            this.Action(this.selected(row)?.hasClient === true ? $r('app.string.desktop_cordis_open_web') :
              $r('app.string.desktop_cordis_run'), 'desktopCordisRun-' + row.id, this.pending.has(row.id),
              (): void => { this.run(row, this.selected(row)); },
              this.selected(row)?.hasClient === true ? undefined : $r('app.media.dsh_dock_play'))
          }
          if (row.running) {
            this.Action($r('app.string.desktop_cordis_stop'), 'desktopCordisStop-' + row.id,
              this.pending.has(row.id), (): void => {
                this.act(row, (runtime: DesktopCordisRuntime): Promise<string> => runtime.stop(row));
              }, $r('app.media.dsh_cordis_stop_fill'))
          }
          this.Action($r('app.string.desktop_cordis_remove'), 'desktopCordisRemove-' + row.id,
            this.pending.has(row.id), (): void => {
              this.act(row, (runtime: DesktopCordisRuntime): Promise<string> => runtime.remove(row));
            }, $r('app.media.dsh_dock_trash'))
        }
      }.width('100%').justifyContent(FlexAlign.End)
      if (!row.approval && row.next && row.next !== row.current) {
        if (row.current) {
          Text($r('app.string.desktop_cordis_current', row.current)).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        Text($r('app.string.desktop_cordis_next', row.next)).fontSize(12).fontColor($r('sys.color.font_secondary'))
        Row({ space: 4 }) {
          this.Action($r('app.string.desktop_cordis_retry'), 'desktopCordisRetry-' + row.id,
            this.pending.has(row.id), (): void => { this.run(row, this.packageOf(row, row.next)); })
          if (row.current) {
            this.Action($r('app.string.desktop_cordis_rollback'), 'desktopCordisRollback-' + row.id,
              this.pending.has(row.id), (): void => { this.run(row, this.packageOf(row, row.current)); })
          }
        }
      }
      if (this.errors.get(row.id) || row.problem) {
        Text(this.errors.get(row.id) || row.problem).fontSize(12).fontColor($r('sys.color.warning'))
          .key('desktopCordisError-' + row.id)
      }
      if (row.running && row.running !== this.selected(row)?.id) {
        Text($r('app.string.desktop_cordis_current', row.running)).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
    }
    .key('desktopCordisRow-' + row.id)
    .width('100%').alignItems(HorizontalAlign.Start).padding(10).borderRadius(8)
    .border({ width: 1, color: $r('app.color.workspace_border') })
  }

  @Builder
  private Panel() {
    Column() {
      Text($r('app.string.desktop_cordis_title')).height(44).width('100%').padding({ left: 12, right: 12 })
        .fontSize(14).fontWeight(FontWeight.Medium)
      Scroll() {
        Column({ space: 6 }) {
          if (this.problem) {
            Text(this.problem).fontSize(12).fontColor($r('sys.color.warning'))
          }
          if (this.group(true).length > 0) {
            Text($r('app.string.desktop_cordis_group_current')).fontSize(12)
              .fontColor($r('sys.color.font_secondary')).padding({ top: 6 })
            ForEach(this.group(true), (row: DesktopCordisRow) => { this.Plugin(row) },
              (row: DesktopCordisRow): string => JSON.stringify(row))
          }
          if (this.group(false).length > 0) {
            Text($r('app.string.desktop_cordis_group_other')).fontSize(12)
              .fontColor($r('sys.color.font_secondary')).padding({ top: 6 })
            ForEach(this.group(false), (row: DesktopCordisRow) => { this.Plugin(row) },
              (row: DesktopCordisRow): string => JSON.stringify(row))
          }
        }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 12, right: 12, bottom: 12 })
      }.width('100%').constraintSize({ maxHeight: 384 })
    }.key('desktopCordisPanel').width(420)
  }

  build() {
    if (this.rows.length > 0) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Image($r('app.media.dsh_cordis_plugin_outline')).width(16).height(16).supportSvg2(true)
          if (!this.collapsed) {
            Text('Cordis Plugin').fontSize(14).layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text($r('app.string.desktop_cordis_count', this.runningCount())).fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
          }
        }.width(this.collapsed ? 16 : '100%')
      }
      .key('desktopCordisToggle').width('100%').height(this.collapsed ? 36 : 42).borderRadius(12)
      .padding({ left: this.collapsed ? 0 : 8, right: this.collapsed ? 0 : 10 })
      .backgroundColor(this.opened || this.rows.some((row: DesktopCordisRow): boolean => !!row.approval) ?
        $r('app.color.workspace_selection') : Color.Transparent)
      .focusOnTouch(false).accessibilityText($r('app.string.desktop_cordis_title')).accessibilitySelected(this.opened)
      .onClick((): void => {
        // ArkUI can dismiss the popup on pointer down and then deliver the anchor's click on release.
        if (!this.opened && Date.now() - this.dismissedAt < 150) { return; }
        this.opened = !this.opened;
        if (this.opened) { this.runtime?.refresh(); }
      })
      .bindPopup(this.opened, { builder: this.Panel(), placement: Placement.TopLeft,
        enableArrow: false, focusable: true, mask: false,
        systemMaterial: desktopMenuOptions(Placement.TopLeft).systemMaterial,
        onStateChange: (event): void => {
          if (!event.isVisible && this.opened) {
            this.dismissedAt = Date.now();
            this.opened = false;
          }
        } })
    }
  }
}
