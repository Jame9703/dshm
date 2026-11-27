import { DesktopPluginInstall } from './DesktopPluginInstall';
import { desktopMenuOptions } from './DesktopMenuOptions';

@Component
export struct DesktopPluginInstallDialog {
  @ObjectLink installer: DesktopPluginInstall;
  onClose: () => void = (): void => {};
  onEnable: () => void = (): void => {};
  @State private detailsOpen: boolean = false;

  private phaseTitle(): Resource {
    switch (this.installer.phase) {
      case 'starting': return $r('app.string.desktop_plugin_install_starting');
      case 'running': return $r('app.string.desktop_plugin_install_running');
      case 'applying': return $r('app.string.desktop_plugin_install_applying');
      case 'cancelling': return $r('app.string.desktop_plugin_install_cancelling');
      case 'unconfirmed':
      case 'unknown': return $r('app.string.desktop_plugin_install_unknown');
      case 'failed': return $r('app.string.desktop_plugin_install_failed');
      case 'cancelled': return $r('app.string.desktop_plugin_install_cancelled');
      default: return $r('app.string.desktop_plugin_install_done');
    }
  }

  private registryActions(): MenuElement[] {
    const options: MenuElement[] = [{ value: $r('app.string.desktop_plugin_install_default_registry'),
      action: (): void => { this.installer.registry = ''; } }];
    for (const registry of this.installer.registries) {
      options.push({ value: registry, action: (): void => { this.installer.registry = registry; } });
    }
    return options;
  }

  @Builder
  private Input() {
    Text($r('app.string.desktop_plugin_install_spec')).fontSize(13)
      .fontColor($r('sys.color.font_secondary'))
    TextInput({ text: this.installer.spec, placeholder: $r('app.string.desktop_plugin_install_placeholder') })
      .key('desktopPluginInstallSpec').width('100%').enabled(this.installer.phase !== 'checking')
      .onChange((value: string): void => { this.installer.spec = value; })
      .onSubmit((): void => { this.installer.inspect(); })
    Row({ space: 8 }) {
      TextInput({ text: this.installer.registry, placeholder: $r('app.string.desktop_plugin_install_default_registry') })
        .key('desktopPluginInstallRegistry').layoutWeight(1).enabled(this.installer.phase !== 'checking')
        .onChange((value: string): void => { this.installer.registry = value; })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Image($r('app.media.dsh_queue_chevron_down_outline')).width(16).height(16).supportSvg2(true)
          .draggable(false).accessibilityLevel('no')
      }.width(36).height(36).padding(0).borderRadius(8).key('desktopPluginInstallRegistryOptions')
      .accessibilityText($r('app.string.desktop_plugin_install_registry')).enabled(this.installer.phase !== 'checking')
      .bindMenu(this.registryActions(), desktopMenuOptions(Placement.BottomRight))
    }.width('100%')
  }

  @Builder
  private Identity() {
    Column({ space: 6 }) {
      Text(this.installer.name || this.installer.spec).fontSize(17).fontWeight(FontWeight.Medium)
        .key('desktopPluginInstallName').copyOption(CopyOptions.InApp)
      if (this.installer.version) {
        Text(this.installer.version).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      if (this.installer.description && this.installer.phase === 'review') {
        Text(this.installer.description).fontSize(14).maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis })
          .copyOption(CopyOptions.InApp)
      }
      if (this.installer.source) {
        Text(this.installer.source).fontSize(12).fontColor($r('sys.color.font_secondary')).copyOption(CopyOptions.InApp)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(10).borderRadius(9)
    .backgroundColor($r('app.color.workspace_selection'))
  }

  @Builder
  private Status() {
    Row({ space: 8 }) {
      if (this.installer.busy() && this.installer.phase !== 'unconfirmed') { LoadingProgress().width(16).height(16) }
      Text(this.phaseTitle()).key('desktopPluginInstallPhase').fontSize(15).fontWeight(FontWeight.Medium)
    }
    if (this.installer.tried) {
      Text(this.installer.tried).fontSize(13).fontColor($r('sys.color.font_secondary'))
    }
    if (this.installer.phase === 'done' && this.installer.restartRequired) {
      Text($r('app.string.desktop_plugin_install_restart')).fontSize(13).fontColor($r('sys.color.font_secondary'))
    }
  }

  @Builder
  private Output() {
    if (this.installer.output || this.installer.logPath) {
      Button(this.detailsOpen ? $r('app.string.desktop_plugin_install_hide_logs') :
        $r('app.string.desktop_plugin_install_show_logs'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopPluginInstallLogs').onClick((): void => { this.detailsOpen = !this.detailsOpen; })
      if (this.detailsOpen) {
        Scroll() {
          Column({ space: 6 }) {
            Text(this.installer.output).fontSize(12).fontFamily('monospace').key('desktopPluginInstallOutput')
              .copyOption(CopyOptions.InApp).width('100%')
            if (this.installer.logPath) {
              Text(this.installer.logPath).fontSize(12).fontColor($r('sys.color.font_secondary'))
                .copyOption(CopyOptions.InApp).width('100%')
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(8)
        }.width('100%').constraintSize({ maxHeight: 230 }).align(Alignment.TopStart).borderRadius(8)
        .backgroundColor($r('app.color.workspace_canvas'))
      }
    }
  }

  @Builder
  private Buttons() {
    Row({ space: 8 }) {
      Blank()
      if (this.installer.phase === 'idle' || this.installer.phase === 'checking') {
        Button($r('app.string.desktop_plugin_install_close'), { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(this.onClose)
        Button($r('app.string.desktop_plugin_install_check')).key('desktopPluginInstallInspect')
          .enabled(this.installer.phase === 'idle' && this.installer.spec.trim().length > 0)
          .onClick((): void => { this.installer.inspect(); })
      } else if (this.installer.phase === 'review') {
        Button($r('app.string.desktop_plugin_install_back'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => { this.installer.edit(); })
        Button($r('app.string.desktop_plugin_install_confirm')).key('desktopPluginInstallConfirm')
          .onClick((): void => { this.installer.start(); })
      } else if (this.installer.busy()) {
        if (this.installer.phase === 'unconfirmed' || (this.installer.phase === 'applying' && this.installer.problem)) {
          Button($r('app.string.desktop_plugin_install_recover'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopPluginInstallRecover').onClick((): void => { this.installer.recover(); })
        }
        if (this.installer.phase !== 'applying') {
          Button($r('app.string.desktop_plugin_install_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopPluginInstallCancel').enabled(this.installer.phase !== 'cancelling')
            .onClick((): void => { this.installer.cancel(); })
        }
        Button($r('app.string.desktop_plugin_install_hide')).key('desktopPluginInstallHide').onClick(this.onClose)
      } else {
        if (this.installer.phase === 'done' || this.installer.phase === 'unknown') {
          Button($r('app.string.desktop_plugin_install_another'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopPluginInstallAnother').enabled(!this.installer.enabling)
            .onClick((): void => { this.detailsOpen = false; this.installer.reset(); })
        } else {
          Button($r('app.string.desktop_plugin_install_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopPluginInstallRetry').onClick((): void => { this.detailsOpen = false; this.installer.edit(); })
        }
        if (this.installer.phase === 'done' && this.installer.installedName && !this.installer.enabled) {
          Button($r('app.string.desktop_plugin_install_enable')).key('desktopPluginInstallEnable')
            .enabled(!this.installer.enabling).onClick(this.onEnable)
        } else {
          Button($r('app.string.desktop_plugin_install_close')).onClick(this.onClose)
        }
      }
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.desktop_plugin_install_add')).fontSize(20).fontWeight(FontWeight.Medium)
        Blank()
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true)
            .draggable(false).accessibilityLevel('no')
        }.width(34).height(34).padding(0).borderRadius(8).key('desktopPluginInstallClose')
        .accessibilityText($r('app.string.desktop_plugin_install_close')).onClick(this.onClose)
      }.width('100%')
      if (this.installer.phase === 'idle' || this.installer.phase === 'checking') {
        this.Input()
      } else {
        this.Identity()
        if (this.installer.phase !== 'review') { this.Status() }
        this.Output()
      }
      if (this.installer.problem) {
        Text(this.installer.problem).key('desktopPluginInstallProblem').fontSize(13)
          .fontColor($r('app.color.workspace_status_error')).width('100%').copyOption(CopyOptions.InApp)
      }
      this.Buttons()
    }.key('desktopPluginInstallDialog').padding(18).width('100%').alignItems(HorizontalAlign.Start)
  }
}
