import type { DesktopReferenceCrumb } from './DesktopReferences';

export interface DesktopPaletteRow {
  id: string;
  title: string;
  detail: string;
  token: string;
  section: string;
  icon?: Resource;
  drill?: boolean;
  userOnly?: boolean;
}

@Component
export struct DesktopCommandPalette {
  @Prop rows: DesktopPaletteRow[] = [];
  @Prop highlight: number = 0;
  @Prop viewMode: string = '';
  @Prop crumbs: DesktopReferenceCrumb[] = [];
  @Prop filter: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop skillError: boolean = false;
  @Prop riskName: string = '';
  @Prop agreed: boolean = false;
  scroller: Scroller = new Scroller();
  onPick: (id: string) => void = (_id: string): void => {};
  onDrill: (id: string) => void = (_id: string): void => {};
  onCrumb: (text: string) => void = (_text: string): void => {};
  onFilter: (value: string) => void = (_value: string): void => {};
  onRetry: () => void = (): void => {};
  onModelsSettings: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onAgree: (value: boolean) => void = (_value: boolean): void => {};
  onKey: (event: KeyEvent) => boolean = (_event: KeyEvent): boolean => false;

  @Builder
  private ReferenceRow(row: DesktopPaletteRow, index: number) {
    Column() {
      if (index === 0 || this.rows[index - 1].section !== row.section) {
        Text(row.section).height(24).fontSize(11).width('100%')
          .fontColor($r('sys.color.font_secondary')).padding({ left: 5 })
      }
      Row({ space: 2 }) {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 7 }) {
            Image(row.icon).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
            Text(row.title).fontSize(13).fontColor($r('sys.color.font_primary')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            if (row.detail) {
              Text(row.detail).fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 95 })
            }
          }.width('100%')
        }.key('desktopPaletteChoice-' + index).layoutWeight(1).height(34)
          .padding({ left: 7, right: 7 }).borderRadius(7).focusOnTouch(false)
          .onClick((): void => { this.onPick(row.id); })
        if (row.drill === true) {
          Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12)
              .fontColor([$r('sys.color.font_secondary')]).accessibilityLevel('no')
          }.key('desktopReferenceDrill-' + index).width(28).height(28).padding(0).focusOnTouch(false)
            .accessibilityText('打开文件夹 ' + row.title).onClick((): void => { this.onDrill(row.id); })
        }
      }.width('100%').borderRadius(7)
        .backgroundColor(this.highlight === index ? $r('app.color.workspace_selection') : Color.Transparent)
    }.width('100%')
  }

  build() {
    Column({ space: 4 }) {
      if (this.riskName) {
        Text(`确认启用${this.riskName}？`).fontSize(15).fontWeight(FontWeight.Medium)
        Text('启用此预设后，某些操作可以在较少的确认步骤下执行。').fontSize(13)
          .fontColor($r('sys.color.font_secondary')).width('100%')
        Row({ space: 5 }) {
          Checkbox().select(this.agreed).onChange(this.onAgree)
          Text('我已了解风险，并愿意继续').fontSize(13)
        }.width('100%')
        Row({ space: 6 }) {
          Blank()
          Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(this.onBack)
          Button('启用').enabled(this.agreed).onClick((): void => { this.onPick('confirm'); })
        }.width('100%')
      } else {
        if (this.viewMode === 'reference' && this.crumbs.length > 0) {
          Scroll() {
            Row({ space: 2 }) {
              ForEach(this.crumbs, (crumb: DesktopReferenceCrumb, index: number): void => {
                if (index > 0) {
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).accessibilityLevel('no')
                }
                Button(crumb.label, { buttonStyle: ButtonStyleMode.TEXTUAL }).height(26).fontSize(11).padding(4)
                  .focusOnTouch(false).enabled(index < this.crumbs.length - 1)
                  .onClick((): void => { this.onCrumb(crumb.text); })
              }, (crumb: DesktopReferenceCrumb): string => crumb.text)
            }
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }
        if (this.viewMode === 'model' || this.viewMode === 'permission') {
          TextInput({ text: this.filter, placeholder: this.viewMode === 'model' ? '搜索模型' : '搜索权限预设' })
            .height(35).width('100%').fontSize(13).key('desktopSlashSearch')
            .onChange(this.onFilter).onKeyPreIme(this.onKey)
        }
        if (this.loading) {
          LoadingProgress().width(20).height(20).margin(4)
        }
        if (this.error || this.skillError) {
          Row({ space: 5 }) {
            Text(this.error || $r('app.string.desktop_skills_failed'))
              .fontSize(12).fontColor($r('sys.color.warning')).layoutWeight(1)
            Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(this.onRetry)
          }.width('100%')
        } else if (!this.loading && this.rows.length === 0) {
          if (this.viewMode === 'model' && !this.filter.trim()) {
            Button($r('app.string.desktop_chat_model_settings'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick(this.onModelsSettings)
          } else {
            Text(this.viewMode === 'reference' ? '没有匹配的引用' : '无匹配选项').fontSize(13).fontColor($r('sys.color.font_secondary')).padding(8)
          }
        }
        if (this.rows.length > 0 && this.viewMode === 'reference') {
          Scroll(this.scroller) {
            Column() {
              ForEach(this.rows, (row: DesktopPaletteRow, index: number): void => {
                this.ReferenceRow(row, index)
              }, (row: DesktopPaletteRow): string => row.id + ':' + row.detail)
            }.width('100%')
          }.width('100%').constraintSize({ maxHeight: 244 }).scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
        } else if (this.rows.length > 0) {
          List({ scroller: this.scroller }) {
            ForEach(this.rows, (row: DesktopPaletteRow, index: number): void => {
              ListItem() {
                Column({ space: 2 }) {
                  if (row.section && (index === 0 || this.rows[index - 1].section !== row.section)) {
                    Text(row.section === 'skill' ? $r('app.string.desktop_skills_label') : row.section)
                      .fontSize(11).width('100%').fontColor($r('sys.color.font_secondary')).padding(5)
                  }
                  Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
                    Row({ space: 7 }) {
                      if (row.section !== 'skill') {
                        SymbolGlyph(this.viewMode === 'commands' ? $r('sys.symbol.chevron_right') : $r('sys.symbol.circle'))
                          .fontSize(11).fontColor([$r('sys.color.font_secondary')])
                      }
                      Column({ space: 2 }) {
                        Text(row.title).fontSize(13).fontColor($r('sys.color.font_primary')).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        if (row.detail || row.userOnly === true) {
                          Text() {
                            if (row.userOnly === true) {
                              Span($r('app.string.desktop_skills_user_only'))
                            }
                            if (row.userOnly === true && row.detail) { Span(' · ') }
                            if (row.detail) { Span(row.detail) }
                          }.fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                      if (row.token) {
                        Text(row.token).fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
                      }
                    }.width('100%')
                  }.key('desktopSlashOption-' + row.id).width('100%').height(row.detail || row.userOnly ? 41 : 34)
                  .padding({ left: 7, right: 7 }).borderRadius(7)
                  .backgroundColor(this.highlight === index ? $r('app.color.workspace_selection') : Color.Transparent)
                  .onClick((): void => { this.onPick(row.id); })
                }.width('100%')
              }
            }, (row: DesktopPaletteRow): string => row.id + ':' + row.section + ':' + row.detail + ':' + row.userOnly)
          }.width('100%').constraintSize({ maxHeight: 244 }).scrollBar(BarState.Auto)
        }
      }
    }.alignItems(HorizontalAlign.Start).width(316).padding(9)
  }
}
