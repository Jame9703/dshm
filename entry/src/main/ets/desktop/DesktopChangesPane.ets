import {
  desktopAppliedDiff, desktopChangedPath, desktopFileDiff, desktopFileName, DesktopChangedFile, DesktopChangeTarget, DesktopDiff,
  DesktopDiffCell, DesktopDiffRow
} from './DesktopArtifacts';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopMenuOptions } from './DesktopMenuOptions';

class DiffRows implements IDataSource {
  private rows: DesktopDiffRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.rows.length; }
  getData(index: number): DesktopDiffRow { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((other: DataChangeListener): boolean => other !== listener);
  }
  reset(rows: DesktopDiffRow[]): void {
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }
}

@Component
export struct DesktopChangesPane {
  host?: DesktopHostActions;
  @Prop @Watch('onTarget') target: DesktopChangeTarget | undefined = undefined;
  onClose: () => void = (): void => {};
  onFile: (path: string, name: string, target: DesktopChangeTarget) => void =
    (_path: string, _name: string, _target: DesktopChangeTarget): void => {};

  @State private selected: number = 0;
  @State private diff: DesktopDiff | undefined = undefined;
  @State private loading: boolean = false;
  @State private missing: boolean = false;
  @State private error: boolean = false;
  @State private split: boolean = false;
  @State private wrap: boolean = false;
  @State private viewport: number = 300;
  @State private lineWidth: number = 300;
  private readonly rows: DiffRows = new DiffRows();
  private revision: number = 0;

  aboutToAppear(): void { this.onTarget(); }
  aboutToDisappear(): void { this.revision++; }

  private onTarget(): void {
    this.split = this.target?.split === true;
    this.wrap = this.target?.wrap === true;
    this.select(this.target?.index ?? 0);
  }

  private selectedFile(): DesktopChangedFile | undefined {
    return this.target?.summary.files[this.selected];
  }

  private fileOptions(): MenuElement[] {
    return this.target?.summary.files.map((file: DesktopChangedFile, index: number): MenuElement => {
      const counts = file.binary ? '二进制' : file.oversized ? '过大' :
        this.target?.summary.applied ? '' : `+${file.added} −${file.deleted}`;
      return { value: (this.selected === index ? '✓ ' : '') + `${file.display}   ${counts}`,
        action: (): void => { this.select(index); } };
    }) ?? [];
  }

  private async select(index: number): Promise<void> {
    const revision = ++this.revision;
    const target = this.target;
    const host = this.host;
    const file = target?.summary.files[index];
    if (target === undefined || host === undefined || file === undefined) {
      return;
    }
    this.selected = index;
    this.diff = undefined;
    this.loading = true;
    this.missing = false;
    this.error = false;
    if (target.summary.applied === true) {
      this.diff = desktopAppliedDiff(file);
      this.loading = false;
      this.updateRows();
      return;
    }
    const result = await host.changeDiff(target.sessionId, target.sequence, index);
    if (revision !== this.revision) {
      return;
    }
    this.loading = false;
    this.missing = result.error?.httpStatus === 404;
    this.diff = desktopFileDiff(result.value);
    this.error = !this.missing && this.diff === undefined;
    this.updateRows();
  }

  private updateRows(): void {
    const sideBySide = this.split && this.diff?.allowSplit === true;
    const rows = (sideBySide ? this.diff?.splitRows : this.diff?.rows) ?? [];
    let longest = 0;
    rows.forEach((row: DesktopDiffRow): void => {
      longest = Math.max(longest, row.left?.text.length ?? 0, row.right?.text.length ?? 0);
    });
    this.lineWidth = (sideBySide ? 2 : 1) * (longest * 8 + 77);
    this.rows.reset(rows);
  }

  private openFile(): void {
    const file = this.selectedFile();
    const target = this.target;
    if (file !== undefined && target !== undefined) {
      this.onFile(desktopChangedPath(target.summary.cwd, file.path), desktopFileName(file.path), {
        sessionId: target.sessionId, sequence: target.sequence, summary: target.summary,
        index: this.selected, split: this.split, wrap: this.wrap
      });
    }
  }

  private lineBackground(kind?: string): ResourceColor {
    return kind === '+' ? $r('app.color.desktop_diff_added') :
      kind === '-' ? $r('app.color.desktop_diff_deleted') : Color.Transparent;
  }

  @Builder
  private DiffCode(text: string) {
    if (this.wrap) {
      Text(text).fontFamily('monospace').fontSize(12).width('100%').layoutWeight(1)
        .copyOption(CopyOptions.LocalDevice).wordBreak(WordBreak.BREAK_ALL)
    } else {
      Text(text).fontFamily('monospace').fontSize(12).maxLines(1).layoutWeight(1).copyOption(CopyOptions.LocalDevice)
    }
  }

  @Builder
  private Side(cell?: DesktopDiffCell) {
    Row({ space: 3 }) {
      if (this.diff?.showNumbers) {
        Text(cell === undefined ? '' : String(cell.number)).fontFamily('monospace').fontSize(11).width(33)
          .textAlign(TextAlign.End).fontColor($r('sys.color.font_tertiary'))
      }
      Text(cell?.kind ?? '').fontFamily('monospace').fontSize(12).width(12).textAlign(TextAlign.Center)
      this.DiffCode(cell?.text ?? '')
    }
    .padding({ left: 4, right: 7, top: 2, bottom: 2 }).alignItems(VerticalAlign.Top).layoutWeight(1)
    .backgroundColor(this.lineBackground(cell?.kind))
  }

  @Builder
  private DiffLine(row: DesktopDiffRow) {
    if (row.title) {
      Text(row.title).width('100%').fontFamily('monospace').fontSize(11)
        .fontColor($r('sys.color.font_secondary')).backgroundColor($r('app.color.workspace_panel'))
        .padding({ left: 8, top: 6, bottom: 6 })
    } else if (this.split && this.diff?.allowSplit) {
      Row() {
        this.Side(row.left)
        this.Side(row.right)
      }
      .width('100%').alignItems(VerticalAlign.Top)
    } else {
      Row({ space: 3 }) {
        if (this.diff?.showNumbers) {
          Text(row.left === undefined ? '' : String(row.left.number)).fontFamily('monospace').fontSize(11).width(31)
            .fontColor($r('sys.color.font_tertiary')).textAlign(TextAlign.End)
          Text(row.right === undefined ? '' : String(row.right.number)).fontFamily('monospace').fontSize(11).width(31)
            .fontColor($r('sys.color.font_tertiary')).textAlign(TextAlign.End)
        }
        Text(row.left?.kind ?? row.right?.kind ?? '').fontFamily('monospace').fontSize(12).width(12)
        this.DiffCode(row.left?.text ?? row.right?.text ?? '')
      }
      .width('100%').padding({ left: 4, right: 6, top: 2, bottom: 2 }).alignItems(VerticalAlign.Top)
      .backgroundColor(this.lineBackground(row.left?.kind ?? row.right?.kind))
    }
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 4 }) {
            Text(this.selectedFile()?.display ?? `第 ${this.target?.summary.turn ?? 0} 轮改动`)
              .fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).rotate({ angle: 90 })
          }.width('100%')
        }
        .layoutWeight(1).borderRadius(7).padding({ left: 8, right: 5 })
        .accessibilityDescription('选择要查看的文件').bindMenu(this.fileOptions(), desktopMenuOptions(Placement.BottomLeft))
        Button(this.split ? '单栏' : '双栏', { buttonStyle: ButtonStyleMode.TEXTUAL }).padding(5)
          .key('desktopDiffSplit').enabled(this.diff?.allowSplit === true)
          .onClick((): void => { this.split = !this.split; this.updateRows(); })
        Button(this.wrap ? '不换行' : '换行', { buttonStyle: ButtonStyleMode.TEXTUAL }).padding(5)
          .key('desktopDiffWrap').onClick((): void => { this.wrap = !this.wrap; })
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.doc_text')).fontSize(15)
        }
        .width(28).padding(0).enabled(this.selectedFile() !== undefined && !this.loading)
        .accessibilityText('在侧边栏打开整个文件').onClick((): void => { this.openFile(); })
        Button('×', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(29).padding(0)
          .key('desktopCloseChanges').accessibilityText('关闭改动审阅').onClick(this.onClose)
      }
      .width('100%').height(42).padding({ left: 6, right: 4 })
      .border({ width: { bottom: 1 }, color: $r('app.color.workspace_border') })
      if (this.loading) {
        LoadingProgress().width(24).height(24).margin(10).accessibilityText('正在读取改动')
      } else if (this.missing || this.error) {
        Row({ space: 7 }) {
          Text(this.missing ? '这轮改动的内容已不可用' : '无法读取改动').fontSize(13)
          if (this.error) {
            Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick((): void => { this.select(this.selected); })
          }
        }.padding(10)
      } else {
        if (this.diff?.notice) {
          Text(this.diff?.notice ?? '').fontSize(12).fontColor($r('sys.color.font_secondary'))
            .width('100%').padding(8)
        }
        Scroll() {
          List() {
            LazyForEach(this.rows, (row: DesktopDiffRow): void => {
              ListItem() { this.DiffLine(row) }
            }, (row: DesktopDiffRow): string => `${this.selected}:${this.split}:${row.id}`)
          }
          .width(this.wrap ? this.viewport : Math.max(this.viewport, this.lineWidth)).height('100%')
        }
        .width('100%').layoutWeight(1).align(Alignment.TopStart).scrollable(ScrollDirection.Horizontal)
        .onAreaChange((_old: Area, area: Area): void => {
          const next = Number(area.width);
          if (next > 0 && next !== this.viewport) {
            this.viewport = next;
          }
        })
      }
    }
    .height('100%').width('100%').backgroundColor($r('app.color.workspace_canvas'))
    .border({ width: { left: 1 }, color: $r('app.color.workspace_border') })
  }
}
