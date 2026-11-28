export interface DesktopTimelineDiscussionDraft {
  open: boolean;
  text: string;
  id: string;
  busy: boolean;
  notice: string;
}

export const EMPTY_TIMELINE_DISCUSSION: DesktopTimelineDiscussionDraft = {
  open: false, text: '', id: '', busy: false, notice: ''
};

type DesktopTimelineDraftListener = (key: string, draft: DesktopTimelineDiscussionDraft) => void;

/** Drafts are scoped to the host and outlive the mounted Timeline panel. */
export class DesktopTimelineDiscussionDrafts {
  private readonly sessions = new Map<string, Map<string, DesktopTimelineDiscussionDraft>>();
  private readonly listeners = new Map<string, Set<DesktopTimelineDraftListener>>();

  read(session: string, key: string): DesktopTimelineDiscussionDraft {
    return this.sessions.get(session)?.get(key) ?? EMPTY_TIMELINE_DISCUSSION;
  }

  write(session: string, key: string, draft: DesktopTimelineDiscussionDraft): void {
    const entries = this.sessions.get(session) ?? new Map<string, DesktopTimelineDiscussionDraft>();
    if (draft.open || draft.text || draft.id || draft.busy || draft.notice) {
      entries.set(key, draft);
      this.sessions.set(session, entries);
    } else {
      entries.delete(key);
      if (entries.size === 0) { this.sessions.delete(session); }
    }
    this.listeners.get(session)?.forEach((listener: DesktopTimelineDraftListener): void => { listener(key, draft); });
  }

  watch(session: string, listener: DesktopTimelineDraftListener): () => void {
    const listeners = this.listeners.get(session) ?? new Set<DesktopTimelineDraftListener>();
    listeners.add(listener);
    this.listeners.set(session, listeners);
    return (): void => {
      listeners.delete(listener);
      if (listeners.size === 0 && this.listeners.get(session) === listeners) { this.listeners.delete(session); }
    };
  }
}
