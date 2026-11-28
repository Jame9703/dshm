import { DesktopPluginMaintenance } from './DesktopPluginMaintenance';

@Component
export struct DesktopPluginMaintenanceDialog {
  @ObjectLink model: DesktopPluginMaintenance;
  onConfirm: () => void = (): void => {};
  onClose: () => void = (): void => {};
  @State private showOutput: boolean = false;

  private stepLabel(): Resource {
    switch (this.model.step) {
      case 'checking': return $r('app.string.desktop_plugin_maintenance_checking');
      case 'removing': return $r('app.string.desktop_plugin_maintenance_removing');
      case 'installing': return $r('app.string.desktop_plugin_maintenance_installing');
      case 'restoring': return $r('app.string.desktop_plugin_maintenance_restoring');
      default: return $r('app.string.desktop_plugin_maintenance_waiting');
    }
  }

  private resultLabel(): Resource {
    if (this.model.connectionLost) { return $r('app.string.desktop_plugin_maintenance_unknown'); }
    if (this.model.application === 'applied') { return $r('app.string.desktop_plugin_maintenance_done'); }
    if (this.model.application === 'restart-required') { return $r('app.string.desktop_plugin_maintenance_restart'); }
    return $r('app.string.desktop_plugin_maintenance_failed');
  }

  build() {
    Column({ space: 14 }) {
      Text(this.model.action === 'update' ? $r('app.string.desktop_plugin_maintenance_update') :
        $r('app.string.desktop_plugin_maintenance_remove'))
        .fontSize(21).fontWeight(FontWeight.Medium).width('100%')
      Text(this.model.title).width('100%').fontSize(15)
      if (this.model.action === 'update') {
        Text(this.model.fromVersion + ' → ' + this.model.toVersion)
          .width('100%').fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      if (this.model.catalog !== undefined) {
        Column({ space: 4 }) {
          Text($r('app.string.desktop_plugin_catalog_source')).fontSize(13)
          Text(this.model.catalog.fromSource).key('desktopPluginMaintenanceSourceFrom')
            .fontSize(12).fontColor($r('sys.color.font_secondary')).copyOption(CopyOptions.LocalDevice)
          Text(this.model.catalog.targetSpec).key('desktopPluginMaintenanceSourceTo')
            .fontSize(12).fontColor($r('sys.color.brand')).copyOption(CopyOptions.LocalDevice)
        }.key('desktopPluginMaintenanceSourceChange').width('100%').alignItems(HorizontalAlign.Start)
      }
      if (this.model.phase === 'confirm') {
        Text(this.model.action === 'update' ? $r('app.string.desktop_plugin_maintenance_update_note') :
          $r('app.string.desktop_plugin_maintenance_remove_note'))
          .width('100%').fontSize(13).fontColor($r('sys.color.font_secondary'))
      } else if (this.model.phase === 'running') {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).accessibilityLevel('no')
          Text(this.stepLabel()).key('desktopPluginMaintenanceStep').fontSize(14)
        }.width('100%')
      } else if (this.model.phase === 'done') {
        Text(this.resultLabel()).width('100%').key('desktopPluginMaintenanceResult').fontSize(14)
        if (this.model.problem) {
          Text(this.model.problem).width('100%').fontSize(13).fontColor($r('app.color.workspace_status_error'))
        }
        if (this.model.restore) {
          Text(this.model.restore === 'applied' || this.model.restore === 'restart-required' ?
            $r('app.string.desktop_plugin_maintenance_restored') : $r('app.string.desktop_plugin_maintenance_restore_failed'))
            .key('desktopPluginMaintenanceRestore').width('100%').fontSize(13)
        }
      }
      if (this.model.output) {
        Button(this.showOutput ? $r('app.string.desktop_plugin_maintenance_hide_output') :
          $r('app.string.desktop_plugin_maintenance_show_output'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => { this.showOutput = !this.showOutput; })
        if (this.showOutput) {
          Scroll() {
            Text(this.model.output).width('100%').fontFamily('monospace').fontSize(12).copyOption(CopyOptions.LocalDevice)
          }.width('100%').constraintSize({ maxHeight: 160 })
        }
      }
      if (this.model.phase !== 'running') {
        Row({ space: 8 }) {
          Blank()
          Button(this.model.phase === 'confirm' ? $r('app.string.desktop_plugin_maintenance_cancel') :
            $r('app.string.desktop_plugin_maintenance_close'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopPluginMaintenanceClose').onClick(this.onClose)
          if (this.model.phase === 'confirm') {
            Button(this.model.action === 'update' ? $r('app.string.desktop_plugin_maintenance_update_action') :
              $r('app.string.desktop_plugin_maintenance_remove_action'))
              .key('desktopPluginMaintenanceConfirm').onClick(this.onConfirm)
          }
        }.width('100%')
      }
    }.key('desktopPluginMaintenanceDialog').width('100%').padding(24).alignItems(HorizontalAlign.Start)
  }
}
