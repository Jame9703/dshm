import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { desktopPluginSvg } from './DesktopPluginSvg';

const ICON_DATA = new RegExp('^data:image/(png|jpeg|webp|svg\\+xml);base64,[a-zA-Z0-9+/=]+$');
const MAX_ICON_URL: number = 349568;
const SVG_DATA: string = 'data:image/svg+xml;base64,';
const CODEX: string = '@deepseek-ai/dsh-subagent-codex';
const CLAUDE: string = '@deepseek-ai/dsh-subagent-claude-code';

export function desktopPluginIcon(value: string): string {
  return value.length <= MAX_ICON_URL && ICON_DATA.test(value) ? value : '';
}

@Component
export struct DesktopPluginArtwork {
  @Prop @Watch('iconChanged') icon: string = '';
  @Prop packageName: string = '';
  @Prop component: boolean = false;
  @Prop @Watch('iconChanged') artworkSize: number = 36;
  @State private failed: boolean = false;
  @State private picture?: image.PixelMap = undefined;
  private active: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.iconChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.generation++;
    this.releasePicture();
  }

  private releasePicture(): void {
    const picture = this.picture;
    this.picture = undefined;
    picture?.release().catch((): void => {});
  }

  private iconChanged(): void {
    const generation = ++this.generation;
    this.failed = false;
    this.releasePicture();
    if (this.active && this.icon.startsWith(SVG_DATA)) {
      const pixels = Math.max(1, Math.min(144, Math.ceil(this.getUIContext().vp2px(this.artworkSize))));
      this.decodeSvg(this.icon, pixels, generation).then((picture?: image.PixelMap): void => {
        if (this.active && this.generation === generation) { this.picture = picture; }
        else { picture?.release().catch((): void => {}); }
      });
    }
  }

  private async decodeSvg(icon: string, pixels: number, generation: number): Promise<image.PixelMap | undefined> {
    let source: image.ImageSource | undefined;
    try {
      const bytes = await new util.Base64Helper().decode(icon.slice(SVG_DATA.length));
      if (!this.active || this.generation !== generation) { return undefined; }
      const input = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(input).set(bytes);
      const sanitized = desktopPluginSvg(input);
      if (sanitized === undefined) { return undefined; }
      source = image.createImageSource(sanitized);
      if (source === undefined) { return undefined; }
      const info = await source.getImageInfo();
      if (!this.active || this.generation !== generation) { return undefined; }
      const width = info.size.width;
      const height = info.size.height;
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return undefined; }
      const scale = pixels / Math.max(width, height);
      return await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale))
      } });
    } catch (_) {
      return undefined;
    } finally {
      await source?.release().catch((): void => {});
    }
  }

  private image(): ResourceStr | image.PixelMap {
    if (this.picture !== undefined) { return this.picture; }
    if (this.icon && !this.failed) {
      if (!this.icon.startsWith(SVG_DATA)) { return this.icon; }
      // Keep the bundled artwork available while the SVG is decoding or if it cannot be decoded.
      if (this.packageName === CODEX || this.packageName === CLAUDE) {
        return $r('app.media.dsh_plugin_artwork_external_agent');
      }
    }
    return this.component ? $r('app.media.dsh_plugin_artwork_subagent') : $r('app.media.dsh_plugin_artwork_component');
  }

  build() {
    Image(this.image()).width(this.artworkSize).height(this.artworkSize).objectFit(ImageFit.Contain)
      .supportSvg2(true).draggable(false).accessibilityLevel('no')
      .onError((): void => { this.failed = true; })
  }
}
