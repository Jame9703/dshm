import type { SessionListItem } from 'appstate';
import { getRecord, getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { desktopSubagentCatalog, desktopSubagentDurationLabel, desktopSubagentModeLabel, desktopSubagentRows,
  desktopSubagentTokenLabel } from './DesktopSubagents';
import type { DesktopSubagentEntry, DesktopSubagentRow } from './DesktopSubagents';
import { desktopTeamBoardVisible } from './DesktopTeam';
import type { DesktopTeam, DesktopTeamTask } from './DesktopTeam';

interface DesktopSubagentBranch {
  id: string;
  state: string;
  entries: DesktopSubagentEntry[];
  projection?: Object;
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
  @Prop @Watch('catalogChanged') entries: DesktopSubagentEntry[] = [];
  @Prop team?: DesktopTeam = undefined;
  @Prop @Watch('syncMetricClock') summaries: SessionListItem[] = [];
  onOpen: (item: DesktopSubagentEntry, parents: DesktopSubagentEntry[]) => void = (): void => {};
  onOpenAside: (item: DesktopSubagentEntry, parents: DesktopSubagentEntry[]) => void = (): void => {};
  @State @Watch('syncMetricClock') private shown: boolean = false;
  @State private clockMs: number = 0;
  private clockTimer: number = -1;
  @State private unfolded: boolean = false;
  @State private expanded: string[] = [];
  @State private branches: DesktopSubagentBranch[] = [];
  @State private teamUnfolded: boolean = false;
  @State private taskExpanded: string = '';
  @State private taskHovered: string = '';
  private taskHoverTimer: number = -1;
  private readonly teamFolds: Map<string, boolean> = new Map<string, boolean>();
  private readonly folds: Map<string, boolean> = new Map<string, boolean>();
  private readonly branchLoads: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private generation: number = 0;
  private metricLoadGeneration: number = 0;

  aboutToDisappear(): void {
    this.generation++;
    this.branchLoads.clear();
    this.stopMetricClock();
    this.hoverTask('');
  }

  private stopMetricClock(): void {
    if (this.clockTimer < 0) { return; }
    clearInterval(this.clockTimer);
    this.clockTimer = -1;
  }

  private syncMetricClock(): void {
    if (!this.shown) {
      this.stopMetricClock();
      this.hoverTask('');
      return;
    }
    this.clockMs = Date.now();
    if (this.summaries.some((summary: SessionListItem): boolean => summary.running)) {
      if (this.clockTimer < 0) {
        this.clockTimer = setInterval((): void => { this.clockMs = Date.now(); }, 1000);
      }
    } else {
      this.stopMetricClock();
    }
  }

  private ownerChanged(): void {
    this.generation++;
    this.shown = false;
    this.expanded = [];
    this.branchLoads.clear();
    this.branches = [];
    this.unfolded = this.folds.get(this.sessionId) === true;
    this.teamUnfolded = this.teamFolds.get(this.sessionId) === true;
    this.taskExpanded = '';
  }

  private rootId(): string { return this.child?.parentId ?? this.sessionId; }

  private branch(id: string): DesktopSubagentBranch | undefined {
    return this.branches.find((branch: DesktopSubagentBranch): boolean => branch.id === id);
  }

  private listedChildren(id: string): DesktopSubagentEntry[] | undefined {
    const item = this.summaries.find((row: SessionListItem): boolean => row.id === id);
    return desktopSubagentCatalog(id, getRecord(getRecord(item?.raw, 'projections'), 'values'));
  }

  private loadedProjections(): Map<string, Object> {
    const projections = new Map<string, Object>();
    for (const branch of this.branches) {
      if (branch.projection !== undefined) { projections.set(branch.id, branch.projection); }
    }
    return projections;
  }

  private rootRows(projections: Map<string, Object> = this.loadedProjections()): DesktopSubagentRow[] {
    const root = this.rootId();
    const children = root === this.sessionId ? this.entries : this.branch(root)?.entries ?? this.listedChildren(root) ?? [];
    return desktopSubagentRows(children, this.summaries, projections);
  }

  private expandRows(rows: DesktopSubagentRow[], parents: DesktopSubagentEntry[], out: DesktopSubagentTreeRow[],
    projections: Map<string, Object>): void {
    for (const row of rows) {
      if (row.entry.id === this.rootId() || parents.some((parent: DesktopSubagentEntry): boolean => parent.id === row.entry.id)) {
        continue;
      }
      out.push({ row: row, parents: parents });
      if (this.expanded.includes(row.entry.id)) {
        const entries = row.entry.id === this.sessionId ? this.entries : this.branch(row.entry.id)?.entries ?? [];
        this.expandRows(desktopSubagentRows(entries, this.summaries, projections), parents.concat([row.entry]), out, projections);
      }
    }
  }

  private visibleRows(): DesktopSubagentTreeRow[] {
    const projections = this.loadedProjections();
    const root = this.rootRows(projections);
    const result: DesktopSubagentTreeRow[] = [];
    this.expandRows(root.length > 6 && !this.unfolded ? root.slice(0, 5) : root, [], result, projections);
    return result;
  }

  private setBranch(branch: DesktopSubagentBranch): void {
    this.branches = this.branches.filter((old: DesktopSubagentBranch): boolean => old.id !== branch.id).concat([branch]);
  }

  private catalogChanged(): void {
    if (this.shown) { this.prepareMetrics(); }
  }

  private loadBranch(id: string): Promise<void> {
    if (!id || id === this.sessionId) { return Promise.resolve(); }
    const pending = this.branchLoads.get(id);
    if (pending !== undefined) { return pending; }
    const read = this.readBranch(id, this.generation);
    this.branchLoads.set(id, read);
    return read;
  }

  private async readBranch(id: string, generation: number): Promise<void> {
    const previous = this.branch(id);
    const entries = previous?.entries ?? this.listedChildren(id) ?? [];
    this.setBranch({ id: id, state: 'loading', entries: entries, projection: previous?.projection });
    const result = await this.host?.call('session/projections', { 'sessionId': id });
    if (generation !== this.generation) { return; }
    const projection = result?.ok === true ? result.value : undefined;
    const rows = desktopSubagentCatalog(id, getRecord(projection, 'values'));
    this.setBranch({ id: id, state: projection !== undefined ? 'ready' : 'error',
      entries: rows ?? entries, projection: projection ?? previous?.projection });
    this.branchLoads.delete(id);
  }

  private async prepareMetrics(parentId?: string): Promise<void> {
    const generation = this.generation;
    const request = ++this.metricLoadGeneration;
    if (parentId !== undefined && this.branch(parentId)?.state !== 'ready') { await this.loadBranch(parentId); }
    for (const node of this.visibleRows()) {
      if (!this.shown || generation !== this.generation || request !== this.metricLoadGeneration) { return; }
      const row = node.row;
      const id = row.entry.id;
      if (row.status === 'external' || (row.tokens !== undefined && row.settledMs !== undefined) ||
        this.branch(id) !== undefined || this.summaries.some((summary: SessionListItem): boolean =>
          summary.id === id && getString(summary.raw, 'formatStatus') === 'migration-required')) { continue; }
      await this.loadBranch(id);
    }
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
      this.prepareMetrics(id);
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
  private Metrics(row: DesktopSubagentRow) {
    if (row.tokens !== undefined || row.settledMs !== undefined) {
      Column({ space: 2 }) {
        if (row.tokens !== undefined) {
          Text(desktopSubagentTokenLabel(row.tokens)).fontSize(11).maxLines(1)
            .fontColor($r('sys.color.font_secondary'))
        }
        if (row.settledMs !== undefined) {
          Text(desktopSubagentDurationLabel(row, this.clockMs)).fontSize(11).maxLines(1)
            .fontColor($r('sys.color.font_secondary'))
            .accessibilityText(desktopSubagentDurationLabel(row, this.clockMs, true))
        }
      }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: 84 })
    }
  }

  @Builder
  private TreeRow(node: DesktopSubagentTreeRow) {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        if (this.canExpand(node.row)) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([$r('sys.color.font_secondary')])
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
              Text(node.row.title).fontSize(13).fontColor($r('sys.color.font_primary'))
                .fontWeight(node.row.entry.id === this.sessionId ? FontWeight.Medium : FontWeight.Regular)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(desktopSubagentModeLabel(node.row.entry.mode) +
                (node.row.status === 'running' ? ' · 运行中' : node.row.status === 'completed' ? ' · 已完成' :
                  node.row.status === 'inactive' ? ' · 未运行' : ''))
                .fontSize(11).fontColor($r('sys.color.font_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            this.Metrics(node.row)
            if (node.row.entry.id === this.sessionId) {
              Image($r('app.media.dsh_dock_check')).width(16).height(16).supportSvg2(true)
                .draggable(false).accessibilityLevel('no')
            }
          }.width('100%')
        }.key('desktopSubagentOpen-' + node.row.entry.id).layoutWeight(1).height(48).padding({ left: 6, right: 8 })
          .enabled(node.row.status !== 'external').focusOnTouch(false).onClick((): void => { this.open(node); })
        if (node.row.status !== 'external' && node.row.entry.id !== this.sessionId) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_sidebar_panel_outline')).width(14).height(14).rotate({ angle: 180 })
              .supportSvg2(true).draggable(false)
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

  private hasTree(): boolean { return this.child !== undefined || this.entries.length > 0; }

  private hoverTask(id: string): void {
    clearTimeout(this.taskHoverTimer);
    this.taskHoverTimer = -1;
    if (!id || this.taskExpanded === id) { this.taskHovered = ''; return; }
    this.taskHoverTimer = setTimeout((): void => { this.taskHovered = id; }, this.taskHovered ? 0 : 350);
  }

  private taskStatus(task: DesktopTeamTask): string {
    return task.blocked ? '被依赖阻塞' : task.status === 'in_progress' ? '进行中' :
      task.status === 'completed' ? '已完成' : '待处理';
  }

  @Builder
  private TaskPreview(task: DesktopTeamTask) {
    Column({ space: 5 }) {
      Text(task.subject).fontSize(14).fontWeight(FontWeight.Medium)
      Text(this.taskStatus(task)).fontSize(12).fontColor($r('sys.color.font_secondary'))
      Text('负责人：' + task.owner).fontSize(12)
      if (task.description) { Text(task.description).fontSize(12).maxLines(8).textOverflow({ overflow: TextOverflow.Ellipsis }) }
    }.width(240).padding(12).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TaskRow(task: DesktopTeamTask) {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Circle().width(7).height(7).fill(task.blocked ? $r('sys.color.warning') : task.status === 'in_progress' ?
            $r('sys.color.brand') : task.status === 'completed' ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
          Text(task.subject).fontSize(13).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14).supportSvg2(true)
            .rotate({ angle: this.taskExpanded === task.id ? 180 : 0 }).accessibilityLevel('no')
        }.width('100%')
      }.key('desktopTeamTask-' + task.id).width('100%').height(34).padding({ left: 8, right: 8 }).focusOnTouch(false)
        .accessibilityText(task.subject + ' · ' + this.taskStatus(task)).accessibilitySelected(this.taskExpanded === task.id)
        .onClick((): void => {
          this.hoverTask('');
          this.taskExpanded = this.taskExpanded === task.id ? '' : task.id;
        })
        .onHover((hovered: boolean): void => { this.hoverTask(hovered ? task.id : ''); })
        .bindPopup(this.taskHovered === task.id, { builder: this.TaskPreview(task), placement: Placement.Right,
          enableArrow: false, systemMaterial: desktopMenuOptions(Placement.Right).systemMaterial })
      if (this.taskExpanded === task.id) {
        Column({ space: 4 }) {
          if (task.description) { Text(task.description).fontSize(13) }
          Text('负责人：' + task.owner).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 22, right: 8, bottom: 4 })
      }
    }.width('100%')
  }

  @Builder
  private SharedTasks() {
    Row({ space: 8 }) {
      Text('共享任务').fontSize(16).fontWeight(FontWeight.Medium)
      Text(this.team?.progress ?? '').key('desktopTeamProgress').fontSize(12).layoutWeight(1)
        .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').padding({ left: 8, right: 8 })
    if (this.team?.failure) {
      Text('任务记录无效：' + this.team.failure).fontSize(12).padding({ left: 8, right: 8 })
        .fontColor($r('sys.color.warning'))
    }
    ForEach((this.team?.tasks.length ?? 0) > 6 && !this.teamUnfolded ? this.team?.tasks.slice(0, 5) ?? [] :
      this.team?.tasks ?? [], (task: DesktopTeamTask): void => { this.TaskRow(task) },
      (task: DesktopTeamTask): string => JSON.stringify(task))
    if ((this.team?.tasks.length ?? 0) > 6) {
      Button(this.teamUnfolded ? '收起' : `显示其余 ${(this.team?.tasks.length ?? 5) - 5} 个`,
        { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopTeamFold').onClick((): void => {
        this.teamUnfolded = !this.teamUnfolded;
        this.teamFolds.set(this.sessionId, this.teamUnfolded);
      })
    }
  }

  @Builder
  private MemberTree() {
    Row({ space: 8 }) {
      Text('子智能体').fontSize(16).fontWeight(FontWeight.Medium)
      Text(this.progress()).fontSize(12).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
    }.width('100%').padding({ left: 8, right: 8 })
    this.BranchState(this.rootId())
    if (this.rootRows().length === 0 && this.branch(this.rootId())?.state === 'ready') {
      Text('没有子智能体').fontSize(13).fontColor($r('sys.color.font_secondary'))
    }
    ForEach(this.visibleRows(), (node: DesktopSubagentTreeRow): void => { this.TreeRow(node) },
      (node: DesktopSubagentTreeRow): string => JSON.stringify([node.row.entry.parentId, node.row.entry.id,
        node.row.entry.mode, node.row.title, node.row.status, node.parents.length, node.row.tokens,
        node.row.settledMs, node.row.turnSince, node.row.turnThrough]))
    if (this.rootRows().length > 6) {
      Button(this.unfolded ? '收起' : `再显示 ${this.rootRows().length - 5} 个`, { buttonStyle: ButtonStyleMode.TEXTUAL })
        .onClick((): void => {
          this.unfolded = !this.unfolded;
          this.folds.set(this.sessionId, this.unfolded);
          if (this.unfolded) { this.prepareMetrics(); }
        })
    }
  }

  @Builder
  private Panel() {
    Scroll() {
      Column({ space: 6 }) {
        if (this.hasTree()) { this.MemberTree() }
        if (desktopTeamBoardVisible(this.team)) { this.SharedTasks() }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
    }.width(344).constraintSize({ maxHeight: 420 }).align(Alignment.TopStart)
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 3 }) {
        if (this.hasTree()) {
          SymbolGlyph($r('sys.symbol.person_2')).fontSize(16).fontColor([$r('sys.color.font_primary')]).accessibilityLevel('no')
        } else {
          Image($r('app.media.dsh_team_users_outline')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
        }
        if (!this.shown && this.entries.some((entry: DesktopSubagentEntry): boolean => entry.mode !== 'external' &&
          this.summaries.some((summary: SessionListItem): boolean => summary.id === entry.id && summary.running))) {
          Circle().width(6).height(6).fill($r('sys.color.brand'))
        }
      }
    }.width(36).height(34).padding(0).focusOnTouch(false).key('desktopSubagentsToggle')
      .accessibilityText(this.hasTree() ? '子智能体' : '共享任务')
      .onClick((): void => {
        this.shown = !this.shown;
        if (this.shown) { this.prepareMetrics(this.rootId()); }
      })
      .bindPopup(this.shown, { builder: this.Panel(), placement: Placement.BottomRight, enableArrow: false,
        systemMaterial: desktopMenuOptions(Placement.BottomRight).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible) { this.shown = false; } } })
  }
}
