export interface DesktopTerminalCursorColors {
  fill: string;
  accent: string;
}

function linearChannel(color: string, offset: number): number {
  const value = Number.parseInt(color.slice(offset, offset + 2), 16) / 255;
  return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}

function luminance(color: string): number {
  return 0.2126 * linearChannel(color, 1) + 0.7152 * linearChannel(color, 3) + 0.0722 * linearChannel(color, 5);
}

/** Contrast thresholds match the bundled WebUI's terminal-cursor.ts. */
export function desktopTerminalCursorColors(background: string, preferred: string): DesktopTerminalCursorColors {
  const paper = luminance(background);
  const ink = luminance(preferred);
  const contrast = (Math.max(paper, ink) + 0.05) / (Math.min(paper, ink) + 0.05);
  const fill = contrast >= 3 ? preferred : paper > 0.179 ? '#000000' : '#ffffff';
  return { fill: fill, accent: luminance(fill) > 0.179 ? '#000000' : '#ffffff' };
}
