import { KeyCode } from '@kit.InputKit';
import { desktopMenuOptions } from './DesktopMenuOptions';

@Component
export struct DesktopPiAiReorderHandle {
  @Prop handleId: string = '';
  @Prop rowPosition: number = 1;
  @Prop enabledForEdit: boolean = true;
  onStep: (direction: number) => void = (): void => {};
  onPointerHold: (pressed: boolean) => void = (): void => {};
  onDragBegin: (event: GestureEvent, handle: Area) => void = (): void => {};
  onDragUpdate: (event: GestureEvent) => void = (): void => {};
  onPanFinished: (event: GestureEvent) => void = (): void => {};
  onDragCancel: () => void = (): void => {};
  @State private hintVisible: boolean = false;
  private hintTimer: number = -1;
  private focusTimer: number = -1;
  private handleArea?: Area;

  aboutToDisappear(): void {
    clearTimeout(this.focusTimer);
    this.dismissHint();
    this.onPointerHold(false);
  }

  private dismissHint(): void {
    clearTimeout(this.hintTimer);
    this.hintTimer = -1;
    this.hintVisible = false;
  }

  private begin(event: GestureEvent): void {
    this.dismissHint();
    if (this.handleArea !== undefined) { this.onDragBegin(event, this.handleArea); }
  }

  private onKey(event: KeyEvent): boolean {
    if (!this.enabledForEdit || event.type !== KeyType.Down ||
      (event.keyCode !== KeyCode.KEYCODE_DPAD_UP && event.keyCode !== KeyCode.KEYCODE_DPAD_DOWN)) { return false; }
    this.dismissHint();
    this.onStep(event.keyCode === KeyCode.KEYCODE_DPAD_UP ? -1 : 1);
    event.stopPropagation();
    return true;
  }

  private focusHandle(): void {
    clearTimeout(this.focusTimer);
    this.focusTimer = setTimeout((): void => {
      try {
        const focus = this.getUIContext().getFocusController();
        focus.requestFocus(this.handleId);
      } catch (_) {}
    }, 16);
  }

  @Builder
  private Hint() {
    Text($r('app.string.desktop_model_option_reorder_help')).fontSize(12)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 }).fontColor($r('sys.color.font_primary'))
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }

  build() {
    Button('', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
      .id(this.handleId).width(28).height(28).padding(0).borderRadius(6).enabled(this.enabledForEdit)
      .backgroundImage($r('app.media.dsh_model_drag_handle'), ImageRepeat.NoRepeat)
      .backgroundImageSize({ width: 14, height: 14 }).backgroundImagePosition(Alignment.Center)
      .focusable(true).focusOnTouch(true)
      .onAreaChange((_previous: Area, area: Area): void => { this.handleArea = area; })
      .accessibilityText($r('app.string.desktop_model_option_reorder', this.rowPosition.toString()))
      .accessibilityDescription($r('app.string.desktop_model_option_reorder_help'))
      .onKeyPreIme((event: KeyEvent): boolean => this.onKey(event))
      .onClick((): void => { this.focusHandle(); })
      .onMouse((event: MouseEvent): void => {
        if (!this.enabledForEdit || event.button !== MouseButton.Left) { return; }
        if (event.action === MouseAction.Press) {
          this.dismissHint();
          this.onPointerHold(true);
        } else if (event.action === MouseAction.Release) {
          this.onPointerHold(false);
        }
      })
      .onHover((hovered: boolean): void => {
        this.dismissHint();
        if (!hovered) { this.onPointerHold(false); }
        if (hovered && this.enabledForEdit) {
          this.hintTimer = setTimeout((): void => { this.hintVisible = true; }, 300);
        }
      })
      .bindPopup(this.hintVisible, { builder: this.Hint(), placement: Placement.Bottom, targetSpace: 6,
        enableArrow: false, focusable: false, mask: false, autoCancel: false,
        systemMaterial: desktopMenuOptions(Placement.Bottom).systemMaterial })
      .priorityGesture(GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.All, distance: 5 }).allowedTypes([SourceTool.MOUSE, SourceTool.TOUCHPAD])
          .onActionStart((event: GestureEvent): void => { this.begin(event); })
          .onActionUpdate(this.onDragUpdate).onActionEnd(this.onPanFinished).onActionCancel(this.onDragCancel),
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ duration: 320 }).allowedTypes([SourceTool.Finger, SourceTool.Pen]),
          PanGesture({ direction: PanDirection.All, distance: 5 }).allowedTypes([SourceTool.Finger, SourceTool.Pen])
            .onActionStart((event: GestureEvent): void => { this.begin(event); })
            .onActionUpdate(this.onDragUpdate).onActionEnd(this.onPanFinished).onActionCancel(this.onDragCancel))))
  }
}
