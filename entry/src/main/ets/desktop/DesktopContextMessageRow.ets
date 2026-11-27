import type { DesktopContextMessage, DesktopContextToolMutations } from './DesktopContextMessageModel';
import {
  DESKTOP_CONTEXT_MAX_CHARS, DesktopContextBodyData, DesktopContextCatalogEntry, DesktopContextField,
  DesktopContextInstruction, DesktopContextRecall, DesktopContextSnapshotSection, DesktopContextTextRun,
  desktopContextBodyData, desktopContextJsonText, desktopContextNoticeSummary
} from './DesktopContextMessageContent';

@Component
struct DesktopContextBoundedText {
  @Prop text: string = '';
  @Prop textSize: number = 11;
  @Prop family: string = 'monospace';

  build() {
    Column() {
      Text(this.text.slice(0, DESKTOP_CONTEXT_MAX_CHARS)).width('100%')
        .fontSize(this.textSize).fontFamily(this.family).fontColor($r('sys.color.font_secondary'))
        .wordBreak(WordBreak.BREAK_ALL).copyOption(CopyOptions.LocalDevice)
      if (this.text.length > DESKTOP_CONTEXT_MAX_CHARS) {
        Text($r('app.string.desktop_context_truncated', String(this.text.length))).width('100%')
          .fontSize(this.textSize).fontFamily(this.family).fontColor($r('sys.color.font_tertiary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
struct DesktopContextUnknownBlock {
  @Prop nodeKey: string = '';
  @Prop block: Object | undefined = undefined;
  @Prop codeSize: number = 11;
  @Prop codeFamily: string = 'monospace';
  @State private open: boolean = false;
  @State private text: string = '';

  private toggle(): void {
    if (!this.open) { this.text = desktopContextJsonText(this.block, true); }
    this.open = !this.open;
  }

  build() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 5 }) {
          Text(this.open ? '▾' : '▸').fontSize(this.codeSize).accessibilityLevel('no')
          Text($r('app.string.desktop_context_unknown_block')).fontSize(this.codeSize).fontFamily(this.codeFamily)
            .fontColor($r('sys.color.font_tertiary')).maxLines(1)
        }
      }.key(this.nodeKey).height(this.codeSize + 9).padding(0).borderRadius(5)
        .focusOnTouch(false).accessibilityGroup(true).accessibilitySelected(this.open)
        .onClick((): void => { this.toggle(); })
      if (this.open) {
        DesktopContextBoundedText({ text: this.text, textSize: this.codeSize, family: this.codeFamily })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

function instructionLabel(action: string): Resource {
  if (action === 'loaded') { return $r('app.string.desktop_context_instruction_loaded'); }
  if (action === 'added') { return $r('app.string.desktop_context_instruction_added'); }
  if (action === 'updated') { return $r('app.string.desktop_context_instruction_updated'); }
  return $r('app.string.desktop_context_instruction_removed');
}

@Component
export struct DesktopContextMessageBody {
  @Prop @Watch('prepare') row: DesktopContextMessage;
  @Prop @Watch('prepare') forceNotice: boolean = false;
  @Prop codeSize: number = 11;
  @Prop codeFamily: string = 'monospace';

  @State private body: DesktopContextBodyData = { runs: [], fields: [] };

  aboutToAppear(): void {
    this.prepare();
  }

  private prepare(): void {
    this.body = desktopContextBodyData(this.row, this.forceNotice);
  }

  @Builder
  private Caption(text: Resource) {
    Text(text).fontSize(this.codeSize).fontFamily(this.codeFamily)
      .fontColor($r('sys.color.font_tertiary')).width('100%')
  }

  @Builder
  private ModelFacing() {
    ForEach(this.body.runs, (run: DesktopContextTextRun): void => {
      if (run.unknown) {
        DesktopContextUnknownBlock({ nodeKey: 'desktopContextUnknown-' + this.row.id + '-' + run.key,
          block: run.block, codeSize: this.codeSize, codeFamily: this.codeFamily })
      } else {
        DesktopContextBoundedText({ text: run.text, textSize: this.codeSize, family: this.codeFamily })
      }
    }, (run: DesktopContextTextRun): string => run.key)
  }

  @Builder
  private ToolMutations(mutations: DesktopContextToolMutations) {
    if (mutations.added.length > 0) {
      this.Caption($r('app.string.desktop_context_tools_added', mutations.added.join(', ')))
    }
    if (mutations.removed.length > 0) {
      this.Caption($r('app.string.desktop_context_tools_removed', mutations.removed.join(', ')))
    }
  }

  @Builder
  private StructuredContent() {
    if (this.body.instructions !== undefined) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.body.instructions, (file: DesktopContextInstruction): void => {
          Row({ space: 6 }) {
            Text(file.path).fontSize(this.codeSize).fontFamily(this.codeFamily)
              .fontColor($r('sys.color.font_secondary')).wordBreak(WordBreak.BREAK_ALL)
            Text(instructionLabel(file.action)).fontSize(this.codeSize).fontFamily(this.codeFamily)
              .fontColor($r('sys.color.font_tertiary'))
          }.margin({ bottom: 4, right: 12 }).constraintSize({ maxWidth: '100%' })
            .accessibilityDescription(file.digest ?? '')
        }, (file: DesktopContextInstruction): string => file.path)
      }.width('100%').margin({ bottom: 4 })
    }
    if (this.body.catalog !== undefined) {
      if (this.body.catalog.replacement) { this.Caption($r('app.string.desktop_context_catalog_replaced')) }
      ForEach(this.body.catalog.featured, (entry: DesktopContextCatalogEntry): void => {
        Row({ space: 8 }) {
          Text(entry.name).fontSize(this.codeSize).fontFamily(this.codeFamily).maxLines(1)
            .fontColor($r('sys.color.font_secondary'))
          Text(entry.description).fontSize(this.codeSize).fontFamily(this.codeFamily).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).fontColor($r('sys.color.font_tertiary'))
        }.width('100%')
      }, (_entry: DesktopContextCatalogEntry, index: number): string => String(index))
      if (this.body.catalog.remaining > 0) {
        this.Caption($r('app.string.desktop_context_catalog_more', String(this.body.catalog.remaining)))
      }
    }
    if (this.body.sections !== undefined) {
      this.Caption($r('app.string.desktop_context_snapshot_supersedes'))
      ForEach(this.body.sections, (section: DesktopContextSnapshotSection): void => {
        Column({ space: 2 }) {
          Text(section.name).width('100%').fontSize(this.codeSize).fontFamily(this.codeFamily)
            .fontColor($r('sys.color.font_tertiary'))
          DesktopContextBoundedText({ text: section.text, textSize: this.codeSize, family: this.codeFamily })
        }.width('100%').margin({ top: 4 })
      }, (_section: DesktopContextSnapshotSection, index: number): string => String(index))
    }
    if (this.body.relaySender !== undefined) {
      this.Caption($r('app.string.desktop_context_relay_sender', this.body.relaySender))
    }
    if (this.body.recalled !== undefined) {
      ForEach(this.body.recalled, (recall: DesktopContextRecall): void => {
        Row({ space: 8 }) {
          Text(recall.name).fontSize(this.codeSize).fontFamily(this.codeFamily)
            .fontColor($r('sys.color.font_secondary')).wordBreak(WordBreak.BREAK_ALL).flexShrink(1)
          Text($r('app.string.desktop_context_recall_counts', String(recall.retained), String(recall.omitted)))
            .fontSize(this.codeSize).fontFamily(this.codeFamily).fontColor($r('sys.color.font_tertiary'))
          if (recall.truncated) {
            Text($r('app.string.desktop_context_recall_truncated'))
              .fontSize(this.codeSize).fontFamily(this.codeFamily).fontColor($r('sys.color.font_tertiary'))
          }
        }.width('100%')
      }, (_recall: DesktopContextRecall, index: number): string => String(index))
    }
  }

  @Builder
  private SourceFields() {
    if (this.body.fields.length > 0) {
      Divider().color($r('sys.color.comp_divider')).strokeWidth(0.5).margin({ top: 4, bottom: 4 })
      ForEach(this.body.fields, (field: DesktopContextField): void => {
        Row({ space: 8 }) {
          Text(field.name).fontSize(this.codeSize).fontFamily(this.codeFamily).constraintSize({ minWidth: 96 })
            .fontColor($r('sys.color.font_tertiary'))
          Column() {
            DesktopContextBoundedText({ text: field.value, textSize: this.codeSize, family: this.codeFamily })
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      }, (field: DesktopContextField): string => field.name)
    }
  }

  build() {
    Column({ space: 4 }) {
      if (!this.forceNotice && this.row.mutations !== undefined) {
        this.ToolMutations(this.row.mutations)
      } else {
        this.StructuredContent()
        this.ModelFacing()
        this.SourceFields()
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct DesktopContextMessageRow {
  @Prop @Watch('resetForRow') row: DesktopContextMessage;
  @Prop bodySize: number = 14;
  @Prop textFamily: string = '';
  @Prop codeSize: number = 11;
  @Prop codeFamily: string = 'monospace';
  @State private open: boolean = false;
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private pressed: boolean = false;
  private activeRowId: string = '';

  aboutToAppear(): void {
    this.resetForRow();
  }

  private resetForRow(): void {
    if (this.activeRowId === this.row.id) { return; }
    this.activeRowId = this.row.id;
    this.open = false;
    this.hovered = false;
    this.focused = false;
    this.pressed = false;
  }

  private expandable(): boolean {
    const mutations: DesktopContextToolMutations | undefined = this.row.mutations;
    return mutations === undefined || mutations.added.length + mutations.removed.length !== 1;
  }

  private title(): Resource {
    const mutations: DesktopContextToolMutations | undefined = this.row.mutations;
    if (mutations !== undefined) {
      if (this.expandable()) { return $r('app.string.desktop_context_tools_updated'); }
      return mutations.added.length === 1 ? $r('app.string.desktop_context_tool_added', mutations.added[0]) :
        $r('app.string.desktop_context_tool_removed', mutations.removed[0]);
    }
    return this.row.producerRole === 'recall' ? $r('app.string.desktop_context_recall') :
      $r('app.string.desktop_context_injection');
  }

  private toolSummary(): Resource {
    const added: number = this.row.mutations?.added.length ?? 0;
    const removed: number = this.row.mutations?.removed.length ?? 0;
    if (added > 0 && removed > 0) {
      return $r('app.string.desktop_context_tools_changed', String(added), String(removed));
    }
    return added > 0 ? $r('app.string.desktop_context_tools_added_count', String(added)) :
      $r('app.string.desktop_context_tools_removed_count', String(removed));
  }

  private leadingIcon(): Resource {
    if (this.open) { return $r('app.media.dsh_queue_chevron_up_outline'); }
    if (this.expandable() && (this.hovered || this.focused || this.pressed)) {
      return $r('app.media.dsh_queue_chevron_down_outline');
    }
    if (this.row.mutations !== undefined) { return $r('app.media.dsh_reference_file'); }
    return this.row.producerRole === 'recall' ? $r('app.media.dsh_reference_session') :
      $r('app.media.dsh_context_injection_outline');
  }

  @Builder
  private Dot() {
    Circle({ width: 2, height: 2 }).fill($r('sys.color.font_tertiary')).margin({ left: 8, right: 8 })
      .accessibilityLevel('no')
  }

  @Builder
  private Header() {
    Row() {
      Row() {
        Image(this.leadingIcon()).width(this.bodySize).height(this.bodySize)
          .supportSvg2(true).draggable(false).accessibilityLevel('no')
      }.width(this.bodySize + 2).justifyContent(FlexAlign.Center).margin({ right: 6 })
      Text(this.title()).fontSize(this.bodySize - 1).fontFamily(this.textFamily).maxLines(1)
        .fontColor($r('sys.color.font_secondary')).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.row.mutations !== undefined && this.expandable()) {
        this.Dot()
        Text(this.toolSummary()).fontSize(this.bodySize - 1).fontFamily(this.textFamily).maxLines(1)
          .fontColor($r('sys.color.font_tertiary')).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
      } else if (this.row.mutations === undefined && this.row.producerLabel.length > 0) {
        this.Dot()
        Text(this.row.producerLabel).key('desktopContextSource-' + this.row.id)
          .fontSize(this.bodySize - 1).fontFamily(this.textFamily).maxLines(1)
          .fontColor($r('sys.color.font_tertiary')).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
        if (desktopContextNoticeSummary(this.row).length > 0) {
          this.Dot()
          Text(desktopContextNoticeSummary(this.row)).key('desktopContextSummary-' + this.row.id)
            .fontSize(this.bodySize - 1).fontFamily(this.textFamily).maxLines(1)
            .fontColor($r('sys.color.font_tertiary')).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
        }
      }
    }.width('100%').height(this.bodySize + 10).alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 4 }) {
      if (this.expandable()) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          this.Header()
        }.key('desktopContextDisclosure-' + this.row.id).width('100%').height(this.bodySize + 10).padding(0)
          .borderRadius(6).focusOnTouch(false).accessibilityGroup(true).accessibilitySelected(this.open)
          .accessibilityDescription(this.open ? $r('app.string.desktop_question_collapse') :
            $r('app.string.desktop_question_expand'))
          .backgroundColor(this.hovered || this.pressed ? $r('app.color.workspace_selection') : Color.Transparent)
          .onFocus((): void => { this.focused = true; }).onBlur((): void => { this.focused = false; })
          .onHover((hovered: boolean): void => { this.hovered = hovered; })
          .onTouch((event: TouchEvent): void => {
            this.pressed = event.type === TouchType.Down || event.type === TouchType.Move;
          })
          .onClick((): void => { this.open = !this.open; })
      } else {
        this.Header()
      }
      if (this.open && this.expandable()) {
        Row() {
          Blank().width(this.bodySize + 8)
          Scroll() {
            DesktopContextMessageBody({ row: this.row, codeSize: this.codeSize, codeFamily: this.codeFamily })
          }.key('desktopContextBody-' + this.row.id).layoutWeight(1).constraintSize({ maxHeight: 141 })
            .padding({ left: 12, right: 16, top: 10, bottom: 12 }).borderRadius(8)
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
            .backgroundColor($r('app.color.workspace_panel'))
        }.width('100%')
      }
    }.key('desktopContextMessage-' + this.row.id).width('100%').padding({ bottom: this.open ? 4 : 0 })
      .alignItems(HorizontalAlign.Start)
  }
}
