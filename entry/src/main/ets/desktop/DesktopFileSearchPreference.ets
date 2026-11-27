import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { parseJson } from 'connection';
import {
  decodeDesktopFileSearchPreferenceBook, defaultDesktopFileSearchPreferences, DESKTOP_FILE_SEARCH_PREFERENCES_KEY,
  desktopFileSearchWorkspaceKey, encodeDesktopFileSearchPreferenceBook, encodeDesktopFileSearchPreferences,
  readDesktopFileSearchPreferences
} from './DesktopFileSearchModel';
import type { DesktopFileSearchPreferencePatch, DesktopFileSearchPreferences } from './DesktopFileSearchModel';

const PREFERENCES: string = 'dshm_desktop_workspace';

type WorkspaceListener = (value: DesktopFileSearchPreferences) => void;

interface WorkspaceSearchScope {
  snapshot: DesktopFileSearchPreferences;
  encoded: string;
  listeners: Set<WorkspaceListener>;
}

/** One preference book can serve the sidebar and each detached file navigator in a frame. */
export class DesktopFileSearchPreferenceBook {
  private readonly context: common.Context;
  private readonly scopes: Map<string, WorkspaceSearchScope> = new Map<string, WorkspaceSearchScope>();
  private readonly noWorkspace: DesktopFileSearchPreferences = defaultDesktopFileSearchPreferences();
  private native?: preferences.Preferences;
  private observing: boolean = false;
  private raw: string = '';
  private entries: Map<string, Object> = new Map<string, Object>();
  private readonly nativeChanged = (key: string): void => {
    if (key === DESKTOP_FILE_SEARCH_PREFERENCES_KEY && this.native !== undefined) { this.reload(this.native); }
  };

  constructor(context: common.Context) { this.context = context; }

  get(cwd: string): DesktopFileSearchPreferences {
    const key = desktopFileSearchWorkspaceKey(cwd);
    if (!key) { return this.noWorkspace; }
    const native = this.preferences();
    if (native !== undefined) { this.reload(native); }
    return this.scope(key).snapshot;
  }

  subscribe(cwd: string, listener: WorkspaceListener): () => void {
    const key = desktopFileSearchWorkspaceKey(cwd);
    if (!key) { return (): void => {}; }
    this.get(cwd);
    const scope = this.scope(key);
    const subscription = (value: DesktopFileSearchPreferences): void => listener(value);
    scope.listeners.add(subscription);
    this.observeNative();
    return (): void => {
      scope.listeners.delete(subscription);
      if (!this.hasListeners()) { this.stopObserving(); }
    };
  }

  update(cwd: string, patch: DesktopFileSearchPreferencePatch): boolean {
    const key = desktopFileSearchWorkspaceKey(cwd);
    if (!key) { return false; }
    const native = this.preferences();
    if (native === undefined || !this.reload(native)) { return false; }
    const current = this.scope(key).snapshot;
    const merged: DesktopFileSearchPreferences = {
      rules: patch.rules ?? current.rules,
      showHidden: patch.showHidden ?? current.showHidden,
      respectGitignore: patch.respectGitignore ?? current.respectGitignore
    };
    const changed = parseJson(encodeDesktopFileSearchPreferences(merged));
    if (changed === undefined && !this.entries.has(key)) { return true; }
    const updated = new Map<string, Object>(this.entries);
    if (changed === undefined) { updated.delete(key); }
    else { updated.set(key, changed); }
    const serialized = encodeDesktopFileSearchPreferenceBook(updated);
    if (serialized === this.raw) { return true; }
    const previous = this.raw;
    try {
      native.putSync(DESKTOP_FILE_SEARCH_PREFERENCES_KEY, serialized);
      native.flushSync();
    } catch (_) {
      this.restoreCachedWrite(native, previous, serialized);
      return false;
    }
    this.apply(serialized);
    return true;
  }

  private preferences(): preferences.Preferences | undefined {
    if (this.native === undefined) {
      try { this.native = preferences.getPreferencesSync(this.context, { name: PREFERENCES }); }
      catch (_) { return undefined; }
      if (this.hasListeners()) { this.observeNative(); }
    }
    return this.native;
  }

  private reload(native: preferences.Preferences): boolean {
    let raw = '';
    try {
      const value = native.getSync(DESKTOP_FILE_SEARCH_PREFERENCES_KEY, '');
      if (typeof value === 'string') { raw = value; }
    } catch (_) { return false; }
    this.apply(raw);
    return true;
  }

  private apply(raw: string): void {
    if (raw === this.raw) { return; }
    this.raw = raw;
    this.entries = decodeDesktopFileSearchPreferenceBook(raw);
    this.scopes.forEach((scope: WorkspaceSearchScope, key: string): void => {
      const snapshot = readDesktopFileSearchPreferences(this.entries.get(key));
      const encoded = encodeDesktopFileSearchPreferences(snapshot);
      if (encoded === scope.encoded) { return; }
      scope.snapshot = snapshot;
      scope.encoded = encoded;
      scope.listeners.forEach((listener: WorkspaceListener): void => {
        if (snapshot === scope.snapshot) { listener(snapshot); }
      });
    });
  }

  private scope(key: string): WorkspaceSearchScope {
    const existing = this.scopes.get(key);
    if (existing !== undefined) { return existing; }
    const snapshot = readDesktopFileSearchPreferences(this.entries.get(key));
    const created: WorkspaceSearchScope = {
      snapshot: snapshot, encoded: encodeDesktopFileSearchPreferences(snapshot), listeners: new Set<WorkspaceListener>()
    };
    this.scopes.set(key, created);
    return created;
  }

  private hasListeners(): boolean {
    for (const scope of this.scopes.values()) {
      if (scope.listeners.size > 0) { return true; }
    }
    return false;
  }

  private observeNative(): void {
    if (this.observing || this.native === undefined) { return; }
    try {
      this.native.on('change', this.nativeChanged);
      this.observing = true;
    } catch (_) {}
  }

  private stopObserving(): void {
    if (!this.observing || this.native === undefined) { return; }
    try {
      this.native.off('change', this.nativeChanged);
      this.observing = false;
    } catch (_) {}
  }

  private restoreCachedWrite(native: preferences.Preferences, previous: string, attempted: string): void {
    try {
      if (native.getSync(DESKTOP_FILE_SEARCH_PREFERENCES_KEY, '') === attempted) {
        if (previous) { native.putSync(DESKTOP_FILE_SEARCH_PREFERENCES_KEY, previous); }
        else { native.deleteSync(DESKTOP_FILE_SEARCH_PREFERENCES_KEY); }
      }
    } catch (_) {}
  }
}
