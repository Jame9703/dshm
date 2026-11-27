import { LengthMetrics } from '@kit.ArkUI';
import { openExternalUrl } from 'platform';
import { desktopAccountMetadata, desktopAccountLocale } from './DesktopAccountClient';
import {
  DesktopAccountSettingsBalances, DesktopAccountSettingsIdentity, DesktopAccountSettingsProfile, DesktopAccountSettingsWallet,
  desktopAccountPlatformHome, desktopAccountPlatformLink, desktopAccountSettingsBalances, desktopAccountSettingsProfile,
  emptyDesktopAccountSettingsIdentity
} from './DesktopAccountSettingsModel';
import type { DesktopHostActions } from './DesktopHostActions';

@Component
export struct DesktopAccountSettings {
  host?: DesktopHostActions;
  @Prop @Watch('identityChanged') identity: DesktopAccountSettingsIdentity = emptyDesktopAccountSettingsIdentity();
  @Prop @Watch('identityChanged') localePreference: string = 'system';
  @StorageProp('dshDesktopVoiceForeground') @Watch('foregroundChanged') private foreground: boolean = true;
  @State private profile?: DesktopAccountSettingsProfile = undefined;
  @State private balances?: DesktopAccountSettingsBalances = undefined;
  @State private profileLoaded: boolean = false;
  @State private balanceLoaded: boolean = false;
  @State private avatarReady: boolean = false;
  @State private avatarFailed: boolean = false;
  @State private avatarImageEpoch: number = 0;
  @State private linkFailed: boolean = false;
  @State private infoUrl: string = '';
  @State private usageUrl: string = '';
  @State private topUpUrl: string = '';
  private active: boolean = false;
  private readVersion: number = 0;
  private lastIdentity?: DesktopAccountSettingsIdentity;
  private lastLocale: string = '';
  private refreshOnReturn: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.identityChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.readVersion++;
    this.lastIdentity = undefined;
    this.refreshOnReturn = false;
  }

  private identityChanged(): void {
    if (!this.active) { return; }
    const identity = this.identity;
    const locale = desktopAccountLocale(this.localePreference);
    const previous = this.lastIdentity;
    this.infoUrl = identity.signedIn ? desktopAccountPlatformHome(identity.usageUrl) : '';
    this.usageUrl = identity.signedIn ? desktopAccountPlatformLink(identity.usageUrl) : '';
    this.topUpUrl = identity.signedIn ? desktopAccountPlatformLink(identity.topUpUrl) : '';
    if (previous !== undefined && previous.revision === identity.revision && previous.signedIn === identity.signedIn &&
      this.lastLocale === locale) { return; }
    this.lastIdentity = identity;
    this.lastLocale = locale;
    this.refreshOnReturn = false;
    this.linkFailed = false;
    this.profile = undefined;
    this.balances = undefined;
    this.profileLoaded = false;
    this.balanceLoaded = false;
    this.avatarImageEpoch++;
    this.avatarReady = false;
    this.avatarFailed = false;
    this.refresh();
  }

  private foregroundChanged(): void {
    if (this.foreground && this.refreshOnReturn) {
      this.refreshOnReturn = false;
      this.refresh();
    }
  }

  private refresh(): void {
    const version = ++this.readVersion;
    const host = this.host;
    if (!this.active || !this.identity.signedIn) { return; }
    if (host === undefined) {
      this.profileLoaded = true;
      this.balanceLoaded = true;
      return;
    }
    const metadata = desktopAccountMetadata(this.lastLocale);
    host.call('account/getProfile', { 'client': metadata }).then(result => {
      if (this.active && version === this.readVersion) {
        const next = result.ok ? desktopAccountSettingsProfile(result.value) : undefined;
        if (next?.avatarUrl !== this.profile?.avatarUrl || this.avatarFailed) {
          this.avatarImageEpoch++;
          this.avatarReady = false;
          this.avatarFailed = false;
        }
        this.profile = next;
        this.profileLoaded = true;
      }
    }).catch((): void => {
      if (this.active && version === this.readVersion) { this.profileLoaded = true; }
    });
    host.call('account/getBalance', { 'client': metadata }).then(result => {
      if (this.active && version === this.readVersion) {
        this.balances = result.ok ? desktopAccountSettingsBalances(result.value) : undefined;
        this.balanceLoaded = true;
      }
    }).catch((): void => {
      if (this.active && version === this.readVersion) { this.balanceLoaded = true; }
    });
  }

  private async followLink(target: string, refreshBalance: boolean): Promise<void> {
    if (!this.active || !this.identity.signedIn || !target) { return; }
    const accountRevision = this.identity.revision;
    this.linkFailed = false;
    if (refreshBalance) { this.refreshOnReturn = true; }
    const opened = await openExternalUrl(target);
    if (!this.active || this.identity.revision !== accountRevision || opened) { return; }
    if (refreshBalance) { this.refreshOnReturn = false; }
    this.linkFailed = true;
  }

  @Builder
  private AvatarPicture(src: string, epoch: number) {
    Image(src).key('desktopAccountSettingsAvatarImage-' + epoch.toString())
      .width(32).height(32).objectFit(ImageFit.Cover).borderRadius(16).draggable(false).accessibilityLevel('no')
      .opacity(this.avatarReady ? 1 : 0)
      .onComplete((): void => { if (this.active && epoch === this.avatarImageEpoch) { this.avatarReady = true; } })
      .onError((): void => {
        if (this.active && epoch === this.avatarImageEpoch) {
          this.avatarReady = false;
          this.avatarFailed = true;
        }
      })
  }

  @Builder
  private Avatar() {
    Stack() {
      if (!this.avatarReady) {
        Image($r('app.media.dsh_settings_account')).width(16).height(16).supportSvg2(true)
          .draggable(false).accessibilityLevel('no')
      }
      if (this.profile?.avatarUrl && !this.avatarFailed) {
        this.AvatarPicture(this.profile.avatarUrl, this.avatarImageEpoch)
      }
    }.key('desktopAccountSettingsAvatar').width(32).height(32).borderRadius(16).clip(true)
      .backgroundColor($r('app.color.workspace_selection'))
  }

  @Builder
  private AccountDetails() {
    Flex({ alignItems: ItemAlign.Center, wrap: FlexWrap.Wrap,
      space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(8) } }) {
      Row({ space: 10 }) {
        this.Avatar()
        Column({ space: 3 }) {
          Text(this.profile?.name || $r('app.string.desktop_account_settings_signed_in'))
            .key('desktopAccountSettingsName').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.profile?.contact || (this.profileLoaded ? $r('app.string.desktop_account_settings_profile_unavailable') :
            $r('app.string.desktop_account_settings_loading')))
            .key('desktopAccountSettingsContact').fontSize(13).fontColor($r('sys.color.font_tertiary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start)
      }.flexGrow(1).flexShrink(1).constraintSize({ minHeight: 44 })
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 4 }) {
          Text($r('app.string.desktop_account_settings_info')).fontSize(13).fontColor($r('sys.color.font_secondary'))
          Image($r('app.media.dsh_browser_right_up_outline')).width(12).height(12)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
        }
      }.key('desktopAccountSettingsInfo').enabled(this.infoUrl.length > 0).height(32).borderRadius(8)
        .onClick((): void => { this.followLink(this.infoUrl, false); })
    }.key('desktopAccountSettingsIdentity').width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .borderRadius(12).border({ width: 0.5, color: $r('app.color.workspace_border') })
      .backgroundColor($r('app.color.workspace_panel'))
  }

  private walletRows(bonus: boolean): DesktopAccountSettingsWallet[] {
    return (bonus ? this.balances?.bonus : this.balances?.normal) ?? [];
  }

  @Builder
  private WalletRow(label: Resource, bonus: boolean, key: string) {
    Flex({ alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween, wrap: FlexWrap.Wrap,
      space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(5) } }) {
      Text(label).fontSize(13).fontColor($r('sys.color.font_primary'))
      if (this.walletRows(bonus).length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End,
          space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
          ForEach(this.walletRows(bonus), (wallet: DesktopAccountSettingsWallet): void => {
            Text(wallet.text).key(key + '-' + wallet.currency).fontSize(18).fontColor($r('sys.color.font_primary'))
          }, (wallet: DesktopAccountSettingsWallet, index: number): string => index + ':' + wallet.currency + ':' + wallet.text)
        }.flexShrink(1)
      } else if (this.balanceLoaded) {
        Button($r('app.string.desktop_account_settings_balance_unavailable'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key(key + 'Unavailable').fontSize(13).height(32).borderRadius(8).enabled(this.usageUrl.length > 0)
          .onClick((): void => { this.followLink(this.usageUrl, true); })
      } else {
        Text($r('app.string.desktop_account_settings_loading')).key(key + 'Loading')
          .fontSize(13).fontColor($r('sys.color.font_tertiary'))
      }
    }.width('100%').constraintSize({ minHeight: 40 }).padding({ top: 4, bottom: 4 })
  }

  @Builder
  private WalletDetails() {
    Column({ space: 8 }) {
      this.WalletRow($r('app.string.desktop_account_settings_balance'), false,
        'desktopAccountSettingsBalance')
      if (!this.balanceLoaded || (this.balances?.bonus.length ?? 0) > 0) {
        Divider().color($r('app.color.workspace_border')).strokeWidth(0.5)
        this.WalletRow($r('app.string.desktop_account_settings_bonus'), true,
          'desktopAccountSettingsBonus')
      }
      Divider().color($r('app.color.workspace_border')).strokeWidth(0.5)
      Flex({ alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween, wrap: FlexWrap.Wrap,
        space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(8) } }) {
        Text($r('app.string.desktop_account_settings_more')).fontSize(13).fontColor($r('sys.color.font_tertiary'))
        Row({ space: 8 }) {
          Button($r('app.string.desktop_account_settings_usage'), { buttonStyle: ButtonStyleMode.NORMAL })
            .key('desktopAccountSettingsUsage').height(36).borderRadius(8)
            .enabled(this.usageUrl.length > 0).onClick((): void => { this.followLink(this.usageUrl, true); })
          Button($r('app.string.desktop_account_settings_top_up'), { buttonStyle: ButtonStyleMode.EMPHASIZED })
            .key('desktopAccountSettingsTopUp').height(36).borderRadius(8)
            .enabled(this.topUpUrl.length > 0).onClick((): void => { this.followLink(this.topUpUrl, true); })
        }
      }.width('100%').constraintSize({ minHeight: 40 })
    }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .borderRadius(12).border({ width: 0.5, color: $r('app.color.workspace_border') })
      .backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Column({ space: 16 }) {
      if (this.identity.signedIn) {
        this.AccountDetails()
        this.WalletDetails()
        if (this.linkFailed) {
          Text($r('app.string.desktop_account_settings_open_failed')).key('desktopAccountSettingsLinkError')
            .fontSize(13).fontColor($r('sys.color.warning'))
        }
      }
    }.key('desktopAccountSettings').width('100%').padding({ top: 8, bottom: 8 }).alignItems(HorizontalAlign.Start)
  }
}
