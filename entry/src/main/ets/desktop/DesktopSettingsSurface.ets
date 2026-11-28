import type { DesktopAccountNotices } from './DesktopAccountNotices';
import type { DesktopCodingToolsSnapshot } from './DesktopCodingTools';
import type { DesktopHostActions } from './DesktopHostActions';
import lazy { IndexContent } from '../pages/IndexContent';

export interface DesktopSettingsSize {
  compact: boolean;
  width: number;
  height: number;
}

export function desktopSettingsSize(width: number, height: number): DesktopSettingsSize {
  const compact = width < 768;
  return { compact: compact, width: Math.max(1, compact ? width : Math.min(800, width - 48)),
    height: Math.max(1, compact ? height : Math.min(800, height - 48)) };
}

export interface DesktopSettingsSurfaceParams {
  compact: boolean;
  mode: ThemeColorMode;
  section: string;
  accountNotices?: DesktopAccountNotices;
  host?: DesktopHostActions;
  codingTools: DesktopCodingToolsSnapshot;
  changeCodingTools: (enabled: boolean) => void;
  close: () => void;
  startCreator: () => void;
  selectSection: (section: string) => void;
  openPlugins: () => void;
}

@Builder
export function buildDesktopSettingsSurface(params: DesktopSettingsSurfaceParams) {
  WithTheme({ colorMode: params.mode }) {
    IndexContent({ desktopSection: params.section, desktopSettingsCompact: params.compact,
      desktopAccountNotices: params.accountNotices, desktopAccountHost: params.host, desktopCodingTools: params.codingTools,
      onDesktopCodingToolsChange: params.changeCodingTools, onCloseSettings: params.close, onStartPresetCreator: params.startCreator,
      onSettingsSection: params.selectSection, onOpenPlugins: params.openPlugins })
  }
}
