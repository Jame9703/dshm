import { desktopWorkspaceRelativePath } from './DesktopFileSearchResults';

export enum DesktopFileNavigatorMode {
  PUSH = 'push', OVERLAY = 'overlay', FILL = 'fill'
}

export const DESKTOP_FILE_NAVIGATOR_DEFAULT_WIDTH: number = 260;

export interface DesktopFileNavigatorBounds {
  minimum: number;
  maximum: number;
  width: number;
}

export function desktopFileNavigatorMode(rowWidth: number, windowWidth: number): DesktopFileNavigatorMode {
  if (windowWidth < 768 || rowWidth < 400) { return DesktopFileNavigatorMode.FILL; }
  return rowWidth >= 560 ? DesktopFileNavigatorMode.PUSH : DesktopFileNavigatorMode.OVERLAY;
}

export function desktopFileNavigatorBounds(rowWidth: number, preference: number): DesktopFileNavigatorBounds {
  const maximum = Math.max(0, rowWidth - (rowWidth >= 560 ? 336 : 120));
  const minimum = Math.min(180, maximum);
  return { minimum: minimum, maximum: maximum, width: Math.min(Math.max(minimum, preference), maximum) };
}

export function desktopFileNavigatorRelativePath(path: string, workspace: string): string {
  const root = workspace.replace(new RegExp('/+$'), '');
  const relative = path.startsWith('/') && (root || workspace === '/') && path.startsWith(root + '/') ?
    path.slice(root.length + 1) : path;
  return desktopWorkspaceRelativePath(relative) ? relative : '';
}
