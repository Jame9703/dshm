import { getArray, getBoolean, getNumber, getRecord, getString } from 'connection';

export interface DesktopCommand {
  name: string;
  alias: string;
  label: string;
  description: string;
  kind: string;
  hint?: string;
  attachments: boolean;
}

export interface DesktopSlashToken {
  start: number;
  end: number;
  leading: boolean;
  query: string;
}

export interface DesktopCommandInvocation {
  token: string;
  suffix: string;
}

export interface DesktopCommandRecord {
  id: string;
  sequence: number;
  completed: number;
  name: string;
  args: string;
  outcome: string;
  text: string;
  sourceSequence: number;
}

export function desktopCommandCatalog(value?: Object): DesktopCommand[] | undefined {
  const wrapper: Record<string, Object> = { 'items': value ?? '' };
  const items = getArray(value, 'items') ?? getArray(wrapper, 'items');
  if (items === undefined) { return undefined; }
  const result: DesktopCommand[] = [];
  for (const row of items) {
    const name = getString(row, 'name') ?? '';
    if (!new RegExp('^[a-z][a-z0-9_-]*$').test(name)) { continue; }
    const input = getRecord(row, 'input');
    const command: DesktopCommand = { name: name, alias: name, label: name,
      description: getString(row, 'description') ?? '', kind: 'host', hint: getString(input, 'hint'),
      attachments: getBoolean(input, 'attachments') === true };
    switch (getString(row, 'definitionId')) {
      case '@deepseek-ai/dsh-command-goal':
        command.alias = '目标'; command.label = '目标'; command.description = '设置或查看长期任务目标'; command.kind = 'goal'; break;
      case '@deepseek-ai/dsh-plan-mode':
        command.alias = '计划'; command.label = '计划'; command.description = '进入或退出计划模式'; command.kind = 'plan'; break;
      case '@deepseek-ai/dsh-command-feedback':
        command.alias = '反馈'; command.label = '反馈'; command.description = '发送关于当前会话的反馈'; command.kind = 'feedback'; break;
      case '@deepseek-ai/dsh-command-compact':
        command.alias = '压缩'; command.label = '压缩'; command.description = '压缩以上对话内容'; command.kind = 'compact'; break;
      case '@deepseek-ai/dsh-permission-presets':
        command.alias = '权限'; command.label = '权限'; command.description = '切换权限预设'; command.kind = 'permission'; break;
      case '@deepseek-ai/dsh-session-log-export':
        command.alias = '导出'; command.label = '下载日志'; command.description = '将当前会话内容导出为 ZIP'; command.kind = 'export'; break;
      default: break;
    }
    result.push(command);
  }
  return result;
}

export function commandInvocation(text: string): DesktopCommandInvocation | undefined {
  const line = text.trim();
  const match = new RegExp('^/(\\S+)').exec(line);
  return match === null ? undefined : { token: match[1], suffix: line.slice(match[0].length) };
}

export function resolveDesktopCommand(commands: DesktopCommand[], token: string): DesktopCommand | undefined {
  return commands.find((item: DesktopCommand): boolean => item.name === token) ??
    commands.find((item: DesktopCommand): boolean => item.alias === token);
}

export function activeDesktopSlash(text: string, caret: number): DesktopSlashToken | undefined {
  const word = new RegExp('[\\p{L}\\p{N}_]', 'u');
  const space = new RegExp('\\s');
  for (let index = Math.min(caret, text.length) - 1; index >= 0; index--) {
    const char = text.charAt(index);
    if (space.test(char)) { return undefined; }
    if (char !== '/') { continue; }
    const previous = text.charAt(index - 1);
    if (previous === '/' || word.test(previous) ||
      (previous === ':' && index > 1 && !space.test(text.charAt(index - 2)))) { continue; }
    const query = text.slice(index + 1, caret);
    if (query.includes('/')) { return undefined; }
    return { start: index, end: caret, leading: text.search(new RegExp('\\S')) === index, query: query };
  }
  return undefined;
}

export function commandCandidates(commands: DesktopCommand[], query: string, leading: boolean): DesktopCommand[] {
  const native: DesktopCommand[] = [
    { name: 'file', alias: '文件', label: '文件', description: '添加附件', kind: 'file', attachments: true },
    { name: 'model', alias: '模型', label: '模型', description: '切换当前会话的模型', kind: 'model', attachments: false }
  ];
  const all = [...commands, ...native.filter((choice: DesktopCommand): boolean =>
    !commands.some((command: DesktopCommand): boolean => command.name === choice.name))];
  const order = ['file', 'goal', 'plan', 'feedback', 'compact', 'permission', 'model', 'export'];
  const needle = query.toLowerCase();
  return all.filter((item: DesktopCommand): boolean => (leading || item.hint === undefined || item.kind === 'feedback') &&
    (!needle || [item.name, item.alias, item.label].some((term: string): boolean => term.toLowerCase().includes(needle))))
    .sort((left: DesktopCommand, right: DesktopCommand): number => {
      if (needle && (left.name === needle || left.alias === needle) !== (right.name === needle || right.alias === needle)) {
        return left.name === needle || left.alias === needle ? -1 : 1;
      }
      const a = order.indexOf(left.kind);
      const b = order.indexOf(right.kind);
      return (a < 0 ? order.length : a) - (b < 0 ? order.length : b);
    });
}

export function observeDesktopCommand(records: Map<string, DesktopCommandRecord>, event?: Object): void {
  const type = getString(event, 'type');
  if (type !== 'command/run' && type !== 'command/done') { return; }
  const body = getRecord(event, 'data');
  const id = getString(body, 'commandId') ?? '';
  const sequence = getNumber(event, 'seq') ?? -1;
  if (!id || sequence < 0) { return; }
  const row: DesktopCommandRecord = records.get(id) ?? { id: id, sequence: -1, completed: -1,
    name: '', args: '', outcome: '', text: '', sourceSequence: -1 };
  if (type === 'command/run' && (row.sequence < 0 || sequence <= row.sequence)) {
    row.sequence = sequence;
    row.name = getString(body, 'name') ?? '';
    row.args = getString(body, 'args') ?? '';
  } else if (type === 'command/done' && sequence >= row.completed) {
    row.completed = sequence;
    row.outcome = getString(body, 'kind') ?? '';
    row.text = getString(body, 'text') ?? '';
    row.sourceSequence = getNumber(body, 'sourceEventSeq') ?? -1;
  }
  records.set(id, row);
}
