import { desktopWorkspaceRelativePath } from './DesktopFileSearchResults';

export enum DesktopFileContextAction {
  SIDEBAR = 'sidebar', FLOAT = 'float', REVEAL = 'reveal', OPEN = 'open', COPY_PATH = 'copyPath',
  COPY_IMAGE = 'copyImage', DOWNLOAD = 'download', ADD_TO_CHAT = 'addToChat'
}

export interface DesktopFileContextItem {
  action: DesktopFileContextAction;
  enabled: boolean;
}

export function desktopFileContextCopyPath(root: string, path: string): string {
  if (path.startsWith('/') && !path.includes('\0')) { return path; }
  if (!root.startsWith('/') || root.includes('\0')) { return ''; }
  if (path === '.') { return root; }
  if (!desktopWorkspaceRelativePath(path)) { return ''; }
  return root.replace(new RegExp('/+$'), '') + '/' + path;
}

export function desktopFileContextPathItems(directory: boolean, canLocate: boolean,
  validFile: boolean, canCopyPath: boolean): DesktopFileContextItem[] {
  if (directory) {
    return [{ action: DesktopFileContextAction.REVEAL, enabled: canLocate },
      { action: DesktopFileContextAction.COPY_PATH, enabled: canCopyPath }];
  }
  return [{ action: DesktopFileContextAction.SIDEBAR, enabled: validFile },
    { action: DesktopFileContextAction.FLOAT, enabled: validFile },
    { action: DesktopFileContextAction.REVEAL, enabled: canLocate },
    { action: DesktopFileContextAction.OPEN, enabled: canLocate },
    { action: DesktopFileContextAction.COPY_PATH, enabled: canCopyPath }];
}

export function desktopFileContextTransferItems(isImage: boolean,
  canCopyImage: boolean, canDownload: boolean): DesktopFileContextItem[] {
  const items: DesktopFileContextItem[] = [];
  if (isImage) { items.push({ action: DesktopFileContextAction.COPY_IMAGE, enabled: canCopyImage }); }
  items.push({ action: DesktopFileContextAction.DOWNLOAD, enabled: canDownload });
  return items;
}
