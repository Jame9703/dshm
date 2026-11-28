import { KeyCode } from '@kit.InputKit';
import { common } from '@kit.AbilityKit';
import { ComponentContent, LengthMetrics, window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { desktopAttachmentUri, desktopDroppedFiles, packDesktopClipboardPicture } from '../desktop/DesktopAttachmentIntake';
import type { DesktopDroppedFiles } from '../desktop/DesktopAttachmentIntake';
import { StartupFrameCallback } from '../common/DesktopStartup';
import { desktopDockTabRevealDelta } from '../desktop/DesktopDockTabScroll';
import { getArray, getRecord, getString, parseTarget, randomUuid } from 'connection';
import type { RpcResult } from 'connection';
import { SESSION_PAGE_ENDPOINT, WORKSPACE_ARCHIVE_SESSION_ENDPOINT } from 'dshcompat';
import type { DesktopInteraction, DesktopQuestionAnswer } from '../desktop/DesktopInteractions';
import { localDesktopQuestionDrafts } from '../desktop/DesktopQuestionDrafts';
import type { DesktopQuestionProgress } from '../desktop/DesktopQuestionDrafts';
import { DesktopTerminalPane } from '../desktop/DesktopTerminalPane';
import { DesktopTerminalGuide, DesktopTerminalTitle } from '../desktop/DesktopTerminalChrome';
import type { DesktopTerminalRow } from '../desktop/DesktopTerminalClient';
import type { DesktopTerminalLaunchRequest } from '../desktop/DesktopTerminalShells';
import { DesktopAgentTerminalInventory } from '../desktop/DesktopTerminalRosters';
import type { DesktopTerminalRosterSink } from '../desktop/DesktopTerminalRosters';
import { DesktopBrowserPane } from '../desktop/DesktopBrowserPane';
import { desktopBrowserAddress } from '../desktop/DesktopBrowserAddress';
import { DesktopFilesPane } from '../desktop/DesktopFilesPane';
import { DesktopFileNavigatorBook, DesktopFileNavigatorLink, desktopFileNavigatorKey } from '../desktop/DesktopFileNavigator';
import { desktopFileTypeIcon } from '../desktop/DesktopFileType';
import { DesktopFileSearchPreferenceBook } from '../desktop/DesktopFileSearchPreference';
import type { DesktopDocumentViewState } from '../desktop/DesktopDocumentZoomModel';
import { DesktopChangesPane } from '../desktop/DesktopChangesPane';
import { DesktopChangeTarget } from '../desktop/DesktopArtifacts';
import { DesktopPlanPreviewPane } from '../desktop/DesktopPlanPreviewPane';
import type { DesktopPlanDocument } from '../desktop/DesktopPlan';
import { DesktopCompactionPreviewPane } from '../desktop/DesktopCompactionPreviewPane';
import { readDesktopCompactionSummary } from '../desktop/DesktopCompactionModel';
import { exportDesktopLog } from '../desktop/DesktopLogExport';
import { DesktopLogStage, DesktopSessionLogDialog } from '../desktop/DesktopSessionLogDialog';
import { DesktopGoalAction, DesktopGoalRef } from '../desktop/DesktopGoal';
import { DesktopFeedback, DesktopFeedbackTarget, DesktopRating } from '../desktop/DesktopFeedback';
import { DesktopFeedbackDialog } from '../desktop/DesktopFeedbackDialog';
import { desktopHostProblem } from '../desktop/DesktopHostActions';
import { DesktopWorkspaceSearchResults } from '../desktop/DesktopWorkspaceSearch';
import { desktopWorkspaceSearchQuery } from '../desktop/DesktopWorkspaceSearchModel';
import { desktopSubagentCatalog, desktopSubagentFromSummary } from '../desktop/DesktopSubagents';
import type { DesktopSubagentEntry } from '../desktop/DesktopSubagents';
import { DesktopAccountPane } from '../desktop/DesktopAccountPane';
import { DesktopDeepSeekKeyDialog } from '../desktop/DesktopDeepSeekKeyDialog';
import { readDesktopDeepSeekKeyTarget } from '../desktop/DesktopDeepSeekKeySetup';
import type { DesktopDeepSeekKeyTarget } from '../desktop/DesktopDeepSeekKeySetup';
import { DesktopAccountOnboardingLayer } from '../desktop/DesktopAccountOnboardingLayer';
import { emptyDesktopOnboardingView } from '../desktop/DesktopAccountOnboardingState';
import type { DesktopOnboardingView } from '../desktop/DesktopAccountOnboardingState';
import { emptyDesktopCodingToolsSnapshot } from '../desktop/DesktopCodingTools';
import type { DesktopCodingToolsSnapshot } from '../desktop/DesktopCodingTools';
import type { DesktopPresetDefaultSync } from '../desktop/DesktopPresetDefaults';
import { DesktopAccountNoticeCard } from '../desktop/DesktopAccountNoticeCard';
import type { DesktopAccountNotice } from '../desktop/DesktopAccountNotices';
import { desktopAccountPlatformLink, emptyDesktopAccountSettingsIdentity } from '../desktop/DesktopAccountSettingsModel';
import type { DesktopAccountSettingsIdentity } from '../desktop/DesktopAccountSettingsModel';
import type { DesktopAccountDetailsAccess, DesktopAccountDetailsSnapshot } from '../desktop/DesktopAccountDetails';
import type { DesktopGeneralHostAccess } from '../desktop/DesktopGeneralHostPreferences';
import { desktopAccountContactUrl } from '../desktop/DesktopAccountContact';
import { DesktopAccountQuotaDialog, DesktopQuotaToast, DESKTOP_QUOTA_TOAST_HOLD_MS, DESKTOP_QUOTA_TOAST_FADE_MS }
  from '../desktop/DesktopQuotaNotice';
import type { DesktopQuotaNotice } from '../desktop/DesktopQuotaNoticeModel';
import { controlMaterial, copyText, dialogMaterial, mimeTypeForName, openExternalUrl, openFileLocation, openSystemPreview, PickOutcome,
  pickDocumentUris, pickFolder, readDeviceFacts, readDocumentBytes, uriFromPath } from 'platform';
import { desktopMenuOptions, desktopPluginEntryItems } from '../desktop/DesktopMenuOptions';
import { DesktopPluginsPane } from '../desktop/DesktopPluginsPane';
import { DesktopSchedulePane } from '../desktop/DesktopSchedulePane';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { followSessionAddress, followSubagentAddress, projectSessionPage } from 'appstate';
import type { ModelSelection, QueueActionBody, SessionListItem } from 'appstate';
import { DesktopConversationPane } from '../desktop/DesktopConversationPane';
import { DesktopTimelinePane } from '../desktop/DesktopTimelinePane';
import { emptyDesktopTimelineBrowse } from '../desktop/DesktopTimelineModel';
import type { DesktopTimelineBrowseState, DesktopTimelineLocation } from '../desktop/DesktopTimelineModel';
import { DesktopTimelineViewport } from '../desktop/DesktopTimelineViewport';
import { DEFAULT_DESKTOP_TIMELINE_PREFERENCES } from '../desktop/DesktopTimelinePreferences';
import type { DesktopTimelinePreferences } from '../desktop/DesktopTimelinePreferences';
import { DesktopDockChatPane } from '../desktop/DesktopDockChatPane';
import { DesktopReplyMedia } from '../desktop/DesktopReplyMedia';
import type { DesktopDockChatActions } from '../desktop/DesktopDockChatPane';
import { EMPTY_DESKTOP_DRAFT } from '../desktop/DesktopDraftReferences';
import type { DesktopComposerDraft } from '../desktop/DesktopDraftReferences';
import { DesktopShortcutDialog } from '../desktop/DesktopShortcutDialog';
import { DesktopShortcut, desktopShortcutEqual, desktopShortcutFromEvent, desktopShortcutLabels, desktopShortcutModifiers, desktopShortcutRows,
  desktopShortcutValue, readDesktopShortcuts } from '../desktop/DesktopShortcuts';
import type { DesktopShortcutRow } from '../desktop/DesktopShortcuts';
import { desktopDockCloseFloat, desktopDockCloseTab, desktopDockFloat, desktopDockFloatPosition, desktopDockFloatRect,
  desktopDockFocusFloat, desktopDockMerge, desktopDockMoveTab, desktopDockOpen, desktopDockSeatFloat, desktopDockSelect,
  desktopDockPresentation, desktopDockResize, desktopDockSplit, desktopDockSplitFraction, desktopDockTab,
  desktopDockBindTerminal, desktopDockBrowserAddress, desktopDockChatTab, desktopDockNavigatePreview, desktopDockOpenPreviewIn,
  desktopDockResourceId,
  desktopDockTerminalIds,
  desktopDockTerminalTab, desktopDockProjectTerminals,
  DesktopDockKind, emptyDesktopDock } from '../desktop/DesktopRightDock';
import type { DesktopDockChatTarget, DesktopDockFloat, DesktopDockLayout, DesktopDockPane, DesktopDockRect, DesktopDockTab } from '../desktop/DesktopRightDock';
import { readDesktopDock, readDesktopDockTerminalIds, saveDesktopDock } from '../desktop/DesktopRightDockPreference';
import { copyDesktopReferenceImage, DesktopReferenceAction, openDesktopReferenceFile, saveDesktopReferenceFile } from '../desktop/DesktopReferenceActions';
import { DesktopReferenceSource } from '../desktop/DesktopReferenceActions';
import type { DesktopFileReferenceOffer } from '../desktop/DesktopReferenceActions';
import { desktopReferenceText } from '../desktop/DesktopReferences';
import { DesktopAttachmentViewer, desktopDraftGif } from '../desktop/DesktopAttachments';
import type { DesktopDraftAttachment, DesktopMediaAttachment } from '../desktop/DesktopAttachments';
import type { DesktopUnreadSession } from '../desktop/DesktopSessionReading';
import { DesktopArchiveDialog, DesktopArchiveFilter, desktopArchiveActivity } from '../desktop/DesktopSessionArchive';
import type { DesktopArchiveNotice, DesktopArchiveRequest } from '../desktop/DesktopSessionArchive';
import type { DesktopConversation, DesktopConversationSnapshot } from '../desktop/DesktopConversation';
import { DesktopAccountSessionNotice, DesktopWorkspaceData } from '../desktop/DesktopWorkspaceData';
import { DesktopWorkspacePicker } from '../desktop/DesktopWorkspacePicker';
import type { DesktopWorkspacePickerRow } from '../desktop/DesktopWorkspacePickerModel';
import { readDesktopNativeDestination } from '../desktop/DesktopWorkspaceHandoff';
import type { DesktopCordisWebLocation, DesktopHandoffSubagent, DesktopNativeDestination, DesktopPluginLocation,
  DesktopWebDestination } from '../desktop/DesktopWorkspaceHandoff';
import { DesktopCordisControl } from '../desktop/DesktopCordisControl';
import type { DesktopSessionCreation, DesktopWorkspaceRow, DesktopWorkspaceSnapshot } from '../desktop/DesktopWorkspaceData';
import { desktopWorkspaceAppearance, saveDesktopWorkspaceAppearance, setDesktopWorkspaceEnabled,
  desktopWorkspaceSelectionHost, readDesktopSavedChildSelection, readDesktopWorkspaceSelection, saveDesktopWorkspaceSelection,
  WEB_WORKSPACE_PAGE } from '../desktop/DesktopWorkspacePreference';
import type { DesktopSavedChildSelection } from '../desktop/DesktopWorkspacePreference';
import { DEFAULT_DESKTOP_TYPOGRAPHY, sameDesktopTypography } from '../desktop/DesktopTheme';
import type { DesktopTheme, DesktopTypography } from '../desktop/DesktopTheme';
import lazy { buildDesktopSettingsSurface, desktopSettingsSize } from '../desktop/DesktopSettingsSurface';
import type { DesktopSettingsSize, DesktopSettingsSurfaceParams } from '../desktop/DesktopSettingsSurface';
import lazy { disposeOverlayContent } from '../common/DesktopWebPicker';
import { DesktopSessionGrouping, DesktopSessionOrdering, desktopReorderSessions, desktopSessionAccount,
  desktopSessionOrder, desktopSessionOrdersEqual, desktopSessionRows, desktopSidebarSections,
  desktopWorkspaceMove, desktopWorkspaceParents } from '../desktop/DesktopSessionOrder';
import type { DesktopSessionInsertion, DesktopSidebarSection, DesktopWorkspaceGroup } from '../desktop/DesktopSessionOrder';
import { readDesktopSidebarView, saveDesktopSidebarView } from '../desktop/DesktopSidebarPreference';
import { desktopRunningSidebarChildren, desktopSidebarAge, DesktopSidebarAgeUnit, DesktopSidebarPending,
  desktopSidebarRequired, desktopSidebarRevealDepth, desktopSidebarRows, SIDEBAR_SESSION_PAGE } from '../desktop/DesktopSidebarStatus';

const DOMAIN: number = 0xD000;
const TAG: string = 'DshDesktopWorkspace';
const DOCK_HANDLE_WIDTH: number = 7;
const DOCK_MIN_WIDTH: number = 220;
const DOCK_SPLIT_MIN_WIDTH: number = 540;
const DOCK_TAB_TITLE_HEIGHT: number = 28;

interface DesktopDockTabTarget {
  session: string;
  pane: number;
  tab: string;
}

interface DesktopDockTabContext extends DesktopDockTabTarget {
  serial: number;
  offset: Position;
}

interface DesktopAccountSessionToast {
  notice: DesktopAccountSessionNotice;
  token: number;
  fading: boolean;
}

interface DesktopAccountSessionToastTimers {
  fade: number;
  dismiss: number;
}

interface DesktopQuotaBrowserVisit {
  notice: number;
  release: () => void;
  departed: boolean;
  returned: boolean;
  launched: boolean;
}

interface DesktopNewSessionNavigation {
  id: string;
  workspace: string;
  sourceSession: string;
  sourceWorkspace: string;
  sourcePanel: string;
  sourceVersion: number;
  prompt: string;
}

interface DesktopSessionDrag {
  owner: string;
  groupId: string;
  session: SessionListItem;
}

interface DesktopSidebarDisplaySection extends DesktopSidebarSection {
  rows: SessionListItem[];
  hidden: number;
  hasOverflow: boolean;
}

interface DesktopWorkspaceDropBand {
  id: string;
  left: number;
  right: number;
  top: number;
  bottom: number;
}

interface DesktopWorkspaceDropCue {
  band: DesktopWorkspaceDropBand;
  after: boolean;
}

interface DesktopTerminalRenameTarget {
  version: number;
  sessionId: string;
  tabId: string;
  terminalId: string;
  title: string;
}

interface DesktopDockDrop {
  pane: number;
  before: string;
  side: string;
}

@Entry({ useSharedStorage: true })
@Component
struct DesktopWorkspace {
  @StorageProp('dshHostLaunchUrl') @Watch('onHostChanged') private hostUrl: string = '';
  @StorageProp('dshHostBootError') private hostError: string = '';
  @LocalStorageLink('dshDesktopWorkspaceActive') private active: boolean = false;
  @LocalStorageLink('dshDesktopWorkspaceId') private workspaceId: string = '';
  @LocalStorageLink('dshDesktopSessionId') private sessionId: string = '';
  @LocalStorageLink('dshDesktopSelectionHost') private selectionHost: string = '';
  private savedSessionId?: string;
  @LocalStorageLink('dshDesktopWebHandoff') private webHandoff: string = '';
  @LocalStorageLink('dshDesktopNativeHandoff') private nativeHandoff: string = '';
  private nativeSelectionVersion: number = 0;

  @State private visibleGroups: DesktopWorkspaceGroup[] = [];
  @State private expandedIds: string[] = [];
  @State private sidebarGrouping: DesktopSessionGrouping = DesktopSessionGrouping.WORKSPACE;
  @State private sidebarOrdering: DesktopSessionOrdering = DesktopSessionOrdering.UPDATED;
  private manualOrders: Map<string, string[]> = new Map<string, string[]>();
  private sidebarExpansionLoaded: boolean = false;
  @State private sidebarCollapsed: boolean = false;
  @State private sidebarWidth: number = 280;
  @State private defaultDockWidth: number = 340;
  @State private rightDock: DesktopDockLayout = emptyDesktopDock();
  @State private dockDragWidth: number = 0;
  @State private dockDragFraction: number = 0;
  @State private dockGripHover: number = 0;
  @State private dockDropCue: string = '';
  @State private dockDragTitle: string = '';
  @State private dockDragX: number = 0;
  @State private dockDragY: number = 0;
  @State private floatPreview: DesktopDockRect | undefined = undefined;
  @State private floatGestureTab: string = '';
  private floatOrigin?: DesktopDockRect;
  private dockBounds?: Area;
  private workbenchBounds?: Area;
  private sessionContentBounds?: Area;
  @State private sessionDrag?: DesktopSessionDrag = undefined;
  @State private sessionDropPane: number = -1;
  @State private sessionInsertion?: DesktopSessionInsertion = undefined;
  private sidebarListBounds?: Area;
  @State private workspaceDragId: string = '';
  @State private workspaceDragTitle: string = '';
  @State private workspaceDropCue?: DesktopWorkspaceDropCue = undefined;
  private workspaceDropBands: DesktopWorkspaceDropBand[] = [];
  private readonly workspaceHeaderBounds: Map<string, Area> = new Map<string, Area>();
  private readonly sessionRowBounds: Map<string, Area> = new Map<string, Area>();
  private dockDrag?: DesktopDockTabTarget;
  private dockMiddlePress?: DesktopDockTabTarget;
  private dockDrop?: DesktopDockDrop;
  private dockPanActive: boolean = false;
  private readonly dockTabBounds = new Map<string, Area>();
  private readonly dockTabScrollers: Scroller[] = [new Scroller(), new Scroller()];
  private readonly dockTabViewports = new Map<number, Area>();
  private readonly dockTabRevealPending = new Set<number>();
  private dockTabRevealPosted: boolean = false;
  private browserTabCount: number = 0;
  private readonly dockPaneBounds = new Map<number, Area>();
  private dockSessionId: string = '';
  private dockResizeStart: number = 0;
  private dockResizeSession: string = '';
  private readonly docks = new Map<string, DesktopDockLayout>();
  private readonly shownPlanReviews: Set<string> = new Set<string>();
  @State private searchOpen: boolean = false;
  @State private query: string = '';
  @State private selectedWorkspaceTitle: ResourceStr = '';
  @State @Watch('refreshSettingsSurface') private appearance: string = 'system';
  @State private typography: DesktopTypography = DEFAULT_DESKTOP_TYPOGRAPHY;
  @State private shortcutsOpen: boolean = false;
  @State private shortcutBindings: DesktopShortcutRow[] = desktopShortcutRows([]);
  @State private terminalCreateRequest?: DesktopTerminalLaunchRequest = undefined;
  @State private selectedTitle: ResourceStr = '';
  @State private selectedSessionDirectory: string = '';
  @State private referenceOffer: DesktopFileReferenceOffer | undefined = undefined;
  @State private ready: boolean = false;
  @State private error: string = '';
  @State private switching: boolean = false;
  @State private settingsOpen: boolean = false;
  private settingsSurface?: ComponentContent<DesktopSettingsSurfaceParams>;
  private settingsSurfaceSize?: DesktopSettingsSize;
  private settingsSizing: boolean = false;
  private settingsSurfaceReady: boolean = false;
  private settingsClosing: boolean = false;
  private settingsSection: string = 'settings.general';
  private settingsOpeningPlugins: boolean = false;
  @State @Watch('onPanelChanged') private panel: string = 'session';
  @State private pluginName: string = '';
  @State private pluginLocation: DesktopPluginLocation = { kind: 'list', name: '', rowId: '' };
  private pluginTitle: string = '';
  private pluginDescription: string = '';
  @State private workspaceBusy: boolean = false;
  private workspaceFolderErrorOpen: boolean = false;
  @State private forking: boolean = false;
  private pendingForkId: string = '';
  private pendingForkSource: string = '';
  private pendingNewSession?: DesktopNewSessionNavigation;
  @State private archivedIds: string[] = [];
  @State private archiveFilter: DesktopArchiveFilter = DesktopArchiveFilter.HIDE;
  @State private archiveRequest: DesktopArchiveRequest | undefined = undefined;
  @State private archiveNotice: DesktopArchiveNotice | undefined = undefined;
  @State private archiveProblem: string = '';
  private archiveDialog: number = -1;
  private archiveDialogVersion: number = 0;
  private archiveNoticeTimer: number = -1;
  @State private pinned: string[] = [];
  @State private unreadSessions: Map<string, DesktopUnreadSession> = new Map<string, DesktopUnreadSession>();
  @State private runningSidebarChildren: Map<string, number> = new Map<string, number>();
  @State private sidebarPending: Map<string, DesktopSidebarPending> = new Map<string, DesktopSidebarPending>();
  @State private sidebarAttention: Set<string> = new Set<string>();
  @State private sidebarWatermarks: Map<string, number> = new Map<string, number>();
  private readonly sidebarOverflowBounds: Map<string, Area> = new Map<string, Area>();
  @State private readingReady: boolean = false;
  @State private renameOpen: boolean = false;
  @State private renameDraft: string = '';
  private renameDialog: number = -1;
  private renameDialogVersion: number = 0;
  private renameId: string = '';
  private renameWorkspace: boolean = false;
  @State private chat: DesktopConversationSnapshot | undefined = undefined;
  @State private timelineLocation?: DesktopTimelineLocation = undefined;
  private pendingTimelineLocation?: DesktopTimelineLocation;
  private timelineLocationRevision: number = 0;
  @State private timelineRoot: string = '';
  @State private timelineBrowse: DesktopTimelineBrowseState = emptyDesktopTimelineBrowse();
  private readonly timelineBrowses = new Map<string, DesktopTimelineBrowseState>();
  private readonly timelineViewports = new Map<string, DesktopTimelineViewport>();
  private timelineViewport = new DesktopTimelineViewport();
  @State private timelinePreferences: DesktopTimelinePreferences = DEFAULT_DESKTOP_TIMELINE_PREFERENCES;
  private timelinePreferencesReady: boolean = false;
  private timelineObservedTree?: boolean;
  private timelineAutoPending: boolean = false;
  @State private interactions: DesktopInteraction[] = [];
  @State private draft: DesktopComposerDraft = EMPTY_DESKTOP_DRAFT;
  @State private chatError: string = '';
  @State private attachments: DesktopDraftAttachment[] = [];
  private readonly attachmentsBySession: Map<string, DesktopDraftAttachment[]> = new Map<string, DesktopDraftAttachment[]>();
  private imageDialog: number = -1;
  private imageDialogVersion: number = 0;
  private imageDialogOpening: boolean = false;
  @State private creating: boolean = false;
  @State private landingPreset: string = '';
  @State private busySessions: string[] = [];
  @State private stoppingSessions: string[] = [];
  @State private copyingTranscript: boolean = false;
  @State private exportingLog: boolean = false;
  @State private logStage: DesktopLogStage = DesktopLogStage.PREPARING;
  @State private logProblem: string = '';
  private logDialog: number = -1;
  private logDialogVersion: number = 0;
  @State private choosingFeedback: boolean = false;
  private feedbackDialog: number = -1;
  private feedbackDialogVersion: number = 0;
  private openingFeedback: boolean = false;
  private readonly drafts: Map<string, DesktopComposerDraft> = new Map<string, DesktopComposerDraft>();

  @State private groups: DesktopWorkspaceGroup[] = [];
  @State private sessionSummaries: SessionListItem[] = [];
  private selectedSubagent?: DesktopSubagentEntry;
  private readonly subagentAddresses: Map<string, DesktopSubagentEntry> = new Map();
  private data?: DesktopWorkspaceData;
  private fileSearchBook?: DesktopFileSearchPreferenceBook;
  private readonly fileNavigators = new DesktopFileNavigatorBook();
  private readonly documentViews = new Map<string, DesktopDocumentViewState>();
  private readonly closingDockTerminals = new Set<string>();
  private readonly pendingTerminalRenames = new Set<string>();
  private terminalRenameVersion: number = 0;
  @State private terminalRename?: DesktopTerminalRenameTarget = undefined;
  private dockTabContextSerial: number = 0;
  @State private dockTabContext?: DesktopDockTabContext = undefined;
  private readonly agentTerminals = new DesktopAgentTerminalInventory();
  private agentTerminalSession: string = '';
  private stopAgentTerminals?: () => void;
  private readonly replyMedia = new DesktopReplyMedia();
  @State private workbenchWidth: number = 440;
  @State private workbenchHeight: number = 640;
  private accountOpening: boolean = false;
  private accountClosePending: boolean = false;
  private accountKeyHandoff?: DesktopWorkspaceData;
  @State private accountDialog: number = -1;
  @State private accountDismissRequest: number = 0;
  @State private accountLauncherSignedIn: boolean = false;
  @State private accountLauncherName: string = '';
  @State private accountLauncherAvatar: string = '';
  private accountLauncherUid: string = '';
  private accountLauncherProfileRevision: number = -1;
  @State private accountNotices: DesktopAccountNotice[] = [];
  @State private accountSessionToasts: DesktopAccountSessionToast[] = [];
  private readonly accountSessionToastTimers = new Map<DesktopAccountSessionNotice, DesktopAccountSessionToastTimers>();
  private accountSessionToastToken: number = 0;
  @State private accountOnboarding: DesktopOnboardingView = emptyDesktopOnboardingView();
  @State @Watch('refreshSettingsSurface') private codingTools: DesktopCodingToolsSnapshot = emptyDesktopCodingToolsSnapshot();
  private onboardingBrowser?: DesktopWorkspaceData;
  private onboardingBrowserLeft: boolean = false;
  private onboardingBrowserTimer: number = -1;
  @State private accountNoticesWindowShown: boolean = true;
  private quotaNotice?: DesktopQuotaNotice;
  private quotaAccount = emptyDesktopAccountSettingsIdentity();
  private stopQuotaAccount?: () => void;
  private quotaDialogId: number = -1;
  private quotaDialogToken: number = -1;
  @State private quotaToastToken: number = -1;
  @State private quotaToastFading: boolean = false;
  private quotaFadeTimer: number = -1;
  private quotaToastTimer: number = -1;
  private quotaBrowserTimer: number = -1;
  private quotaBrowserVisit?: DesktopQuotaBrowserVisit;
  private pageActive: boolean = false;
  @State private pageVisible: boolean = false;
  private readingWindow?: window.Window;
  private readingFocused: boolean = false;
  // A zoom can rebuild the focused report while the modifier remains pressed in this window.
  private readonly timelineZoomKeys = new Set<number>();
  @State private timelineWheelModifier: boolean = false;
  private readonly readingWindowEvent = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_HIDDEN) {
      this.accountNoticesWindowShown = false;
    } else if (event === window.WindowEventType.WINDOW_SHOWN || event === window.WindowEventType.WINDOW_ACTIVE) {
      this.accountNoticesWindowShown = true;
    }
    if (event === window.WindowEventType.WINDOW_HIDDEN || event === window.WindowEventType.WINDOW_INACTIVE) {
      this.resetTimelineWheelModifier();
      this.noteQuotaBrowserFocus(false);
      this.noteOnboardingBrowserFocus(false);
    } else if (event === window.WindowEventType.WINDOW_ACTIVE) {
      this.noteQuotaBrowserFocus(true);
      this.noteOnboardingBrowserFocus(true);
      this.showQuotaSurface();
    }
    this.readingFocused = event === window.WindowEventType.WINDOW_ACTIVE ||
      (event === window.WindowEventType.WINDOW_SHOWN && this.readingWindow?.isFocused() === true);
    this.syncReading();
  };
  private measured: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.pageActive = true;
    this.pageVisible = true;
    this.attachReadingWindow();
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.appearance = desktopWorkspaceAppearance(context);
      const view = readDesktopSidebarView(context);
      this.sidebarGrouping = view.grouping;
      this.sidebarOrdering = view.ordering;
      this.archiveFilter = view.archiveFilter;
      this.manualOrders = view.orders;
      this.sidebarExpansionLoaded = view.expanded !== undefined;
      this.expandedIds = view.expanded ?? [];
    }
    this.onHostChanged();
  }

  private attachReadingWindow(): void {
    if (this.readingWindow !== undefined) { return; }
    const name = this.getUIContext().getWindowName();
    if (name !== undefined) {
      try {
        const owner = window.findWindow(name);
        owner.on('windowEvent', this.readingWindowEvent);
        this.readingWindow = owner;
        this.readingFocused = owner.isFocused();
        this.accountNoticesWindowShown = owner.isWindowShowing();
      } catch (_) {}
    }
  }

  aboutToDisappear(): void {
    this.replyMedia.release();
    this.active = false;
    this.pageActive = false;
    this.pageVisible = false;
    try { this.readingWindow?.off('windowEvent', this.readingWindowEvent); } catch (_) {}
    this.readingWindow = undefined;
    this.closeAccount();
    this.resetAccountSessionToasts();
    this.resetAccountOnboarding();
    this.resetQuota();
    this.closeSettings();
    this.closeLogDialog();
    this.closeFeedback();
    this.closeImagePreview();
    this.closeRename();
    this.closeArchiveConfirmation();
    this.dismissArchiveNotice();
    this.terminalRename = undefined;
    this.dockTabContext = undefined;
    this.clearAgentTerminalWatch();
    this.data?.stop();
    this.data = undefined;
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.noteQuotaBrowserFocus(true);
    this.noteOnboardingBrowserFocus(true);
    this.showQuotaSurface();
    this.reloadShortcutBindings();
    this.attachReadingWindow();
    this.syncReading();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.resetTimelineWheelModifier();
    this.noteQuotaBrowserFocus(false);
    this.noteOnboardingBrowserFocus(false);
    this.shortcutsOpen = false;
    this.clearSessionDrag();
    this.clearWorkspaceDrag();
    this.syncReading();
  }

  private resetTimelineWheelModifier(): void {
    this.timelineZoomKeys.clear();
    this.timelineWheelModifier = false;
  }

  private updateTimelineWheelModifier(event: KeyEvent): void {
    if (event.keyCode !== KeyCode.KEYCODE_CTRL_LEFT && event.keyCode !== KeyCode.KEYCODE_CTRL_RIGHT &&
      event.keyCode !== KeyCode.KEYCODE_META_LEFT && event.keyCode !== KeyCode.KEYCODE_META_RIGHT) { return; }
    if (event.type === KeyType.Down) { this.timelineZoomKeys.add(event.keyCode); }
    else { this.timelineZoomKeys.delete(event.keyCode); }
    this.timelineWheelModifier = this.timelineZoomKeys.size > 0;
  }

  private syncReading(): void {
    const chat = this.chat?.sessionId === this.sessionId ? this.chat : undefined;
    const visible = this.pageActive && this.pageVisible && !this.settingsOpen && !this.accountOnboarding.visible &&
      this.quotaDialogToken < 0 &&
      this.panel === 'session' &&
      this.readingFocused;
    this.data?.reading.show(this.sessionId, chat?.historyLoaded === true, chat?.receivedTurn ?? 0, visible);
  }

  private onPanelChanged(): void {
    if (this.panel !== 'session') {
      this.terminalRename = undefined;
      this.dockTabContext = undefined;
    }
    this.syncReading();
    this.syncAgentTerminalWatch();
  }

  private clearAgentTerminalWatch(): void {
    this.agentTerminalSession = '';
    this.stopAgentTerminals?.();
    this.stopAgentTerminals = undefined;
  }

  private syncAgentTerminalWatch(): void {
    const data = this.data;
    const session = this.pageActive && this.panel === 'session' && this.dockSessionId === this.sessionId ? this.sessionId : '';
    if (session === this.agentTerminalSession) { return; }
    this.clearAgentTerminalWatch();
    if (!session || data === undefined) { return; }
    this.agentTerminalSession = session;
    this.stopAgentTerminals = data.terminalRosters.watch(session, {
      items: (items: Object[]): void => {
        if (this.data !== data || this.agentTerminalSession !== session || this.sessionId !== session) { return; }
        const changes = this.agentTerminals.apply(session, items, desktopDockTerminalIds(this.rightDock));
        let layout = desktopDockProjectTerminals(this.rightDock, changes.metadata, changes.ended);
        for (const opened of changes.opened) {
          layout = desktopDockOpen(layout, desktopDockTerminalTab(opened.id, opened.title || '终端',
            opened.agentControlled, opened.sandboxMode), false);
        }
        this.setDock(layout);
      },
      problem: (_message: string): void => {}
    });
  }

  onBackPress(): boolean {
    if (this.accountDialog >= 0) { this.accountDismissRequest++; return true; }
    if (this.terminalRename !== undefined) { this.terminalRename = undefined; return true; }
    if (this.quotaDialogToken >= 0) { this.data?.dismissQuota(this.quotaDialogToken); return true; }
    if (this.settingsOpen) { this.closeSettings(); return true; }
    if (this.panel === 'session' && this.rightDock.focusedFloat) {
      const id = this.rightDock.focusedFloat;
      if (this.floatingPanel(id)?.tab.kind === DesktopDockKind.TERMINAL) { this.collapseFloatingTerminal(id); }
      else { this.closeDockTab(-1, id); }
      return true;
    }
    if (this.rightDock.expanded && this.sessionId && this.panel === 'session') {
      if (this.rightDock.fullscreen) { this.toggleDockFullscreen(); }
      else { this.toggleRightDock(); }
      return true;
    }
    if (this.panel !== 'session') {
      this.panel = 'session';
      return true;
    }
    return false;
  }

  private onHostChanged(): void {
    if (!this.pageActive) {
      return;
    }
    const host = desktopWorkspaceSelectionHost(this.hostUrl);
    this.dockTabContext = undefined;
    if (host && host !== this.selectionHost) {
      if (this.selectionHost) {
        this.nativeSelectionVersion++;
        this.sessionId = '';
        this.workspaceId = '';
      }
      this.selectionHost = host;
      this.savedSessionId = undefined;
    }
    this.closeAccount();
    this.resetAccountSessionToasts();
    this.resetAccountOnboarding();
    this.closeFeedback();
    this.closeImagePreview();
    this.closeArchiveConfirmation();
    this.dismissArchiveNotice();
    this.resetQuota();
    this.clearAgentTerminalWatch();
    this.agentTerminals.clear();
    this.data?.stop();
    this.data = undefined;
    this.selectedSubagent = undefined;
    this.accountLauncherSignedIn = false;
    this.accountLauncherName = '';
    this.accountLauncherAvatar = '';
    this.accountLauncherUid = '';
    this.accountLauncherProfileRevision = -1;
    this.subagentAddresses.clear();
    this.attachmentsBySession.clear();
    this.attachments = [];
    this.groups = [];
    this.codingTools = emptyDesktopCodingToolsSnapshot();
    this.visibleGroups = [];
    this.selectedWorkspaceTitle = '';
    this.selectedTitle = '';
    this.ready = false;
    this.error = '';
    this.chat = undefined;
    this.timelineBrowses.clear();
    this.timelineViewports.clear();
    this.timelineViewport = new DesktopTimelineViewport();
    this.timelineBrowse = emptyDesktopTimelineBrowse();
    this.resetTimelineLocation();
    this.timelinePreferencesReady = false;
    this.timelinePreferences = DEFAULT_DESKTOP_TIMELINE_PREFERENCES;
    this.interactions = [];
    this.unreadSessions = new Map<string, DesktopUnreadSession>();
    this.runningSidebarChildren = new Map<string, number>();
    this.sidebarPending = new Map<string, DesktopSidebarPending>();
    this.sidebarAttention = new Set<string>();
    this.sidebarWatermarks = new Map<string, number>();
    this.readingReady = false;
    this.archivedIds = [];
    this.shownPlanReviews.clear();
    this.docks.clear();
    this.documentViews.clear();
    this.fileNavigators.clear();
    this.closingDockTerminals.clear();
    this.pendingTerminalRenames.clear();
    this.terminalRename = undefined;
    this.dockSessionId = '';
    this.rightDock = emptyDesktopDock();
    this.clearDockGesture();
    this.clearWorkspaceDrag();
    this.terminalCreateRequest = undefined;
    this.chatError = '';
    this.creating = false;
    this.pendingNewSession = undefined;
    this.workspaceBusy = false;
    this.busySessions = [];
    this.stoppingSessions = [];
    if (this.hostUrl.length === 0) {
      return;
    }
    this.data = new DesktopWorkspaceData((snapshot: DesktopWorkspaceSnapshot): void => {
      this.error = snapshot.error;
      if (!snapshot.ready) {
        return;
      }
      const priorPins = new Set<string>(this.pinned);
      const newPins = this.ready ? snapshot.pinned.filter((id: string): boolean => !priorPins.has(id)) : [];
      this.archivedIds = snapshot.archivedIds;
      this.pinned = snapshot.pinned;
      this.runningSidebarChildren = desktopRunningSidebarChildren(snapshot.sessions, snapshot.unlistedRunning);
      this.collectSidebarAttention();
      this.updateGroups(snapshot.workspaces, snapshot.sessions, newPins);
      this.ready = true;
    }, (snapshot: DesktopConversationSnapshot): void => {
      const previous = this.chat?.sessionId === snapshot.sessionId ? this.chat?.timelineCommandOpen ?? 0 : 0;
      this.chat = snapshot;
      if (snapshot.sessionId === this.sessionId && snapshot.timelineCommandOpen > previous) {
        this.requestTimeline(snapshot.sessionId, '', '', true);
      } else {
        this.openPendingTimeline();
      }
      this.observeTimelineTree(snapshot);
      if (snapshot.subagent !== undefined) { this.subagentAddresses.set(snapshot.subagent.id, snapshot.subagent); }
      this.syncReading();
    }, (items: DesktopInteraction[]): void => {
      this.interactions = items;
      const review = items.find((row: DesktopInteraction): boolean =>
        row.sessionId === this.sessionId && row.planReview !== undefined && row.reviewHidden !== true);
      if (review?.planReview !== undefined && this.panel === 'session' && !this.shownPlanReviews.has(review.id)) {
        this.shownPlanReviews.add(review.id);
        this.showPlan(review.planReview.document);
      }
    }, (items: DesktopUnreadSession[], ready: boolean): void => {
      const unread = new Map<string, DesktopUnreadSession>();
      items.forEach((item: DesktopUnreadSession): void => { unread.set(item.id, item); });
      this.unreadSessions = unread;
      this.readingReady = ready;
      this.collectSidebarAttention();
      this.raiseSidebarWatermarks();
    }, (run: () => void): void => {
      this.getUIContext().postFrameCallback(new StartupFrameCallback(run));
    }, (pending: Map<string, DesktopSidebarPending>): void => {
      this.sidebarPending = pending;
      this.collectSidebarAttention();
      this.raiseSidebarWatermarks();
    }, (notices: DesktopAccountNotice[]): void => {
      if (this.pageActive) { this.accountNotices = notices; }
    }, (theme: DesktopTheme): void => {
      this.applyHostTheme(theme);
    }, (link: string): Promise<boolean> => {
      return this.pageActive ? openExternalUrl(link) : Promise.resolve(false);
    }, (message: ResourceStr): void => {
      if (this.pageActive) { this.getUIContext().getPromptAction().showToast({ message: message }); }
    }, (notice?: DesktopQuotaNotice): void => {
      if (this.pageActive) { this.presentQuota(notice); }
    }, (value: DesktopTimelinePreferences): void => {
      if (!this.pageActive) { return; }
      this.timelinePreferences = value;
      this.timelinePreferencesReady = true;
      this.openFirstTimelineTree();
    }, (view: DesktopOnboardingView): void => { this.showAccountOnboarding(view); },
    (state: DesktopCodingToolsSnapshot): void => { if (this.pageActive) { this.codingTools = state; } },
     (owner: DesktopWorkspaceData, notice: DesktopAccountSessionNotice): void => {
       this.showAccountSessionToast(owner, notice);
     },
    localDesktopQuestionDrafts(this.getUIContext().getHostContext()?.filesDir));
    const data = this.data;
    data.accountNotices.details.observe((snapshot: DesktopAccountDetailsSnapshot): void => {
      this.updateAccountLauncher(data, snapshot);
    });
    data.start(this.hostUrl).then((): void => { this.restoreTerminalHolds(data); });
  }

  private async restoreTerminalHolds(data: DesktopWorkspaceData): Promise<void> {
    if (!this.pageActive || this.data !== data) { return; }
    const holds = await readDesktopDockTerminalIds(this.getUIContext().getHostContext());
    if (!this.pageActive || this.data !== data) { return; }
    holds.forEach((ids: string[], sessionId: string): void => {
      if (!this.docks.has(sessionId)) { data.terminalRetentions.setTabs(sessionId, ids); }
    });
  }

  private applyHostTheme(theme: DesktopTheme): void {
    if (!this.pageActive) { return; }
    if (!sameDesktopTypography(this.typography, theme.typography)) { this.typography = theme.typography; }
    AppStorage.setOrCreate<string>('dshAppearanceMode', theme.appearance);
    if (this.appearance === theme.appearance) { return; }
    this.appearance = theme.appearance;
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      saveDesktopWorkspaceAppearance(context, theme.appearance).catch((): void => {});
    }
  }

  private workspaceColorMode(): ThemeColorMode {
    return this.appearance === 'dark' ? ThemeColorMode.DARK :
      this.appearance === 'light' ? ThemeColorMode.LIGHT : ThemeColorMode.SYSTEM;
  }

  private updateGroups(workspaces: DesktopWorkspaceRow[], sessions: SessionListItem[], newPins: string[]): void {
    this.sessionSummaries = sessions;
    const returned = readDesktopNativeDestination(this.nativeHandoff);
    this.nativeHandoff = '';
    const destination = returned?.host === this.hostUrl ? returned : undefined;
    const selection = destination?.preserveSession === true ? undefined : destination;
    const byMember = new Map<string, DesktopWorkspaceGroup>();
    const byPath = new Map<string, DesktopWorkspaceGroup>();
    this.groups = workspaces.map((row: DesktopWorkspaceRow): DesktopWorkspaceGroup => {
      const group: DesktopWorkspaceGroup = { id: row.id, path: row.path, title: row.title || row.path, sessions: [] };
      row.sessionIds.forEach((id: string): void => { byMember.set(id, group); });
      if (row.path.length > 0) {
        byPath.set(row.path, group);
      }
      return group;
    });
    const ungrouped: DesktopWorkspaceGroup = {
      id: '', path: '', title: $r('app.string.desktop_experiment_ungrouped'), sessions: []
    };
    for (const session of sessions) {
      const group = byMember.get(session.id) ?? byPath.get(session.cwd) ?? ungrouped;
      group.sessions.push(session);
      if (selection === undefined && session.id === this.sessionId && this.selectedSubagent === undefined &&
        !this.archivedIds.includes(session.id)) {
        this.selectSession(group, session);
      }
    }
    if (ungrouped.sessions.length > 0) {
      this.groups.push(ungrouped);
    }
    if (selection !== undefined) {
      this.restoreWebSelection(selection);
    } else if (this.archivedIds.includes(this.sessionId) || (this.selectedSubagent === undefined &&
      !sessions.some((session: SessionListItem): boolean => session.id === this.sessionId))) {
      this.clearSession(this.sessionId.length > 0);
      this.selectedWorkspaceTitle =
        this.groups.find((group: DesktopWorkspaceGroup): boolean => group.id === this.workspaceId)?.title ?? '';
    }
    if (!this.ready && destination === undefined && !this.sessionId) { this.restoreSavedSessionAfterFrame(); }
    if (!this.ready && !this.sidebarExpansionLoaded) {
      const first = this.groups.find((group: DesktopWorkspaceGroup): boolean => group.id === this.workspaceId) ??
        this.groups[0];
      this.expandedIds = first === undefined ? [] : [first.id];
    }
    if (this.sidebarOrdering === DesktopSessionOrdering.MANUAL) { this.reconcileSessionOrders(newPins); }
    this.filterGroups();
    if (this.pendingForkId && (this.sessionId !== this.pendingForkSource || this.panel !== 'session' ||
      this.openSessionById(this.pendingForkId, false))) {
      this.pendingForkId = '';
      this.pendingForkSource = '';
    }
    this.openPendingNewSession();
    if (destination?.plugin !== undefined) { this.openPlugins('', '', '', destination.plugin); }
  }

  private rememberSession(selection: string): void {
    if (!this.selectionHost || this.savedSessionId === selection) { return; }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) { return; }
    const host = this.selectionHost;
    this.savedSessionId = selection;
    saveDesktopWorkspaceSelection(context, host, selection).then((saved: boolean): void => {
      if (!saved && this.selectionHost === host && this.savedSessionId === selection) { this.savedSessionId = undefined; }
    });
  }

  private rememberChildSession(group: DesktopWorkspaceGroup, child: DesktopSubagentEntry): void {
    const children: DesktopSubagentEntry[] = [];
    const seen = new Set<string>();
    let entry: DesktopSubagentEntry | undefined = child;
    while (entry !== undefined && entry.mode !== 'external' && !seen.has(entry.id) && !seen.has(entry.parentId)) {
      children.push(entry);
      seen.add(entry.id);
      entry = this.subagentAddresses.get(entry.parentId);
    }
    if (children.length === 0) { return; }
    const selection: DesktopSavedChildSelection = { workspaceId: group.id, children: children };
    this.rememberSession(JSON.stringify(selection));
  }

  private restoreSavedSessionAfterFrame(): void {
    const owner = this.data;
    const host = this.selectionHost;
    const version = this.nativeSelectionVersion;
    if (owner === undefined || !host) { return; }
    const stillSelected = (): boolean => this.pageActive && this.ready && this.data === owner &&
      this.selectionHost === host && !this.sessionId && this.nativeSelectionVersion === version &&
      this.panel === 'session' && !this.switching && !this.creating && !this.workspaceBusy &&
      !this.searchOpen && !this.settingsOpen && this.accountDialog < 0;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      if (!stillSelected()) { return; }
      const context = this.getUIContext().getHostContext();
      if (context === undefined) { return; }
      const saved = readDesktopWorkspaceSelection(context, host);
      this.savedSessionId = saved;
      if (!saved) { return; }
      const child = readDesktopSavedChildSelection(saved);
      if (child !== undefined) {
        if (!this.restoreSavedChild(child)) { this.rememberSession(''); }
        return;
      }
      const row = this.sessionSummaries.find((session: SessionListItem): boolean => session.id === saved);
      if (row === undefined || this.archivedIds.includes(saved)) { this.rememberSession(''); return; }
      const blankWorkspace = row.blank ? owner.savedBlankWorkspace(row.id, row.cwd) : '';
      if (blankWorkspace) {
        owner.restoreBlankSession(blankWorkspace, saved, stillSelected).then((result: DesktopSessionCreation): void => {
          if (!stillSelected()) { return; }
          if (result.id) { this.openSessionById(result.id, false); }
          else if (result.problem) { this.getUIContext().getPromptAction().showToast({ message: result.problem }); }
        }).catch((): void => {});
      } else if (!this.openSessionById(saved, false)) { this.rememberSession(''); }
    }));
  }

  private restoreSavedChild(saved: DesktopSavedChildSelection): boolean {
    const child = saved.children[0];
    const root = saved.children[saved.children.length - 1].parentId;
    if (this.archivedIds.includes(root) || saved.children.some((row: DesktopSubagentEntry): boolean =>
      this.archivedIds.includes(row.id))) { return false; }
    const group = this.groups.find((candidate: DesktopWorkspaceGroup): boolean =>
      candidate.sessions.some((row: SessionListItem): boolean => row.id === root)) ??
      this.groups.find((candidate: DesktopWorkspaceGroup): boolean => candidate.id === saved.workspaceId);
    if (group === undefined) { return false; }
    for (const entry of saved.children) { this.subagentAddresses.set(entry.id, entry); }
    const rootSession = group.sessions.find((row: SessionListItem): boolean => row.id === root);
    const summary = this.sessionSummaries.find((row: SessionListItem): boolean => row.id === child.id);
    const session: SessionListItem = summary ?? { id: child.id, title: child.label || child.name,
      cwd: rootSession?.cwd ?? group.path, createdAt: child.createdAt, updatedAt: 0, running: false, blank: false, raw: '' };
    this.selectSession(group, session, child);
    this.revealWorkspace(group.id);
    this.revealSidebarSession(group.id, root);
    return true;
  }

  private restoreWebSelection(destination: DesktopNativeDestination): void {
    if (!destination.parentId && destination.sessionId && this.openSessionById(destination.sessionId, false)) { return; }
    this.clearSession(!destination.parentId);
    this.selectedWorkspaceTitle =
      this.groups.find((group: DesktopWorkspaceGroup): boolean => group.id === this.workspaceId)?.title ?? '';
    if (destination.parentId) {
      this.restoreWebSubagent(destination);
    } else if (destination.sessionId) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_experiment_open_failed') });
    }
  }

  private isRestoringWebPlugin(location?: DesktopPluginLocation): boolean {
    return this.panel === 'plugins' && location !== undefined && this.pluginLocation.kind === location.kind &&
      this.pluginLocation.name === location.name && this.pluginLocation.rowId === location.rowId;
  }

  private async restoreWebSubagent(destination: DesktopNativeDestination): Promise<void> {
    const owner = this.data;
    const parentId = destination.parentId;
    const childId = destination.sessionId;
    const selection = this.nativeSelectionVersion;
    const context = this.getUIContext().getHostContext();
    const remembered = context === undefined || !this.selectionHost ? undefined :
      readDesktopSavedChildSelection(readDesktopWorkspaceSelection(context, this.selectionHost));
    const ancestors = this.webSubagentAncestors(destination, remembered);
    const root = ancestors.length > 0 ? ancestors[ancestors.length - 1].parentId : parentId;
    const archived = (): boolean => this.archivedIds.includes(root) || this.archivedIds.includes(childId) ||
      ancestors.some((entry: DesktopSubagentEntry): boolean => this.archivedIds.includes(entry.id));
    const accepts = (entry?: DesktopSubagentEntry): boolean => entry !== undefined &&
      entry.parentId === parentId && entry.id === childId && entry.mode !== 'external' &&
      (destination.mode === 'unknown' || entry.mode === destination.mode);
    const findGroup = (): DesktopWorkspaceGroup | undefined => this.groups.find((candidate: DesktopWorkspaceGroup): boolean =>
      candidate.sessions.some((session: SessionListItem): boolean => session.id === root));
    const summary = this.sessionSummaries.find((item: SessionListItem): boolean => item.id === childId);
    const listed = summary === undefined ? undefined : desktopSubagentFromSummary(summary);
    let entry = accepts(listed) ? listed : remembered?.children.find((item: DesktopSubagentEntry): boolean => accepts(item));
    if (owner !== undefined && findGroup() !== undefined && !archived() && !accepts(entry)) {
      const result = await owner.actions.call('session/projections', { 'sessionId': parentId });
      if (!this.pageActive || this.data !== owner || this.hostUrl !== destination.host ||
        selection !== this.nativeSelectionVersion || (this.panel !== 'session' &&
          !this.isRestoringWebPlugin(destination.plugin))) { return; }
      const children = result.ok ? desktopSubagentCatalog(parentId, getRecord(result.value, 'values')) : undefined;
      entry = children?.find((child: DesktopSubagentEntry): boolean => accepts(child));
      if (entry === undefined && children === undefined && ancestors.length > 0) {
        // A one-shot parent can be unlisted. The addressed follow validates the selected child on the Host.
        entry = { id: childId, parentId: parentId, mode: destination.mode,
          name: childId, label: summary?.title ?? '', createdAt: summary?.createdAt ?? 0 };
      }
    }
    const group = findGroup();
    if (group === undefined || archived() || entry === undefined || !accepts(entry) ||
      !this.restoreSavedChild({ workspaceId: group.id, children: [entry, ...ancestors] })) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_experiment_open_failed') });
      return;
    }
  }

  private webSubagentAncestors(destination: DesktopNativeDestination,
    remembered?: DesktopSavedChildSelection): DesktopSubagentEntry[] {
    const ancestors: DesktopSubagentEntry[] = [];
    const visited = new Set<string>([destination.sessionId]);
    let id = destination.parentId;
    while (id && !visited.has(id)) {
      visited.add(id);
      const summary = this.sessionSummaries.find((row: SessionListItem): boolean => row.id === id);
      const listed = summary === undefined ? undefined : desktopSubagentFromSummary(summary);
      const saved = remembered?.children.find((entry: DesktopSubagentEntry): boolean => entry.id === id);
      const address = destination.ancestors?.find((entry: DesktopHandoffSubagent): boolean => entry.childSessionId === id);
      const known = saved ?? listed;
      const entry: DesktopSubagentEntry | undefined = address === undefined ? known :
        { id: id, parentId: address.parentSessionId, mode: address.mode, name: known?.name ?? id,
          label: known?.label || summary?.title || '', createdAt: known?.createdAt ?? summary?.createdAt ?? 0 };
      if (entry === undefined || entry.mode === 'external' || visited.has(entry.parentId)) { break; }
      ancestors.push(entry);
      id = entry.parentId;
    }
    return ancestors;
  }

  private showRename(id: string, workspace: boolean, title: ResourceStr): void {
    if (this.renameOpen || this.workspaceBusy) { return; }
    this.renameId = id;
    this.renameWorkspace = workspace;
    this.renameDraft = this.accessibilityLabel(title);
    this.renameOpen = true;
    this.openRename();
  }

  private async openRename(): Promise<void> {
    const version = ++this.renameDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.RenameDialog(); },
        alignment: DialogAlignment.Center, width: Math.max(220, Math.min(440, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.renameDialogVersion) {
            this.renameDialog = -1;
            this.renameOpen = false;
            this.renameDialogVersion++;
          }
        } });
      if (this.pageActive && version === this.renameDialogVersion) { this.renameDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.renameDialogVersion) { this.renameOpen = false; }
    }
  }

  private closeRename(): void {
    const id = this.renameDialog;
    this.renameDialogVersion++;
    this.renameDialog = -1;
    this.renameOpen = false;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private async rename(): Promise<void> {
    const title = this.renameDraft.trim();
    if (!title || this.workspaceBusy) {
      return;
    }
    const id = this.renameId;
    const workspace = this.renameWorkspace;
    const version = this.renameDialogVersion;
    if (await this.manage(workspace ? 'workspace/rename' : 'session/rename', workspace ?
      { 'workspaceId': id, 'title': title } : { 'sessionId': id, 'title': title })) {
      if (version === this.renameDialogVersion) { this.closeRename(); }
    }
  }

  private async manage(endpoint: string, payload: Record<string, Object>): Promise<boolean> {
    const data = this.data;
    if (data === undefined || this.workspaceBusy) {
      return false;
    }
    this.workspaceBusy = true;
    const problem = await data.manage(endpoint, payload);
    if (this.data !== data) {
      return false;
    }
    this.workspaceBusy = false;
    if (problem.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message: problem });
      return false;
    }
    return true;
  }

  private workspaceActions(group: DesktopWorkspaceGroup): MenuElement[] {
    return [
      { value: '重命名工作区', action: (): void => { this.showRename(group.id, true, group.title); } },
      { value: '移除工作区', action: (): void => {
        this.getUIContext().getPromptAction().showDialog({
          title: '移除工作区',
          message: '仅移除工作区登记，会话与目录文件会保留。',
          buttons: [{ text: '取消', color: '#777777' }, { text: '移除', color: '#B73535' }]
        }).then((result): void => {
          if (result.index === 1 && this.pageActive) {
            this.manage('workspace/delete', { 'workspaceId': group.id });
          }
        }).catch((): void => {});
      } }
    ];
  }

  private sessionActions(session: SessionListItem): MenuElement[] {
    if (this.archivedIds.includes(session.id)) {
      return [
        { value: '复制 Session ID', icon: $r('app.media.dsh_session_copy'),
          action: (): void => { this.copySessionId(session.id); } },
        { value: '取消归档', icon: $r('app.media.dsh_session_unarchive_outline'),
          action: (): void => { this.restoreSession(session.id); } }
      ];
    }
    const pinned = this.pinned.includes(session.id);
    const unread = this.unreadSession(session.id) !== undefined;
    return [
      { value: '在右侧打开', icon: $r('app.media.sidebar_toggle'), enabled: !!this.sessionId && session.id !== this.sessionId,
        action: (): void => { this.showDockChat({ id: session.id, subagent: desktopSubagentFromSummary(session) }, session.title); } },
      { value: pinned ? '取消置顶' : '置顶会话',
        icon: pinned ? $r('app.media.dsh_session_pin_fill') : $r('app.media.dsh_session_pin_outline'), action: (): void => {
        this.manage(pinned ? 'workspace/unpinSession' : 'workspace/pinSession', { 'sessionId': session.id });
      } },
      { value: '重命名会话', icon: $r('app.media.dsh_dock_edit'),
        action: (): void => { this.showRename(session.id, false, this.sessionLabel(session)); } },
      { value: unread ? '标为已读' : '标为未读', enabled: this.readingReady,
        icon: unread ? $r('app.media.dsh_session_mail_read_outline') : $r('app.media.dsh_session_mail_unread_outline'),
        action: (): void => { this.markReading(session.id); } },
      { value: '分叉会话', icon: $r('app.media.dsh_session_branch_outline'),
        action: (): void => { this.forkFrom(session.id); } },
      { value: '复制 Session ID', icon: $r('app.media.dsh_session_copy'),
        action: (): void => { this.copySessionId(session.id); } },
      { value: '归档会话', icon: $r('app.media.dsh_session_archive_outline'),
        action: (): void => { this.archiveSession(session.id, this.accessibilityLabel(this.sessionLabel(session))); } }
    ];
  }

  private async archiveSession(id: string, title: string, stop: boolean = false): Promise<void> {
    const data = this.data;
    if (data === undefined || this.workspaceBusy || (stop ? this.archiveRequest?.id !== id :
      this.archiveRequest !== undefined)) { return; }
    this.workspaceBusy = true;
    this.archiveProblem = '';
    const body: Record<string, Object> = { 'sessionId': id };
    if (stop) { body['stopActivity'] = true; }
    const result = await data.actions.call(WORKSPACE_ARCHIVE_SESSION_ENDPOINT, body);
    if (this.data !== data || !this.pageActive) { return; }
    this.workspaceBusy = false;
    if (result.ok) {
      this.closeArchiveConfirmation();
      this.showArchiveNotice(id, stop);
    } else if (!stop && result.error?.code === 'workspace/session-active') {
      this.archiveRequest = { id: id, title: title, activity: desktopArchiveActivity(result.error.details, id) };
      this.openArchiveConfirmation();
    } else {
      const problem = result.error?.message || '无法归档会话，请重试';
      if (stop) { this.archiveProblem = problem; }
      else { this.getUIContext().getPromptAction().showToast({ message: problem }); }
    }
  }

  @Builder
  private ArchiveConfirmationContent(request: DesktopArchiveRequest) {
    DesktopArchiveDialog({ title: request.title, activity: request.activity, busy: this.workspaceBusy,
      problem: this.archiveProblem, onClose: (): void => { this.closeArchiveConfirmation(); },
      onConfirm: (): void => { this.archiveSession(request.id, request.title, true); } })
  }

  private async openArchiveConfirmation(): Promise<void> {
    const request = this.archiveRequest;
    if (request === undefined) { return; }
    const version = ++this.archiveDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.ArchiveConfirmationContent(request); },
        alignment: DialogAlignment.Center,
        width: Math.max(220, Math.min(496, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onWillDismiss: (action): void => { if (!this.workspaceBusy) { action.dismiss(); } },
        onDidDisappear: (): void => {
          if (version === this.archiveDialogVersion) {
            this.archiveDialog = -1;
            this.archiveRequest = undefined;
            this.archiveDialogVersion++;
          }
        }
      });
      if (this.pageActive && version === this.archiveDialogVersion) { this.archiveDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.archiveDialogVersion) {
        this.archiveRequest = undefined;
        prompt.showToast({ message: '无法打开归档确认，请重试' });
      }
    }
  }

  private closeArchiveConfirmation(): void {
    const dialog = this.archiveDialog;
    this.archiveDialog = -1;
    this.archiveDialogVersion++;
    this.archiveRequest = undefined;
    this.archiveProblem = '';
    if (dialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(dialog); }
  }

  private async restoreSession(id: string): Promise<void> {
    if (await this.manage('workspace/unarchiveSession', { 'sessionId': id })) {
      if (this.archiveNotice?.id === id) { this.dismissArchiveNotice(); }
    }
  }

  private setArchiveFilter(filter: DesktopArchiveFilter, sessionId: string = ''): void {
    this.sidebarCollapsed = false;
    this.archiveFilter = filter;
    const group = sessionId ? this.groups.find((item: DesktopWorkspaceGroup): boolean =>
      item.sessions.some((row: SessionListItem): boolean => row.id === sessionId)) : undefined;
    if (group !== undefined) { this.revealWorkspace(group.id); }
    this.filterGroups();
    this.saveSidebarView();
  }

  private saveSidebarView(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) { return; }
    this.sidebarExpansionLoaded = true;
    saveDesktopSidebarView(context, { grouping: this.sidebarGrouping, ordering: this.sidebarOrdering,
      archiveFilter: this.archiveFilter, expanded: this.expandedIds, orders: this.manualOrders });
  }

  private setSidebarGrouping(grouping: DesktopSessionGrouping): void {
    if (grouping === this.sidebarGrouping) { return; }
    this.clearSessionDrag();
    this.clearWorkspaceDrag();
    this.sidebarGrouping = grouping;
    this.sidebarWatermarks = new Map<string, number>();
    this.filterGroups();
    this.saveSidebarView();
  }

  private setSidebarOrdering(ordering: DesktopSessionOrdering): void {
    if (ordering === this.sidebarOrdering) { return; }
    this.manualOrders = ordering === DesktopSessionOrdering.MANUAL ? this.snapshotSessionOrders() : new Map<string, string[]>();
    this.sidebarOrdering = ordering;
    this.filterGroups();
    this.saveSidebarView();
  }

  private showArchiveNotice(id: string, stopped: boolean): void {
    this.archiveNotice = { id: id, stopped: stopped };
    this.pauseArchiveNotice(false);
  }

  private pauseArchiveNotice(paused: boolean): void {
    if (this.archiveNoticeTimer !== -1) {
      clearTimeout(this.archiveNoticeTimer);
      this.archiveNoticeTimer = -1;
    }
    if (!paused && this.archiveNotice !== undefined) {
      this.archiveNoticeTimer = setTimeout((): void => { this.dismissArchiveNotice(); }, 6000);
    }
  }

  private dismissArchiveNotice(): void {
    this.pauseArchiveNotice(true);
    this.archiveNotice = undefined;
  }

  @Builder
  private ArchiveNoticeContent(notice: DesktopArchiveNotice) {
    Row({ space: 5 }) {
      Text(notice.stopped ? '已停止并归档，可' : '会话已归档，可')
        .key('desktopArchiveNoticeText').fontSize(13).fontColor($r('sys.color.font_primary'))
      Button('撤销', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopArchiveUndo')
        .height(30).padding({ left: 5, right: 5 }).enabled(!this.workspaceBusy)
        .onFocus((): void => this.pauseArchiveNotice(true)).onBlur((): void => this.pauseArchiveNotice(false))
        .onClick((): void => { this.restoreSession(notice.id); })
      if (this.archiveFilter === DesktopArchiveFilter.HIDE) {
        Text('或').fontSize(13).fontColor($r('sys.color.font_primary'))
        Button('筛选已归档会话', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopArchiveNoticeFilter')
          .height(30).padding({ left: 5, right: 5 })
          .onFocus((): void => this.pauseArchiveNotice(true)).onBlur((): void => this.pauseArchiveNotice(false))
          .onClick((): void => {
            this.setArchiveFilter(DesktopArchiveFilter.ALL, notice.id);
            this.dismissArchiveNotice();
          })
      }
    }.padding({ left: 14, right: 10, top: 4, bottom: 4 }).constraintSize({ maxWidth: '95%' })
      .borderRadius(14).margin({ bottom: 28 })
      .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : undefined)
      .systemMaterial(controlMaterial()).shadow({ radius: 14, color: '#26000000', offsetY: 4 })
      .onHover((hovered: boolean): void => this.pauseArchiveNotice(hovered))
  }

  private unreadSession(sessionId: string): DesktopUnreadSession | undefined {
    return this.unreadSessions.get(sessionId);
  }

  private async markReading(sessionId: string): Promise<void> {
    const data = this.data;
    if (data === undefined) { return; }
    const problem = await data.reading.mark(sessionId);
    if (problem && this.data === data && this.pageActive) {
      this.getUIContext().getPromptAction().showToast({ message: problem });
    }
  }

  private async copySessionId(sessionId: string): Promise<void> {
    const copied = await copyText(sessionId);
    if (this.pageActive) {
      this.getUIContext().getPromptAction().showToast({ message: copied ? 'Session ID 已复制' : '复制失败，请重试' });
    }
  }

  private focusSearch(): void {
    this.sidebarCollapsed = false;
    this.searchOpen = true;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      if (this.pageActive && this.searchOpen) {
        this.getUIContext().getFocusController().requestFocus('desktopWorkspaceSearch');
      }
    }));
  }

  private closeSearch(): void {
    this.query = '';
    this.searchOpen = false;
  }

  private openSearchResult(id: string): void {
    if (this.openSessionById(id)) { this.closeSearch(); }
  }

  private reloadShortcutBindings(): void {
    const prefs = readDesktopShortcuts(this.getUIContext().getHostContext());
    this.shortcutBindings = desktopShortcutRows(prefs.overrides);
  }

  private workspaceShortcut(key: DesktopShortcut): boolean {
    if (!this.pageActive || !this.pageVisible || this.settingsOpen || this.shortcutsOpen || this.renameOpen || this.accountOpening ||
      this.accountDialog >= 0 || this.openingFeedback || this.feedbackDialog >= 0 || this.logDialog >= 0 ||
      this.archiveRequest !== undefined || this.imageDialog >= 0 || this.imageDialogOpening ||
      this.terminalRename !== undefined) { return false; }
    if (key === DesktopShortcut.REFERENCE) { this.shortcutsOpen = true; return true; }
    if (key === DesktopShortcut.NEW_SESSION) { this.newSession(); return true; }
    if (key === DesktopShortcut.LEFT_SIDEBAR) { this.sidebarCollapsed = !this.sidebarCollapsed; return true; }
    if (key === DesktopShortcut.SEARCH) { this.focusSearch(); return true; }
    if (key === DesktopShortcut.ADD_WORKSPACE) { this.addWorkspace(); return true; }
    if (key === DesktopShortcut.SETTINGS) { this.openSettings(); return true; }
    if (this.panel !== 'session' || !this.sessionId) { return false; }
    if (key === DesktopShortcut.RIGHT_SIDEBAR) { this.toggleRightDock(); return true; }
    if (key === DesktopShortcut.SPLIT_DOCK && !this.rightDock.focusedFloat && this.rightDock.expanded && this.canSplitDock()) {
      this.splitDock(); return true;
    }
    if (key === DesktopShortcut.CLOSE_DOCK_TAB && this.rightDock.focusedFloat) {
      this.closeDockTab(-1, this.rightDock.focusedFloat); return true;
    }
    if (key === DesktopShortcut.CLOSE_DOCK_TAB && this.rightDock.expanded) {
      const tab = desktopDockTab(this.rightDock);
      if (tab !== undefined) { this.closeDockTab(this.rightDock.focus, tab.id); return true; }
    }
    if (key === DesktopShortcut.FILES) { this.showWorkspaceFiles(); return true; }
    if (key === DesktopShortcut.NEW_TERMINAL) { this.showTerminal(true); return true; }
    if (key === DesktopShortcut.NEW_BROWSER) { this.openBrowser(this.rightDock.focus); return true; }
    const session = this.groups.find((group: DesktopWorkspaceGroup): boolean =>
      group.id === this.workspaceId)?.sessions.find((row: SessionListItem): boolean => row.id === this.sessionId);
    if (session === undefined || this.archivedIds.includes(session.id)) { return false; }
    if (key === DesktopShortcut.ARCHIVE) {
      this.archiveSession(session.id, this.accessibilityLabel(this.sessionLabel(session)));
      return true;
    }
    if (session.blank) { return false; }
    const detailOpen = this.rightDock.expanded || this.rightDock.floats.length > 0;
    if (key === DesktopShortcut.FORK) {
      this.forkFrom(session.id);
    } else if (key === DesktopShortcut.RENAME && !detailOpen) {
      this.showRename(session.id, false, this.sessionLabel(session));
    } else if (key === DesktopShortcut.TOGGLE_READ && !detailOpen && this.readingReady) {
      this.markReading(session.id);
    } else {
      return false;
    }
    return true;
  }

  private terminalShortcut(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    const key = desktopShortcutFromEvent(event);
    if (!key.ctrl && !key.alt) { return false; }
    const row = this.shortcutBindings.find((item: DesktopShortcutRow): boolean => !item.occupiedBy &&
      desktopShortcutEqual(item.binding, key));
    return row !== undefined && [DesktopShortcut.REFERENCE, DesktopShortcut.SETTINGS, DesktopShortcut.FILES,
      DesktopShortcut.NEW_TERMINAL, DesktopShortcut.NEW_BROWSER, DesktopShortcut.RIGHT_SIDEBAR, DesktopShortcut.SPLIT_DOCK,
      DesktopShortcut.CLOSE_DOCK_TAB].includes(row.id) && this.workspaceShortcut(row.id);
  }

  private eligibleSidebarSessions(sessions: SessionListItem[]): SessionListItem[] {
    return sessions.filter((row: SessionListItem): boolean => getString(row.raw, 'origin') !== 'subagent' &&
      (!row.blank || row.id === this.sessionId));
  }

  private orderedSidebarSessions(sessions: SessionListItem[], account: string, archived: Set<string>,
    sectioned: boolean = false): SessionListItem[] {
    const saved = this.sidebarOrdering === DesktopSessionOrdering.MANUAL ? this.manualOrders.get(account) ?? [] : undefined;
    return sectioned ? desktopSessionRows(sessions, saved, this.pinned, archived, this.sessionId) :
      desktopSessionOrder(sessions, saved, this.pinned, archived, this.sessionId);
  }

  private snapshotSessionOrders(): Map<string, string[]> {
    const orders = new Map<string, string[]>();
    const archived = new Set<string>(this.archivedIds);
    for (const group of this.groups) {
      const account = desktopSessionAccount(DesktopSessionGrouping.WORKSPACE, group.id);
      const members = this.eligibleSidebarSessions(group.sessions);
      orders.set(account, this.orderedSidebarSessions(members, account, archived).map((row: SessionListItem): string => row.id));
    }
    const flat = desktopSessionAccount(DesktopSessionGrouping.FLAT, '');
    const visible = this.eligibleSidebarSessions(this.sessionSummaries);
    orders.set(flat, this.orderedSidebarSessions(visible, flat, archived).map((row: SessionListItem): string => row.id));
    return orders;
  }

  private reconcileSessionOrders(newPins: string[]): void {
    const orders = this.snapshotSessionOrders();
    if (newPins.length > 0) {
      const pinned = new Set<string>(newPins);
      orders.forEach((rows: string[], account: string): void => {
        const members = new Set<string>(rows);
        const leading = newPins.filter((id: string): boolean => members.has(id));
        orders.set(account, leading.concat(rows.filter((id: string): boolean => !pinned.has(id))));
      });
    }
    if (!desktopSessionOrdersEqual(this.manualOrders, orders)) {
      this.manualOrders = orders;
      this.saveSidebarView();
    }
  }

  private filterGroups(): void {
    const archived = new Set<string>(this.archivedIds);
    const matches: DesktopWorkspaceGroup[] = [];
    const flat = this.sidebarGrouping === DesktopSessionGrouping.FLAT;
    const single: DesktopWorkspaceGroup = { id: '', path: '', title: $r('app.string.desktop_sidebar_sessions'),
      sessions: this.sessionSummaries };
    const groups = flat ? [single] : this.groups;
    for (const group of groups) {
      const account = desktopSessionAccount(this.sidebarGrouping, group.id);
      const visible = this.eligibleSidebarSessions(group.sessions).filter((row: SessionListItem): boolean => {
        const isArchived = archived.has(row.id);
        return (this.archiveFilter === DesktopArchiveFilter.ALL ||
          isArchived === (this.archiveFilter === DesktopArchiveFilter.ONLY));
      });
      if (visible.length > 0 || (this.archiveFilter !== DesktopArchiveFilter.ONLY && group.id)) {
        const sessions = this.orderedSidebarSessions(visible, account, archived, true);
        matches.push({ id: group.id, path: group.path, title: group.title, sessions: sessions });
      }
    }
    this.visibleGroups = matches;
    this.raiseSidebarWatermarks();
  }

  private collectSidebarAttention(): void {
    const attention = new Set<string>();
    this.sidebarPending.forEach((_, id: string): void => { attention.add(id); });
    this.runningSidebarChildren.forEach((_, id: string): void => { attention.add(id); });
    this.unreadSessions.forEach((_, id: string): void => { attention.add(id); });
    if (attention.size !== this.sidebarAttention.size || Array.from(attention).some((id: string): boolean =>
      !this.sidebarAttention.has(id))) { this.sidebarAttention = attention; }
  }

  private sidebarHasOverflow(): boolean {
    return this.sidebarGrouping !== DesktopSessionGrouping.FLAT && !this.query.trim();
  }

  private sidebarRequired(group: DesktopWorkspaceGroup): number {
    return desktopSidebarRequired(group.sessions, this.panel === 'session' ? this.sessionId : '', this.sidebarAttention);
  }

  private raiseSidebarWatermarks(): void {
    if (!this.sidebarHasOverflow()) { return; }
    let raised: Map<string, number> | undefined;
    for (const section of this.sidebarSections()) {
      if (section.header) { continue; }
      const group = section.group;
      const needed = this.sidebarRequired(group);
      if (needed <= (this.sidebarWatermarks.get(group.id) ?? SIDEBAR_SESSION_PAGE)) { continue; }
      raised = raised ?? new Map<string, number>(this.sidebarWatermarks);
      raised.set(group.id, needed);
    }
    if (raised !== undefined) { this.sidebarWatermarks = raised; }
  }

  private sidebarLimit(group: DesktopWorkspaceGroup): number {
    return Math.max(this.sidebarRequired(group), this.sidebarWatermarks.get(group.id) ?? SIDEBAR_SESSION_PAGE);
  }

  private visibleSidebarSessions(group: DesktopWorkspaceGroup): SessionListItem[] {
    return this.sidebarHasOverflow() ? desktopSidebarRows(group.sessions, this.sidebarLimit(group)) : group.sessions;
  }

  private sidebarHiddenCount(group: DesktopWorkspaceGroup): number {
    return group.sessions.length - this.visibleSidebarSessions(group).length;
  }

  private showSidebarOverflow(group: DesktopWorkspaceGroup): boolean {
    return this.sidebarHasOverflow() &&
      desktopSidebarRows(group.sessions, this.sidebarRequired(group)).length < group.sessions.length;
  }

  private toggleSidebarOverflow(group: DesktopWorkspaceGroup): void {
    const marks = new Map<string, number>(this.sidebarWatermarks);
    const hidden = this.sidebarHiddenCount(group);
    if (hidden === 0) { marks.delete(group.id); }
    else { marks.set(group.id, this.sidebarLimit(group) + SIDEBAR_SESSION_PAGE); }
    this.sidebarWatermarks = marks;
  }

  private revealSidebarSession(groupId: string, sessionId: string): void {
    if (!this.sidebarHasOverflow()) { return; }
    const group = this.visibleGroups.find((row: DesktopWorkspaceGroup): boolean => row.id === groupId);
    if (group === undefined) { return; }
    const needed = desktopSidebarRevealDepth(group.sessions, sessionId);
    if (needed > this.sidebarLimit(group)) {
      const marks = new Map<string, number>(this.sidebarWatermarks);
      marks.set(groupId, needed);
      this.sidebarWatermarks = marks;
    }
    this.raiseSidebarWatermarks();
  }

  private forgetSidebarWatermarks(id: string): void {
    const marks = new Map<string, number>(this.sidebarWatermarks);
    const parents = this.sidebarGrouping === DesktopSessionGrouping.TREE ? desktopWorkspaceParents(this.groups) : undefined;
    for (const key of this.sidebarWatermarks.keys()) {
      for (let owner: string | undefined = key; owner !== undefined; owner = parents?.get(owner)) {
        if (owner === id) {
          marks.delete(key);
          break;
        }
      }
    }
    if (marks.size !== this.sidebarWatermarks.size) { this.sidebarWatermarks = marks; }
  }

  private sidebarSections(): DesktopSidebarSection[] {
    return desktopSidebarSections(this.visibleGroups, this.sidebarGrouping, this.expandedIds, !!this.query.trim());
  }

  private revealWorkspace(id: string): void {
    const parents = this.sidebarGrouping === DesktopSessionGrouping.TREE ? desktopWorkspaceParents(this.groups) : undefined;
    const expanded = new Set<string>(this.expandedIds);
    for (let current: string | undefined = id; current !== undefined; current = parents?.get(current)) {
      expanded.add(current);
    }
    if (expanded.size !== this.expandedIds.length) { this.expandedIds = Array.from(expanded); }
  }

  private isExpanded(id: string): boolean {
    return this.query.trim().length > 0 || this.expandedIds.includes(id);
  }

  private toggleWorkspace(id: string): void {
    if (this.expandedIds.includes(id)) {
      this.expandedIds = this.expandedIds.filter((item: string): boolean => item !== id);
      this.forgetSidebarWatermarks(id);
    } else {
      this.expandedIds = [...this.expandedIds, id];
      this.raiseSidebarWatermarks();
    }
    this.saveSidebarView();
  }

  private sessionLabel(session: SessionListItem): ResourceStr {
    return session.title || $r('app.string.desktop_experiment_unnamed');
  }

  private selectSession(group: DesktopWorkspaceGroup, session: SessionListItem,
    subagent: DesktopSubagentEntry | undefined = desktopSubagentFromSummary(session)): void {
    this.landingPreset = '';
    if (this.dockSessionId !== session.id) {
      this.dockSessionId = session.id;
      this.dockTabContext = undefined;
      this.clearDockGesture();
      this.rightDock = this.docks.get(session.id) ?? readDesktopDock(this.getUIContext().getHostContext(), session.id);
      this.docks.set(session.id, this.rightDock);
      this.data?.terminalRetentions.setTabs(session.id, desktopDockTerminalIds(this.rightDock));
    }
    const changing = this.sessionId !== session.id;
    if (changing) {
      this.nativeSelectionVersion++;
      this.terminalRename = undefined;
      this.terminalCreateRequest = undefined;
      this.referenceOffer = undefined;
      this.closeFeedback();
      this.closeImagePreview();
      this.draft = this.drafts.get(session.id) ?? EMPTY_DESKTOP_DRAFT;
      this.attachments = this.attachmentsBySession.get(session.id) ?? [];
      this.chatError = '';
    }
    if (changing) {
      this.resetTimelineLocation();
      this.timelineBrowse = this.timelineBrowses.get(session.id) ?? emptyDesktopTimelineBrowse();
      this.timelineViewport = this.timelineViewports.get(session.id) ?? new DesktopTimelineViewport();
      this.timelineViewports.set(session.id, this.timelineViewport);
    }
    this.sessionId = session.id;
    this.selectedSubagent = subagent;
    if (subagent === undefined) { this.rememberSession(session.id); }
    else { this.rememberChildSession(group, subagent); }
    this.workspaceId = group.id;
    this.selectedTitle = this.sessionLabel(session);
    this.selectedSessionDirectory = session.cwd;
    this.selectedWorkspaceTitle = group.title;
    this.data?.conversation.open(session.id, subagent);
    this.syncAgentTerminalWatch();
    if (changing && this.ready) { this.filterGroups(); }
  }

  private openSubagent(entry: DesktopSubagentEntry, parents: DesktopSubagentEntry[], aside: boolean = false): void {
    if (entry.mode === 'external') { return; }
    for (const parent of parents) { this.subagentAddresses.set(parent.id, parent); }
    this.subagentAddresses.set(entry.id, entry);
    const title = entry.label || entry.name;
    if (aside) { this.showDockChat({ id: entry.id, subagent: entry }, title); }
    else { this.openRelatedSession(entry.id, title, entry); }
  }

  private showDockChat(target: DesktopDockChatTarget, title: string, destination?: number): void {
    if (!this.sessionId || !target.id || target.id === this.sessionId) { return; }
    const tab = desktopDockChatTab(target, title);
    const exists = this.rightDock.panes.some((pane: DesktopDockPane): boolean =>
      pane.tabs.some((item: DesktopDockTab): boolean => item.id === tab.id)) ||
      this.rightDock.floats.some((panel: DesktopDockFloat): boolean => panel.tab.id === tab.id);
    const layout = destination === undefined && !exists && this.rightDock.panes[0].tabs.length > 0 && this.canSplitDock() &&
      this.dockAvailableWidth() >= DOCK_SPLIT_MIN_WIDTH ?
      desktopDockSplit(this.rightDock) : this.rightDock;
    this.setDock(desktopDockOpen(layout, tab, true, destination));
  }

  private openSubagentParent(child: DesktopSubagentEntry): void {
    const parent = this.subagentAddresses.get(child.parentId);
    this.openRelatedSession(child.parentId, parent?.label || parent?.name || child.parentId, parent);
  }

  private openRelatedSession(id: string, title: string, subagent?: DesktopSubagentEntry): void {
    const current = this.groups.find((group: DesktopWorkspaceGroup): boolean => group.id === this.workspaceId);
    const group = this.groups.find((candidate: DesktopWorkspaceGroup): boolean =>
      candidate.sessions.some((session: SessionListItem): boolean => session.id === id)) ?? current;
    if (group === undefined) { return; }
    const session = this.sessionSummaries.find((item: SessionListItem): boolean => item.id === id);
    const target: SessionListItem = session ?? { id: id, title: title, cwd: this.selectedSessionDirectory,
      createdAt: subagent?.createdAt ?? 0, updatedAt: 0, running: false, blank: false, raw: '' };
    this.selectSession(group, target, subagent ?? desktopSubagentFromSummary(target));
    if (subagent?.label) { this.selectedTitle = subagent.label; }
    this.panel = 'session';
  }

  private changeDraft(session: string, value: DesktopComposerDraft): void {
    if (session && this.sessionId === session) {
      this.storeDraft(session, value);
    }
  }

  private storeDraft(session: string, value: DesktopComposerDraft): void {
    if (!session) { return; }
    if (value.text.length > 0) { this.drafts.set(session, value); }
    else { this.drafts.delete(session); }
    if (this.sessionId === session) { this.draft = value; }
  }

  private clearSession(forgetSaved: boolean = false): void {
    if (this.sessionId || forgetSaved) { this.nativeSelectionVersion++; }
    if (forgetSaved) { this.rememberSession(''); }
    this.terminalRename = undefined;
    this.closeFeedback();
    this.closeImagePreview();
    this.resetTimelineLocation();
    this.sessionId = '';
    this.selectedSubagent = undefined;
    this.terminalCreateRequest = undefined;
    this.dockTabContext = undefined;
    this.dockSessionId = '';
    this.clearDockGesture();
    this.rightDock = emptyDesktopDock();
    this.referenceOffer = undefined;
    this.selectedTitle = '';
    this.draft = EMPTY_DESKTOP_DRAFT;
    this.attachments = [];
    this.chatError = '';
    this.data?.conversation.open('');
    this.syncAgentTerminalWatch();
  }

  private async newSession(targetWorkspaceId?: string, prompt: string = '', preset: string = ''): Promise<void> {
    const data = this.data;
    if (data === undefined || !this.ready || this.creating) {
      return;
    }
    const current = this.sessionId ? this.groups.find((group: DesktopWorkspaceGroup): boolean =>
      !!group.id && group.id === this.workspaceId) : undefined;
    const preferred = targetWorkspaceId ?? current?.id ?? data.creatorWorkspace(this.sessionId);
    const workspace = this.groups.find((group: DesktopWorkspaceGroup): boolean => !!group.id && group.id === preferred);
    if (workspace === undefined) {
      if (prompt) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_plugin_entry_workspace_required') });
      } else if (targetWorkspaceId === undefined) { this.addWorkspace(); }
      return;
    }
    this.creating = true;
    this.pendingNewSession = undefined;
    this.chatError = '';
    const previousWorkspace = this.workspaceId;
    const previousSession = this.sessionId;
    const previousPanel = this.panel;
    const version = ++this.nativeSelectionVersion;
    const wantedPreset = preset || (previousSession || prompt ? '' : this.landingPreset);
    const created = await data.createSession(workspace.id, wantedPreset)
      .catch((): DesktopSessionCreation => ({ id: '', problem: '' }));
    if (!this.pageActive || this.data !== data) {
      return;
    }
    this.creating = false;
    if (this.nativeSelectionVersion !== version || this.workspaceId !== previousWorkspace ||
      this.sessionId !== previousSession || this.panel !== previousPanel) { return; }
    const id = created.id;
    if (!id || (prompt && this.busySessions.includes(id))) {
      this.getUIContext().getPromptAction().showToast({
        message: created.problem || $r('app.string.desktop_chat_create_failed')
      });
      return;
    }
    this.pendingNewSession = { id: id, workspace: workspace.id, sourceSession: previousSession,
      sourceWorkspace: previousWorkspace, sourcePanel: previousPanel, sourceVersion: version, prompt: prompt };
    this.openPendingNewSession();
  }

  private openPendingNewSession(): void {
    const pending = this.pendingNewSession;
    if (pending === undefined) { return; }
    if (this.workspaceId !== pending.sourceWorkspace || this.sessionId !== pending.sourceSession ||
      this.panel !== pending.sourcePanel || this.nativeSelectionVersion !== pending.sourceVersion ||
      this.archivedIds.includes(pending.id)) { this.pendingNewSession = undefined; return; }
    const group = this.groups.find((item: DesktopWorkspaceGroup): boolean => item.id === pending.workspace);
    const session = group?.sessions.find((item: SessionListItem): boolean => item.id === pending.id);
    if (group === undefined || session === undefined) { return; }
    this.pendingNewSession = undefined;
    if (pending.prompt) {
      const draft = this.drafts.get(pending.id) ?? EMPTY_DESKTOP_DRAFT;
      this.storeDraft(pending.id, { text: draft.text ? draft.text + '\n' + pending.prompt : pending.prompt,
        references: draft.references });
    }
    this.pickWorkspace(group);
    this.selectSession(group, session);
    this.panel = 'session';
  }

  private createPluginDraft(prompt: Resource): void {
    this.newSession(undefined, this.accessibilityLabel(prompt), 'cordis');
  }

  private startPresetCreator(): void {
    if (!this.ready || this.creating || this.data === undefined) { return; }
    if (this.groups.some((group: DesktopWorkspaceGroup): boolean => !!group.id)) {
      this.newSession(undefined, '', 'cordis');
      return;
    }
    this.clearSession(true);
    this.workspaceId = '';
    this.selectedWorkspaceTitle = '';
    this.panel = 'session';
    this.landingPreset = 'cordis';
  }

  private async chatAction(run: (id: string) => Promise<string>, sentDraft?: string,
    id: string = this.sessionId): Promise<string> {
    const data = this.data;
    if (id.length === 0 || data === undefined || this.busySessions.includes(id)) {
      return '当前会话暂不可操作';
    }
    this.busySessions = [...this.busySessions, id];
    if (this.sessionId === id) { this.chatError = ''; }
    let error: string;
    try { error = await run(id); } catch (_) { error = '当前会话操作失败'; }
    if (!this.pageActive || this.data !== data) {
      return error;
    }
    this.busySessions = this.busySessions.filter((other: string): boolean => other !== id);
    if (error.length === 0 && sentDraft !== undefined && this.drafts.get(id)?.text === sentDraft) {
      this.drafts.delete(id);
      if (this.sessionId === id) {
        this.draft = EMPTY_DESKTOP_DRAFT;
      }
    }
    if (this.sessionId === id) {
      this.chatError = error;
    }
    return error;
  }

  private attachDocument(): void {
    const data = this.data;
    if (data !== undefined) {
      this.chatAction((id: string): Promise<string> => this.pickConversationDocuments(data, id, data.conversation));
    }
  }

  private async pickConversationDocuments(data: DesktopWorkspaceData, id: string, conversation: DesktopConversation): Promise<string> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) { return '无法打开文件选择器'; }
    try {
      const picked = await pickDocumentUris(context, 500);
      if (picked.outcome === PickOutcome.CANCELLED) { return ''; }
      if (picked.outcome !== PickOutcome.PICKED) { return picked.reason; }
      return await this.stageDocuments(data, id, picked.uris, conversation);
    } catch (_) {
      return '无法读取所选文件';
    }
  }

  private async stageDocuments(data: DesktopWorkspaceData, id: string, uris: string[],
    conversation: DesktopConversation = data.conversation): Promise<string> {
    const problems: string[] = [];
    for (const uri of uris) {
      if (this.data !== data) { return ''; }
      const problem = await this.stageDocument(data, id, uri, '', conversation);
      if (problem) { problems.push(problem); }
    }
    return problems.join('\n');
  }

  private attachDroppedFiles(files: DesktopDroppedFiles): void {
    const data = this.data;
    if (data === undefined) { return; }
    this.chatAction((id: string): Promise<string> => this.stageDroppedDocuments(data, id, files, data.conversation));
  }

  private async stageDroppedDocuments(data: DesktopWorkspaceData, id: string, files: DesktopDroppedFiles,
    conversation: DesktopConversation): Promise<string> {
    const problems = await this.stageDocuments(data, id, files.uris, conversation);
    if (!files.hasFolder) { return problems; }
    const folderProblem = '请从工作区文件面板添加目录中的文件';
    return problems ? problems + '\n' + folderProblem : folderProblem;
  }

  private attachClipboard(): void {
    const data = this.data;
    if (data === undefined) { return; }
    this.chatAction((id: string): Promise<string> => this.stageClipboard(data, id, data.conversation));
  }

  private async stageClipboard(data: DesktopWorkspaceData, id: string, conversation: DesktopConversation): Promise<string> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const clipboard = await board.getData();
      const problems: string[] = [];
      const uris = new Set<string>();
      let pictureCount = 0;
      for (let index = 0; index < clipboard.getRecordCount(); index++) {
        if (this.data !== data) { return ''; }
        const record = clipboard.getRecord(index);
        if (record.mimeType === pasteboard.MIMETYPE_TEXT_URI) {
          const uri = desktopAttachmentUri(record.uri);
          if (uri) { uris.add(uri); }
        } else if (record.mimeType === pasteboard.MIMETYPE_PIXELMAP && record.pixelMap !== undefined) {
          const picture = record.pixelMap;
          pictureCount++;
          const name = pictureCount === 1 ? '剪贴板图片.png' : '剪贴板图片-' + pictureCount + '.png';
          try {
            const bytes = await packDesktopClipboardPicture(picture);
            const problem = await this.stageAttachment(data, id, name, bytes, 'image/png', conversation);
            if (problem) { problems.push(problem); }
          } catch (_) {
            problems.push(name + '：无法读取剪贴板图片');
          } finally {
            await picture.release().catch((): void => {});
          }
        }
      }
      if (uris.size === 0 && pictureCount === 0) {
        const files = desktopDroppedFiles(await board.getUnifiedData());
        for (const uri of files.uris) { uris.add(uri); }
        if (files.hasFolder) { problems.push('请从工作区文件面板添加目录中的文件'); }
      }
      const problemsFromFiles = await this.stageDocuments(data, id, Array.from(uris), conversation);
      if (problemsFromFiles) { problems.push(problemsFromFiles); }
      if (uris.size === 0 && pictureCount === 0 && problems.length === 0) { return '剪贴板中没有可添加的图片或文件'; }
      return problems.join('\n');
    } catch (_) {
      return '无法读取剪贴板附件';
    }
  }

  private async stageDocument(data: DesktopWorkspaceData, id: string, uri: string, name: string = '',
    conversation: DesktopConversation = data.conversation): Promise<string> {
    if (this.data !== data) { return ''; }
    const file = await readDocumentBytes(uri, conversation.imageLimit(id));
    if (file.outcome !== PickOutcome.PICKED || file.data === undefined) {
      return file.reason || '无法读取所选附件';
    }
    return this.stageAttachment(data, id, name || file.name, file.data, file.mediaType, conversation);
  }

  private async stageAttachment(data: DesktopWorkspaceData, id: string, label: string, bytes: ArrayBuffer,
    mediaType: string, conversation: DesktopConversation = data.conversation): Promise<string> {
    if (this.data !== data) { return ''; }
    try {
      const uploaded = await conversation.upload(id, label, bytes, mediaType, this.subagentAddresses.get(id));
      if (typeof uploaded === 'string') { return `${label}：${uploaded}`; }
      if (mediaType === 'image/gif' && uploaded.picture !== undefined && !uploaded.picture.draftImageSource && this.data === data) {
        const animation = await desktopDraftGif(bytes).catch((): string => '');
        if (animation) { uploaded.picture.draftImageSource = animation; }
      }
      if (this.data === data) {
        this.setAttachments(id, [...(this.attachmentsBySession.get(id) ?? []), uploaded]);
      }
      return '';
    } catch (_) {
      return `${label}：附件上传失败`;
    }
  }

  private setAttachments(id: string, items: DesktopDraftAttachment[]): void {
    if (items.length === 0) {
      this.attachmentsBySession.delete(id);
    } else {
      this.attachmentsBySession.set(id, items);
    }
    if (id === this.sessionId) {
      this.attachments = items;
    }
  }

  @Builder
  private ImagePreviewContent(sessionId: string, row: DesktopMediaAttachment, height: number) {
    DesktopAttachmentViewer({ sessionId: sessionId, attachment: row, host: this.data?.actions, viewportHeight: height,
      onClose: (): void => { this.closeImagePreview(); } })
  }

  private async openImagePreview(row: DesktopMediaAttachment, sessionId: string = this.sessionId): Promise<void> {
    const owner = this.sessionId;
    if (!sessionId || (row.reference === undefined && !row.draftImageSource) || this.imageDialog >= 0 || this.imageDialogOpening) {
      return;
    }
    const version = ++this.imageDialogVersion;
    const height = Math.max(120, Math.min(490, this.workbenchHeight - 135));
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    this.imageDialogOpening = true;
    try {
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.ImagePreviewContent(sessionId, row, height); },
        width: Math.max(220, Math.min(760, this.workbenchWidth - 32)),
        alignment: DialogAlignment.Center, autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.imageDialogVersion) {
            this.imageDialog = -1;
            this.imageDialogOpening = false;
            this.imageDialogVersion++;
          }
        }
      });
      if (this.pageActive && this.sessionId === owner && version === this.imageDialogVersion) { this.imageDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (version === this.imageDialogVersion) { prompt.showToast({ message: '无法打开图片预览' }); }
    } finally {
      if (version === this.imageDialogVersion) { this.imageDialogOpening = false; }
    }
  }

  private closeImagePreview(): void {
    const dialog = this.imageDialog;
    this.imageDialog = -1;
    this.imageDialogOpening = false;
    this.imageDialogVersion++;
    if (dialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(dialog); }
  }

  private sendMessage(alternateDelivery: boolean): void {
    const conversation = this.data?.conversation;
    const text = this.draft.text;
    const files = this.attachments;
    if (conversation !== undefined && (text.trim().length > 0 || files.length > 0)) {
      this.chatAction(async (id: string): Promise<string> => {
        const result = await conversation.send(id, text, files,
          (sessionId: string): Promise<string> => this.exportLog(sessionId),
          (sessionId: string): Promise<string> => this.openSessionFeedback(sessionId), alternateDelivery);
        if (result.length === 0 && conversation === this.data?.conversation) {
          this.setAttachments(id, []);
        }
        return result;
      }, text);
    }
  }

  private openSessionFeedback(sessionId: string, feedback: DesktopFeedback | undefined = this.data?.conversation.feedback): Promise<string> {
    return this.openFeedback({ sessionId: sessionId, messageId: '', version: '' }, feedback);
  }

  private async chooseReplyRating(sessionId: string, messageId: string, rating: DesktopRating,
    feedback: DesktopFeedback | undefined = this.data?.conversation.feedback): Promise<void> {
    const owner = this.sessionId;
    const data = this.data;
    if (feedback === undefined || !sessionId || !messageId || this.choosingFeedback ||
      this.feedbackDialog >= 0 || this.openingFeedback) { return; }
    this.choosingFeedback = true;
    try {
      const loadProblem = await feedback.ensure(sessionId);
      if (!this.pageActive || this.sessionId !== owner || this.data !== data) { return; }
      const previous = feedback.current(messageId);
      const target: DesktopFeedbackTarget = { sessionId: sessionId, messageId: messageId,
        rating: rating, version: previous?.version ?? '' };
      const problem = !loadProblem && previous?.rating === rating ?
        await feedback.retract(target) : await this.openFeedback(target, feedback);
      if (problem && this.pageActive && this.sessionId === owner) {
        this.getUIContext().getPromptAction().showToast({ message: problem });
      }
    } finally {
      this.choosingFeedback = false;
    }
  }

  @Builder
  private FeedbackContent(target: DesktopFeedbackTarget, version: number, feedback: DesktopFeedback) {
    DesktopFeedbackDialog({
      onClose: (): void => { this.closeFeedback(); },
      onSubmit: (category: string, note: string): Promise<string> => this.submitFeedback(target, version, feedback, category, note)
    })
  }

  private async openFeedback(target: DesktopFeedbackTarget, feedback?: DesktopFeedback): Promise<string> {
    const owner = this.sessionId;
    if (!this.pageActive || !target.sessionId || !owner || feedback === undefined) {
      return '当前会话暂不可反馈';
    }
    if (this.feedbackDialog >= 0 || this.openingFeedback) { return ''; }
    this.openingFeedback = true;
    const version = ++this.feedbackDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.FeedbackContent(target, version, feedback); },
        alignment: DialogAlignment.Center, width: Math.max(230, Math.min(488, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.feedbackDialogVersion) { this.feedbackDialog = -1; this.feedbackDialogVersion++; }
        } });
      if (this.pageActive && this.sessionId === owner && version === this.feedbackDialogVersion) {
        this.feedbackDialog = id;
      } else {
        prompt.closeCustomDialog(id);
      }
      return '';
    } catch (_) {
      return '无法打开反馈弹窗';
    } finally {
      this.openingFeedback = false;
    }
  }

  private closeFeedback(): void {
    const id = this.feedbackDialog;
    this.feedbackDialog = -1;
    this.feedbackDialogVersion++;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private async submitFeedback(target: DesktopFeedbackTarget, version: number, feedback: DesktopFeedback,
    category: string, note: string): Promise<string> {
    if (!this.pageActive || version !== this.feedbackDialogVersion) {
      return '当前会话暂不可反馈';
    }
    const problem = await feedback.record(target, category, note);
    if (!problem && this.pageActive && version === this.feedbackDialogVersion) {
      this.closeFeedback();
      this.getUIContext().getPromptAction().showToast({ message: '感谢你的反馈' });
    }
    return problem;
  }

  private async copyTranscript(sessionId: string = this.sessionId): Promise<void> {
    const conversation = this.data?.conversation;
    if (conversation === undefined || !sessionId || this.copyingTranscript) { return; }
    this.copyingTranscript = true;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const reply = await conversation.readMarkdown(sessionId);
      if (!this.pageActive || this.data?.conversation !== conversation) { return; }
      if (!reply.ok || typeof reply.value !== 'string' || !reply.value.trim()) {
        prompt.showToast({ message: '无法读取 Session 进行复制，请重试' });
        return;
      }
      const copied = await copyText(reply.value);
      if (this.pageActive) {
        prompt.showToast({ message: copied ? 'Session 已复制为 Markdown' : '无法写入剪贴板，请检查权限后重试' });
      }
    } finally {
      this.copyingTranscript = false;
    }
  }

  private async exportLog(id: string): Promise<string> {
    const conversation = this.data?.conversation;
    const context = this.getUIContext().getHostContext();
    if (conversation === undefined || context === undefined) { return '当前会话暂不可导出'; }
    if (this.exportingLog) { return '当前正在导出会话日志'; }
    this.exportingLog = true;
    this.logStage = DesktopLogStage.PREPARING;
    this.logProblem = '';
    try {
      await this.openLogDialog();
      if (!this.pageActive || this.data?.conversation !== conversation) { return ''; }
      const result = await exportDesktopLog(context, id,
        (onData: (chunk: ArrayBuffer) => void): Promise<string> => conversation.downloadLog(id, onData),
        (): boolean => {
          if (!this.pageActive || this.data?.conversation !== conversation) { return false; }
          this.logStage = DesktopLogStage.CHOOSING;
          return true;
        });
      if (!this.pageActive || this.data?.conversation !== conversation) { return ''; }
      if (result.error) {
        this.logProblem = result.error;
        this.logStage = DesktopLogStage.FAILED;
      } else if (result.saved) {
        this.logStage = DesktopLogStage.SAVED;
      } else {
        this.closeLogDialog();
      }
      return result.error;
    } finally {
      this.exportingLog = false;
    }
  }

  @Builder
  private LogDialogContent() {
    DesktopSessionLogDialog({ stage: this.logStage, problem: this.logProblem,
      onClose: (): void => { this.closeLogDialog(); } })
  }

  private async openLogDialog(): Promise<void> {
    if (this.logDialog >= 0) { return; }
    const version = ++this.logDialogVersion;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.LogDialogContent(); },
        alignment: DialogAlignment.Center, width: Math.max(220, Math.min(448, this.workbenchWidth - 32)),
        autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (version === this.logDialogVersion) { this.logDialog = -1; this.logDialogVersion++; }
        } });
      if (this.pageActive && version === this.logDialogVersion) { this.logDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.pageActive) { prompt.showToast({ message: '正在导出 Session' }); }
    }
  }

  private closeLogDialog(): void {
    const id = this.logDialog;
    this.logDialog = -1;
    this.logDialogVersion++;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private setDock(layout: DesktopDockLayout): void {
    if (!this.sessionId || layout === this.rightDock) { return; }
    const previous = this.rightDock;
    this.dockMiddlePress = undefined;
    const edit = this.terminalRename;
    if (edit !== undefined && this.findTerminalRenameTab(layout, edit) === undefined) { this.terminalRename = undefined; }
    const menu = this.dockTabContext;
    if (menu !== undefined && (!layout.expanded || !layout.panes[menu.pane]?.tabs.some(
      (tab: DesktopDockTab): boolean => tab.id === menu.tab))) {
      this.dockTabContext = undefined;
    }
    if (layout.panes !== this.rightDock.panes || layout.floats !== this.rightDock.floats) {
      this.retainFileNavigators(layout);
    }
    this.rightDock = layout;
    if (layout.expanded) {
      layout.panes.forEach((pane: DesktopDockPane, index: number): void => {
        const oldPane = previous.panes[index];
        if (!previous.expanded || oldPane?.id !== pane.id || oldPane.active !== pane.active ||
          oldPane.tabs.findIndex((tab: DesktopDockTab): boolean => tab.id === pane.active) !==
            pane.tabs.findIndex((tab: DesktopDockTab): boolean => tab.id === pane.active)) {
          this.requestDockTabReveal(index);
        }
      });
    } else {
      this.dockTabRevealPending.clear();
    }
    this.docks.set(this.sessionId, layout);
    this.data?.terminalRetentions.setTabs(this.sessionId, desktopDockTerminalIds(layout));
    saveDesktopDock(this.getUIContext().getHostContext(), this.sessionId, layout);
  }

  private observeDockTabArea(index: number, id: string, area: Area): void {
    const previous = this.dockTabBounds.get(id);
    this.dockTabBounds.set(id, area);
    if (this.rightDock.panes[index]?.active === id &&
      (this.dockTabRevealPending.has(index) || previous?.width !== area.width)) {
      this.requestDockTabReveal(index);
    }
  }

  private observeDockTabViewport(index: number, previous: Area, area: Area): void {
    this.dockTabViewports.set(index, area);
    if (previous.width !== area.width || this.dockTabRevealPending.has(index)) {
      this.requestDockTabReveal(index);
    }
  }

  private requestDockTabReveal(index: number): void {
    this.dockTabRevealPending.add(index);
    if (this.dockTabRevealPosted) { return; }
    this.dockTabRevealPosted = true;
    this.getUIContext().postFrameCallback(new StartupFrameCallback((): void => {
      this.dockTabRevealPosted = false;
      if (!this.pageActive || !this.rightDock.expanded || this.panel !== 'session') {
        this.dockTabRevealPending.clear();
        return;
      }
      this.dockTabRevealPending.forEach((paneIndex: number): void => {
        const active = this.rightDock.panes[paneIndex]?.active;
        if (!active) { this.dockTabRevealPending.delete(paneIndex); return; }
        const tab = this.dockTabBounds.get(active);
        const viewport = this.dockTabViewports.get(paneIndex);
        if (tab === undefined || viewport === undefined || Number(viewport.width) <= 0) { return; }
        this.dockTabRevealPending.delete(paneIndex);
        const delta = desktopDockTabRevealDelta(Number(viewport.globalPosition.x), Number(viewport.width),
          Number(tab.globalPosition.x), Number(tab.width));
        if (Math.abs(delta) > 0.5) { this.dockTabScrollers[paneIndex]?.scrollBy(delta, 0); }
      });
    }));
  }

  private dockShows(kind: DesktopDockKind): boolean {
    return this.rightDock.floats.some((panel: DesktopDockFloat): boolean => panel.tab.kind === kind) ||
      (this.rightDock.expanded && this.rightDock.panes.some((pane: DesktopDockPane): boolean =>
        pane.tabs.some((tab: DesktopDockTab): boolean => tab.id === pane.active && tab.kind === kind)));
  }

  private focusDockPane(index: number): void {
    if (index < 0 || index >= this.rightDock.panes.length ||
      (this.rightDock.focus === index && !this.rightDock.focusedFloat)) { return; }
    this.setDock(desktopDockPresentation(this.rightDock, index, this.rightDock.expanded, this.rightDock.fullscreen, ''));
  }

  private toggleRightDock(): void {
    this.setDock(desktopDockPresentation(this.rightDock, this.rightDock.focus, !this.rightDock.expanded, false));
  }

  private toggleDockFullscreen(): void {
    this.setDock(desktopDockPresentation(this.rightDock, this.rightDock.focus, true, !this.rightDock.fullscreen));
  }

  private splitDock(): void {
    if (!this.canSplitDock()) { return; }
    this.setDock(desktopDockSplit(this.rightDock));
  }

  private canSplitDock(): boolean {
    return this.rightDock.panes.length === 1 && this.workbenchWidth >= DOCK_SPLIT_MIN_WIDTH;
  }

  private dockAvailableWidth(): number {
    return this.workbenchWidth - (this.sidebarCollapsed ? 52 : this.sidebarWidth) - 275 - DOCK_HANDLE_WIDTH;
  }

  private dockWidth(): number {
    return this.clampDockWidth(this.dockDragWidth || this.rightDock.width || this.defaultDockWidth);
  }

  private clampDockWidth(width: number): number {
    const minimum = this.rightDock.panes.length === 1 ? DOCK_MIN_WIDTH : DOCK_SPLIT_MIN_WIDTH;
    return Math.min(Math.max(minimum, width), Math.max(minimum, this.dockAvailableWidth()));
  }

  private dockPaneWeight(index: number): number {
    const fraction = this.dockDragFraction || this.rightDock.fraction;
    return this.rightDock.panes.length === 1 ? 1 : Math.round(1000 * (index === 0 ? fraction : 1 - fraction));
  }

  private dockFullscreen(): boolean {
    return this.rightDock.expanded && (this.rightDock.fullscreen || this.dockAutoFullscreen());
  }

  private dockAutoFullscreen(): boolean {
    const minimum = this.rightDock.panes.length === 1 ? DOCK_MIN_WIDTH : DOCK_SPLIT_MIN_WIDTH;
    return this.dockAvailableWidth() < minimum;
  }

  private startDockResize(split: boolean): void {
    this.dockResizeSession = this.sessionId;
    this.dockResizeStart = split ? this.rightDock.fraction : this.dockWidth();
  }

  private updateDockResize(split: boolean, offset: number): void {
    if (!this.dockResizeSession || this.dockResizeSession !== this.sessionId) { return; }
    if (split) {
      const width = Number(this.dockBounds?.width ?? 0) - DOCK_HANDLE_WIDTH;
      if (width > 0) { this.dockDragFraction = desktopDockSplitFraction(this.dockResizeStart + offset / width); }
    } else {
      this.dockDragWidth = this.clampDockWidth(this.dockResizeStart - offset);
    }
  }

  private finishDockResize(commit: boolean): void {
    const width = this.dockDragWidth;
    const fraction = this.dockDragFraction;
    const session = this.dockResizeSession;
    this.dockResizeSession = '';
    this.dockDragWidth = 0;
    this.dockDragFraction = 0;
    if (commit && session && session === this.sessionId && (width || fraction)) {
      this.setDock(desktopDockResize(this.rightDock, width || this.rightDock.width, fraction || this.rightDock.fraction));
    }
  }

  private clearDockGesture(): void {
    this.dockMiddlePress = undefined;
    this.clearSessionDrag();
    this.endDockDrag(false);
    this.dockTabBounds.clear();
    this.dockTabViewports.clear();
    this.dockTabRevealPending.clear();
    this.dockGripHover = 0;
    this.finishDockResize(false);
    this.finishFloatResize(false);
  }

  private closeDockTab(index: number, id: string): void {
    const terminalId = this.dockStoredTab(index, id)?.terminalId;
    if (terminalId) { this.closeDockTerminal(this.sessionId, id, terminalId); }
    else { this.removeDockTab(index, id); }
  }

  private findTerminalRenameTab(layout: DesktopDockLayout, target: DesktopTerminalRenameTarget): DesktopDockTab | undefined {
    const matches = (tab: DesktopDockTab): boolean => tab.id === target.tabId && tab.terminalId === target.terminalId;
    return layout.panes.flatMap((pane: DesktopDockPane): DesktopDockTab[] => pane.tabs).find(matches) ??
      layout.floats.find((panel: DesktopDockFloat): boolean => matches(panel.tab))?.tab;
  }

  private startTerminalRename(index: number, id: string): void {
    const tab = this.dockStoredTab(index, id);
    if (!this.pageActive || this.panel !== 'session' || !this.sessionId || !tab?.terminalId ||
      this.terminalRename !== undefined || this.data === undefined) { return; }
    const key = JSON.stringify([this.sessionId, tab.terminalId]);
    if (this.pendingTerminalRenames.has(key)) { return; }
    if (index < 0) { this.focusFloat(id); }
    else { this.setDock(desktopDockSelect(this.rightDock, index, id)); }
    this.terminalRename = { version: ++this.terminalRenameVersion, sessionId: this.sessionId, tabId: id,
      terminalId: tab.terminalId, title: tab.title };
  }

  private async finishTerminalRename(version: number, value: string, save: boolean): Promise<void> {
    const target = this.terminalRename;
    if (target?.version !== version) { return; }
    this.terminalRename = undefined;
    const title = value.trim();
    const host = this.data?.actions;
    const layout = this.docks.get(target.sessionId);
    const tab = layout === undefined ? undefined : this.findTerminalRenameTab(layout, target);
    if (!save || !title || title.length > 120 || title === target.title || title === tab?.title || tab === undefined ||
      !this.pageActive || host === undefined) { return; }
    const key = JSON.stringify([target.sessionId, target.terminalId]);
    this.pendingTerminalRenames.add(key);
    const result = await host.call('terminal/rename', { 'agentId': target.sessionId, 'id': target.terminalId, 'title': title });
    if (!this.pageActive || this.data?.actions !== host) { return; }
    this.pendingTerminalRenames.delete(key);
    if (!result.ok) {
      this.getUIContext().getPromptAction().showToast({ message: desktopHostProblem(result) });
      return;
    }
    const latest = this.docks.get(target.sessionId);
    // A later host title wins if it arrived while the request was in flight.
    if (latest === undefined || this.findTerminalRenameTab(latest, target)?.title !== tab.title) { return; }
    const next = desktopDockBindTerminal(latest, target.tabId, target.terminalId, title);
    if (target.sessionId === this.sessionId) { this.setDock(next); }
    else {
      this.docks.set(target.sessionId, next);
      saveDesktopDock(this.getUIContext().getHostContext(), target.sessionId, next);
    }
  }

  private async closeDockTerminal(sessionId: string, tabId: string, terminalId: string): Promise<void> {
    const host = this.data?.actions;
    const key = JSON.stringify([sessionId, terminalId]);
    if (host === undefined || this.closingDockTerminals.has(key)) { return; }
    this.closingDockTerminals.add(key);
    const result = await host.call('terminal/close', { 'agentId': sessionId, 'id': terminalId });
    if (!this.pageActive || this.data?.actions !== host) { return; }
    this.closingDockTerminals.delete(key);
    if (!result.ok && result.error?.code !== 'terminal/unavailable') {
      this.getUIContext().getPromptAction().showToast({ message: desktopHostProblem(result) });
      return;
    }
    const layout = this.docks.get(sessionId);
    if (layout === undefined) { return; }
    const index = layout.panes.findIndex((pane: DesktopDockPane): boolean => pane.tabs.some(
      (tab: DesktopDockTab): boolean => tab.id === tabId && tab.terminalId === terminalId));
    if (index < 0 && !layout.floats.some((panel: DesktopDockFloat): boolean =>
      panel.tab.id === tabId && panel.tab.terminalId === terminalId)) { return; }
    if (sessionId === this.sessionId) { this.removeDockTab(index, tabId); return; }
    const next = index < 0 ? desktopDockCloseFloat(layout, tabId) : desktopDockCloseTab(layout, index, tabId);
    this.docks.set(sessionId, next);
    this.data?.terminalRetentions.setTabs(sessionId, desktopDockTerminalIds(next));
    saveDesktopDock(this.getUIContext().getHostContext(), sessionId, next);
  }

  private removeDockTab(index: number, id: string): void {
    this.documentViews.delete(this.documentViewKey(id));
    if (this.terminalCreateRequest?.tabId === id) { this.terminalCreateRequest = undefined; }
    this.dockTabBounds.delete(id);
    this.setDock(index < 0 ? desktopDockCloseFloat(this.rightDock, id) : desktopDockCloseTab(this.rightDock, index, id));
  }

  private hideDockTool(kind: DesktopDockKind): void {
    const panel = this.rightDock.floats.find((item: DesktopDockFloat): boolean => item.tab.kind === kind);
    if (panel !== undefined && kind === DesktopDockKind.TERMINAL) { this.collapseFloatingTerminal(panel.tab.id); }
    else if (panel !== undefined) { this.closeDockTab(-1, panel.tab.id); }
    else { this.toggleRightDock(); }
  }

  private collapseFloatingTerminal(id: string): void {
    const layout = desktopDockSeatFloat(this.rightDock, id);
    this.setDock(desktopDockPresentation(layout, layout.focus, false, false));
  }

  private showPlan(document: DesktopPlanDocument, sessionId: string = this.sessionId): void {
    const source = sessionId === this.sessionId ? undefined : sessionId;
    const tab: DesktopDockTab = { id: desktopDockResourceId('plan', document.callId, source), kind: DesktopDockKind.PLAN,
      title: document.title || '计划预览', plan: document, sourceSessionId: source };
    this.setDock(desktopDockOpen(this.rightDock, tab));
  }

  private async openCompaction(target: DesktopDockChatTarget, sequence: number,
    isCurrent: () => boolean): Promise<ResourceStr | undefined> {
    const owner = this.sessionId;
    const host = this.data?.actions;
    if (!target.id || !owner || host === undefined || !isCurrent()) { return undefined; }
    const child = target.subagent;
    const address = child === undefined ? followSessionAddress(target.id) :
      followSubagentAddress(child.parentId, child.id, child.mode);
    const result = await host.call(SESSION_PAGE_ENDPOINT, { 'address': address, 'throughSeq': sequence, 'maxMessages': 1 });
    if (!this.pageActive || this.sessionId !== owner || this.data?.actions !== host || !isCurrent()) { return undefined; }
    if (!result.ok) { return $r('app.string.desktop_compaction_read_failed'); }
    const markdown = readDesktopCompactionSummary(projectSessionPage(result.value).records, sequence);
    if (markdown === undefined) { return $r('app.string.desktop_compaction_not_found'); }
    const id = desktopDockResourceId('compaction', JSON.stringify([target.id, child?.parentId, child?.mode, sequence]));
    const title = this.accessibilityLabel($r('app.string.desktop_compaction_preview_title'));
    const tab: DesktopDockTab = { id: id, kind: DesktopDockKind.COMPACTION, title: title, compactionMarkdown: markdown };
    this.setDock(desktopDockOpen(this.rightDock, tab));
    return undefined;
  }

  private showWorkspaceFiles(toggle: boolean = false): void {
    if (toggle && this.dockShows(DesktopDockKind.FILES)) { this.hideDockTool(DesktopDockKind.FILES); return; }
    const tab: DesktopDockTab = { id: DesktopDockKind.FILES, kind: DesktopDockKind.FILES, title: '工作区文件' };
    this.setDock(desktopDockOpen(this.rightDock, tab, false));
  }

  private showTerminal(create: boolean = false, toggle: boolean = false): void {
    if (toggle && this.dockShows(DesktopDockKind.TERMINAL)) { this.hideDockTool(DesktopDockKind.TERMINAL); return; }
    const active = desktopDockTab(this.rightDock);
    const tab: DesktopDockTab = (active?.kind === DesktopDockKind.TERMINAL ? active :
      this.rightDock.floats.find((panel: DesktopDockFloat): boolean => panel.tab.kind === DesktopDockKind.TERMINAL)?.tab ??
      this.rightDock.panes.flatMap((pane: DesktopDockPane): DesktopDockTab[] => pane.tabs).find(
        (item: DesktopDockTab): boolean => item.kind === DesktopDockKind.TERMINAL)) ??
      { id: DesktopDockKind.TERMINAL, kind: DesktopDockKind.TERMINAL, title: '终端' };
    this.setDock(desktopDockOpen(this.rightDock, tab, false));
    if (create) { this.terminalCreateRequest = { sessionId: this.sessionId, tabId: tab.id, shellPath: '' }; }
  }

  private openDockTerminal(index: number, tabId: string, row: DesktopTerminalRow): boolean {
    const current = this.dockStoredTab(index, tabId);
    if (!current?.terminalId || current.terminalId === row.id) { return false; }
    const prior = this.rightDock.panes.flatMap((pane: DesktopDockPane): DesktopDockTab[] => pane.tabs).find(
      (tab: DesktopDockTab): boolean => tab.kind === DesktopDockKind.TERMINAL && tab.terminalId === row.id) ??
      this.rightDock.floats.find((panel: DesktopDockFloat): boolean => panel.tab.kind === DesktopDockKind.TERMINAL &&
        panel.tab.terminalId === row.id)?.tab;
    this.setDock(desktopDockOpen(this.rightDock, prior ?? desktopDockTerminalTab(row.id, row.title), false));
    return true;
  }

  private replaceDockTerminal(sessionId: string, tabId: string, oldId: string, row: DesktopTerminalRow): boolean {
    if (!this.pageActive || sessionId !== this.sessionId || !oldId || !row.id || oldId === row.id ||
      this.closingDockTerminals.has(JSON.stringify([sessionId, oldId]))) { return false; }
    const next = desktopDockBindTerminal(this.rightDock, tabId, row.id, row.title, oldId);
    if (next === this.rightDock) { return false; }
    this.setDock(next);
    return true;
  }

  private showArtifact(path: string, name: string, sessionId: string = this.sessionId): void {
    const source = sessionId === this.sessionId ? undefined : sessionId;
    const next = desktopDockNavigatePreview(this.rightDock, path, name, source);
    if (next !== this.rightDock) { this.setDock(next); }
  }

  private replaceArtifact(index: number, tab: DesktopDockTab, path: string, name: string): void {
    if (!this.pageActive || !this.dockTabShown(index, tab.id) ||
      this.dockStoredTab(index, tab.id)?.kind !== DesktopDockKind.PREVIEW) { return; }
    const next = desktopDockNavigatePreview(this.rightDock, path, name, tab.sourceSessionId, tab.id);
    if (next === this.rightDock) { return; }
    const replaced = index < 0 ? next.floats.find((panel: DesktopDockFloat): boolean => panel.tab.id === tab.id)?.tab :
      next.panes[index]?.tabs.find((candidate: DesktopDockTab): boolean => candidate.id === tab.id);
    if (replaced?.file?.path === path) { this.documentViews.delete(this.documentViewKey(tab.id)); }
    this.setDock(next);
  }

  private openArtifactIn(index: number, tab: DesktopDockTab, path: string, name: string, floating: boolean): void {
    if (!this.pageActive || !this.dockTabShown(index, tab.id) || this.dockStoredTab(index, tab.id) === undefined) {
      return;
    }
    const next = desktopDockOpenPreviewIn(this.rightDock, path, name, tab.sourceSessionId,
      floating, this.defaultFloatRect(), this.fileSearchRoot(tab));
    if (next !== this.rightDock) { this.setDock(next); }
  }

  private fileMenuCanReference(session: string): boolean {
    return session === this.sessionId && this.chat?.sessionId === session && this.chat.loading === false &&
      !this.busySessions.includes(session);
  }

  private showChanges(target: DesktopChangeTarget, sessionId: string = this.sessionId): void {
    if (target.sessionId !== sessionId) { return; }
    const source = sessionId === this.sessionId ? undefined : sessionId;
    const tab: DesktopDockTab = { id: desktopDockResourceId('changes', String(target.sequence), source), kind: DesktopDockKind.CHANGES,
      sourceSessionId: source,
      title: '改动审阅', changes: target, changeLocation: !target.summary.applied && target.sequence >= 0 ?
        { sequence: target.sequence, index: target.index, split: target.split, wrap: target.wrap } : undefined };
    this.setDock(desktopDockOpen(this.rightDock, tab));
  }

  private async referenceFileAction(action: DesktopReferenceAction, path: string, name: string,
    sessionId: string = this.sessionId): Promise<void> {
    const owner = this.sessionId;
    const host = this.data?.actions;
    if (!sessionId || host === undefined) { return; }
    const result = await host.call('workspaceFiles/stat', { 'workspaceFileScopeId': sessionId, 'path': path });
    if (!this.pageActive || this.sessionId !== owner || this.data?.actions !== host) { return; }
    const absolute = getString(result.value, 'absolutePath') ?? '';
    const ability = this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
    const toast = this.getUIContext().getPromptAction();
    if (!result.ok || !absolute.startsWith('/')) {
      toast.showToast({ message: '无法访问此文件' });
      return;
    }
    const source: DesktopReferenceSource = { host: host, sessionId: sessionId, path: path, absolutePath: absolute };
    try {
      switch (action) {
        case DesktopReferenceAction.ADD_TO_CHAT:
          if (desktopReferenceText(absolute, false, true) && !this.busySessions.includes(sessionId) &&
            this.chat?.sessionId === sessionId && this.chat?.loading === false) {
            this.referenceOffer = { sessionId: sessionId, path: absolute };
          } else {
            toast.showToast({ message: '无法添加文件，请返回对话后重试' });
          }
          break;
        case DesktopReferenceAction.COPY_PATH:
          toast.showToast({ message: await copyText(absolute) ? '已复制' : '无法复制路径' });
          break;
        case DesktopReferenceAction.COPY_IMAGE:
          await copyDesktopReferenceImage(source);
          toast.showToast({ message: '已复制' });
          break;
        case DesktopReferenceAction.DOWNLOAD:
          if (ability === undefined) { throw new Error('Missing context'); }
          if (await saveDesktopReferenceFile(ability, source, name)) {
            toast.showToast({ message: '已下载' });
          }
          break;
        case DesktopReferenceAction.OPEN:
          if (ability === undefined || !await openDesktopReferenceFile(ability, absolute, name)) {
            toast.showToast({ message: '系统未能打开此文件' });
          }
          break;
        case DesktopReferenceAction.REVEAL:
          if (ability === undefined || openFileLocation(ability, absolute) !== 'ok') {
            toast.showToast({ message: '无法在系统文件中定位' });
          }
          break;
      }
    } catch (_) {
      toast.showToast({ message: action === DesktopReferenceAction.DOWNLOAD ? '无法保存文件' : '无法复制图片' });
    }
  }

  private async openArtifactAction(path: string, name: string, reveal: boolean,
    sessionId: string = this.sessionId): Promise<void> {
    const owner = this.sessionId;
    const result = await this.data?.actions.call('workspaceFiles/stat', { 'workspaceFileScopeId': sessionId, 'path': path });
    const ability = this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext');
    if (!this.pageActive || this.sessionId !== owner) {
      return;
    }
    const absolute = getString(result?.value, 'absolutePath') ?? '';
    const ok = result?.ok === true && absolute.startsWith('/') && ability !== undefined && (reveal ?
      openFileLocation(ability, absolute) === 'ok' :
      await openSystemPreview(ability, uriFromPath(absolute), name, mimeTypeForName(name)));
    if (!ok) {
      this.getUIContext().getPromptAction().showToast({ message: reveal ? '无法在系统文件中定位' : '系统未能打开此文件的预览' });
    }
  }

  private async stopMessage(): Promise<void> {
    const data = this.data;
    const session = this.sessionId;
    if (data === undefined || !session) { return; }
    const problem = await this.stopForSession(session, data.conversation);
    if (problem && this.pageActive && this.data === data && this.sessionId === session) { this.chatError = problem; }
  }

  private async stopForSession(session: string, conversation: DesktopConversation): Promise<string> {
    const owner = this.data;
    if (!session || owner === undefined || this.stoppingSessions.includes(session)) { return ''; }
    this.stoppingSessions = [...this.stoppingSessions, session];
    try {
      return await conversation.cancel(session);
    } catch (_) {
      return '宿主未确认停止';
    } finally {
      if (this.data === owner && this.pageActive) {
        this.stoppingSessions = this.stoppingSessions.filter((id: string): boolean => id !== session);
      }
    }
  }

  private workspacePickerRows(): DesktopWorkspacePickerRow[] {
    return this.groups.filter((group: DesktopWorkspaceGroup): boolean => !!group.id)
      .map((group: DesktopWorkspaceGroup): DesktopWorkspacePickerRow => ({
        id: group.id, title: this.accessibilityLabel(group.title), path: group.path
      }));
  }

  private pickWorkspace(group: DesktopWorkspaceGroup): void {
    if (group.id !== this.workspaceId) {
      this.clearSession(true);
    }
    this.workspaceId = group.id;
    this.selectedWorkspaceTitle = group.title;
    this.sidebarCollapsed = false;
    this.closeSearch();
    this.filterGroups();
    this.revealWorkspace(group.id);
  }

  private async addWorkspace(): Promise<void> {
    const data = this.data;
    const ui = this.getUIContext();
    const context = ui.getHostContext();
    if (data === undefined || !this.ready || context === undefined || this.workspaceBusy || this.workspaceFolderErrorOpen) {
      return;
    }
    const selection = this.nativeSelectionVersion;
    const panel = this.panel;
    this.workspaceBusy = true;
    try {
      const picked = await pickFolder(context);
      if (picked.outcome === PickOutcome.CANCELLED || this.data !== data) {
        return;
      }
      if (picked.outcome !== PickOutcome.PICKED || picked.path.length === 0) {
        this.showWorkspaceFolderError(data, picked.reason || $r('app.string.desktop_experiment_action_failed'));
        return;
      }
      const created = await data.createWorkspace(picked.path);
      if (this.data !== data) {
        return;
      }
      const id = created.id;
      if (!id) {
        this.showWorkspaceFolderError(data, created.problem || $r('app.string.desktop_experiment_action_failed'));
        return;
      }
      if (picked.reason.length > 0) {
        ui.getPromptAction().showToast({ message: picked.reason });
      }
      if (this.pageActive && this.nativeSelectionVersion === selection && this.panel === panel) {
        this.revealWorkspace(id);
        await this.newSession(id);
      }
    } catch (_) {
      this.showWorkspaceFolderError(data, $r('app.string.desktop_experiment_action_failed'));
    } finally {
      if (this.data === data) {
        this.workspaceBusy = false;
      }
    }
  }

  private showWorkspaceFolderError(owner: DesktopWorkspaceData, message: ResourceStr): void {
    if (!this.pageActive || this.data !== owner || this.workspaceFolderErrorOpen) { return; }
    this.workspaceFolderErrorOpen = true;
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.desktop_workspace_picker_folder_error'),
      message: message,
      buttons: [
        { text: $r('app.string.desktop_workspace_picker_cancel'), color: '#777777' },
        { text: $r('app.string.desktop_workspace_picker_retry'), color: '#4176E6' }
      ],
      systemMaterial: desktopMenuOptions(Placement.BottomLeft).systemMaterial
    }).then((result): void => {
      this.workspaceFolderErrorOpen = false;
      if (result.index === 1 && this.pageActive && this.data === owner) { this.addWorkspace(); }
    }).catch((): void => { this.workspaceFolderErrorOpen = false; });
  }

  private openPlugins(name: string = '', title: string = '', description: string = '', location?: DesktopPluginLocation): void {
    this.pluginTitle = title;
    this.pluginDescription = description;
    this.pluginName = name;
    this.pluginLocation = location ?? { kind: name ? 'package' : 'list', name: name, rowId: '' };
    this.panel = 'plugins';
  }

  private settingsSurfaceParams(): DesktopSettingsSurfaceParams {
    const details = this.data?.accountNotices.details;
    const actions = this.data?.actions;
    // Keep the account subscription bound to the workbench owner across the settings sheet's state snapshots.
    const accountDetails: DesktopAccountDetailsAccess | undefined = details === undefined ? undefined : {
      observe: (listener: (snapshot: DesktopAccountDetailsSnapshot) => void): () => void => details.observe(listener),
      refreshAfterCurrent: (): void => { details.refreshAfterCurrent(); }
    };
    const generalHost: DesktopGeneralHostAccess | undefined = actions === undefined ? undefined : {
      call: (endpoint: string, body?: Record<string, Object | null>): Promise<RpcResult> => actions.call(endpoint, body)
    };
    return { compact: this.settingsSurfaceSize?.compact ?? false, mode: this.workspaceColorMode(),
      section: this.settingsSection, accountNotices: this.data?.accountNotices, accountDetails: accountDetails,
      host: actions, generalHost: generalHost,
      codingTools: this.codingTools, changeCodingTools: (enabled: boolean): void => { this.data?.codingTools.setEnabled(enabled); },
      close: (): void => { this.closeSettings(); },
      startCreator: (): void => { this.startPresetCreator(); },
      capturePresetDefaultSync: (): DesktopPresetDefaultSync | undefined => this.capturePresetDefaultSync(),
      selectSection: (section: string): void => { this.settingsSection = section; },
      openPlugins: (): void => { this.settingsOpeningPlugins = true; } };
  }

  private capturePresetDefaultSync(): DesktopPresetDefaultSync | undefined {
    const owner = this.data;
    const session = this.sessionId;
    if (owner === undefined || !session || this.selectedSubagent !== undefined ||
      !this.sessionSummaries.some((row: SessionListItem): boolean => row.id === session && row.blank)) {
      return undefined;
    }
    const version = this.nativeSelectionVersion;
    return async (id: string): Promise<string> => {
      if (!this.pageActive || this.data !== owner || this.nativeSelectionVersion !== version || this.sessionId !== session ||
        this.selectedSubagent !== undefined || this.busySessions.includes(session) ||
        (this.chat?.sessionId === session && this.chat.running) ||
        !this.sessionSummaries.some((row: SessionListItem): boolean => row.id === session && row.blank)) { return ''; }
      const result = await owner.selectBlankSessionPreset(session, id);
      return result.ok && result.value === id ? '' : result.error?.message ||
        this.accessibilityLabel($r('app.string.desktop_preset_default_sync_failed'));
    };
  }

  private refreshSettingsSurface(): void {
    if (!this.settingsClosing) { this.settingsSurface?.update(this.settingsSurfaceParams()); }
  }

  private resizeSettingsSurface(): void {
    const content = this.settingsSurface;
    if (content === undefined || !this.settingsSurfaceReady || this.settingsClosing || this.settingsSizing) { return; }
    const size = desktopSettingsSize(this.workbenchWidth, this.workbenchHeight);
    const previous = this.settingsSurfaceSize;
    if (size.width === previous?.width && size.height === previous?.height) { return; }
    this.settingsSizing = true;
    const style: SheetOptions = { width: size.width, height: size.height,
      radius: LengthMetrics.vp(size.compact ? 0 : 28) };
    this.getUIContext().updateBindSheet(content, style, true).then((): void => {
      if (content !== this.settingsSurface) { return; }
      this.settingsSizing = false;
      if (this.settingsClosing) { return; }
      this.settingsSurfaceSize = size;
      if (previous?.compact !== size.compact) { this.refreshSettingsSurface(); }
      this.resizeSettingsSurface();
    }).catch((): void => {
      if (content === this.settingsSurface) { this.settingsSizing = false; }
    });
  }

  private async openSettings(section: string = ''): Promise<void> {
    if (!this.pageActive || this.switching || this.settingsOpen) { return; }
    if (section) { this.settingsSection = section; }
    this.settingsOpen = true;
    this.syncReading();
    const ui = this.getUIContext();
    let opening: ComponentContent<DesktopSettingsSurfaceParams> | undefined;
    try {
      const size = desktopSettingsSize(this.workbenchWidth, this.workbenchHeight);
      this.settingsSurfaceSize = size;
      const content = new ComponentContent<DesktopSettingsSurfaceParams>(ui, wrapBuilder(buildDesktopSettingsSurface),
        this.settingsSurfaceParams());
      this.settingsSurface = content;
      opening = content;
      const material = dialogMaterial();
      await ui.openBindSheet(content, {
        preferType: SheetType.CENTER, width: size.width, height: size.height,
        dragBar: false, showClose: false, radius: LengthMetrics.vp(size.compact ? 0 : 28), systemMaterial: material,
        maskColor: $r('app.color.desktop_settings_mask'),
        backgroundColor: material === undefined ? $r('app.color.desktop_settings_surface') : undefined,
        onDisappear: (): void => { if (this.settingsSurface === content) { this.settingsDismissed(); } }
      });
      if (this.settingsSurface !== content) { return; }
      this.settingsSurfaceReady = true;
      if (this.settingsClosing || !this.pageActive) { this.dismissSettingsSurface(content); }
      else {
        this.data?.accountNotices.details.refresh();
        this.resizeSettingsSurface();
      }
    } catch (_) {
      if (opening === undefined || this.settingsSurface === opening) {
        this.settingsDismissed();
        if (this.pageActive) { ui.getPromptAction().showToast({ message: $r('app.string.desktop_settings_failed') }); }
      }
    }
  }

  private closeSettings(): void {
    const content = this.settingsSurface;
    if (content === undefined || this.settingsClosing) { return; }
    this.settingsClosing = true;
    if (this.settingsSurfaceReady) { this.dismissSettingsSurface(content); }
  }

  private dismissSettingsSurface(content: ComponentContent<DesktopSettingsSurfaceParams>): void {
    this.getUIContext().closeBindSheet(content).catch((): void => {
      if (this.settingsSurface === content) { this.settingsClosing = false; }
    });
  }

  private settingsDismissed(): void {
    const content = this.settingsSurface;
    this.settingsSurface = undefined;
    this.settingsSurfaceSize = undefined;
    this.settingsSurfaceReady = false;
    this.settingsSizing = false;
    this.settingsClosing = false;
    if (content !== undefined) { disposeOverlayContent(content); }
    this.settingsOpen = false;
    const showPlugins = this.settingsOpeningPlugins;
    this.settingsOpeningPlugins = false;
    if (this.pageActive) {
      if (showPlugins) { this.openPlugins(); }
      this.reloadShortcutBindings();
      this.syncReading();
    }
  }

  private async forkFrom(source: string, atSeq?: number,
    conversation: DesktopConversation | undefined = this.data?.conversation): Promise<void> {
    const data = this.data;
    const owner = this.sessionId;
    if (data === undefined || this.forking ||
      (atSeq !== undefined && (!conversation?.canForkAt(atSeq) || (conversation === data.conversation && source !== owner)))) {
      return;
    }
    this.forking = true;
    try {
      const result = await data.forkSession(source, atSeq);
      if (!this.pageActive || this.data !== data) { return; }
      if (result.problem) {
        this.getUIContext().getPromptAction().showToast({ message: result.problem });
      } else if (atSeq !== undefined && result.id && conversation !== data.conversation && owner === this.sessionId) {
        this.showDockChat({ id: result.id }, '分叉会话');
      } else if (atSeq !== undefined && result.id && this.sessionId === source && this.panel === 'session' &&
        !this.openSessionById(result.id, false)) {
        this.pendingForkId = result.id;
        this.pendingForkSource = source;
      }
    } finally {
      this.forking = false;
    }
  }

  private openSessionById(id: string, notifyMissing: boolean = true): boolean {
    if (this.archivedIds.includes(id)) {
      if (notifyMissing) {
        this.getUIContext().getPromptAction().showToast({ message: '已归档对话暂时无法查看，请取消归档后查看' });
      }
      return false;
    }
    for (const group of this.groups) {
      const row = group.sessions.find((session: SessionListItem): boolean => session.id === id);
      if (row !== undefined) {
        this.selectSession(group, row);
        this.panel = 'session';
        this.revealWorkspace(group.id);
        this.revealSidebarSession(group.id, id);
        return true;
      }
    }
    if (notifyMissing) { this.getUIContext().getPromptAction().showToast({ message: '会话暂不可用' }); }
    return false;
  }

  @Builder
  private AccountDialog(owner: DesktopWorkspaceData, callbackOrigin: string, signOutMode: boolean) {
    DesktopAccountPane({
      host: owner.actions,
      signOutMode: signOutMode,
      callbackOrigin: callbackOrigin,
      appearance: this.appearance,
      localePreference: owner.accountLanguagePreference(),
      dismissRequest: this.accountDismissRequest,
      onState: (state: Object): void => { if (this.data === owner) { owner.completeAccountLogin(state); } },
      onClose: (): void => { this.closeAccount(); },
      onAddKey: (): void => {
        if (this.pageActive && this.data === owner && this.accountKeyHandoff === undefined) {
          this.accountKeyHandoff = owner;
          this.closeAccount(true);
        }
      }
    })
  }

  private async openAccount(signOutMode: boolean): Promise<void> {
    const owner = this.data;
    if (owner === undefined || this.accountOpening || this.accountDialog >= 0 || this.accountOnboarding.visible) {
      return;
    }
    this.accountOpening = true;
    this.accountClosePending = false;
    const callbackOrigin = parseTarget(this.hostUrl)?.address.baseUrl ?? '';
    owner.startAccountUpdates();
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.AccountDialog(owner, callbackOrigin, signOutMode); },
        alignment: DialogAlignment.Center,
        width: Math.max(220, Math.min(440, this.workbenchWidth - 32)),
        autoCancel: false,
        systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onWillDismiss: (action: DismissDialogAction): void => {
          if (action.reason === DismissReason.PRESS_BACK) { this.accountDismissRequest++; }
        },
        onDidDisappear: (): void => { this.accountLoginDisappeared(); }
      });
      if (this.pageActive && !this.accountClosePending && this.data === owner) {
        this.accountDialog = id;
      } else {
        prompt.closeCustomDialog(id);
      }
    } catch (_) {
      if (this.pageActive) {
        prompt.showToast({ message: '无法打开账号弹窗' });
      }
    } finally {
      this.accountOpening = false;
    }
  }

  private accountLoginDisappeared(): void {
    this.accountDialog = -1;
    const owner = this.accountKeyHandoff;
    this.accountKeyHandoff = undefined;
    if (owner !== undefined && this.pageActive && this.data === owner) { this.openAccountKey(owner); }
  }

  @Builder
  private AccountKeyDialog(owner: DesktopWorkspaceData, target: DesktopDeepSeekKeyTarget) {
    DesktopDeepSeekKeyDialog({ host: owner.actions, initialTarget: target, compact: this.workbenchWidth <= 560,
      availableHeight: Math.max(160, this.workbenchHeight - 48), onLater: (): void => { this.closeAccount(); } })
  }

  private async openAccountKey(owner: DesktopWorkspaceData): Promise<void> {
    this.accountOpening = true;
    this.accountClosePending = false;
    const prompt = this.getUIContext().getPromptAction();
    try {
      const target = await readDesktopDeepSeekKeyTarget(owner.actions);
      if (target === undefined || !this.pageActive || this.accountClosePending || this.data !== owner) { return; }
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.AccountKeyDialog(owner, target); },
        alignment: DialogAlignment.Center, width: Math.max(220, Math.min(600, this.workbenchWidth - 48)),
        autoCancel: false, isModal: true, systemMaterial: material,
        maskColor: $r('app.color.desktop_settings_mask'),
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onWillDismiss: (_action: DismissDialogAction): void => {},
        onDidDisappear: (): void => { this.accountDialog = -1; }
      });
      if (this.pageActive && !this.accountClosePending && this.data === owner) { this.accountDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.pageActive && !this.accountClosePending && this.data === owner) {
        prompt.showToast({ message: $r('app.string.desktop_deepseek_setup_open_failed') });
      }
    } finally {
      this.accountOpening = false;
    }
  }

  private updateAccountLauncher(owner: DesktopWorkspaceData, snapshot: DesktopAccountDetailsSnapshot): void {
    if (!snapshot.identity.ready || !this.pageActive || this.data !== owner) { return; }
    this.accountLauncherSignedIn = snapshot.identity.signedIn;
    if (this.accountLauncherProfileRevision === snapshot.profileRevision) { return; }
    this.accountLauncherProfileRevision = snapshot.profileRevision;
    this.accountLauncherName = snapshot.profileLoaded ? snapshot.profile?.name || snapshot.profile?.contact ||
      this.accessibilityLabel($r('app.string.desktop_account_settings_signed_in')) : '';
    this.accountLauncherAvatar = snapshot.profile?.avatarUrl ?? '';
    this.accountLauncherUid = snapshot.profileId;
  }

  private async openAccountFeedback(): Promise<void> {
    const owner = this.data;
    if (!this.pageActive || !this.ready || owner === undefined) { return; }
    const uid = this.accountLauncherUid;
    const facts = readDeviceFacts();
    const reply = await owner.actions.accountContactDocument();
    if (!this.pageActive || this.data !== owner) { return; }
    const href = reply.ok ? desktopAccountContactUrl(reply.value, uid, facts.osFullName,
      facts.screenWidthVp * facts.density, facts.screenHeightVp * facts.density) : '';
    const opened = href ? await openExternalUrl(href) : false;
    if (!opened && this.pageActive && this.data === owner) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_account_settings_open_failed') });
    }
  }

  private closeAccount(preserveKeyHandoff: boolean = false): void {
    if (!preserveKeyHandoff) { this.accountKeyHandoff = undefined; }
    this.accountClosePending = true;
    if (this.accountDialog >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.accountDialog);
    }
  }

  private showAccountOnboarding(view: DesktopOnboardingView): void {
    if (!this.pageActive) { return; }
    const previous = this.accountOnboarding.visible;
    if (view.visible && !previous) {
      this.closeAccount();
      this.closeSettings();
      this.closeQuotaSurface();
      this.shortcutsOpen = false;
    }
    this.accountOnboarding = view;
    if (!view.visible) {
      this.clearOnboardingBrowser();
      this.showQuotaSurface();
    }
    if (previous !== view.visible) { this.syncReading(); }
  }

  private resetAccountOnboarding(): void {
    this.accountOnboarding = emptyDesktopOnboardingView();
    this.clearOnboardingBrowser();
  }

  private clearOnboardingBrowser(): void {
    clearTimeout(this.onboardingBrowserTimer);
    this.onboardingBrowserTimer = -1;
    this.onboardingBrowser = undefined;
    this.onboardingBrowserLeft = false;
  }

  private async openOnboardingTopUp(href: string): Promise<void> {
    const owner = this.data;
    if (!href || owner === undefined || this.onboardingBrowser !== undefined || !this.accountOnboarding.visible) { return; }
    this.onboardingBrowser = owner;
    this.onboardingBrowserLeft = false;
    const opened = await openExternalUrl(href);
    if (this.onboardingBrowser !== owner) { return; }
    if (!opened) {
      this.clearOnboardingBrowser();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_account_settings_open_failed') });
    } else if (!this.onboardingBrowserLeft) {
      this.onboardingBrowserTimer = setTimeout((): void => {
        if (this.onboardingBrowser === owner && !this.onboardingBrowserLeft) {
          this.clearOnboardingBrowser();
          owner.onboarding.refreshBalance();
        }
      }, 1500);
    }
  }

  private noteOnboardingBrowserFocus(focused: boolean): void {
    if (this.onboardingBrowser === undefined) { return; }
    if (!focused) { this.onboardingBrowserLeft = true; }
    else if (this.onboardingBrowserLeft) {
      const owner = this.onboardingBrowser;
      this.clearOnboardingBrowser();
      if (owner === this.data) { owner.onboarding.refreshBalance(); }
    }
  }

  private showAccountSessionToast(owner: DesktopWorkspaceData, notice: DesktopAccountSessionNotice): void {
    if (!this.pageActive || owner !== this.data) { return; }
    if (notice === DesktopAccountSessionNotice.SESSION_EXPIRED && this.accountSessionToastTimers.has(notice)) { return; }
    const previous = this.accountSessionToastTimers.get(notice);
    if (previous !== undefined) {
      clearTimeout(previous.fade);
      clearTimeout(previous.dismiss);
    }
    const token = ++this.accountSessionToastToken;
    const toast: DesktopAccountSessionToast = { notice: notice, token: token, fading: false };
    this.accountSessionToasts = this.accountSessionToasts.filter((item: DesktopAccountSessionToast): boolean =>
      item.notice !== notice).concat(toast);
    const fade = setTimeout((): void => {
      if (this.data !== owner) { return; }
      this.accountSessionToasts = this.accountSessionToasts.map((item: DesktopAccountSessionToast): DesktopAccountSessionToast =>
        item.token === token ? { notice: item.notice, token: item.token, fading: true } : item);
    }, DESKTOP_QUOTA_TOAST_HOLD_MS);
    const dismiss = setTimeout((): void => {
      if (this.data !== owner || !this.accountSessionToasts.some((item: DesktopAccountSessionToast): boolean =>
        item.token === token)) { return; }
      this.accountSessionToastTimers.delete(notice);
      this.accountSessionToasts = this.accountSessionToasts.filter((item: DesktopAccountSessionToast): boolean =>
        item.token !== token);
    }, DESKTOP_QUOTA_TOAST_HOLD_MS + DESKTOP_QUOTA_TOAST_FADE_MS);
    this.accountSessionToastTimers.set(notice, { fade: fade, dismiss: dismiss });
  }

  private resetAccountSessionToasts(): void {
    this.accountSessionToastTimers.forEach((timers: DesktopAccountSessionToastTimers): void => {
      clearTimeout(timers.fade);
      clearTimeout(timers.dismiss);
    });
    this.accountSessionToastTimers.clear();
    this.accountSessionToasts = [];
  }

  private accountSessionToastFading(token: number): boolean {
    return this.accountSessionToasts.find((item: DesktopAccountSessionToast): boolean => item.token === token)
      ?.fading ?? false;
  }

  private resetQuota(): void {
    this.quotaNotice = undefined;
    this.stopQuotaAccount?.();
    this.stopQuotaAccount = undefined;
    this.quotaAccount = emptyDesktopAccountSettingsIdentity();
    this.releaseQuotaBrowser();
    this.closeQuotaSurface();
  }

  private presentQuota(notice?: DesktopQuotaNotice): void {
    this.closeQuotaSurface();
    this.quotaNotice = notice;
    if (notice === undefined) {
      this.releaseQuotaBrowser();
      return;
    }
    const data = this.data;
    if (notice.code === 'ACCOUNT_QUOTA' && data !== undefined && this.stopQuotaAccount === undefined) {
      this.stopQuotaAccount = data.accountNotices.observeAccount((identity: DesktopAccountSettingsIdentity): void => {
        if (this.data !== data) { return; }
        const signedOut = this.quotaAccount.signedIn && !identity.signedIn;
        this.quotaAccount = identity;
        if (signedOut && this.quotaNotice?.code === 'ACCOUNT_QUOTA') {
          data.dismissQuota(this.quotaNotice.token);
        } else {
          this.showQuotaSurface();
        }
      });
      data.accountNotices.connect();
    }
    this.showQuotaSurface();
  }

  private showQuotaSurface(): void {
    const notice = this.quotaNotice;
    if (notice === undefined || !this.pageActive || !this.pageVisible || !this.accountNoticesWindowShown ||
        this.accountOnboarding.visible ||
        this.quotaBrowserVisit !== undefined || this.quotaDialogToken >= 0 || this.quotaToastToken >= 0) { return; }
    if (notice.code === 'ACCOUNT_QUOTA') {
      if (!this.quotaAccount.ready) { return; }
      if (this.quotaAccount.signedIn && desktopAccountPlatformLink(this.quotaAccount.topUpUrl)) {
        this.openQuotaDialog(notice.token);
        return;
      }
    }
    this.showQuotaToast(notice.token);
  }

  private showQuotaToast(token: number): void {
    this.quotaToastToken = token;
    this.quotaToastFading = false;
    this.quotaFadeTimer = setTimeout((): void => {
      if (this.quotaToastToken === token) { this.quotaToastFading = true; }
    }, DESKTOP_QUOTA_TOAST_HOLD_MS);
    this.quotaToastTimer = setTimeout((): void => { this.data?.dismissQuota(token); },
      DESKTOP_QUOTA_TOAST_HOLD_MS + DESKTOP_QUOTA_TOAST_FADE_MS);
  }

  private closeQuotaSurface(): void {
    clearTimeout(this.quotaFadeTimer);
    clearTimeout(this.quotaToastTimer);
    this.quotaToastToken = -1;
    this.quotaToastFading = false;
    const id = this.quotaDialogId;
    const wasModal = this.quotaDialogToken >= 0;
    this.quotaDialogId = -1;
    this.quotaDialogToken = -1;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
    if (wasModal) { this.syncReading(); }
  }

  @Builder
  private QuotaDialog(owner: DesktopWorkspaceData, token: number) {
    WithTheme({ colorMode: this.workspaceColorMode() }) {
      DesktopAccountQuotaDialog({ onDismiss: (): void => { if (this.data === owner) { owner.dismissQuota(token); } },
        onTopUp: (): void => { if (this.data === owner) { this.openQuotaTopUp(token); } } })
    }
  }

  private async openQuotaDialog(token: number): Promise<void> {
    const owner = this.data;
    if (owner === undefined) { return; }
    this.quotaDialogToken = token;
    this.syncReading();
    const prompt = this.getUIContext().getPromptAction();
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({
        builder: (): void => { this.QuotaDialog(owner, token); }, alignment: DialogAlignment.Center,
        width: Math.max(220, Math.min(380, this.workbenchWidth - 48)), cornerRadius: 16,
        autoCancel: true, isModal: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (this.data === owner && this.quotaDialogToken === token) {
            this.quotaDialogId = -1;
            owner.dismissQuota(token);
          }
        }
      });
      if (this.pageActive && this.data === owner && this.quotaDialogToken === token) { this.quotaDialogId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.data === owner && this.quotaDialogToken === token) {
        this.quotaDialogToken = -1;
        this.syncReading();
        this.showQuotaToast(token);
      }
    }
  }

  private async openQuotaTopUp(token: number): Promise<void> {
    const data = this.data;
    const href = desktopAccountPlatformLink(this.quotaAccount.topUpUrl);
    if (data === undefined || this.quotaNotice?.token !== token || this.quotaBrowserVisit !== undefined || !href) { return; }
    const visit: DesktopQuotaBrowserVisit = {
      notice: token, release: data.holdQuota(token), departed: false, returned: false, launched: false
    };
    this.quotaBrowserVisit = visit;
    this.closeQuotaSurface();
    const opened = await openExternalUrl(href);
    if (this.quotaBrowserVisit !== visit || this.data !== data) { return; }
    if (!opened) {
      this.releaseQuotaBrowser();
      this.showQuotaSurface();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_account_settings_open_failed') });
      return;
    }
    visit.launched = true;
    if (visit.returned) { data.dismissQuota(token); }
    else if (!visit.departed) {
      // Some system handlers open the link without taking focus from the workbench.
      this.quotaBrowserTimer = setTimeout((): void => {
        if (this.quotaBrowserVisit === visit && !visit.departed) { data.dismissQuota(token); }
      }, 1500);
    }
  }

  private noteQuotaBrowserFocus(focused: boolean): void {
    const visit = this.quotaBrowserVisit;
    if (visit === undefined) { return; }
    if (!focused) { visit.departed = true; }
    else if (visit.departed) {
      visit.returned = true;
      if (visit.launched) { this.data?.dismissQuota(visit.notice); }
    }
  }

  private releaseQuotaBrowser(): void {
    clearTimeout(this.quotaBrowserTimer);
    const visit = this.quotaBrowserVisit;
    this.quotaBrowserVisit = undefined;
    visit?.release();
  }

  private sidebarActions(footer: boolean): Array<MenuElement> {
    if (footer) {
      const signedIn = this.accountLauncherSignedIn;
      return [
        { value: $r('app.string.desktop_workspace_settings'), icon: $r('app.media.dsh_account_menu_settings'),
          action: (): void => { this.openSettings(); } },
        { value: $r('app.string.desktop_account_feedback'), icon: $r('app.media.dsh_account_menu_feedback'),
          enabled: this.ready, action: (): void => { this.openAccountFeedback(); } },
        { value: signedIn ? $r('app.string.desktop_account_sign_out') : $r('app.string.desktop_account_sign_in'),
          icon: signedIn ? $r('app.media.dsh_account_menu_sign_out') : $r('app.media.dsh_account_menu_sign_in'),
          enabled: this.ready, action: (): void => { this.openAccount(signedIn); } },
        { value: $r('app.string.desktop_experiment_open_web_home'), action: (): void => { this.openWeb(false); } },
        { value: $r('app.string.desktop_experiment_exit'), action: (): void => { this.openWeb(true); } }
      ];
    }
    return [
      { value: $r('app.string.desktop_workspace_settings'), action: (): void => { this.openSettings(); } },
      { value: $r('app.string.desktop_experiment_schedule'), action: (): void => { this.panel = 'schedule'; } },
      { value: '已归档会话', action: (): void => { this.setArchiveFilter(DesktopArchiveFilter.ONLY); } },
      ...desktopPluginEntryItems(this.ready ? (): void => { this.openPlugins(); } : undefined,
        (): void => { this.createPluginDraft($r('app.string.desktop_plugin_prompt_sidebar')); })
    ];
  }

  private displaySidebarSections(): DesktopSidebarDisplaySection[] {
    return this.sidebarSections().map((section: DesktopSidebarSection): DesktopSidebarDisplaySection => {
      const rows = section.header ? [] : this.visibleSidebarSessions(section.group);
      return { group: section.group, depth: section.depth, header: section.header, rows: rows,
        hidden: section.group.sessions.length - rows.length,
        hasOverflow: !section.header && this.showSidebarOverflow(section.group) };
    });
  }

  private sidebarSectionKey(section: DesktopSidebarDisplaySection): string {
    const group = section.group;
    const title = typeof group.title === 'string' ? group.title : '';
    const rows = section.rows.map((session: SessionListItem): string =>
      JSON.stringify([session.id, session.title, session.running, session.updatedAt, session.blank,
        this.pinned.includes(session.id), this.archivedIds.includes(session.id)]));
    return JSON.stringify([section.depth, section.header, group.id, title, section.hidden, section.hasOverflow, ...rows]);
  }

  private markSidebarVisible(ready: boolean): void {
    if (ready && !this.measured) {
      this.measured = true;
      hilog.warn(DOMAIN, TAG, 'DSHM-TRACE ArkUI 工作区和会话列表可见');
    }
  }

  private async openWeb(leaveExperiment: boolean, action: string = '', session: string = this.sessionId,
    plugin?: DesktopPluginLocation, child?: DesktopSubagentEntry, cordis?: DesktopCordisWebLocation): Promise<void> {
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
      const sessionId = leaveExperiment ? '' : session;
      const workspaceId = !sessionId ? '' : session === this.sessionId ? this.workspaceId :
        this.groups.find((group: DesktopWorkspaceGroup): boolean =>
          group.sessions.some((row: SessionListItem): boolean => row.id === session))?.id ?? '';
      const target: DesktopWebDestination = {
        host: this.hostUrl, sessionId: sessionId, workspaceId: workspaceId, action: action,
        bundle: plugin?.kind === 'package' ? plugin.name : '', plugin: plugin, cordis: cordis
      };
      const subagent = child ?? this.subagentAddresses.get(sessionId) ??
        (sessionId === this.sessionId ? this.selectedSubagent : undefined);
      if (subagent !== undefined && subagent.id === sessionId && subagent.mode !== 'external') {
        target.subagent = { parentSessionId: subagent.parentId, childSessionId: subagent.id, mode: subagent.mode };
      }
      this.webHandoff = leaveExperiment ? '' : JSON.stringify(target);
      hilog.warn(DOMAIN, TAG, 'DSHM-TRACE 从 ArkUI 打开 WebUI');
      await ui.getRouter().replaceUrl({ url: WEB_WORKSPACE_PAGE });
    } catch (_) {
      this.webHandoff = '';
      this.switching = false;
      ui.getPromptAction().showToast({ message: $r('app.string.desktop_experiment_switch_failed') });
    }
  }

  private accessibilityLabel(label: ResourceStr): string {
    return typeof label === 'string' ? label :
      this.getUIContext().getHostContext()?.resourceManager.getStringSync(label) ?? '';
  }

  @Builder
  private IconButton(icon: Resource, label: ResourceStr, action: () => void) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(icon).fontSize(16).fontColor([$r('sys.color.font_secondary')])
    }
    .width(32).height(32).borderRadius(7).backgroundColor(Color.Transparent)
    .focusOnTouch(false).accessibilityText(this.accessibilityLabel(label)).onClick(action)
  }

  @Builder
  private ShortcutLabel(icon: Resource, label: ResourceStr) {
    Row({ space: 8 }) {
      SymbolGlyph(icon).fontSize(16).fontColor([$r('sys.color.font_primary')])
      if (!this.sidebarCollapsed) {
        Text(label).fontSize(14).fontFamily(this.typography.textFamily).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
  }

  @Builder
  private SidebarShortcut(icon: Resource, label: ResourceStr, action: () => void, accent: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      this.ShortcutLabel(icon, label)
    }
    .width('100%').height(accent ? 38 : 34).borderRadius(accent ? 9 : 7)
    .padding({ left: this.sidebarCollapsed ? 0 : 8, right: this.sidebarCollapsed ? 0 : 8 })
    .align(accent || this.sidebarCollapsed ? Alignment.Center : Alignment.Start)
    .backgroundColor(accent ? $r('app.color.workspace_action') : Color.Transparent)
    .focusOnTouch(false).accessibilityText(this.accessibilityLabel(label)).enabled(!this.switching).onClick(action)
  }

  @Builder
  private SidebarMenu(footer: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        if (footer && this.accountLauncherSignedIn) {
          this.AccountLauncherAvatar(this.accountLauncherAvatar)
        } else if (footer) {
          Image($r('app.media.dsh_account_menu_dots')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        } else { this.MenuDots() }
        if (!this.sidebarCollapsed) {
          Text(footer && this.accountLauncherSignedIn ? this.accountLauncherName : $r('app.string.desktop_experiment_more'))
            .fontSize(14).fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    .width('100%').height(footer ? this.sidebarCollapsed ? 36 : this.accountLauncherSignedIn ? 44 : 32 : 34)
    .borderRadius(7).backgroundColor(Color.Transparent)
    .padding({ left: this.sidebarCollapsed ? 0 : 8, right: this.sidebarCollapsed ? 0 : 8 })
    .align(this.sidebarCollapsed ? Alignment.Center : Alignment.Start)
    .focusOnTouch(false)
    .key(footer ? 'desktopSidebarFooterMenu' : 'desktopSidebarPanelMenu')
    .accessibilityText(footer ? $r('app.string.desktop_experiment_footer_menu') :
      $r('app.string.desktop_experiment_more'))
    .bindMenu(this.sidebarActions(footer), desktopMenuOptions(footer ? Placement.TopLeft : Placement.BottomLeft))
  }

  @Builder
  private AccountLauncherAvatar(href: string) {
    Stack() {
      if (href.length > 0) {
        Image(href).width(24).height(24).borderRadius(12).objectFit(ImageFit.Cover).draggable(false).accessibilityLevel('no')
          .onError((): void => { if (this.accountLauncherAvatar === href) { this.accountLauncherAvatar = ''; } })
      } else {
        Image($r('app.media.dsh_settings_account')).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
      }
    }.width(24).height(24).borderRadius(12).backgroundColor($r('app.color.workspace_selection'))
  }

  @Builder
  private MenuDots() {
    Row({ space: 2.5 }) {
      Circle().width(2.5).height(2.5).fill($r('sys.color.font_primary'))
      Circle().width(2.5).height(2.5).fill($r('sys.color.font_primary'))
      Circle().width(2.5).height(2.5).fill($r('sys.color.font_primary'))
    }
    .width(16).justifyContent(FlexAlign.Center)
  }

  @Builder
  private TopBar() {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.MenuDots()
      }
      .width(28).height(24).borderRadius(5).backgroundColor(Color.Transparent).focusOnTouch(false)
      .accessibilityText($r('app.string.desktop_experiment_title'))
      .bindMenu(this.sidebarActions(true), desktopMenuOptions(Placement.BottomLeft))
      Blank()
    }
    .width('100%').height(38).padding({ left: 10, right: 132 })
  }

  private workspaceDragParents(): Map<string, string> {
    return this.sidebarGrouping === DesktopSessionGrouping.TREE ? desktopWorkspaceParents(this.groups) : new Map<string, string>();
  }

  private workspaceTargets(sourceId: string): DesktopWorkspaceDropBand[] {
    const parents = this.workspaceDragParents();
    const owner = parents.get(sourceId);
    const bands = new Map<string, DesktopWorkspaceDropBand>();
    const sections = this.sidebarSections();
    for (const section of sections) {
      const id = section.group.id;
      if (!id || id === sourceId || !section.header || parents.get(id) !== owner) { continue; }
      const area = this.workspaceHeaderBounds.get(id);
      if (area === undefined || Number(area.height) <= 0) { continue; }
      const x = Number(area.globalPosition.x);
      const y = Number(area.globalPosition.y);
      bands.set(id, { id: id, left: x + Math.min(7, section.depth) * 12, right: x + Number(area.width),
        top: y, bottom: y + Number(area.height) });
    }
    for (const section of sections) {
      let band: DesktopWorkspaceDropBand | undefined;
      for (let id: string | undefined = section.group.id; id !== undefined; id = parents.get(id)) {
        band = bands.get(id);
        if (band !== undefined) { break; }
      }
      if (band === undefined) { continue; }
      const groupBand = band;
      if (section.header) {
        this.extendWorkspaceBand(groupBand, this.workspaceHeaderBounds.get(section.group.id));
      } else {
        this.visibleSidebarSessions(section.group).forEach((session: SessionListItem): void => {
          this.extendWorkspaceBand(groupBand, this.sessionRowBounds.get(session.id));
        });
        this.extendWorkspaceBand(groupBand, this.sidebarOverflowBounds.get(section.group.id));
      }
    }
    return Array.from(bands.values());
  }

  private extendWorkspaceBand(band: DesktopWorkspaceDropBand, area?: Area): void {
    if (area === undefined || Number(area.height) <= 0) { return; }
    band.bottom = Math.max(band.bottom, Number(area.globalPosition.y) + Number(area.height));
  }

  private canDragWorkspace(id: string): boolean {
    return this.ready && !this.workspaceBusy && !!id && this.sidebarGrouping !== DesktopSessionGrouping.FLAT &&
      !this.query.trim();
  }

  private beginWorkspaceDrag(event: GestureEvent, group: DesktopWorkspaceGroup): void {
    if (!this.canDragWorkspace(group.id)) { return; }
    this.workspaceDropBands = this.workspaceTargets(group.id);
    this.workspaceDragTitle = this.accessibilityLabel(group.title);
    this.workspaceDragId = group.id;
    this.updateWorkspaceDrag(event);
  }

  private positionSidebarDrag(x: number, y: number): void {
    this.dockDragX = Math.max(0, Math.min(this.workbenchWidth - 160, x + 12));
    this.dockDragY = Math.max(0, Math.min(this.workbenchHeight - 28, y + 9));
  }

  private updateWorkspaceDrag(event: GestureEvent): void {
    if (!this.workspaceDragId) { return; }
    const pointer = event.fingerInfos?.[0] ?? event.fingerList[0];
    if (pointer === undefined) { return; }
    const x = pointer.globalX;
    const y = pointer.globalY;
    this.positionSidebarDrag(x - Number(this.workbenchBounds?.globalPosition.x ?? 0),
      y - Number(this.workbenchBounds?.globalPosition.y ?? 0));
    const band = this.dockAreaContains(this.sidebarListBounds, x, y) ? this.workspaceDropBands.find(
      (item: DesktopWorkspaceDropBand): boolean => x >= item.left && x < item.right && y >= item.top && y < item.bottom) : undefined;
    const after = band !== undefined && y >= (band.top + band.bottom) / 2;
    if (this.workspaceDropCue?.band.id !== band?.id || this.workspaceDropCue?.after !== after) {
      this.workspaceDropCue = band === undefined ? undefined : { band: band, after: after };
    }
  }

  private clearWorkspaceDrag(): void {
    this.workspaceDragId = '';
    this.workspaceDragTitle = '';
    this.workspaceDropCue = undefined;
    this.workspaceDropBands = [];
  }

  private dropWorkspace(event: GestureEvent): void {
    this.updateWorkspaceDrag(event);
    const source = this.workspaceDragId;
    const cue = this.workspaceDropCue;
    this.clearWorkspaceDrag();
    if (cue === undefined || !this.canDragWorkspace(source)) { return; }
    const move = desktopWorkspaceMove(this.groups, this.workspaceDragParents(), source, cue.band.id, cue.after);
    if (move === undefined) { return; }
    const payload: Record<string, Object> = { 'workspaceId': source };
    if (move.beforeId !== undefined) { payload['beforeWorkspaceId'] = move.beforeId; }
    this.manage('workspace/insertBefore', payload);
  }

  private workspaceMarkerY(cue: DesktopWorkspaceDropCue): number {
    const origin = Number(this.workbenchBounds?.globalPosition.y ?? 0);
    const top = Number(this.sidebarListBounds?.globalPosition.y ?? origin);
    const bottom = top + Number(this.sidebarListBounds?.height ?? 0);
    const edge = cue.after ? cue.band.bottom : cue.band.top;
    return Math.min(bottom - 2, Math.max(top, edge - 1)) - origin;
  }

  @Builder
  private WorkspaceDropMarker(cue: DesktopWorkspaceDropCue) {
    Divider().width(Math.max(0, cue.band.right - cue.band.left)).strokeWidth(2)
      .color($r('sys.color.ohos_id_color_activated'))
      .position({ x: cue.band.left - Number(this.workbenchBounds?.globalPosition.x ?? 0),
        y: this.workspaceMarkerY(cue) })
      .zIndex(this.rightDock.floats.length + 1).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }

  @Builder
  private WorkspaceRow(group: DesktopWorkspaceGroup, depth: number) {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Image(this.isExpanded(group.id) ? $r('app.media.dsh_sidebar_folder_open') : $r('app.media.dsh_sidebar_workspace'))
            .width(16).height(16).supportSvg2(true).draggable(false).accessibilityLevel('no')
          Image($r('app.media.dsh_sidebar_workspace_arrow')).width(10).height(10).supportSvg2(true)
            .fillColor($r('sys.color.font_tertiary')).draggable(false).accessibilityLevel('no')
            .rotate({ angle: this.isExpanded(group.id) ? 90 : 0 })
          Text(group.title).fontSize(14).fontFamily(this.typography.textFamily).fontColor($r('sys.color.font_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .layoutWeight(1).height(34).padding({ left: 8, right: 4 }).borderRadius(8)
      .backgroundColor(Color.Transparent).focusOnTouch(false).accessibilityText(this.accessibilityLabel(group.title))
      .priorityGesture(GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.All, distance: 8 }).allowedTypes([SourceTool.MOUSE, SourceTool.TOUCHPAD])
          .onActionStart((event: GestureEvent): void => { this.beginWorkspaceDrag(event, group); })
          .onActionUpdate((event: GestureEvent): void => { this.updateWorkspaceDrag(event); })
          .onActionEnd((event: GestureEvent): void => { this.dropWorkspace(event); })
          .onActionCancel((): void => { this.clearWorkspaceDrag(); }),
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ duration: 320 }).allowedTypes([SourceTool.Finger, SourceTool.Pen]),
          PanGesture({ direction: PanDirection.All, distance: 8 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
            .onActionStart((event: GestureEvent): void => { this.beginWorkspaceDrag(event, group); })
            .onActionUpdate((event: GestureEvent): void => { this.updateWorkspaceDrag(event); })
            .onActionEnd((event: GestureEvent): void => { this.dropWorkspace(event); })
            .onActionCancel((): void => { this.clearWorkspaceDrag(); }))))
      .onClick((): void => this.toggleWorkspace(group.id))
      if (group.id) {
        this.RowMenu('管理工作区 ' + this.accessibilityLabel(group.title), this.workspaceActions(group))
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_sidebar_workspace_new_chat')).width(14).height(14).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
        }.key('desktopWorkspaceNewSession-' + group.id).width(28).height(30).padding(0).borderRadius(7)
          .focusOnTouch(false).enabled(!this.creating)
          .accessibilityText($r('app.string.desktop_sidebar_new_in_workspace', this.accessibilityLabel(group.title)))
          .onClick((): void => { this.newSession(group.id); })
      }
    }
    .width('100%').padding({ left: Math.min(7, depth) * 12 })
    .onAreaChange((_, area: Area): void => { this.workspaceHeaderBounds.set(group.id, area); })
    .onDisAppear((): void => { this.workspaceHeaderBounds.delete(group.id); })
  }

  private canDragSession(session: SessionListItem, archived: boolean): boolean {
    return this.ready && !session.blank && !archived;
  }

  private beginSessionDrag(event: GestureEvent, groupId: string, session: SessionListItem, archived: boolean): void {
    if (!this.canDragSession(session, archived)) { return; }
    this.sessionDrag = { owner: this.sessionId, groupId: groupId, session: session };
    this.updateSessionDrag(event);
  }

  private updateSessionDrag(event: GestureEvent): void {
    const drag = this.sessionDrag;
    if (drag === undefined || drag.owner !== this.sessionId) { return; }
    const pointer = event.fingerInfos?.[0] ?? event.fingerList[0];
    if (pointer === undefined) { return; }
    const x = pointer.globalX - Number(this.workbenchBounds?.globalPosition.x ?? 0);
    const y = pointer.globalY - Number(this.workbenchBounds?.globalPosition.y ?? 0);
    this.positionSidebarDrag(x, y);
    this.sessionDropPane = this.sessionRightDrop(drag, pointer.globalX, pointer.globalY, x, y);
    const insert = this.sidebarSessionDrop(drag, pointer.globalX, pointer.globalY);
    if (insert?.id !== this.sessionInsertion?.id || insert?.after !== this.sessionInsertion?.after) {
      this.sessionInsertion = insert;
    }
  }

  private canDropSessionRight(drag: DesktopSessionDrag): boolean {
    return this.panel === 'session' && !!drag.owner && drag.owner !== drag.session.id;
  }

  private sessionRightDrop(drag: DesktopSessionDrag, globalX: number, globalY: number, x: number, y: number): number {
    if (!this.canDropSessionRight(drag)) { return -1; }
    if (this.rightDock.expanded) {
      return this.rightDock.panes.findIndex((_pane: DesktopDockPane, index: number): boolean =>
        this.dockAreaContains(this.dockPaneBounds.get(index), globalX, globalY));
    }
    const rect = this.sessionDropRect(this.sessionContentBounds, true);
    return x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height ? this.rightDock.focus : -1;
  }

  private sidebarSessionDrop(drag: DesktopSessionDrag, x: number, y: number): DesktopSessionInsertion | undefined {
    if (this.query.trim() || !this.dockAreaContains(this.sidebarListBounds, x, y)) { return undefined; }
    const group = this.visibleGroups.find((item: DesktopWorkspaceGroup): boolean => item.id === drag.groupId);
    if (group === undefined) { return undefined; }
    const pinned = this.pinned.includes(drag.session.id);
    for (const target of this.visibleSidebarSessions(group)) {
      const bounds = this.sessionRowBounds.get(target.id);
      const targetPinned = this.pinned.includes(target.id) && !this.archivedIds.includes(target.id);
      if (target.id === drag.session.id || targetPinned !== pinned || bounds === undefined ||
        !this.dockAreaContains(bounds, x, y)) { continue; }
      return { id: target.id, after: target.blank || y >= Number(bounds.globalPosition.y) + Number(bounds.height) / 2 };
    }
    return undefined;
  }

  private clearSessionDrag(): void {
    this.sessionDrag = undefined;
    this.sessionDropPane = -1;
    this.sessionInsertion = undefined;
  }

  private dropSession(event: GestureEvent): void {
    this.updateSessionDrag(event);
    const drag = this.sessionDrag;
    const pane = this.sessionDropPane;
    const insert = this.sessionInsertion;
    this.clearSessionDrag();
    if (drag === undefined || drag.owner !== this.sessionId || this.archivedIds.includes(drag.session.id)) { return; }
    const session = this.sessionSummaries.find((row: SessionListItem): boolean => row.id === drag.session.id);
    if (session === undefined || session.blank) { return; }
    if (pane >= 0 && this.canDropSessionRight(drag)) {
      this.showDockChat({ id: session.id, subagent: desktopSubagentFromSummary(session) }, session.title, pane);
    } else if (insert !== undefined) {
      this.reorderSidebarSession(drag, insert);
    }
  }

  private reorderSidebarSession(drag: DesktopSessionDrag, insert: DesktopSessionInsertion): void {
    const group = this.visibleGroups.find((item: DesktopWorkspaceGroup): boolean => item.id === drag.groupId);
    const flat = this.sidebarGrouping === DesktopSessionGrouping.FLAT;
    const members = flat ? this.sessionSummaries : this.groups.find((item: DesktopWorkspaceGroup): boolean =>
      item.id === drag.groupId)?.sessions;
    if (group === undefined || members === undefined) { return; }
    const archived = new Set<string>(this.archivedIds);
    const account = desktopSessionAccount(this.sidebarGrouping, drag.groupId);
    const order = this.orderedSidebarSessions(this.eligibleSidebarSessions(members), account, archived);
    const next = desktopReorderSessions(order, this.visibleSidebarSessions(group), drag.session.id, insert,
      new Set<string>(this.pinned), archived);
    if (next === undefined) { return; }
    if (this.sidebarOrdering !== DesktopSessionOrdering.MANUAL) { this.manualOrders = this.snapshotSessionOrders(); }
    this.manualOrders.set(account, next);
    this.sidebarOrdering = DesktopSessionOrdering.MANUAL;
    this.filterGroups();
    this.saveSidebarView();
  }

  private sessionDropRect(bounds: Area | undefined, collapsed: boolean): DesktopDockRect {
    const width = Number(bounds?.width ?? 0);
    const openWidth = this.dockAutoFullscreen() ? width : Math.min(width, this.dockWidth());
    const inset = collapsed ? width - openWidth : 0;
    return {
      x: Number(bounds?.globalPosition.x ?? 0) - Number(this.workbenchBounds?.globalPosition.x ?? 0) + inset,
      y: Number(bounds?.globalPosition.y ?? 0) - Number(this.workbenchBounds?.globalPosition.y ?? 0),
      width: width - inset, height: Number(bounds?.height ?? 0)
    };
  }

  @Builder
  private SessionDropZone(index: number, rect: DesktopDockRect, quiet: boolean) {
    if (rect.width > 0 && rect.height > 0) {
      Stack() {
        if (!quiet || this.sessionDropPane === index) {
          Column({ space: 8 }) {
            Image($r('app.media.dsh_sidebar_panel_outline')).width(20).height(20).rotate({ angle: 180 })
              .supportSvg2(true).draggable(false)
              .fillColor($r('sys.color.font_secondary')).accessibilityLevel('no')
            Text($r('app.string.desktop_session_drop')).fontSize(13).fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_secondary'))
          }.width('100%').height('100%').padding(12).justifyContent(FlexAlign.Center)
            .borderRadius(12).border({ width: 1.5, style: BorderStyle.Dashed,
              color: this.sessionDropPane === index ? $r('sys.color.ohos_id_color_activated') :
                $r('app.color.workspace_border') })
            .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : Color.Transparent)
            .systemMaterial(controlMaterial())
        }
      }.key('desktopSessionDrop-' + index).width(rect.width).height(rect.height).padding(8)
        .position({ x: rect.x, y: rect.y }).zIndex(this.rightDock.floats.length + 1)
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
    }
  }

  private sidebarSessionTime(session: SessionListItem): ResourceStr {
    const age = desktopSidebarAge(session.updatedAt || session.createdAt || Date.now(), Date.now());
    switch (age.unit) {
      case DesktopSidebarAgeUnit.MINUTES: return $r('app.string.desktop_sidebar_time_minutes', age.count);
      case DesktopSidebarAgeUnit.HOURS: return $r('app.string.desktop_sidebar_time_hours', age.count);
      case DesktopSidebarAgeUnit.DAYS: return $r('app.string.desktop_sidebar_time_days', age.count);
      case DesktopSidebarAgeUnit.MONTHS: return $r('app.string.desktop_sidebar_time_months', age.count);
      case DesktopSidebarAgeUnit.YEARS: return $r('app.string.desktop_sidebar_time_years', age.count);
      default: return $r('app.string.desktop_sidebar_time_now');
    }
  }

  private sidebarSessionLabel(session: SessionListItem, archived: boolean): ResourceStr {
    if (!archived) {
      switch (this.sidebarPending.get(session.id)) {
        case DesktopSidebarPending.APPROVAL: return $r('app.string.desktop_sidebar_pending_approval');
        case DesktopSidebarPending.QUESTION: return $r('app.string.desktop_sidebar_pending_question');
        case DesktopSidebarPending.PLAN_REVIEW: return $r('app.string.desktop_sidebar_pending_plan');
      }
    }
    return this.sidebarSessionTime(session);
  }

  private sidebarSessionDescription(session: SessionListItem, archived: boolean): string {
    if (archived) { return this.accessibilityLabel($r('app.string.desktop_sidebar_session_archived')); }
    if (session.blank) { return ''; }
    const parts: string[] = [];
    if (this.sidebarPending.has(session.id)) {
      parts.push(this.accessibilityLabel(this.sidebarSessionLabel(session, false)));
    }
    if (session.running) { parts.push(this.accessibilityLabel($r('app.string.desktop_sidebar_session_running'))); }
    const children = this.runningSidebarChildren.get(session.id) ?? 0;
    if (children > 0) {
      const title = this.getUIContext().getHostContext()?.resourceManager.getStringSync(
        $r('app.string.desktop_sidebar_children_running'), children);
      if (title !== undefined) { parts.push(title); }
    }
    const unread = this.unreadSession(session.id);
    if (unread !== undefined) {
      parts.push(this.accessibilityLabel(unread.failed ? $r('app.string.desktop_sidebar_session_failed') :
        $r('app.string.desktop_sidebar_session_unread')));
    }
    return parts.join(' · ');
  }

  @Builder
  private SidebarSessionDot(session: SessionListItem, archived: boolean) {
    Stack() {
      if (!archived && !session.blank) {
        if (this.sidebarPending.has(session.id)) {
          Circle().width(7).height(7).fill($r('sys.color.warning')).key('desktopSessionPending-' + session.id)
        } else if (session.running || this.runningSidebarChildren.has(session.id)) {
          LoadingProgress().width(13).height(13).color($r('sys.color.brand')).key('desktopSessionRunning-' + session.id)
        } else if (this.unreadSession(session.id) !== undefined) {
          Circle().width(7).height(7).fill(this.unreadSession(session.id)?.failed === true ?
            $r('app.color.workspace_status_error') : $r('sys.color.brand')).key('desktopSessionUnread-' + session.id)
        }
      }
    }.width(14).accessibilityLevel('no')
  }

  @Builder
  private SessionRow(groupId: string, depth: number, session: SessionListItem, archived: boolean) {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          this.SidebarSessionDot(session, archived)
          Text(this.sessionLabel(session)).fontSize(14).fontFamily(this.typography.textFamily).fontColor(archived ?
            $r('sys.color.font_tertiary') : $r('sys.color.font_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!session.blank) {
            Text(this.sidebarSessionLabel(session, archived)).key('desktopSessionTrailing-' + session.id)
              .fontSize(11).fontColor(!archived && this.sidebarPending.has(session.id) ?
                $r('sys.color.font_secondary') : $r('sys.color.font_tertiary')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 76 }).accessibilityLevel('no')
          }
          if (!archived && this.pinned.includes(session.id)) {
            Image($r('app.media.dsh_session_pin_fill')).width(14).height(14).supportSvg2(true)
              .draggable(false).accessibilityText('已置顶')
          }
        }
        .width('100%')
      }
      .layoutWeight(1).height(32).padding({ left: 10, right: 4 }).borderRadius(8)
      .backgroundColor(Color.Transparent).focusOnTouch(false)
      .accessibilityText(this.accessibilityLabel(this.sessionLabel(session)))
      .accessibilityDescription(this.sidebarSessionDescription(session, archived))
      .accessibilitySelected(this.sessionId === session.id)
      .priorityGesture(GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.All, distance: 8 }).allowedTypes([SourceTool.MOUSE, SourceTool.TOUCHPAD])
          .onActionStart((event: GestureEvent): void => { this.beginSessionDrag(event, groupId, session, archived); })
          .onActionUpdate((event: GestureEvent): void => { this.updateSessionDrag(event); })
          .onActionEnd((event: GestureEvent): void => { this.dropSession(event); })
          .onActionCancel((): void => { this.clearSessionDrag(); }),
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ duration: 320 }).allowedTypes([SourceTool.Finger, SourceTool.Pen]),
          PanGesture({ direction: PanDirection.All, distance: 8 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
            .onActionStart((event: GestureEvent): void => { this.beginSessionDrag(event, groupId, session, archived); })
            .onActionUpdate((event: GestureEvent): void => { this.updateSessionDrag(event); })
            .onActionEnd((event: GestureEvent): void => { this.dropSession(event); })
            .onActionCancel((): void => { this.clearSessionDrag(); }))))
      .onClick((): void => { this.openSessionById(session.id); })
      if (archived) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_session_unarchive_outline')).width(14).height(14).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
        }.key('desktopRestoreSession-' + session.id).width(30).height(30).padding(0).borderRadius(7)
          .enabled(!this.workspaceBusy).focusOnTouch(false).accessibilityText('取消归档')
          .onClick((): void => { this.restoreSession(session.id); })
      }
      if (!session.blank) {
        // Bind in the row's render scope so selection and reading changes refresh its actions.
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          this.MenuDots()
        }
        .key('desktopSessionMenu-' + session.id).width(32).height(32).borderRadius(7)
        .backgroundColor(Color.Transparent).focusOnTouch(false).enabled(!this.workspaceBusy)
        .accessibilityText('管理会话 ' + this.accessibilityLabel(this.sessionLabel(session)))
        .bindMenu(this.sessionActions(session), desktopMenuOptions(Placement.BottomRight))
      }
    }
    .width('100%').borderRadius(8).padding({ left: Math.min(7, depth) * 12 })
    .border({ width: { top: this.sessionInsertion?.id === session.id && !this.sessionInsertion?.after ? 2 : 0,
      bottom: this.sessionInsertion?.id === session.id && this.sessionInsertion?.after ? 2 : 0 },
      color: $r('sys.color.ohos_id_color_activated') })
    .backgroundColor(this.sessionId === session.id ? $r('app.color.workspace_selection') : Color.Transparent)
    .onAreaChange((_, area: Area): void => { this.sessionRowBounds.set(session.id, area); })
    .onDisAppear((): void => { this.sessionRowBounds.delete(session.id); })
  }

  @Builder
  private RowMenu(label: string, actions: MenuElement[]) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      this.MenuDots()
    }
    .width(32).height(32).borderRadius(7).backgroundColor(Color.Transparent)
    .focusOnTouch(false).accessibilityText(label).enabled(!this.workspaceBusy)
    .bindMenu(actions, desktopMenuOptions(Placement.BottomRight))
  }

  @Builder
  private RenameDialog() {
    Column({ space: 12 }) {
      Text(this.renameWorkspace ? '重命名工作区' : '重命名会话').fontSize(20).fontWeight(FontWeight.Medium)
      TextInput({ text: this.renameDraft, placeholder: '名称' }).key('desktopWorkspaceRenameInput').defaultFocus(true)
        .onChange((value: string): void => { this.renameDraft = value; })
        .onSubmit((): void => { this.rename(); })
      Row({ space: 8 }) {
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.workspaceBusy)
          .onClick((): void => { this.closeRename(); })
        Button('保存').enabled(!this.workspaceBusy && this.renameDraft.trim().length > 0)
          .onClick((): void => { this.rename(); })
      }
    }
    .width('100%').padding(22)
  }

  @Builder
  private SidebarViewMenu() {
    Menu() {
      MenuItemGroup({ header: $r('app.string.desktop_sidebar_group_by') }) {
        MenuItem({ content: $r('app.string.desktop_sidebar_group_workspace'), startIcon: $r('app.media.dsh_sidebar_workspace') })
          .key('desktopSidebarGroupWorkspace').selectIcon(true).selected(this.sidebarGrouping === DesktopSessionGrouping.WORKSPACE)
          .onChange((): void => { this.setSidebarGrouping(DesktopSessionGrouping.WORKSPACE); })
        MenuItem({ content: $r('app.string.desktop_sidebar_group_tree'), startIcon: $r('app.media.dsh_sidebar_tree') })
          .key('desktopSidebarGroupTree').selectIcon(true).selected(this.sidebarGrouping === DesktopSessionGrouping.TREE)
          .onChange((): void => { this.setSidebarGrouping(DesktopSessionGrouping.TREE); })
        MenuItem({ content: $r('app.string.desktop_sidebar_group_flat'), startIcon: $r('app.media.dsh_sidebar_flat') })
          .key('desktopSidebarGroupFlat').selectIcon(true).selected(this.sidebarGrouping === DesktopSessionGrouping.FLAT)
          .onChange((): void => { this.setSidebarGrouping(DesktopSessionGrouping.FLAT); })
      }
      MenuItemGroup({ header: $r('app.string.desktop_sidebar_order_by') }) {
        MenuItem({ content: $r('app.string.desktop_sidebar_order_manual'), startIcon: $r('app.media.dsh_sidebar_manual') })
          .key('desktopSidebarOrderManual').selectIcon(true).selected(this.sidebarOrdering === DesktopSessionOrdering.MANUAL)
          .onChange((): void => { this.setSidebarOrdering(DesktopSessionOrdering.MANUAL); })
        MenuItem({ content: $r('app.string.desktop_sidebar_order_updated'), startIcon: $r('app.media.dsh_sidebar_updated') })
          .key('desktopSidebarOrderUpdated').selectIcon(true).selected(this.sidebarOrdering === DesktopSessionOrdering.UPDATED)
          .onChange((): void => { this.setSidebarOrdering(DesktopSessionOrdering.UPDATED); })
      }
      MenuItemGroup({ header: $r('app.string.desktop_sidebar_filter_by') }) {
        MenuItem({ content: $r('app.string.desktop_sidebar_filter_hidden'), startIcon: $r('app.media.dsh_session_archive_off_outline') })
          .key('desktopSidebarArchiveHide').selectIcon(true).selected(this.archiveFilter === DesktopArchiveFilter.HIDE)
          .onChange((): void => { this.setArchiveFilter(DesktopArchiveFilter.HIDE); })
        MenuItem({ content: $r('app.string.desktop_sidebar_filter_all'), startIcon: $r('app.media.dsh_queue_queue_outline') })
          .key('desktopSidebarArchiveAll').selectIcon(true).selected(this.archiveFilter === DesktopArchiveFilter.ALL)
          .onChange((): void => { this.setArchiveFilter(DesktopArchiveFilter.ALL); })
        MenuItem({ content: $r('app.string.desktop_sidebar_filter_only'), startIcon: $r('app.media.dsh_session_archive_check_outline') })
          .key('desktopSidebarArchiveOnly').selectIcon(true).selected(this.archiveFilter === DesktopArchiveFilter.ONLY)
          .onChange((): void => { this.setArchiveFilter(DesktopArchiveFilter.ONLY); })
      }
    }
  }

  @Builder
  private WorkspaceSearchButton() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image($r('app.media.dsh_workspace_search_outline')).width(this.sidebarCollapsed ? 18 : 14)
        .height(this.sidebarCollapsed ? 18 : 14).supportSvg2(true).accessibilityLevel('no')
    }.key('desktopWorkspaceSearchToggle').width(this.sidebarCollapsed ? 36 : 32).height(this.sidebarCollapsed ? 36 : 32)
      .padding(0).borderRadius(7).focusOnTouch(false).enabled(this.ready)
      .accessibilityText($r('app.string.desktop_experiment_search')).onClick((): void => { this.focusSearch(); })
  }

  @Builder
  private WorkspaceSearchField() {
    Row({ space: 5 }) {
      Image($r('app.media.dsh_workspace_search_outline')).width(11).height(11)
        .supportSvg2(true).accessibilityLevel('no')
      TextInput({ text: this.query, placeholder: $r('app.string.desktop_workspace_search_placeholder') })
        .key('desktopWorkspaceSearch').height(32).layoutWeight(1).fontSize(14).maxLength(500)
        .padding(0).backgroundColor(Color.Transparent)
        .onChange((value: string): void => { this.query = desktopWorkspaceSearchQuery(value); })
        .onBlur((): void => { if (!this.query.trim()) { this.closeSearch(); } })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
            this.closeSearch();
            event.stopPropagation();
            return true;
          }
          return false;
        })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_workspace_search_clear')).width(14).height(14)
          .supportSvg2(true).accessibilityLevel('no')
      }.key('desktopWorkspaceSearchClear').width(26).height(26).padding(0).borderRadius(6).focusOnTouch(false)
        .accessibilityText($r('app.string.desktop_workspace_search_clear')).onClick((): void => { this.closeSearch(); })
    }.width('100%').height(32).margin({ top: 14 }).padding({ left: 9, right: 4 }).borderRadius(8)
      .backgroundColor($r('app.color.workspace_selection'))
  }

  @Builder
  private WorkspaceTree() {
    if (this.searchOpen) {
      this.WorkspaceSearchField()
    } else {
      Row() {
        Text(this.sidebarGrouping === DesktopSessionGrouping.FLAT ? $r('app.string.desktop_sidebar_sessions') :
          $r('app.string.desktop_experiment_workspaces'))
          .fontSize(14).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_session_sliders_two_outline')).width(16).height(16)
            .supportSvg2(true).accessibilityLevel('no')
        }.key('desktopWorkspaceArchiveFilter').width(32).height(32).padding(0).borderRadius(7)
          .focusOnTouch(false).accessibilityText('视图选项').enabled(this.ready)
          .bindMenu(this.SidebarViewMenu, desktopMenuOptions(Placement.BottomRight))
        this.WorkspaceSearchButton()
        this.IconButton($r('sys.symbol.plus'), $r('app.string.desktop_experiment_add_workspace'),
          (): void => { this.addWorkspace(); })
      }
      .width('100%').padding({ left: 8 }).margin({ top: 14 })
    }
    if (this.ready && this.query.trim().length > 0) {
      DesktopWorkspaceSearchResults({ host: this.data?.actions, query: this.query, sessions: this.sessionSummaries,
        groups: this.groups, archiveFilter: this.archiveFilter, archivedIds: this.archivedIds, selectedId: this.sessionId,
        restoreEnabled: !this.workspaceBusy,
        onOpen: (id: string): void => { this.openSearchResult(id); },
        onRestore: (id: string): void => { this.restoreSession(id); } })
    } else if (this.ready) {
      List({ space: 2 }) {
        ForEach(this.displaySidebarSections(), (section: DesktopSidebarDisplaySection): void => {
          if (section.header) {
            ListItem() { this.WorkspaceRow(section.group, section.depth) }
          } else {
            ForEach(section.rows, (session: SessionListItem): void => {
              ListItem() {
                this.SessionRow(section.group.id, section.depth, session, this.archivedIds.includes(session.id))
              }
            }, (session: SessionListItem): string => session.id)
            if (section.hasOverflow) {
              ListItem() {
                Button(section.hidden > 0 ? $r('app.string.desktop_sidebar_show_more', section.hidden) :
                  $r('app.string.desktop_sidebar_show_less'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .key('desktopSidebarOverflow-' + section.group.id).width('100%').height(30)
                  .padding({ left: 24 + Math.min(7, section.depth) * 12, right: 8 }).align(Alignment.Start)
                  .fontSize(12).fontColor($r('sys.color.font_secondary')).focusOnTouch(false)
                  .onClick((): void => { this.toggleSidebarOverflow(section.group); })
                  .onAreaChange((_, area: Area): void => { this.sidebarOverflowBounds.set(section.group.id, area); })
                  .onDisAppear((): void => { this.sidebarOverflowBounds.delete(section.group.id); })
              }
            }
          }
        }, (section: DesktopSidebarDisplaySection): string => this.sidebarSectionKey(section))
        if (this.visibleGroups.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([$r('sys.color.font_tertiary')])
              if (!this.query && this.archiveFilter === DesktopArchiveFilter.ONLY) {
                Text('暂无已归档会话').fontSize(14).fontColor($r('sys.color.font_secondary'))
                Button('查看其他会话', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .onClick((): void => { this.setArchiveFilter(DesktopArchiveFilter.HIDE); })
              } else {
                Text(this.query.length > 0 ? $r('app.string.desktop_experiment_search_empty') :
                  $r('app.string.desktop_experiment_empty')).fontSize(14).fontColor($r('sys.color.font_secondary'))
              }
            }
            .width('100%').padding({ top: 36, bottom: 24 })
          }
        }
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      .enableScrollInteraction(this.sessionDrag === undefined && !this.workspaceDragId)
      .onAreaChange((_, area: Area): void => { this.sidebarListBounds = area; })
      .onVisibleAreaChange([0], (visible: boolean): void => this.markSidebarVisible(visible))
    } else {
      Text(this.error || this.hostError || $r('app.string.desktop_experiment_loading'))
        .width('100%').padding({ left: 8, right: 8, top: 12 })
        .fontSize(13).fontColor($r('sys.color.font_secondary'))
      if (this.error.length > 0 && this.hostUrl.length > 0) {
        this.SidebarShortcut($r('sys.symbol.arrow_clockwise'), $r('app.string.desktop_experiment_retry'),
          (): void => this.onHostChanged(), false)
      }
      Blank()
    }
  }

  @Builder
  private Sidebar() {
    Stack({ alignContent: Alignment.BottomStart }) {
      this.SidebarContent()
      if (!this.sidebarCollapsed && this.pageVisible && this.accountNoticesWindowShown &&
        this.accountDialog < 0 && this.accountNotices.length > 0) {
        Column() {
          ForEach(this.accountNotices.slice(0, 1), (notice: DesktopAccountNotice): void => {
            DesktopAccountNoticeCard({ notice: notice, behind: this.accountNotices.length - 1,
              copyHeight: Math.max(80, this.workbenchHeight * 0.4),
              onDisplayed: (id: string): void => {
                if (this.pageVisible && this.accountNoticesWindowShown && this.accountDialog < 0) {
                  this.data?.accountNotices.reportDisplayed(id);
                }
              },
              onAccount: (id: string): void => {
                if (this.data?.accountNotices.openAccount(id)) { this.openSettings('account'); }
              },
              onDismiss: (id: string): void => { this.data?.accountNotices.dismiss(id); }
            })
          }, (notice: DesktopAccountNotice): string => notice.id)
        }.width(Math.min(280, this.sidebarWidth - 20)).margin({ left: 10, bottom: this.accountLauncherSignedIn ? 58 : 48 })
      }
    }.width(this.sidebarCollapsed ? 52 : this.sidebarWidth).height('100%')
  }

  @Builder
  private SidebarContent() {
    Column({ space: 2 }) {
      Row({ space: 9 }) {
        if (!this.sidebarCollapsed) {
          Image($r('app.media.logo_dark')).width(24).height(24).objectFit(ImageFit.Contain)
          Text($r('app.string.app_name')).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        }
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.sidebar_toggle')).width(16).height(16).fillColor($r('sys.color.font_secondary'))
        }
        .width(32).height(32).borderRadius(7).backgroundColor(Color.Transparent).focusOnTouch(false)
        .accessibilityText(this.sidebarCollapsed ? $r('app.string.desktop_experiment_expand_sidebar') :
          $r('app.string.desktop_experiment_collapse_sidebar'))
        .onClick((): void => { this.sidebarCollapsed = !this.sidebarCollapsed; })
      }
      .width('100%').height(64).padding({ left: this.sidebarCollapsed ? 0 : 6 })
      .justifyContent(this.sidebarCollapsed ? FlexAlign.Center : FlexAlign.Start)
      this.SidebarShortcut($r('sys.symbol.plus_circle'), $r('app.string.action_new_session'),
        (): void => { this.newSession(); }, true)
      Blank().height(12)
      this.SidebarShortcut($r('sys.symbol.square_grid_2x2'), $r('app.string.desktop_experiment_plugins'),
        (): void => { this.openPlugins(); }, false)
      this.SidebarShortcut($r('sys.symbol.clock'), $r('app.string.desktop_experiment_schedule'),
        (): void => { this.panel = 'schedule'; }, false)
      this.SidebarShortcut($r('sys.symbol.gearshape'), $r('app.string.desktop_workspace_settings'),
        (): void => { this.openSettings(); }, false)
      this.SidebarMenu(false)
      if (!this.sidebarCollapsed) {
        this.WorkspaceTree()
      } else {
        this.WorkspaceSearchButton()
        Blank()
      }
      if (this.ready && this.data !== undefined) {
        DesktopCordisControl({
          runtime: this.data.cordis, sessionId: this.sessionId, collapsed: this.sidebarCollapsed,
          onWeb: (session: string, location: DesktopCordisWebLocation): void => {
            this.openWeb(false, 'cordis', session, undefined, undefined, location);
          }
        })
      }
      this.SidebarMenu(true)
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.sidebarCollapsed ? 8 : 10, right: this.sidebarCollapsed ? 8 : 10, bottom: 8 })
    .backgroundColor($r('app.color.workspace_sidebar'))
    .border({ width: { right: 1 }, color: $r('app.color.workspace_border') })
  }

  @Builder
  private SessionContent() {
    Row() {
      if (this.sessionId.length > 0) {
        DesktopConversationPane({
          developerTools: this.codingTools.enabled,
          host: this.data?.actions, replyMedia: this.replyMedia,
          cordis: this.data?.cordis,
          snapshot: this.chat,
          onTimelineReceipt: (owner: string, tree: string, task: string): void => {
            this.requestTimeline(owner, tree, task);
          },
          sessionSummaries: this.sessionSummaries,
          onSubagent: (entry: DesktopSubagentEntry, parents: DesktopSubagentEntry[]): void => {
            this.openSubagent(entry, parents);
          },
          onSubagentAside: (entry: DesktopSubagentEntry, parents: DesktopSubagentEntry[]): void => {
            this.openSubagent(entry, parents, true);
          },
          onSubagentParent: (child: DesktopSubagentEntry): void => { this.openSubagentParent(child); },
          interactions: this.interactions,
          onDecision: (id: string, allow: boolean): void => {
            const interactions = this.data?.interactions;
            if (interactions !== undefined) {
              this.chatAction((): Promise<string> => interactions.approve(id, allow));
            }
          },
          onAnswer: (id: string, answers: DesktopQuestionAnswer[]): void => {
            const interactions = this.data?.interactions;
            if (interactions !== undefined) {
              this.chatAction((): Promise<string> => interactions.answer(id, answers));
            }
          },
          onQuestionProgress: (id: string, progress: DesktopQuestionProgress, engage: boolean): void => {
            this.data?.interactions.saveQuestion(id, progress, engage);
          },
          onQuestionHold: (id: string): void => { this.data?.interactions.holdQuestion(id); },
          onQuestionFocus: (id: string, focused: boolean): void => {
            this.data?.interactions.setQuestionFocus(id, focused);
          },
          onQuestionClose: (id: string): void => {
            const interactions = this.data?.interactions;
            if (interactions !== undefined) { this.chatAction((): Promise<string> => interactions.closeQuestion(id)); }
          },
          onQuestionResume: (id: string): void => { this.data?.interactions.reopenQuestion(id); },
          onPlanDecision: (id: string, approve: boolean): void => {
            const interactions = this.data?.interactions;
            if (interactions !== undefined) {
              this.chatAction((): Promise<string> => approve ?
                interactions.approvePlanReview(id) : interactions.dismissPlanReview(id));
            }
          },
          onPlanMode: (enabled: boolean): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined) {
              this.chatAction((id: string): Promise<string> => conversation.togglePlanMode(id, enabled));
            }
          },
          onTeamMode: (id: string, enabled: boolean): Promise<string> =>
            this.data?.conversation.setTeamMode(id, enabled) ?? Promise.resolve('当前会话暂不可操作'),
          onGoalAction: (action: DesktopGoalAction, ref: DesktopGoalRef, objective: string): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.mutateGoal(id, action, ref, objective));
          },
          onPlanPreview: (plan: DesktopPlanDocument): void => { this.showPlan(plan); },
          onOpenCompaction: (sequence: number, isCurrent: () => boolean): Promise<ResourceStr | undefined> =>
            this.openCompaction({ id: this.sessionId, subagent: this.chat?.subagent }, sequence, isCurrent),
          onBrowsePlugins: (): void => { this.openPlugins(); },
          onCreatePlugin: (): void => { this.createPluginDraft($r('app.string.desktop_plugin_prompt_conversation')); },
          onPlanResume: (id: string): void => { this.data?.interactions.reopenPlanReview(id); },
          onArtifactFile: (path: string, name: string): void => { this.showArtifact(path, name); },
          onReferenceFileAction: (action: DesktopReferenceAction, path: string, name: string): void => {
            this.referenceFileAction(action, path, name);
          },
          onArtifactAction: (path: string, name: string, reveal: boolean): void => { this.openArtifactAction(path, name, reveal); },
          onChanges: (target: DesktopChangeTarget): void => { this.showChanges(target); },
          title: this.selectedTitle,
          workspaceTitle: this.selectedWorkspaceTitle,
          sessionDirectory: this.selectedSessionDirectory,
          draft: this.draft,
          appearance: this.appearance, typography: this.typography,
          referenceOffer: this.referenceOffer,
          attachments: this.attachments,
          onAddAttachment: (): void => this.attachDocument(),
          onDropAttachments: (files: DesktopDroppedFiles): void => { this.attachDroppedFiles(files); },
          onPasteAttachments: (): void => { this.attachClipboard(); },
          onOpenImage: (row: DesktopMediaAttachment): void => { this.openImagePreview(row); },
          onLink: (href: string): void => this.openConversationLink(href),
          onRemoveAttachment: (receiptId: string): void => {
            this.setAttachments(this.sessionId, this.attachments.filter((file: DesktopDraftAttachment): boolean =>
              file.receiptId !== receiptId));
          },
          busy: this.busySessions.includes(this.sessionId),
          commandError: this.chatError,
          menuOptions: desktopMenuOptions(Placement.TopLeft),
          onDraft: (session: string, value: DesktopComposerDraft): void => this.changeDraft(session, value),
          onSend: (alternateDelivery: boolean): void => this.sendMessage(alternateDelivery),
          onQueueAction: (session: string, id: string, action: QueueActionBody): Promise<string> =>
            this.data?.conversation.updateQueue(session, id, action) ?? Promise.resolve('当前会话暂不可操作'),
          onSteerQueue: (): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined) { this.chatAction((id: string): Promise<string> => conversation.steerQueue(id)); }
          },
          onLoadModels: (refresh: boolean): void => { this.data?.conversation.loadModels(refresh); },
          onModelsSettings: (): void => { this.openSettings('settings.models'); },
          onPluginDetails: (name: string, title: string, description: string): void => {
            this.openPlugins(name, title, description);
          },
          onLoadCommands: (): void => { this.data?.conversation.loadCommands(this.sessionId); },
          onLoadSkills: (): void => { this.data?.conversation.loadSkills(this.sessionId); },
          onCommand: (name: string): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.runCommandChoice(id, name,
                (sessionId: string): Promise<string> => this.exportLog(sessionId)));
          },
          onSelectModel: (selection: ModelSelection): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.selectModel(id, selection));
          },
          onSlashPermission: (preset: string): Promise<string> => {
            const conversation = this.data?.conversation;
            return conversation === undefined ? Promise.resolve('当前会话暂不可操作') : this.chatAction(
              (id: string): Promise<string> => conversation.selectPermission(id, preset));
          },
          onStop: (): void => { this.stopMessage(); },
          stopping: this.stoppingSessions.includes(this.sessionId),
          onContinue: (sequence: number): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined && !this.draft.text.trim() && this.attachments.length === 0) {
              this.chatAction((id: string): Promise<string> => conversation.continueGeneration(id, sequence));
            }
          },
          onEarlier: (): void => this.data?.conversation.loadEarlier(),
          onWeb: (): void => { this.openWeb(false); },
          onCordisWeb: (location: DesktopCordisWebLocation): void => {
            this.openWeb(false, 'cordis', this.sessionId, undefined, undefined, location);
          },
          copyingTranscript: this.copyingTranscript,
          exportingLog: this.exportingLog,
          choosingFeedback: this.choosingFeedback,
          forking: this.forking,
          onFork: (id: string, atSeq: number): void => { this.forkFrom(id, atSeq); },
          onSessionFeedback: (sessionId: string): Promise<string> => this.openSessionFeedback(sessionId),
          onWarmFeedback: (sessionId: string): void => { this.data?.conversation.feedback.ensure(sessionId); },
          onReplyRating: (sessionId: string, messageId: string, rating: DesktopRating): void => {
            this.chooseReplyRating(sessionId, messageId, rating);
          },
          onCopyTranscript: (): void => { this.copyTranscript(); },
          onExportLog: (): void => {
            this.chatAction((id: string): Promise<string> => this.exportLog(id));
          },
          filesOpen: this.dockShows(DesktopDockKind.FILES),
          rightDockOpen: this.rightDock.expanded,
          timelineOpen: this.dockShows(DesktopDockKind.TIMELINE),
          timelineRoot: this.dockShows(DesktopDockKind.TIMELINE) ? this.timelineRoot : '',
          timelineDecimals: this.timelinePreferences.decimals, timelineSegmented: this.timelinePreferences.segmentedProgress,
          onTimelineDockToggle: (owner: string, tree: string): void => { this.toggleTimelineDock(owner, tree); },
          onTimelineDockRemove: (owner: string, tree: string): Promise<boolean> =>
            this.data?.conversation.removeTimelineDraft(owner, tree) ?? Promise.resolve(false),
          onTimeline: (): void => { this.showTimeline(true); },
          onRightDock: (): void => this.toggleRightDock(),
          onFiles: (): void => this.showWorkspaceFiles(true),
          terminalOpen: this.dockShows(DesktopDockKind.TERMINAL),
          onTerminal: (): void => this.showTerminal(false, true),
          onPermission: (preset: string): void => {
            const conversation = this.data?.conversation;
            if (conversation !== undefined) {
              this.chatAction((id: string): Promise<string> => conversation.selectPermission(id, preset));
            }
          }
        })
        .layoutWeight(1).visibility(this.dockFullscreen() ? Visibility.None : Visibility.Visible)
        if (this.data !== undefined && (this.rightDock.expanded || this.rightDock.panes[0].tabs.length > 0 ||
          this.rightDock.panes.length > 1)) {
          if (this.rightDock.expanded && !this.dockFullscreen()) { this.DockResizeHandle(false) }
          Column() { this.RightDock() }
            .width(this.dockFullscreen() ? '100%' : this.dockWidth()).height('100%')
            .visibility(this.rightDock.expanded ? Visibility.Visible : Visibility.None)
        }
      } else {
        this.SessionPane()
      }
    }
    .height('100%').layoutWeight(1)
    .onAreaChange((_, area: Area): void => { this.sessionContentBounds = area; })
  }

  private hasTimeline(): boolean {
    return this.chat?.sessionId === this.sessionId && this.chat?.timeline !== undefined;
  }

  private resetTimelineLocation(): void {
    this.pendingTimelineLocation = undefined;
    this.timelineLocation = undefined;
    this.timelineRoot = '';
    this.timelineObservedTree = undefined;
    this.timelineAutoPending = false;
  }

  private observeTimelineTree(snapshot: DesktopConversationSnapshot): void {
    if (snapshot.sessionId !== this.sessionId || this.timelineObservedTree === true) { return; }
    const trees = getArray(snapshot.timeline?.value, 'trees');
    if (trees === undefined) { return; }
    this.timelineAutoPending = this.timelineObservedTree === false && trees.length > 0;
    this.timelineObservedTree = trees.length > 0;
    this.openFirstTimelineTree();
  }

  private openFirstTimelineTree(): void {
    if (!this.timelineAutoPending || !this.timelinePreferencesReady || this.workbenchBounds === undefined) { return; }
    this.timelineAutoPending = false;
    const trees = this.chat?.sessionId === this.sessionId ? getArray(this.chat?.timeline?.value, 'trees') : undefined;
    if (this.timelinePreferences.autoOpenSidebar && this.workbenchWidth > 768 && this.panel === 'session' &&
        !this.dockShows(DesktopDockKind.TIMELINE) && (trees?.length ?? 0) > 0) {
      this.requestTimeline(this.sessionId, '', '', true);
    }
  }

  private toggleTimelineDock(owner: string, tree: string): void {
    if (owner !== this.sessionId || this.chat?.sessionId !== owner || this.chat?.timelineTree?.id !== tree) { return; }
    if (tree !== this.timelineRoot || !this.dockShows(DesktopDockKind.TIMELINE)) {
      this.requestTimeline(owner, tree, '');
    } else if (this.rightDock.expanded && this.rightDock.panes.some((pane: DesktopDockPane): boolean =>
      pane.active === DesktopDockKind.TIMELINE)) {
      this.toggleRightDock();
    } else {
      this.hideDockTool(DesktopDockKind.TIMELINE);
    }
  }

  private requestTimeline(owner: string, tree: string, task: string, resetReportDetails: boolean = false): void {
    if (!owner || owner !== this.sessionId) { return; }
    this.timelineLocationRevision++;
    this.pendingTimelineLocation = { session: owner, tree: tree, task: task, revision: this.timelineLocationRevision,
      resetReportDetails: resetReportDetails };
    this.openPendingTimeline();
  }

  private openPendingTimeline(): void {
    const location = this.pendingTimelineLocation;
    if (location === undefined || location.session !== this.sessionId || !this.hasTimeline()) { return; }
    this.pendingTimelineLocation = undefined;
    this.timelineLocation = location;
    this.showTimeline();
  }

  private showTimeline(toggle: boolean = false): void {
    if (!this.hasTimeline()) { return; }
    if (toggle && this.dockShows(DesktopDockKind.TIMELINE)) { this.hideDockTool(DesktopDockKind.TIMELINE); return; }
    const tab: DesktopDockTab = { id: DesktopDockKind.TIMELINE, kind: DesktopDockKind.TIMELINE,
      title: this.accessibilityLabel($r('app.string.desktop_timeline_title')) };
    this.setDock(desktopDockOpen(this.rightDock, tab));
  }

  private dockMenu(index: number): MenuElement[] {
    const items: MenuElement[] = [
      { value: '工作区文件', action: (): void => this.openDockTool(index, DesktopDockKind.FILES) },
      { value: '新建终端', action: (): void => this.openDockTool(index, DesktopDockKind.TERMINAL) },
      { value: $r('app.string.desktop_browser_title'), action: (): void => { this.openBrowser(index); } }
    ];
    if (this.hasTimeline()) {
      items.push({ value: $r('app.string.desktop_timeline_title'),
        action: (): void => { this.openDockTool(index, DesktopDockKind.TIMELINE); } });
    }
    if (this.canSplitDock()) {
      items.push({ value: '向右分屏', action: (): void => { this.splitDock(); } });
    } else if (this.rightDock.panes.length === 2) {
      items.push({ value: '合并分屏', action: (): void => { this.setDock(desktopDockMerge(this.rightDock, index)); } });
    }
    return items;
  }

  private openDockTool(index: number, kind: DesktopDockKind): void {
    if (!this.rightDock.panes[index]) { return; }
    const owner = this.rightDock.panes.findIndex((pane: DesktopDockPane): boolean =>
      pane.tabs.some((tab: DesktopDockTab): boolean => tab.kind === kind));
    if (owner >= 0 && owner !== index) {
      this.setDock(desktopDockMoveTab(this.rightDock, owner, kind));
    }
    this.focusDockPane(index);
    if (kind === DesktopDockKind.FILES) { this.showWorkspaceFiles(); }
    else if (kind === DesktopDockKind.TERMINAL) { this.showTerminal(true); }
    else if (kind === DesktopDockKind.TIMELINE) { this.showTimeline(); }
  }

  private launchDockTerminal(index: number, shellPath: string = ''): void {
    if (!this.sessionId || this.data === undefined || this.terminalCreateRequest !== undefined ||
      this.rightDock.panes[index] === undefined) { return; }
    const id = desktopDockResourceId(DesktopDockKind.TERMINAL, 'launch-' + randomUuid());
    const tab: DesktopDockTab = { id: id, kind: DesktopDockKind.TERMINAL,
      title: this.accessibilityLabel($r('app.string.desktop_terminal_chrome_title')), terminalLaunch: true };
    this.setDock(desktopDockOpen(this.rightDock, tab, false, index));
    this.terminalCreateRequest = { sessionId: this.sessionId, tabId: id, shellPath: shellPath };
  }

  private terminalGuideShortcut(): string {
    const binding = this.shortcutBindings.find((row: DesktopShortcutRow): boolean =>
      row.id === DesktopShortcut.NEW_TERMINAL && !row.occupiedBy);
    return binding === undefined ? '' : desktopShortcutLabels(binding.binding).join(' + ');
  }

  private browserOrigin(): string {
    return parseTarget(this.hostUrl)?.address.baseUrl ?? '';
  }

  private openConversationLink(href: string): void {
    const page = desktopBrowserAddress(href, this.browserOrigin(), false);
    if (!page.href) {
      this.getUIContext().getPromptAction().showToast({ message: page.problem });
      return;
    }
    if (this.data?.opensLinksInDock() !== false) {
      this.openBrowser(this.rightDock.focus, page.href, page.title);
    } else {
      openExternalUrl(page.href).then((ok: boolean): void => {
        if (!ok) { this.getUIContext().getPromptAction().showToast({ message: '无法打开系统浏览器' }); }
      });
    }
  }

  private openBrowser(index: number, address: string = '', title: string = '浏览器'): void {
    if (!this.rightDock.panes[index] || !this.sessionId) { return; }
    const id = 'browser:' + Date.now() + ':' + ++this.browserTabCount;
    const tab: DesktopDockTab = { id: id, kind: DesktopDockKind.BROWSER, title: title, browserAddress: address };
    this.setDock(desktopDockOpen(this.rightDock, tab, true, index));
  }

  private dockTabMenu(index: number, tab: DesktopDockTab): MenuElement[] {
    const session = this.sessionId;
    const data = this.data;
    const guarded = (action: () => void): (() => void) => (): void => {
      if (!this.pageActive || this.panel !== 'session' || !this.rightDock.expanded ||
        session !== this.sessionId || data !== this.data || this.dockStoredTab(index, tab.id) === undefined) { return; }
      if (this.isDockTabContext(index, tab.id)) { this.dockTabContext = undefined; }
      action();
    };
    const items: MenuElement[] = [];
    if (this.dockStoredTab(index, tab.id)?.terminalId) {
      items.push({ value: $r('app.string.desktop_terminal_rename_action'), action: guarded((): void => {
        this.startTerminalRename(index, tab.id);
      }) });
    }
    if (this.rightDock.panes.length === 2) {
      items.push({ value: '移到另一侧', action: guarded((): void => {
        this.setDock(desktopDockMoveTab(this.rightDock, index, tab.id));
      }) });
    } else if (this.canSplitDock()) {
      items.push({ value: '向右分屏', action: guarded((): void => {
        if (!this.canSplitDock()) { return; }
        const next = desktopDockMoveTab(desktopDockSplit(this.rightDock), index, tab.id);
        this.setDock(next);
      }) });
    }
    items.push({ value: '浮动面板', action: guarded((): void => {
      this.floatDockTab(index, tab.id, this.defaultFloatRect());
    }) });
    const tabs = this.rightDock.panes[index]?.tabs ?? [];
    const position = tabs.findIndex((item: DesktopDockTab): boolean => item.id === tab.id);
    const others = tabs.filter((item: DesktopDockTab): boolean => item.id !== tab.id);
    const right = position < 0 ? [] : tabs.slice(position + 1);
    items.push({ value: $r('app.string.desktop_dock_close_tab'), icon: $r('app.media.dsh_dock_close'),
      action: guarded((): void => this.closeDockTab(index, tab.id)) });
    items.push({ value: $r('app.string.desktop_dock_close_others'), enabled: others.length > 0,
      action: guarded((): void => this.closeDockTabs(index, others)) });
    if (right.length > 0) {
      items.push({ value: $r('app.string.desktop_dock_close_right'),
        action: guarded((): void => this.closeDockTabs(index, right)) });
    }
    return items;
  }

  private closeDockTabs(pane: number, targets: DesktopDockTab[]): void {
    for (const target of targets) {
      const tab = this.dockStoredTab(pane, target.id);
      if (tab !== undefined && tab.terminalId === target.terminalId) { this.closeDockTab(pane, target.id); }
    }
  }

  private isDockTabContext(pane: number, tab: string): boolean {
    const menu = this.dockTabContext;
    return menu !== undefined && menu.session === this.sessionId && menu.pane === pane && menu.tab === tab;
  }

  private showDockTabContext(pane: number, tab: string, offset: Position): boolean {
    if (!this.pageActive || this.panel !== 'session' || !this.rightDock.expanded ||
      this.dockStoredTab(pane, tab) === undefined) { return false; }
    if (!this.isDockTabContext(pane, tab)) {
      this.dockTabContext = { session: this.sessionId, pane: pane, tab: tab,
        serial: ++this.dockTabContextSerial, offset: offset };
    }
    return true;
  }

  private dockTabMouse(event: MouseEvent, pane: number, tab: string): void {
    if (event.button === MouseButton.Middle) {
      if (event.action === MouseAction.Press) {
        this.dockMiddlePress = { session: this.sessionId, pane: pane, tab: tab };
      } else if (event.action === MouseAction.Release) {
        const pressed = this.dockMiddlePress;
        this.dockMiddlePress = undefined;
        if (pressed?.session === this.sessionId && pressed.pane === pane && pressed.tab === tab &&
          (event.pressedButtons?.length ?? 0) === 0 && this.pageActive && this.panel === 'session' &&
          this.rightDock.expanded &&
          this.dockStoredTab(pane, tab) !== undefined) {
          this.closeDockTab(pane, tab);
        }
      } else { return; }
      event.stopPropagation();
      return;
    }
    if (event.button !== MouseButton.Right) { return; }
    if (event.action === MouseAction.Press) {
      event.stopPropagation();
    } else if (event.action === MouseAction.Release && this.showDockTabContext(pane, tab,
      { x: event.x, y: event.y - DOCK_TAB_TITLE_HEIGHT })) {
      event.stopPropagation();
    }
  }

  private dockTabKey(event: KeyEvent, pane: number, tab: string): boolean {
    if (event.type !== KeyType.Down || event.metaKey === 1) { return false; }
    const key = desktopShortcutFromEvent(event);
    if (key.ctrl || key.alt || !(key.code === KeyCode.KEYCODE_MENU || (key.code === KeyCode.KEYCODE_F10 && key.shift))) {
      return false;
    }
    if (!this.showDockTabContext(pane, tab, { x: 0, y: 0 })) { return false; }
    event.stopPropagation();
    return true;
  }

  private dockTabContextOptions(pane: number, tab: string): MenuOptions {
    const options = desktopMenuOptions(Placement.BottomLeft);
    const menu = this.dockTabContext;
    if (menu === undefined || !this.isDockTabContext(pane, tab)) { return options; }
    options.offset = menu.offset;
    options.onDisappear = (): void => {
      if (this.dockTabContext?.serial === menu.serial) { this.dockTabContext = undefined; }
    };
    return options;
  }

  private dockStoredTab(index: number, id: string): DesktopDockTab | undefined {
    if (index < 0) { return this.floatingPanel(id)?.tab; }
    return this.rightDock.panes[index]?.tabs.find((tab: DesktopDockTab): boolean => tab.id === id);
  }

  private dockTabShown(index: number, id: string): boolean {
    return index < 0 ? this.floatingPanel(id) !== undefined :
      this.rightDock.expanded && this.rightDock.panes[index]?.active === id;
  }

  private floatingPanel(id: string): DesktopDockFloat | undefined {
    return this.rightDock.floats.find((panel: DesktopDockFloat): boolean => panel.tab.id === id);
  }

  private constrainFloat(rect: DesktopDockRect): DesktopDockRect {
    return desktopDockFloatRect(rect, this.workbenchWidth, this.workbenchHeight);
  }

  private defaultFloatRect(x?: number, y?: number): DesktopDockRect {
    const width = Math.min(540, this.workbenchWidth * 0.64);
    const height = Math.min(430, this.workbenchHeight * 0.68);
    const offset = 20 * (this.rightDock.floats.length % 4);
    return this.constrainFloat({ x: x ?? (this.workbenchWidth - width) / 2 + offset,
      y: y ?? (this.workbenchHeight - height) / 2 + offset, width: width, height: height });
  }

  private floatDockTab(index: number, id: string, rect: DesktopDockRect): void {
    this.dockTabBounds.delete(id);
    this.setDock(desktopDockFloat(this.rightDock, index, id, rect));
  }

  private focusFloat(id: string): void {
    this.setDock(desktopDockFocusFloat(this.rightDock, id));
  }

  private floatDisplayRect(id: string): DesktopDockRect {
    return this.floatGestureTab === id && this.floatPreview !== undefined ? this.floatPreview :
      this.constrainFloat(this.floatingPanel(id)?.rect ?? this.defaultFloatRect());
  }

  private floatZOrder(id: string): number {
    return this.rightDock.floats.findIndex((panel: DesktopDockFloat): boolean => panel.tab.id === id) + 1;
  }

  private blurFloat(): void {
    if (this.rightDock.focusedFloat) { this.focusDockPane(this.rightDock.focus); }
  }

  private beginFloatGesture(id: string): void {
    this.floatPreview = undefined;
    this.floatGestureTab = id;
    this.floatOrigin = this.floatDisplayRect(id);
    this.focusFloat(id);
  }

  private updateFloatResize(dx: number, dy: number): void {
    const origin = this.floatOrigin;
    if (origin === undefined) { return; }
    this.floatPreview = this.constrainFloat({ x: origin.x, y: origin.y,
      width: Math.min(origin.width + dx, this.workbenchWidth - origin.x - 6),
      height: Math.min(origin.height + dy, this.workbenchHeight - origin.y - 6) });
  }

  private finishFloatResize(commit: boolean): void {
    const preview = this.floatPreview;
    const id = this.floatGestureTab;
    this.floatGestureTab = '';
    this.floatOrigin = undefined;
    this.floatPreview = undefined;
    if (commit && preview !== undefined) {
      this.setDock(desktopDockFloatPosition(this.rightDock, id, preview));
    }
  }

  private beginDockDrag(event: GestureEvent, index: number, tab: DesktopDockTab, moving: boolean): void {
    if (!moving && this.dockPanActive) { return; }
    this.dockPanActive = moving;
    this.dockDrag = { session: this.sessionId, pane: index, tab: tab.id };
    if (index < 0) { this.beginFloatGesture(tab.id); }
    else { this.dockDragTitle = tab.title; }
    this.updateDockDrag(event);
  }

  private disarmDockDrag(): void {
    if (!this.dockPanActive) { this.endDockDrag(false); }
  }

  private endDockDrag(commit: boolean): void {
    const source = this.dockDrag;
    const drop = this.dockDrop;
    this.dockDrag = undefined;
    this.dockDrop = undefined;
    this.dockPanActive = false;
    this.dockDropCue = '';
    this.dockDragTitle = '';
    if (source?.pane === -1) {
      this.finishFloatResize(commit && source.session === this.sessionId && drop === undefined);
    }
    if (!commit || source?.session !== this.sessionId || drop === undefined) { return; }
    if (drop.pane < 0) {
      this.floatDockTab(source.pane, source.tab, this.defaultFloatRect(this.dockDragX - 16, this.dockDragY - 24));
      return;
    }
    if (drop.side && this.canSplitDock()) {
      const target = drop.side === 'left' ? 0 : 1;
      const split = desktopDockSplit(this.rightDock, target);
      this.setDock(source.pane < 0 ? desktopDockSeatFloat(split, source.tab, target) :
        desktopDockMoveTab(split, 1 - target, source.tab, target));
    } else if (source.pane < 0) {
      this.setDock(desktopDockSeatFloat(this.rightDock, source.tab, drop.pane, drop.before));
    } else {
      this.setDock(desktopDockMoveTab(this.rightDock, source.pane, source.tab, drop.pane, drop.before));
    }
  }

  private dockAreaContains(area: Area | undefined, x: number, y: number): boolean {
    if (area === undefined) { return false; }
    const left = Number(area.globalPosition.x);
    const top = Number(area.globalPosition.y);
    return x >= left && x < left + Number(area.width) && y >= top && y < top + Number(area.height);
  }

  private dockDropSide(x: number, y: number): string {
    const bounds = this.dockBounds;
    if (!this.canSplitDock() || bounds === undefined || y < Number(bounds.globalPosition.y) + 39) { return ''; }
    const width = Number(bounds.width);
    const offset = x - Number(bounds.globalPosition.x);
    const edge = Math.min(60, width * 0.2);
    return offset < edge ? 'left' : (offset >= width - edge ? 'right' : '');
  }

  private updateDockDrag(event: GestureEvent): void {
    if (this.dockDrag?.session !== this.sessionId) { return; }
    const finger = event.fingerInfos?.[0] ?? event.fingerList[0];
    if (finger === undefined) { return; }
    const x = finger.globalX;
    const y = finger.globalY;
    this.dockDragX = Math.max(0, Math.min(this.workbenchWidth - 160, x + 12));
    this.dockDragY = Math.max(0, Math.min(this.workbenchHeight - 28, y + 9));
    const source = this.dockDrag;
    const origin = this.floatOrigin;
    if (source?.pane === -1 && origin !== undefined) {
      this.floatPreview = this.constrainFloat({ x: origin.x + event.offsetX, y: origin.y + event.offsetY,
        width: origin.width, height: origin.height });
    }
    const covered = this.rightDock.floats.some((panel: DesktopDockFloat): boolean => {
      if (panel.tab.id === source?.tab) { return false; }
      const rect = this.constrainFloat(panel.rect);
      return x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height;
    });
    const pane = this.rightDock.expanded && !covered ?
      this.rightDock.panes.findIndex((_pane: DesktopDockPane, index: number): boolean =>
        this.dockAreaContains(this.dockPaneBounds.get(index), x, y)) : -1;
    const hit = this.rightDock.panes[pane]?.tabs.find((tab: DesktopDockTab): boolean =>
      this.dockAreaContains(this.dockTabBounds.get(tab.id), x, y));
    if (pane < 0 || hit?.id === this.dockDrag?.tab) {
      this.dockDrop = pane < 0 && source !== undefined && source.pane >= 0 &&
        x >= 0 && x < this.workbenchWidth && y >= 44 && y < this.workbenchHeight ?
        { pane: -1, before: '', side: '' } : undefined;
      this.dockDropCue = '';
      return;
    }
    const side = hit === undefined ? this.dockDropSide(x, y) : '';
    this.dockDrop = { pane: pane, before: hit?.id ?? '', side: side };
    this.dockDropCue = hit?.id ?? (side ? 'split-' + side : 'pane-' + pane);
  }

  @Builder
  private DockDragPreview(title: string) {
    Text(title).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor($r('sys.color.font_primary')).padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .constraintSize({ maxWidth: 160 }).borderRadius(7).backgroundColor($r('app.color.workspace_selection'))
      .position({ x: this.dockDragX, y: this.dockDragY }).zIndex(this.rightDock.floats.length + 1)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }

  @Builder
  private DockResizeHandle(split: boolean) {
    Stack() {
      Divider().vertical(true).height('100%').color($r('app.color.workspace_border'))
    }.key(split ? 'desktopDockSplitResize' : 'desktopDockOuterResize')
      .width(DOCK_HANDLE_WIDTH).height('100%')
      .backgroundColor(this.dockGripHover === (split ? 2 : 1) ? $r('app.color.workspace_selection') : Color.Transparent)
      .accessibilityText(split ? '调整分栏宽度' : '调整右侧栏宽度')
      .onHover((hover: boolean): void => { this.dockGripHover = hover ? (split ? 2 : 1) : 0; })
      .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart((): void => { this.startDockResize(split); })
        .onActionUpdate((event: GestureEvent): void => { this.updateDockResize(split, event.offsetX); })
        .onActionEnd((): void => { this.finishDockResize(true); })
        .onActionCancel((): void => { this.finishDockResize(false); }))
  }

  private dockChatActions(data?: DesktopWorkspaceData): DesktopDockChatActions {
    return {
      run: (id: string, operation: (id: string) => Promise<string>): Promise<string> => this.chatAction(operation, undefined, id),
      stop: (id: string, conversation: DesktopConversation): Promise<string> => this.stopForSession(id, conversation),
      readDraft: (id: string): DesktopComposerDraft => this.drafts.get(id) ?? EMPTY_DESKTOP_DRAFT,
      writeDraft: (id: string, draft: DesktopComposerDraft): void => this.storeDraft(id, draft),
      readAttachments: (id: string): DesktopDraftAttachment[] => this.attachmentsBySession.get(id) ?? [],
      writeAttachments: (id: string, files: DesktopDraftAttachment[]): void => this.setAttachments(id, files),
      pickAttachments: (id: string, conversation: DesktopConversation): Promise<string> => data === undefined ?
        Promise.resolve('无法打开文件选择器') : this.pickConversationDocuments(data, id, conversation),
      dropAttachments: (id: string, conversation: DesktopConversation, files: DesktopDroppedFiles): Promise<string> =>
        data === undefined ? Promise.resolve('无法添加文件') : this.stageDroppedDocuments(data, id, files, conversation),
      pasteAttachments: (id: string, conversation: DesktopConversation): Promise<string> => data === undefined ?
        Promise.resolve('无法读取剪贴板附件') : this.stageClipboard(data, id, conversation),
      openMain: (target: DesktopDockChatTarget, title: string): void => this.openRelatedSession(target.id, title, target.subagent),
      openTimeline: (target: DesktopDockChatTarget, title: string, tree: string, task: string): void => {
        if (target.id !== this.sessionId) { this.openRelatedSession(target.id, title, target.subagent); }
        this.requestTimeline(target.id, tree, task, !tree && !task);
      },
      openChild: (child: DesktopSubagentEntry, parents: DesktopSubagentEntry[], aside: boolean): void =>
        this.openSubagent(child, parents, aside),
      openParent: (child: DesktopSubagentEntry): void => this.openSubagentParent(child),
      openImage: (id: string, row: DesktopMediaAttachment): void => { this.openImagePreview(row, id); },
      openFile: (id: string, path: string, name: string): void => this.showArtifact(path, name, id),
      systemFile: (id: string, path: string, name: string, reveal: boolean): void => { this.openArtifactAction(path, name, reveal, id); },
      referenceFile: (id: string, action: DesktopReferenceAction, path: string, name: string): void => {
        this.referenceFileAction(action, path, name, id);
      },
      openPlan: (id: string, plan: DesktopPlanDocument): void => this.showPlan(plan, id),
      openCompaction: (target: DesktopDockChatTarget, sequence: number, isCurrent: () => boolean):
        Promise<ResourceStr | undefined> => this.openCompaction(target, sequence, isCurrent),
      openLink: (href: string): void => this.openConversationLink(href),
      openChanges: (target: DesktopChangeTarget): void => this.showChanges(target, target.sessionId),
      openModels: (): void => { this.openSettings('settings.models'); },
      openPlugin: (name: string, title: string, description: string): void => {
        this.openPlugins(name, title, description);
      },
      openWeb: (id: string, child?: DesktopSubagentEntry, cordis?: DesktopCordisWebLocation): void => {
        this.openWeb(false, cordis === undefined ? '' : 'cordis', id, undefined, child, cordis);
      },
      copy: (id: string): void => { this.copyTranscript(id); },
      exportLog: (id: string): Promise<string> => this.exportLog(id),
      feedback: (id: string, conversation: DesktopConversation): Promise<string> => this.openSessionFeedback(id, conversation.feedback),
      rate: (id: string, messageId: string, rating: DesktopRating, conversation: DesktopConversation): void => {
        this.chooseReplyRating(id, messageId, rating, conversation.feedback);
      },
      fork: (id: string, sequence: number, conversation: DesktopConversation): void => {
        this.forkFrom(id, sequence, conversation);
      }
    };
  }

  private dockChatDirectory(tab: DesktopDockTab): string {
    return this.sessionSummaries.find((row: SessionListItem): boolean => row.id === tab.chat?.id)?.cwd ?? this.selectedSessionDirectory;
  }

  private fileSearchPreferences(): DesktopFileSearchPreferenceBook | undefined {
    if (this.fileSearchBook === undefined) {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) { this.fileSearchBook = new DesktopFileSearchPreferenceBook(context); }
    }
    return this.fileSearchBook;
  }

  private fileSearchRoot(tab: DesktopDockTab): string {
    const session = tab.sourceSessionId;
    return session === undefined ? this.selectedSessionDirectory :
      this.sessionSummaries.find((row: SessionListItem): boolean => row.id === session)?.cwd ?? '';
  }

  private fileNavigatorBinding(index: number, tab: DesktopDockTab): DesktopFileNavigatorLink {
    const paneId = index < 0 ? 'float:' + tab.id : 'dock:' + this.rightDock.panes[index]?.id;
    return { owner: this.sessionId, paneId: paneId, sessionId: tab.sourceSessionId ?? this.sessionId,
      root: this.fileSearchRoot(tab) };
  }

  private retainFileNavigators(layout: DesktopDockLayout): void {
    if (!this.fileNavigators.has(this.sessionId)) { return; }
    const valid = new Set<string>();
    const retain = (paneId: string, tab: DesktopDockTab): void => {
      if (tab.kind === DesktopDockKind.FILES || tab.kind === DesktopDockKind.PREVIEW) {
        valid.add(desktopFileNavigatorKey(paneId, tab.sourceSessionId ?? this.sessionId));
      }
    };
    layout.panes.forEach((pane: DesktopDockPane): void => {
      pane.tabs.forEach((tab: DesktopDockTab): void => retain('dock:' + pane.id, tab));
    });
    layout.floats.forEach((panel: DesktopDockFloat): void => retain('float:' + panel.tab.id, panel.tab));
    this.fileNavigators.retain(this.sessionId, valid);
  }

  private documentViewKey(tabId: string): string { return JSON.stringify([this.sessionId, tabId]); }

  private documentViewReader(tabId: string): () => DesktopDocumentViewState | undefined {
    const key = this.documentViewKey(tabId);
    return (): DesktopDocumentViewState | undefined => this.documentViews.get(key);
  }

  private documentViewWriter(index: number, tabId: string): (view: DesktopDocumentViewState) => void {
    const owner = this.sessionId;
    const key = this.documentViewKey(tabId);
    return (view: DesktopDocumentViewState): void => {
      if (owner === this.sessionId && this.dockTabShown(index, tabId)) { this.documentViews.set(key, view); }
    };
  }

  private timelineNotifier(session: string): (owner: string, text: string) => Promise<string> {
    const data = this.data;
    const child = this.selectedSubagent?.mode === 'continuable';
    return (owner: string, text: string): Promise<string> =>
      data !== undefined && owner === session ? data.sendTimelineNotice(owner, text, child) : Promise.resolve('会话已切换');
  }

  @Builder
  private DockBody(index: number, tab: DesktopDockTab) {
    if (tab.kind === DesktopDockKind.TIMELINE) {
      DesktopTimelinePane({ host: this.data?.actions, sessionId: this.sessionId, location: this.timelineLocation,
        wheelModifierHeld: this.timelineWheelModifier,
        savedBrowse: this.timelineBrowse, draftBook: this.data?.timelineDrafts, viewportMemory: this.timelineViewport,
        onBrowse: (owner: string, state: DesktopTimelineBrowseState): void => {
          if (owner === this.sessionId && this.pageActive && this.dockTabShown(index, tab.id)) {
            this.timelineBrowses.set(owner, state);
            this.timelineBrowse = state;
          }
        },
        progressDecimals: this.timelinePreferences.decimals, segmentedProgress: this.timelinePreferences.segmentedProgress,
        linkLost: this.chat?.sessionId === this.sessionId && this.chat?.timelineLinkLost === true,
        onRetry: (): void => { this.data?.conversation.retryTimeline(); },
        onTaskRoot: (owner: string, tree: string): void => {
          if (owner === this.sessionId && tree !== this.timelineRoot) { this.timelineRoot = tree; }
        },
        opening: this.chat?.sessionId === this.sessionId ? this.chat?.timeline : undefined,
        active: this.hasTimeline() && (index < 0 || (this.rightDock.expanded && this.rightDock.panes[index]?.active === tab.id)),
        writable: this.hasTimeline() && (this.selectedSubagent === undefined || this.selectedSubagent.mode === 'continuable'),
        running: this.chat?.sessionId === this.sessionId && this.chat?.running === true,
        onNotify: this.timelineNotifier(this.sessionId),
        onWeb: (): void => { this.openWeb(false); },
        onLink: (href: string): void => this.openConversationLink(href) })
    } else if (tab.kind === DesktopDockKind.FILES || tab.kind === DesktopDockKind.PREVIEW) {
      DesktopFilesPane({ host: this.data?.actions,
        ability: this.getUIContext().getSharedLocalStorage()?.get<common.UIAbilityContext>('dshDesktopPreviewContext'),
        sessionId: tab.sourceSessionId ?? this.sessionId, requested: this.dockStoredTab(index, tab.id)?.file,
        previewOnly: tab.kind === DesktopDockKind.PREVIEW, focusScope: tab.id, viewportWidth: this.workbenchWidth,
        navigatorBook: this.fileNavigators, navigatorLink: this.fileNavigatorBinding(index, tab),
        shown: this.dockTabShown(index, tab.id),
        interactiveHtml: this.codingTools.enabled,
        preferenceBook: this.fileSearchPreferences(),
        readDocumentView: tab.kind === DesktopDockKind.PREVIEW ? this.documentViewReader(tab.id) : undefined,
        onDocumentView: tab.kind === DesktopDockKind.PREVIEW ? this.documentViewWriter(index, tab.id) : undefined,
        onHide: (): void => this.closeDockTab(index, tab.id),
        onOpenFile: (path: string, name: string): void => {
          if (tab.kind === DesktopDockKind.PREVIEW) { this.replaceArtifact(index, tab, path, name); }
          else {
            this.focusDockPane(index);
            this.showArtifact(path, name, tab.sourceSessionId ?? this.sessionId);
          }
        },
        onOpenFileIn: (path: string, name: string, floating: boolean): void => {
          this.openArtifactIn(index, tab, path, name, floating);
        },
        canReferenceWorkspaceFile: this.fileMenuCanReference(tab.sourceSessionId ?? this.sessionId),
        onReferenceWorkspaceFile: (path: string): void => {
          const session = tab.sourceSessionId ?? this.sessionId;
          if (this.pageActive && this.dockTabShown(index, tab.id) && this.fileMenuCanReference(session) &&
            desktopReferenceText(path, false, true)) {
            this.referenceOffer = { sessionId: session, path: path };
          }
        } })
    } else if (tab.kind === DesktopDockKind.TERMINAL) {
      DesktopTerminalPane({ host: this.data?.actions, sessionId: this.sessionId, appearance: this.appearance,
        shown: this.dockTabShown(index, tab.id),
        focusEligible: this.rightDock.focusedFloat ? this.rightDock.focusedFloat === tab.id : index === this.rightDock.focus,
        cellFontSize: this.typography.terminalSize, cellFontFamily: this.typography.terminalFamily,
        preferredTerminal: tab.terminalId ?? '', origin: this.browserOrigin(), pendingOccurrence: tab.terminalLaunch === true,
        observeRetention: (id: string, listener: (problem: string, code?: string) => void): (() => void) => {
          return this.data?.terminalRetentions.observe(this.sessionId, id, listener) ?? (() => {});
        },
        observeRoster: (sink: DesktopTerminalRosterSink): (() => void) => {
          return this.data?.terminalRosters.watch(this.sessionId, sink) ?? (() => {});
        },
        createRequest: this.terminalCreateRequest?.tabId === tab.id ? this.terminalCreateRequest : undefined,
        onCreateShortcut: (): void => {
          if (this.terminalCreateRequest?.tabId === tab.id) { this.terminalCreateRequest = undefined; }
        },
        onRename: (): void => { this.startTerminalRename(index, tab.id); },
        openInNewTab: (row: DesktopTerminalRow): boolean => this.openDockTerminal(index, tab.id, row),
        replaceInPlace: (sessionId: string, oldId: string, row: DesktopTerminalRow): boolean => {
          return this.replaceDockTerminal(sessionId, tab.id, oldId, row);
        },
        onTerminalSelected: (sessionId: string, id: string, title: string): void => {
          if (sessionId !== this.sessionId) { return; }
          if (!id && tab.id !== DesktopDockKind.TERMINAL) { this.removeDockTab(index, tab.id); }
          else if (id || !this.closingDockTerminals.has(JSON.stringify([sessionId, this.dockStoredTab(index, tab.id)?.terminalId]))) {
            this.setDock(desktopDockBindTerminal(this.rightDock, tab.id, id, title));
          }
        },
        onShortcut: (event: KeyEvent): boolean => {
          if (event.type === KeyType.Down) {
            if (index < 0) { this.focusFloat(tab.id); } else { this.focusDockPane(index); }
          }
          return this.terminalShortcut(event);
        }, onHidePanel: (): void => {
          if (index < 0) { this.collapseFloatingTerminal(tab.id); } else { this.toggleRightDock(); }
        } })
    } else if (tab.kind === DesktopDockKind.PLAN) {
      DesktopPlanPreviewPane({ host: this.data?.actions, sessionId: tab.sourceSessionId ?? this.sessionId,
        document: this.dockStoredTab(index, tab.id)?.plan, shown: this.dockTabShown(index, tab.id),
        onClosePreview: (): void => this.closeDockTab(index, tab.id) })
    } else if (tab.kind === DesktopDockKind.COMPACTION) {
      DesktopCompactionPreviewPane({ markdown: this.dockStoredTab(index, tab.id)?.compactionMarkdown,
        typography: this.typography, onLink: (href: string): void => this.openConversationLink(href) })
    } else if (tab.kind === DesktopDockKind.CHAT) {
      DesktopDockChatPane({ data: this.data, actions: this.dockChatActions(this.data), replyMedia: this.replyMedia,
        developerTools: this.codingTools.enabled,
        target: tab.chat,
        title: tab.title, directory: this.dockChatDirectory(tab), shown: this.dockTabShown(index, tab.id),
        busy: this.busySessions.includes(tab.chat?.id ?? ''), forking: this.forking,
        stopping: this.stoppingSessions.includes(tab.chat?.id ?? ''),
        appearance: this.appearance, typography: this.typography, summaries: this.sessionSummaries,
        timelineDecimals: this.timelinePreferences.decimals, timelineSegmented: this.timelinePreferences.segmentedProgress })
    } else if (tab.kind === DesktopDockKind.BROWSER) {
      DesktopBrowserPane({ address: tab.browserAddress ?? '', restore: tab.restoreBrowser ?? false,
        workspaceOrigin: this.browserOrigin(), onNavigated: (href: string, title: string): void => {
          this.setDock(desktopDockBrowserAddress(this.rightDock, tab.id, href, title));
        } })
    } else {
      DesktopChangesPane({ host: this.data?.actions, sessionId: tab.sourceSessionId ?? this.sessionId,
        target: this.dockStoredTab(index, tab.id)?.changes, changeLocation: this.dockStoredTab(index, tab.id)?.changeLocation,
        shown: this.dockTabShown(index, tab.id),
        onClose: (): void => this.closeDockTab(index, tab.id),
        onFile: (path: string, name: string, target: DesktopChangeTarget): void => {
          this.showChanges(target, tab.sourceSessionId ?? this.sessionId);
          this.focusDockPane(index);
          this.showArtifact(path, name, tab.sourceSessionId ?? this.sessionId);
        } })
    }
  }

  @Builder
  private DockTerminalHeading(index: number, tab: DesktopDockTab, compact: boolean) {
    DesktopTerminalTitle({ title: this.terminalRename?.tabId === tab.id ? this.terminalRename?.title ?? tab.title :
      this.dockStoredTab(index, tab.id)?.title ?? tab.title,
      agentControlled: this.dockStoredTab(index, tab.id)?.agentControlled === true,
      sandboxMode: this.dockStoredTab(index, tab.id)?.terminalSandbox ?? '',
      keyPrefix: index < 0 ? 'desktopFloatTerminal-' + tab.id : 'desktopDockTerminal-' + index + '-' + tab.id,
      compact: compact, editVersion: this.terminalRename?.tabId === tab.id ? this.terminalRename?.version ?? -1 : -1,
      onRenameFinished: (version: number, value: string, save: boolean): void => {
        this.finishTerminalRename(version, value, save);
      } })
  }

  @Builder
  private DockTitleIcon(kind: DesktopDockKind, key: string, title: string) {
    if (kind === DesktopDockKind.FILES) {
      Image($r('app.media.dsh_file_folder')).key(key).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
    } else if (kind === DesktopDockKind.BROWSER) {
      Image($r('app.media.dsh_browser_globe_outline')).key(key).width(14).height(14).accessibilityLevel('no')
    } else if (kind === DesktopDockKind.COMPACTION) {
      Image($r('app.media.dsh_file_markdown')).key(key).width(16).height(16).supportSvg2(true).accessibilityLevel('no')
    } else if (kind === DesktopDockKind.PREVIEW) {
      Image(desktopFileTypeIcon(title)).key(key).width(16).height(16).supportSvg2(true)
        .draggable(false).accessibilityLevel('no')
    }
  }

  private dockTabTitle(tab: DesktopDockTab): ResourceStr {
    return tab.kind === DesktopDockKind.FILES ? $r('app.string.desktop_dock_file_tab') : tab.title;
  }

  @Builder
  private DockTab(index: number, tab: DesktopDockTab) {
    Row({ space: 2 }) {
      if (this.terminalRename?.tabId === tab.id) {
        Row() { this.DockTerminalHeading(index, tab, true) }
          .height(28).padding({ left: 7, right: 2 }).constraintSize({ maxWidth: 200 })
      } else {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          if (tab.kind === DesktopDockKind.TERMINAL) {
            this.DockTerminalHeading(index, tab, true)
          } else {
            Row({ space: 4 }) {
              this.DockTitleIcon(tab.kind, 'desktopDockTabIcon-' + index + '-' + tab.id, tab.title)
              Text(this.dockTabTitle(tab)).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor($r('sys.color.font_primary'))
            }
          }
        }.key('desktopDockTab-' + index + '-' + tab.id).height(DOCK_TAB_TITLE_HEIGHT).padding({ left: 7, right: 2 })
          .constraintSize({ maxWidth: 126 }).accessibilitySelected(this.rightDock.panes[index]?.active === tab.id)
          .onClick((): void => { this.setDock(desktopDockSelect(this.rightDock, index, tab.id)); })
          .onMouse((event: MouseEvent): void => { this.dockTabMouse(event, index, tab.id); })
          .onHover((hovered: boolean): void => {
            if (!hovered && this.dockMiddlePress?.pane === index && this.dockMiddlePress?.tab === tab.id) {
              this.dockMiddlePress = undefined;
            }
          })
          .onKeyEvent((event: KeyEvent): boolean => this.dockTabKey(event, index, tab.id))
          .bindMenu(this.isDockTabContext(index, tab.id), this.dockTabMenu(index, tab),
            this.dockTabContextOptions(index, tab.id))
          .priorityGesture(GestureGroup(GestureMode.Parallel,
            PanGesture({ direction: PanDirection.All, distance: 8 })
              .onActionStart((event: GestureEvent): void => { this.beginDockDrag(event, index, tab, true); })
              .onActionUpdate((event: GestureEvent): void => { this.updateDockDrag(event); })
              .onActionEnd((event: GestureEvent): void => { this.updateDockDrag(event); this.endDockDrag(true); })
              .onActionCancel((): void => { this.endDockDrag(false); }),
            LongPressGesture({ duration: 300 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
              .onAction((event: GestureEvent): void => { this.beginDockDrag(event, index, tab, false); })
              .onActionEnd((): void => { this.disarmDockDrag(); })
              .onActionCancel((): void => { this.disarmDockDrag(); }),
            TapGesture({ count: 2, distanceThreshold: 6 }).onAction((): void => {
              if (tab.kind === DesktopDockKind.TERMINAL) { this.startTerminalRename(index, tab.id); }
            })))
      }
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_dock_close')).width(11).height(11).accessibilityLevel('no')
      }.key('desktopDockClose-' + index + '-' + tab.id).width(21).height(24).padding(0)
        .accessibilityText('关闭标签 ' + tab.title).onClick((): void => this.closeDockTab(index, tab.id))
      if (this.rightDock.panes[index]?.active === tab.id) {
        Button('···', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(22).height(24).padding(0)
          .key('desktopDockTabMenu-' + index + '-' + tab.id).accessibilityText('标签操作 ' + tab.title)
          .bindMenu(this.dockTabMenu(index, tab), desktopMenuOptions(Placement.BottomLeft))
      }
    }.height(30).borderRadius(7)
      .border({ width: { left: 2 }, color: this.dockDropCue === tab.id ? $r('sys.color.ohos_id_color_activated') : Color.Transparent })
      .backgroundColor(this.rightDock.panes[index]?.active === tab.id ? $r('app.color.workspace_selection') : Color.Transparent)
      .onAreaChange((_, area: Area): void => { this.observeDockTabArea(index, tab.id, area); })
  }

  @Builder
  private DockGuide(index: number) {
    Column({ space: 8 }) {
      Button('工作区文件', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopDockGuideFiles-' + index)
        .onClick((): void => this.openDockTool(index, DesktopDockKind.FILES))
      Column() {
        DesktopTerminalGuide({ host: this.data?.actions, sessionId: this.sessionId, origin: this.browserOrigin(),
          createKey: 'desktopDockGuideTerminal-' + index, shellKey: 'desktopDockGuideTerminalShell-' + index,
          canCreate: this.data !== undefined && this.sessionId.length > 0, shortcutText: this.terminalGuideShortcut(),
          onCreate: (): void => { this.launchDockTerminal(index); },
          onShellCreate: (shellPath: string): void => { this.launchDockTerminal(index, shellPath); } })
      }.width('90%').constraintSize({ maxWidth: 360 })
      if (this.hasTimeline()) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 7 }) {
            Image($r('app.media.dsh_timeline_icon')).width(20).height(20).supportSvg2(true).accessibilityLevel('no')
            Text($r('app.string.desktop_timeline_title')).fontSize(14)
          }
        }.key('desktopDockGuideTimeline').accessibilityText($r('app.string.desktop_timeline_title'))
          .onClick((): void => { this.openDockTool(index, DesktopDockKind.TIMELINE); })
      }
      Button($r('app.string.desktop_browser_title'), { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopDockGuideBrowser-' + index)
        .onClick((): void => this.openBrowser(index))
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Image($r('app.media.dsh_right_more_tools')).width(22).height(22).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
          Text($r('app.string.desktop_plugin_entry_more_tools')).fontSize(14).fontColor($r('sys.color.font_primary'))
        }
      }.key('desktopDockGuideMore-' + index).height(36).borderRadius(8)
      .accessibilityText($r('app.string.desktop_plugin_entry_more_tools'))
      .bindMenu(desktopPluginEntryItems((): void => { this.openPlugins(); },
        (): void => { this.createPluginDraft($r('app.string.desktop_plugin_prompt_rightbar')); }),
        desktopMenuOptions(Placement.BottomRight))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  private DockPane(index: number) {
    Column() {
      Row({ space: 4 }) {
        Scroll(this.dockTabScrollers[index]) {
          Row({ space: 4 }) {
            ForEach(this.rightDock.panes[index]?.tabs ?? [], (tab: DesktopDockTab): void => {
              this.DockTab(index, tab)
            }, (tab: DesktopDockTab): string => this.sessionId + ':' + tab.id + ':' + tab.title)
          }
        }.key('desktopDockTabStrip-' + index).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .align(Alignment.Start)
          .onAreaChange((previous: Area, area: Area): void => { this.observeDockTabViewport(index, previous, area); })
          .enableScrollInteraction(!this.dockDragTitle).layoutWeight(1)
        Button('＋', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopDockAdd-' + index)
          .height(30).width(28).padding(0).accessibilityText('新建标签页')
          .bindMenu(this.dockMenu(index), desktopMenuOptions(Placement.BottomRight))
        if (index === this.rightDock.panes.length - 1) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image(this.dockFullscreen() ? $r('app.media.dsh_right_restore') : $r('app.media.dsh_right_fullscreen'))
              .width(16).height(16).fillColor($r('sys.color.font_primary')).accessibilityLevel('no')
          }.key('desktopDockFullscreen').width(28).height(30).padding(0)
            .accessibilityText(this.dockFullscreen() ? '退出全屏' : '全屏').enabled(!this.dockAutoFullscreen())
            .onClick((): void => this.toggleDockFullscreen())
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.sidebar_toggle')).width(16).height(16).rotate({ angle: 180 })
              .fillColor($r('sys.color.font_primary')).accessibilityLevel('no')
          }.key('desktopDockCollapse').width(28).height(30).padding(0).accessibilityText('收起右侧栏')
            .onClick((): void => this.toggleRightDock())
        }
      }.width('100%').height(39).padding({ left: 5, right: 5 })
        .backgroundColor(this.dockDropCue === 'pane-' + index ? $r('app.color.workspace_selection') : Color.Transparent)
        .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      Stack() {
        if (!this.rightDock.panes[index]?.tabs.length) {
          this.DockGuide(index)
        } else {
          ForEach(this.rightDock.panes[index]?.tabs ?? [], (tab: DesktopDockTab): void => {
            Column() { this.DockBody(index, tab) }
              .width('100%').height('100%')
              .visibility(this.rightDock.panes[index]?.active === tab.id ? Visibility.Visible : Visibility.None)
          }, (tab: DesktopDockTab): string => this.sessionId + ':' + tab.id)
        }
        if (this.dockDropCue === 'split-left' || this.dockDropCue === 'split-right') {
          Row() {
            if (this.dockDropCue === 'split-right') { Blank() }
            Column().width('20%').height('100%').backgroundColor($r('app.color.workspace_selection'))
          }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').layoutWeight(1)
    }.key('desktopDockPane-' + index).layoutWeight(this.dockPaneWeight(index)).height('100%')
      .onAreaChange((_, area: Area): void => { this.dockPaneBounds.set(index, area); })
      .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) { this.focusDockPane(index); } })
  }

  @Builder
  private RightDock() {
    Row() {
      this.DockPane(0)
      if (this.rightDock.panes.length === 2) {
        this.DockResizeHandle(true)
        this.DockPane(1)
      }
    }.key('desktopRightDock').width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
      .onAreaChange((_, area: Area): void => { this.dockBounds = area; })
  }

  @Builder
  private FloatingDockPane(panel: DesktopDockFloat) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row({ space: 3 }) {
          if (this.terminalRename?.tabId === panel.tab.id) {
            Row() { this.DockTerminalHeading(-1, panel.tab, false) }
              .layoutWeight(1).height(36).padding({ left: 11 }).justifyContent(FlexAlign.Start)
          } else {
            Row() {
              if (panel.tab.kind === DesktopDockKind.TERMINAL) {
                this.DockTerminalHeading(-1, panel.tab, false)
              } else {
                Row({ space: 4 }) {
                  this.DockTitleIcon(panel.tab.kind, 'desktopDockFloatIcon-' + panel.tab.id, panel.tab.title)
                  Text(this.dockTabTitle(panel.tab)).fontSize(13).fontWeight(FontWeight.Medium).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_primary'))
                }
              }
            }
              .layoutWeight(1).height(36).padding({ left: 11 }).justifyContent(FlexAlign.Start)
              .key('desktopDockFloatTitle-' + panel.tab.id)
              .gesture(GestureGroup(GestureMode.Exclusive, PanGesture({ direction: PanDirection.All, distance: 3 })
                .onActionStart((event: GestureEvent): void => { this.beginDockDrag(event, -1, panel.tab, true); })
                .onActionUpdate((event: GestureEvent): void => { this.updateDockDrag(event); })
                .onActionEnd((event: GestureEvent): void => { this.updateDockDrag(event); this.endDockDrag(true); })
                .onActionCancel((): void => { this.endDockDrag(false); }),
                TapGesture({ count: 2, distanceThreshold: 2 }).onAction((): void => {
                  if (panel.tab.kind === DesktopDockKind.TERMINAL) { this.startTerminalRename(-1, panel.tab.id); }
                })))
          }
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.sidebar_toggle')).width(16).height(16).rotate({ angle: 180 })
              .fillColor($r('sys.color.font_primary')).accessibilityLevel('no')
          }.width(31).height(30).padding(0).key('desktopDockFloatSeat-' + panel.tab.id)
            .accessibilityText('收回到侧边栏').onClick((): void => {
              this.setDock(desktopDockSeatFloat(this.rightDock, panel.tab.id));
            })
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_dock_close')).width(13).height(13)
              .fillColor($r('sys.color.font_primary')).accessibilityLevel('no')
          }.width(29).height(30).padding(0).key('desktopDockFloatClose-' + panel.tab.id)
            .accessibilityText('关闭浮动面板 ' + panel.tab.title).onClick((): void => { this.closeDockTab(-1, panel.tab.id); })
        }.height(36).width('100%').padding({ right: 4 })
          .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : undefined)
          .systemMaterial(controlMaterial())
          .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
        Column() { this.DockBody(-1, panel.tab) }.width('100%').layoutWeight(1)
          .backgroundColor($r('app.color.workspace_canvas'))
      }.width('100%').height('100%')
      Stack() {
        Image($r('app.media.dsh_right_fullscreen')).width(11).height(11)
          .fillColor($r('sys.color.font_tertiary')).accessibilityLevel('no')
      }.width(21).height(21).backgroundColor($r('app.color.workspace_panel'))
        .key('desktopDockFloatResize-' + panel.tab.id).accessibilityText('调整浮动面板大小')
        .gesture(PanGesture({ direction: PanDirection.All, distance: 1 })
          .onActionStart((): void => { this.beginFloatGesture(panel.tab.id); })
          .onActionUpdate((event: GestureEvent): void => { this.updateFloatResize(event.offsetX, event.offsetY); })
          .onActionEnd((): void => { this.finishFloatResize(true); })
          .onActionCancel((): void => { this.finishFloatResize(false); }))
    }.key('desktopDockFloat-' + panel.tab.id)
      .width(this.floatDisplayRect(panel.tab.id).width).height(this.floatDisplayRect(panel.tab.id).height)
      .position({ x: this.floatDisplayRect(panel.tab.id).x, y: this.floatDisplayRect(panel.tab.id).y })
      .zIndex(this.floatZOrder(panel.tab.id)).clip(true).borderRadius(12)
      .border({ width: 1, color: this.rightDock.focusedFloat === panel.tab.id ?
        $r('sys.color.ohos_id_color_activated') : $r('app.color.workspace_border') })
      .shadow({ radius: 22, color: '#40000000', offsetY: 6 })
      .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) { this.focusFloat(panel.tab.id); } })
      .onMouse((event: MouseEvent): void => { if (event.action === MouseAction.Press) { this.focusFloat(panel.tab.id); } })
  }

  @Builder
  private SessionPane() {
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        Image($r('app.media.logo_dark')).width(32).height(28).objectFit(ImageFit.Contain)
        Text(this.selectedTitle || $r('app.string.desktop_experiment_welcome'))
          .fontSize(26).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '83%' })
      }
      .justifyContent(FlexAlign.Center)
      Column({ space: 8 }) {
        Row() {
          DesktopWorkspacePicker({ rows: this.workspacePickerRows(), selectedId: this.workspaceId,
            caption: this.selectedWorkspaceTitle || $r('app.string.desktop_experiment_choose_workspace'),
            ready: this.ready && !this.creating && !this.workspaceBusy,
            onPick: (id: string): void => { this.newSession(id); },
            onAdd: (): void => { this.addWorkspace(); } })
          if (this.landingPreset === 'cordis') {
            Row({ space: 6 }) {
              Image($r('app.media.dsh_agent_preset_outline')).width(14).height(14).supportSvg2(true)
                .draggable(false).accessibilityLevel('no')
              Text($r('app.string.desktop_agent_preset_cordis')).fontSize(13).fontColor($r('sys.color.font_secondary'))
            }.key('desktopLandingCreatorPreset').accessibilityGroup(true).padding({ left: 8, right: 8 })
          }
        }
        .width('100%').padding({ left: 4 })
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 12 }) {
            Text($r('app.string.action_new_session'))
              .fontSize(15).fontColor($r('sys.color.font_primary')).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.plus')).fontSize(17).fontColor([$r('sys.color.font_primary')])
          }
          .width('100%')
        }
        .width('100%').constraintSize({ minHeight: 76 }).padding({ left: 16, right: 16 }).borderRadius(21)
        .key('desktopWorkspaceLandingNewSession')
        .backgroundColor($r('app.color.workspace_panel')).focusOnTouch(false).enabled(this.ready && !this.creating)
        .onClick((): void => { this.newSession(); })
      }
      .width('100%').constraintSize({ maxWidth: 712 })
      if (this.chatError.length > 0) {
        Text(this.chatError).fontSize(13).fontColor($r('sys.color.warning'))
      }
    }
    .width('100%').height('100%').padding({ left: 26, right: 26 }).justifyContent(FlexAlign.Center)
  }

  @Builder
  private WorkbenchContent() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          this.TopBar()
          Row() {
            if (this.panel !== 'session' || !this.dockFullscreen()) { this.Sidebar() }
            if (this.panel === 'plugins' && this.ready && this.data !== undefined) {
              DesktopPluginsPane({
                host: this.data.actions, installer: this.data.pluginInstall, maintenance: this.data.pluginMaintenance,
                connectorAccounts: this.data.connectorAccounts, localePreference: this.data.accountLanguagePreference(),
                requestedBundle: this.pluginName, requestedLocation: this.pluginLocation, requestedTitle: this.pluginTitle,
                requestedDescription: this.pluginDescription,
                onWeb: (location: DesktopPluginLocation): void => { this.openWeb(false, 'plugins', this.sessionId, location); }
              })
            } else if (this.panel === 'schedule' && this.ready && this.data !== undefined) {
              DesktopSchedulePane({
                host: this.data.actions, catalog: this.data.scheduleCatalog,
                sessionId: this.sessionId,
                workspacePath: this.data.workspacePath(this.workspaceId),
                draftBusy: this.creating,
                onOpenSession: (id: string): void => { this.openSessionById(id); },
                onDraft: (prompt: Resource): void => { this.newSession(undefined, this.accessibilityLabel(prompt)); },
                onWeb: (): void => { this.openWeb(false, 'schedule'); }
              })
            } else if (this.panel !== 'session') {
              Column() {
                Text(this.error || this.hostError || $r('app.string.desktop_experiment_loading'))
                  .fontColor($r('sys.color.font_secondary'))
              }
              .layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
            } else {
              this.SessionContent()
            }
          }
          .width('100%').layoutWeight(1)
        }
        .width('100%').height('100%').backgroundColor($r('app.color.workspace_canvas'))
        .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) { this.blurFloat(); } })
        .onMouse((event: MouseEvent): void => { if (event.action === MouseAction.Press) { this.blurFloat(); } })
        if (this.panel === 'session' && this.sessionId && this.data !== undefined) {
          ForEach(this.rightDock.floats, (panel: DesktopDockFloat): void => {
            this.FloatingDockPane(panel)
          }, (panel: DesktopDockFloat): string => this.sessionId + ':' + panel.tab.id)
        }
        if (this.sessionDrag !== undefined && this.canDropSessionRight(this.sessionDrag)) {
          if (this.rightDock.expanded) {
            this.SessionDropZone(0, this.sessionDropRect(this.dockPaneBounds.get(0), false),
              this.rightDock.panes.length > 1)
            if (this.rightDock.panes.length > 1) {
              this.SessionDropZone(1, this.sessionDropRect(this.dockPaneBounds.get(1), false), true)
            }
          } else {
            this.SessionDropZone(this.rightDock.focus, this.sessionDropRect(this.sessionContentBounds, true), false)
          }
        }
        if (this.pageVisible && !this.shortcutsOpen && !this.settingsOpen) {
          Row() {
            ForEach(this.shortcutBindings, (row: DesktopShortcutRow): void => {
              if (!row.occupiedBy && row.binding.code !== 0) {
                Button().width(0).height(0).focusable(false).accessibilityLevel('no')
                  .keyboardShortcut(desktopShortcutValue(row.binding), desktopShortcutModifiers(row.binding),
                    (): void => { this.workspaceShortcut(row.id); })
              }
            }, (row: DesktopShortcutRow): string => row.id + row.occupiedBy + JSON.stringify(row.binding))
          }.width(0).height(0).visibility(Visibility.Hidden).accessibilityLevel('no')
        }
        DesktopShortcutDialog({ show: this.shortcutsOpen, panelWidth: Math.max(250, Math.min(480, this.workbenchWidth - 32)),
          onClose: (): void => { this.shortcutsOpen = false; }, onChanged: (): void => this.reloadShortcutBindings() })
        if (this.archiveNotice !== undefined) {
          this.ArchiveNoticeContent(this.archiveNotice)
        }
        if (this.quotaToastToken >= 0 || this.accountSessionToasts.length > 0) {
          Column({ space: 8 }) {
            if (this.quotaToastToken >= 0) { DesktopQuotaToast({ fading: this.quotaToastFading }) }
            ForEach(this.accountSessionToasts, (toast: DesktopAccountSessionToast): void => {
              Column() {
                DesktopQuotaToast({ message: toast.notice === DesktopAccountSessionNotice.SESSION_EXPIRED ?
                  $r('app.string.desktop_account_session_expired') : $r('app.string.desktop_account_model_sign_in_required'),
                  fading: this.accountSessionToastFading(toast.token), showWarningIcon: false })
              }.key(toast.notice === DesktopAccountSessionNotice.SESSION_EXPIRED ?
                'desktopAccountSessionExpiredNotice' : 'desktopAccountModelSignInRequiredNotice')
            }, (toast: DesktopAccountSessionToast): string => String(toast.token))
          }.width('100%').height('100%').padding({ top: 40, left: 24, right: 24 })
            .alignItems(HorizontalAlign.Center).hitTestBehavior(HitTestMode.None)
        }
        if (this.workspaceDropCue !== undefined) { this.WorkspaceDropMarker(this.workspaceDropCue) }
        if (this.workspaceDragTitle) {
          this.DockDragPreview(this.workspaceDragTitle)
        } else if (this.sessionDrag !== undefined) {
          this.DockDragPreview(this.sessionDrag.session.title)
        } else if (this.dockDragTitle) {
          this.DockDragPreview(this.dockDragTitle)
        }
      }
      .width('100%').height('100%')
      .visibility(this.accountOnboarding.visible ? Visibility.Hidden : Visibility.Visible)
      .enabled(!this.accountOnboarding.visible)
      .accessibilityLevel(this.accountOnboarding.visible ? 'no-hide-descendants' : 'auto')
  }

  build() {
    WithTheme({ colorMode: this.workspaceColorMode() }) {
      Stack() {
        this.WorkbenchContent()
        if (this.accountOnboarding.visible) {
          DesktopAccountOnboardingLayer({ view: this.accountOnboarding, contentWidth: this.workbenchWidth,
            controller: this.data?.onboarding, localePreference: this.data?.accountLanguagePreference() ?? 'system',
            onTopUp: (href: string): void => { this.openOnboardingTopUp(href); }
          })
        }
      }.width('100%').height('100%')
      .onKeyEvent((event: KeyEvent): void => { this.updateTimelineWheelModifier(event); })
      .onAreaChange((_, area: Area): void => {
        this.workbenchBounds = area;
        this.workbenchWidth = Number(area.width);
        this.workbenchHeight = Number(area.height);
        this.resizeSettingsSurface();
        this.openFirstTimelineTree();
        this.sidebarWidth = Math.max(160, Math.min(280, Number(area.width) * 0.48));
        this.defaultDockWidth = Math.max(DOCK_MIN_WIDTH, Math.min(520, (Number(area.width) - this.sidebarWidth) * 0.46));
      })
    }
  }
}
