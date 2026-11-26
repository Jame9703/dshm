import { Speaker, TrajectoryItem } from 'appstate';
import { KeyCode } from '@kit.InputKit';
import type { ModelOption, ModelSelection, PendingAttachment } from 'appstate';
import type { DesktopConversationSnapshot, DesktopPermissionOption, DesktopTranscriptItem } from './DesktopConversation';
import { DesktopInteractionPane } from './DesktopInteractionPane';
import type { DesktopInteraction, DesktopQuestionAnswer } from './DesktopInteractions';
import type { DesktopPlanDocument } from './DesktopPlan';
import { MarkdownRenderer } from '../view/MarkdownRenderer';
import { DesktopArtifactsPane } from './DesktopArtifactsPane';
import { DesktopChangeTarget } from './DesktopArtifacts';
import { DesktopHostActions } from './DesktopHostActions';
import { DesktopJobsControl } from './DesktopJobsControl';
import { DesktopProcessPane } from './DesktopProcessPane';
import { DesktopCommandPalette, DesktopPaletteRow } from './DesktopCommandPalette';
import { activeDesktopSlash, commandCandidates, commandInvocation, resolveDesktopCommand } from './DesktopCommands';
import type { DesktopCommand, DesktopCommandRecord, DesktopSlashToken } from './DesktopCommands';
import { desktopMenuOptions } from './DesktopMenuOptions';
import { DesktopGoalBar } from './DesktopGoalBar';
import { DesktopGoalAction, DesktopGoalRef } from './DesktopGoal';

@Component
export struct DesktopConversationPane {
  host?: DesktopHostActions;
  @Prop @Watch('onSnapshotChanged') snapshot: DesktopConversationSnapshot | undefined = undefined;
  @Prop title: ResourceStr = '';
  @Prop workspaceTitle: ResourceStr = '';
  @Prop draft: string = '';
  @Prop interactions: DesktopInteraction[] = [];
  @Prop attachments: PendingAttachment[] = [];
  @Prop busy: boolean = false;
  @Prop terminalOpen: boolean = false;
  @Prop filesOpen: boolean = false;
  @Prop commandError: string = '';
  @Prop menuOptions: MenuOptions | undefined = undefined;
  @Prop copyingTranscript: boolean = false;
  @Prop exportingLog: boolean = false;
  onDraft: (value: string) => void = () => {};
  onAddAttachment: () => void = () => {};
  onRemoveAttachment: (receiptId: string) => void = () => {};
  onSend: () => void = () => {};
  onLoadModels: () => void = () => {};
  onModelsSettings: () => void = () => {};
  onLoadCommands: () => void = () => {};
  onCommand: (name: string) => Promise<string> = (_name: string): Promise<string> => Promise.resolve('');
  onSlashModel: (selection: ModelSelection) => Promise<string> =
    (_selection: ModelSelection): Promise<string> => Promise.resolve('');
  onSlashPermission: (preset: string) => Promise<string> = (_preset: string): Promise<string> => Promise.resolve('');
  onStop: () => void = () => {};
  onEarlier: () => void = () => {};
  onWeb: () => void = () => {};
  onCopyTranscript: () => void = () => {};
  onExportLog: () => void = () => {};
  onTerminal: () => void = () => {};
  onFiles: () => void = () => {};
  onModel: (selection: ModelSelection) => void = () => {};
  onPermission: (preset: string) => void = () => {};
  onDecision: (id: string, allow: boolean) => void = (_id: string, _allow: boolean): void => {};
  onAnswer: (id: string, answers: DesktopQuestionAnswer[]) => void =
    (_id: string, _answers: DesktopQuestionAnswer[]): void => {};
  onPlanMode: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onGoalAction: (action: DesktopGoalAction, ref: DesktopGoalRef, objective: string) => Promise<string> =
    (_action: DesktopGoalAction, _ref: DesktopGoalRef, _objective: string): Promise<string> => Promise.resolve('');
  onPlanPreview: (plan: DesktopPlanDocument) => void = (_plan: DesktopPlanDocument): void => {};
  onPlanDecision: (id: string, approve: boolean) => void = (_id: string, _approve: boolean): void => {};
  onPlanResume: (id: string) => void = (_id: string): void => {};
  onArtifactFile: (path: string, name: string) => void = (_path: string, _name: string): void => {};
  onArtifactAction: (path: string, name: string, reveal: boolean) => void =
    (_path: string, _name: string, _reveal: boolean): void => {};
  onChanges: (target: DesktopChangeTarget) => void = (_target: DesktopChangeTarget): void => {};

  private readonly scroller: Scroller = new Scroller();
  private following: boolean = true;
  private sessionId: string = '';
  private messageCount: number = 0;
  private partial: string = '';
  private scrollTimer: number = -1;
  @State private expandedProcesses: string[] = [];
  @State private expandedReasoning: string[] = [];
  @State private inspectedTool: string = '';
  private readonly composer: TextAreaController = new TextAreaController();
  private readonly paletteScroller: Scroller = new Scroller();
  private slashFrame: number = -1;
  private slashToken?: DesktopSlashToken;
  private paletteDraft: string = '';
  private dismissedDraft?: string;
  @State private palette: string = '';
  @State private query: string = '';
  @State private leading: boolean = true;
  @State private paletteFilter: string = '';
  @State private highlight: number = 0;
  @State private riskPreset: string = '';
  @State private agreed: boolean = false;
  @State private paletteNotice: string = '';

  aboutToDisappear(): void {
    this.cancelSlashRefresh();
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  private onSnapshotChanged(): void {
    const id = this.snapshot?.sessionId ?? '';
    const count = this.snapshot?.transcript.length ?? 0;
    const partial = this.snapshot?.partial ?? '';
    if (id !== this.sessionId) {
      this.sessionId = id;
      this.following = true;
      this.expandedProcesses = [];
      this.expandedReasoning = [];
      this.inspectedTool = '';
      this.dismissedDraft = undefined;
      this.closePalette();
    } else if (count === this.messageCount && partial === this.partial) {
      return;
    }
    this.messageCount = count;
    this.partial = partial;
    if (this.following && this.scrollTimer === -1) {
      this.scrollTimer = setTimeout((): void => {
        this.scrollTimer = -1;
        if (this.following && this.snapshot?.sessionId === this.sessionId) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 30);
    }
  }

  private closePalette(): void {
    this.cancelSlashRefresh();
    this.palette = '';
    this.slashToken = undefined;
    this.riskPreset = '';
    this.agreed = false;
  }

  private cancelSlashRefresh(): void {
    if (this.slashFrame !== -1) { clearTimeout(this.slashFrame); this.slashFrame = -1; }
  }

  private refreshSlash(): void {
    if (this.slashFrame !== -1 || this.palette === 'model' || this.palette === 'permission') { return; }
    // ArkUI may report selection before updating the bound draft in the current input frame.
    this.slashFrame = setTimeout((): void => {
      this.slashFrame = -1;
      this.detectSlash(this.draft, this.composer.getCaretOffset().index);
    }, 16);
  }

  private detectSlash(text: string, caret: number): void {
    if (this.palette === 'model' || this.palette === 'permission') { return; }
    if (text === this.dismissedDraft || this.busy || this.snapshot?.loading !== false) {
      this.closePalette();
      return;
    }
    const token = activeDesktopSlash(text, caret);
    if (token === undefined) { this.closePalette(); return; }
    const refresh = this.palette !== 'commands' || this.query !== token.query || this.leading !== token.leading;
    this.slashToken = token;
    this.paletteDraft = text;
    this.query = token.query;
    this.leading = token.leading;
    if (refresh) { this.highlight = 0; }
    this.palette = 'commands';
    if (!this.snapshot.commands && !this.snapshot.commandLoading && !this.snapshot.commandError) {
      this.onLoadCommands();
    }
  }

  private paletteCommands(): DesktopCommand[] {
    return commandCandidates(this.snapshot?.commands ?? [], this.query, this.leading);
  }

  private modelKey(option: ModelOption): string {
    return JSON.stringify([option.provider, option.modelId]);
  }

  private paletteRows(): DesktopPaletteRow[] {
    if (this.palette === 'commands') {
      return this.paletteCommands().map((row: DesktopCommand): DesktopPaletteRow => {
        return { id: row.name, title: row.label, detail: row.description, token: `/${row.alias}`,
          section: ['file', 'goal', 'plan', 'feedback'].includes(row.kind) ? '添加' : '指令' };
      });
    }
    const needle = this.paletteFilter.trim().toLowerCase();
    if (this.palette === 'model') {
      return (this.snapshot?.models ?? []).filter((row: ModelOption): boolean =>
        `${row.modelName} ${row.providerName} ${row.modelId}`.toLowerCase().includes(needle))
        .map((row: ModelOption): DesktopPaletteRow => {
          const current = this.snapshot?.selection;
          return { id: this.modelKey(row), title: row.modelName, detail: row.providerName, section: '',
            token: current?.provider === row.provider && current?.modelId === row.modelId ? '✓' : '' };
        });
    }
    return (this.snapshot?.permissions ?? []).filter((row: DesktopPermissionOption): boolean =>
      `${row.title} ${row.detail} ${row.value}`.toLowerCase().includes(needle))
      .map((row: DesktopPermissionOption): DesktopPaletteRow => ({ id: row.value, title: row.title, detail: row.detail,
        section: '', token: this.snapshot?.permission === row.value ? '✓' : '' }));
  }

  private replaceSlash(original: string, token: DesktopSlashToken, replacement: string): void {
    if (this.draft !== original) { return; }
    const text = original.slice(0, token.start) + replacement + original.slice(token.end);
    this.dismissedDraft = text;
    this.onDraft(text);
    const session = this.sessionId;
    this.getUIContext().getFocusController().requestFocus('desktopSlashComposer');
    setTimeout((): void => {
      if (session === this.sessionId && text === this.draft) {
        this.composer.caretPosition(token.start + replacement.length);
      }
    }, 0);
  }

  private openChoice(kind: string): void {
    this.paletteFilter = '';
    this.highlight = 0;
    this.riskPreset = '';
    this.agreed = false;
    this.palette = kind;
    if (kind === 'model') { this.onLoadModels(); }
  }

  private async pickPalette(id: string): Promise<void> {
    const token = this.slashToken;
    const original = this.paletteDraft;
    if (token === undefined || original !== this.draft || this.busy) { return; }
    const session = this.sessionId;
    const view = this.palette;
    let problem = '';
    if (view === 'commands') {
      const row = this.paletteCommands().find((item: DesktopCommand): boolean => item.name === id);
      if (row === undefined) { return; }
      if (row.kind === 'file') {
        this.closePalette();
        this.replaceSlash(original, token, '');
        this.onAddAttachment();
        return;
      }
      if (row.kind === 'model' || (row.kind === 'permission' && (this.snapshot?.permissions.length ?? 0) > 0)) {
        this.openChoice(row.kind);
        return;
      }
      this.closePalette();
      if (row.hint !== undefined) {
        this.replaceSlash(original, token, `/${row.alias} `);
        return;
      }
      this.following = true;
      problem = await this.onCommand(row.name);
    } else if (view === 'model') {
      const option = this.snapshot?.models.find((row: ModelOption): boolean => this.modelKey(row) === id);
      if (option === undefined) { return; }
      this.closePalette();
      problem = await this.onSlashModel({ provider: option.provider, modelId: option.modelId,
        effort: option.defaultEffort });
    } else if (view === 'permission') {
      const preset = this.riskPreset || id;
      if (id === 'confirm' && (!this.riskPreset || !this.agreed)) { return; }
      if (id !== 'confirm' && this.snapshot?.permission !== preset &&
        (preset === 'danger-full-access' || preset === 'auto')) {
        this.riskPreset = preset;
        this.agreed = false;
        return;
      }
      this.closePalette();
      problem = await this.onSlashPermission(preset);
    }
    if (session === this.sessionId && !problem) { this.replaceSlash(original, token, ''); }
  }

  private handleSend(): void {
    if (this.busy || this.snapshot?.loading !== false) { return; }
    const command = commandInvocation(this.draft);
    if (command !== undefined && !command.suffix) {
      const choices = commandCandidates(this.snapshot.commands ?? [], '', true);
      const row = resolveDesktopCommand(choices, command.token);
      if (row?.kind === 'file' || row?.kind === 'model' ||
        (row?.kind === 'permission' && this.snapshot.permissions.length > 0)) {
        if (row.kind !== 'file' && this.attachments.length > 0) {
          this.paletteNotice = `/${command.token} 不接受附件，请先移除附件`;
          return;
        }
        this.slashToken = activeDesktopSlash(this.draft, this.draft.trimEnd().length);
        this.paletteDraft = this.draft;
        this.query = command.token;
        this.leading = true;
        this.palette = 'commands';
        this.pickPalette(row.name);
        return;
      }
    }
    this.dismissedDraft = this.draft;
    this.closePalette();
    this.following = true;
    this.onSend();
  }

  private paletteKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    if (this.palette && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (this.riskPreset) { this.riskPreset = ''; this.agreed = false; }
      else { this.dismissedDraft = this.draft; this.closePalette(); }
      return true;
    }
    if (this.riskPreset) { return false; }
    const rows = this.palette ? this.paletteRows() : [];
    const up = event.keyCode === KeyCode.KEYCODE_DPAD_UP;
    if (rows.length > 0 && (up || event.keyCode === KeyCode.KEYCODE_DPAD_DOWN)) {
      this.highlight = (this.highlight + (up ? -1 : 1) + rows.length) % rows.length;
      this.paletteScroller.scrollToIndex(this.highlight, false, ScrollAlign.AUTO);
      return true;
    }
    if (event.keyCode !== KeyCode.KEYCODE_ENTER || event.getModifierKeyState?.(['Shift']) || this.snapshot?.running) {
      return false;
    }
    const item = rows[this.highlight] ?? rows[0];
    if (item !== undefined) { this.pickPalette(item.id); }
    else { this.handleSend(); }
    return true;
  }

  @Builder
  private CommandPopup() {
    DesktopCommandPalette({ rows: this.paletteRows(), viewMode: this.palette, filter: this.paletteFilter,
      highlight: this.highlight, scroller: this.paletteScroller, agreed: this.agreed,
      riskName: this.snapshot?.permissions.find((row: DesktopPermissionOption): boolean =>
        row.value === this.riskPreset)?.title ?? '', loading: this.palette === 'commands' ?
        this.snapshot?.commandLoading === true : (this.palette === 'model' && this.snapshot?.modelsLoading === true),
      error: this.palette === 'commands' ? this.snapshot?.commandError ?? '' : '',
      onPick: (id: string): void => { this.pickPalette(id); },
      onAgree: (value: boolean): void => { this.agreed = value; },
      onFilter: (value: string): void => { this.paletteFilter = value; this.highlight = 0; },
      onRetry: (): void => { this.onLoadCommands(); },
      onModelsSettings: (): void => { this.closePalette(); this.onModelsSettings(); },
      onBack: (): void => { this.riskPreset = ''; this.agreed = false; },
      onKey: (event: KeyEvent): boolean => this.paletteKey(event) })
  }

  @Builder
  private CommandCard(row: DesktopCommandRecord) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(`/${row.name}${row.args.trim() ? ' ' + row.args.trimStart() : ''}`).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1).copyOption(CopyOptions.LocalDevice)
        Text(row.completed < 0 ? '执行中' : (row.outcome === 'success' ? '完成' : '失败'))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.width('100%')
      if (row.text) { MarkdownRenderer({ text: row.text }) }
    }.width('100%').constraintSize({ maxWidth: 712 }).alignItems(HorizontalAlign.Start).padding(12)
      .borderRadius(12).backgroundColor($r('app.color.workspace_panel'))
  }

  private visibleInteraction(): DesktopInteraction[] {
    const visible = this.interactions.filter((row: DesktopInteraction): boolean => !row.reviewHidden);
    const row = visible.find((item: DesktopInteraction): boolean => item.planReview !== undefined) ?? visible[0];
    return row === undefined ? [] : [row];
  }

  @Builder
  private PlanCard(plan: DesktopPlanDocument) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(20).fontColor([$r('sys.color.font_secondary')])
        Column({ space: 3 }) {
          Text(plan.title).fontSize(15).fontColor($r('sys.color.font_primary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('计划文档').fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('打开').fontSize(13).fontColor($r('sys.color.brand'))
      }.width('100%')
    }
    .width('100%').constraintSize({ maxWidth: 712 }).padding(12).borderRadius(12)
    .backgroundColor($r('app.color.workspace_panel')).onClick((): void => { this.onPlanPreview(plan); })
  }

  private modelMenu(): Array<MenuElement> {
    if ((this.snapshot?.models.length ?? 0) === 0) {
      return [{ value: $r('app.string.desktop_chat_model_settings'), action: this.onModelsSettings }];
    }
    return (this.snapshot?.models ?? []).map((option: ModelOption): MenuElement => {
      return {
        value: option.modelName + ' · ' + option.providerName,
        action: (): void => this.onModel({
          provider: option.provider, modelId: option.modelId, effort: option.defaultEffort
        })
      };
    });
  }

  private sessionMenu(): MenuElement[] {
    return [
      { value: '复制会话为 Markdown', icon: $r('app.media.dsh_session_copy'),
        enabled: !this.copyingTranscript, action: this.onCopyTranscript },
      { value: '下载 Session 日志', icon: $r('app.media.dsh_session_download'),
        enabled: !this.exportingLog && !this.busy, action: this.onExportLog }
    ];
  }

  private effortMenu(): Array<MenuElement> {
    const selection = this.snapshot?.selection;
    if (selection === undefined) {
      return [];
    }
    const option = this.snapshot?.models.find((item: ModelOption): boolean =>
      item.provider === selection.provider && item.modelId === selection.modelId);
    return (option?.efforts ?? []).map((effort: string): MenuElement => {
      return {
        value: effort,
        action: (): void => this.onModel({
          provider: selection.provider, modelId: selection.modelId, effort: effort
        })
      };
    });
  }

  @Builder
  private Message(item: TrajectoryItem) {
    Column() {
      if (item.speaker === Speaker.USER) {
        Text(item.body)
          .fontSize(15).fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .constraintSize({ maxWidth: '82%' }).borderRadius(16)
          .backgroundColor($r('app.color.workspace_panel'))
      } else {
        if (item.reasoning) {
          Button(this.expandedReasoning.includes(item.id) ? '收起思考过程' : '思考过程',
            { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(30).onClick((): void => {
              this.expandedReasoning = this.expandedReasoning.includes(item.id) ?
                this.expandedReasoning.filter((id: string): boolean => id !== item.id) : [...this.expandedReasoning, item.id];
            })
          if (this.expandedReasoning.includes(item.id)) {
            MarkdownRenderer({ text: item.reasoning })
          }
        }
        if (item.body) { MarkdownRenderer({ text: item.body }) }
      }
    }
    .width('100%').constraintSize({ maxWidth: 712 })
    .alignItems(item.speaker === Speaker.USER ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  @Builder
  private ModelChip(effort: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 5 }) {
        Text(effort ? this.snapshot?.selection?.effort || $r('app.string.desktop_chat_effort') :
          this.snapshot?.modelLabel || $r('app.string.desktop_chat_select_model'))
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10)
          .fontColor([$r('sys.color.font_tertiary')]).rotate({ angle: 90 })
      }
    }
    .height(32).padding({ left: 8, right: 8 }).constraintSize({ maxWidth: effort ? 95 : 160 })
    .borderRadius(8).backgroundColor(Color.Transparent).focusOnTouch(false)
    .enabled(!this.busy).bindMenu(effort ? this.effortMenu() : this.modelMenu(), this.menuOptions)
  }

  @Builder
  private ComposerControls() {
    Scroll() {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.paperclip')).fontSize(16)
        }
        .width(32).height(32).focusOnTouch(false)
        .enabled(!this.busy && this.snapshot?.loading === false)
        .accessibilityText('添加附件').onClick(this.onAddAttachment)
        if (this.snapshot?.planMode !== undefined) {
          Button(this.snapshot?.planMode ? '计划模式 ×' : '计划模式', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(31).borderRadius(8).focusOnTouch(false).enabled(!this.busy)
            .accessibilitySelected(this.snapshot?.planMode === true)
            .onClick((): void => { this.onPlanMode(this.snapshot?.planMode !== true); })
        }
        if ((this.snapshot?.permissions.length ?? 0) > 0) {
          Button(this.snapshot?.permissions.find((row: DesktopPermissionOption): boolean =>
            row.value === this.snapshot?.permission)?.title || '访问模式', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(31).borderRadius(8).enabled(!this.busy).focusOnTouch(false)
            .bindMenu(this.snapshot?.permissions.map((row: DesktopPermissionOption): MenuElement => {
              return { value: (row.value === this.snapshot?.permission ? '✓ ' : '') + row.title,
                action: (): void => { this.onPermission(row.value); } };
            }) ?? [], this.menuOptions)
        }
        this.ModelChip(false)
        if (this.effortMenu().length > 0) {
          this.ModelChip(true)
        }
      }
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
    .layoutWeight(1).height(36)
  }

  @Builder
  private Composer() {
    Column({ space: 6 }) {
      if (this.attachments.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.attachments, (item: PendingAttachment, index: number) => {
              Button(item.name + ' ×', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .enabled(!this.busy).accessibilityText('移除附件 ' + item.name)
                .onClick((): void => { this.onRemoveAttachment(item.receiptId); })
            }, (item: PendingAttachment, index: number): string => item.receiptId + index)
          }
        }
        .scrollable(ScrollDirection.Horizontal).width('100%').padding({ left: 8, right: 8 })
      }
      TextArea({ text: this.draft, controller: this.composer, placeholder: this.snapshot?.planMode === true ?
        '描述你的任务以生成计划' : $r('app.string.desktop_chat_placeholder') })
        .key('desktopSlashComposer').enterKeyType(EnterKeyType.Send)
        .width('100%').height(66).fontSize(15).borderRadius(16).padding({ left: 12, right: 12, top: 10 })
        .fontColor($r('sys.color.font_primary')).backgroundColor(Color.Transparent)
        .onChange((text: string): void => {
          this.paletteNotice = '';
          this.onDraft(text);
          if (text !== this.dismissedDraft) { this.dismissedDraft = undefined; }
          this.refreshSlash();
        })
        .onTextSelectionChange((start: number, end: number): void => {
          if (start === end) { this.refreshSlash(); }
        })
        .onKeyPreIme((event: KeyEvent): boolean => this.paletteKey(event))
        .onSubmit((): void => { if (!this.snapshot?.running) { this.handleSend(); } })
        .bindPopup(this.palette !== '', { builder: this.CommandPopup(), placement: Placement.TopLeft,
          enableArrow: false, mask: false, focusable: this.palette !== 'commands',
          systemMaterial: desktopMenuOptions(Placement.TopLeft).systemMaterial,
          onStateChange: (event): void => {
            if (!event.isVisible && this.palette) { this.dismissedDraft = this.draft; this.closePalette(); }
          } })
      Row({ space: 4 }) {
        this.ComposerControls()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.snapshot?.running ? $r('sys.symbol.xmark') : $r('sys.symbol.arrow_up'))
            .fontSize(17).fontColor([Color.White])
        }
        .key('desktopComposerSubmit').width(34).height(34)
        .backgroundColor($r('sys.color.brand')).focusOnTouch(false)
        .accessibilityText(this.snapshot?.running ? $r('app.string.desktop_chat_stop') :
          $r('app.string.desktop_chat_send'))
        .enabled(!this.busy && (this.snapshot?.running === true ||
          ((this.draft.trim().length > 0 || this.attachments.length > 0) &&
            this.snapshot?.loading === false)))
        .onClick((): void => {
          if (this.snapshot?.running) {
            this.onStop();
          } else {
            this.handleSend();
          }
        })
      }
      .width('100%').padding({ left: 8, right: 8, bottom: 7 })
    }
    .width('100%').constraintSize({ maxWidth: 712 })
    .borderRadius(20).backgroundColor($r('app.color.workspace_panel'))
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.workspaceTitle !== '') {
            Text(this.workspaceTitle).fontSize(12).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.snapshot?.sessionId) {
          DesktopJobsControl({ host: this.host, sessionId: this.snapshot?.sessionId ?? '' })
        }
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(18).fontColor([$r('sys.color.font_primary')])
        }
          .key('desktopWorkspaceFiles').width(34).height(34).padding(0).focusOnTouch(false)
          .accessibilityText('工作区文件').accessibilitySelected(this.filesOpen).onClick(this.onFiles)
        Button('终端', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(34).focusOnTouch(false)
          .accessibilitySelected(this.terminalOpen)
          .onClick(this.onTerminal)
        Button($r('app.string.desktop_experiment_open_web'),
          { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(34).focusOnTouch(false).onClick(this.onWeb)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_session_ellipsis')).width(18).height(18).supportSvg2(true).draggable(false)
            .accessibilityLevel('no')
        }.key('desktopSessionMore').width(34).height(34).padding(0).focusOnTouch(false)
          .accessibilityText('会话菜单').enabled(this.snapshot?.loading === false)
          .bindMenu(this.sessionMenu(), desktopMenuOptions(Placement.BottomRight))
      }
      .width('100%').height(50).padding({ left: 20, right: 16 })
      if (this.snapshot?.loading) {
        LoadingProgress().width(22).height(22).color($r('sys.color.brand'))
      }
      if (this.snapshot?.hasEarlier) {
        Button($r('app.string.desktop_chat_earlier'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick((): void => {
            this.following = false;
            this.onEarlier();
          })
      }
      List({ space: 16, scroller: this.scroller }) {
        ForEach(this.snapshot?.transcript ?? [], (item: DesktopTranscriptItem): void => {
          ListItem() {
            Row() {
              if (item.plan !== undefined) {
                this.PlanCard(item.plan)
              } else if (item.command !== undefined) {
                this.CommandCard(item.command)
              } else if (item.message !== undefined) {
                this.Message(item.message)
              } else if (item.artifacts !== undefined) {
                DesktopArtifactsPane({ host: this.host, sessionId: this.snapshot?.sessionId ?? '',
                  artifacts: item.artifacts, onFile: this.onArtifactFile, onFileAction: this.onArtifactAction,
                  onReview: this.onChanges })
              } else if (item.process !== undefined) {
                DesktopProcessPane({ group: item.process, expanded: this.expandedProcesses.includes(item.id),
                  inspected: this.inspectedTool, onFile: this.onArtifactFile,
                  onToggle: (): void => {
                    this.expandedProcesses = this.expandedProcesses.includes(item.id) ?
                      this.expandedProcesses.filter((id: string): boolean => id !== item.id) : [...this.expandedProcesses, item.id];
                  },
                  onInspect: (id: string): void => { this.inspectedTool = this.inspectedTool === id ? '' : id; } })
              }
            }
            .width('100%').justifyContent(FlexAlign.Center)
          }
        }, (item: DesktopTranscriptItem): string => item.id + (item.process?.version ?? '') + (item.command?.completed ?? ''))
        if ((this.snapshot?.partial.length ?? 0) > 0) {
          ListItem() {
            Row() {
              Text(this.snapshot?.partial ?? '').fontSize(15).fontColor($r('sys.color.font_primary'))
                .width('100%').constraintSize({ maxWidth: 712 })
            }
            .width('100%').justifyContent(FlexAlign.Center)
          }
        }
        if (this.snapshot?.preparingTool) {
          ListItem() {
            Row({ space: 7 }) {
              LoadingProgress().width(16).height(16)
              Text(`正在准备 ${this.snapshot?.preparingTool ?? ''}`).fontSize(13)
            }.width('100%').constraintSize({ maxWidth: 712 }).padding({ left: 7 })
          }
        }
      }
      .layoutWeight(1).width('100%').padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .scrollBar(BarState.Auto)
      .onScrollIndex((_first: number, last: number): void => {
        this.following = last >= this.messageCount - 1;
      })
      if (this.visibleInteraction().length > 0) {
        Row() {
          ForEach(this.visibleInteraction(), (row: DesktopInteraction) => {
            DesktopInteractionPane({
              request: row, busy: this.busy, onDecision: this.onDecision, onAnswer: this.onAnswer,
              onPlanDecision: this.onPlanDecision, onPlanPreview: this.onPlanPreview
            })
          }, (row: DesktopInteraction): string => row.id)
        }
        .width('100%').padding({ left: 20, right: 20, bottom: 8 }).justifyContent(FlexAlign.Center)
      } else if (this.interactions.some((row: DesktopInteraction): boolean => row.reviewHidden === true)) {
        Button('继续审阅计划', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => {
          const review = this.interactions.find((row: DesktopInteraction): boolean => row.reviewHidden === true);
          if (review !== undefined) {
            this.onPlanResume(review.id);
          }
        })
      } else if (this.snapshot?.waitingForInput) {
        Text('正在读取待处理请求…').fontSize(13).fontColor($r('sys.color.font_secondary')).padding(8)
      }
      if (this.paletteNotice || this.commandError || this.snapshot?.error) {
        Text(this.paletteNotice || this.commandError || this.snapshot?.error || '')
          .fontSize(13).fontColor($r('sys.color.warning'))
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 16, right: 16, bottom: 6 })
      }
      Column({ space: 6 }) {
        if (this.snapshot?.goal !== undefined && this.snapshot.goal.phase !== 'complete') {
          DesktopGoalBar({ goal: this.snapshot.goal, busy: this.busy, onAction: this.onGoalAction })
        }
        this.Composer()
      }.width('100%').padding({ left: 20, right: 20, bottom: 16 }).alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
  }
}
