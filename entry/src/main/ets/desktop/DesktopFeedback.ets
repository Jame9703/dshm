import { FeedbackRow } from 'appstate';
import { getArray, getBoolean, getRecord, getString } from 'connection';
import { RpcResult } from 'connection';
import { MESSAGE_FEEDBACK_DELETE_ENDPOINT, MESSAGE_FEEDBACK_LIST_ENDPOINT, MESSAGE_FEEDBACK_PUT_ENDPOINT,
  SESSION_FEEDBACK_RECORD_ENDPOINT } from 'dshcompat';
import { DesktopHostActions } from './DesktopHostActions';

export enum DesktopRating {
  POSITIVE = 'positive',
  NEGATIVE = 'negative'
}

export interface DesktopFeedbackTarget {
  sessionId: string;
  messageId: string;
  rating?: DesktopRating;
  version: string;
}

function feedbackRow(value?: Object): FeedbackRow | undefined {
  const messageId = getString(value, 'messageId') ?? '';
  const rating = getString(value, 'rating') ?? '';
  const version = getString(value, 'version') ?? '';
  if (!messageId || !version || (rating !== DesktopRating.POSITIVE && rating !== DesktopRating.NEGATIVE)) {
    return undefined;
  }
  return { messageId: messageId, rating: rating, version: version,
    note: getString(value, 'note') ?? '', category: getString(value, 'category') ?? '' };
}

function failureCode(reply: RpcResult): string {
  return reply.ok ? getString(getRecord(reply.value, 'error'), 'code') ?? '' : reply.error?.code ?? '';
}

function feedbackProblem(reply: RpcResult): string {
  const code = failureCode(reply);
  if (code === 'version-conflict') { return '这条反馈已在别处改动，已显示最新状态'; }
  if (code === 'note-too-large') { return '描述太长，请缩短后再提交'; }
  return '反馈保存失败';
}

export class DesktopFeedback {
  private readonly host: DesktopHostActions;
  private readonly changed: () => void;
  private sessionId: string = '';
  private epoch: number = 0;
  private warmed: boolean = false;
  private ready: boolean = false;
  private read?: Promise<string>;
  private tail: Promise<string> = Promise.resolve('');
  private readonly cached: Map<string, FeedbackRow[]> = new Map<string, FeedbackRow[]>();
  rows: FeedbackRow[] = [];

  constructor(host: DesktopHostActions, changed: () => void) {
    this.host = host;
    this.changed = changed;
  }

  select(id: string): void {
    if (id === this.sessionId) { return; }
    this.sessionId = id;
    this.epoch++;
    this.read = undefined;
    this.rows = this.cached.get(id) ?? [];
    this.warmed = this.cached.has(id);
    this.ready = false;
    if (this.warmed) { this.resync(); }
  }

  ensure(id: string): Promise<string> {
    if (!id || id !== this.sessionId) { return Promise.resolve('反馈状态加载失败'); }
    if (this.ready) { return Promise.resolve(''); }
    if (this.read !== undefined) { return this.read; }
    const epoch = this.epoch;
    this.warmed = true;
    this.read = this.readRows(id, epoch).finally((): void => {
      if (epoch === this.epoch) { this.read = undefined; }
    });
    return this.read;
  }

  resync(): void {
    const id = this.sessionId;
    if (!id || !this.warmed) { return; }
    this.enqueue((): Promise<string> => {
      if (id !== this.sessionId) { return Promise.resolve(''); }
      this.ready = false;
      return this.ensure(id);
    });
  }

  private async readRows(id: string, epoch: number): Promise<string> {
    const response = await this.host.call(MESSAGE_FEEDBACK_LIST_ENDPOINT, { 'sessionId': id });
    if (epoch !== this.epoch) { return '会话已切换'; }
    const value = getBoolean(response.value, 'ok') === true ? getRecord(response.value, 'value') : response.value;
    const items = response.ok ? getArray(value, 'items') : undefined;
    if (items === undefined) { return '反馈状态加载失败'; }
    const rows: FeedbackRow[] = [];
    for (const item of items) {
      const row = feedbackRow(item);
      if (row !== undefined) { rows.push(row); }
    }
    this.ready = true;
    this.update(rows);
    return '';
  }

  current(messageId: string): FeedbackRow | undefined {
    return this.rows.find((row: FeedbackRow): boolean => row.messageId === messageId);
  }

  record(target: DesktopFeedbackTarget, category: string, note: string): Promise<string> {
    const epoch = this.epoch;
    return this.enqueue(async (): Promise<string> => {
      if (target.sessionId !== this.sessionId || epoch !== this.epoch) { return '会话已切换'; }
      const body: Record<string, Object | null> = { 'sessionId': target.sessionId };
      const text = note.trim();
      if (category) { body['category'] = category; }
      if (!target.messageId) {
        if (text) { body['text'] = text; }
        const reply = await this.host.call(SESSION_FEEDBACK_RECORD_ENDPOINT, body);
        return reply.ok && getBoolean(reply.value, 'ok') === true ? '' : feedbackProblem(reply);
      }
      if (await this.ensure(target.sessionId)) { return '反馈状态加载失败'; }
      if (epoch !== this.epoch) { return '会话已切换'; }
      body['messageId'] = target.messageId;
      body['rating'] = target.rating ?? '';
      body['ifVersion'] = target.version || null;
      if (text) { body['note'] = text; }
      const reply = await this.host.call(MESSAGE_FEEDBACK_PUT_ENDPOINT, body);
      return this.accept(reply, target, epoch, false);
    });
  }

  retract(target: DesktopFeedbackTarget): Promise<string> {
    const epoch = this.epoch;
    return this.enqueue(async (): Promise<string> => {
      if (target.sessionId !== this.sessionId || epoch !== this.epoch || !target.version) { return '会话已切换'; }
      const reply = await this.host.call(MESSAGE_FEEDBACK_DELETE_ENDPOINT, {
        'sessionId': target.sessionId, 'messageId': target.messageId, 'ifVersion': target.version
      });
      return this.accept(reply, target, epoch, true);
    });
  }

  private accept(reply: RpcResult, target: DesktopFeedbackTarget, epoch: number, remove: boolean): string {
    if (epoch !== this.epoch) { return '会话已切换'; }
    const messageId = target.messageId;
    if (reply.ok && getBoolean(reply.value, 'ok') === true) {
      const value = getRecord(reply.value, 'value');
      const row = remove ? undefined : feedbackRow(value);
      if (remove ? getBoolean(value, 'absent') !== true : row?.messageId !== messageId) { return '反馈保存失败'; }
      this.replace(messageId, row);
      return '';
    }
    if (failureCode(reply) === 'version-conflict') {
      const observed = feedbackRow(getRecord(getRecord(reply.value, 'error'), 'current'));
      this.replace(messageId, observed);
      target.version = observed?.version ?? '';
    }
    return feedbackProblem(reply);
  }

  private replace(messageId: string, row?: FeedbackRow): void {
    const rows = this.rows.filter((current: FeedbackRow): boolean => current.messageId !== messageId);
    if (row !== undefined) { rows.push(row); }
    this.update(rows);
  }

  private update(rows: FeedbackRow[]): void {
    this.rows = rows;
    if (this.cached.size >= 16 && !this.cached.has(this.sessionId)) {
      const oldest = this.cached.keys().next();
      if (!oldest.done) { this.cached.delete(oldest.value); }
    }
    this.cached.set(this.sessionId, rows);
    this.changed();
  }

  private enqueue(run: () => Promise<string>): Promise<string> {
    const task = this.tail.then(run);
    this.tail = task.catch((): string => '反馈保存失败');
    return this.tail;
  }
}
