import { getArray, getField, getNumber, getString } from 'connection';

export interface DesktopTimelineReceiptTask {
  id: string;
  title: string;
  note: string;
  status: string;
  before: number;
  after: number;
}

export interface DesktopTimelineReceipt {
  tree: string;
  title: string;
  branch: string;
  at: number;
  previousAt?: number;
  before: number;
  after: number;
  total: number;
  tasks: DesktopTimelineReceiptTask[];
}

function progress(value?: number): boolean {
  return value !== undefined && value >= 0 && value <= 1;
}

const RECEIPT_STATUSES: string[] = ['pending', 'active', 'paused', 'blocked', 'done', 'retired'];

function timestamp(value: number): boolean { return value >= 0 && value <= 8640000000000000; }

export function readDesktopTimelineReceipt(value?: Object): DesktopTimelineReceipt | undefined {
  if (value === undefined || getNumber(value, 'version') !== 1 || Object.keys(value).length !== 10) {
    return undefined;
  }
  const tree = getString(value, 'tree')?.trim();
  const title = getString(value, 'title');
  const branch = getString(value, 'branch');
  const at = getNumber(value, 'at');
  const previousAt = getNumber(value, 'previousAt');
  const before = getNumber(value, 'before');
  const after = getNumber(value, 'after');
  const total = getNumber(value, 'total');
  const rows = getArray(value, 'tasks');
  if (!tree || tree.length > 80 || !title || title.length > 120 ||
      (branch === undefined ? getField(value, 'branch') !== null : branch.length > 120) ||
      at === undefined || !timestamp(at) ||
      (previousAt === undefined ? getField(value, 'previousAt') !== null : !timestamp(previousAt)) ||
      before === undefined || !progress(before) || after === undefined || !progress(after) ||
      total === undefined || !Number.isInteger(total) || total > 1000 ||
      rows === undefined || rows.length < 1 || rows.length > 6 || total < rows.length) {
    return undefined;
  }
  const tasks: DesktopTimelineReceiptTask[] = [];
  for (const row of rows) {
    const id = getString(row, 'id')?.trim();
    const taskTitle = getString(row, 'title');
    const note = getString(row, 'note');
    const status = getString(row, 'status');
    const taskBefore = getNumber(row, 'before');
    const taskAfter = getNumber(row, 'after');
    if (!id || id.length > 80 || !taskTitle || taskTitle.length > 120 || note === undefined || note.length > 400 ||
        !status || !RECEIPT_STATUSES.includes(status) || taskBefore === undefined || !progress(taskBefore) ||
        taskAfter === undefined || !progress(taskAfter) || Object.keys(row).length !== 6) { return undefined; }
    tasks.push({ id: id, title: taskTitle, note: note, status: status, before: taskBefore, after: taskAfter });
  }
  return { tree: tree, title: title, branch: branch ?? '', at: at, previousAt: previousAt,
    before: before, after: after, total: total, tasks: tasks };
}
