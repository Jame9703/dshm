import { getString } from 'connection';
import type { DesktopContextMessage } from './DesktopContextMessageModel';
import { DesktopContextMessageBody } from './DesktopContextMessageRow';
import { DEFAULT_DESKTOP_TYPOGRAPHY } from './DesktopTheme';
import type { DesktopTypography } from './DesktopTheme';
import { desktopUserMessageClockParts } from './DesktopUserMessageActionsModel';

@Component
export struct DesktopTurnTriggerRow {
  @Prop row: DesktopContextMessage | undefined = undefined;
  @Prop typography: DesktopTypography = DEFAULT_DESKTOP_TYPOGRAPHY;
  @State private expanded: boolean = false;

  private compact(): boolean {
    return this.row?.sourceKind === 'retry' && this.row.content.length === 0;
  }

  private childTitle(): Resource {
    switch (getString(this.row?.source, 'stopReason')) {
      case 'completed': return $r('app.string.desktop_turn_trigger_child_completed');
      case 'aborted': return $r('app.string.desktop_turn_trigger_child_stopped');
      case 'error': return $r('app.string.desktop_turn_trigger_child_failed');
      case 'max-tokens': return $r('app.string.desktop_turn_trigger_child_token_limit');
      case 'refusal': return $r('app.string.desktop_turn_trigger_child_refused');
      case '':
      case undefined: return $r('app.string.desktop_turn_trigger_child');
      default: return $r('app.string.desktop_turn_trigger_child_unknown');
    }
  }

  private title(): Resource {
    if (this.compact()) { return $r('app.string.desktop_turn_trigger_continued'); }
    switch (this.row?.sourceKind) {
      case 'goal': return $r('app.string.desktop_turn_trigger_goal');
      case 'agent-message': return $r('app.string.desktop_turn_trigger_agent');
      case 'team-message': return $r('app.string.desktop_turn_trigger_team');
      case 'subagent-settled': return this.childTitle();
      case 'webhook': return getString(this.row?.source, 'provider') === 'github' ?
        $r('app.string.desktop_turn_trigger_github') : $r('app.string.desktop_turn_trigger_webhook');
      case 'schedule': return $r('app.string.desktop_turn_trigger_schedule');
      case 'tool-jobs': return $r('app.string.desktop_turn_trigger_job');
      case 'cordis-host-runner': return $r('app.string.desktop_turn_trigger_plugin');
      default: return $r('app.string.desktop_turn_trigger_requested');
    }
  }

  private icon(): Resource {
    if (this.compact()) { return $r('app.media.dsh_dock_play'); }
    switch (this.row?.sourceKind) {
      case 'goal': return $r('app.media.dsh_dock_goal');
      case 'agent-message': return $r('app.media.dsh_feedback_paper_plane_outline');
      case 'team-message': return $r('app.media.dsh_agent_preset_outline');
      case 'subagent-settled': return $r('app.media.dsh_team_users_outline');
      case 'webhook': return getString(this.row?.source, 'provider') === 'github' ?
        $r('app.media.dsh_session_branch_outline') : $r('app.media.dsh_browser_globe_outline');
      case 'schedule': return $r('app.media.dsh_clock_outline');
      case 'tool-jobs': return $r('app.media.dsh_queue_queue_outline');
      case 'cordis-host-runner': return $r('app.media.dsh_cordis_plugin_outline');
      default: return $r('app.media.dsh_context_injection_outline');
    }
  }

  private time(): ResourceStr {
    const parts = desktopUserMessageClockParts(this.row?.time ?? 0, Date.now());
    if (parts === undefined) { return ''; }
    if (parts.sameDay) { return parts.hourMinute; }
    return parts.sameYear ? $r('app.string.desktop_user_message_clock_md', parts.month, parts.day, parts.hourMinute) :
      $r('app.string.desktop_user_message_clock_ymd', parts.year, parts.month, parts.day, parts.hourMinute);
  }

  @Builder
  private Header() {
    Row({ space: 10 }) {
      Image(this.icon()).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
      Text(this.title()).fontSize(this.typography.textSize).fontFamily(this.typography.textFamily)
        .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      Text(this.time()).fontSize(12).fontColor($r('sys.color.font_tertiary'))
      Image($r('app.media.dsh_queue_chevron_down_outline')).width(12).height(12).supportSvg2(true)
        .rotate({ angle: this.expanded ? 180 : 0 }).accessibilityLevel('no')
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      if (this.compact()) {
        Row({ space: 6 }) {
          Image(this.icon()).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
          Text(this.title()).fontSize(this.typography.textSize - 1).fontColor($r('sys.color.font_tertiary'))
        }.width('100%').padding({ top: 2, bottom: 2 }).key('desktopContinuation-' + this.row?.id)
      } else if (this.row !== undefined) {
        Column() {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) { this.Header() }
            .key('desktopTurnTriggerDisclosure-' + this.row.id).width('100%').borderRadius(12)
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .accessibilityText(this.title()).accessibilitySelected(this.expanded).focusOnTouch(false)
            .onClick((): void => { this.expanded = !this.expanded; })
          if (this.expanded) {
            Column({ space: 8 }) {
              Text($r('app.string.desktop_turn_trigger_explanation')).fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
              Scroll() {
                DesktopContextMessageBody({ row: this.row, forceNotice: true,
                  codeSize: this.typography.codeSize, codeFamily: this.typography.codeFamily })
              }.width('100%').constraintSize({ maxHeight: 240 }).scrollBar(BarState.Auto)
                .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
            }.key('desktopTurnTriggerBody-' + this.row.id)
              .width('100%').alignItems(HorizontalAlign.Start).padding({ left: 40, right: 16, bottom: 12 })
          }
        }.width('100%').borderRadius(12).border({ width: 0.5, color: $r('app.color.workspace_border') })
          .backgroundColor($r('app.color.workspace_panel'))
      }
    }.width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start)
  }
}
