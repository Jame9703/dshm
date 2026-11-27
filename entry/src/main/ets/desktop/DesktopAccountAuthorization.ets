import { url } from '@kit.ArkTS';

export function desktopAccountCallbackAllowed(origin: string): boolean {
  const originPattern = new RegExp('^http://(?:127\\.0\\.0\\.1|localhost|\\[::1\\]):([1-9][0-9]{0,4})$', 'i');
  const match = originPattern.exec(origin);
  return match !== null && Number(match[1]) <= 65535;
}

export function desktopAccountAuthorizeLink(value: string, dark: boolean): string {
  if (!value) { return ''; }
  try {
    const link = url.URL.parseURL(value);
    if (link.protocol !== 'https:' || link.pathname !== '/dsh/authorize' ||
      link.username || link.password || !link.hostname) { return ''; }
    link.searchParams.set('theme', dark ? 'dark' : 'light');
    return link.href;
  } catch (_) {
    return '';
  }
}
