export interface DesktopPaletteRow {
  id: string;
  title: string;
  detail: string;
  token: string;
  section: string;
}

@Component
export struct DesktopCommandPalette {
  @Prop rows: DesktopPaletteRow[] = [];
  @Prop highlight: number = 0;
  @Prop viewMode: string = '';
  @Prop filter: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop riskName: string = '';
  @Prop agreed: boolean = false;
  scroller: Scroller = new Scroller();
  onPick: (id: string) => void = (_id: string): void => {};
  onFilter: (value: string) => void = (_value: string): void => {};
  onRetry: () => void = (): void => {};
  onModelsSettings: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onAgree: (value: boolean) => void = (_value: boolean): void => {};
  onKey: (event: KeyEvent) => boolean = (_event: KeyEvent): boolean => false;

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
        if (this.viewMode !== 'commands') {
          TextInput({ text: this.filter, placeholder: this.viewMode === 'model' ? '搜索模型' : '搜索权限预设' })
            .height(35).width('100%').fontSize(13).key('desktopSlashSearch')
            .onChange(this.onFilter).onKeyPreIme(this.onKey)
        }
        if (this.loading) {
          LoadingProgress().width(20).height(20).margin(4)
        }
        if (this.error) {
          Row({ space: 5 }) {
            Text(this.error).fontSize(12).fontColor($r('sys.color.warning')).layoutWeight(1)
            Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(this.onRetry)
          }.width('100%')
        } else if (!this.loading && this.rows.length === 0) {
          if (this.viewMode === 'model' && !this.filter.trim()) {
            Button($r('app.string.desktop_chat_model_settings'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick(this.onModelsSettings)
          } else {
            Text('无匹配选项').fontSize(13).fontColor($r('sys.color.font_secondary')).padding(8)
          }
        }
        if (this.rows.length > 0) {
          List({ scroller: this.scroller }) {
            ForEach(this.rows, (row: DesktopPaletteRow, index: number): void => {
              ListItem() {
                Column({ space: 2 }) {
                  if (row.section && (index === 0 || this.rows[index - 1].section !== row.section)) {
                    Text(row.section).fontSize(11).width('100%').fontColor($r('sys.color.font_secondary')).padding(5)
                  }
                  Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
                    Row({ space: 7 }) {
                      SymbolGlyph(this.viewMode === 'commands' ? $r('sys.symbol.chevron_right') : $r('sys.symbol.circle'))
                        .fontSize(11).fontColor([$r('sys.color.font_secondary')])
                      Column({ space: 2 }) {
                        Text(row.title).fontSize(13).fontColor($r('sys.color.font_primary')).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        if (row.detail) {
                          Text(row.detail).fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                      if (row.token) {
                        Text(row.token).fontSize(11).fontColor($r('sys.color.font_secondary')).maxLines(1)
                      }
                    }.width('100%')
                  }.width('100%').height(row.detail ? 41 : 34).padding({ left: 7, right: 7 }).borderRadius(7)
                  .backgroundColor(this.highlight === index ? $r('app.color.workspace_selection') : Color.Transparent)
                  .onClick((): void => { this.onPick(row.id); })
                }.width('100%')
              }
            }, (row: DesktopPaletteRow): string => `${row.id}:${row.section}:${row.detail}`)
          }.width('100%').constraintSize({ maxHeight: 244 }).scrollBar(BarState.Auto)
        }
      }
    }.alignItems(HorizontalAlign.Start).width(316).padding(9)
  }
}
