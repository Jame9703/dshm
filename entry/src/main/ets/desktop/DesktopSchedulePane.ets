import { getArray, getNumber, getRecord, getString } from 'connection';
import type { RpcResult } from 'connection';
import { DesktopHostActions, desktopHostItems, desktopHostProblem } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';

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
  @Prop sessionId: string = '';
  @Prop workspacePath: string = '';
  onOpenSession: (id: string) => void = (_: string): void => {};
  onWeb: () => void = (): void => {};
  @State private tasks: Object[] = [];
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
    this.refresh();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private async invoke(endpoint: string, payload: Record<string, Object | null> = {}): Promise<RpcResult | undefined> {
    if (this.host === undefined || this.busy) {
      return undefined;
    }
    this.busy = true;
    this.status = '';
    const result = await this.host.call(endpoint, payload);
    if (!this.active) {
      return undefined;
    }
    this.busy = false;
    this.status = desktopHostProblem(result);
    return this.status.length === 0 ? result : undefined;
  }

  private async refresh(): Promise<void> {
    const result = await this.invoke('schedule/catalog');
    if (result !== undefined) {
      this.tasks = desktopHostItems(result);
    }
  }

  private chooseEditor(row?: Object): void {
    this.historyId = '';
    this.status = '';
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
    const patch: Record<string, Object> = { 'title': title, 'prompt': prompt };
    if (this.editId.length === 0 || this.originalKind !== this.kind || this.originalRule !== this.rule ||
      this.originalTime !== this.time || this.originalZone !== this.zone ||
      this.originalWeekdays !== this.weekday.join(',')) {
      const timing = this.timing();
      if (timing === undefined) {
        this.status = '请检查时间规则';
        return;
      }
      patch['timing'] = timing;
    }
    if (this.editId.length === 0 || this.targetKind !== this.originalTarget ||
      this.targetSession !== this.originalSession || this.cwd !== this.originalDirectory ||
      this.preset !== this.originalPreset) {
      patch['target'] = this.target();
    }
    const request: Record<string, Object | null> = {
      'id': this.editId, 'action': 'update', 'patch': patch, 'expectedUpdatedAt': this.revision || null
    };
    const result = this.editId.length === 0 ? await this.invoke('schedule/create', patch) :
      await this.invoke('schedule/edit', request);
    if (result !== undefined) {
      this.editing = false;
      await this.refresh();
    }
  }

  private async taskAction(action: string, row: Object): Promise<void> {
    const id = getString(row, 'id') ?? '';
    if (id.length === 0) {
      return;
    }
    if (action === 'history') {
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
    if (result !== undefined && this.historyId === id) {
      const records = getArray(result.value, 'records') ?? [];
      this.deliveries = append ? [...this.deliveries, ...records] : records;
      this.nextBefore = getString(result.value, 'nextBefore') ?? '';
    }
  }

  private confirmDelete(row: Object): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除自动化任务', message: getString(row, 'title') ?? '',
      buttons: [{ text: '取消', color: '#777777' }, { text: '删除', color: '#B73535' }]
    }).then((result): void => {
      if (result.index === 1 && this.active) {
        this.taskAction('delete', row);
      }
    }).catch((): void => {});
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
    TextInput({ text: this.title, placeholder: '任务名称' }).maxLength(120)
      .onChange((value: string): void => { this.title = value; })
    TextArea({ text: this.prompt, placeholder: '为会话填写提示词' }).height(92)
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
      Button('保存任务').enabled(!this.busy).onClick((): void => { this.save(); })
      Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .onClick((): void => { this.editing = false; this.status = ''; })
    }
  }

  @Builder
  private History() {
    Button('返回任务列表', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
      .onClick((): void => { this.historyId = ''; this.status = ''; })
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
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(getString(row, 'title') ?? '').fontSize(15).fontWeight(FontWeight.Medium)
        Text(getString(row, 'prompt') ?? '').fontSize(13).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((getString(row, 'status') === 'active' ? '运行中' : getString(row, 'status') === 'paused' ? '已暂停' :
          '已结束') + ' · ' + formatTime(getString(row, 'scheduledAt') ?? ''))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('更多', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
        .accessibilityText('管理 ' + (getString(row, 'title') ?? '任务'))
        .bindMenu(this.rowActions(row), desktopMenuOptions(Placement.BottomRight))
    }
    .width('100%').padding(10).borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('自动化任务').fontSize(26).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (!this.editing && this.historyId.length === 0) {
          Button('新建任务').enabled(!this.busy).onClick((): void => { this.chooseEditor(); })
          Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .onClick((): void => { this.refresh(); })
        }
        Button('在 WebUI 打开', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy).onClick(this.onWeb)
      }
      .width('100%')
      if (this.busy) {
        LoadingProgress().width(24).height(24)
      }
      if (this.status.length > 0) {
        Text(this.status).fontSize(13).fontColor($r('sys.color.warning')).width('100%')
      }
      Scroll() {
        Column({ space: 8 }) {
          if (this.editing) {
            this.Editor()
          } else if (this.historyId.length > 0) {
            this.History()
          } else {
            ForEach(this.tasks, (row: Object) => {
              this.Task(row)
            }, (row: Object): string => JSON.stringify(row))
            if (!this.busy && this.tasks.length === 0) {
              Text('暂无自动化任务').fontColor($r('sys.color.font_secondary'))
            }
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').layoutWeight(1).align(Alignment.TopStart)
    }
    .padding(20).height('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
  }
}
