import { common } from '@kit.AbilityKit';
import { ReadAloud } from 'platform';

interface MarkdownReplacement {
  pattern: RegExp;
  replacement: string;
}

// Mirrors the DSHM WebUI reply actions so the system receives the same plain text.
const REPLY_MARKDOWN_REPLACEMENTS: MarkdownReplacement[] = [
  { pattern: new RegExp('```[\\s\\S]*?```', 'g'), replacement: '\n' },
  { pattern: new RegExp('~~~[\\s\\S]*?~~~', 'g'), replacement: '\n' },
  { pattern: new RegExp('!\\[([^\\]]*)\\]\\([^)]*\\)', 'g'), replacement: '$1' },
  { pattern: new RegExp('\\[([^\\]]+)\\]\\([^)]*\\)', 'g'), replacement: '$1' },
  { pattern: new RegExp('<\\/?[a-zA-Z][^>]*>', 'g'), replacement: '' },
  { pattern: new RegExp('^[ \\t]{0,3}(#{1,6}|>|[-*+]|\\d+\\.)\\s+', 'gm'), replacement: '' },
  { pattern: new RegExp('^\\s*\\|?[\\s:|-]+\\|[\\s:|-]*$', 'gm'), replacement: '' },
  { pattern: new RegExp('\\|', 'g'), replacement: '，' },
  { pattern: new RegExp('(\\*\\*|__|~~|\\*|_|`)', 'g'), replacement: '' },
  { pattern: new RegExp('[ \\t]+\\n', 'g'), replacement: '\n' },
  { pattern: new RegExp('\\n{3,}', 'g'), replacement: '\n\n' }
];

export function desktopReplyMediaText(markdown: string): string {
  let plain = markdown;
  for (const rule of REPLY_MARKDOWN_REPLACEMENTS) {
    plain = plain.replace(rule.pattern, rule.replacement);
  }
  return plain.trim();
}

/** One player for the workbench, including any reply shown in the dock. */
export class DesktopReplyMedia {
  private readonly reader = new ReadAloud();
  private readonly observers = new Map<string, Set<(reading: boolean) => void>>();
  private activeKey: string = '';

  observe(key: string, update: (reading: boolean) => void): () => void {
    let listeners = this.observers.get(key);
    if (listeners === undefined) {
      listeners = new Set<(reading: boolean) => void>();
      this.observers.set(key, listeners);
    }
    listeners.add(update);
    update(this.activeKey === key);
    return (): void => {
      const current = this.observers.get(key);
      current?.delete(update);
      if (current?.size === 0) { this.observers.delete(key); }
    };
  }

  toggle(context: common.UIAbilityContext, key: string, text: string, title: string, onError: () => void): void {
    if (this.activeKey === key) {
      this.reader.stop();
      return;
    }
    const status = this.reader.start(context, text, (failed: boolean): void => {
      if (this.activeKey !== key) { return; }
      this.setActive('');
      if (failed) { onError(); }
    }, title);
    if (status === 'started' || status === 'fallback') {
      this.setActive(key);
    } else {
      onError();
    }
  }

  release(): void {
    this.reader.release();
    this.setActive('');
  }

  private setActive(key: string): void {
    const previous = this.activeKey;
    if (previous === key) { return; }
    this.activeKey = key;
    this.observers.get(previous)?.forEach((update: (reading: boolean) => void): void => { update(false); });
    this.observers.get(key)?.forEach((update: (reading: boolean) => void): void => { update(true); });
  }
}
