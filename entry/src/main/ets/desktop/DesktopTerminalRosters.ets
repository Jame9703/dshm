import { getArray, getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';

export interface DesktopTerminalRosterSink {
  items: (items: Object[]) => void;
  problem: (message: string) => void;
}

interface DesktopTerminalRosterEntry {
  sinks: Set<DesktopTerminalRosterSink>;
  generation: number;
  stop?: () => void;
  latest?: Object[];
}

/** One roster stream for the active conversation and any visible terminal panes in that session. */
export class DesktopTerminalRosters {
  private readonly host: DesktopHostActions;
  private readonly entries = new Map<string, DesktopTerminalRosterEntry>();
  private connected: boolean = false;

  constructor(host: DesktopHostActions) { this.host = host; }

  watch(sessionId: string, sink: DesktopTerminalRosterSink): () => void {
    let entry = this.entries.get(sessionId);
    if (entry === undefined) {
      entry = { sinks: new Set<DesktopTerminalRosterSink>(), generation: 0 };
      this.entries.set(sessionId, entry);
    }
    const watched = entry;
    watched.sinks.add(sink);
    if (watched.latest !== undefined) { sink.items(watched.latest); }
    this.open(sessionId, watched);
    return (): void => {
      watched.sinks.delete(sink);
      if (watched.sinks.size === 0 && this.entries.get(sessionId) === watched) {
        this.entries.delete(sessionId);
        this.release(watched);
      }
    };
  }

  connect(): void {
    this.connected = true;
    this.entries.forEach((entry: DesktopTerminalRosterEntry, sessionId: string): void => this.open(sessionId, entry));
  }

  dispose(): void {
    this.connected = false;
    this.entries.forEach((entry: DesktopTerminalRosterEntry): void => this.release(entry));
    this.entries.clear();
  }

  private release(entry: DesktopTerminalRosterEntry): void {
    entry.generation++;
    entry.sinks.clear();
    entry.stop?.();
    entry.stop = undefined;
    entry.latest = undefined;
  }

  private open(sessionId: string, entry: DesktopTerminalRosterEntry): void {
    if (!this.connected || entry.stop !== undefined) { return; }
    const generation = ++entry.generation;
    entry.stop = this.host.watch('terminal/watch', { 'sessionId': sessionId }, {
      onItem: (value: Object): void => {
        if (generation !== entry.generation) { return; }
        const wrapper: Record<string, Object> = { 'items': value };
        const items = getArray(wrapper, 'items');
        if (items === undefined) { return; }
        entry.latest = items;
        Array.from(entry.sinks).forEach((sink: DesktopTerminalRosterSink): void => {
          if (entry.sinks.has(sink)) { sink.items(items); }
        });
      },
      onError: (code: string, message: string): void => {
        if (generation !== entry.generation) { return; }
        entry.stop = undefined;
        entry.latest = undefined;
        if (code.startsWith('carrier/')) { return; }
        Array.from(entry.sinks).forEach((sink: DesktopTerminalRosterSink): void => {
          if (entry.sinks.has(sink)) { sink.problem(message); }
        });
      },
      onEnd: (): void => {
        if (generation !== entry.generation) { return; }
        entry.stop = undefined;
        entry.latest = undefined;
      }
    });
  }
}

export interface DesktopAgentTerminalBinding {
  id: string;
  title: string;
  agentControlled: boolean;
  sandboxMode: string;
}

export interface DesktopAgentTerminalChanges {
  opened: DesktopAgentTerminalBinding[];
  ended: Set<string>;
  metadata: Map<string, DesktopAgentTerminalBinding>;
}

interface DesktopAgentTerminalHistory {
  controlled: Set<string>;
  represented: Set<string>;
}

/** A removed agent-controlled shell closes its tab. A user takeover ends automatic cleanup. */
export class DesktopAgentTerminalInventory {
  private readonly sessions = new Map<string, DesktopAgentTerminalHistory>();

  apply(sessionId: string, items: Object[], bound: string[]): DesktopAgentTerminalChanges {
    let session = this.sessions.get(sessionId);
    if (session === undefined) {
      session = { controlled: new Set<string>(), represented: new Set<string>() };
      this.sessions.set(sessionId, session);
    }
    const current = session;
    bound.forEach((id: string): void => { current.represented.add(id); });
    const listed = new Set<string>();
    const controlled = new Set<string>();
    const opened: DesktopAgentTerminalBinding[] = [];
    const metadata = new Map<string, DesktopAgentTerminalBinding>();
    for (const item of items) {
      const id = getString(item, 'id');
      if (!id) { continue; }
      listed.add(id);
      const agent = getString(item, 'origin') === 'agent';
      const binding: DesktopAgentTerminalBinding = { id: id, title: getString(item, 'title') ?? '',
        agentControlled: agent && getString(item, 'control') === 'agent',
        sandboxMode: agent ? getString(item, 'sandboxMode') ?? '' : '' };
      metadata.set(id, binding);
      if (!agent) { continue; }
      if (binding.agentControlled) { controlled.add(id); }
      if (getString(item, 'state') === 'running' && !current.represented.has(id)) {
        current.represented.add(id);
        opened.push(binding);
      }
    }
    const ended = new Set<string>();
    current.controlled.forEach((id: string): void => {
      if (!listed.has(id)) { ended.add(id); }
    });
    current.controlled = controlled;
    return { opened: opened, ended: ended, metadata: metadata };
  }

  clear(): void { this.sessions.clear(); }
}
