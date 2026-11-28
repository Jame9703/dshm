import { getArray, getRecord, getString } from 'connection';
import { desktopLocalizedText } from './DesktopHostActions';
import { DesktopPluginArtwork, desktopPluginIcon } from './DesktopPluginArtwork';

export interface DesktopPluginComponent {
  rowId: string;
  entryId: string;
  module: string;
  title: string;
  description: string;
  artwork: string;
}

export interface DesktopPluginComponentView {
  component: DesktopPluginComponent;
  toggle: boolean;
  settings: boolean;
  enabled: boolean;
  phase: string;
  diagnostic: string;
}

export function desktopPluginComponents(value: Object, locale: string = ''): DesktopPluginComponent[] {
  const rows: DesktopPluginComponent[] = [];
  const seen = new Set<string>();
  for (const row of getArray(value, 'rows') ?? []) {
    const rowId = getString(row, 'rowId') ?? '';
    if (!rowId || seen.has(rowId)) { continue; }
    seen.add(rowId);
    const meta = getRecord(row, 'meta');
    rows.push({ rowId: rowId, entryId: getString(row, 'entryId') ?? '', module: getString(row, 'moduleName') ?? '',
      title: desktopLocalizedText(meta, 'title', locale) || rowId,
      description: desktopLocalizedText(meta, 'description', locale),
      artwork: desktopPluginIcon(getString(meta, 'icon') ?? '') });
  }
  return rows;
}

@Component
export struct DesktopPluginBundleComponents {
  @Prop rows: DesktopPluginComponentView[] = [];
  @Prop busy: boolean = false;
  onSettings: (rowId: string) => void = (_rowId: string): void => {};
  onToggle: (entryId: string, enabled: boolean) => void = (_entryId: string, _enabled: boolean): void => {};
  @State private query: string = '';

  private visibleRows(): DesktopPluginComponentView[] {
    const query = this.query.trim().toLowerCase();
    return query ? this.rows.filter((row: DesktopPluginComponentView): boolean =>
      [row.component.title, row.component.rowId, row.component.module, row.component.description]
        .some((text: string): boolean => text.toLowerCase().includes(query))) : this.rows;
  }

  private status(row: DesktopPluginComponentView): Resource {
    if (row.phase === 'failed') { return $r('app.string.desktop_plugin_component_failed'); }
    if (row.phase === 'loading' || row.phase === 'pending' || row.phase === 'unloading') {
      return $r('app.string.desktop_plugin_component_changing');
    }
    return row.enabled ? $r('app.string.desktop_plugin_component_enabled') : $r('app.string.desktop_plugin_component_disabled');
  }

  build() {
    if (this.rows.length > 0) {
      Column({ space: 8 }) {
        Text($r('app.string.desktop_plugin_components')).fontSize(17).fontWeight(FontWeight.Medium)
        if (this.rows.length > 10) {
          TextInput({ text: this.query, placeholder: $r('app.string.desktop_plugin_components_filter') })
            .width('100%').onChange((value: string): void => { this.query = value; })
        }
        ForEach(this.visibleRows(), (row: DesktopPluginComponentView): void => {
          Row({ space: 12 }) {
            DesktopPluginArtwork({ icon: row.component.artwork, packageName: row.component.module, component: true,
              artworkSize: 30 })
            Column({ space: 4 }) {
              Text(row.component.title).fontSize(14).fontWeight(FontWeight.Medium)
              Text(row.component.description || row.component.module).fontSize(12).fontColor($r('sys.color.font_secondary'))
              Text(this.status(row)).fontSize(12).fontColor($r('sys.color.font_secondary'))
              if (row.diagnostic) {
                Text(row.diagnostic).fontSize(12).fontColor($r('app.color.workspace_status_error'))
              }
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (row.settings) {
              Button($r('app.string.desktop_plugin_component_configure'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                .key('desktopPluginComponentSettings-' + row.component.rowId).enabled(!this.busy)
                .onClick((): void => { this.onSettings(row.component.rowId); })
            }
            if (row.toggle) {
              Toggle({ type: ToggleType.Switch, isOn: row.enabled }).enabled(!this.busy)
                .key('desktopPluginEntryToggle-' + row.component.entryId).accessibilityText(row.component.title)
                .onChange((enabled: boolean): void => {
                  if (enabled !== row.enabled) { this.onToggle(row.component.entryId, enabled); }
                })
            }
          }.key('desktopPluginComponent-' + row.component.rowId).width('100%').padding(10).borderRadius(10)
            .backgroundColor($r('app.color.workspace_panel'))
        }, (row: DesktopPluginComponentView): string => JSON.stringify(row))
        if (this.visibleRows().length === 0) {
          Text($r('app.string.desktop_plugin_components_no_matches')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
      }.key('desktopPluginBundleComponents').width('100%').alignItems(HorizontalAlign.Start)
    }
  }
}
