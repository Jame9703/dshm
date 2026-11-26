import { i18n } from '@kit.LocalizationKit';
import { getNumber, getRecord, getString } from 'connection';
import { openExternalUrl, readAppVersionText } from 'platform';
import { DesktopHostActions, desktopHostProblem } from './DesktopHostActions';

@Component
export struct DesktopAccountPane {
  host?: DesktopHostActions;
  @Prop callbackOrigin: string = '';
  onClose: () => void = (): void => {};
  onAddKey: () => void = (): void => {};
  @State private status: string = '';
  @State private phase: string = '';
  @State private attemptId: string = '';
  @State private authorize: string = '';
  @State private name: string = '';
  @State private contact: string = '';
  @State private usage: string = '';
  @State private topUp: string = '';
  @State private busy: boolean = false;
  @State private failure: string = '';
  private active: boolean = false;
  private stateRevision: number = 0;
  private autoOpen: boolean = false;
  private expiresAt: number = 0;
  private pollTimer: number = -1;
  private stopWatch?: () => void;

  aboutToAppear(): void {
    this.active = true;
    this.connect();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.stopWatch?.();
    this.stopWatch = undefined;
    clearTimeout(this.pollTimer);
  }

  private metadata(): Record<string, Object> {
    const version = readAppVersionText().split(' ')[0];
    return {
      'version': version === '—' ? '' : version,
      'locale': i18n.System.getSystemLanguage(),
      'timezoneOffsetSeconds': -new Date().getTimezoneOffset() * 60
    };
  }

  private connect(): void {
    const host = this.host;
    if (host === undefined) {
      this.failure = '工作区尚未连接';
      return;
    }
    this.stopWatch = host.watch('account/watch', {}, {
      onItem: (frame: Object): void => {
        const state = getRecord(frame, 'state');
        if (state !== undefined && this.active) {
          clearTimeout(this.pollTimer);
          this.accept(state);
        }
      },
      onError: (): void => { this.watchEnded(); },
      onEnd: (): void => { this.watchEnded(); }
    });
    if (this.stopWatch === undefined) {
      this.poll();
    }
  }

  private watchEnded(): void {
    this.stopWatch = undefined;
    this.poll();
  }

  private async poll(): Promise<void> {
    if (this.host === undefined || !this.active) {
      return;
    }
    const result = await this.host.call('account/getState');
    if (!this.active || this.busy) {
      return;
    }
    if (result.ok) {
      this.accept(result.value);
    } else {
      this.failure = desktopHostProblem(result);
    }
    clearTimeout(this.pollTimer);
    this.pollTimer = setTimeout((): void => { this.poll(); }, 2000);
  }

  private accept(value?: Object): void {
    this.stateRevision++;
    const previous = this.status;
    this.status = getString(value, 'status') ?? '';
    const links = getRecord(value, 'links');
    this.usage = getString(links, 'usageUrl') ?? '';
    this.topUp = getString(links, 'topUpUrl') ?? '';
    const attempt = getRecord(value, 'attempt');
    this.attemptId = getString(attempt, 'id') ?? '';
    this.phase = getString(attempt, 'phase') ?? '';
    this.authorize = getString(attempt, 'authorizeUrl') ?? '';
    this.expiresAt = getNumber(attempt, 'expiresAt') ?? 0;
    if (this.phase === 'failed') {
      this.failure = '登录失败，请重试';
    } else if (this.phase === 'expired') {
      this.failure = '授权已过期，请重新登录';
    } else {
      this.failure = '';
    }
    if (this.status === 'credential-stored' && previous !== this.status) {
      this.loadProfile();
    } else if (this.status !== 'credential-stored') {
      this.name = '';
      this.contact = '';
    }
    if (this.autoOpen && this.phase === 'waiting-browser' && this.authorize.length > 0) {
      this.autoOpen = false;
      this.openAuthorization();
    }
  }

  private async loadProfile(): Promise<void> {
    const result = await this.host?.call('account/getProfile', { 'client': this.metadata() });
    if (this.active && this.status === 'credential-stored' && result?.ok) {
      const profile = getRecord(result.value, 'value');
      this.name = getString(profile, 'name') ?? '';
      this.contact = getString(profile, 'contact') ?? '';
    }
  }

  private async openAuthorization(): Promise<void> {
    if (this.phase !== 'waiting-browser' || (this.expiresAt > 0 && Date.now() >= this.expiresAt) ||
      !new RegExp('^https://[^/?#@]+/dsh/authorize(?:[?#]|$)', 'i').test(this.authorize)) {
      this.failure = '授权链接已失效，请重新登录';
      return;
    }
    if (!(await openExternalUrl(this.authorize)) && this.active) {
      this.failure = '无法打开浏览器，请重试';
    }
  }

  private async signIn(): Promise<void> {
    if (this.host === undefined || this.busy || this.callbackOrigin.length === 0) {
      return;
    }
    this.autoOpen = true;
    this.busy = true;
    this.failure = '';
    const revision = this.stateRevision;
    const result = await this.host.call('account/startSignIn', {
      'client': this.metadata(), 'callbackOrigin': this.callbackOrigin, 'loginSource': 'desktop'
    });
    if (!this.active) {
      return;
    }
    this.busy = false;
    if (result.ok) {
      if (revision === this.stateRevision) {
        this.accept(result.value);
      }
    } else {
      this.autoOpen = false;
      this.failure = desktopHostProblem(result);
    }
    if (this.stopWatch === undefined) {
      this.poll();
    }
  }

  private async changeAccount(endpoint: string, body: Record<string, Object>, closeAfter: boolean = false): Promise<void> {
    if (this.host === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.autoOpen = false;
    const revision = this.stateRevision;
    const result = await this.host.call(endpoint, body);
    if (!this.active) {
      return;
    }
    this.busy = false;
    if (result.ok) {
      if (revision === this.stateRevision) {
        this.accept(result.value);
      }
      if (closeAfter) {
        this.onClose();
        return;
      }
    } else {
      this.failure = desktopHostProblem(result);
    }
    if (this.stopWatch === undefined) {
      this.poll();
    }
  }

  private signedOutStatus(): string {
    switch (this.phase) {
      case 'initializing': return '正在准备授权…';
      case 'waiting-browser': return '请在浏览器中完成授权';
      case 'exchanging':
      case 'committing': return '正在完成登录…';
      default: return this.status.length === 0 ? '正在读取账号…' : '在浏览器中完成授权后，返回此窗口。';
    }
  }

  private dismiss(): void {
    if (this.busy || this.phase === 'committing') {
      return;
    }
    if (this.attemptId && (this.phase === 'initializing' || this.phase === 'waiting-browser' ||
      this.phase === 'exchanging')) {
      this.changeAccount('account/cancelSignIn', { 'attemptId': this.attemptId }, true);
      return;
    }
    this.onClose();
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text(this.status === 'credential-stored' ? '账号' : '登录 DeepSeek 账号')
          .fontSize(22).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([$r('sys.color.font_secondary')])
        }
        .width(36).height(36).padding(0).accessibilityText('关闭')
        .enabled(!this.busy && this.phase !== 'committing').onClick((): void => { this.dismiss(); })
      }
      .width('100%')
      if (this.status === 'credential-stored') {
        Text(this.name || '已登录').fontSize(18)
        if (this.contact.length > 0) {
          Text(this.contact).fontColor($r('sys.color.font_secondary'))
        }
        Row({ space: 10 }) {
          if (this.usage.length > 0) {
            Button('用量', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
              openExternalUrl(this.usage);
            })
          }
          if (this.topUp.length > 0) {
            Button('充值', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
              openExternalUrl(this.topUp);
            })
          }
          Button('退出登录', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
            .onClick((): void => {
              this.getUIContext().getPromptAction().showDialog({
                title: '退出 DeepSeek 账号', buttons: [{ text: '取消', color: '#777777' },
                  { text: '退出登录', color: '#B73535' }]
              }).then((result): void => {
                if (result.index === 1 && this.active) {
                  this.changeAccount('account/signOut', { 'client': this.metadata() });
                }
              }).catch((): void => {});
            })
        }
      } else {
        Text(this.signedOutStatus()).fontSize(15).fontColor($r('sys.color.font_secondary'))
        Row({ space: 10 }) {
          if (this.phase === 'waiting-browser') {
            Button('打开浏览器').enabled(!this.busy).onClick((): void => { this.openAuthorization(); })
          } else if (this.phase !== 'initializing' && this.phase !== 'exchanging' && this.phase !== 'committing') {
            Button('添加 API Key', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
              .onClick(this.onAddKey)
            Button('登录').enabled(!this.busy && this.status === 'signed-out').onClick((): void => { this.signIn(); })
          }
          if (this.phase === 'initializing' || this.phase === 'waiting-browser' || this.phase === 'exchanging') {
            Button('取消登录', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy && !!this.attemptId)
              .onClick((): void => {
                this.dismiss();
              })
          }
        }
      }
      if (this.failure.length > 0) {
        Text(this.failure).fontSize(13).fontColor($r('sys.color.warning'))
      }
    }
    .padding(24).width('100%').alignItems(HorizontalAlign.Start)
  }
}
