import { getArray, getString, parseJson } from 'connection';

export enum DesktopArchiveFilter {
  HIDE = 'default',
  ALL = 'show',
  ONLY = 'only'
}

export interface DesktopArchiveActivity {
  kind: string;
  names: string[];
}

export interface DesktopArchiveRequest {
  id: string;
  title: string;
  activity: DesktopArchiveActivity[];
}

export interface DesktopArchiveNotice {
  id: string;
  stopped: boolean;
}

export function desktopArchiveActivity(details: string, sessionId: string): DesktopArchiveActivity[] {
  const value = parseJson(details);
  if (getString(value, 'sessionId') !== sessionId) { return []; }
  const activity: DesktopArchiveActivity[] = [];
  for (const entry of getArray(value, 'activity') ?? []) {
    const kind = getString(entry, 'kind') ?? '';
    if (!kind) { continue; }
    const names: string[] = [];
    for (const item of getArray(entry, 'items') ?? []) {
      names.push(getString(item, 'label') || getString(item, 'id') || '未命名');
    }
    activity.push({ kind: kind, names: names });
  }
  return activity;
}

@Component
export struct DesktopArchiveDialog {
  @Prop title: string = '';
  @Prop activity: DesktopArchiveActivity[] = [];
  @Prop busy: boolean = false;
  @Prop problem: string = '';
  onConfirm: () => void = (): void => {};
  onClose: () => void = (): void => {};

  private activityLabel(row: DesktopArchiveActivity): string {
    const count = row.names.length;
    const names = row.names.join('、');
    if (row.kind === 'turn') { return '进行中的回合'; }
    if (row.kind === 'subagent') { return `${count} 个运行中的子智能体：${names}`; }
    if (row.kind === 'job') { return `${count} 个后台任务：${names}`; }
    if (row.kind === 'schedule') { return `${count} 条定时提醒：${names}`; }
    return count > 0 ? `${count} 项其他工作（${row.kind}）` : `其他工作（${row.kind}）`;
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('停止并归档此会话？').key('desktopArchiveDialogTitle').fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.width(30).height(30).padding(0).accessibilityText('关闭').enabled(!this.busy).onClick(this.onClose)
      }.width('100%')
      Text(`“${this.title}”仍有正在进行的工作。归档会先停止这些工作。之后可在侧栏筛选“全部对话（显示已归档）”中恢复会话，被停止的工作不会自动继续。`)
        .fontSize(14).lineHeight(21).fontColor($r('sys.color.font_secondary')).width('100%')
      if (this.activity.length > 0) {
        Scroll() {
          Column({ space: 5 }) {
            ForEach(this.activity, (row: DesktopArchiveActivity) => {
              Row({ space: 8 }) {
                Circle().width(5).height(5).fill($r('sys.color.font_secondary')).accessibilityLevel('no')
                Text(this.activityLabel(row)).fontSize(14).lineHeight(21).layoutWeight(1)
              }.width('100%')
            }, (row: DesktopArchiveActivity, index: number): string => row.kind + ':' + index)
          }.width('100%').padding({ left: 4 })
        }.width('100%').constraintSize({ maxHeight: 160 }).accessibilityDescription('将被停止的工作')
      }
      if (this.busy || this.problem) {
        Text(this.busy ? '正在停止并归档…' : this.problem).fontSize(13).width('100%')
          .fontColor(this.busy ? $r('sys.color.font_secondary') : $r('sys.color.warning'))
      }
      Row({ space: 8 }) {
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopArchiveCancel')
          .enabled(!this.busy).onClick(this.onClose)
        Button('停止并归档', { buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.ERROR })
          .key('desktopArchiveConfirm').enabled(!this.busy).onClick(this.onConfirm)
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(22).width('100%').alignItems(HorizontalAlign.Start)
  }
}
