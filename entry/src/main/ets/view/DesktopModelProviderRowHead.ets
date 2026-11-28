export enum DesktopModelProviderBadge {
  NONE,
  MISSING,
  CONFIGURED,
  SIGNED_IN
}

/** Pass the named credential's status. A derived fallback has no badge of its own. */
export function desktopModelProviderBadge(accountSignedIn: boolean, credentialRef: string,
  credentialConfigured: boolean | undefined): DesktopModelProviderBadge {
  if (accountSignedIn) { return DesktopModelProviderBadge.SIGNED_IN; }
  if (credentialConfigured === true) { return DesktopModelProviderBadge.CONFIGURED; }
  if (credentialRef && credentialConfigured === false) { return DesktopModelProviderBadge.MISSING; }
  return DesktopModelProviderBadge.NONE;
}

@Component
export struct DesktopModelProviderRowHead {
  @Prop rowKey: string = '';
  @Prop label: ResourceStr = '';
  @Prop credential: DesktopModelProviderBadge = DesktopModelProviderBadge.NONE;
  @Prop declared: boolean = false;
  @Prop editable: boolean = false;
  @Prop removable: boolean = false;
  @Prop editing: boolean = false;
  @Prop writable: boolean = false;
  onEdit: () => void = (): void => {};
  onRemove: () => void = (): void => {};

  private providerName(): string {
    const label = this.label;
    return typeof label === 'string' ? label :
      this.getUIContext().getHostContext()?.resourceManager.getStringSync(label) ?? this.rowKey;
  }

  @Builder
  private CredentialBadge() {
    if (this.credential === DesktopModelProviderBadge.SIGNED_IN) {
      Row({ space: 6 }) {
        Circle().width(8).height(8).fill($r('sys.color.confirm')).accessibilityLevel('no')
        Text($r('app.string.desktop_model_provider_row_signed_in'))
          .fontSize(13).lineHeight(20).fontColor($r('sys.color.confirm'))
      }.key('desktopModelProviderCredential-' + this.rowKey).flexShrink(0)
    } else if (this.credential !== DesktopModelProviderBadge.NONE) {
      Circle().key('desktopModelProviderCredential-' + this.rowKey).width(8).height(8).flexShrink(0)
        .fill(this.credential === DesktopModelProviderBadge.MISSING ? $r('sys.color.alert') : $r('sys.color.confirm'))
        .accessibilityRole(AccessibilityRoleType.IMAGE)
        .accessibilityText(this.credential === DesktopModelProviderBadge.MISSING ?
          $r('app.string.desktop_model_provider_row_credential_missing') :
          $r('app.string.desktop_model_provider_row_credential_configured'))
    }
  }

  build() {
    Row({ space: 10 }) {
      Row({ space: 6 }) {
        Text(this.label).fontSize(14).lineHeight(22).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).flexShrink(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.declared) {
          Text($r('app.string.desktop_model_provider_row_custom')).key('desktopModelProviderCustom-' + this.rowKey)
            .fontSize(11).lineHeight(16).fontColor($r('sys.color.font_secondary')).flexShrink(0)
            .padding({ top: 1, bottom: 1, left: 6, right: 6 }).borderRadius(4)
            .border({ width: 0.5, color: $r('app.color.workspace_border') })
        }
        this.CredentialBadge()
      }.layoutWeight(1).alignItems(VerticalAlign.Center)
      if (this.editable || this.removable) {
        Row({ space: 4 }) {
          if (this.editable) {
            Button($r('app.string.desktop_model_provider_row_edit'),
              { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopModelProviderEdit-' + this.rowKey).height(28).borderRadius(6)
              .padding({ left: 10, right: 10 }).fontSize(12).fontColor($r('sys.color.font_primary'))
              .border({ width: 0.5, color: $r('app.color.workspace_border') })
              .accessibilityText($r('app.string.desktop_model_provider_row_edit_named', this.providerName()))
              .accessibilitySelected(this.editing).onClick(this.onEdit)
          }
          if (this.removable) {
            Button($r('app.string.desktop_model_provider_row_remove'),
              { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
              .key('desktopModelProviderRemove-' + this.rowKey).height(28).borderRadius(6)
              .padding({ left: 10, right: 10 }).fontSize(12).fontColor($r('sys.color.alert'))
              .accessibilityText($r('app.string.desktop_model_provider_row_remove_named', this.providerName()))
              .enabled(this.writable).onClick((): void => { if (this.writable) { this.onRemove(); } })
          }
        }.flexShrink(0)
      }
    }.key('desktopModelProviderHead-' + this.rowKey).width('100%').alignItems(VerticalAlign.Center)
  }
}
