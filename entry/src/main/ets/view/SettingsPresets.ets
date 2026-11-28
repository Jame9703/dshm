/**
 * 设置页「预设」分区（P4-5：从 `SettingsPane.build()` 的内联分支拆出的域组件）。
 *
 * ## 它拥有什么
 *
 * 官方 `settings-agent-presets` 这一页的两半：
 *   ① **预设名单卡片**（E161）：名字 / 说明 / id / 默认标记 / 随附或自定义，以及卡片动作；
 *   ② **`agent-*` 设置分区的编辑器**（E129）：让"新建会话用哪个预设"真的可改。
 *
 * ## 被保留下来的语义（都不是装饰）
 *
 * 1. **复制是创建自定义预设的唯一入口**（官方规则）⇒ **每张卡都有**「复制」，
 *    连随附只读预设也能被复制。
 * 2. **删除只对自定义预设开放**：`trust === 'system'` 是随附只读，
 *    连入口都不给（宿主也会拒绝）——而不是给一个点了必被拒的按钮。
 * 3. **删除走两步确认**（先「确认删除 / 取消」）——这是不可逆动作。
 * 4. **查看是只读查看器**（E173，官方对随附预设就是"在只读查看器里打开"）。
 * 5. **"预设没有可读文本"要说清楚**：宿主返回空串时说明可能的原因，不显示空白面板。
 * 6. **预设只在会话创建时固定** ⇒ 这里改的是**此后新建会话**的默认值，已存在的会话不受影响
 *    （这句话必须留在页面上，否则用户会以为改了当前会话）。
 *
 * ## 组件内状态（三个，都不上宿主）
 *
 * `confirmingId` / `viewedId` / `viewedContent` 都是**一次交互内的临时态**，
 * 关掉设置页就没有意义，所以不进 `NavigationState`（对照那些"刷新后应当恢复"的选中态）。
 *
 * ## 一处例外（如实记录）：查看动作直接调中枢
 *
 * 查看是**纯读取**、无副作用、也不改变其它页面状态；为它再往 `Index` 穿一层 prop
 * 只会增加耦合（与 `SettingsModels.providerCandidates()` 同一类例外）。
 * 写入类动作（复制 / 删除）仍走宿主回调，因为它们要影响"下一步做什么"（提示语落在宿主页上）。
 */

import { window } from '@kit.ArkUI';
import { dialogMaterial } from 'platform';
import {
  AgentPresetRow,
  Fs,
  Radius,
  SessionHub,
  SettingGroup,
  SettingItem,
  Sp,
  presetIsBundled
} from 'appstate';
import { SettingRow } from './SettingRow';
import { desktopAgentPresetName } from '../desktop/DesktopAgentPresetPicker';
import type { DesktopHostActions } from '../desktop/DesktopHostActions';
import { readDesktopPresetComposition } from '../desktop/DesktopPresetComposition';
import { DesktopPresetViewer } from '../desktop/DesktopPresetViewer';
import { DesktopPresetGuide, desktopPresetGuideCopy } from '../desktop/DesktopPresetGuide';
import type { DesktopPresetGuideCopy } from '../desktop/DesktopPresetGuide';
import { writeDesktopPresetDefault } from '../desktop/DesktopPresetDefaults';
import type { DesktopPresetDefaultSync } from '../desktop/DesktopPresetDefaults';

interface DesktopPresetViewport {
  width: number;
  height: number;
}

/** 设置页「预设」分区 */
@Component
export struct SettingsPresets {
  /** Agent 预设名单（E159/E160：`agentPresets/list` 实测形状；`trust === 'system'` = 随附只读） */
  @Prop presets: AgentPresetRow[] = [];
  /** 名单读取结论（非空必须显示：读不到 ≠ 没有预设） */
  @Prop note: string = '';
  /** **全部**设置分区（含被「通用」策展隐藏的 `agent-*`）——预设编辑器要从这里取 */
  @Prop allGroups: SettingGroup[] = [];
  @Prop desktopViewer: boolean = false;
  compositionHost?: DesktopHostActions;
  startCreator?: () => void;
  capturePresetDefaultSync?: () => DesktopPresetDefaultSync | undefined;
  /** 复制（官方唯一的创建入口；随附预设也能复制） */
  onCopy: (from: string, name: string) => void = () => {
  };
  /** 删除（宿主强制"随附预设不可写"，并把它的原话转达给用户） */
  onDelete: (id: string) => void = () => {
  };
  /** 设置项的三个写入口（`agent-*` 分区里会有开关/单选/文本项） */
  onToggleSetting: (key: string, value: boolean) => void = () => {
  };
  onPickChoice: (key: string, current: string) => void = () => {
  };
  onEditText: (item: SettingItem) => void = () => {
  };
  onEditStruct: (item: SettingItem) => void = () => {
  };
  onResetSetting: (key: string) => void = () => {
  };

  /** 已按过一次「删除」、等待确认的预设 id（两步确认） */
  @State confirmingId: string = '';
  /** 正在查看的预设 id（空 = 未查看） */
  @State viewedId: string = '';
  /** 只读查看器当前展示的预设内容（E173） */
  @State viewedContent: string = '';
  @State private viewerProblem: string = '';
  @State private savingDefault: boolean = false;
  @State private defaultProblem: ResourceStr = '';
  private viewerActive: boolean = false;
  private viewerRequest: number = 0;
  private viewerOpening: boolean = false;
  private viewerDialog: number = -1;

  aboutToAppear(): void {
    this.viewerActive = true;
  }

  aboutToDisappear(): void {
    this.viewerActive = false;
    this.viewerRequest++;
    this.closePresetViewer();
  }

  private closePresetViewer(): void {
    if (this.viewerDialog >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(this.viewerDialog); }
  }

  private presetLabel(row: AgentPresetRow): string {
    const label = desktopAgentPresetName(row.id, row.name || undefined);
    return typeof label === 'string' ? label :
      this.getUIContext().getHostContext()?.resourceManager.getStringSync(label) ?? row.id;
  }

  private viewerFailed(problem: string = ''): void {
    this.viewerProblem = problem || (this.getUIContext().getHostContext()?.resourceManager.getStringSync(
      $r('app.string.desktop_preset_view_failed').id) ?? '');
  }

  @Builder
  private PresetViewer(name: string, yaml: string, maxHeight: number) {
    DesktopPresetViewer({ presetName: name, yaml: yaml, maxCodeHeight: maxHeight,
      onClose: (): void => { this.closePresetViewer(); } })
  }

  @Builder
  private PresetGuide(name: string, guide: DesktopPresetGuideCopy, usage: boolean) {
    DesktopPresetGuide({ presetName: name, copy: guide, initialUsage: usage,
      onClose: (): void => { this.closePresetViewer(); } })
  }

  private presetViewport(): DesktopPresetViewport {
    const ui = this.getUIContext();
    const name = ui.getWindowName();
    if (name) {
      try {
        const rect = window.findWindow(name).getWindowProperties().windowRect;
        return { width: Math.max(1, ui.px2vp(rect.width) - 32), height: ui.px2vp(rect.height) };
      } catch (_) {}
    }
    return { width: 720, height: 1000 };
  }

  private async viewPresetComposition(row: AgentPresetRow): Promise<void> {
    if (!this.viewerActive || this.viewerOpening || this.viewerDialog >= 0) { return; }
    this.viewerProblem = '';
    const host = this.compositionHost;
    if (host === undefined) { this.viewerFailed(); return; }
    const request = ++this.viewerRequest;
    try {
      const composition = await readDesktopPresetComposition(host, row.id);
      if (!this.viewerActive || request !== this.viewerRequest) { return; }
      const yaml = composition.yaml;
      if (yaml === undefined) { this.viewerFailed(composition.problem); return; }
      const label = this.presetLabel(row);
      const viewport = this.presetViewport();
      await this.openPresetReader(request, 'desktopPresetView-' + row.id, Math.min(720, viewport.width), undefined,
        (): void => { this.PresetViewer(label, yaml, Math.min(560, viewport.height * 0.6)); });
    } catch (_) {
      if (this.viewerActive && request === this.viewerRequest) { this.viewerFailed(); }
    }
  }

  private viewPresetGuide(row: AgentPresetRow, usage: boolean): void {
    if (!this.viewerActive || this.viewerOpening || this.viewerDialog >= 0 || !this.desktopBuiltIn(row)) { return; }
    const guide = desktopPresetGuideCopy(row.id);
    if (guide === undefined) { return; }
    this.viewerProblem = '';
    const request = ++this.viewerRequest;
    const label = this.presetLabel(row);
    const viewport = this.presetViewport();
    this.openPresetReader(request, this.guideActionId(row.id, usage), Math.min(640, viewport.width),
      Math.min(600, Math.max(1, viewport.height - 32)), (): void => { this.PresetGuide(label, guide, usage); });
  }

  private async openPresetReader(request: number, trigger: string, readerWidth: number, readerHeight: number | undefined,
    content: CustomBuilder): Promise<void> {
    const ui = this.getUIContext();
    const prompt = ui.getPromptAction();
    try {
      const material = dialogMaterial();
      this.viewerOpening = true;
      const id = await prompt.openCustomDialog({
        builder: content, alignment: DialogAlignment.Center,
        width: readerWidth, height: readerHeight, autoCancel: true, isModal: true, cornerRadius: 28,
        systemMaterial: material,
        maskColor: $r('app.color.desktop_settings_mask'),
        backgroundColor: material === undefined ? $r('app.color.desktop_settings_surface') : undefined,
        onDidDisappear: (): void => {
          if (request !== this.viewerRequest) { return; }
          this.viewerDialog = -1;
          this.viewerOpening = false;
          setTimeout((): void => {
            if (this.viewerActive && request === this.viewerRequest) {
              ui.getFocusController().requestFocus(trigger);
            }
          }, 0);
        }
      });
      if (this.viewerActive && request === this.viewerRequest && this.viewerOpening) { this.viewerDialog = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.viewerActive && request === this.viewerRequest) { this.viewerFailed(); }
    } finally {
      if (request === this.viewerRequest) { this.viewerOpening = false; }
    }
  }

  /** `agent-*` 设置分区（E129：Agent 预设相关，官方在设置里有专门分区） */
  private agentGroups(): SettingGroup[] {
    const out: SettingGroup[] = [];
    for (let i = 0; i < this.allGroups.length; i++) {
      const g: SettingGroup = this.allGroups[i];
      if (g.title.startsWith('agent-')) {
        out.push(g);
      }
    }
    return out;
  }

  /**
   * 只读查看器要显示的内容。
   *
   * 【为什么把 Promise 留在组件里】它只写组件自己的 `viewedContent`，
   * 失败信息也只对这一次查看有意义 ⇒ 让它出组件反而要往上传错误分支。
   */
  private readPreset(id: string): void {
    this.viewedId = id;
    this.viewedContent = '正在读取…';
    SessionHub.shared().readAgentPreset(id).then((text: string) => {
      this.viewedContent = text.length > 0
        ? text
        : '宿主没有返回内容（可能该预设没有可读的组装文本，或读取被拒）。';
    }).catch((e: Object) => {
      this.viewedContent = `读取失败：${(e as Error).message}`;
    });
  }

  private hasCreator(): boolean {
    return this.startCreator !== undefined && this.presets.some((row: AgentPresetRow): boolean => row.id === 'cordis');
  }

  private desktopBuiltIn(row: AgentPresetRow): boolean {
    return !row.name && (row.id === 'standard' || row.id === 'ptc' || row.id === 'minimal' || row.id === 'cordis');
  }

  private desktopPresetRows(builtIn: boolean): AgentPresetRow[] {
    return this.presets.filter((row: AgentPresetRow): boolean => this.desktopBuiltIn(row) === builtIn);
  }

  private async makeDefault(row: AgentPresetRow): Promise<void> {
    const host = this.compositionHost;
    if (this.savingDefault || row.isDefault || row.broken !== undefined || host === undefined) { return; }
    const sync = this.capturePresetDefaultSync?.();
    this.savingDefault = true;
    this.defaultProblem = '';
    try {
      const problem = await writeDesktopPresetDefault(host, row.id, async (): Promise<string | undefined> => {
        const rows = await SessionHub.shared().refreshAgentPresets();
        return rows?.find((preset: AgentPresetRow): boolean => preset.isDefault)?.id;
      }, sync);
      if (this.viewerActive) { this.defaultProblem = problem; }
    } catch (_) {
      if (this.viewerActive) { this.defaultProblem = $r('app.string.desktop_preset_default_save_failed'); }
    } finally {
      if (this.viewerActive) { this.savingDefault = false; }
    }
  }

  private guideActionId(id: string, usage: boolean): string {
    return (usage ? 'desktopPresetHowTo-' : 'desktopPresetExplanation-') + id;
  }

  @Builder
  private GuideAction(row: AgentPresetRow, usage: boolean) {
    Button(usage ? $r('app.string.desktop_preset_guide_usage') : $r('app.string.desktop_preset_guide_explanation'),
      { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
      .key(this.guideActionId(row.id, usage)).id(this.guideActionId(row.id, usage)).fontSize(13)
      .padding({ left: 8, right: 8 }).height(28).borderRadius(8).fontColor($r('sys.color.font_secondary'))
      .onClick((): void => { this.viewPresetGuide(row, usage); })
  }

  @Builder
  private DesktopPresetGroup(builtIn: boolean) {
    if (this.desktopPresetRows(builtIn).length > 0 || (!builtIn && this.hasCreator())) {
      Column({ space: 8 }) {
        Text(builtIn ? $r('app.string.desktop_preset_group_built_in') : $r('app.string.desktop_preset_group_custom'))
          .fontSize(14).fontWeight(FontWeight.Medium).width('100%')
        ForEach(this.desktopPresetRows(builtIn), (row: AgentPresetRow): void => { this.presetCard(row); },
          (row: AgentPresetRow): string => row.id + '|' + row.isDefault + '|' + (row.broken ?? ''))
        if (!builtIn && this.hasCreator()) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 6 }) {
              Image($r('app.media.dsh_reference_menu_plus')).width(14).height(14).supportSvg2(true)
                .draggable(false).accessibilityLevel('no')
              Text($r('app.string.desktop_preset_create')).fontSize(14).lineHeight(22)
                .fontColor($r('sys.color.font_primary')).flexShrink(1)
            }
          }.key('desktopPresetCreateInCreator').width('100%').height(44).borderRadius(16)
            .border({ width: 1, style: BorderStyle.Dashed, color: $r('app.color.workspace_border') })
            .enabled(!this.savingDefault)
            .onClick((): void => { this.startCreator?.(); })
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Column({ space: Sp.M }) {
      if (this.viewerProblem.length > 0) {
        Text(this.viewerProblem).key('desktopPresetViewerError').fontSize(12).width('100%')
          .fontColor($r('app.color.workspace_status_error'))
      }
      if (this.defaultProblem !== '') {
        Text(this.defaultProblem).key('desktopPresetDefaultError').fontSize(12).width('100%')
          .fontColor($r('app.color.workspace_status_error'))
      }
      if (this.note.length > 0) {
        Text(this.note)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding(Sp.M)
          .borderRadius(Radius.M)
          .backgroundColor($r('sys.color.background_secondary'))
      }
      if (this.desktopViewer) {
        Column({ space: 4 }) {
          Text($r('app.string.desktop_preset_section_title')).fontSize(20).fontWeight(FontWeight.Medium)
          Text($r('app.string.desktop_preset_section_intro')).fontSize(14).lineHeight(22)
            .fontColor($r('sys.color.font_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start)
        this.DesktopPresetGroup(true)
        this.DesktopPresetGroup(false)
      } else if (this.presets.length > 0) {
        Text('Agent 预设')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        ForEach(this.presets, (p: AgentPresetRow) => {
          this.presetCard(p)
        }, (p: AgentPresetRow) => p.id)
        Text('预设是"这个会话的 Agent 跑哪些插件"的组装；会话创建时固定，改默认只影响此后新建的会话。复制 / 打开位置 / 删除待接线（形状需先探针确证）。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      if (this.agentGroups().length === 0) {
        Text('宿主没有暴露 agent-* 设置分区（端侧只显示它确实报告的东西）。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      } else {
        ForEach(this.agentGroups(), (group: SettingGroup) => {
          this.agentGroup(group)
        }, (group: SettingGroup) => group.title)
      }
      if (!this.desktopViewer) {
        Text('预设**在会话创建时固定**（官方原话），所以这里设置的是**此后新建会话**用的默认值；已存在的会话不受影响。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
    }
    .width('100%')
  }

  /** 一张预设卡：名字 / 默认标记 / 随附或自定义 / 说明 / id / 三个动作 */
  @Builder
  presetCard(p: AgentPresetRow) {
    Column({ space: 2 }) {
      if (this.desktopViewer) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          this.PresetCardDetails(p)
        }.key('desktopPresetMakeDefault-' + p.id).width('100%').height(LayoutPolicy.wrapContent)
          .padding({ left: 2, right: 2, top: 6, bottom: 6 }).borderRadius(12)
          .backgroundColor(Color.Transparent)
          .enabled(!this.savingDefault || p.broken !== undefined)
          .accessibilitySelected(p.isDefault)
          .accessibilityDescription(p.broken ?? '')
          .accessibilityText(p.broken !== undefined ? $r('app.string.desktop_preset_default_broken_action', this.presetLabel(p)) :
            p.isDefault ? $r('app.string.desktop_preset_default_in_use_action', this.presetLabel(p)) :
            $r('app.string.desktop_preset_default_action', this.presetLabel(p)))
          .onClick((): void => { this.makeDefault(p); })
      } else {
        this.PresetCardDetails(p)
      }
      Row({ space: Sp.M }) {
        if (!this.desktopViewer) {
          Text('复制')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.onCopy(p.id, p.name);
            })
          Text(this.viewedId === p.id ? '收起内容' : '查看')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              if (this.viewedId === p.id) {
                this.viewedId = '';
                this.viewedContent = '';
                return;
              }
              this.readPreset(p.id);
            })
        }
        if (!this.desktopViewer && !presetIsBundled(p)) {
          Text(this.confirmingId === p.id ? '确认删除' : '删除')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.alert'))
            .onClick(() => {
              if (this.confirmingId === p.id) {
                this.confirmingId = '';
                this.onDelete(p.id);
              } else {
                this.confirmingId = p.id;
              }
            })
          if (this.confirmingId === p.id) {
            Text('取消')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .onClick(() => {
                this.confirmingId = '';
              })
          }
        }
        if (this.desktopViewer) {
          if (this.desktopBuiltIn(p)) {
            this.GuideAction(p, false)
            this.GuideAction(p, true)
          }
          Blank()
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_preset_browse')).width(16).height(16).supportSvg2(true)
              .draggable(false).accessibilityLevel('no')
          }.key('desktopPresetView-' + p.id).id('desktopPresetView-' + p.id)
            .width(28).height(28).borderRadius(8).padding(6)
            .accessibilityText($r('app.string.desktop_preset_view_action', this.presetLabel(p)))
            .onClick((): void => { this.viewPresetComposition(p); })
        }
      }
      .width('100%')
      if (this.viewedId === p.id) {
        Text(this.viewedContent)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding(Sp.S)
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_primary'))
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(this.desktopViewer ? 20 : Radius.M)
    .border(this.desktopViewer ? { width: 0.5, color: p.broken !== undefined ? $r('app.color.workspace_status_error') :
      p.isDefault ? $r('sys.color.brand') : $r('app.color.workspace_border') } : { width: 0 })
    .backgroundColor(this.desktopViewer && p.isDefault ? $r('app.color.workspace_selection') :
      $r('sys.color.background_secondary'))
  }

  @Builder
  private PresetCardDetails(p: AgentPresetRow) {
    Column({ space: 2 }) {
      Row({ space: Sp.S }) {
        Text(this.desktopViewer ? desktopAgentPresetName(p.id, p.name || undefined) : p.name || p.id)
          .fontSize(Fs.BODY).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.desktopViewer && p.broken !== undefined) {
          Text($r('app.string.desktop_preset_default_broken')).fontSize(Fs.CAPTION)
            .fontColor($r('app.color.workspace_status_error'))
        }
        if (p.isDefault) {
          Text(this.desktopViewer ? $r('app.string.desktop_preset_default_in_use') : '默认')
            .fontSize(Fs.CAPTION).fontColor($r('sys.color.brand'))
        }
        if (!this.desktopViewer || !p.isDefault) {
          Text(this.desktopViewer ? (this.desktopBuiltIn(p) ? $r('app.string.desktop_preset_group_built_in') :
            $r('app.string.desktop_preset_group_custom')) : (presetIsBundled(p) ? '随附' : '自定义'))
            .fontSize(Fs.CAPTION).fontColor($r('sys.color.font_tertiary'))
        }
      }.width('100%')
      if (p.description.length > 0) {
        Text(p.description).fontSize(Fs.CAPTION).fontColor($r('sys.color.font_secondary')).width('100%')
      }
      Text(p.id).fontSize(Fs.CAPTION).fontColor($r('sys.color.font_tertiary')).width('100%')
      if (this.desktopViewer && p.broken) {
        Text(p.broken).key('desktopPresetBrokenReason-' + p.id)
          .fontSize(Fs.CAPTION).fontColor($r('app.color.workspace_status_error')).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 一个 `agent-*` 分区（组标题 + 组内设置项） */
  @Builder
  agentGroup(group: SettingGroup) {
    Column({ space: Sp.XS }) {
      Text(group.title)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      ForEach(group.items, (item: SettingItem) => {
        SettingRow({
          item: item,
          onToggleSetting: (key: string, value: boolean) => {
            this.onToggleSetting(key, value);
          },
          onPickChoice: (key: string, current: string) => {
            this.onPickChoice(key, current);
          },
          onEditText: (it: SettingItem) => {
            this.onEditText(it);
          },
          onEditStruct: (it: SettingItem) => {
            this.onEditStruct(it);
          },
          onResetSetting: (key: string) => {
            this.onResetSetting(key);
          }
        })
      }, (item: SettingItem) => item.key)
    }
    .width('100%')
  }
}
