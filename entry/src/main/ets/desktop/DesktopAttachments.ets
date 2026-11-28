import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { formatBytes } from 'appstate';
import type { PendingAttachment } from 'appstate';
import { getArray, getNumber, getRecord, getString } from 'connection';
import { DesktopHostActions } from './DesktopHostActions';
import { desktopFileTypeIcon } from './DesktopFileType';

export interface DesktopMediaAttachment {
  id: string;
  name: string;
  bytes: number;
  image: boolean;
  width?: number;
  height?: number;
  reference?: Object;
  draftImageSource?: string;
}

export interface DesktopDraftAttachment extends PendingAttachment {
  picture?: DesktopMediaAttachment;
}

export async function desktopDraftGif(bytes: ArrayBuffer): Promise<string> {
  return 'data:image/gif;base64,' + await new util.Base64Helper().encodeToString(new Uint8Array(bytes));
}

export function desktopImageMime(mime: string): boolean {
  return mime === 'image/png' || mime === 'image/jpeg' || mime === 'image/webp' || mime === 'image/gif';
}

export function desktopMediaAttachment(reference: Object | undefined, picture: boolean): DesktopMediaAttachment | undefined {
  const id = getString(reference, 'attachmentId') ?? '';
  if (!id) { return undefined; }
  return { id: id, name: getString(reference, 'name') || (picture ? '图片' : '附件'),
    bytes: getNumber(reference, 'bytes') ?? 0, image: picture,
    width: getNumber(reference, 'width'), height: getNumber(reference, 'height'), reference: reference };
}

export function desktopMessageAttachments(message?: Object): DesktopMediaAttachment[] {
  const result: DesktopMediaAttachment[] = [];
  for (const part of getArray(message, 'content') ?? []) {
    const type = getString(part, 'type');
    if (type !== 'file' && type !== 'image') { continue; }
    const attachment = desktopMediaAttachment(getRecord(part, 'attachment'), type === 'image');
    if (attachment !== undefined) { result.push(attachment); }
  }
  return result;
}

async function readImage(host: DesktopHostActions | undefined, sessionId: string, row: DesktopMediaAttachment,
  edge: number): Promise<image.PixelMap | undefined> {
  if (host === undefined || row.reference === undefined) { return undefined; }
  const responseLimit = row.bytes > 0 ? Math.min(100 * 1024 * 1024, Math.ceil(row.bytes / 3) * 4 + 4096) : undefined;
  const result = await host.call('session/attachment', { 'sessionId': sessionId, 'attachment': row.reference },
    30000, responseLimit);
  const data = result.ok ? getString(result.value, 'data') : undefined;
  if (!data) { return undefined; }
  try {
    const bytes = await new util.Base64Helper().decode(data);
    const array = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(array).set(bytes);
    const source = image.createImageSource(array);
    try {
      const info = await source.getImageInfo();
      const ratio = Math.min(1, edge / Math.max(info.size.width, info.size.height));
      return await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(info.size.width * ratio)),
        height: Math.max(1, Math.round(info.size.height * ratio))
      } });
    } finally {
      await source.release();
    }
  } catch (_) {
    return undefined;
  }
}

@Component
export struct DesktopAttachmentThumbnail {
  @Prop sessionId: string = '';
  @Prop attachment: DesktopMediaAttachment | undefined = undefined;
  @Prop maxEdge: number = 112;
  @Prop nodeKey: string = '';
  @Prop compactPreview: boolean = false;
  host?: DesktopHostActions;
  onOpen: (attachment: DesktopMediaAttachment) => void = (_attachment: DesktopMediaAttachment): void => {};
  @State private picture: image.PixelMap | undefined = undefined;
  private active: boolean = false;
  private requested: boolean = false;

  aboutToAppear(): void { this.active = true; }

  aboutToDisappear(): void {
    this.active = false;
    this.picture?.release().catch((): void => {});
  }

  private async load(): Promise<void> {
    const row = this.attachment;
    if (!this.active || this.requested || row === undefined) { return; }
    this.requested = true;
    if (row.draftImageSource) { return; }
    const picture = await readImage(this.host, this.sessionId, row, this.maxEdge * 3);
    if (this.active) { this.picture = picture; }
    else { picture?.release().catch((): void => {}); }
  }

  private extent(width: boolean): number {
    const w = this.attachment?.width || this.maxEdge;
    const h = this.attachment?.height || this.maxEdge;
    return Math.max(24, Math.round((width ? w : h) * Math.min(1, this.maxEdge / Math.max(w, h))));
  }

  @Builder
  private Picture() {
    if (this.attachment?.draftImageSource || this.picture !== undefined) {
      Image(this.attachment?.draftImageSource ?? this.picture).key(this.nodeKey + '-image').width('100%').height('100%')
        .objectFit(this.compactPreview ? ImageFit.Cover : ImageFit.Contain).draggable(false).accessibilityLevel('no')
    }
  }

  build() {
    if (this.compactPreview) {
      Stack() {
        this.Picture()
      }.key(this.nodeKey).width(24).height(24).borderRadius(4)
        .border({ width: 0.5, color: $r('app.color.workspace_border') })
        .backgroundColor($r('app.color.workspace_panel')).clip(true)
        .accessibilityText($r('app.string.desktop_queue_image'))
        .onVisibleAreaChange([0.01], (visible: boolean): void => { if (visible) { this.load(); } })
    } else {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.Picture()
        if (!this.attachment?.draftImageSource && this.picture === undefined) {
          SymbolGlyph($r('sys.symbol.picture')).fontSize(this.maxEdge <= 48 ? 14 : 22)
            .fontColor([$r('sys.color.font_tertiary')]).accessibilityLevel('no')
        }
      }.key(this.nodeKey).width(this.extent(true)).height(this.extent(false)).padding(0).borderRadius(8)
        .backgroundColor($r('app.color.workspace_panel')).clip(true).focusOnTouch(false)
        .accessibilityText((this.attachment?.name ?? '图片') + '，点击查看原图')
        .onVisibleAreaChange([0.01], (visible: boolean): void => { if (visible) { this.load(); } })
        .onClick((): void => { if (this.attachment !== undefined) { this.onOpen(this.attachment); } })
    }
  }
}

@Component
export struct DesktopAttachmentFile {
  @Prop filename: string = '';
  @Prop bytes: number = 0;

  build() {
    Row({ space: 5 }) {
      Image(desktopFileTypeIcon(this.filename)).width(16).height(16).supportSvg2(true)
        .draggable(false).accessibilityLevel('no')
      Text(this.filename).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 138 })
      Text(formatBytes(this.bytes)).fontSize(11).fontColor($r('sys.color.font_tertiary'))
    }.padding(5).borderRadius(6).border({ width: 1, color: $r('app.color.workspace_border') })
  }
}

@Component
export struct DesktopAttachmentViewer {
  @Prop sessionId: string = '';
  @Prop attachment: DesktopMediaAttachment | undefined = undefined;
  @Prop viewportHeight: number = 460;
  host?: DesktopHostActions;
  onClose: () => void = (): void => {};
  @State private picture: image.PixelMap | undefined = undefined;
  @State private loading: boolean = true;
  @State private zoom: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  private startZoom: number = 1;
  private startX: number = 0;
  private startY: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.picture?.release().catch((): void => {});
  }

  private async load(): Promise<void> {
    const row = this.attachment;
    if (row?.draftImageSource) { this.loading = false; return; }
    const picture = row === undefined ? undefined : await readImage(this.host, this.sessionId, row, 2048);
    if (this.active) { this.picture = picture; this.loading = false; }
    else { picture?.release().catch((): void => {}); }
  }

  private adjustZoom(zoom: number): void {
    this.zoom = Math.max(1, Math.min(4, zoom));
    if (this.zoom === 1) { this.offsetX = 0; this.offsetY = 0; }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        Text(this.attachment?.name ?? '查看原图').key('desktopImageViewerTitle').fontSize(17)
          .fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('−', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(34).height(34).padding(0).fontSize(18)
          .key('desktopImageZoomOut').accessibilityText('缩小').enabled((!!this.attachment?.draftImageSource || this.picture !== undefined) && this.zoom > 1)
          .onClick((): void => { this.adjustZoom(this.zoom / 1.5); })
        Button(`${Math.round(this.zoom * 100)}%`, { buttonStyle: ButtonStyleMode.TEXTUAL }).height(34)
          .key('desktopImageZoomReset').accessibilityText('还原尺寸')
          .onClick((): void => { this.adjustZoom(1); })
        Button('+', { buttonStyle: ButtonStyleMode.TEXTUAL }).width(34).height(34).padding(0).fontSize(18)
          .key('desktopImageZoomIn').accessibilityText('放大').enabled((!!this.attachment?.draftImageSource || this.picture !== undefined) && this.zoom < 4)
          .onClick((): void => { this.adjustZoom(this.zoom * 1.5); })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_dock_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.key('desktopImageViewerClose').width(34).height(34).padding(0).accessibilityText('关闭').onClick(this.onClose)
      }.width('100%')
      Stack() {
        if (this.attachment?.draftImageSource || this.picture !== undefined) {
          Image(this.attachment?.draftImageSource ?? this.picture).key('desktopImageViewerPicture').width('100%').height('100%')
            .objectFit(ImageFit.Contain).draggable(false)
            .scale({ x: this.zoom, y: this.zoom }).translate({ x: this.offsetX, y: this.offsetY })
            .gesture(GestureGroup(GestureMode.Parallel,
              PinchGesture().onActionStart((): void => { this.startZoom = this.zoom; })
                .onActionUpdate((event: GestureEvent): void => { this.adjustZoom(this.startZoom * event.scale); }),
              PanGesture().onActionStart((): void => { this.startX = this.offsetX; this.startY = this.offsetY; })
                .onActionUpdate((event: GestureEvent): void => {
                  if (this.zoom > 1) {
                    const bound = this.viewportHeight * (this.zoom - 1) / 2;
                    this.offsetX = Math.max(-bound, Math.min(bound, this.startX + event.offsetX));
                    this.offsetY = Math.max(-bound, Math.min(bound, this.startY + event.offsetY));
                  }
                })
            ))
        } else if (this.loading) {
          LoadingProgress().width(24).height(24).accessibilityText('正在加载图片')
        } else {
          Text('无法加载图片').fontSize(14).fontColor($r('sys.color.font_secondary'))
        }
      }.width('100%').height(this.viewportHeight).clip(true).borderRadius(10)
    }.width('100%').padding(16)
  }
}
