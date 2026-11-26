import { hilog } from '@kit.PerformanceAnalysisKit';
import type { SessionListItem } from 'appstate';
import { DesktopWorkspaceData } from '../desktop/DesktopWorkspaceData';
import type { DesktopWorkspaceRow, DesktopWorkspaceSnapshot } from '../desktop/DesktopWorkspaceData';
import { setDesktopWorkspaceEnabled, WEB_WORKSPACE_PAGE } from '../desktop/DesktopWorkspacePreference';

const ALL_SESSIONS: string = '';
const DOMAIN: number = 0xD000;
const TAG: string = 'DshDesktopWorkspace';

@Entry({ useSharedStorage: true })
@Component
struct DesktopWorkspace {
  @StorageProp('dshHostLaunchUrl') @Watch('onHostChanged') private hostUrl: string = '';
  @StorageProp('dshHostBootError') private hostError: string = '';
  @LocalStorageLink('dshDesktopWorkspaceActive') private active: boolean = false;
  @LocalStorageLink('dshDesktopWorkspaceId') private workspaceId: string = ALL_SESSIONS;
  @LocalStorageLink('dshDesktopSessionId') private sessionId: string = '';
  @LocalStorageLink('dshDesktopWebSessionId') private webSessionId: string = '';
  @LocalStorageLink('dshDesktopWebWorkspaceId') private webWorkspaceId: string = '';

  @State private workspaces: DesktopWorkspaceRow[] = [];
  @State private visibleSessions: SessionListItem[] = [];
  @State private selectedTitle: ResourceStr = '';
  @State private ready: boolean = false;
  @State private error: string = '';
  @State private switching: boolean = false;

  private sessions: SessionListItem[] = [];
  private data?: DesktopWorkspaceData;
  private pageActive: boolean = false;
  private measured: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.pageActive = true;
    this.onHostChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.pageActive = false;
    this.data?.stop();
    this.data = undefined;
  }

  private onHostChanged(): void {
    if (!this.pageActive) {
      return;
    }
    this.data?.stop();
    this.data = undefined;
    this.workspaces = [];
    this.sessions = [];
    this.visibleSessions = [];
    this.selectedTitle = '';
    this.ready = false;
    this.error = '';
    if (this.hostUrl.length === 0) {
      return;
    }
    this.data = new DesktopWorkspaceData((snapshot: DesktopWorkspaceSnapshot): void => {
      this.error = snapshot.error;
      if (!snapshot.ready) {
        return;
      }
      this.workspaces = snapshot.workspaces;
      this.sessions = snapshot.sessions;
      if (!this.workspaces.some((row: DesktopWorkspaceRow): boolean => row.id === this.workspaceId)) {
        this.workspaceId = ALL_SESSIONS;
      }
      this.updateSessions();
      this.ready = true;
    });
    this.data.start(this.hostUrl);
  }

  private updateSessions(): void {
    const workspace = this.workspaces.find((row: DesktopWorkspaceRow): boolean => row.id === this.workspaceId);
    if (workspace === undefined) {
      this.visibleSessions = this.sessions;
    } else {
      const members = new Set<string>(workspace.sessionIds);
      this.visibleSessions = this.sessions.filter((row: SessionListItem): boolean =>
        members.has(row.id) || this.isLegacySessionInWorkspace(row, workspace));
    }
    const current = this.visibleSessions.find((row: SessionListItem): boolean => row.id === this.sessionId);
    this.sessionId = current?.id ?? '';
    this.selectedTitle = current === undefined ? '' : this.sessionLabel(current);
  }

  private isLegacySessionInWorkspace(session: SessionListItem, workspace: DesktopWorkspaceRow): boolean {
    return workspace.path.length > 0 && session.cwd === workspace.path &&
      !this.workspaces.some((row: DesktopWorkspaceRow): boolean => row.sessionIds.includes(session.id));
  }

  private sessionLabel(session: SessionListItem): ResourceStr {
    return session.title || $r('app.string.desktop_experiment_unnamed');
  }

  private selectWorkspace(id: string): void {
    this.workspaceId = id;
    this.updateSessions();
  }

  private selectSession(session: SessionListItem): void {
    this.sessionId = session.id;
    this.selectedTitle = this.sessionLabel(session);
  }

  private markSidebarVisible(ready: boolean): void {
    if (ready && !this.measured) {
      this.measured = true;
      hilog.warn(DOMAIN, TAG, 'DSHM-TRACE ArkUI 工作区和会话列表可见');
    }
  }

  private async openWeb(leaveExperiment: boolean): Promise<void> {
    if (this.switching) {
      return;
    }
    this.switching = true;
    const ui = this.getUIContext();
    try {
      if (leaveExperiment) {
        const context = ui.getHostContext();
        if (context === undefined) {
          throw new Error('工作台设置不可用');
        }
        await setDesktopWorkspaceEnabled(context, false);
      }
      this.webSessionId = leaveExperiment ? '' : this.sessionId;
      this.webWorkspaceId = leaveExperiment ? '' :
        this.workspaces.find((row: DesktopWorkspaceRow): boolean => row.sessionIds.includes(this.sessionId))?.id ??
          this.workspaceId;
      hilog.warn(DOMAIN, TAG, 'DSHM-TRACE 从 ArkUI 打开 WebUI');
      await ui.getRouter().replaceUrl({ url: WEB_WORKSPACE_PAGE });
    } catch (_) {
      this.webSessionId = '';
      this.webWorkspaceId = '';
      this.switching = false;
      ui.getPromptAction().showToast({ message: $r('app.string.desktop_experiment_switch_failed') });
    }
  }

  @Builder
  private SidebarItem(title: ResourceStr, selected: boolean, select: () => void) {
    Button(title, { type: ButtonType.Normal })
      .width('100%')
      .height(40)
      .borderRadius(9)
      .backgroundColor(selected ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
      .fontColor(selected ? $r('sys.color.brand') : $r('sys.color.font_primary'))
      .fontSize(14)
      .labelStyle({ overflow: TextOverflow.Ellipsis, maxLines: 1 })
      .align(Alignment.Start)
      .accessibilitySelected(selected)
      .onClick(select)
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text($r('app.string.desktop_experiment_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Button($r('app.string.desktop_experiment_exit'))
          .enabled(!this.switching)
          .onClick((): void => { this.openWeb(true); })
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 144 })

      Row() {
        Column({ space: 8 }) {
          Text($r('app.string.desktop_experiment_workspaces'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          if (this.ready) {
            List({ space: 2 }) {
              ListItem() {
                this.SidebarItem($r('app.string.desktop_experiment_all_sessions'), this.workspaceId === ALL_SESSIONS,
                  (): void => this.selectWorkspace(ALL_SESSIONS))
              }
              ForEach(this.workspaces, (row: DesktopWorkspaceRow) => {
                ListItem() {
                  this.SidebarItem(row.title || row.path, this.workspaceId === row.id,
                    (): void => this.selectWorkspace(row.id))
                }
              }, (row: DesktopWorkspaceRow): string => row.id)
            }
            .width('100%')
            .constraintSize({ maxHeight: 180 })
            .onVisibleAreaChange([0], (visible: boolean): void => this.markSidebarVisible(visible))

            Text($r('app.string.desktop_experiment_sessions'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .margin({ top: 8 })
            if (this.visibleSessions.length > 0) {
              List({ space: 2 }) {
                ForEach(this.visibleSessions, (session: SessionListItem) => {
                  ListItem() {
                    this.SidebarItem(this.sessionLabel(session), this.sessionId === session.id,
                      (): void => this.selectSession(session))
                  }
                }, (session: SessionListItem): string => session.id)
              }
              .layoutWeight(1)
              .width('100%')
            } else {
              Text($r('app.string.desktop_experiment_empty'))
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
            }
          }
          if (this.error.length > 0 || this.hostError.length > 0) {
            Text(this.error || this.hostError)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            if (this.hostUrl.length > 0) {
              Button($r('app.string.desktop_experiment_retry')).onClick((): void => this.onHostChanged())
            }
          } else if (!this.ready) {
            Text($r('app.string.desktop_experiment_loading'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
        }
        .width('36%')
        .constraintSize({ maxWidth: 280 })
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor($r('sys.color.background_secondary'))

        Column({ space: 16 }) {
          if (this.ready) {
            Text(this.selectedTitle || $r('app.string.desktop_experiment_select'))
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Button($r('app.string.desktop_experiment_open_web'))
            .enabled(this.ready && this.sessionId.length > 0 && !this.switching)
            .onClick((): void => { this.openWeb(false); })
        }
        .height('100%')
        .layoutWeight(1)
        .padding(20)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
