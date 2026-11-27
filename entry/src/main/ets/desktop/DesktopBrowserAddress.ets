import { url } from '@kit.ArkTS';

export interface DesktopBrowserAddress {
  href: string;
  title: string;
  problem: string;
}

function loopback(host: string): boolean {
  const name = host.replace(new RegExp('\\.$'), '');
  return name === 'localhost' || name.endsWith('.localhost') || name === '[::1]' ||
    name === '0.0.0.0' || name.startsWith('127.');
}

export function workspaceBrowserRequest(target: string, origin: string): boolean {
  if (!origin || !target) { return false; }
  try {
    const main = url.URL.parseURL(origin);
    const page = url.URL.parseURL(target);
    return main.origin === page.origin || (main.port === page.port && loopback(main.hostname) && loopback(page.hostname));
  } catch (_) {
    return false;
  }
}

export function desktopBrowserAddress(input: string, origin: string, assumeHttps: boolean = true): DesktopBrowserAddress {
  const text = input.trim();
  if (!text || text.length > 16384) {
    return { href: '', title: '', problem: text ? '这个地址无效或过长。' : '请输入地址。' };
  }
  try {
    const hasScheme = new RegExp('^[A-Za-z][A-Za-z\\d+.-]*:(?!\\d+(?:[/?#]|$))').test(text);
    const parsed = url.URL.parseURL(!hasScheme && assumeHttps ? 'https://' + text : text);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
      return { href: '', title: '', problem: '只支持 HTTP 和 HTTPS 地址。' };
    }
    if (!parsed.hostname || parsed.username || parsed.password) {
      return { href: '', title: '', problem: '地址无效或包含用户名或密码。' };
    }
    if (workspaceBrowserRequest(parsed.href, origin)) {
      return { href: '', title: '', problem: '不能在嵌入浏览器中打开 DSH 应用自身。' };
    }
    return { href: parsed.href, title: parsed.hostname, problem: '' };
  } catch (_) {
    return { href: '', title: '', problem: '这个地址无效或过长。' };
  }
}
