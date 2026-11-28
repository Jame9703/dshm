import type { DesktopTranscriptItem } from './DesktopConversation';

interface DesktopPromptRun {
  text: string;
  oldest: number;
  newest: number;
}

export interface DesktopPromptHistoryStep {
  text: string;
  sequence?: number;
}

export function desktopPromptHistoryStep(transcript: DesktopTranscriptItem[], sequence: number | undefined,
  older: boolean): DesktopPromptHistoryStep | undefined {
  const prompts: DesktopPromptRun[] = [];
  for (let index = transcript.length - 1; index >= 0; index--) {
    const item = transcript[index];
    const text = item.userCopyText ?? '';
    if (!item.humanPrompt || item.sequence < 0 || !text.trim()) { continue; }
    const last = prompts[prompts.length - 1];
    if (last?.text === text) { last.oldest = item.sequence; }
    else { prompts.push({ text: text, oldest: item.sequence, newest: item.sequence }); }
  }
  let index = -1;
  if (sequence !== undefined) {
    index = prompts.findIndex((run: DesktopPromptRun): boolean => sequence >= run.oldest && sequence <= run.newest);
    if (index < 0) { return undefined; }
  }
  index += older ? 1 : -1;
  if (index === -1) { return { text: '' }; }
  const adjacent = prompts[index];
  return adjacent === undefined ? undefined : { text: adjacent.text, sequence: adjacent.newest };
}
