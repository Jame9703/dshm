import { KeyCode } from '@kit.InputKit';
import { dialogMaterial } from 'platform';
import { DesktopShortcut, desktopShortcutEqual, desktopShortcutFromEvent, desktopShortcutIssue, desktopShortcutLabels,
  desktopShortcutRows, EMPTY_DESKTOP_SHORTCUT, readDesktopShortcuts,
  saveDesktopShortcuts } from './DesktopShortcuts';
import type { DesktopShortcutKey, DesktopShortcutOverride, DesktopShortcutRow, DesktopShortcutSettings } from './DesktopShortcuts';

interface FixedShortcut {
  label: string;
  keys: string[];
}

const FIXED_INPUT: FixedShortcut[] = [
  { label: '发送消息', keys: ['Enter'] }, { label: '换行', keys: ['Shift', 'Enter'] },
  { label: '插话', keys: ['Ctrl', 'Enter'] }
];
const FIXED_MENUS: FixedShortcut[] = [
  { label: '移动菜单选择', keys: ['↑', '↓'] }, { label: '选择菜单项', keys: ['Enter'] },
  { label: '关闭菜单或顶层弹窗', keys: ['Esc'] }
];

@Component
struct DesktopShortcutReference {
  onClose: () => void = () => {};
  onChanged: () => void = () => {};
  @State private rows: DesktopShortcutRow[] = [];
  @State private query: string = '';
  @State private editing: string = '';
  @State private feedback: string = '';
  @State private failed: boolean = false;
  @State private busy: boolean = false;
  @State private confirmReset: boolean = false;
  @State private count: number = 0;
  @State private readable: boolean = true;
  @State private preview: string[] = [];
  private prefs: DesktopShortcutSettings = { overrides: [], raw: '', problem: '' };
  private pending: DesktopShortcutKey = EMPTY_DESKTOP_SHORTCUT;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.reload();
    if (this.prefs.problem) { this.report(this.prefs.problem, true); }
  }

  aboutToDisappear(): void { this.active = false; }

  private reload(): void {
    this.prefs = readDesktopShortcuts(this.getUIContext().getHostContext());
    this.readable = this.prefs.problem.length === 0;
    this.rows = desktopShortcutRows(this.prefs.overrides);
    this.count = this.prefs.overrides.length;
  }

  private report(message: string, error: boolean): void {
    this.feedback = message;
    this.failed = error;
  }

  private match(label: string, keys: string[], alias: string = ''): boolean {
    const search = this.query.toLowerCase().trim();
    return !search || [label, alias, keys.join('+'), keys.join(' '), keys.join('')].some((value: string): boolean =>
      value.toLowerCase().includes(search));
  }

  private editable(): DesktopShortcutRow[] {
    return this.rows.filter((row: DesktopShortcutRow): boolean =>
      this.match(row.label, desktopShortcutLabels(row.binding), row.alias));
  }

  private fixed(rows: FixedShortcut[]): FixedShortcut[] {
    return rows.filter((row: FixedShortcut): boolean => this.match(row.label, row.keys));
  }

  private startRecording(id: string): void {
    this.editing = id;
    this.pending = EMPTY_DESKTOP_SHORTCUT;
    this.preview = [];
    this.feedback = '';
  }

  private stopRecording(): void {
    this.editing = '';
    this.pending = EMPTY_DESKTOP_SHORTCUT;
    this.preview = [];
  }

  private recorderKey(event: KeyEvent, row: DesktopShortcutRow): boolean {
    if (event.keyCode === KeyCode.KEYCODE_TAB) { return false; }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down) {
      this.stopRecording();
      this.feedback = '';
      return true;
    }
    if (this.busy || this.editing !== row.id) { return true; }
    const code = event.keyCode;
    if (event.type === KeyType.Down) {
      if ([KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_CTRL_RIGHT, KeyCode.KEYCODE_ALT_LEFT,
        KeyCode.KEYCODE_ALT_RIGHT, KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_SHIFT_RIGHT].includes(code)) {
        return true;
      }
      if (this.pending.code !== 0 && this.pending.code !== code) {
        this.pending = EMPTY_DESKTOP_SHORTCUT;
        this.preview = [];
        this.report('请使用一个字符键或功能键，再配合修饰键。', true);
        return true;
      }
      if (this.pending.code === code) { return true; }
      const binding = desktopShortcutFromEvent(event);
      const issue = event.metaKey === 1 ? '系统键无法用于 ArkUI 快捷键。' :
        desktopShortcutIssue(binding);
      if (issue) {
        this.report(issue, true);
        return true;
      }
      this.pending = binding;
      this.preview = desktopShortcutLabels(binding);
      this.feedback = '';
    } else if (event.type === KeyType.Up && this.pending.code === code) {
      const value = this.pending;
      this.pending = EMPTY_DESKTOP_SHORTCUT;
      const owner = this.rows.find((other: DesktopShortcutRow): boolean =>
        other.id !== row.id && other.modified && desktopShortcutEqual(other.binding, value));
      if (owner !== undefined) { this.report(`已被「${owner.label}」占用`, true); }
      else { this.saveRow(row.id, value); }
    }
    return true;
  }

  private saveRow(id: string, key?: DesktopShortcutKey): void {
    const next = this.prefs.overrides.filter((item: DesktopShortcutOverride): boolean => item.id !== id);
    if (key !== undefined) { next.push({ id: id, binding: key }); }
    this.persist(next);
  }

  private async persist(next: DesktopShortcutOverride[], reset: boolean = false): Promise<void> {
    if (this.busy || this.prefs.problem) { return; }
    this.busy = true;
    const problem = await saveDesktopShortcuts(this.getUIContext().getHostContext(), this.prefs, next);
    if (!problem) { this.onChanged(); }
    if (!this.active) { return; }
    this.reload();
    this.busy = false;
    if (problem) {
      this.report(problem, true);
    } else {
      this.stopRecording();
      this.confirmReset = false;
      this.report(reset ? '已恢复默认快捷键' : '已修改', false);
    }
  }

  private dismiss(): void {
    if (this.busy) { return; }
    if (this.confirmReset) { this.confirmReset = false; }
    else if (this.editing) { this.stopRecording(); }
    else { this.onClose(); }
  }

  private referenceKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) { return false; }
    const opener = this.rows.find((row: DesktopShortcutRow): boolean => row.id === DesktopShortcut.REFERENCE);
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE || (opener !== undefined && !opener.occupiedBy &&
      desktopShortcutEqual(opener.binding, desktopShortcutFromEvent(event)))) {
      this.dismiss();
      return true;
    }
    return false;
  }

  @Builder
  private Keys(keys: string[], combine: boolean = true) {
    Row({ space: 3 }) {
      ForEach(keys, (key: string, index: number): void => {
        if (combine && index > 0) {
          Text('+').fontSize(10).fontColor($r('sys.color.font_tertiary'))
        }
        Text(key).fontSize(11).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
          .fontColor($r('sys.color.font_secondary')).padding({ left: 5, right: 5, top: 2, bottom: 2 })
          .constraintSize({ minWidth: 20 }).borderRadius(5).backgroundColor($r('app.color.workspace_canvas'))
      }, (key: string): string => key)
    }
  }

  @Builder
  private CommandRow(row: DesktopShortcutRow) {
    Column() {
      Row({ space: 8 }) {
        Text(row.label).fontSize(14).layoutWeight(1).fontColor($r('sys.color.font_primary'))
        if (this.editing === row.id) {
          Button(this.preview.length > 0 ? this.preview.join('+') : '按下快捷键', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .key('desktopShortcutRecorder')
            .defaultFocus(true).onAppear((): void => {
              setTimeout((): void => {
                if (this.active && this.editing === row.id) {
                  this.getUIContext().getFocusController().requestFocus('desktopShortcutRecorder');
                }
              }, 0);
            })
            .onKeyPreIme((event: KeyEvent): boolean => this.recorderKey(event, row))
        } else {
          if (row.occupiedBy || row.binding.code === 0) {
            Text(row.occupiedBy ? `已被「${row.occupiedBy}」占用` : '暂无快捷键')
              .fontSize(12).fontColor($r('sys.color.font_secondary'))
          } else {
            this.Keys(desktopShortcutLabels(row.binding))
          }
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_shortcut_edit')).width(12).height(12)
              .fillColor($r('sys.color.font_secondary')).accessibilityLevel('no')
          }.key(`desktopShortcutEdit-${row.id}`).width(30).height(30).padding(0).borderRadius(8)
            .accessibilityText(`修改${row.label}快捷键`).enabled(!this.busy && this.readable)
            .onClick((): void => this.startRecording(row.id))
        }
      }.width('100%').height(36)
        .onClick((): void => { if (this.editing !== row.id && !this.busy && this.readable) { this.startRecording(row.id); } })
      if (this.editing === row.id) {
        Row({ space: 3 }) {
          Text('松开组合键即保存').fontSize(11).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          Button('移除', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).enabled(!this.busy && row.binding.code !== 0)
            .key('desktopShortcutRemove').onClick((): void => this.saveRow(row.id, EMPTY_DESKTOP_SHORTCUT))
          Button('恢复默认', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).enabled(!this.busy && row.modified)
            .key('desktopShortcutRestore').onClick((): void => this.saveRow(row.id))
        }.width('100%')
      }
    }.width('100%')
  }

  @Builder
  private FixedGroup(label: string, rows: FixedShortcut[]) {
    if (rows.length > 0) {
      Text(label).fontSize(12).fontColor($r('sys.color.font_secondary')).padding({ top: 12, bottom: 4 })
      ForEach(rows, (row: FixedShortcut): void => {
        Row() {
          Text(row.label).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          this.Keys(row.keys, row.keys[0] !== '↑')
        }.width('100%').height(34)
      }, (row: FixedShortcut): string => row.label)
    }
  }

  @Builder
  private Confirmation() {
    Text('恢复全部默认快捷键？').fontSize(16).fontWeight(FontWeight.Medium).padding({ bottom: 12 })
    Text('你修改或移除的 ArkUI 快捷键都会恢复。').fontSize(14).fontColor($r('sys.color.font_secondary'))
    Row({ space: 8 }) {
      Blank().layoutWeight(1)
      Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(!this.busy).onClick((): void => { this.confirmReset = false; })
      Button('恢复默认').key('desktopShortcutConfirmReset').enabled(!this.busy)
        .onClick((): void => { this.persist([], true); })
    }.width('100%').padding({ top: 16 })
  }

  build() {
    Column({ space: 10 }) {
      if (this.confirmReset) {
        this.Confirmation()
      } else {
        Row() {
          Text('快捷键').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Image($r('app.media.dsh_dock_close')).width(14).height(14).accessibilityLevel('no')
          }.key('desktopShortcutClose').width(30).height(30).padding(0)
            .accessibilityText('关闭快捷键').enabled(!this.busy).onClick((): void => this.dismiss())
        }.width('100%')
        Row({ space: 8 }) {
          Image($r('app.media.dsh_shortcut_search')).width(14).height(14)
            .fillColor($r('sys.color.font_tertiary')).accessibilityLevel('no')
          TextInput({ text: this.query, placeholder: '搜索快捷键' }).key('desktopShortcutSearch')
            .defaultFocus(true).layoutWeight(1).height(36).fontSize(13).padding(0).backgroundColor(Color.Transparent)
            .cancelButton({ style: CancelButtonStyle.INPUT }).onChange((value: string): void => {
              if (value !== this.query) { this.stopRecording(); this.query = value; }
            })
            .onKeyPreIme((event: KeyEvent): boolean => this.referenceKey(event))
        }.width('100%').height(36).padding({ left: 13, right: 10 }).borderRadius(12)
          .backgroundColor($r('app.color.workspace_canvas')).border({ width: 0.5, color: $r('app.color.workspace_border') })
        Scroll() {
          Column() {
            ForEach(this.editable(), (row: DesktopShortcutRow): void => { this.CommandRow(row) },
              (row: DesktopShortcutRow): string => row.id + JSON.stringify(row.binding) + row.occupiedBy + row.modified)
            this.FixedGroup('消息输入', this.fixed(FIXED_INPUT))
            this.FixedGroup('菜单与弹层', this.fixed(FIXED_MENUS))
            if (this.editable().length === 0 && this.fixed(FIXED_INPUT).length === 0 && this.fixed(FIXED_MENUS).length === 0) {
              Text('没有匹配的快捷键').fontSize(13).fontColor($r('sys.color.font_secondary')).padding({ top: 14 })
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
        Row() {
          Button('恢复全部默认', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopShortcutResetAll')
            .fontSize(13).fontColor($r('sys.color.font_secondary')).enabled(this.count > 0 && !this.busy && this.readable)
            .onClick((): void => { this.stopRecording(); this.feedback = ''; this.confirmReset = true; })
          Blank().layoutWeight(1)
          if (this.count > 0) {
            Text(`${this.count} 项已自定义`).fontSize(12).fontColor($r('sys.color.font_secondary'))
          }
        }.width('100%')
      }
      if (this.feedback) {
        Text(this.feedback).key('desktopShortcutFeedback').fontSize(12)
          .fontColor(this.failed ? $r('sys.color.warning') : $r('sys.color.font_secondary'))
      }
    }.key('desktopShortcutReference').height(this.confirmReset ? 154 : '100%').width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 12 })
      .onKeyEvent((event: KeyEvent): boolean => this.referenceKey(event))
  }
}

@Component
export struct DesktopShortcutDialog {
  @Prop @Watch('sync') show: boolean = false;
  @Prop panelWidth: number = 480;
  onClose: () => void = () => {};
  onChanged: () => void = () => {};
  private current: number = -1;
  private generation: number = 0;
  private mounted: boolean = false;

  aboutToAppear(): void { this.mounted = true; this.sync(); }

  aboutToDisappear(): void { this.mounted = false; this.close(); }

  private close(): void {
    this.generation++;
    const id = this.current;
    this.current = -1;
    if (id >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(id); }
  }

  private sync(): void {
    if (this.show) { this.open(); }
    else { this.close(); }
  }

  private async open(): Promise<void> {
    const version = ++this.generation;
    const prompt = this.getUIContext().getPromptAction();
    const material = dialogMaterial();
    try {
      const id = await prompt.openCustomDialog({ builder: (): void => { this.Content(); }, alignment: DialogAlignment.Center,
        width: this.panelWidth, height: '78%', autoCancel: true, systemMaterial: material, cornerRadius: 24,
        backgroundColor: material === undefined ? $r('app.color.workspace_panel') : undefined,
        onDidDisappear: (): void => {
          if (this.generation === version) { this.current = -1; this.onClose(); }
        } });
      if (this.generation === version && this.show) { this.current = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.generation === version) { this.onClose(); }
    }
  }

  @Builder
  private Content() {
    DesktopShortcutReference({ onClose: this.onClose, onChanged: (): void => {
      if (this.mounted) { this.onChanged(); }
    } })
  }

  build() { Blank().width(0).height(0).accessibilityLevel('no'); }
}

@Component
export struct DesktopShortcutSettingsRow {
  onOpen: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('快捷键').fontSize(14).fontColor($r('sys.color.font_primary'))
        Text('查看和编辑当前可用的快捷键和输入操作').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('编辑快捷键', { buttonStyle: ButtonStyleMode.TEXTUAL }).key('desktopSettingsEditShortcuts')
        .onClick(this.onOpen)
    }.width('100%').height(64)
  }
}
