import { dialogMaterial } from 'platform';
import { getArray, getNumber, getRecord, getString } from 'connection';
import type { RpcResult } from 'connection';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopScheduleCatalog, desktopScheduleNextTime, desktopScheduleRows,
  desktopScheduleShowsRecommendations } from './DesktopScheduleCatalog';
import type { DesktopScheduleCatalogSnapshot } from './DesktopScheduleCatalog';
import { DesktopScheduleRecommendations } from './DesktopScheduleRecommendations';

interface ScheduleRuleChoice {
  id: string;
  title: string;
  placeholder: string;
}

const RULES: ScheduleRuleChoice[] = [
  { 'id': 'after', 'title': '延时一次', placeholder: '延时（分钟）' },
  { 'id': 'at', 'title': '指定时间', placeholder: '日期 YYYY-MM-DD' },
  { 'id': 'every', 'title': '固定间隔', placeholder: '间隔（分钟）' },
  { 'id': 'daily', 'title': '每天', placeholder: '时间 HH:mm:ss' },
  { 'id': 'weekly', 'title': '每周', placeholder: '时间 HH:mm:ss' },
  { 'id': 'cron', 'title': 'Cron 表达式', placeholder: '分 时 日 月 周' },
  { 'id': 'rrule', 'title': '日历重复规则', placeholder: '' }
];

const TARGETS: ScheduleRuleChoice[] = [
  { 'id': 'new_once', 'title': '新建并复用一个会话', placeholder: '' },
  { 'id': 'new', 'title': '每次创建新会话', placeholder: '' },
  { 'id': 'session', 'title': '使用现有会话', placeholder: '' }
];

function formatTime(iso: string): string {
  const value = Date.parse(iso);
  return Number.isNaN(value) ? iso : new Date(value).toLocaleString();
}

@Component
export struct DesktopSchedulePane {
  host?: DesktopHostActions;
  catalog?: DesktopScheduleCatalog;
  @Prop sessionId: string = '';
  @Prop workspacePath: string = '';
  @Prop draftBusy: boolean = false;
  onOpenSession: (id: string) => void = (_: string): void => {};
  onDraft: (prompt: Resource) => void = (_: Resource): void => {};
  onWeb: () => void = (): void => {};
  @State private tasks: Object[] = [];
  @State private rows: Object[] = [];
  @State private catalogError: string = '';
  @State private catalogLoading: boolean = false;
  @State private catalogReady: boolean = false;
  @State private filter: string = 'active';
  @State private search: string = '';
  @State private paneWidth: number = 0;
  @State private conflict: boolean = false;
  private stopCatalog?: () => void;
  private originalTitle: string = '';
  private originalPrompt: string = '';
  private failureCode: string = '';
  private confirmId: number = -1;
  private confirmOpening: boolean = false;
  private confirmVersion: number = 0;
  @State private deliveries: Object[] = [];
  @State private nextBefore: string = '';
  @State private historyId: string = '';
  @State private status: string = '';
  @State private busy: boolean = false;
  @State private editing: boolean = false;
  @State private editId: string = '';
  @State private revision: string = '';
  @State private title: string = '';
  @State private prompt: string = '';
  @State private kind: string = 'after';
  @State private rule: string = '';
  @State private time: string = '';
  @State private zone: string = 'Asia/Shanghai';
  @State private weekday: number[] = [];
  @State private targetKind: string = 'new_once';
  @State private targetSession: string = '';
  @State private cwd: string = '';
  @State private preset: string = '';
  private originalKind: string = '';
  private originalRule: string = '';
  private originalTime: string = '';
  private originalZone: string = '';
  private originalWeekdays: string = '';
  private originalTarget: string = '';
  private originalSession: string = '';
  private originalDirectory: string = '';
  private originalPreset: string = '';
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.stopCatalog = this.catalog?.watch((snapshot: DesktopScheduleCatalogSnapshot): void => {
      if (!this.active) { return; }
      this.tasks = snapshot.tasks;
      this.refilter();
      this.catalogError = snapshot.error;
      this.catalogLoading = snapshot.loading;
      this.catalogReady = snapshot.ready;
      if (!snapshot.loading && !snapshot.error && this.detailId() && !this.taskById(this.detailId()) &&
          !this.hasDraftChanges()) { this.closeDetail(); }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.stopCatalog?.();
    this.stopCatalog = undefined;
    this.closeConfirm();
  }

  private async invoke(endpoint: string, payload: Record<string, Object | null> = {}): Promise<RpcResult | undefined> {
    if (this.host === undefined || this.busy) {
      return undefined;
    }
    this.busy = true;
    this.status = '';
    this.failureCode = '';
    let result: RpcResult;
    try {
      result = await this.host.call(endpoint, payload);
    } catch (_) {
      if (this.active) {
        this.busy = false;
        this.status = '宿主请求失败';
      }
      return undefined;
    }
    if (!this.active) {
      return undefined;
    }
    this.busy = false;
    this.failureCode = result.error?.code || getString(result.value, 'code') || '';
    this.status = desktopHostProblem(result);
    return this.status.length === 0 ? result : undefined;
  }

  private async refresh(): Promise<boolean> { return await this.catalog?.refresh() ?? false; }

  private taskById(id: string): Object | undefined {
    return this.tasks.find((row: Object): boolean => getString(row, 'id') === id);
  }

  private refilter(): void {
    this.rows = desktopScheduleRows(this.tasks, this.filter, this.search);
  }

  private catalogActions(): MenuElement[] {
    return [{ value: $r('app.string.desktop_schedule_clear'), enabled: !this.catalogLoading,
      action: (): void => { this.confirmDelete(); } }];
  }

  private openDraft(prompt: Resource): void {
    if (this.active && !this.busy && !this.draftBusy) { this.onDraft(prompt); }
  }

  private creationActions(): MenuElement[] {
    return [
      { value: $r('app.string.desktop_schedule_creation_create_chat'), icon: $r('app.media.dsh_reference_session'),
        action: (): void => { this.openDraft($r('app.string.desktop_schedule_creation_create_prompt')); } },
      { value: $r('app.string.desktop_schedule_creation_manual'), icon: $r('app.media.dsh_dock_edit'),
        action: (): void => { this.chooseEditor(); } }
    ];
  }

  private emptyTitle(): Resource {
    if (this.search.trim()) { return $r('app.string.desktop_schedule_creation_search_empty'); }
    if (this.filter === 'active') { return $r('app.string.desktop_schedule_creation_empty_active'); }
    if (this.filter === 'paused') { return $r('app.string.desktop_schedule_creation_empty_paused'); }
    if (this.filter === 'ended') { return $r('app.string.desktop_schedule_creation_empty_ended'); }
    return $r('app.string.desktop_schedule_creation_empty_all');
  }

  private endedCount(): number {
    return this.tasks.filter((row: Object): boolean => getString(row, 'status') === 'ended').length;
  }

  private statusLabel(value: string): Resource {
    if (value === 'active') { return $r('app.string.desktop_schedule_active'); }
    if (value === 'paused') { return $r('app.string.desktop_schedule_paused'); }
    if (value === 'ended') { return $r('app.string.desktop_schedule_ended'); }
    return $r('app.string.desktop_schedule_all');
  }

  private hasDetail(): boolean { return this.editing || !!this.historyId; }

  private detailId(): string { return this.historyId || this.editId; }

  private closeDetail(): void {
    this.editing = false;
    this.historyId = '';
    this.editId = '';
    this.conflict = false;
    this.status = '';
  }

  private chooseEditor(row?: Object): void {
    this.historyId = '';
    this.status = '';
    this.conflict = false;
    this.editId = getString(row, 'id') ?? '';
    this.revision = getString(row, 'updatedAt') ?? '';
    this.title = getString(row, 'title') ?? '';
    this.prompt = getString(row, 'prompt') ?? '';
    this.kind = getString(row, 'kind') ?? 'after';
    this.rule = '';
    this.time = getString(row, 'time') ?? '';
    this.zone = getString(row, 'timeZone') ?? 'Asia/Shanghai';
    this.weekday = [];
    const days = getArray(row, 'weekdays') ?? [];
    for (let day = 1; day <= 7; day++) {
      if (days.includes(day)) {
        this.weekday.push(day);
      }
    }
    if (this.kind === 'at') {
      const instant = getString(row, 'scheduledAt') ?? '';
      this.rule = instant.slice(0, 10);
      this.time = instant.slice(11, 19);
      this.zone = 'UTC';
    } else if (this.kind === 'after' || this.kind === 'every') {
      this.rule = String((getNumber(row, this.kind === 'after' ? 'afterSeconds' : 'everySeconds') ?? 3600) / 60);
    } else if (this.kind === 'cron') {
      this.rule = getString(row, 'expression') ?? '';
    } else if (this.kind === 'rrule') {
      this.rule = getString(row, 'rrule') ?? '';
    } else {
      this.rule = this.time;
    }
    const target = getRecord(row, 'target');
    const create = getRecord(target, 'create');
    this.targetKind = getString(target, 'kind') ?? 'new_once';
    this.targetSession = this.targetKind === 'session' ? getString(target, 'sessionId') ?? '' : this.sessionId;
    this.cwd = getString(create, 'cwd') ?? (row === undefined ? this.workspacePath : '');
    this.preset = getString(create, 'agentPreset') ?? '';
    this.originalTitle = this.title;
    this.originalPrompt = this.prompt;
    this.originalKind = this.kind;
    this.originalRule = this.rule;
    this.originalTime = this.time;
    this.originalZone = this.zone;
    this.originalWeekdays = this.weekday.join(',');
    this.originalTarget = this.targetKind;
    this.originalSession = this.targetSession;
    this.originalDirectory = this.cwd;
    this.originalPreset = this.preset;
    this.editing = true;
  }

  private timing(): Record<string, Object> | undefined {
    const kind = this.kind;
    const rule = this.rule.trim();
    const zone = this.zone.trim();
    const value: Record<string, Object> = { 'kind': kind };
    if (kind === 'after' || kind === 'every') {
      const seconds = Math.round(Number(rule) * 60);
      if (!Number.isSafeInteger(seconds) || seconds < (kind === 'every' ? 60 : 1)) {
        return undefined;
      }
      value[kind === 'after' ? 'after_seconds' : 'every_seconds'] = seconds;
    } else if (kind === 'at' || kind === 'daily' || kind === 'weekly') {
      const raw = kind === 'at' ? this.time.trim() : rule;
      const time = raw.length === 5 ? raw + ':00' : raw;
      if (!/^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,3})?$/.test(time) || zone.length === 0) {
        return undefined;
      }
      const local: Record<string, Object> = { 'time': time, 'time_zone': zone };
      if (kind === 'at') {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(rule)) {
          return undefined;
        }
        local['date'] = rule;
      }
      if (kind === 'weekly') {
        if (this.weekday.length === 0) {
          return undefined;
        }
        local['weekdays'] = this.weekday;
      }
      value[kind] = local;
    } else if (kind === 'cron') {
      if (rule.split(/\s+/).length !== 5 || zone.length === 0) {
        return undefined;
      }
      const timing: Record<string, Object> = { 'expression': rule, 'time_zone': zone };
      value['cron'] = timing;
    } else {
      if (rule.length === 0) {
        return undefined;
      }
      value['rrule'] = rule;
    }
    return value;
  }

  private target(): Record<string, Object> {
    const result: Record<string, Object> = { 'kind': this.targetKind };
    if (this.targetKind === 'session') {
      result['sessionId'] = this.targetSession.trim();
    } else {
      const create: Record<string, Object> = {};
      if (this.cwd.trim().length > 0) {
        create['cwd'] = this.cwd.trim();
      }
      if (this.preset.trim().length > 0) {
        create['agentPreset'] = this.preset.trim();
      }
      result['create'] = create;
    }
    return result;
  }

  private async save(): Promise<void> {
    const title = this.title.trim();
    const prompt = this.prompt.trim();
    if (title.length === 0 || prompt.length === 0 ||
      (this.targetKind === 'session' && this.targetSession.trim().length === 0)) {
      this.status = '请填写任务名称、提示词和投递会话';
      return;
    }
    const patch: Record<string, Object> = {};
    if (!this.editId || this.originalTitle !== this.title) { patch['title'] = title; }
    if (!this.editId || this.originalPrompt !== this.prompt) { patch['prompt'] = prompt; }
    if (!this.editId || this.timingChanged()) {
      const timing = this.timing();
      if (timing === undefined) {
        this.status = '请检查时间规则';
        return;
      }
      patch['timing'] = timing;
    }
    if (!this.editId || this.targetChanged()) {
      patch['target'] = this.target();
    }
    if (Object.keys(patch).length === 0) { return; }
    const request: Record<string, Object | null> = {
      'id': this.editId, 'action': 'update', 'patch': patch, 'expectedUpdatedAt': this.revision || null
    };
    const result = this.editId.length === 0 ? await this.invoke('schedule/create', patch) :
      await this.invoke('schedule/edit', request);
    if (result !== undefined) {
      const savedId = this.editId || getString(result.value, 'id') || getString(getRecord(result.value, 'task'), 'id') || '';
      this.closeDetail();
      if (await this.refresh() && this.active && savedId) {
        const row = this.taskById(savedId);
        if (row !== undefined) { this.chooseEditor(row); }
      }
    } else if (this.active && this.failureCode === 'schedule_conflict') {
      this.conflict = true;
    }
  }

  private timingChanged(): boolean {
    return this.originalKind !== this.kind || this.originalRule !== this.rule ||
      this.originalTime !== this.time || this.originalZone !== this.zone || this.originalWeekdays !== this.weekday.join(',');
  }

  private hasDraftChanges(): boolean {
    return this.editing && (this.title !== this.originalTitle || this.prompt !== this.originalPrompt ||
      this.timingChanged() || this.targetChanged());
  }

  private targetChanged(): boolean {
    return this.targetKind !== this.originalTarget || this.targetSession !== this.originalSession ||
      this.cwd !== this.originalDirectory || this.preset !== this.originalPreset;
  }

  private async rebaseDraft(): Promise<void> {
    const id = this.editId;
    if (!id || !this.catalog || this.busy) { return; }
    this.busy = true;
    try {
      if (!(await this.refresh()) || !this.active || id !== this.editId) { return; }
      const row = this.taskById(id);
      if (row === undefined) {
        this.status = '该任务已不存在，当前草稿仍可查看。';
        return;
      }
      const title = this.title !== this.originalTitle ? this.title : undefined;
      const prompt = this.prompt !== this.originalPrompt ? this.prompt : undefined;
      const timingChanged = this.timingChanged();
      const targetChanged = this.targetChanged();
      const kind = this.kind;
      const rule = this.rule;
      const time = this.time;
      const zone = this.zone;
      const weekdays = this.weekday;
      const target = this.targetKind;
      const session = this.targetSession;
      const cwd = this.cwd;
      const preset = this.preset;
      this.chooseEditor(row);
      if (title !== undefined) { this.title = title; }
      if (prompt !== undefined) { this.prompt = prompt; }
      if (timingChanged) {
        this.kind = kind;
        this.rule = rule;
        this.time = time;
        this.zone = zone;
        this.weekday = weekdays;
      }
      if (targetChanged) {
        this.targetKind = target;
        this.targetSession = session;
        this.cwd = cwd;
        this.preset = preset;
      }
      this.status = '';
    } finally {
      if (this.active) { this.busy = false; }
    }
  }

  private async taskAction(action: string, row: Object): Promise<void> {
    const id = getString(row, 'id') ?? '';
    if (id.length === 0) {
      return;
    }
    if (action === 'history') {
      if (this.editId !== id) { this.chooseEditor(row); }
      this.historyId = id;
      this.deliveries = [];
      this.nextBefore = '';
      await this.history(false);
      return;
    }
    const payload: Record<string, Object | null> = { 'id': id };
    if (action !== 'run') {
      payload['expectedUpdatedAt'] = getString(row, 'updatedAt') ?? null;
      payload['action'] = action === 'delete' ? 'delete' : 'update';
      if (action !== 'delete') {
        const patch: Record<string, Object> = { 'active': action === 'resume' };
        payload['patch'] = patch;
      }
    }
    const result = await this.invoke(action === 'run' ? 'schedule/run' : 'schedule/edit', payload);
    if (result !== undefined) {
      if (action === 'delete' && this.detailId() === id) { this.closeDetail(); }
      await this.refresh();
    }
  }

  private async history(append: boolean): Promise<void> {
    const id = this.historyId;
    const query: Record<string, Object> = { 'id': id, 'limit': 25 };
    if (append) {
      query['before'] = this.nextBefore;
    }
    const result = await this.invoke('schedule/history', query);
    if (append && this.failureCode === 'delivery_cursor_not_found' && this.active && this.historyId === id) {
      this.nextBefore = '';
      await this.history(false);
      return;
    }
    if (result !== undefined && this.historyId === id) {
      const records = getArray(result.value, 'records') ?? [];
      this.deliveries = append ? [...this.deliveries, ...records] : records;
      this.nextBefore = getString(result.value, 'nextBefore') ?? '';
    }
  }

  private closeConfirm(): void {
    const id = this.confirmId;
    this.confirmVersion++;
    this.confirmId = -1;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private async deleteConfirmed(row?: Object): Promise<void> {
    if (row !== undefined) { await this.taskAction('delete', row); return; }
    const result = await this.invoke('schedule/deleteInactive');
    const count = getNumber(result?.value, 'deleted');
    if (result !== undefined && count !== undefined && Number.isSafeInteger(count) && count >= 0) {
      await this.refresh();
      if (this.active) { this.status = this.formatCleared(count); }
    } else if (result !== undefined) {
      this.status = '宿主未确认清理结果';
    }
  }

  private formatCleared(count: number): string {
    const manager = this.getUIContext().getHostContext()?.resourceManager;
    return manager?.getStringSync($r('app.string.desktop_schedule_cleared').id, count) ?? String(count);
  }

  @Builder
  private DeleteDialog(row?: Object) {
    Column({ space: 12 }) {
      Text(row === undefined ? $r('app.string.desktop_schedule_clear') : $r('app.string.desktop_schedule_delete'))
        .width('100%').fontWeight(FontWeight.Medium).fontSize(19)
      Text(row === undefined ? $r('app.string.desktop_schedule_clear_message', this.endedCount()) :
        (getString(row, 'title') ?? '')).width('100%').fontSize(14)
      Row({ space: 10 }) {
        Button($r('app.string.desktop_schedule_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopScheduleDeleteCancel').onClick((): void => { this.closeConfirm(); })
        Button(row === undefined ? $r('app.string.desktop_schedule_clear_action') : $r('app.string.desktop_schedule_delete_action'))
          .key('desktopScheduleDeleteConfirm').fontColor(Color.White)
          .backgroundColor($r('app.color.workspace_status_error')).onClick((): void => {
            this.closeConfirm();
            this.deleteConfirmed(row);
          })
      }.width('100%').justifyContent(FlexAlign.End)
    }.key('desktopScheduleClearConfirm').width('100%').padding(20).alignItems(HorizontalAlign.Start)
  }

  private async confirmDelete(row?: Object): Promise<void> {
    if (!this.active || this.busy || this.catalogLoading || this.confirmOpening || this.confirmId >= 0) { return; }
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    const version = ++this.confirmVersion;
    this.confirmOpening = true;
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.DeleteDialog(row); },
        width: 420, alignment: DialogAlignment.Center, autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined, cornerRadius: 20,
        onDidDisappear: (): void => { if (version === this.confirmVersion) { this.confirmId = -1; } }
      });
      if (this.active && version === this.confirmVersion) { this.confirmId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.active) { this.status = '无法打开确认弹窗'; }
    } finally { this.confirmOpening = false; }
  }

  private rowActions(row: Object): MenuElement[] {
    const status = getString(row, 'status');
    const actions: MenuElement[] = [
      { value: '编辑', 'action': (): void => { this.chooseEditor(row); } },
      { value: '立即运行', 'action': (): void => { this.taskAction('run', row); } },
      { value: '投递历史', 'action': (): void => { this.taskAction('history', row); } }
    ];
    if (status !== 'ended') {
      actions.push({ value: status === 'active' ? '暂停' : '恢复', 'action': (): void => {
        this.taskAction(status === 'active' ? 'pause' : 'resume', row);
      } });
    }
    actions.push({ value: '删除', 'action': (): void => { this.confirmDelete(row); } });
    return actions;
  }

  @Builder
  private Editor() {
    Text(this.editId.length > 0 ? '编辑任务' : '新建任务').fontSize(18).fontWeight(FontWeight.Medium)
    TextInput({ text: this.title, placeholder: '任务名称' }).key('desktopScheduleTitle').maxLength(120).enabled(!this.busy)
      .onChange((value: string): void => { this.title = value; })
    TextArea({ text: this.prompt, placeholder: '为会话填写提示词' }).key('desktopSchedulePrompt').height(92).enabled(!this.busy)
      .onChange((value: string): void => { this.prompt = value; })
    Button(RULES.find((row: ScheduleRuleChoice): boolean => row.id === this.kind)?.title || '时间规则',
      { buttonStyle: ButtonStyleMode.TEXTUAL })
      .bindMenu(RULES.map((row: ScheduleRuleChoice): MenuElement => {
        return { value: row.title, 'action': (): void => {
          if (this.kind !== row.id) {
            this.kind = row.id;
            this.rule = '';
          }
        } };
      }), desktopMenuOptions(Placement.BottomLeft))
    if (this.kind === 'rrule') {
      TextArea({ text: this.rule, placeholder: 'DTSTART 和 RRULE（RFC 5545）' }).height(86)
        .onChange((value: string): void => { this.rule = value; })
    } else {
      TextInput({ text: this.rule,
        placeholder: RULES.find((row: ScheduleRuleChoice): boolean => row.id === this.kind)?.placeholder || '' })
        .onChange((value: string): void => { this.rule = value; })
    }
    if (this.kind === 'at') {
      TextInput({ text: this.time, placeholder: '时间 HH:mm:ss' })
        .onChange((value: string): void => { this.time = value; })
    }
    if (this.kind === 'at' || this.kind === 'daily' || this.kind === 'weekly' || this.kind === 'cron') {
      TextInput({ text: this.zone, placeholder: 'IANA 时区，例如 Asia/Shanghai' })
        .onChange((value: string): void => { this.zone = value; })
    }
    if (this.kind === 'weekly') {
      Row({ space: 6 }) {
        ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
          Button('周' + '一二三四五六日'.charAt(day - 1), {
            buttonStyle: this.weekday.includes(day) ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL
          }).onClick((): void => {
            this.weekday = this.weekday.includes(day) ?
              this.weekday.filter((value: number): boolean => value !== day) : [...this.weekday, day];
          })
        }, (day: number): string => '' + day)
      }
    }
    Button(TARGETS.find((row: ScheduleRuleChoice): boolean => row.id === this.targetKind)?.title || '投递位置',
      { buttonStyle: ButtonStyleMode.TEXTUAL })
      .bindMenu(TARGETS.map((row: ScheduleRuleChoice): MenuElement => {
        return { value: row.title, 'action': (): void => { this.targetKind = row.id; } };
      }), desktopMenuOptions(Placement.BottomLeft))
    if (this.targetKind === 'session') {
      TextInput({ text: this.targetSession, placeholder: '会话 ID' })
        .onChange((value: string): void => { this.targetSession = value; })
    } else {
      TextInput({ text: this.cwd, placeholder: '工作区路径（可选）' })
        .onChange((value: string): void => { this.cwd = value; })
      TextInput({ text: this.preset, placeholder: 'Agent 预设（可选）' })
        .onChange((value: string): void => { this.preset = value; })
    }
    Row({ space: 10 }) {
      Button('保存任务').key('desktopScheduleSave').enabled(!this.busy && !this.conflict).onClick((): void => { this.save(); })
      if (this.conflict) {
        Button($r('app.string.desktop_schedule_rebase'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopScheduleRebase').enabled(!this.busy).onClick((): void => { this.rebaseDraft(); })
      }
      Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .onClick((): void => { this.closeDetail(); })
    }
  }

  @Builder
  private History() {
    if (!this.busy && this.deliveries.length === 0) {
      Text('暂无投递记录').fontColor($r('sys.color.font_secondary'))
    }
    ForEach(this.deliveries, (record: Object) => {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(formatTime(getString(record, 'deliveredAt') ?? '')).fontSize(15)
          if (getString(record, 'prompt')) {
            Text(getString(record, 'prompt')).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (getString(record, 'targetSessionId')) {
          Button('打开会话', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
            this.onOpenSession(getString(record, 'targetSessionId') ?? '');
          })
        }
      }
      .width('100%').padding(10).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
    }, (record: Object): string => getString(record, 'messageId') ?? '')
    if (this.nextBefore.length > 0) {
      Button('加载较早的记录', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .onClick((): void => { this.history(true); })
    }
  }

  @Builder
  private Task(row: Object) {
    Row({ space: 7 }) {
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Column({ space: 5 }) {
          Text(getString(row, 'title') || getString(row, 'prompt') || '').width('100%').fontSize(15)
            .fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(getString(row, 'prompt') ?? '').width('100%').fontSize(12).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_secondary'))
          Row({ space: 7 }) {
            Text(this.statusLabel(getString(row, 'status') ?? '')).fontSize(11).fontColor($r('sys.color.font_secondary'))
            Text(formatTime(desktopScheduleNextTime(row))).fontSize(11).fontColor($r('sys.color.font_secondary'))
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.key('desktopScheduleTask-' + (getString(row, 'id') ?? '')).layoutWeight(1).height(76).borderRadius(8)
        .accessibilitySelected(this.detailId() === getString(row, 'id')).enabled(!this.busy)
        .onClick((): void => { this.chooseEditor(row); })
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_session_ellipsis')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
      }.key('desktopScheduleTaskMenu-' + (getString(row, 'id') ?? '')).width(32).height(32).padding(0)
        .accessibilityText($r('app.string.desktop_schedule_task_options')).enabled(!this.busy)
        .bindMenu(this.rowActions(row), desktopMenuOptions(Placement.BottomRight))
    }.width('100%').padding({ left: 2, right: 5 }).borderRadius(10)
      .backgroundColor(this.detailId() === getString(row, 'id') ? $r('app.color.workspace_selection') :
        $r('app.color.workspace_panel'))
  }

  @Builder
  private EmptyCatalog() {
    Column({ space: 12 }) {
      Image($r('app.media.dsh_schedule_empty')).width(110).height(110).supportSvg2(true).accessibilityLevel('no')
      Text(this.emptyTitle()).fontSize(14).textAlign(TextAlign.Center).fontColor($r('sys.color.font_tertiary'))
      Button($r('app.string.desktop_schedule_creation_empty_action'), {
        type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL
      }).key('desktopScheduleEmptyCreate').height(34).borderRadius(8).margin({ top: 4 })
        .enabled(!this.busy && !this.draftBusy).onClick((): void => { this.chooseEditor(); })
    }.width('100%').padding({ left: 20, right: 20, top: 42, bottom: 28 })
      .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private List() {
    Column({ space: 10 }) {
      Row({ space: 4 }) {
        ForEach(['active', 'paused', 'ended', 'all'], (item: string): void => {
          Button(this.statusLabel(item), { buttonStyle: this.filter === item ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL })
            .key('desktopScheduleFilter-' + item).layoutWeight(1).height(31).padding(0).fontSize(12)
            .accessibilitySelected(this.filter === item).onClick((): void => { this.filter = item; this.refilter(); })
        }, (item: string): string => item)
      }.width('100%')
      Row({ space: 5 }) {
        Search({ value: this.search, placeholder: $r('app.string.desktop_schedule_search') })
          .key('desktopScheduleSearch').layoutWeight(1).height(35)
          .onChange((text: string): void => { this.search = text; this.refilter(); })
        if (this.filter !== 'active' && this.endedCount() > 0) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_session_ellipsis')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
          }.key('desktopScheduleCatalogMore').width(35).height(35).padding(0)
            .accessibilityText($r('app.string.desktop_schedule_catalog_options')).enabled(!this.busy)
            .bindMenu(this.catalogActions(), desktopMenuOptions(Placement.BottomRight))
        }
      }.width('100%')
      if (this.catalogLoading) { LoadingProgress().width(18).height(18) }
      if (this.catalogError) {
        Row({ space: 7 }) {
          Text(this.catalogError).fontSize(12).key('desktopScheduleCatalogError').layoutWeight(1)
          Button($r('app.string.desktop_schedule_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopScheduleCatalogRetry').onClick((): void => { this.refresh(); })
        }.width('100%')
      }
      Scroll() {
        Column({ space: 7 }) {
          ForEach(this.rows, (row: Object): void => {
            this.Task(row)
          }, (row: Object): string => (getString(row, 'id') ?? '') + ':' + (getString(row, 'updatedAt') ?? '') +
            ':' + (getString(row, 'status') ?? '') + ':' + desktopScheduleNextTime(row))
          if (this.catalogReady && this.rows.length === 0) {
            this.EmptyCatalog()
          }
          if (desktopScheduleShowsRecommendations(this.catalogReady, this.rows.length, this.search, this.filter)) {
            DesktopScheduleRecommendations({
              twoColumns: (this.paneWidth >= 840 && this.hasDetail() ? this.paneWidth * 0.39 : this.paneWidth) > 600,
              disabled: this.busy || this.draftBusy,
              onChoose: (prompt: Resource): void => { this.openDraft(prompt); }
            })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).key('desktopScheduleCatalog')
    }.width(this.paneWidth >= 840 && this.hasDetail() ? '39%' : '100%').height('100%')
      .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Detail() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        if (this.detailId()) {
          Button($r('app.string.desktop_schedule_rules'), {
            buttonStyle: this.historyId ? ButtonStyleMode.TEXTUAL : ButtonStyleMode.NORMAL
          }).key('desktopScheduleRuleTab').onClick((): void => { if (!this.busy) { this.historyId = ''; } })
          Button($r('app.string.desktop_schedule_records'), {
            buttonStyle: this.historyId ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL
          }).key('desktopScheduleHistoryTab').onClick((): void => {
            const row = this.taskById(this.detailId());
            if (row !== undefined && !this.busy) { this.taskAction('history', row); }
          })
        }
        Blank()
        Button($r('app.string.desktop_schedule_close'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopScheduleCloseDetail').enabled(!this.busy).onClick((): void => { this.closeDetail(); })
      }.width('100%')
      Scroll() {
        Column({ space: 8 }) {
          if (this.historyId) { this.History() }
          else { this.Editor() }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.layoutWeight(1).height('100%').key('desktopScheduleDetail')
  }

  @Builder
  private CreateButtons() {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED }) {
        Row({ space: 6 }) {
          Image($r('app.media.dsh_reference_menu_plus')).width(13).height(13).supportSvg2(true)
            .fillColor(Color.White).accessibilityLevel('no')
          Text($r('app.string.desktop_schedule_creation_new')).fontSize(13).fontColor(Color.White)
        }
      }.key('desktopScheduleNew').height(34).padding({ left: 10, right: 10 })
        .borderRadius({ topLeft: 8, bottomLeft: 8, topRight: 0, bottomRight: 0 })
        .enabled(!this.busy && !this.draftBusy)
        .onClick((): void => { this.openDraft($r('app.string.desktop_schedule_creation_create_prompt')); })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED }) {
        Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true)
          .fillColor(Color.White).accessibilityLevel('no')
      }.key('desktopScheduleCreateOptions').height(34).width(30).padding(0)
        .borderRadius({ topLeft: 0, bottomLeft: 0, topRight: 8, bottomRight: 8 })
        .borderWidth({ left: 1 }).borderColor('#40FFFFFF')
        .accessibilityText($r('app.string.desktop_schedule_creation_create_method'))
        .enabled(!this.busy && !this.draftBusy)
        .bindMenu(this.creationActions(), desktopMenuOptions(Placement.BottomRight))
    }
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_experiment_schedule')).fontSize(26).fontWeight(FontWeight.Medium).layoutWeight(1)
        this.CreateButtons()
        Button($r('app.string.desktop_schedule_web'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(!this.busy).onClick(this.onWeb)
      }.width('100%')
      if (this.busy) { LoadingProgress().width(20).height(20) }
      if (this.status) {
        Text(this.status).key('desktopScheduleStatus').fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
      }
      Row({ space: 14 }) {
        if (!this.hasDetail() || this.paneWidth >= 840) { this.List() }
        if (this.hasDetail()) { this.Detail() }
      }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)
    }.padding(20).height('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
      .onAreaChange((_old: Area, area: Area): void => {
        const width = Number(area.width);
        if (Number.isFinite(width) && Math.abs(width - this.paneWidth) >= 1) { this.paneWidth = width; }
      })
  }
}
