import { controlMaterial } from 'platform';

export enum DesktopChatHistoryStatus {
  HIDDEN = 'hidden',
  MORE = 'more',
  LOADING = 'loading',
  PROCESSING = 'processing',
  RETRY = 'retry',
  START = 'start'
}

/** A fully loaded conversation needs no history control unless it had earlier pages. */
export function desktopChatHistoryState(hasEarlier: boolean, wasPartial: boolean,
  loading: boolean, processing: boolean, failed: boolean): DesktopChatHistoryStatus {
  if (!hasEarlier) {
    return wasPartial ? DesktopChatHistoryStatus.START : DesktopChatHistoryStatus.HIDDEN;
  }
  if (loading) { return DesktopChatHistoryStatus.LOADING; }
  if (failed) { return DesktopChatHistoryStatus.RETRY; }
  return processing ? DesktopChatHistoryStatus.PROCESSING : DesktopChatHistoryStatus.MORE;
}

export function desktopChatCanLoadHistory(status: DesktopChatHistoryStatus): boolean {
  return status === DesktopChatHistoryStatus.MORE || status === DesktopChatHistoryStatus.RETRY;
}

function historyLabel(status: DesktopChatHistoryStatus): Resource {
  switch (status) {
    case DesktopChatHistoryStatus.LOADING:
      return $r('app.string.desktop_chat_history_loading');
    case DesktopChatHistoryStatus.PROCESSING:
      return $r('app.string.desktop_chat_history_processing');
    case DesktopChatHistoryStatus.RETRY:
      return $r('app.string.desktop_chat_history_retry');
    case DesktopChatHistoryStatus.START:
      return $r('app.string.desktop_chat_history_start');
    default:
      return $r('app.string.desktop_chat_history_more');
  }
}

@Component
export struct DesktopChatHistoryEdge {
  @Prop status: DesktopChatHistoryStatus = DesktopChatHistoryStatus.HIDDEN;
  onLoad: () => void = (): void => {};

  @Builder
  private Label(status: DesktopChatHistoryStatus) {
    Text(historyLabel(status)).fontSize(12).fontColor($r('sys.color.font_secondary'))
      .maxLines(1).visibility(this.status === status ? Visibility.Visible : Visibility.Hidden)
      .accessibilityLevel(this.status === status ? 'auto' : 'no')
  }

  build() {
    Row() {
      if (this.status !== DesktopChatHistoryStatus.HIDDEN) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL }) {
          // Keep the button width stable while an earlier page arrives and is laid out.
          Stack() {
            this.Label(DesktopChatHistoryStatus.MORE)
            this.Label(DesktopChatHistoryStatus.LOADING)
            this.Label(DesktopChatHistoryStatus.PROCESSING)
            this.Label(DesktopChatHistoryStatus.RETRY)
            this.Label(DesktopChatHistoryStatus.START)
          }
        }
        .height(26).padding({ left: 12, right: 12 }).borderRadius(7)
        .backgroundColor($r('app.color.workspace_panel'))
        .focusOnTouch(false)
        .enabled(desktopChatCanLoadHistory(this.status))
        .opacity(desktopChatCanLoadHistory(this.status) ? 1 : 0.6)
        .accessibilityText(historyLabel(this.status))
        .key('desktopChatHistoryEdge')
        .onClick((): void => {
          if (desktopChatCanLoadHistory(this.status)) { this.onLoad(); }
        })
      }
    }.width('100%').justifyContent(FlexAlign.Center)
  }
}

@Component
export struct DesktopChatReturnToTail {
  onReturn: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
      Image($r('app.media.dsh_queue_chevron_down_outline')).width(16).height(16)
        .supportSvg2(true).draggable(false).accessibilityLevel('no')
    }
    .width(34).height(34).padding(0)
    .backgroundColor(controlMaterial() === undefined ? $r('app.color.workspace_panel') : undefined)
    .systemMaterial(controlMaterial())
    .border({ width: 1, color: $r('app.color.workspace_border') })
    .shadow({ radius: 8, color: '#20000000', offsetY: 2 })
    .focusOnTouch(false)
    .key('desktopChatReturnToTail')
    .accessibilityText($r('app.string.desktop_chat_return_to_tail'))
    .onClick(this.onReturn)
  }
}
