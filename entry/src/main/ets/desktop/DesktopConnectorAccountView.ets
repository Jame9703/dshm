import { LengthMetrics } from '@kit.ArkUI';
import { DesktopConnectorAccounts } from './DesktopConnectorAccounts';
import type { DesktopConnectorAccount, DesktopConnectorAction, DesktopConnectorNote,
  DesktopConnectorPrompt } from './DesktopConnectorAccounts';

function stateColor(phase: string): Resource {
  switch (phase) {
    case 'checking':
    case 'connecting': return $r('sys.color.brand');
    case 'connected': return $r('app.color.desktop_connector_connected');
    case 'unavailable': return $r('sys.color.warning');
    default: return $r('sys.color.font_tertiary');
  }
}

@Component
export struct DesktopConnectorBadge {
  @Prop text: string = '';
  @Prop phase: string = '';

  build() {
    Text(this.text).key('desktopConnectorBadge').fontSize(12).maxLines(1)
      .fontColor(stateColor(this.phase)).padding({ top: 3, bottom: 3, left: 7, right: 7 })
      .borderRadius(6).borderWidth(0.5).borderColor($r('app.color.workspace_border'))
  }
}

@Component
export struct DesktopConnectorAccountView {
  @Prop account?: DesktopConnectorAccount = undefined;
  @Prop actionsEnabled: boolean = false;
  onAction: (account: DesktopConnectorAccount, action: DesktopConnectorAction) => void =
    (_account: DesktopConnectorAccount, _action: DesktopConnectorAction): void => {};

  @Builder
  private Action(action: DesktopConnectorAction) {
    Button(action.label, { buttonStyle: action.variant === 'primary' ? ButtonStyleMode.EMPHASIZED :
      (action.variant === 'ghost' ? ButtonStyleMode.TEXTUAL : ButtonStyleMode.NORMAL) })
      .key('desktopConnectorAction-' + action.kind + (action.operation ? '-' + action.operation : ''))
      .height(30).borderRadius(8).enabled(this.actionsEnabled)
      .onClick((): void => {
        const account = this.account;
        if (account !== undefined) { this.onAction(account, action); }
      })
  }

  build() {
    if (this.account !== undefined) {
      Column({ space: 8 }) {
        Text(this.account.title).fontSize(14).fontWeight(FontWeight.Medium)
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center,
          space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(6) } }) {
          Row({ space: 8 }) {
            Blank().width(8).height(8).borderRadius(4).backgroundColor(stateColor(this.account.phase)).accessibilityLevel('no')
            Text(this.account.status).key('desktopConnectorStatus').fontSize(13).layoutWeight(1)
              .fontColor($r('sys.color.font_primary'))
          }.layoutWeight(1)
          ForEach(this.account.actions, (action: DesktopConnectorAction): void => {
            this.Action(action)
          }, (action: DesktopConnectorAction): string => JSON.stringify(action))
        }.width('100%')
        if (this.account.detail) {
          Text(this.account.detail).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
        ForEach(this.account.notes, (note: DesktopConnectorNote) => {
          Row({ space: 8 }) {
            Text(note.text).fontSize(13).layoutWeight(1).fontColor($r('sys.color.font_secondary'))
            if (note.action !== undefined) { this.Action(note.action) }
          }.width('100%')
        }, (note: DesktopConnectorNote): string => JSON.stringify(note))
        if (this.account.failure) {
          Text(this.account.failure).key('desktopConnectorFailure').fontSize(13)
            .fontColor($r('app.color.workspace_status_error'))
        }
        if (this.account.diagnostics.length > 0) {
          Text($r('app.string.desktop_connector_diagnostic', this.account.diagnostics.join(' · ')))
            .fontSize(13).copyOption(CopyOptions.LocalDevice).fontColor($r('app.color.workspace_status_error'))
        }
        if (this.account.hint) {
          Text(this.account.hint).fontSize(13).fontColor($r('sys.color.font_tertiary'))
        }
      }.key('desktopConnectorSection').width('100%').padding({ top: 6, bottom: 6 })
      .alignItems(HorizontalAlign.Start)
    }
  }
}

@Component
export struct DesktopConnectorDialog {
  @ObjectLink accounts: DesktopConnectorAccounts;
  @Prop accountKey: string = '';
  @Prop activation: boolean = false;
  prompt: DesktopConnectorPrompt = { title: '', body: '', label: '' };
  onDismiss: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  build() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text(this.prompt.title).fontSize(19).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(16).height(16).supportSvg2(true).draggable(false)
            .accessibilityLevel('no')
        }.key('desktopConnectorDialogClose').width(32).height(32).padding(0)
        .accessibilityText($r('app.string.desktop_plugin_install_close')).onClick(this.onDismiss)
      }.width('100%')
      if (this.prompt.body) {
        Text(this.prompt.body).width('100%').fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: 8 }) {
        Blank()
        Button(this.activation ? $r('app.string.desktop_connector_later') : $r('app.string.desktop_connector_cancel'),
          { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopConnectorDialogDismiss').onClick(this.onDismiss)
        Button(this.prompt.label).key('desktopConnectorDialogConfirm').defaultFocus(true)
          .enabled(this.accounts.linked && !this.accounts.pending.includes(this.accountKey)).onClick(this.onConfirm)
      }.width('100%')
    }.key('desktopConnectorDialog').width('100%').padding(20).alignItems(HorizontalAlign.Start)
  }
}
