import { url } from '@kit.ArkTS';
import { getString } from 'connection';

export function desktopAccountContactUrl(document: Object | undefined, uid: string, deviceInfo: string,
  width: number, height: number): string {
  const configured = getString(document, 'contactFormUrl');
  if (!configured) { return ''; }
  try {
    const form = url.URL.parseURL(configured);
    if (form.protocol !== 'https:' || !form.hostname || form.username || form.password) { return ''; }
    const context: string[] = deviceInfo ? [deviceInfo] : [];
    if (Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0) {
      context.push(`screen_resolution=${Math.round(width)}x${Math.round(height)}`);
    }
    const fields: Record<string, string> = {
      'uid': uid, 'source': getString(document, 'contactSource') ?? '',
      'harness_version': getString(document, 'clientVersion') ?? '', 'device_info': context.join('; ')
    };
    for (const name of Object.keys(fields)) {
      form.searchParams.set('hide_' + name, '1');
      const field = 'prefill_' + name;
      form.searchParams.delete(field);
      if (fields[name]) { form.searchParams.set(field, fields[name]); }
    }
    for (const name of ['os_version', 'device_brand', 'app_locale', 'screen_resolution', 'app_version', 'device_model']) {
      form.searchParams.delete('prefill_' + name);
      form.searchParams.delete('hide_' + name);
    }
    return form.href;
  } catch (_) {
    return '';
  }
}
