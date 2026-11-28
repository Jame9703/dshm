interface ScheduleRecommendation {
  id: string;
  icon: Resource;
  title: Resource;
  description: Resource;
  schedule: Resource;
  prompt: Resource;
}

const RECOMMENDATIONS: ScheduleRecommendation[] = [
  {
    id: 'daily-brief', icon: $r('app.media.dsh_schedule_daily_brief'),
    title: $r('app.string.desktop_schedule_daily_brief_title'),
    description: $r('app.string.desktop_schedule_daily_brief_description'),
    schedule: $r('app.string.desktop_schedule_daily_brief_schedule'),
    prompt: $r('app.string.desktop_schedule_daily_brief_prompt')
  },
  {
    id: 'weekly-review', icon: $r('app.media.dsh_schedule_weekly_review'),
    title: $r('app.string.desktop_schedule_weekly_review_title'),
    description: $r('app.string.desktop_schedule_weekly_review_description'),
    schedule: $r('app.string.desktop_schedule_weekly_review_schedule'),
    prompt: $r('app.string.desktop_schedule_weekly_review_prompt')
  },
  {
    id: 'issue-scan', icon: $r('app.media.dsh_schedule_issue_scan'),
    title: $r('app.string.desktop_schedule_issue_scan_title'),
    description: $r('app.string.desktop_schedule_issue_scan_description'),
    schedule: $r('app.string.desktop_schedule_issue_scan_schedule'),
    prompt: $r('app.string.desktop_schedule_issue_scan_prompt')
  },
  {
    id: 'plugin-compat', icon: $r('app.media.dsh_schedule_plugin_compat'),
    title: $r('app.string.desktop_schedule_plugin_compat_title'),
    description: $r('app.string.desktop_schedule_plugin_compat_description'),
    schedule: $r('app.string.desktop_schedule_plugin_compat_schedule'),
    prompt: $r('app.string.desktop_schedule_plugin_compat_prompt')
  },
  {
    id: 'topic-tracking', icon: $r('app.media.dsh_schedule_topic_tracking'),
    title: $r('app.string.desktop_schedule_topic_tracking_title'),
    description: $r('app.string.desktop_schedule_topic_tracking_description'),
    schedule: $r('app.string.desktop_schedule_topic_tracking_schedule'),
    prompt: $r('app.string.desktop_schedule_topic_tracking_prompt')
  },
  {
    id: 'branch-cleanup', icon: $r('app.media.dsh_schedule_branch_cleanup'),
    title: $r('app.string.desktop_schedule_branch_cleanup_title'),
    description: $r('app.string.desktop_schedule_branch_cleanup_description'),
    schedule: $r('app.string.desktop_schedule_branch_cleanup_schedule'),
    prompt: $r('app.string.desktop_schedule_branch_cleanup_prompt')
  },
  {
    id: 'weather', icon: $r('app.media.dsh_schedule_weather'),
    title: $r('app.string.desktop_schedule_weather_title'),
    description: $r('app.string.desktop_schedule_weather_description'),
    schedule: $r('app.string.desktop_schedule_weather_schedule'),
    prompt: $r('app.string.desktop_schedule_weather_prompt')
  },
  {
    id: 'workout', icon: $r('app.media.dsh_schedule_workout'),
    title: $r('app.string.desktop_schedule_workout_title'),
    description: $r('app.string.desktop_schedule_workout_description'),
    schedule: $r('app.string.desktop_schedule_workout_schedule'),
    prompt: $r('app.string.desktop_schedule_workout_prompt')
  }
];

@Component
export struct DesktopScheduleRecommendations {
  @Prop twoColumns: boolean = false;
  @Prop disabled: boolean = false;
  onChoose: (prompt: Resource) => void = (_: Resource): void => {};
  @State private hoveredId: string = '';
  @State private focusedId: string = '';

  @Builder
  private Tile(item: ScheduleRecommendation) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 14 }) {
        Stack() {
          if (this.hoveredId === item.id || this.focusedId === item.id) {
            Image($r('app.media.dsh_reference_menu_plus')).width(18).height(18).supportSvg2(true)
              .fillColor($r('app.color.desktop_schedule_glyph')).accessibilityLevel('no')
          } else {
            Image(item.icon).width(20).height(20).supportSvg2(true).accessibilityLevel('no')
          }
        }.width(40).height(40).borderRadius(8).backgroundColor($r('app.color.desktop_schedule_tile'))
        Column({ space: 2 }) {
          Text(item.title).fontSize(14).fontWeight(FontWeight.Medium).lineHeight(22)
            .fontColor($r('sys.color.font_primary'))
          Text(item.description).fontSize(13).lineHeight(20).fontColor($r('sys.color.font_secondary'))
          Row({ space: 6 }) {
            Image($r('app.media.dsh_clock_outline')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
            Text(item.schedule).fontSize(13).lineHeight(20).fontColor($r('sys.color.font_tertiary'))
          }.margin({ top: 4 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(VerticalAlign.Top)
    }.key('desktopScheduleRecommendation-' + item.id)
      .layoutWeight(1).padding(12).constraintSize({ minHeight: 62 }).borderRadius(10)
      .enabled(!this.disabled).accessibilityText(item.title).focusOnTouch(false)
      .onClick((): void => { this.onChoose(item.prompt); })
      .onHover((inside: boolean): void => {
        if (inside) { this.hoveredId = item.id; }
        else if (this.hoveredId === item.id) { this.hoveredId = ''; }
      })
      .onFocus((): void => { this.focusedId = item.id; })
      .onBlur((): void => { if (this.focusedId === item.id) { this.focusedId = ''; } })
  }

  build() {
    Column({ space: 4 }) {
      Text($r('app.string.desktop_schedule_recommendations')).fontSize(13).fontWeight(FontWeight.Medium)
        .lineHeight(20).fontColor($r('sys.color.font_tertiary')).padding({ left: 12, right: 12, bottom: 2 })
      if (this.twoColumns) {
        ForEach([0, 2, 4, 6], (index: number): void => {
          Row({ space: 16 }) {
            this.Tile(RECOMMENDATIONS[index])
            this.Tile(RECOMMENDATIONS[index + 1])
          }.width('100%').alignItems(VerticalAlign.Top)
        }, (index: number): string => String(index))
      } else {
        ForEach(RECOMMENDATIONS, (item: ScheduleRecommendation): void => {
          Row() { this.Tile(item) }.width('100%')
        }, (item: ScheduleRecommendation): string => item.id)
      }
    }.width('100%').margin({ top: 8 }).alignItems(HorizontalAlign.Start)
      .key('desktopScheduleRecommendations')
  }
}
