import { getNumber } from 'connection';

const FIELDS: string[] = ['inputTokens', 'cacheReadTokens', 'cacheWriteTokens', 'outputTokens', 'reasoningTokens'];

export interface DesktopTraceUsageLine {
  metric: string;
  amount: number;
  detail: boolean;
}

export function desktopTraceUsage(value?: Object): Record<string, number> | undefined {
  const usage: Record<string, number> = {};
  let reported = false;
  for (const key of FIELDS) {
    const amount = getNumber(value, key);
    if (amount !== undefined && Number.isFinite(amount) && amount >= 0) {
      usage[key] = amount;
      reported = true;
    }
  }
  return reported ? usage : undefined;
}

export function desktopTraceAddUsage(total: Record<string, number> | undefined,
  usage: Record<string, number> | undefined): Record<string, number> | undefined {
  if (usage === undefined) { return total; }
  const result: Record<string, number> = {};
  for (const key of FIELDS) {
    const previous = getNumber(total, key);
    const amount = getNumber(usage, key);
    if (previous !== undefined || amount !== undefined) { result[key] = (previous ?? 0) + (amount ?? 0); }
  }
  return result;
}

export function desktopTraceUsageLines(usage?: Object): DesktopTraceUsageLine[] {
  const lines: DesktopTraceUsageLine[] = [];
  const input = getNumber(usage, 'inputTokens');
  const read = getNumber(usage, 'cacheReadTokens');
  const write = getNumber(usage, 'cacheWriteTokens');
  const output = getNumber(usage, 'outputTokens');
  const reasoning = getNumber(usage, 'reasoningTokens');
  if (input !== undefined || read !== undefined || write !== undefined) {
    lines.push({ metric: 'input', amount: (input ?? 0) + (read ?? 0) + (write ?? 0), detail: false });
  }
  if (read !== undefined) { lines.push({ metric: 'cacheRead', amount: read, detail: true }); }
  if (write !== undefined) { lines.push({ metric: 'cacheWrite', amount: write, detail: true }); }
  if (input !== undefined) { lines.push({ metric: 'uncached', amount: input, detail: true }); }
  if (output !== undefined) { lines.push({ metric: 'output', amount: output, detail: false }); }
  if (reasoning !== undefined) { lines.push({ metric: 'reasoning', amount: reasoning, detail: true }); }
  if (output !== undefined && reasoning !== undefined) {
    lines.push({ metric: 'content', amount: output - reasoning, detail: true });
  }
  return lines;
}
