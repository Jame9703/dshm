import { url } from '@kit.ArkTS';
import { getArray, getRecord, getString } from 'connection';
import { desktopBrowserAddress } from './DesktopBrowserAddress';

export interface DesktopAccountSettingsIdentity {
  ready: boolean;
  signedIn: boolean;
  revision: number;
  usageUrl: string;
  topUpUrl: string;
}

export function emptyDesktopAccountSettingsIdentity(): DesktopAccountSettingsIdentity {
  return { ready: false, signedIn: false, revision: 0, usageUrl: '', topUpUrl: '' };
}

export interface DesktopAccountSettingsProfile {
  name: string;
  contact: string;
  avatarUrl: string;
}

export interface DesktopAccountSettingsWallet {
  currency: string;
  text: string;
}

export interface DesktopAccountSettingsBalances {
  normal: DesktopAccountSettingsWallet[];
  bonus: DesktopAccountSettingsWallet[];
}

const DECIMAL: RegExp = new RegExp('^(-?)(\\d*)(?:\\.(\\d*))?(?:e([+-]?\\d+))?$', 'i');
const GROUP_DIGITS: RegExp = new RegExp('\\B(?=(\\d{3})+(?!\\d))', 'g');

function accountUrl(value: string): string {
  return value.length === 0 ? '' : desktopBrowserAddress(value, '', false).href;
}

export function desktopAccountPlatformLink(value: string): string {
  return accountUrl(value);
}

export function desktopAccountPlatformHome(usageUrl: string): string {
  const address = accountUrl(usageUrl);
  return address ? url.URL.parseURL(address).origin + '/' : '';
}

export function desktopAccountSettingsProfile(value?: Object): DesktopAccountSettingsProfile | undefined {
  if (getString(value, 'status') !== 'ready') { return undefined; }
  const profile = getRecord(value, 'value');
  if (profile === undefined) { return undefined; }
  return {
    name: getString(profile, 'name') ?? '',
    contact: getString(profile, 'contact') ?? '',
    avatarUrl: accountUrl(getString(profile, 'avatarUrl') ?? '')
  };
}

function carryDecimal(digits: string): string {
  for (let index = digits.length - 1; index >= 0; index--) {
    const value = digits.charCodeAt(index) - 48;
    if (value < 9) {
      return digits.slice(0, index) + (value + 1).toString() + '0'.repeat(digits.length - index - 1);
    }
  }
  return '1' + '0'.repeat(digits.length);
}

/** Matches the Platform balance display rules while keeping cents in decimal strings. */
export function formatDesktopAccountBalance(amount: string, symbol: string): string {
  const match = DECIMAL.exec(amount);
  if (match === null) { return ''; }
  const whole = match[2];
  const raw = whole + (match[3] ?? '');
  if (!raw) { return ''; }
  let zeros = 0;
  while (zeros < raw.length && raw.charAt(zeros) === '0') { zeros++; }
  if (zeros === raw.length) { return symbol + '0.00'; }
  const negative = match[1] === '-';
  const point = whole.length - zeros + (match[4] === undefined ? 0 : Number(match[4]));
  if (point < -1) { return (negative ? '-' : '<') + symbol + '0.01'; }
  // Bound extreme exponents so the UI cannot allocate an unbounded number of digits.
  if (point > 1024) { return ''; }
  const prefix = point > 0 ? point : 1;
  const digits = point <= 0 ? '0'.repeat(1 - point) + raw.slice(zeros) : raw.slice(zeros);
  const cut = prefix + 2;
  let cents = digits.slice(0, cut).padEnd(cut, '0');
  if (negative && digits.charCodeAt(cut) >= 53) { cents = carryDecimal(cents); }
  const integral = cents.slice(0, -2).replace(GROUP_DIGITS, ',');
  return (negative ? '-' : '') + symbol + integral + '.' + cents.slice(-2);
}

function normalizeWallets(value: Object[], positiveOnly: boolean): DesktopAccountSettingsWallet[] {
  const result: DesktopAccountSettingsWallet[] = [];
  for (const wallet of value) {
    const currency = getString(wallet, 'currency');
    if (currency !== 'CNY' && currency !== 'USD') { continue; }
    const symbol = currency === 'CNY' ? '¥' : '$';
    const amount = getString(wallet, 'balance') ?? '';
    const text = formatDesktopAccountBalance(amount, symbol);
    if (text && (!positiveOnly || (!text.startsWith('-') && text !== symbol + '0.00'))) {
      result.push({ currency: currency, text: text });
    }
  }
  return result;
}

export function desktopAccountSettingsBalances(value?: Object): DesktopAccountSettingsBalances | undefined {
  if (getString(value, 'status') !== 'ready') { return undefined; }
  const normal = getArray(value, 'value');
  const bonus = getArray(value, 'bonusWallets');
  if (normal === undefined || bonus === undefined) { return undefined; }
  return { normal: normalizeWallets(normal, false), bonus: normalizeWallets(bonus, true) };
}
