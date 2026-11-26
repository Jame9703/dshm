@Entry
@Component
struct Host {
  build() {
    Column() {
      Text('host').fontSize(12).fontColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .justifyContent(FlexAlign.Center)
  }
}
