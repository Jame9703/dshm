import { accessibility } from '@kit.AccessibilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { getNumber, getRecord, getString } from 'connection';
import { copyText, openExternalUrl } from 'platform';
import { desktopAccountLocale, desktopAccountMetadata } from './DesktopAccountClient';
import { desktopAccountAuthorizeLink, desktopAccountCallbackAllowed } from './DesktopAccountAuthorization';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';

const FALLBACK_DELAY_MS: number = 600;
const POLL_INTERVAL_MS: number = 2000;

@Component
struct DesktopAccountSpinner {
  @State private angle: number = 0;
  @State private reducedMotion: boolean = true;
  private observingMotion: boolean = false;
  private readonly motionChanged = (enabled: boolean): void => {
    this.angle = 0;
    this.reducedMotion = enabled;
  };

  aboutToAppear(): void {
    try {
      this.reducedMotion = accessibility.isAnimationReduceEnabledSync();
      accessibility.onAnimationReduceStateChange(this.motionChanged);
      this.observingMotion = true;
    } catch (_) {
      this.reducedMotion = true;
    }
  }

  aboutToDisappear(): void {
    if (this.observingMotion) {
      try { accessibility.offAnimationReduceStateChange(this.motionChanged); } catch (_) {}
      this.observingMotion = false;
    }
  }

  build() {
    Stack() {
      if (this.reducedMotion) {
        Image($r('app.media.dsh_account_loading_outline')).width(16).height(16).draggable(false).supportSvg2(true)
      } else {
        Image($r('app.media.dsh_account_loading_outline')).width(16).height(16).draggable(false).supportSvg2(true)
          .rotate({ angle: this.angle })
          .onAppear((): void => {
            this.getUIContext().animateTo({ duration: 1000, curve: Curve.Linear, iterations: -1 }, (): void => {
              this.angle = 360;
            });
          })
      }
    }.width(16).height(16).accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct DesktopAccountPane {
  host?: DesktopHostActions;
  @Prop signOutMode: boolean = false;
  @Prop callbackOrigin: string = '';
  @Prop appearance: string = 'system';
  @Prop localePreference: string = 'system';
  @Prop @Watch('dismissRequested') dismissRequest: number = 0;
  onClose: () => void = (): void => {};
  onAddKey: () => void = (): void => {};
  onState: (state: Object) => void = (_state: Object): void => {};

  @State private status: string = '';
  @State private phase: string = '';
  @State private attemptId: string = '';
  @State private authorize: string = '';
  @State private expiresAt: number = 0;
  @State private errorCode: string = '';
  @State private busy: boolean = false;
  @State private failure: string = '';
  @State private browserFailure: boolean = false;
  @State private copyResult: string = '';
  @State private signOutImpact: string = '';

  private active: boolean = false;
  private successClosed: boolean = false;
  private actionStarted: boolean = false;
  private stateRevision: number = 0;
  private accountRevision: number = 0;
  private watchRevision: number = 0;
  private watchReady: boolean = false;
  private polling: boolean = false;
  private launchedAttempt: string = '';
  private launchAttempt: string = '';
  private pollTimer: number = -1;
  private copyTimer: number = -1;
  private stopWatch?: () => void;

  aboutToAppear(): void {
    this.active = true;
    this.connectWatch();
    this.schedulePoll(FALLBACK_DELAY_MS);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.watchRevision++;
    this.stopWatch?.();
    this.stopWatch = undefined;
    clearTimeout(this.pollTimer);
    clearTimeout(this.copyTimer);
  }

  private dismissRequested(): void { if (this.active) { this.dismiss(); } }

  private connectWatch(): void {
    const host = this.host;
    if (!this.active || host === undefined || this.stopWatch !== undefined) { return; }
    const revision = ++this.watchRevision;
    const ended = (): void => {
      if (!this.active || revision !== this.watchRevision) { return; }
      this.watchRevision++;
      this.stopWatch = undefined;
      this.watchReady = false;
      this.schedulePoll(0);
    };
    this.stopWatch = host.watch('account/watch', {}, {
      onItem: (frame: Object): void => {
        if (!this.active || revision !== this.watchRevision) { return; }
        const state = getRecord(frame, 'state');
        if (state === undefined) { return; }
        this.watchReady = true;
        clearTimeout(this.pollTimer);
        this.accept(state, getString(frame, 'type') === 'credentials-changed');
      },
      onError: ended,
      onEnd: ended
    });
  }

  private schedulePoll(delay: number = POLL_INTERVAL_MS): void {
    clearTimeout(this.pollTimer);
    if (this.active && !this.watchReady && this.host !== undefined) {
      this.pollTimer = setTimeout((): void => { this.poll(); }, delay);
    }
  }

  private async poll(): Promise<void> {
    const host = this.host;
    if (!this.active || this.watchReady || host === undefined) { return; }
    if (this.polling || this.busy) { this.schedulePoll(); return; }
    this.connectWatch();
    const revision = this.stateRevision;
    this.polling = true;
    const result = await host.call('account/getState');
    this.polling = false;
    if (!this.active || this.watchReady) { return; }
    if (revision === this.stateRevision && !this.busy) {
      if (result.ok) { this.accept(result.value); }
      else if (!this.status) { this.failure = desktopHostProblem(result); }
    }
    this.schedulePoll();
  }

  private accept(value?: Object, credentialsChanged: boolean = false): void {
    const status = getString(value, 'status');
    if (value === undefined || (status !== 'signed-out' && status !== 'credential-stored')) { return; }
    const previous = this.status;
    this.stateRevision++;
    this.status = status;
    const attempt = getRecord(value, 'attempt');
    const nextId = getString(attempt, 'id') ?? '';
    const nextUrl = getString(attempt, 'authorizeUrl') ?? '';
    if (this.attemptId !== nextId || this.authorize !== nextUrl) {
      clearTimeout(this.copyTimer);
      this.copyResult = '';
      this.browserFailure = false;
    }
    this.attemptId = nextId;
    this.authorize = nextUrl;
    this.phase = getString(attempt, 'phase') ?? '';
    this.expiresAt = getNumber(attempt, 'expiresAt') ?? 0;
    this.errorCode = getString(attempt, 'errorCode') ?? '';
    if (!previous || credentialsChanged) { this.failure = ''; }
    this.onState(value);
    if (credentialsChanged || previous !== status) {
      this.accountRevision++;
      this.signOutImpact = '';
    }
    if (this.signOutMode !== (status === 'credential-stored')) {
      this.finish();
      return;
    }
    if (this.signOutMode) {
      if (!this.signOutImpact) { this.prepareSignOut(); }
    } else {
      if (!this.actionStarted) {
        this.actionStarted = true;
        this.signIn(true);
      }
      this.openOwnedAttempt();
    }
  }

  private finish(): void {
    if (this.successClosed) { return; }
    this.successClosed = true;
    this.launchAttempt = '';
    this.onClose();
  }

  private clientMetadata(): Record<string, Object> {
    return desktopAccountMetadata(desktopAccountLocale(this.localePreference));
  }

  private activeAttempt(): boolean {
    return this.phase === 'initializing' || this.phase === 'waiting-browser' ||
      this.phase === 'exchanging' || this.phase === 'committing';
  }

  private darkScheme(): boolean {
    const system = this.getUIContext().getHostContext()?.resourceManager.getConfigurationSync().colorMode ===
      resourceManager.ColorMode.DARK;
    return this.appearance === 'dark' || (this.appearance === 'system' && system);
  }

  private currentLink(): string {
    if (this.phase !== 'waiting-browser' || (this.expiresAt > 0 && Date.now() >= this.expiresAt)) { return ''; }
    return desktopAccountAuthorizeLink(this.authorize, this.darkScheme());
  }

  private openOwnedAttempt(): void {
    if (!this.launchAttempt || this.launchAttempt !== this.attemptId || this.launchedAttempt === this.attemptId ||
      this.phase !== 'waiting-browser' || !this.authorize) { return; }
    this.launchedAttempt = this.attemptId;
    this.openAuthorization();
  }

  private async openAuthorization(): Promise<void> {
    const attempt = this.attemptId;
    const link = this.currentLink();
    if (!link) { this.browserFailure = true; return; }
    const opened = await openExternalUrl(link);
    if (this.active && this.attemptId === attempt && this.phase === 'waiting-browser') { this.browserFailure = !opened; }
  }

  private async copyAuthorization(): Promise<void> {
    const attempt = this.attemptId;
    const link = this.currentLink();
    if (!link) { return; }
    const copied = await copyText(link);
    if (!this.active || this.attemptId !== attempt || this.phase !== 'waiting-browser') { return; }
    this.copyResult = copied ? 'copied' : 'failed';
    clearTimeout(this.copyTimer);
    this.copyTimer = setTimeout((): void => { this.copyResult = ''; }, 2000);
  }

  private async signIn(joinActive: boolean = false): Promise<void> {
    const host = this.host;
    if (host === undefined || this.busy || this.status !== 'signed-out' || this.phase === 'committing') { return; }
    if (!desktopAccountCallbackAllowed(this.callbackOrigin)) {
      this.failure = this.getUIContext().getHostContext()?.resourceManager
        .getStringSync($r('app.string.desktop_account_invalid_callback').id) ?? '';
      return;
    }
    this.busy = true;
    this.failure = '';
    this.browserFailure = false;
    this.launchAttempt = '';
    if (!joinActive && this.activeAttempt() && this.attemptId) {
      const revision = this.stateRevision;
      const cancelled = await host.call('account/cancelSignIn', { 'attemptId': this.attemptId });
      if (!this.active) { return; }
      if (!cancelled.ok) {
        this.failure = desktopHostProblem(cancelled);
        this.busy = false;
        return;
      }
      if (revision === this.stateRevision) { this.accept(cancelled.value); }
      if (this.status !== 'signed-out' || this.activeAttempt()) { this.busy = false; return; }
    }
    const revision = this.stateRevision;
    const result = await host.call('account/startSignIn', {
      'client': this.clientMetadata(), 'callbackOrigin': this.callbackOrigin, 'loginSource': 'desktop'
    });
    if (!this.active) { return; }
    this.busy = false;
    if (result.ok) {
      this.launchAttempt = getString(getRecord(result.value, 'attempt'), 'id') ?? '';
      if (revision === this.stateRevision) { this.accept(result.value); }
      else { this.openOwnedAttempt(); }
    } else { this.failure = desktopHostProblem(result); }
    this.schedulePoll(0);
  }

  private async changeAccount(endpoint: string, body: Record<string, Object>): Promise<void> {
    const host = this.host;
    if (host === undefined || this.busy ||
      (endpoint === 'account/signOut' && (!this.signOutImpact || this.status !== 'credential-stored'))) { return; }
    this.busy = true;
    this.failure = '';
    this.launchAttempt = '';
    const revision = this.stateRevision;
    const result = await host.call(endpoint, body);
    if (!this.active) { return; }
    this.busy = false;
    if (result.ok) {
      if (revision === this.stateRevision) { this.accept(result.value); }
      this.finish();
    } else {
      this.failure = desktopHostProblem(result);
      this.schedulePoll(0);
    }
  }

  private async prepareSignOut(): Promise<void> {
    if (this.busy || this.status !== 'credential-stored' || this.host === undefined) { return; }
    const revision = this.accountRevision;
    this.busy = true;
    const result = await this.host.call('account/hasRunningAccountTasks');
    if (!this.active) { return; }
    this.busy = false;
    if (this.status !== 'credential-stored') { return; }
    if (revision !== this.accountRevision) { this.prepareSignOut(); return; }
    this.failure = '';
    this.signOutImpact = result.ok && typeof result.value === 'boolean' ? (result.value === true ? 'running' : 'idle') : 'unknown';
  }

  private dismiss(): void {
    if (this.busy || this.phase === 'committing') { return; }
    if (this.signOutMode) { this.finish(); return; }
    if (this.status === 'signed-out' && this.attemptId && this.activeAttempt()) {
      this.changeAccount('account/cancelSignIn', { 'attemptId': this.attemptId });
    } else { this.finish(); }
  }

  private failedSignIn(): boolean { return this.phase === 'failed' || this.failure.length > 0; }

  private waitingForSignIn(): boolean { return (this.busy || this.activeAttempt()) && !this.failedSignIn(); }

  private accountTitle(): Resource {
    if (this.signOutMode) { return $r('app.string.desktop_account_sign_out'); }
    if (this.failedSignIn()) { return $r('app.string.desktop_account_login_failed'); }
    if (this.waitingForSignIn()) { return $r('app.string.desktop_account_login_waiting'); }
    if (this.phase === 'expired') { return $r('app.string.desktop_account_login_expired'); }
    return $r('app.string.desktop_account_login_title');
  }

  private loginDescription(): Resource {
    if (this.failedSignIn()) {
      return this.errorCode === 'no-response' ? $r('app.string.desktop_account_no_response') : $r('app.string.desktop_account_retry_description');
    }
    if (this.phase === 'expired') { return $r('app.string.desktop_account_login_again'); }
    return this.status.length === 0 ? $r('app.string.desktop_account_settings_loading') : $r('app.string.desktop_account_login_description');
  }

  @Builder
  private Outlined(label: Resource, id: string, enabled: () => boolean, action: () => void) {
    Button(label, { buttonStyle: ButtonStyleMode.TEXTUAL }).key(id)
      .fontSize(14).height(36).borderRadius(8).padding({ left: 14, right: 14 })
      .border({ width: 0.5, color: $r('app.color.workspace_border') }).enabled(enabled()).onClick(action)
  }

  @Builder
  private ConfirmSignOut() {
    Text(this.signOutImpact === 'running' ? $r('app.string.desktop_account_sign_out_running') :
      this.signOutImpact === 'idle' ? $r('app.string.desktop_account_sign_out_idle') : $r('app.string.desktop_account_sign_out_unknown'))
      .fontSize(14).lineHeight(22).width('100%')
    Row({ space: 8 }) {
      Blank()
      this.Outlined($r('app.string.desktop_account_quota_cancel'), 'desktopAccountCancelSignOut', (): boolean => !this.busy,
        (): void => { this.dismiss(); })
      Button($r('app.string.desktop_account_sign_out')).key('desktopAccountConfirmSignOut')
        .fontSize(14).height(36).borderRadius(8).enabled(!this.busy).onClick((): void => {
          this.changeAccount('account/signOut', { 'client': this.clientMetadata() });
        })
    }.width('100%')
  }

  @Builder
  private BrowserHint() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
      Text($r('app.string.desktop_account_browser_prompt')).fontSize(14).lineHeight(22)
      Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Text(this.copyResult === 'copied' ? $r('app.string.desktop_account_link_copied') :
          this.copyResult === 'failed' ? $r('app.string.desktop_account_copy_failed') : $r('app.string.desktop_account_copy_link'))
          .fontSize(14).lineHeight(22).decoration({ type: TextDecorationType.Underline })
      }.key('desktopAccountCopyLoginLink').height(22).padding(0).borderRadius(2)
        .enabled(!this.busy && this.phase === 'waiting-browser' && !!this.authorize)
        .onClick((): void => { this.copyAuthorization(); })
      Text($r('app.string.desktop_account_browser_description')).fontSize(14).lineHeight(22)
    }.width('100%')
    if (this.browserFailure && this.phase === 'waiting-browser' && this.authorize.length > 0) {
      Button($r('app.string.desktop_account_open_browser'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopAccountOpenBrowser').fontSize(14).height(32).enabled(!this.busy)
        .onClick((): void => { this.openAuthorization(); })
    }
  }

  @Builder
  private WaitingButton() {
    Stack() {
      Button($r('app.string.desktop_account_continue_in_browser'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopAccountSignIn').fontColor(Color.Transparent)
        .width('100%').height('100%').borderRadius(8).backgroundColor(Color.Transparent)
        .enabled(false).accessibilityText($r('app.string.desktop_account_continue_in_browser'))
      DesktopAccountSpinner()
    }.width(72).height(36).borderRadius(8).backgroundColor($r('sys.color.brand'))
  }

  @Builder
  private Login() {
    if (this.waitingForSignIn()) {
      this.BrowserHint()
    } else { Text(this.loginDescription()).fontSize(14).lineHeight(22) }
    Row({ space: 8 }) {
      Blank()
      if (this.busy || this.activeAttempt()) {
        this.Outlined($r('app.string.desktop_account_quota_cancel'), 'desktopAccountCancelSignIn',
          (): boolean => !this.busy && this.phase !== 'committing' && !!this.attemptId, (): void => { this.dismiss(); })
      } else {
        this.Outlined($r('app.string.desktop_account_add_key'), 'desktopAccountAddKey', (): boolean => !this.busy, this.onAddKey)
      }
      if (this.waitingForSignIn()) {
        this.WaitingButton()
      } else {
        Button(this.failedSignIn() || this.phase === 'expired' ?
          $r('app.string.desktop_account_retry') : $r('app.string.desktop_account_sign_in'),
          { buttonStyle: ButtonStyleMode.EMPHASIZED }).key('desktopAccountSignIn')
          .constraintSize({ minWidth: 72 }).height(36).borderRadius(8).fontSize(14).fontColor(Color.White)
          .enabled(!this.busy && this.status === 'signed-out' && this.phase !== 'committing' &&
            (!this.activeAttempt() || this.failedSignIn()))
          .onClick((): void => { this.signIn(); })
      }
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.accountTitle()).fontSize(16).lineHeight(24).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.key('desktopAccountDialogClose').width(28).height(28).padding(0)
          .accessibilityText($r('app.string.desktop_account_quota_close'))
          .enabled(!this.busy && this.phase !== 'committing').onClick((): void => { this.dismiss(); })
      }.width('100%')
      if (this.signOutMode) {
        if (this.signOutImpact) { this.ConfirmSignOut() }
        else {
          Text($r('app.string.desktop_account_settings_loading')).fontSize(14).lineHeight(22)
        }
      } else { this.Login() }
      if (this.failure) { Text(this.failure).fontSize(13).fontColor($r('sys.color.warning')) }
      if (this.browserFailure && this.phase === 'waiting-browser') {
        Text($r('app.string.desktop_account_browser_unavailable')).fontSize(13).fontColor($r('sys.color.warning'))
      }
    }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
  }
}
