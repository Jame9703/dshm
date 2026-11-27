import type { SessionListItem } from 'appstate';
import type { DesktopHostActions } from './DesktopHostActions';
import { DesktopArchiveFilter } from './DesktopSessionArchive';
import type { DesktopWorkspaceGroup } from './DesktopSessionOrder';
import {
  DESKTOP_WORKSPACE_SEARCH_LIMIT, DesktopWorkspaceSearchIndex, DesktopWorkspaceSearchRequest,
  desktopWorkspaceSearchQuery
} from './DesktopWorkspaceSearchModel';
import type { DesktopWorkspaceSearchPage, DesktopWorkspaceSearchRow } from './DesktopWorkspaceSearchModel';

@Component
struct DesktopWorkspaceSearchResult {
  @Prop row: DesktopWorkspaceSearchRow = {
    id: '', title: '', workspace: '', snippet: '', archived: false, running: false
  };
  @Prop selected: boolean = false;
  @Prop restoreEnabled: boolean = true;
  onOpen: (id: string) => void = (_id: string): void => {};
  onRestore: (id: string) => void = (_id: string): void => {};

  build() {
    Row({ space: 2 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Row() {
              if (!this.row.archived && this.row.running) {
                LoadingProgress().width(11).height(11).color($r('sys.color.brand'))
                  .accessibilityLevel('no')
              }
            }.width(16).height(18).justifyContent(FlexAlign.Center)
            Text(this.row.title || $r('app.string.desktop_experiment_unnamed'))
              .fontSize(14)
              .fontColor(this.row.archived ? $r('sys.color.font_tertiary') : $r('sys.color.font_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }.width('100%')
          Row({ space: 6 }) {
            Text(this.row.workspace || $r('app.string.desktop_workspace_search_ungrouped'))
              .fontSize(12).fontColor($r('sys.color.font_tertiary'))
              .constraintSize({ maxWidth: this.row.snippet ? '40%' : '100%' })
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.row.snippet) {
              Text(this.row.snippet).key('desktopWorkspaceSearchSnippet-' + this.row.id)
                .fontSize(12)
                .fontColor(this.row.archived ? $r('sys.color.font_tertiary') : $r('sys.color.font_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }.width('100%').padding({ left: 22 })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      .key('desktopWorkspaceSearchResult-' + this.row.id)
      .layoutWeight(1).height(48).padding({ left: 8, right: 4 }).borderRadius(8)
      .backgroundColor(this.selected ? $r('app.color.workspace_selection') : Color.Transparent)
      .focusOnTouch(false).accessibilitySelected(this.selected)
      .onClick((): void => { this.onOpen(this.row.id); })
      if (this.row.archived) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_session_unarchive_outline')).width(14).height(14).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
        }
        .key('desktopWorkspaceSearchRestore-' + this.row.id)
        .width(30).height(30).padding(0).borderRadius(7)
        .focusOnTouch(false).enabled(this.restoreEnabled)
        .accessibilityText($r('app.string.desktop_workspace_search_restore'))
        .onClick((): void => { this.onRestore(this.row.id); })
      }
    }.width('100%').alignItems(VerticalAlign.Top)
  }
}

/** Replaces the sidebar tree only while a nonblank search is active. */
@Component
export struct DesktopWorkspaceSearchResults {
  host?: DesktopHostActions;
  @Prop @Watch('queryChanged') query: string = '';
  @Prop @Watch('metadataChanged') sessions: SessionListItem[] = [];
  @Prop @Watch('metadataChanged') groups: DesktopWorkspaceGroup[] = [];
  @Prop @Watch('metadataChanged') archivedIds: string[] = [];
  @Prop @Watch('metadataChanged') archiveFilter: DesktopArchiveFilter = DesktopArchiveFilter.HIDE;
  @Prop selectedId: string = '';
  @Prop restoreEnabled: boolean = true;
  onOpen: (id: string) => void = (_id: string): void => {};
  onRestore: (id: string) => void = (_id: string): void => {};

  @State private matches: DesktopWorkspaceSearchRow[] = [];
  @State private pending: boolean = false;
  @State private failed: boolean = false;
  @State private hasMore: boolean = false;
  private index?: DesktopWorkspaceSearchIndex;
  private remotePage?: DesktopWorkspaceSearchPage;
  private readonly request = new DesktopWorkspaceSearchRequest();
  private currentQuery: string = '';
  private metadataTimer: number = -1;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.prepareIndex();
    this.queryChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.request.cancel();
    clearTimeout(this.metadataTimer);
    this.metadataTimer = -1;
    this.currentQuery = '';
  }

  private prepareIndex(): void {
    this.index = new DesktopWorkspaceSearchIndex(this.sessions, this.groups, this.archivedIds, this.archiveFilter);
  }

  private metadataChanged(): void {
    if (!this.active) { return; }
    // Archive, groups, and session summaries arrive in the same sidebar update.
    // Rebuild once after all of its props have landed.
    this.index = undefined;
    if (this.metadataTimer >= 0) { return; }
    this.metadataTimer = setTimeout((): void => {
      this.metadataTimer = -1;
      if (this.active && this.index === undefined) { this.refreshResults(); }
    }, 0);
  }

  private refreshResults(): void {
    if (this.index === undefined) { this.prepareIndex(); }
    const result = this.index?.results(this.currentQuery, this.remotePage);
    this.matches = result?.items ?? [];
    this.hasMore = result?.hasMore ?? false;
  }

  private queryChanged(): void {
    if (!this.active) { return; }
    const normalized = desktopWorkspaceSearchQuery(this.query).trim();
    if (normalized === this.currentQuery) { return; }
    const host = this.host;
    this.currentQuery = normalized;
    this.remotePage = undefined;
    this.pending = normalized.length > 0 && host !== undefined;
    this.failed = normalized.length > 0 && host === undefined;
    this.refreshResults();
    this.request.cancel();
    if (!normalized || host === undefined) { return; }
    this.request.start(normalized, async (query: string): Promise<Object | undefined> => {
      const result = await host.call('session/search', { 'query': query }, 10000, 163840, true);
      return result.ok ? result.value : undefined;
    }, (page?: DesktopWorkspaceSearchPage): void => {
      if (!this.active || this.host !== host) { return; }
      this.remotePage = page;
      this.pending = false;
      this.failed = page === undefined;
      this.refreshResults();
    });
  }

  private rowById(id: string): DesktopWorkspaceSearchRow | undefined {
    return this.matches.find((row: DesktopWorkspaceSearchRow): boolean => row.id === id);
  }

  @Builder
  private SearchSkeleton() {
    Row({ space: 8 }) {
      Circle().width(7).height(7).fill($r('app.color.workspace_selection'))
      Column({ space: 6 }) {
        Row().width('64%').height(7).borderRadius(3).backgroundColor($r('app.color.workspace_selection'))
        Row().width('82%').height(6).borderRadius(3).backgroundColor($r('app.color.workspace_selection'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').height(36).padding({ left: 14, right: 8 }).accessibilityLevel('no')
  }

  build() {
    List({ space: 2 }) {
      ForEach(this.matches, (entry: DesktopWorkspaceSearchRow): void => {
        ListItem() {
          DesktopWorkspaceSearchResult({
            row: this.rowById(entry.id) ?? entry,
            selected: this.selectedId === entry.id,
            restoreEnabled: this.restoreEnabled,
            onOpen: this.onOpen,
            onRestore: this.onRestore
          })
        }
      }, (entry: DesktopWorkspaceSearchRow): string => entry.id)
      if (this.pending) {
        ListItem() {
          Column() {
            this.SearchSkeleton()
            if (this.matches.length === 0) { this.SearchSkeleton() }
          }.key('desktopWorkspaceSearchPending')
            .accessibilityText($r('app.string.desktop_workspace_search_pending'))
        }
      } else if (this.failed) {
        ListItem() {
          Text($r('app.string.desktop_workspace_search_unavailable'))
            .key('desktopWorkspaceSearchUnavailable').width('100%').padding({ left: 12, top: 12, right: 12, bottom: 8 })
            .fontSize(12).fontColor($r('sys.color.font_tertiary'))
        }
      } else if (this.matches.length === 0) {
        ListItem() {
          Text($r('app.string.desktop_workspace_search_empty'))
            .key('desktopWorkspaceSearchEmpty').width('100%').padding({ left: 12, top: 12, right: 12, bottom: 8 })
            .fontSize(12).fontColor($r('sys.color.font_tertiary'))
        }
      }
      if (this.hasMore) {
        ListItem() {
          Text($r('app.string.desktop_workspace_search_has_more', DESKTOP_WORKSPACE_SEARCH_LIMIT))
            .key('desktopWorkspaceSearchHasMore').width('100%').padding({ left: 12, top: 10, right: 12, bottom: 10 })
            .fontSize(12).fontColor($r('sys.color.font_tertiary'))
        }
      }
    }.key('desktopWorkspaceSearchResults').width('100%').layoutWeight(1).scrollBar(BarState.Auto)
  }
}
