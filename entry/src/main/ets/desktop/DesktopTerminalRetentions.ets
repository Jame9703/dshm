import { getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';

type TerminalRetentionListener = (problem: string) => void;

interface DesktopTerminalHold {
  sessionId: string;
  id: string;
  stop?: () => void;
  generation: number;
  ready: boolean;
  problem: string;
  listeners: Set<TerminalRetentionListener>;
}

/** The workspace window owns a hold for each distinct terminal in its open dock tabs. */
export class DesktopTerminalRetentions {
  private readonly host: DesktopHostActions;
  private readonly holds = new Map<string, Map<string, DesktopTerminalHold>>();
  private connected: boolean = false;

  constructor(host: DesktopHostActions) { this.host = host; }

  setTabs(sessionId: string, ids: string[]): void {
    const wanted = new Set<string>(ids);
    let session = this.holds.get(sessionId);
    if (session === undefined && wanted.size === 0) { return; }
    if (session === undefined) {
      session = new Map<string, DesktopTerminalHold>();
      this.holds.set(sessionId, session);
    }
    session.forEach((hold: DesktopTerminalHold, id: string): void => {
      if (!wanted.has(id)) {
        session?.delete(id);
        this.release(hold);
      }
    });
    for (const id of wanted) {
      if (id && !session.has(id)) {
        const hold: DesktopTerminalHold = { sessionId: sessionId, id: id, generation: 0,
          ready: false, problem: '', listeners: new Set<TerminalRetentionListener>() };
        session.set(id, hold);
        this.open(hold);
      }
    }
    if (session.size === 0) { this.holds.delete(sessionId); }
  }

  connect(): void {
    this.connected = true;
    this.holds.forEach((session: Map<string, DesktopTerminalHold>): void => {
      session.forEach((hold: DesktopTerminalHold): void => this.open(hold));
    });
  }

  dispose(): void {
    this.connected = false;
    this.holds.forEach((session: Map<string, DesktopTerminalHold>): void => {
      session.forEach((hold: DesktopTerminalHold): void => this.release(hold));
    });
    this.holds.clear();
  }

  observe(sessionId: string, id: string, listener: TerminalRetentionListener): () => void {
    const hold = this.holds.get(sessionId)?.get(id);
    if (hold === undefined) {
      listener('终端标签已关闭');
      return (): void => {};
    }
    hold.listeners.add(listener);
    if (hold.ready) { listener(''); }
    else {
      // Entering or explicitly retrying a tab may retry a terminal-domain failure once.
      hold.problem = '';
      this.open(hold);
    }
    return (): void => { hold.listeners.delete(listener); };
  }

  private open(hold: DesktopTerminalHold): void {
    if (!this.connected || hold.stop !== undefined || hold.problem) { return; }
    const generation = ++hold.generation;
    hold.stop = this.host.watch('terminal/retain', { 'sessionId': hold.sessionId, 'id': hold.id }, {
      onItem: (value: Object): void => {
        if (generation !== hold.generation || hold.ready || getString(value, 'type') !== 'retained') { return; }
        hold.ready = true;
        hold.listeners.forEach((listener: TerminalRetentionListener): void => listener(''));
      },
      onError: (code: string, message: string): void => {
        if (generation !== hold.generation) { return; }
        hold.stop = undefined;
        hold.ready = false;
        if (code.startsWith('carrier/')) { return; }
        this.fail(hold, message || '无法保留终端');
      },
      onEnd: (): void => {
        if (generation !== hold.generation) { return; }
        hold.stop = undefined;
        hold.ready = false;
        this.fail(hold, '终端已关闭或不可用');
      }
    });
  }

  private fail(hold: DesktopTerminalHold, problem: string): void {
    hold.problem = problem;
    hold.listeners.forEach((listener: TerminalRetentionListener): void => listener(problem));
  }

  private release(hold: DesktopTerminalHold): void {
    hold.generation++;
    hold.listeners.clear();
    hold.stop?.();
    hold.stop = undefined;
  }
}
