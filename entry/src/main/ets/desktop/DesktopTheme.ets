import { getNumber, getString } from 'connection';

export const DESKTOP_THEME_NS: string = 'ui-theme';

export interface DesktopTypography {
  textSize: number;
  codeSize: number;
  terminalSize: number;
  textFamily: string;
  codeFamily: string;
  terminalFamily: string;
}

export interface DesktopTheme {
  appearance: string;
  typography: DesktopTypography;
}

export interface DesktopFontSizeSpec {
  field: string;
  minimum: number;
  maximum: number;
  defaultValue: number;
}

export const DESKTOP_TEXT_SIZE: DesktopFontSizeSpec = { field: 'fontSize', minimum: 10, maximum: 22, defaultValue: 14 };
export const DESKTOP_CODE_SIZE: DesktopFontSizeSpec = { field: 'codeFontSize', minimum: 10, maximum: 16, defaultValue: 11 };
export const DESKTOP_TERMINAL_SIZE: DesktopFontSizeSpec = {
  field: 'terminalFontSize', minimum: 10, maximum: 20, defaultValue: 13
};

export const DEFAULT_DESKTOP_TYPOGRAPHY: DesktopTypography = {
  textSize: DESKTOP_TEXT_SIZE.defaultValue, codeSize: DESKTOP_CODE_SIZE.defaultValue,
  terminalSize: DESKTOP_TERMINAL_SIZE.defaultValue, textFamily: '', codeFamily: 'monospace', terminalFamily: 'monospace'
};

const GENERIC_FONTS: Set<string> = new Set([
  'serif', 'sans-serif', 'monospace', 'cursive', 'fantasy', 'system-ui', 'ui-serif', 'ui-sans-serif',
  'ui-monospace', 'ui-rounded', 'emoji', 'math', 'fangsong', '-apple-system', 'blinkmacsystemfont'
]);
const FONT_CONTROL = new RegExp('["\'\\\\<>\\u0000-\\u001f\\u007f]', 'g');
const FONT_SPACES = new RegExp('\\s+', 'g');

function fontNames(value: string): string[] {
  return value.split(',').map((part: string): string => part.replace(FONT_CONTROL, '').replace(FONT_SPACES, ' ').trim())
    .filter((part: string): boolean => part.length > 0);
}

export function desktopFontDocumentValue(value: string): string {
  return fontNames(value).map((name: string): string => GENERIC_FONTS.has(name.toLowerCase()) ? name : `"${name}"`)
    .join(', ');
}

export function desktopFontSize(value: number | undefined, spec: DesktopFontSizeSpec): number {
  return value !== undefined && Number.isInteger(value) && value >= spec.minimum && value <= spec.maximum ?
    value : spec.defaultValue;
}

export function desktopAppearance(value: string | undefined): string {
  return value === 'light' || value === 'dark' ? value : 'system';
}

export function desktopThemeFrom(section: Object): DesktopTheme {
  const code = fontNames(getString(section, 'codeFontFamily') ?? '');
  if (!code.includes('monospace')) { code.push('monospace'); }
  const terminal = fontNames(getString(section, 'terminalFontFamily') ?? '');
  return {
    appearance: desktopAppearance(getString(section, 'preference')),
    typography: {
      textSize: desktopFontSize(getNumber(section, DESKTOP_TEXT_SIZE.field), DESKTOP_TEXT_SIZE),
      codeSize: desktopFontSize(getNumber(section, DESKTOP_CODE_SIZE.field), DESKTOP_CODE_SIZE),
      terminalSize: desktopFontSize(getNumber(section, DESKTOP_TERMINAL_SIZE.field), DESKTOP_TERMINAL_SIZE),
      textFamily: fontNames(getString(section, 'textFontFamily') ?? '').join(', '),
      codeFamily: code.join(', '), terminalFamily: terminal.join(', ') || 'monospace'
    }
  };
}

export function sameDesktopTypography(left: DesktopTypography, right: DesktopTypography): boolean {
  return left.textSize === right.textSize && left.codeSize === right.codeSize && left.terminalSize === right.terminalSize &&
    left.textFamily === right.textFamily && left.codeFamily === right.codeFamily && left.terminalFamily === right.terminalFamily;
}
