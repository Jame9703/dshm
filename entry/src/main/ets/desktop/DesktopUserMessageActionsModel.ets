import { getArray, getString } from 'connection';
import { desktopSecretRanges } from './DesktopSecretMask';

export interface DesktopUserMessageClockParts {
  year: string;
  month: string;
  day: string;
  hourMinute: string;
  sameDay: boolean;
  sameYear: boolean;
}

/** Event text blocks match the WebUI bubble's clipboard input. */
export function desktopUserMessageCopyText(eventData: Object | undefined): string {
  const content: Object[] | undefined = getArray(eventData, 'content');
  if (content === undefined) { return getString(eventData, 'content') ?? ''; }
  const text: string[] = [];
  for (const block of content) {
    if (getString(block, 'type') !== 'text') { continue; }
    const value: string | undefined = getString(block, 'text');
    if (value !== undefined) { text.push(value); }
  }
  return text.join('');
}

/** The native action preserves the displayed credential masking on the clipboard. */
export function desktopUserMessageClipboardText(text: string): string {
  let result: string = '';
  let cursor: number = 0;
  for (const range of desktopSecretRanges(text)) {
    result += text.slice(cursor, range.start) + range.masked;
    cursor = range.end;
  }
  return result + text.slice(cursor);
}

export function desktopUserMessageClockParts(timestamp: number, now: number): DesktopUserMessageClockParts | undefined {
  const date: Date = new Date(timestamp);
  if (timestamp <= 0 || !Number.isFinite(date.getTime())) { return undefined; }
  const today: Date = new Date(now);
  const sameYear: boolean = today.getFullYear() === date.getFullYear();
  return {
    year: String(date.getFullYear()),
    month: String(date.getMonth() + 1),
    day: String(date.getDate()),
    hourMinute: String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0'),
    sameDay: sameYear && today.getMonth() === date.getMonth() && today.getDate() === date.getDate(),
    sameYear: sameYear
  };
}
