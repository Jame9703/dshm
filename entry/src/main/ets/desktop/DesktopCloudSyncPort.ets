import { common } from '@kit.AbilityKit';
import {
  fetchAccountDisplayName, KindStat, PluginDiff, PluginSpec, SilentSignInKind, SyncEngine, SyncRoot,
  TaskProgress, silentSignIn, specKind
} from 'platform';

export interface DesktopCloudPlugin {
  name: string;
  spec: string;
  kind: string;
}

export interface DesktopCloudSyncOverview {
  signedIn: boolean;
  enabled: boolean;
  displayName: string;
  accountLabel: string;
  cloudText: string;
  cloudBadge: string;
  cloudOk: boolean;
  lastSyncText: string;
  pendingSessions: number;
  pendingBytes: number;
  pluginCount: number;
  plugins: DesktopCloudPlugin[];
  units: KindStat[];
}

export interface DesktopCloudSyncActivity {
  running: boolean;
  progress: TaskProgress;
}

export interface DesktopCloudSignIn {
  kind: 'success' | 'cancelled' | 'error';
  reason: string;
}

export interface DesktopCloudPluginList {
  present: boolean;
  missing: DesktopCloudPlugin[];
  differing: number;
}

export interface DesktopCloudPluginInstallResult {
  ok: boolean;
  summary: string;
  needsRestart: boolean;
}

export interface DesktopCloudSyncPort {
  overview(): DesktopCloudSyncOverview;
  activity(): DesktopCloudSyncActivity;
  refreshStats(): Promise<void>;
  generation(): number;
  signIn(onProfile?: () => void): Promise<DesktopCloudSignIn>;
  signOut(): void;
  setEnabled(on: boolean): Promise<string>;
  upload(): Promise<string>;
  pull(): Promise<string>;
  checkPlugins(): Promise<DesktopCloudPluginList>;
  installPlugins(picked: DesktopCloudPlugin[]): Promise<DesktopCloudPluginInstallResult>;
}

function describePlugin(plugin: PluginSpec): DesktopCloudPlugin {
  return { name: plugin.name, spec: plugin.spec, kind: specKind(plugin.spec) };
}

/** Adapter for the same application-wide account and storage used by both WebUI shells. */
class LiveDesktopCloudSync implements DesktopCloudSyncPort {
  private static signingIn: boolean = false;
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    SyncRoot.attach(context.filesDir);
  }

  overview(): DesktopCloudSyncOverview {
    const state = SyncEngine.state();
    // Do not walk the session tree on the signed-out screen or on each progress tick.
    const scope = state.signedIn ? SyncEngine.scopeSummary() : null;
    return {
      signedIn: state.signedIn, enabled: state.enabled,
      displayName: state.displayName, accountLabel: state.accountLabel,
      cloudText: state.cloudServiceText, cloudBadge: state.cloudServiceBadge, cloudOk: state.cloudServiceOk,
      lastSyncText: state.lastSyncText, pendingSessions: scope?.sessionCount ?? 0, pendingBytes: scope?.totalBytes ?? 0,
      pluginCount: state.pluginCount,
      plugins: state.signedIn ? SyncEngine.plugins().slice(0, 8).map(describePlugin) : [],
      units: state.signedIn ? SyncEngine.stats() : []
    };
  }

  activity(): DesktopCloudSyncActivity {
    return { running: SyncEngine.isRunning(), progress: SyncEngine.currentProgress() };
  }

  refreshStats(): Promise<void> {
    return SyncEngine.refreshStat(this.context);
  }

  generation(): number {
    return SyncEngine.currentGeneration();
  }

  async signIn(onProfile?: () => void): Promise<DesktopCloudSignIn> {
    if (LiveDesktopCloudSync.signingIn || SyncEngine.state().signedIn) {
      return { kind: 'cancelled', reason: '' };
    }
    LiveDesktopCloudSync.signingIn = true;
    const before = this.generation();
    try {
      const result = await silentSignIn(this.context);
      if (before !== this.generation() || result.kind === SilentSignInKind.CANCELED) {
        return { kind: 'cancelled', reason: '' };
      }
      if (result.kind !== SilentSignInKind.OK) {
        return { kind: 'error', reason: result.reason };
      }
      SyncEngine.adoptLogin(result.unionId);
      const owner = this.generation();
      fetchAccountDisplayName(this.context).then((profile): void => {
        if (profile.ok && this.generation() === owner) {
          SyncEngine.adoptAccountLabel(profile.label);
          onProfile?.();
        }
      }).catch((): void => {});
      return { kind: 'success', reason: '' };
    } catch (_) {
      return { kind: 'error', reason: '' };
    } finally {
      LiveDesktopCloudSync.signingIn = false;
    }
  }

  signOut(): void {
    SyncEngine.signOut();
  }

  setEnabled(on: boolean): Promise<string> {
    return SyncEngine.setEnabled(on);
  }

  upload(): Promise<string> {
    return SyncEngine.syncNow(this.context);
  }

  pull(): Promise<string> {
    return SyncEngine.pullAndImport(this.context);
  }

  async checkPlugins(): Promise<DesktopCloudPluginList> {
    const manifest = await SyncEngine.readRemotePluginManifest(this.context);
    if (!manifest) {
      return { present: false, missing: [], differing: 0 };
    }
    const diff: PluginDiff = await SyncEngine.pluginDiff(this.context, manifest);
    return { present: true, missing: diff.missing.map(describePlugin), differing: diff.differing.length };
  }

  async installPlugins(picked: DesktopCloudPlugin[]): Promise<DesktopCloudPluginInstallResult> {
    const specs = picked.map((plugin: DesktopCloudPlugin): PluginSpec => {
      return { name: plugin.name, spec: plugin.spec };
    });
    const report = await SyncEngine.restorePlugins(this.context, specs);
    return { ok: report.ok, summary: report.summary, needsRestart: report.needsRestart };
  }
}

export function createDesktopCloudSyncPort(context: common.UIAbilityContext): DesktopCloudSyncPort {
  return new LiveDesktopCloudSync(context);
}
