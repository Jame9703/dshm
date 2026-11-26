import { ComponentContent, promptAction, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { immersiveMaterialOf } from 'platform';
import { buildWebPickerPanel, WebPickerPage, WebPickerPanelParams, WebPickerRow } from './WebPickerPanel';

interface ActivePicker {
  id: number;
  content: ComponentContent<WebPickerPanelParams>;
  params: WebPickerPanelParams;
  ui: UIContext;
  send: (id: number, event: string, value: string) => void;
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
      const content = new ComponentContent<WebPickerPanelParams>(ui, wrapBuilder(buildWebPickerPanel), params);
      const dialog: ActivePicker = {
        id: id, content: content, params: params, ui: ui, send: sender,
        opened: false, closing: false, event: 'dismiss', value: ''
      };
      const baseX: number = ui.px2vp(anchor.windowOffset.x);
      const baseY: number = ui.px2vp(anchor.windowOffset.y);
      const options: promptAction.BaseDialogOptions = {
        alignment: DialogAlignment.TopStart,
        offset: {
          dx: baseX + Math.min(Math.max(8, x * viewport.width), viewport.width - width - 8),
          dy: baseY + Math.max(8, placeBelow ? bottomVp + 6 : topVp - room - 6)
        },
        autoCancel: true,
        maskColor: Color.Transparent,
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
      if (deviceInfo.sdkApiVersion >= 26) {
        try {
          if (uiMaterial.isImmersiveMaterialSupported()) {
            options.systemMaterial = immersiveMaterialOf(uiMaterial.ImmersiveStyle.THIN, false);
          }
        } catch (e) {
          // The default dialog style still shows the original options.
        }
      }
      this.active = dialog;
      ui.getPromptAction().openCustomDialog(content, options).then((): void => {
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

  update(id: number, payload: string): boolean {
    const dialog = this.active;
    if (dialog === undefined || dialog.id !== id || dialog.closing) return false;
    const page: WebPickerPage | undefined = decodePicker(payload);
    if (page === undefined) return false;
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
      dialog.ui.getPromptAction().closeCustomDialog(dialog.content).catch((): void => this.finish(dialog));
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
