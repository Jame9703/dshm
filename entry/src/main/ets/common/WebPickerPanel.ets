import { uiMaterial } from '@kit.ArkUI';

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
  material: uiMaterial.ImmersiveMaterial | undefined;
  search: (value: string) => void;
  select: (key: string) => void;
}

@Observed
export class WebPickerPanelState {
  page: WebPickerPage;

  constructor(page: WebPickerPage) {
    this.page = page;
  }
}

@Component
struct WebPickerPanel {
  @ObjectLink model: WebPickerPanelState;
  @Prop panelWidth: number = 320;
  @Prop panelHeight: number = 320;
  search: (value: string) => void = () => {};
  select: (key: string) => void = () => {};

  @Builder
  pickerRow(row: WebPickerRow, index: number) {
    if (row.group.length > 0 && (index === 0 || this.model.page.rows[index - 1].group !== row.group)) {
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
      if (this.model.page.title.length > 0) {
        Text(this.model.page.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 10, right: 10, top: 4 })
      }
      if (this.model.page.search.length > 0) {
        TextInput({ text: this.model.page.query, placeholder: this.model.page.search })
          .type(InputType.Normal)
          .height(36)
          .maxLength(300)
          .onChange((value: string): void => this.search(value))
      }
      if (this.model.page.status.length > 0) {
        Text(this.model.page.status)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10 })
      }
      if (this.model.page.rows.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.model.page.rows, (row: WebPickerRow, index: number): void => {
              this.pickerRow(row, index)
            }, (row: WebPickerRow): string => row.key)
          }
          .width('100%')
        }
        .align(Alignment.TopStart)
        .width('100%')
        .constraintSize({ maxHeight: this.panelHeight })
        .scrollBar(BarState.Auto)
      } else if (this.model.page.empty.length > 0 && this.model.page.status.length === 0) {
        Text(this.model.page.empty)
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
export function buildWebPickerPanel(params: WebPickerPanelParams, model: WebPickerPanelState) {
  WithTheme({ colorMode: params.themeDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
    WebPickerPanel({
      model: model, panelWidth: params.width, panelHeight: params.height,
      search: params.search, select: params.select
    })
  }
}

@Builder
export function buildWebPickerMenu(params: WebPickerPanelParams) {
  WithTheme({ colorMode: params.themeDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
    Menu() {
      ForEach(params.page.rows, (row: WebPickerRow): void => {
        MenuItem({ content: row.detail.length > 0 ? row.label + '\n' + row.detail : row.label })
          .contentFont({ size: 14 })
          .selectIcon(true)
          .selected(row.selected)
          .accessibilityText(row.detail.length > 0 ? row.label + ', ' + row.detail : row.label)
          .accessibilitySelected(row.selected)
          .enabled(!row.disabled)
          .onClick((): void => params.select(row.key))
      }, (row: WebPickerRow): string => row.key)
    }
    .width(params.width)
  }
}
