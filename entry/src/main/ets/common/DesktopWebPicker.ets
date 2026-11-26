import { ComponentContent, promptAction, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { immersiveMaterialOf } from 'platform';
import { buildWebPickerMenu, buildWebPickerPanel, WebPickerPage, WebPickerPanelParams, WebPickerRow } from './WebPickerPanel';

interface ActivePicker {
  id: number;
  content: ComponentContent<WebPickerPanelParams>;
  params: WebPickerPanelParams;
  ui: UIContext;
  send: (id: number, event: string, value: string) => void;
  menu: boolean;
  opened: boolean;
  closing: boolean;
  event: string;
  value: string;
}

function decodePicker(payload: string): WebPickerPage | undefined {
  if (payload.length > 524288) return undefined;
  try {
    const lines: string[] = payload.split('\n');
    const header: string[] = lines[0].split('|').map((field: string): string => decodeURIComponent(field));
    if (header.length !== 5 || lines.length > 1001 || header.some((field: string): boolean => field.length > 2000)) {
      return undefined;
    }
    const rows: WebPickerRow[] = [];
    const keys: Set<string> = new Set<string>();
    for (let i: number = 1; i < lines.length; i++) {
      const cells: string[] = lines[i].split('|');
      if (cells.length !== 5 || cells[0].length === 0) return undefined;
      const flags: number = Number(cells[0]);
      const key: string = decodeURIComponent(cells[1]);
      const label: string = decodeURIComponent(cells[2]);
      if (!Number.isInteger(flags) || flags < 0 || flags > 15 || key.length === 0 || key.length > 512 ||
        label.length === 0 || label.length > 512 || keys.has(key)) return undefined;
      keys.add(key);
      const row: WebPickerRow = {
        key: key, label: label, detail: decodeURIComponent(cells[3]), group: decodeURIComponent(cells[4]),
        selected: (flags & 1) !== 0, disabled: (flags & 2) !== 0, stay: (flags & 4) !== 0, drill: (flags & 8) !== 0
      };
      if (row.detail.length > 2000 || row.group.length > 512) return undefined;
      rows.push(row);
    }
    return { title: header[0], search: header[1], query: header[2], status: header[3], empty: header[4], rows: rows };
  } catch (e) {
    return undefined;
  }
}

function canUsePickerMenu(page: WebPickerPage): boolean {
  return page.title.length === 0 && page.search.length === 0 && page.status.length === 0 &&
    page.empty.length === 0 && page.rows.length > 0 &&
    page.rows.every((row: WebPickerRow): boolean => row.group.length === 0 && !row.stay && !row.drill);
}

function pickerMaterial(menu: boolean): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.sdkApiVersion < 26) return undefined;
  try {
    if (uiMaterial.isImmersiveMaterialSupported()) {
      return immersiveMaterialOf(menu ? uiMaterial.ImmersiveStyle.THICK : uiMaterial.ImmersiveStyle.THIN, false);
    }
  } catch (e) {
    // Use the platform's default menu or dialog background.
  }
  return undefined;
}

export interface WebPickerViewport {
  width: number;
  height: number;
  dark: boolean;
}

export class DesktopWebPicker {
  private active: ActivePicker | undefined;

  isActive(): boolean {
    return this.active !== undefined;
  }

  open(ui: UIContext, id: number, x: number, top: number, bottom: number, viewport: WebPickerViewport,
    payload: string, sender: (id: number, event: string, value: string) => void): boolean {
    if (this.active !== undefined || !Number.isSafeInteger(id) || id <= 0 ||
      !Number.isFinite(x) || !Number.isFinite(top) || !Number.isFinite(bottom) ||
      x < 0 || x > 1 || top < 0 || top > bottom || bottom > 1 || viewport.width < 220 || viewport.height < 200) {
      return false;
    }
    const page: WebPickerPage | undefined = decodePicker(payload);
    if (page === undefined) return false;
    try {
      const anchor = ui.getComponentUtils().getRectangleById('dshm-web-menu-anchor');
      const width: number = Math.min(360, viewport.width - 16);
      const topVp: number = top * viewport.height;
      const bottomVp: number = bottom * viewport.height;
      const below: number = viewport.height - bottomVp - 8;
      const placeBelow: boolean = below >= 330 || below >= topVp - 8;
      const room: number = Math.min(430, Math.max(110, placeBelow ? below : topVp - 8));
      const height: number = Math.max(64, room - 100);
      const params: WebPickerPanelParams = {
        page: page, width: width, height: height, themeDark: viewport.dark,
        search: (value: string): void => this.search(id, value),
        select: (key: string): void => this.select(id, key)
      };
      const menu: boolean = canUsePickerMenu(page);
      const content = new ComponentContent<WebPickerPanelParams>(ui,
        menu ? wrapBuilder(buildWebPickerMenu) : wrapBuilder(buildWebPickerPanel), params);
      const dialog: ActivePicker = {
        id: id, content: content, params: params, ui: ui, send: sender, menu: menu,
        opened: false, closing: false, event: 'dismiss', value: ''
      };
      const left: number = Math.min(Math.max(8, x * viewport.width), viewport.width - width - 8);
      this.active = dialog;
      const opening: Promise<void> = menu
        ? this.openMenu(dialog, left, Math.max(8, placeBelow ? bottomVp + 6 : topVp - room - 6))
        : this.openPanel(dialog, ui.px2vp(anchor.windowOffset.x) + left,
          ui.px2vp(anchor.windowOffset.y) + Math.max(8, placeBelow ? bottomVp + 6 : topVp - room - 6));
      opening.then((): void => {
        if (this.active !== dialog) return;
        dialog.opened = true;
        if (dialog.closing) this.dismiss(dialog);
      }).catch((): void => {
        if (!dialog.closing) dialog.event = 'fallback';
        this.finish(dialog);
      });
      return true;
    } catch (e) {
      const dialog = this.active;
      if (dialog !== undefined && dialog.id === id) {
        dialog.event = '';
        this.finish(dialog);
      }
      return false;
    }
  }

  private openMenu(dialog: ActivePicker, x: number, y: number): Promise<void> {
    // A plain choice list uses the same system menu surface as the account menu.
    const options: MenuOptions = {
      anchorPosition: { x: x, y: y },
      systemMaterial: pickerMaterial(true),
      onDisappear: (): void => this.finish(dialog)
    };
    return dialog.ui.getPromptAction().openMenu(dialog.content, { id: 'dshm-web-menu-anchor' }, options);
  }

  private openPanel(dialog: ActivePicker, x: number, y: number): Promise<void> {
    const options: promptAction.BaseDialogOptions = {
      alignment: DialogAlignment.TopStart,
      offset: { dx: x, dy: y },
      autoCancel: true,
      maskColor: Color.Transparent,
      systemMaterial: pickerMaterial(false),
      onWillDismiss: (action: DismissDialogAction): void => {
        if (!dialog.closing && action.reason === DismissReason.PRESS_BACK &&
          dialog.params.page.rows.some((row: WebPickerRow): boolean => row.key === 'back' && row.stay)) {
          this.select(dialog.id, 'back');
          return;
        }
        action.dismiss();
      },
      onDidDisappear: (): void => this.finish(dialog)
    };
    return dialog.ui.getPromptAction().openCustomDialog(dialog.content, options);
  }

  update(id: number, payload: string): boolean {
    const dialog = this.active;
    if (dialog === undefined || dialog.id !== id || dialog.closing) return false;
    const page: WebPickerPage | undefined = decodePicker(payload);
    if (page === undefined || (dialog.menu && !canUsePickerMenu(page))) return false;
    const current = dialog.params;
    const params: WebPickerPanelParams = {
      page: page, width: current.width, height: current.height, themeDark: current.themeDark,
      search: current.search, select: current.select
    };
    try {
      dialog.content.update(params);
      dialog.params = params;
      return true;
    } catch (e) {
      return false;
    }
  }

  close(id?: number): void {
    const dialog = this.active;
    if (dialog === undefined || (id !== undefined && dialog.id !== id) || dialog.closing) return;
    dialog.event = '';
    this.dismiss(dialog);
  }

  private search(id: number, value: string): void {
    const dialog = this.active;
    if (dialog !== undefined && dialog.id === id && !dialog.closing && dialog.params.page.search.length > 0) {
      dialog.send(id, 'search', value.slice(0, 300));
    }
  }

  private select(id: number, key: string): void {
    const dialog = this.active;
    if (dialog === undefined || dialog.id !== id || dialog.closing) return;
    const row = dialog.params.page.rows.find((item: WebPickerRow): boolean => item.key === key);
    if (row === undefined || row.disabled) return;
    if (row.stay) {
      dialog.send(id, 'select', key);
      return;
    }
    dialog.event = 'select';
    dialog.value = key;
    this.dismiss(dialog);
  }

  private dismiss(dialog: ActivePicker): void {
    dialog.closing = true;
    if (!dialog.opened) return;
    try {
      const prompt = dialog.ui.getPromptAction();
      const closing: Promise<void> = dialog.menu ? prompt.closeMenu(dialog.content) : prompt.closeCustomDialog(dialog.content);
      closing.catch((): void => this.finish(dialog));
    } catch (e) {
      this.finish(dialog);
    }
  }

  private finish(dialog: ActivePicker): void {
    if (this.active !== dialog) return;
    this.active = undefined;
    try {
      dialog.content.dispose();
    } catch (e) {
      // Window destruction can release the content first.
    }
    if (dialog.event.length > 0) dialog.send(dialog.id, dialog.event, dialog.value);
  }
}
