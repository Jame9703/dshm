import { KeyCode } from '@kit.InputKit';
import { SessionStatsInput } from 'appstate';
import {
  DesktopChatSessionUsage, DesktopChatTurnUsage, DesktopChatUsageRoute, DesktopChatUsageSnapshot, emptyDesktopChatUsage
} from './DesktopChatUsageModel';
import { desktopChatCachePercent, desktopChatCompactTokens, desktopChatExactTokens, desktopChatTokensPerSecond } from './DesktopChatUsageFormat';
import { desktopMenuOptions } from './DesktopMenuOptions';

const READING_FONT_SIZE: number = 12;
const READING_TIP_DELAY_MS: number = 200;

interface ChatUsageDetail {
  id: string;
  label: Resource;
  value: ResourceStr;
}

function exactTokens(value: number): Resource {
  return $r('app.string.desktop_chat_usage_token_count', desktopChatExactTokens(value));
}

function compactTokens(value: number): Resource {
  return $r('app.string.desktop_chat_usage_token_count', desktopChatCompactTokens(value));
}

function durationText(ms: number): Resource {
  if (ms < 60000) { return $r('app.string.desktop_chat_usage_seconds', String(Math.round(ms / 100) / 10)); }
  const seconds = Math.round(ms / 1000);
  return $r('app.string.desktop_chat_usage_minutes', Math.floor(seconds / 60), seconds % 60);
}

function activityRows(activity: SessionStatsInput): ChatUsageDetail[] {
  const rows: ChatUsageDetail[] = [];
  if (activity.llmMs > 0) {
    rows.push({ id: 'llm', label: $r('app.string.desktop_chat_usage_llm'), value: durationText(activity.llmMs) });
  }
  if (activity.toolMs > 0) {
    rows.push({ id: 'tool', label: $r('app.string.desktop_chat_usage_tool'), value: durationText(activity.toolMs) });
  }
  if (activity.ttftSteps > 0) {
    rows.push({ id: 'ttft', label: $r('app.string.desktop_chat_usage_ttft'), value: durationText(activity.ttftMs / activity.ttftSteps) });
  }
  const speed = desktopChatTokensPerSecond(activity.decodeTokens, activity.decodeMs);
  if (speed) {
    rows.push({ id: 'speed', label: $r('app.string.desktop_chat_usage_speed'),
      value: $r('app.string.desktop_chat_usage_tps', speed) });
  }
  return rows;
}

function tokenRows(input: number, output: number, hit: string, read?: number, write?: number,
  reasoning?: number, routes?: DesktopChatUsageRoute[]): ChatUsageDetail[] {
  const rows: ChatUsageDetail[] = [];
  if (routes !== undefined && routes.length > 0) {
    rows.push({ id: 'routes', label: $r('app.string.desktop_chat_usage_routes'),
      value: routes.map((route: DesktopChatUsageRoute): string => route.provider + '/' + route.model).join(', ') });
  }
  if (hit) {
    rows.push({ id: 'hit', label: $r('app.string.desktop_chat_usage_hit_label'), value: hit + '%' });
  }
  rows.push({ id: 'input', label: $r('app.string.desktop_chat_usage_uncached'), value: exactTokens(input) });
  if (read !== undefined) {
    rows.push({ id: 'read', label: $r('app.string.desktop_chat_usage_read'), value: exactTokens(read) });
  }
  if (write !== undefined) {
    rows.push({ id: 'write', label: $r('app.string.desktop_trace_cache_write'), value: exactTokens(write) });
  }
  rows.push({ id: 'output', label: $r('app.string.desktop_trace_output_tokens'),
    value: reasoning === undefined ? exactTokens(output) :
      $r('app.string.desktop_chat_usage_reasoning', desktopChatExactTokens(output), desktopChatExactTokens(reasoning)) });
  return rows;
}

/** Trigger-anchored glass surface for the detailed readings. */
@Component
struct DesktopChatUsagePill {
  @Prop glyph: Resource = $r('app.media.dsh_chat_usage_database');
  @Prop @Watch('resetPill') ownerKey: string = '';
  @Prop @Watch('resetPill') simpleReading: boolean = false;
  @Prop enableReadingTip: boolean = false;
  @Prop @Watch('readingGeometryChanged') triggerMaxWidth: number = 400;
  @Prop triggerKey: string = '';
  @Prop popupKey: string = '';
  @Prop title: Resource = $r('app.string.desktop_chat_usage_session_title');
  @Prop titleValue: ResourceStr = '';
  @Prop @Watch('scheduleClippingCheck') label: ResourceStr = '';
  @Prop @Watch('scheduleClippingCheck') secondLabel: ResourceStr = '';
  @Prop detailRows: ChatUsageDetail[] = [];
  @Prop iconSize: number = 14;
  @Prop triggerHeight: number = 22;
  @Prop labelHidden: boolean = false;
  @Prop @Watch('readingGeometryChanged') availableWidth: number = 348;
  @State private popupVisible: boolean = false;
  @State private hovering: boolean = false;
  @State private readingClipped: boolean = false;
  @State private readingTip: boolean = false;
  @State private readingPinned: boolean = false;

  private labelWidth: number = -1;
  private secondLabelWidth: number = -1;
  private measuring: number = -1;
  private hoverDelay: number = -1;
  private observing: boolean = false;
  private labelFocused: boolean = false;

  aboutToAppear(): void {
    this.observing = true;
    this.scheduleClippingCheck();
  }

  aboutToDisappear(): void {
    this.observing = false;
    if (this.measuring >= 0) { clearTimeout(this.measuring); this.measuring = -1; }
    this.resetPill();
  }

  private closePopup(): void { this.popupVisible = false; }

  private resetPill(): void {
    this.closePopup();
    this.dismissTip();
    this.readingClipped = false;
    this.scheduleClippingCheck();
  }

  private readingGeometryChanged(): void {
    this.closeTip();
    this.scheduleClippingCheck();
  }

  private readingSized(width: number, second: boolean): void {
    if (!this.enableReadingTip || !Number.isFinite(width) || width < 0) { return; }
    if (second) {
      if (width === this.secondLabelWidth) { return; }
      this.secondLabelWidth = width;
    } else {
      if (width === this.labelWidth) { return; }
      this.labelWidth = width;
    }
    this.scheduleClippingCheck();
  }

  private isLabelClipped(label: ResourceStr, width: number): boolean {
    if (label === '' || width < 0) { return false; }
    const context = this.getUIContext();
    const pixels = context.getMeasureUtils().measureText({ textContent: label, fontSize: READING_FONT_SIZE });
    return Number.isFinite(pixels) && pixels > Math.ceil(context.vp2px(width));
  }

  private scheduleClippingCheck(): void {
    if (!this.observing || !this.enableReadingTip || this.measuring >= 0) { return; }
    // Size callbacks run during layout. Reconcile both segments outside that pass.
    this.measuring = setTimeout((): void => {
      this.measuring = -1;
      if (!this.observing) { return; }
      this.readingClipped = this.isLabelClipped(this.label, this.labelWidth) ||
        this.isLabelClipped(this.secondLabel, this.secondLabelWidth);
      if (!this.readingClipped) {
        this.closeTip();
      } else if (this.labelFocused) {
        this.showTip();
      } else if (this.hovering) {
        this.scheduleHoverTip();
      }
    }, 0);
  }

  private cancelHoverDelay(): void {
    if (this.hoverDelay < 0) { return; }
    clearTimeout(this.hoverDelay);
    this.hoverDelay = -1;
  }

  private closeTip(): void {
    this.cancelHoverDelay();
    this.readingTip = false;
    this.readingPinned = false;
  }

  private dismissTip(): void {
    this.closeTip();
    this.hovering = false;
    this.labelFocused = false;
  }

  private showTip(): void {
    if (this.enableReadingTip && this.readingClipped && !this.popupVisible) { this.readingTip = true; }
  }

  private scheduleHoverTip(): void {
    if (!this.readingClipped || this.popupVisible || this.readingTip || this.hoverDelay >= 0) { return; }
    this.hoverDelay = setTimeout((): void => {
      this.hoverDelay = -1;
      if (this.observing && this.hovering) { this.showTip(); }
    }, READING_TIP_DELAY_MS);
  }

  private hoverChanged(inside: boolean): void {
    this.hovering = inside;
    if (inside) {
      this.scheduleHoverTip();
    } else {
      this.cancelHoverDelay();
      if (!this.readingPinned) { this.closeTip(); }
    }
  }

  private focusChanged(focused: boolean): void {
    this.labelFocused = focused;
    if (focused) {
      this.cancelHoverDelay();
      this.showTip();
    } else if (!this.hovering && !this.readingPinned) {
      this.closeTip();
    }
  }

  private togglePlainTip(): void {
    if (!this.enableReadingTip || !this.readingClipped) { return; }
    if (this.readingPinned) {
      this.dismissTip();
      return;
    }
    this.cancelHoverDelay();
    this.readingPinned = true;
    this.showTip();
  }

  private toggleDetails(): void {
    this.dismissTip();
    this.popupVisible = !this.popupVisible;
  }

  private dismissOnEscape(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
    if (this.popupVisible) {
      this.closePopup();
      return true;
    }
    if (this.readingTip || this.hoverDelay >= 0) {
      this.dismissTip();
      return true;
    }
    return false;
  }

  private handleKey(event: KeyEvent, plain: boolean = false): boolean {
    if (event.type !== KeyType.Down) { return false; }
    if (this.dismissOnEscape(event)) { return true; }
    if (event.keyCode === KeyCode.KEYCODE_TAB && this.simpleReading) { this.dismissTip(); }
    if (plain && (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
      this.togglePlainTip();
      return true;
    }
    return false;
  }

  private labelMaxWidth(second: boolean): number {
    const width = this.triggerMaxWidth - this.iconSize - 21;
    if (this.secondLabel === '') { return Math.max(1, width); }
    return Math.max(1, (width - 16) * (second ? 0.43 : 0.57));
  }

  private detailValue(id: string): ResourceStr {
    return this.detailRows.find((row: ChatUsageDetail): boolean => row.id === id)?.value ?? '';
  }

  @Builder
  private Glyph() {
    Image(this.glyph).width(this.iconSize).height(this.iconSize).supportSvg2(true).draggable(false)
      .accessibilityLevel('no')
  }

  @Builder
  private Reading() {
    Row({ space: 6 }) {
      Text(this.label).fontSize(READING_FONT_SIZE).fontColor($r('sys.color.font_tertiary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
        .constraintSize({ maxWidth: this.labelMaxWidth(false) })
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => { this.readingSized(Number(size.width), false); })
      if (this.secondLabel !== '') {
        Text('·').fontSize(12).fontColor($r('sys.color.font_tertiary')).accessibilityLevel('no')
        Text(this.secondLabel).fontSize(READING_FONT_SIZE).fontColor($r('sys.color.font_tertiary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
          .constraintSize({ maxWidth: this.labelMaxWidth(true) })
          .onSizeChange((_old: SizeOptions, size: SizeOptions): void => { this.readingSized(Number(size.width), true); })
      }
    }.flexShrink(1)
  }

  @Builder
  private Panel() {
    Scroll() {
      Column({ space: 7 }) {
        Row({ space: 10 }) {
          Row({ space: 6 }) {
            this.Glyph()
            Text(this.title).fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary')).flexShrink(1)
          }.layoutWeight(1)
          Text(this.titleValue).fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
        }.width('100%').alignItems(VerticalAlign.Top)
        Divider().color($r('app.color.workspace_border'))
        ForEach(this.detailRows, (row: ChatUsageDetail): void => {
          Row({ space: 12 }) {
            Text(row.label).fontSize(12).fontColor($r('sys.color.font_tertiary'))
              .layoutWeight(1).maxLines(2)
            Text(this.detailValue(row.id)).key(this.popupKey + '-' + row.id)
              .fontSize(12).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.End)
              .constraintSize({ maxWidth: Math.max(100, Math.min(220, this.availableWidth * 0.56)) })
              .wordBreak(WordBreak.BREAK_WORD)
          }.width('100%').alignItems(VerticalAlign.Top)
        }, (row: ChatUsageDetail): string => row.id)
      }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
    }.key(this.popupKey).accessibilityText(this.title)
      .width(Math.max(180, Math.min(360, this.availableWidth - 24))).constraintSize({ maxHeight: 315 })
      .align(Alignment.TopStart).focusable(true).defaultFocus(true)
      .onKeyEvent((event: KeyEvent): boolean => this.handleKey(event))
  }

  @Builder
  private Content() {
    Row({ space: 5 }) {
      this.Glyph()
      if (!this.labelHidden) { this.Reading() }
    }.padding({ left: this.labelHidden ? 6 : 8, right: this.labelHidden ? 6 : 8 }).flexShrink(1)
  }

  @Builder
  private ReadingTip() {
    Text() {
      Span(this.label)
      if (this.secondLabel !== '') {
        Span(' · ')
        Span(this.secondLabel)
      }
    }.key(this.triggerKey + 'Tooltip').fontSize(READING_FONT_SIZE)
      .fontColor($r('sys.color.font_primary')).textAlign(TextAlign.Center)
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .constraintSize({ maxWidth: Math.max(100, Math.min(320, this.availableWidth - 24)) })
      .focusable(this.readingPinned).defaultFocus(this.readingPinned)
      .onKeyEvent((event: KeyEvent): boolean => this.handleKey(event))
  }

  build() {
    Row() {
      Row() {
        if (this.simpleReading) {
          if (this.readingClipped) {
            Row() { this.Content() }.height(this.triggerHeight).flexShrink(1).focusable(true)
              .onFocus((): void => { this.focusChanged(true); })
              .onBlur((): void => { this.focusChanged(false); })
              .onClick((): void => { this.togglePlainTip(); })
              .onKeyEvent((event: KeyEvent): boolean => this.handleKey(event, true))
          } else {
            Row() { this.Content() }.height(this.triggerHeight).flexShrink(1)
          }
        } else {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            this.Content()
          }.height(this.triggerHeight).padding(0).borderRadius(6).flexShrink(1).focusOnTouch(false)
            .accessibilityGroup(true).accessibilityText(this.title)
            .backgroundColor(this.popupVisible || this.hovering ? $r('app.color.workspace_selection') : Color.Transparent)
            .onFocus((): void => { this.focusChanged(true); })
            .onBlur((): void => { this.focusChanged(false); })
            .onClick((): void => { this.toggleDetails(); })
            .onKeyEvent((event: KeyEvent): boolean => this.handleKey(event))
        }
      }.flexShrink(1)
        .onHover((inside: boolean): void => { this.hoverChanged(inside); })
        .bindPopup(this.readingTip && !this.popupVisible, { builder: this.ReadingTip(), placement: Placement.Top,
          targetSpace: 8, enableArrow: false, focusable: this.readingPinned, mask: false, autoCancel: this.readingPinned,
          systemMaterial: desktopMenuOptions(Placement.Top).systemMaterial,
          onStateChange: (event): void => {
            if (!event.isVisible && this.readingTip) { this.dismissTip(); }
          } })
    }.key(this.triggerKey).flexShrink(1).constraintSize({ maxWidth: this.triggerMaxWidth })
      .bindPopup(this.popupVisible, { builder: this.Panel(), placement: Placement.TopLeft, targetSpace: 8,
        enableArrow: false, focusable: true, mask: false, autoCancel: true,
        systemMaterial: desktopMenuOptions(Placement.TopLeft).systemMaterial,
        onStateChange: (event): void => { if (!event.isVisible) { this.closePopup(); } } })
  }
}

/** Native compact or detailed performance and token readings beside the composer controls. */
@Component
export struct DesktopChatUsageDock {
  @Prop stats: DesktopChatUsageSnapshot = emptyDesktopChatUsage();
  @Prop compact: boolean = false;
  @Prop sessionId: string = '';
  @Prop availableWidth: number = 348;

  private speed(): string {
    return desktopChatTokensPerSecond(this.stats.activity.decodeTokens, this.stats.activity.decodeMs);
  }

  private counts(): Resource {
    return $r('app.string.desktop_chat_usage_counts', this.stats.activity.turns, this.stats.activity.steps);
  }

  private activityLabel(): ResourceStr {
    return this.compact ? $r('app.string.desktop_chat_usage_tps', this.speed()) : this.counts();
  }

  private detailSpeed(): ResourceStr {
    const speed = this.speed();
    return !this.compact && speed ? $r('app.string.desktop_chat_usage_tps', speed) : '';
  }

  private promptTokens(): number {
    const usage = this.stats.usage;
    return usage === undefined ? 0 : usage.uncachedInputTokens + usage.cacheReadTokens + usage.cacheWriteTokens;
  }

  private tokenTotal(): number { return this.promptTokens() + (this.stats.usage?.outputTokens ?? 0); }

  private cacheText(): string { return desktopChatCachePercent(this.stats.usage?.cacheReadTokens, this.promptTokens()); }

  private cacheLabel(): ResourceStr {
    const hit = this.cacheText();
    return hit ? $r('app.string.desktop_chat_usage_hit', hit + '%') : '';
  }

  private usageRows(): ChatUsageDetail[] {
    const data: DesktopChatSessionUsage | undefined = this.stats.usage;
    return data === undefined ? [] : tokenRows(data.uncachedInputTokens, data.outputTokens, this.cacheText(),
      data.cacheReadTokens, data.cacheWriteTokens === 0 ? undefined : data.cacheWriteTokens);
  }

  private isPlainActivity(): boolean {
    const activity = this.stats.activity;
    return this.compact || !(activity.llmMs > 0 || activity.toolMs > 0 || activity.ttftSteps > 0 || this.speed());
  }

  private showsActivity(): boolean {
    return this.compact ? this.speed() !== '' : this.stats.activity.steps > 0;
  }

  private showsUsage(): boolean {
    return this.stats.usage !== undefined && this.tokenTotal() > 0 && (!this.compact || this.cacheText() !== '');
  }

  private dockMaxWidth(): number {
    return Math.max(48, Math.min(320, this.availableWidth / 2 - 16));
  }

  private pillMaxWidth(): number {
    const width = this.dockMaxWidth();
    return this.showsActivity() && this.showsUsage() ? (width - 2) / 2 : width;
  }

  build() {
    Row({ space: 2 }) {
      if (this.showsActivity()) {
        DesktopChatUsagePill({ glyph: $r('app.media.dsh_chat_usage_gauge'), ownerKey: this.sessionId, enableReadingTip: true,
          simpleReading: this.isPlainActivity(), triggerKey: 'desktopChatActivity', popupKey: 'desktopChatActivityPopup',
          title: $r('app.string.desktop_chat_usage_activity_title'), titleValue: this.counts(),
          label: this.activityLabel(), secondLabel: this.detailSpeed(),
          detailRows: this.compact ? [] : activityRows(this.stats.activity), availableWidth: this.availableWidth,
          triggerMaxWidth: this.pillMaxWidth() })
      }
      if (this.showsUsage()) {
        DesktopChatUsagePill({ ownerKey: this.sessionId, simpleReading: this.compact, enableReadingTip: true,
          triggerKey: 'desktopChatUsage', popupKey: 'desktopChatUsagePopup',
          title: $r('app.string.desktop_chat_usage_session_title'), titleValue: exactTokens(this.tokenTotal()),
          label: this.compact ? this.cacheLabel() : compactTokens(this.tokenTotal()),
          secondLabel: this.compact ? '' : this.cacheLabel(),
          detailRows: this.compact ? [] : this.usageRows(), availableWidth: this.availableWidth,
          triggerMaxWidth: this.pillMaxWidth() })
      }
    }.key('desktopChatUsageDock').flexShrink(1)
      .constraintSize({ maxWidth: this.dockMaxWidth() })
  }
}

/** Exact, completed-turn accounting attached to the reply actions. */
@Component
export struct DesktopChatUsageTurn {
  @Prop usage?: DesktopChatTurnUsage = undefined;
  @Prop compact: boolean = false;
  @Prop ownerKey: string = '';
  @Prop availableWidth: number = 348;
  @Prop narrow: boolean = false;

  private detail(): ChatUsageDetail[] {
    const data = this.usage;
    if (data === undefined) { return []; }
    return tokenRows(data.uncachedInputTokens, data.outputTokens,
      desktopChatCachePercent(data.cacheReadTokens, data.totalTokens - data.outputTokens, true),
      data.cacheReadTokens, data.cacheWriteTokens, data.reasoningTokens, data.routes);
  }

  build() {
    Row() {
      if (this.usage !== undefined && !this.compact) {
        DesktopChatUsagePill({ ownerKey: this.ownerKey,
          triggerKey: this.ownerKey ? 'desktopChatTurnUsage-' + this.ownerKey : 'desktopChatTurnUsage',
          popupKey: 'desktopChatTurnUsagePopup', title: $r('app.string.desktop_chat_usage_turn_title'),
          titleValue: exactTokens(this.usage.totalTokens),
          label: $r('app.string.desktop_chat_usage_turn_label', desktopChatCompactTokens(this.usage.totalTokens)),
          detailRows: this.detail(), iconSize: 15, triggerHeight: 28,
          labelHidden: this.narrow, availableWidth: this.availableWidth })
      }
    }.flexShrink(1)
  }
}
