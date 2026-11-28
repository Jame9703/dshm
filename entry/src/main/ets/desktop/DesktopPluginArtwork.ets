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
  @Prop artworkSize: number = 36;
  @State private failed: boolean = false;

  private iconChanged(): void { this.failed = false; }

  private image(): ResourceStr {
    if (this.icon && !this.failed) {
      if (!this.icon.startsWith(SVG_DATA)) { return this.icon; }
      // ArkUI can render the reviewed bundled vectors as resources, but not through an SVG data URL.
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
