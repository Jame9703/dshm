import { i18n } from '@kit.LocalizationKit';
import { readAppVersionText } from 'platform';

export function desktopAccountLocale(preference: string = 'system'): string {
  return preference && preference !== 'system' ? preference : i18n.System.getSystemLanguage();
}

export function desktopAccountMetadata(locale: string = desktopAccountLocale()): Record<string, Object> {
  const version = readAppVersionText().split(' ')[0];
  return {
    'version': version === '—' ? '' : version,
    'locale': locale,
    'timezoneOffsetSeconds': -new Date().getTimezoneOffset() * 60
  };
}
