import type { SessionListItem } from 'appstate';
import { getRecord, getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { desktopSubagentCatalog, desktopSubagentModeLabel, desktopSubagentRows } from './DesktopSubagents';
import type { DesktopSubagentEntry, DesktopSubagentRow } from './DesktopSubagents';

interface DesktopSubagentBranch {
  id: string;
  state: string;
  entries: DesktopSubagentEntry[];
}

interface DesktopSubagentTreeRow {
  row: DesktopSubagentRow;
  parents: DesktopSubagentEntry[];
}

@Component
export struct DesktopSubagentsControl {
  host?: DesktopHostActions;
  @Prop @Watch('ownerChanged') sessionId: string = '';
  @Prop child?: DesktopSubagentEntry = undefined;
  @Prop entries: DesktopSubagentEntry[] = [];
  @Prop summaries: SessionListItem[] = [];
  onOpen: (item: DesktopSubagentEntry, parents: DesktopSubagentEntry[]) => void = (): void => {};
  onOpenAside: (item: DesktopSubagentEntry, parents: DesktopSubagentEntry[]) => void = (): void => {};
  @State private shown: boolean = false;
  @State private unfolded: boolean = false;
  @State private expanded: string[] = [];
  @State private branches: DesktopSubagentBranch[] = [];
  private readonly folds: Map<string, boolean> = new Map<string, boolean>();
  private generation: number = 0;

  aboutToDisappear(): void { this.generation++; }

  private ownerChanged(): void {
    this.generation++;
    this.shown = false;
    this.expanded = [];
    this.branches = [];
    this.unfolded = this.folds.get(this.sessionId) === true;
  }

  private rootId(): string { return this.child?.parentId ?? this.sessionId; }

  private branch(id: string): DesktopSubagentBranch | undefined {
    return this.branches.find((branch: DesktopSubagentBranch): boolean => branch.id === id);
  }

  private listedChildren(id: string): DesktopSubagentEntry[] | undefined {
    const item = this.summaries.find((row: SessionListItem): boolean => row.id === id);
    return desktopSubagentCatalog(id, getRecord(getRecord(item?.raw, 'projections'), 'values'));
  }

  private rootRows(): DesktopSubagentRow[] {
    const root = this.rootId();
    const children = root === this.sessionId ? this.entries : this.branch(root)?.entries ?? this.listedChildren(root) ?? [];
    return desktopSubagentRows(children, this.summaries);
  }

  private expandRows(rows: DesktopSubagentRow[], parents: DesktopSubagentEntry[], out: DesktopSubagentTreeRow[]): void {
    for (const row of rows) {
      if (row.entry.id === this.rootId() || parents.some((parent: DesktopSubagentEntry): boolean => parent.id === row.entry.id)) {
        continue;
      }
      out.push({ row: row, parents: parents });
      if (this.expanded.includes(row.entry.id)) {
        const entries = row.entry.id === this.sessionId ? this.entries : this.branch(row.entry.id)?.entries ?? [];
        this.expandRows(desktopSubagentRows(entries, this.summaries), parents.concat([row.entry]), out);
      }
    }
  }

  private visibleRows(): DesktopSubagentTreeRow[] {
    const root = this.rootRows();
    const result: DesktopSubagentTreeRow[] = [];
    this.expandRows(root.length > 6 && !this.unfolded ? root.slice(0, 5) : root, [], result);
    return result;
  }

  private setBranch(branch: DesktopSubagentBranch): void {
    this.branches = this.branches.filter((old: DesktopSubagentBranch): boolean => old.id !== branch.id).concat([branch]);
  }

  private async loadBranch(id: string): Promise<void> {
    if (!id || id === this.sessionId || this.branch(id)?.state === 'loading') { return; }
    const generation = this.generation;
    const entries = this.branch(id)?.entries ?? this.listedChildren(id) ?? [];
    this.setBranch({ id: id, state: 'loading', entries: entries });
    const result = await this.host?.call('session/projections', { 'sessionId': id });
    if (generation !== this.generation) { return; }
    const rows = desktopSubagentCatalog(id, getRecord(result?.value, 'values'));
    this.setBranch({ id: id, state: result?.ok === true ? 'ready' : 'error', entries: rows ?? entries });
  }

  private canExpand(row: DesktopSubagentRow): boolean {
    if (row.status === 'external') { return false; }
    const id = row.entry.id;
    if (id === this.sessionId) { return this.entries.length > 0; }
    const branch = this.branch(id);
    if (branch?.state === 'ready') { return branch.entries.length > 0; }
    const item = this.summaries.find((summary: SessionListItem): boolean => summary.id === id);
    if (getString(item?.raw, 'formatStatus') === 'migration-required') { return false; }
    return (this.listedChildren(id)?.length ?? 1) > 0;
  }

  private toggleBranch(id: string): void {
    if (this.expanded.includes(id)) {
      this.expanded = this.expanded.filter((item: string): boolean => item !== id);
    } else {
      this.expanded = this.expanded.concat([id]);
      if (this.branch(id)?.state !== 'ready') { this.loadBranch(id); }
    }
  }

  private open(node: DesktopSubagentTreeRow): void {
    if (node.row.status === 'external') { return; }
    this.shown = false;
    this.onOpen(node.row.entry, node.parents);
  }

  private progress(): string {
    const rows = this.rootRows();
    const labels: string[] = [];
    const completed = rows.filter((row: DesktopSubagentRow): boolean => row.status === 'completed').length;
    const running = rows.filter((row: DesktopSubagentRow): boolean => row.status === 'running').length;
    const inactive = rows.filter((row: DesktopSubagentRow): boolean => row.status === 'inactive').length;
    const external = rows.length - completed - running - inactive;
    if (completed > 0) { labels.push(`${completed} 已完成`); }
    if (running > 0) { labels.push(`${running} 运行中`); }
    if (inactive > 0) { labels.push(`${inactive} 未运行`); }
    if (external > 0) { labels.push(`${external} 外部`); }
    return labels.join(' · ');
  }

  @Builder
  private BranchState(id: string) {
    if (this.branch(id)?.state === 'loading') {
      Text('正在加载子智能体…').fontSize(12).fontColor($r('sys.color.font_secondary'))
    } else if (this.branch(id)?.state === 'error') {
      Row({ space: 8 }) {
        Text('无法加载子智能体').fontSize(12).fontColor($r('sys.color.font_secondary'))
        Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.loadBranch(id); })
      }
    }
  }

  @Builder
  private TreeRow(node: DesktopSubagentTreeRow) {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        if (this.canExpand(node.row)) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10)
              .rotate({ angle: this.expanded.includes(node.row.entry.id) ? 90 : 0 })
          }.key('desktopSubagentExpand-' + node.row.entry.id).width(26).height(30).padding(0).focusOnTouch(false)
            .accessibilityText((this.expanded.includes(node.row.entry.id) ? '收起 ' : '展开 ') + node.row.title)
            .onClick((): void => { this.toggleBranch(node.row.entry.id); })
        } else { Blank().width(26) }
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 8 }) {
            Circle().width(7).height(7).fill(node.row.status === 'running' ? $r('sys.color.brand') :
              node.row.status === 'completed' ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
            Column({ space: 2 }) {
              Text(node.row.title).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(desktopSubagentModeLabel(node.row.entry.mode) +
                (node.row.status === 'running' ? ' · 运行中' : node.row.status === 'completed' ? ' · 已完成' :
                  node.row.status === 'inactive' ? ' · 未运行' : ''))
                .fontSize(11).fontColor($r('sys.color.font_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (node.row.entry.id === this.sessionId) { Text('✓').fontSize(13) }
          }.width('100%')
        }.key('desktopSubagentOpen-' + node.row.entry.id).layoutWeight(1).height(48).padding({ left: 6, right: 8 })
          .enabled(node.row.status !== 'external').focusOnTouch(false).onClick((): void => { this.open(node); })
        if (node.row.status !== 'external' && node.row.entry.id !== this.sessionId) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.sidebar_toggle')).width(14).height(14).rotate({ angle: 180 })
              .fillColor($r('sys.color.font_secondary')).accessibilityLevel('no')
          }.key('desktopSubagentAside-' + node.row.entry.id).width(30).height(34).padding(0).focusOnTouch(false)
            .accessibilityText('在右侧打开 ' + node.row.title).onClick((): void => {
              this.shown = false;
              this.onOpenAside(node.row.entry, node.parents);
            })
        }
      }.width('100%')
      if (this.expanded.includes(node.row.entry.id)) { this.BranchState(node.row.entry.id) }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Math.min(8, node.parents.length) * 14 })
  }

  @Builder
  private Panel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('子智能体').fontSize(16).fontWeight(FontWeight.Medium)
        Text(this.progress()).fontSize(12).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      }.width('100%').padding({ left: 8, right: 8 })
      this.BranchState(this.rootId())
      if (this.rootRows().length === 0 && this.branch(this.rootId())?.state === 'ready') {
        Text('没有子智能体').fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.visibleRows(), (node: DesktopSubagentTreeRow): void => { this.TreeRow(node) },
            (node: DesktopSubagentTreeRow): string => JSON.stringify([node.row.entry.parentId, node.row.entry.id,
              node.row.entry.mode, node.row.title, node.row.status, node.parents.length]))
          if (this.rootRows().length > 6) {
            Button(this.unfolded ? '收起' : `再显示 ${this.rootRows().length - 5} 个`, { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick((): void => { this.unfolded = !this.unfolded; this.folds.set(this.sessionId, this.unfolded); })
          }
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 360 }).align(Alignment.TopStart)
    }.width(344).padding(12).alignItems(HorizontalAlign.Start)
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.person_2')).fontSize(16).accessibilityLevel('no')
        if (!this.shown && this.entries.some((entry: DesktopSubagentEntry): boolean => entry.mode !== 'external' &&
          this.summaries.some((summary: SessionListItem): boolean => summary.id === entry.id && summary.running))) {
          Circle().width(6).height(6).fill($r('sys.color.brand'))
        }
      }
    }.width(36).height(34).padding(0).focusOnTouch(false).key('desktopSubagentsToggle').accessibilityText('子智能体')
      .onClick((): void => {
        this.shown = !this.shown;
        if (this.shown) { this.loadBranch(this.rootId()); }
      })
      .bindPopup(this.shown, { builder: this.Panel(), placement: Placement.BottomRight, enableArrow: false,
        systemMaterial: desktopMenuOptions(Placement.BottomRight).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible) { this.shown = false; } } })
  }
}
