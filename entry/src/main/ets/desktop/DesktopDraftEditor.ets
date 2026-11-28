import { util } from '@kit.ArkTS';
import { LengthMetrics } from '@kit.ArkUI';
import { common2D, drawing, text } from '@kit.ArkGraphics2D';
import { resourceManager } from '@kit.LocalizationKit';
import type { DesktopComposerDraft, DesktopDraftReference } from './DesktopDraftReferences';

class ReferenceIconPath {
  readonly shape: drawing.Path = new drawing.Path();
  readonly filled: boolean;

  constructor(data: string, filled: boolean) {
    this.filled = filled;
    this.shape.buildFromSvgString(data);
  }
}

class DraftReferenceSpan extends CustomSpan {
  readonly wire: string;
  readonly reference: DesktopDraftReference;
  private readonly icon: ReferenceIconPath[];
  private readonly density: number;
  private readonly brush = new drawing.Brush();
  private readonly pen = new drawing.Pen();
  private readonly label: text.Paragraph;
  private readonly iconSize: number;
  private readonly labelStart: number;
  private readonly contentHeight: number;
  private layoutWidth: number = -1;

  constructor(wire: string, reference: DesktopDraftReference, icon: ReferenceIconPath[], density: number,
    fontSize: number, fontFamily: string, color: common2D.Color) {
    super();
    this.wire = wire;
    this.reference = reference;
    this.icon = icon;
    this.density = density;
    this.iconSize = 16 * density;
    this.labelStart = (icon.length > 0 ? 19 : 0) * density;
    this.contentHeight = Math.max(16, Math.ceil(fontSize / density));
    this.brush.setAntiAlias(true);
    this.brush.setColor(color);
    this.pen.setAntiAlias(true);
    this.pen.setColor(color);
    this.pen.setStrokeWidth(1);
    const style: text.TextStyle = { fontSize: fontSize, color: color, ellipsis: '…',
      fontFamilies: fontFamily ? fontFamily.split(',').map((name: string): string => name.trim()) : undefined };
    const layout: text.ParagraphStyle = { maxLines: 1, textStyle: style, wordBreak: text.WordBreak.BREAK_ALL };
    const builder = new text.ParagraphBuilder(layout, text.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(reference.label.replace(/[\r\n]/gu, ' '));
    this.label = builder.build();
  }

  onMeasure(info: CustomSpanMeasureInfo): CustomSpanMetrics {
    const limit = Math.min(info.maxWidth ?? Infinity, 240 * this.density);
    if (limit !== this.layoutWidth) {
      this.layoutWidth = limit;
      this.label.layoutSync(Math.max(0, limit - this.labelStart));
    }
    return { width: Math.min(limit, this.labelStart + Math.ceil(this.label.getMaxIntrinsicWidth())) / this.density,
      height: this.contentHeight };
  }

  onDraw(context: DrawContext, info: CustomSpanDrawInfo): void {
    const canvas = context.canvas;
    if (this.icon.length > 0) {
      canvas.save();
      canvas.translate(info.x, (info.lineTop + info.lineBottom - this.iconSize) / 2);
      canvas.scale(this.density, this.density);
      for (const path of this.icon) {
        if (path.filled) { canvas.attachBrush(this.brush); }
        else { canvas.attachPen(this.pen); }
        canvas.drawPath(path.shape);
        if (path.filled) { canvas.detachBrush(); }
        else { canvas.detachPen(); }
      }
      canvas.restore();
    }
    this.label.paint(canvas, info.x + this.labelStart, info.baseline - this.label.getAlphabeticBaseline());
  }
}

export class DesktopDraftEditor {
  readonly controller = new RichEditorStyledStringController();
  private readonly icons = new Map<string, ReferenceIconPath[]>();
  private readonly colors = new Map<boolean, common2D.Color>();

  private icon(ui: UIContext, kind: string): ReferenceIconPath[] {
    if (kind === 'skill') { return []; }
    const cached = this.icons.get(kind);
    if (cached !== undefined) { return cached; }
    const paths: ReferenceIconPath[] = [];
    const resource = kind === 'session' ? $r('app.media.dsh_inline_reference_session') :
      (kind === 'directory' ? $r('app.media.dsh_inline_reference_folder') : $r('app.media.dsh_inline_reference_file'));
    try {
      const bytes = ui.getHostContext()?.resourceManager.getMediaContentSync(resource.id);
      if (bytes !== undefined) {
        const svg = util.TextDecoder.create('utf-8').decodeToString(bytes);
        const pathPattern = /<path\b([^>]+)>/gu;
        let match = pathPattern.exec(svg);
        while (match !== null) {
          const data = /\bd="([^"]+)"/u.exec(match[1]);
          if (data !== null) { paths.push(new ReferenceIconPath(data[1], /\bfill="#/u.test(match[1]))); }
          match = pathPattern.exec(svg);
        }
      }
    } catch (_) {
      // The label remains editable when the resource cannot be loaded.
    }
    this.icons.set(kind, paths);
    return paths;
  }

  private color(ui: UIContext, dark: boolean): common2D.Color {
    const cached = this.colors.get(dark);
    if (cached !== undefined) { return cached; }
    const manager = ui.getHostContext()?.resourceManager;
    let value = dark ? 0x7AAAFF : 0x4176E6;
    if (manager !== undefined) {
      try {
        const config = manager.getConfigurationSync();
        config.colorMode = dark ? resourceManager.ColorMode.DARK : resourceManager.ColorMode.LIGHT;
        value = manager.getOverrideResourceManager(config).getColorSync($r('app.color.desktop_reference_text').id);
      } catch (_) {
        // Keep the reference readable while resource configuration is changing.
      }
    }
    const color: common2D.Color = { alpha: 255, red: (value >> 16) & 255, green: (value >> 8) & 255, blue: value & 255 };
    this.colors.set(dark, color);
    return color;
  }

  format(draft: DesktopComposerDraft, ui: UIContext, dark: boolean, size: number, family: string): StyledString {
    if (!draft.text) { return new StyledString(''); }
    const style: StyleOptions = { styledKey: StyledStringKey.FONT,
      styledValue: new TextStyle({ fontSize: LengthMetrics.fp(size), fontFamily: family }) };
    if (draft.references.length === 0) { return new StyledString(draft.text, [style]); }
    const value = new MutableStyledString('');
    const density = ui.vp2px(1);
    const fontSize = ui.fp2px(size);
    const color = this.color(ui, dark);
    let start = 0;
    for (const reference of draft.references) {
      if (reference.start > start) {
        value.appendStyledString(new StyledString(draft.text.slice(start, reference.start), [style]));
      }
      const wire = draft.text.slice(reference.start, reference.end);
      value.appendStyledString(new StyledString(new DraftReferenceSpan(wire, reference, this.icon(ui, reference.kind),
        density, fontSize, family, color)));
      start = reference.end;
    }
    if (start < draft.text.length) { value.appendStyledString(new StyledString(draft.text.slice(start), [style])); }
    return value;
  }

  read(): DesktopComposerDraft {
    const value = this.controller.getStyledString();
    const visible = value.getString();
    const references: DesktopDraftReference[] = [];
    let wire = '';
    let start = 0;
    if (value.length > 0) {
      const spans = value.getStyles(0, value.length, StyledStringKey.CUSTOM_SPAN);
      spans.sort((left: SpanStyle, right: SpanStyle): number => left.start - right.start);
      for (const style of spans) {
        const span = style.styledValue;
        if (!(span instanceof DraftReferenceSpan) || style.start < start) { continue; }
        wire += visible.slice(start, style.start);
        references.push({ start: wire.length, end: wire.length + span.wire.length,
          kind: span.reference.kind, label: span.reference.label });
        wire += span.wire;
        start = style.start + style.length;
      }
    }
    return { text: wire + visible.slice(start), references: references };
  }
}
