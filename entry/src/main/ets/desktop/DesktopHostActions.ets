import { Connection, getArray, getRecord, getString, RemoteFailure, rpcFail } from 'connection';
import type { RpcResult, StreamSink } from 'connection';
import { argsFor } from 'dshcompat';

export class DesktopHostActions {
  private readonly connection: Connection;

  constructor(connection: Connection) {
    this.connection = connection;
  }

  watch(endpoint: string, body: Record<string, Object>, sink: StreamSink): (() => void) | undefined {
    const args = argsFor(endpoint, body);
    return args === undefined ? undefined : this.connection.openStream(endpoint, args, sink);
  }

  async call(endpoint: string, body: Record<string, Object | null> = {},
    optionsTimeoutMs: number = 15000): Promise<RpcResult> {
    const args = argsFor(endpoint, body);
    if (args === undefined) {
      return rpcFail(new RemoteFailure('unsupported', '当前宿主协议不提供此操作', ''));
    }
    return this.connection.call(endpoint, args, { timeoutMs: optionsTimeoutMs });
  }
}

export function desktopHostProblem(result: RpcResult): string {
  if (!result.ok) {
    return result.error?.message || '宿主请求失败';
  }
  const value = result.value;
  const code = getString(value, 'code');
  if (code === 'schedule_conflict') {
    return '任务已在其他窗口修改，请刷新后重试';
  }
  if (code === 'schedule_execution_pending') {
    return '任务已在排队或运行';
  }
  if (code === 'schedule_not_found' || code === 'delivery_cursor_not_found') {
    return '任务或投递记录已变化，请刷新后重试';
  }
  const outcome = getString(value, 'application');
  if (outcome === 'failed' || outcome === 'overridden' || outcome === 'cancelled') {
    const error = getRecord(value, 'error');
    return getString(error, 'message') || getString(error, 'code') || (
      outcome === 'overridden' ? '当前配置覆盖了本次操作' :
        outcome === 'cancelled' ? '操作已取消' : '宿主未能应用修改'
    );
  }
  return '';
}

export function desktopHostItems(result: RpcResult): Object[] {
  const wrapped: Record<string, Object> = { 'items': result.value ?? '' };
  return getArray(wrapped, 'items') ?? [];
}
