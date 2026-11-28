export interface DesktopTimelineDetailTarget {
  tree: string;
  id: string;
  scroll: number;
}

export interface DesktopTimelineRulerViewport {
  zoom: number;
  level: number;
  anchor: number;
  pinned: boolean;
  backMs: number;
  horizontal: number;
  newest: string;
  unread: boolean;
}

/** Session-local state that survives Dock component replacement without publishing scroll frames to the workspace. */
export class DesktopTimelineViewport {
  lease: number = 0;
  locationRevision: number = 0;
  tab: string = 'tasks';
  taskTrail: DesktopTimelineDetailTarget[] = [];
  reportTrail: DesktopTimelineDetailTarget[] = [];
  taskScroll: number = 0;
  reportScroll: number = 0;
  ruler?: DesktopTimelineRulerViewport;
}
