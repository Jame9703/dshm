import type { DesktopAccountNotices } from './DesktopAccountNotices';
import type { DesktopAccountDetailsAccess } from './DesktopAccountDetails';
import type { DesktopGeneralHostAccess } from './DesktopGeneralHostPreferences';
import type { DesktopModelProviderAccess } from './DesktopModelProviderReadiness';
import type { DesktopCodingToolsSnapshot } from './DesktopCodingTools';
import type { DesktopHostActions } from './DesktopHostActions';
import type { DesktopPresetDefaultSync } from './DesktopPresetDefaults';
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
  accountDetails?: DesktopAccountDetailsAccess;
  host?: DesktopHostActions;
  generalHost?: DesktopGeneralHostAccess;
  modelProviders?: DesktopModelProviderAccess;
  codingTools: DesktopCodingToolsSnapshot;
  changeCodingTools: (enabled: boolean) => void;
  close: () => void;
  startCreator: () => void;
  capturePresetDefaultSync: () => DesktopPresetDefaultSync | undefined;
  selectSection: (section: string) => void;
  openPlugins: () => void;
}

@Builder
export function buildDesktopSettingsSurface(params: DesktopSettingsSurfaceParams) {
  WithTheme({ colorMode: params.mode }) {
    IndexContent({ desktopSection: params.section, desktopSettingsCompact: params.compact,
      desktopAccountNotices: params.accountNotices, desktopAccountDetails: params.accountDetails,
      desktopAccountHost: params.host, desktopGeneralHost: params.generalHost, desktopModelProviders: params.modelProviders,
      desktopCodingTools: params.codingTools,
      onDesktopCodingToolsChange: params.changeCodingTools, onCloseSettings: params.close, onStartPresetCreator: params.startCreator,
      capturePresetDefaultSync: params.capturePresetDefaultSync,
      onSettingsSection: params.selectSection, onOpenPlugins: params.openPlugins })
  }
}
