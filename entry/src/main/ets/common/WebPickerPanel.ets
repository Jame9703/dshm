export interface WebPickerRow {
  key: string;
  label: string;
  detail: string;
  group: string;
  selected: boolean;
  disabled: boolean;
  stay: boolean;
  drill: boolean;
}

export interface WebPickerPage {
  title: string;
  search: string;
  query: string;
  status: string;
  empty: string;
  rows: WebPickerRow[];
}

export interface WebPickerPanelParams {
  page: WebPickerPage;
  width: number;
  height: number;
  themeDark: boolean;
  search: (value: string) => void;
  select: (key: string) => void;
}

const EMPTY_PAGE: WebPickerPage = { title: '', search: '', query: '', status: '', empty: '', rows: [] };

@Component
struct WebPickerPanel {
  @Prop page: WebPickerPage = EMPTY_PAGE;
  @Prop panelWidth: number = 320;
  @Prop panelHeight: number = 320;
  search: (value: string) => void = () => {};
  select: (key: string) => void = () => {};

  @Builder
  pickerRow(row: WebPickerRow, index: number) {
    if (row.group.length > 0 && (index === 0 || this.page.rows[index - 1].group !== row.group)) {
      Text(row.group)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 4 })
    }
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(row.label)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (row.detail.length > 0) {
            Text(row.detail)
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (row.selected || row.drill) {
          Text(row.selected ? '✓' : '›')
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 42 })
    .borderRadius(8)
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .accessibilityText(row.detail.length > 0 ? row.label + ', ' + row.detail : row.label)
    .accessibilitySelected(row.selected)
    .enabled(!row.disabled)
    .onClick((): void => this.select(row.key))
  }

  build() {
    Column({ space: 6 }) {
      if (this.page.title.length > 0) {
        Text(this.page.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 10, right: 10, top: 4 })
      }
      if (this.page.search.length > 0) {
        TextInput({ text: this.page.query, placeholder: this.page.search })
          .type(InputType.Normal)
          .height(36)
          .maxLength(300)
          .onChange((value: string): void => this.search(value))
      }
      if (this.page.status.length > 0) {
        Text(this.page.status)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10 })
      }
      if (this.page.rows.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.page.rows, (row: WebPickerRow, index: number): void => {
              this.pickerRow(row, index)
            }, (row: WebPickerRow): string => row.key)
          }
          .width('100%')
        }
        .align(Alignment.TopStart)
        .width('100%')
        .constraintSize({ maxHeight: this.panelHeight })
        .scrollBar(BarState.Auto)
      } else if (this.page.empty.length > 0 && this.page.status.length === 0) {
        Text(this.page.empty)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding(10)
      }
    }
    .width(this.panelWidth)
    .padding(8)
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
export function buildWebPickerPanel(params: WebPickerPanelParams) {
  WithTheme({ colorMode: params.themeDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
    WebPickerPanel({
      page: params.page, panelWidth: params.width, panelHeight: params.height,
      search: params.search, select: params.select
    })
  }
}
