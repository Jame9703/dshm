/**
 * pi-ai 路由的编辑 / 新建浮层 —— 对齐 dsh 官方 Models 页的**逐字段表单**。
 *
 * ## 为什么必须有这个浮层（用户报的"自定义 API 保存不了"）
 *
 * 官方 Models 页的「添加模型提供商 → **自定义模型 API**」是**唯一**能创建
 * 目录外路由的入口：中转站、自部署服务、比 pi-ai 目录更新的提供方都属于这一类。
 * 我们此前没有这个入口，而候选列表来自 `llm/listProviders ∪
 * llm/listConfigurableProviders`——那是 **pi-ai 自带目录**，用户自己的
 * `wb2api` 这类路由两个目录里都不存在 ⇒ **界面上无处可加**。
 *
 * ## 与官方卡片逐字段对齐
 *
 * | 官方键 | 本浮层 | 说明 |
 * |---|---|---|
 * | `customRoute`（Provider ID） | 路由 id | 仅新建时可改；它是 settings 键与凭据引用词干 |
 * | `customDisplayName` | 显示名 | 仅新建时可改 |
 * | `baseUrl` | 端点 | 必填，须是 http/https |
 * | `customApi`（**API 协议**） | API 协议 | 下拉，候选**读自 schema**（不写死） |
 * | 模型目录（`ModelListEditor`） | 模型行 | 至少一个，id 必填 |
 * | `keyInput`（只写不读） | API 密钥 | 空 = 保留原密钥（页面读不回明文） |
 *
 * ## 边界：副作用全在宿主
 *
 * 与 `SettingTextSheet` / `SettingStructSheet` 同一条纪律：草稿、校验、写入与回执
 * 都归宿主；本组件只渲染 + 回调。它不持有 RPC、不认识端点名，也不自己跑校验
 * （校验结论由宿主演算后随 `fieldError` 传入）。
 */

import { checkPiAiModelReasoning, emptyModelRow, Fs, invalidPiAiCapacity, piAiReasoningProtocol, Radius, Sp, Sz } from 'appstate';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@kit.InputKit';
import { HarmonySpacing } from 'appstate';
import { protocolLabel } from 'appstate';
import type { PiAiModelRow, PiAiProviderView, PiAiReasoningProtocol } from 'appstate';
import { DesktopRetryPolicy } from '../desktop/DesktopRetryPolicy';
import { desktopMenuOptions } from '../desktop/DesktopMenuOptions';
import { DesktopPiAiModelDiscovery } from '../desktop/DesktopPiAiModelDiscovery';
import { PiAiModelSettingsRow } from './PiAiModelSettingsRow';
import type { DesktopHostActions } from '../desktop/DesktopHostActions';
import type { DesktopNewRetryPolicy, DesktopRetryChange, DesktopRetryDocument } from '../desktop/DesktopRetryPolicyModel';
import { desktopPiAiModelDrop, desktopPiAiModelInsertionIndex } from '../desktop/DesktopPiAiModelOrder';
import type { DesktopPiAiModelBand, DesktopPiAiModelInsertion } from '../desktop/DesktopPiAiModelOrder';

/** 表单模式：编辑已有路由 / 新建路由 */
export enum PiAiSheetMode {
  EDIT = 'edit',
  CREATE = 'create',
  CATALOG = 'catalog'
}

/** pi-ai 路由的编辑 / 新建浮层 */
@Component
export struct PiAiProviderSheet {
  /** 编辑还是新建（`PiAiSheetMode` 的取值；决定 id 是否可改与按钮文案） */
  @Prop mode: string = PiAiSheetMode.CREATE;
  @Prop inline: boolean = false;
  @Prop existingDeclared: boolean = false;
  @Prop existingDisplayName: string = '';
  @Prop existingDisplayNamePlaceholder: string = '';
  inlineScroller?: Scroller;
  @Prop inlineViewport: Area | undefined = undefined;
  @Prop existingKeyCanClear: boolean = false;
  @Prop existingKeyClearPending: boolean = false;
  @Prop existingKeyClearApplied: boolean = false;
  onExistingKeyClear: () => void = (): void => {};
  @Prop locked: boolean = false;
  @Prop profileCommitted: boolean = false;
  @Prop submitBlocked: boolean = false;
  @Prop hideKey: boolean = false;
  @Prop keyPlaceholder: ResourceStr = '';
  @Prop notice: ResourceStr = '';
  @Prop retryPath: string[] = [];
  @Prop retryDocument?: DesktopRetryDocument = undefined;
  onRetryOperations: (value: DesktopRetryChange) => void = (): void => {};
  onDiscoveryBusy: (value: boolean) => void = (): void => {};
  /** 正在编辑的表单值（真值在宿主） */
  @Prop draft: PiAiProviderView;
  @Prop modelKeys: number[] = [];
  @Prop catalogStandard: boolean = false;
  @Prop catalogWritable: boolean = false;
  @Prop modelsOverridden: boolean = false;
  onRestoreModels: () => void = (): void => {};
  /** 可声明的 API 协议（来自 Host schema；空 ⇒ 禁用选择并如实说明） */
  @Prop protocols: string[];
  @Prop reasoningLevels: string[] = [];
  /** 端点占位（随协议变化；宿主算好传入） */
  @Prop baseURLPlaceholder: string = '';
  /** 密钥草稿（只写不读：打开时恒为空） */
  @Prop keyDraft: string = '';
  /** 该路由的凭据引用（显示用：让人知道密钥存到哪个引用下） */
  @Prop keyRef: string = '';
  /** 该引用当前是否已配置（已配置时留空 = 保留原来那把） */
  @Prop keyConfigured: boolean = false;
  /** 端点/协议等字段的即时校验文案（宿主算好传进来） */
  @Prop fieldError: string = '';
  /** 结果 / 进度文案（空串 = 不显示） */
  @Prop note: string = '';
  /** 这一层的回执是否属于自己（归属标记由宿主统一管，见 E353） */
  @Prop noteOwned: boolean = false;
  /** 写入进行中（按钮防重复提交） */
  @Prop busy: boolean = false;
  retryHost?: DesktopHostActions;
  @Prop retryValid: boolean = true;
  onRetryDraft: (value: DesktopNewRetryPolicy) => void = (_value: DesktopNewRetryPolicy): void => {};

  onRouteChange: (value: string) => void = () => {
  };
  onDisplayNameChange: (value: string) => void = () => {
  };
  onBaseURLChange: (value: string) => void = () => {
  };
  onApiChange: (value: string) => void = () => {
  };
  onKeyChange: (value: string) => void = () => {
  };
  onModelChange: (index: number, row: PiAiModelRow) => void = () => {
  };
  onAddModel: () => void = () => {
  };
  onAdoptModels: (models: PiAiModelRow[]) => void = (_models: PiAiModelRow[]): void => {};
  onRemoveModel: (index: number) => void = () => {
  };
  onMoveModel: (source: number, target: number, after: boolean) => void = (): void => {};
  onSubmit: () => void = () => {
  };
  onDelete: () => void = () => {
  };
  onClose: () => void = () => {
  };
  @State private discovering: boolean = false;
  @State private advanced: boolean = false;
  @State private heldModel: number = -1;
  @State private draggedModel: number = -1;
  @State private insertion?: DesktopPiAiModelInsertion = undefined;
  @State private dragPicture?: image.PixelMap = undefined;
  @State private dragLeft: number = 0;
  @State private dragTop: number = 0;
  private dragWidth: number = 0;
  private dragHeight: number = 0;
  private dragOffsetX: number = 0;
  private dragOffsetY: number = 0;
  private dragWindowX: number = 0;
  private dragWindowY: number = 0;
  private dragVersion: number = 0;
  private focusTimer: number = -1;
  private sheetArea?: Area;
  private formArea?: Area;
  private readonly formScroller = new Scroller();
  private readonly modelBands = new Map<number, DesktopPiAiModelBand>();

  aboutToDisappear(): void {
    this.cancelModelDrag();
    clearTimeout(this.focusTimer);
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        this.Form()
        if (this.dragPicture !== undefined) {
          Image(this.dragPicture).width(this.dragWidth).height(this.dragHeight).objectFit(ImageFit.Fill)
            .position({ x: this.dragLeft, y: this.dragTop }).zIndex(2).draggable(false)
            .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        }
      }.width('100%').onAreaChange((_before: Area, area: Area): void => { this.sheetArea = area; })
    }.key(this.isInlineEdit() ? 'desktopPiAiProviderInlineEditor' : 'desktopPiAiProviderSheet-' + this.mode)
      .width('100%').padding(this.isInlineEdit() ? 0 : HarmonySpacing.CONTAINER)
  }

  @Builder
  private Form() {
    if (this.inline) {
      Column() { this.Fields() }
        .width('100%').onAreaChange((_before: Area, area: Area): void => { this.formArea = area; })
    } else {
      Scroll(this.formScroller) { this.Fields() }
        .width('100%').constraintSize({ maxHeight: '78%' })
        .enableScrollInteraction(this.heldModel < 0 && this.draggedModel < 0)
        .onAreaChange((_before: Area, area: Area): void => { this.formArea = area; })
    }
  }

  @Builder
  private Fields() {
    Column({ space: this.isInlineEdit() ? 14 : Sp.S }) {
      if (!this.inline) {
          Text(this.isCreate() ? '添加自定义模型 API' : `编辑提供方「${this.draft.route}」`)
            .fontSize(Fs.BODY)
            .width('100%')
          Text('为 pi-ai 目录里没有的路由（中转站、自部署服务）声明端点与协议。'
            + '这些字段没有任何东西能兜底，所以端点、协议与至少一个模型都是必填。')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
      }
      if (this.isInlineEdit()) {
        this.ExistingFields()
      } else if (this.mode === PiAiSheetMode.CATALOG) {
        if (!this.hideKey) { this.keyField() }
        Button($r('app.string.desktop_catalog_provider_advanced'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopCatalogProviderAdvanced').accessibilitySelected(this.advanced)
          .onClick((): void => { this.advanced = !this.advanced; })
        Column({ space: Sp.S }) {
          this.baseURLField()
          this.RetryField()
          this.modelsField()
        }.width('100%').visibility(this.advanced ? Visibility.Visible : Visibility.None)
      } else {
          this.idField()
          this.baseURLField()
          this.protocolField()
          if (this.inline) {
            this.keyField()
            this.RetryField()
            this.modelsField()
          } else {
            this.modelsField()
            this.keyField()
            this.RetryField()
          }
      }

      if (this.fieldError.length > 0) {
        Text(this.fieldError).fontSize(Fs.CAPTION).fontColor($r('sys.color.alert')).width('100%')
      }
      if (this.notice !== '') {
        Text(this.notice).key('desktopCatalogProviderNotice').fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.alert')).width('100%')
      }
      if (this.noteOwned && this.note.length > 0) {
        Text(this.note).fontSize(Fs.CAPTION).fontColor($r('sys.color.font_secondary')).width('100%')
      }

      if (this.isInlineEdit()) {
        this.ExistingFooter()
      } else {
        Row({ space: Sp.S }) {
          Button('取消')
            .key('desktopPiAiProviderCancel').layoutWeight(1).enabled(!this.inline || (!this.busy && !this.discovering))
            .backgroundColor($r('sys.color.background_secondary')).fontColor($r('sys.color.font_primary'))
            .onClick((): void => { this.onClose(); })
          Button(this.isCreate() ? '添加' : '保存')
            .key('desktopPiAiProviderSubmit').layoutWeight(1).enabled(this.canSubmit())
            .onClick((): void => { this.onSubmit(); })
        }.width('100%')
      }
      if (!this.inline && this.mode === PiAiSheetMode.EDIT) {
        Button('删除这个提供方').width('100%').enabled(!this.busy && !this.discovering)
          .backgroundColor($r('sys.color.background_secondary')).fontColor($r('sys.color.warning'))
          .onClick((): void => { this.onDelete(); })
      }
    }.width('100%').padding(this.fieldsPadding()).borderRadius(Radius.L)
      .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  private ExistingFields() {
    Flex({ alignItems: ItemAlign.Baseline }) {
      Text(this.existingTitle()).fontSize(14).lineHeight(22).fontWeight(FontWeight.Medium)
      if (this.existingTitle() !== this.draft.route) {
        Text(this.draft.route).fontSize(12).lineHeight(18).fontColor($r('sys.color.font_tertiary')).margin({ left: 8 })
      }
    }.width('100%')
    if (!this.hideKey) { this.ExistingKeyField() }
    Column({ space: 10 }) {
      Divider().strokeWidth(0.5).color($r('app.color.workspace_border'))
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Image(this.advanced ? $r('app.media.dsh_queue_chevron_down_outline') :
            $r('app.media.dsh_browser_chevron_right_outline')).width(12).height(12)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
          Text($r('app.string.desktop_model_provider_editor_advanced')).fontSize(13)
        }
      }.key('desktopPiAiProviderAdvanced').height(28).padding({ left: 4, right: 6 })
        .accessibilitySelected(this.advanced).onClick((): void => {
          if (this.advanced) { this.cancelModelDrag(); }
          this.advanced = !this.advanced;
        })
      Column({ space: 12 }) {
        if (this.existingDeclared) {
          Column({ space: 6 }) {
            Text($r('app.string.desktop_model_provider_editor_display_name')).fontSize(12).width('100%')
              .fontColor($r('sys.color.font_secondary'))
            TextInput({ text: this.draft.displayName, placeholder: this.existingDisplayNamePlaceholder || this.draft.route })
              .key('desktopPiAiProviderDisplayName').width('100%').height(Sz.TOUCH_MIN).fontSize(Fs.SECONDARY)
              .accessibilityText($r('app.string.desktop_model_provider_editor_display_name'))
              .enabled(this.canChangeModelFields())
              .onChange((value: string): void => {
                if (this.canChangeModelFields() && value !== this.draft.displayName) { this.onDisplayNameChange(value); }
              })
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        this.baseURLField()
        if (this.existingDeclared) { this.protocolField() }
        this.RetryField()
        this.modelsField()
      }.width('100%').visibility(this.advanced ? Visibility.Visible : Visibility.None)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ExistingFooter() {
    Row({ space: 8 }) {
      Blank().layoutWeight(1)
      Button(this.existingKeyClearApplied ? $r('app.string.desktop_model_provider_editor_close') :
        $r('app.string.desktop_model_provider_editor_cancel'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopPiAiProviderCancel').height(36).borderRadius(8).fontSize(14).padding({ left: 14, right: 14 })
        .border({ width: 0.5, color: $r('app.color.workspace_border') })
        .enabled(!this.busy).onClick((): void => { if (!this.busy) { this.onClose(); } })
      Button(this.busy ? $r('app.string.desktop_model_provider_editor_applying') :
        $r('app.string.desktop_model_provider_editor_apply'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED })
        .key('desktopPiAiProviderSubmit').height(36).borderRadius(8).fontSize(14).fontWeight(FontWeight.Medium)
        .padding({ left: 16, right: 16 })
        .enabled(this.canSubmit()).onClick((): void => { if (this.canSubmit()) { this.onSubmit(); } })
    }.width('100%')
  }

  @Builder
  private RetryField() {
    if (this.inline && this.retryDocument !== undefined) {
      DesktopRetryPolicy({ namespace: 'llm-pi-ai', path: this.retryPath, suppliedDocument: this.retryDocument,
        draftOnly: true, parentBusy: this.busy || this.locked || this.profileCommitted,
        onOperations: this.onRetryOperations })
    } else if (!this.inline && this.mode === PiAiSheetMode.CREATE && this.retryHost !== undefined) {
            DesktopRetryPolicy({ host: this.retryHost, namespace: 'llm-pi-ai',
              path: ['providers', '', 'retryPolicy'], draftOnly: true, parentBusy: this.busy,
              onDraft: this.onRetryDraft })
    }
  }

  private modelIndex(key: number): number { return this.modelKeys.indexOf(key); }

  private modelFor(key: number): PiAiModelRow { return this.draft.models[this.modelIndex(key)] ?? emptyModelRow(); }

  private modelHandle(key: number): string { return 'desktopPiAiModelReorder-' + key; }

  private modelBody(key: number): string { return 'desktopPiAiModelReorderBody-' + key; }

  private stepModel(key: number, direction: number): void {
    if (!this.canChangeModelFields() || this.draggedModel >= 0) { return; }
    const from = this.modelIndex(key);
    const target = this.modelKeys[from + direction];
    if (from < 0 || target === undefined) { return; }
    this.onMoveModel(key, target, direction > 0);
    clearTimeout(this.focusTimer);
    this.focusTimer = setTimeout((): void => {
      try { this.getUIContext().getFocusController().requestFocus(this.modelHandle(key)); } catch (_) {}
    }, 16);
  }

  private rememberModelBand(key: number, area: Area): void {
    this.modelBands.set(key, { key: key, left: Number(area.globalPosition.x), top: Number(area.globalPosition.y),
      width: Number(area.width), height: Number(area.height) });
  }

  private modelDragPoint(event: GestureEvent): FingerInfo | undefined {
    return event.fingerInfos?.[0] ?? event.fingerList[0];
  }

  private holdModel(key: number, pressed: boolean): void {
    if (pressed && this.canChangeModelFields() && this.modelKeys.length > 1) { this.heldModel = key; }
    else if (!pressed && this.heldModel === key) { this.heldModel = -1; }
  }

  private beginModelDrag(key: number, event: GestureEvent, handle: Area): void {
    if (!this.canChangeModelFields() || this.draggedModel >= 0 || this.modelKeys.length < 2) { return; }
    const band = this.modelBands.get(key);
    const point = this.modelDragPoint(event);
    if (band === undefined || point === undefined) { return; }
    this.dragWidth = band.width;
    this.dragHeight = band.height;
    const x = Number(handle.globalPosition.x) + point.localX;
    const y = Number(handle.globalPosition.y) + point.localY;
    // Gesture coordinates use the app window even when the sheet opens in a subwindow.
    this.dragWindowX = point.globalX - x;
    this.dragWindowY = point.globalY - y;
    this.dragOffsetX = x - event.offsetX - band.left;
    this.dragOffsetY = y - event.offsetY - band.top;
    const revision = ++this.dragVersion;
    this.getUIContext().getComponentSnapshot().get(this.modelBody(key)).then((preview: image.PixelMap): void => {
      if (revision === this.dragVersion && this.draggedModel === key) { this.dragPicture = preview; }
      else { preview.release().catch((): void => {}); }
    }).catch((): void => {});
    this.draggedModel = key;
    this.updateModelDrag(event);
  }

  private updateModelDrag(event: GestureEvent, canScroll: boolean = true): void {
    if (!this.canChangeModelFields()) { this.cancelModelDrag(); return; }
    const inlineFrame = this.inline ? this.inlineViewport : undefined;
    const frame = inlineFrame ?? this.formArea;
    const scroller = this.inline ? (inlineFrame === undefined ? undefined : this.inlineScroller) : this.formScroller;
    const root = this.sheetArea;
    const point = this.modelDragPoint(event);
    if (this.draggedModel < 0 || point === undefined || frame === undefined || root === undefined) { return; }
    const pointerX = point.globalX - this.dragWindowX;
    const pointerY = point.globalY - this.dragWindowY;
    this.dragLeft = pointerX - Number(root.globalPosition.x) - this.dragOffsetX;
    this.dragTop = pointerY - Number(root.globalPosition.y) - this.dragOffsetY;
    const x = pointerX - Number(frame.globalPosition.x);
    const y = pointerY - Number(frame.globalPosition.y);
    const inside = x >= 0 && x < Number(frame.width) && y >= 0 && y < Number(frame.height);
    if (!inside) { this.insertion = undefined; return; }
    if (canScroll && scroller !== undefined) {
      const height = Number(frame.height);
      if (y < 26) { scroller.scrollBy(0, (y - 26) * 0.45); }
      else if (y > height - 26) { scroller.scrollBy(0, (y - height + 26) * 0.45); }
    }
    const visible: DesktopPiAiModelBand[] = [];
    for (const key of this.modelKeys) {
      const band = this.modelBands.get(key);
      if (band !== undefined) { visible.push(band); }
    }
    this.insertion = desktopPiAiModelDrop(visible, pointerX, pointerY, this.draggedModel);
  }

  private endModelDrag(event: GestureEvent): void {
    this.updateModelDrag(event, false);
    const from = this.draggedModel;
    const target = this.insertion;
    this.cancelModelDrag();
    if (this.canChangeModelFields() && target !== undefined &&
      desktopPiAiModelInsertionIndex(this.modelKeys, from, target.key, target.after) >= 0) {
      this.onMoveModel(from, target.key, target.after);
    }
  }

  private cancelModelDrag(): void {
    this.dragVersion++;
    this.draggedModel = -1;
    this.heldModel = -1;
    this.insertion = undefined;
    const preview = this.dragPicture;
    this.dragPicture = undefined;
    preview?.release().catch((): void => {});
  }

  @Builder
  private InsertionLine() {
    Row({ space: 0 }) {
      Image($r('app.media.dsh_model_drop_wedge')).width(6).height(8).supportSvg2(true).draggable(false)
      Column().height(2).layoutWeight(1).backgroundColor('#4084DB')
    }.width('100%').height(8).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }

  @Builder
  private ModelRow(key: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        PiAiModelSettingsRow({ initialModel: this.modelFor(key), rowIndex: this.modelIndex(key),
          reorderHandleId: this.modelHandle(key), defaultInput: this.draft.defaultInput, reasoning: this.reasoningProtocol(),
          removable: this.isInlineEdit() || this.mode === PiAiSheetMode.CATALOG || this.modelKeys.length > 1,
          editingEnabled: this.canChangeModelFields(),
          onChange: (value: PiAiModelRow): void => {
            if (this.canChangeModelFields()) { this.onModelChange(this.modelIndex(key), value); }
          },
          onRemove: (): void => {
            if (this.canChangeModelFields()) { this.onRemoveModel(this.modelIndex(key)); }
          },
          onOrderStep: (step: number): void => { this.stepModel(key, step); },
          onOrderHold: (pressed: boolean): void => { this.holdModel(key, pressed); },
          onOrderBegin: (event: GestureEvent, handle: Area): void => { this.beginModelDrag(key, event, handle); },
          onOrderUpdate: (event: GestureEvent): void => { this.updateModelDrag(event); },
          onOrderEnd: (event: GestureEvent): void => { this.endModelDrag(event); },
          onOrderCancel: (): void => { this.cancelModelDrag(); } })
      }.width('100%').id(this.modelBody(key)).opacity(this.draggedModel === key ? 0.5 : 1)
      if (this.insertion?.key === key) {
        Column() { this.InsertionLine() }.width('100%').height(8)
          .align(this.insertion?.after ? Alignment.BottomStart : Alignment.TopStart)
          .position({ x: 0, y: this.insertion?.after ? (this.modelBands.get(key)?.height ?? 0) : -8 })
          .zIndex(1).hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').onAreaChange((_before: Area, area: Area): void => { this.rememberModelBand(key, area); })
  }

  /** 是否新建模式（`mode` 以 string 传入，集中一处判定） */
  private isCreate(): boolean {
    return this.mode === PiAiSheetMode.CREATE;
  }

  private isInlineEdit(): boolean { return this.inline && this.mode === PiAiSheetMode.EDIT; }

  private existingTitle(): string { return this.existingDisplayName || this.draft.displayName || this.draft.route; }

  private fieldsPadding(): Padding {
    if (this.isInlineEdit()) { return { top: 14, bottom: 14, left: 16, right: 16 }; }
    const space = this.inline ? Sp.S : Sp.L;
    return { top: space, bottom: space, left: space, right: space };
  }

  private canChangeModelFields(): boolean { return !this.locked && !this.busy && !this.profileCommitted; }

  private canSubmit(): boolean {
    return !this.locked && !this.submitBlocked && !this.busy && !this.discovering && this.retryValid &&
      this.capacitiesValid() && this.reasoningValid();
  }

  private capacitiesValid(): boolean {
    return (this.catalogStandard && !this.modelsOverridden) || this.draft.models.every((row: PiAiModelRow): boolean =>
      !invalidPiAiCapacity(row.contextWindow) && !invalidPiAiCapacity(row.maxTokens));
  }

  private reasoningProtocol(): PiAiReasoningProtocol { return piAiReasoningProtocol(this.draft.api, this.reasoningLevels); }

  private reasoningValid(): boolean {
    const protocol = this.reasoningProtocol();
    return (this.catalogStandard && !this.modelsOverridden && !protocol.levelsOnly) ||
      this.draft.models.every((row: PiAiModelRow): boolean => checkPiAiModelReasoning(row, protocol) === '');
  }

  private protocolMenu(): MenuElement[] {
    return this.protocols.map((id: string): MenuElement => ({ value: protocolLabel(id),
      icon: id === this.draft.api ? $r('app.media.dsh_dock_check') : undefined,
      action: (): void => { if (this.canChangeModelFields()) { this.onApiChange(id); } } }));
  }

  /** Provider ID / 显示名 */
  @Builder
  idField() {
    if (this.isCreate()) {
      Text('Provider ID')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.draft.route, placeholder: 'my-gateway' })
        .key('desktopPiAiProviderRoute')
        .fontSize(Fs.SECONDARY)
        .height(Sz.TOUCH_MIN)
        .width('100%')
        .enabled(!this.locked && !this.busy && !this.profileCommitted)
        .onChange((v: string) => {
          this.onRouteChange(v);
        })
      Text('只能用小写字母、数字与连字符，并以字母开头。它同时是设置键与凭据引用名（<ID>_API_KEY）。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')

      Text('显示名（可选）')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.draft.displayName, placeholder: this.draft.route })
        .fontSize(Fs.SECONDARY)
        .height(Sz.TOUCH_MIN)
        .width('100%')
        .enabled(!this.locked && !this.busy && !this.profileCommitted)
        .onChange((v: string) => {
          this.onDisplayNameChange(v);
        })
    } else {
      /*
       * 编辑模式下 id 与显示名**不可改**。理由同官方注释：Provider ID 是 settings 的键、
       * 是其它每个命名空间与已记录会话引用的名字、也是搬不走的凭据引用词干——
       * 改它等于换一个提供方，而不是编辑这一个。
       */
      Text(`Provider ID：${this.draft.route}（创建后不可改）`)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
  }

  /** 端点 */
  @Builder
  baseURLField() {
    Text(this.isInlineEdit() ? $r('app.string.desktop_model_provider_editor_endpoint') : 'API 地址（端点）')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
    TextInput({ text: this.draft.baseURL, placeholder: this.baseURLPlaceholder })
      .key('desktopPiAiProviderBaseURL')
      .fontSize(Fs.SECONDARY)
      .height(Sz.TOUCH_MIN)
      .width('100%')
      .enabled(!this.locked && !this.busy && !this.profileCommitted)
      .onChange((v: string) => {
        if (this.canChangeModelFields() && (!this.isInlineEdit() || v !== this.draft.baseURL)) { this.onBaseURLChange(v); }
      })
  }

  /** API 协议（官方 `customApi`，中文文案即「API 协议」） */
  @Builder
  protocolField() {
    Text(this.isInlineEdit() ? $r('app.string.desktop_model_provider_editor_protocol') : 'API 协议')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
    if (this.protocols.length === 0) {
      // 读不到候选时**如实说明并禁用**，而不是给一个点了没用的下拉
      Text('Host 没有报告可声明的协议（schema 未读到），暂时无法保存。请确认核心版本后重试。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.warning'))
        .width('100%')
    } else if (this.isInlineEdit()) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          Text(this.draft.api ? protocolLabel(this.draft.api) : $r('app.string.desktop_model_provider_editor_protocol_unset'))
            .fontSize(14).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.dsh_queue_chevron_down_outline')).width(14).height(14)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
        }.width('100%')
      }.key('desktopPiAiProviderProtocol').width('100%').height(36).borderRadius(8)
        .padding({ left: 10, right: 10 }).backgroundColor($r('sys.color.background_primary'))
        .enabled(this.canChangeModelFields()).bindMenu(this.protocolMenu(), desktopMenuOptions(Placement.BottomLeft))
    } else if (this.inline) {
      Button(protocolLabel(this.draft.api), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .key('desktopPiAiProviderProtocol').width('100%').enabled(!this.locked && !this.busy && !this.profileCommitted)
        .bindMenu(this.protocolMenu(), desktopMenuOptions(Placement.BottomLeft))
    } else {
      ForEach(this.protocols, (api: string) => {
        Row({ space: Sp.S }) {
          SymbolGlyph(this.draft.api === api
            ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.circle'))
            .fontSize(16)   // token-exempt: 行内图标尺寸
            .fontColor([this.draft.api === api ? $r('sys.color.brand') : $r('sys.color.font_tertiary')])
          Text(protocolLabel(api))
            .fontSize(Fs.SECONDARY)
            .layoutWeight(1)
          Text(api)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .padding(Sp.S)
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_primary'))
        .onClick(() => {
          this.onApiChange(api);
        })
      }, (api: string) => api)
    }
  }

  /** 模型目录（官方 `ModelListEditor`） */
  @Builder
  modelsField() {
    Row({ space: Sp.S }) {
      Column({ space: 4 }) {
        Text(this.isInlineEdit() ? $r('app.string.desktop_model_provider_editor_models') :
          `模型目录（${this.draft.models.length} 个）`).fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary'))
        if (this.catalogStandard || this.isInlineEdit()) {
          Text(this.modelsOverridden ? $r('app.string.desktop_model_catalog_customized') :
            $r('app.string.desktop_model_catalog_inherited')).key('desktopPiAiModelsLayer')
            .fontSize(Fs.CAPTION).fontColor($r('sys.color.font_tertiary'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if ((this.catalogStandard || this.isInlineEdit()) && this.modelsOverridden) {
        Button($r('app.string.desktop_model_catalog_restore'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPiAiRestoreModels').fontSize(Fs.CAPTION).height(32)
          .enabled(this.catalogWritable && this.canChangeModelFields() && !this.discovering)
          .onClick((): void => {
            if (this.catalogWritable && this.canChangeModelFields() && !this.discovering) { this.onRestoreModels(); }
          })
      }
    }.width('100%')
    if ((this.catalogStandard || this.isInlineEdit()) && this.draft.models.length === 0) {
      Text($r('app.string.desktop_model_catalog_empty')).fontSize(Fs.CAPTION).width('100%')
        .fontColor($r('sys.color.font_tertiary'))
    }
    if (this.retryHost !== undefined) {
      DesktopPiAiModelDiscovery({ host: this.retryHost, provider: this.isCreate() ? '' : this.draft.route,
        endpoint: this.draft.baseURL, api: this.draft.api, keyReference: this.isCreate() ? '' : this.draft.apiKeyEnv,
        keyDraft: this.keyDraft, models: this.draft.models,
        unavailable: !this.canChangeModelFields() || (this.isInlineEdit() && this.existingKeyClearPending),
        onAdopt: (models: PiAiModelRow[]): void => {
          if (this.canChangeModelFields() && (!this.isInlineEdit() || !this.existingKeyClearPending)) {
            this.onAdoptModels(models);
          }
        }, onFetchingChange: (fetching: boolean): void => {
          this.discovering = fetching;
          this.onDiscoveryBusy(fetching);
        } })
    }
    if (!this.isInlineEdit()) {
      Text('模型 id 是"这个路由提供什么"的唯一依据；显示名可不填（不填就沿用适配器默认）。')
        .fontSize(Fs.CAPTION).fontColor($r('sys.color.font_tertiary')).width('100%')
    }
    Column({ space: 12 }) {
      ForEach(this.modelKeys, (key: number): void => { this.ModelRow(key); }, (key: number): string => String(key))
    }.width('100%')
    if (this.isInlineEdit()) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 6 }) {
          Image($r('app.media.dsh_reference_menu_plus')).width(14).height(14)
            .supportSvg2(true).draggable(false).accessibilityLevel('no')
          Text($r('app.string.desktop_model_provider_editor_add_model')).fontSize(12)
        }
      }.key('desktopPiAiProviderModelAdd').height(34).borderRadius(8)
        .enabled(this.canChangeModelFields() && !this.discovering)
        .onClick((): void => { if (this.canChangeModelFields() && !this.discovering) { this.onAddModel(); } })
    } else {
      Button('加一个模型')
        .key('desktopPiAiProviderModelAdd').width('100%').enabled(this.canChangeModelFields() && !this.discovering)
        .backgroundColor($r('sys.color.background_secondary')).fontColor($r('sys.color.font_primary'))
        .onClick((): void => { this.onAddModel(); })
    }
  }

  private canTypeExistingKey(): boolean { return !this.locked && !this.busy && !this.existingKeyClearApplied; }

  private savedKeyCanClear(): boolean {
    return this.existingKeyCanClear && !this.existingKeyClearPending && !this.existingKeyClearApplied && this.keyDraft === '';
  }

  private clearExistingKey(): boolean {
    if (!this.canTypeExistingKey() || !this.savedKeyCanClear()) { return false; }
    this.onExistingKeyClear();
    return true;
  }

  private existingKeyPlaceholder(): ResourceStr {
    if (this.keyPlaceholder !== '') { return this.keyPlaceholder; }
    return this.keyRef ? $r('app.string.desktop_model_provider_editor_key_fallback', this.keyRef) :
      $r('app.string.desktop_model_provider_editor_key_placeholder');
  }

  @Builder
  private ExistingKeyField() {
    Column({ space: 6 }) {
      Text($r('app.string.desktop_model_provider_editor_key')).fontSize(12).width('100%')
        .fontColor($r('sys.color.font_secondary'))
      TextInput({ text: this.keyDraft, placeholder: this.existingKeyPlaceholder() })
        .key('desktopPiAiProviderKey').width('100%').height(Sz.TOUCH_MIN).fontSize(Fs.SECONDARY)
        .type(InputType.Password).showPasswordIcon(this.keyDraft.length > 0)
        .accessibilityText($r('app.string.desktop_model_provider_editor_key')).enabled(this.canTypeExistingKey())
        .onChange((value: string): void => {
          if (this.canTypeExistingKey() && value !== this.keyDraft) { this.onKeyChange(value); }
        })
        .onKeyPreIme((event: KeyEvent): boolean => {
          if (event.type === KeyType.Down &&
            (event.keyCode === KeyCode.KEYCODE_DEL || event.keyCode === KeyCode.KEYCODE_FORWARD_DEL) &&
            this.clearExistingKey()) {
            event.stopPropagation();
            return true;
          }
          return false;
        })
      if (this.savedKeyCanClear()) {
        Button($r('app.string.desktop_model_provider_editor_key_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .key('desktopPiAiProviderKeyClear').height(28).fontSize(12).enabled(this.canTypeExistingKey())
          .onClick((): void => { this.clearExistingKey(); })
      }
      if (this.existingKeyClearPending || this.existingKeyClearApplied) {
        Text(this.existingKeyClearApplied ? $r('app.string.desktop_model_provider_editor_key_clear_applied') :
          this.keyRef ? $r('app.string.desktop_model_provider_editor_key_clear_env', this.keyRef) :
          $r('app.string.desktop_model_provider_editor_key_clear_pending')).fontSize(12).width('100%')
          .fontColor($r('sys.color.font_secondary'))
      } else if (this.keyConfigured && this.keyDraft.length === 0) {
        Text($r('app.string.desktop_model_provider_editor_key_saved')).fontSize(12).width('100%')
          .fontColor($r('sys.color.font_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 密钥（官方 `keyInput`：只写不读） */
  @Builder
  keyField() {
    Text(this.keyRef.length > 0 ? `API 密钥（存入 ${this.keyRef}）` : 'API 密钥')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
    TextInput({
      text: this.keyDraft,
      placeholder: this.keyPlaceholder !== '' ? this.keyPlaceholder : this.keyConfigured ? '已配置；留空表示不改动' : '粘贴密钥'
    })
      .key('desktopPiAiProviderKey')
      .fontSize(Fs.SECONDARY)
      .type(InputType.Password)
      .height(Sz.TOUCH_MIN)
      .width('100%')
      .enabled(!this.locked && !this.busy)
      .onChange((v: string) => {
        this.onKeyChange(v);
      })
    if (!this.inline) {
      Text('明文只在这一个请求里存在，本机既不留存也不显示（只能覆盖，读不回）。留空表示保留 Host 上已有的那把。')
        .fontSize(Fs.CAPTION).fontColor($r('sys.color.font_tertiary')).width('100%')
    }
  }
}
