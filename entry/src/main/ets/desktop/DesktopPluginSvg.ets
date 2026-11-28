import { convertxml, util } from '@kit.ArkTS';
import { getArray, getRecord, getString } from 'connection';

export const DESKTOP_PLUGIN_SVG_MAX_BYTES: number = 256 * 1024;
const MAX_DIMENSION: number = 512;
const MAX_COORDINATE: number = 1000000;
const MAX_ELEMENTS: number = 384;
const MAX_DEPTH: number = 24;
const MAX_REFERENCES: number = 128;
const MAX_REFERENCE_DEPTH: number = 8;
const SVG_NAMESPACE: string = 'http://www.w3.org/2000/svg';

const XML_OPTIONS: convertxml.ConvertOptions = {
  trim: true, ignoreDeclaration: true, ignoreInstruction: true, ignoreComment: true,
  ignoreCDATA: true, ignoreDoctype: true, ignoreText: true,
  declarationKey: 'declaration', instructionKey: 'instruction', attributesKey: 'attributes', textKey: 'text',
  cdataKey: 'cdata', doctypeKey: 'doctype', commentKey: 'comment', parentKey: 'parent',
  typeKey: 'kind', nameKey: 'tag', elementsKey: 'children'
};

const TAGS = new Set<string>([
  'svg', 'g', 'defs', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon',
  'linearGradient', 'radialGradient', 'stop', 'clipPath', 'mask'
]);
const DEFINITIONS = new Set<string>(['linearGradient', 'radialGradient', 'clipPath', 'mask']);
const METADATA = new Set<string>(['title', 'desc', 'metadata']);
const COLORS = new Set<string>(['fill', 'stroke', 'color', 'stop-color']);
const SCALARS = new Set<string>([
  'x', 'y', 'x1', 'x2', 'y1', 'y2', 'cx', 'cy', 'fx', 'fy', 'r', 'rx', 'ry', 'fr', 'width', 'height',
  'opacity', 'fill-opacity', 'stroke-opacity', 'stop-opacity', 'stroke-width', 'stroke-miterlimit',
  'stroke-dashoffset', 'offset', 'pathLength'
]);
const KEYWORDS = new Set<string>([
  'fill-rule', 'clip-rule', 'stroke-linecap', 'stroke-linejoin', 'vector-effect', 'visibility', 'display',
  'gradientUnits', 'clipPathUnits', 'maskUnits', 'maskContentUnits', 'mask-type', 'spreadMethod',
  'shape-rendering', 'preserveAspectRatio'
]);
const INLINE_PRESENTATION = new Set<string>([
  'fill', 'stroke', 'color', 'stop-color', 'fill-opacity', 'stroke-opacity', 'stop-opacity', 'opacity',
  'stroke-width', 'stroke-miterlimit', 'stroke-linecap', 'stroke-linejoin', 'stroke-dasharray',
  'stroke-dashoffset', 'fill-rule', 'clip-rule', 'clip-path', 'mask', 'vector-effect', 'visibility', 'display'
]);

const XML_HEADER = new RegExp('^\\s*<\\?xml\\s[^?]*\\?>');
const XML_COMMENT = new RegExp('<!--[\\s\\S]*?-->', 'g');
const XML_CONTROL = new RegExp('[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f]');
const IDENTIFIER = new RegExp('^[A-Za-z_][A-Za-z0-9_.:-]{0,63}$');
const FRAGMENT = new RegExp("^url\\(\\s*(['\"]?)#([A-Za-z_][A-Za-z0-9_.:-]{0,63})\\1\\s*\\)$");
const SIMPLE_COLOR = new RegExp('^(?:[A-Za-z][A-Za-z-]{0,24}|#[0-9a-fA-F]{3,8})$');
const COMPONENT_COLOR = new RegExp('^(?:rgb|rgba|hsl|hsla)\\([0-9Ee.,%+\\-\\s]+\\)$', 'i');
const NUMBER = new RegExp('[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[Ee][+-]?\\d+)?', 'g');
const SCALAR = new RegExp('^[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[Ee][+-]?\\d+)?(?:px|%)?$');
const NUMBERS_ONLY = new RegExp('^[0-9Ee.,%+\\-\\s]+$');
const PATH_COMMANDS = new RegExp('^[MmZzLlHhVvCcSsQqTtAa0-9Ee.,+\\-\\s]+$');
const TRANSFORM_PART = new RegExp('^(?:,\\s*)?(?:matrix|translate|scale|rotate|skewX|skewY)\\s*\\([0-9Ee.,+\\-\\s]+$');
const SAFE_KEYWORDS = new RegExp('^[A-Za-z][A-Za-z0-9\\- ]{0,35}$');
const SEPARATORS = new RegExp('[\\s,]+');

interface DesktopSvgViewport {
  width: number;
  height: number;
  viewBox: string;
}

interface DesktopSvgReference {
  owner: string;
  target: string;
  property: string;
}

function boundedNumbers(value: string, limit: number): boolean {
  const tokens = value.match(NUMBER);
  return tokens !== null && tokens.length <= limit &&
    tokens.every((token: string): boolean => Math.abs(Number(token)) <= MAX_COORDINATE);
}

function boundedTransform(value: string): boolean {
  if (!value.endsWith(')') || value.length > 1024) { return false; }
  const parts = value.slice(0, -1).split(')');
  return parts.length <= 16 && parts.every((part: string): boolean => TRANSFORM_PART.test(part.trim())) &&
    boundedNumbers(value, 48);
}

function pixelSize(value?: string): number {
  if (value === undefined) { return 0; }
  const raw = value.trim();
  if (!SCALAR.test(raw) || raw.endsWith('%')) { return 0; }
  const size = Number(raw.endsWith('px') ? raw.slice(0, -2) : raw);
  return size > 0 && size <= MAX_COORDINATE ? size : 0;
}

function inlinePresentation(value?: string): Map<string, string> | undefined {
  if (!value || value.length > 4096) { return undefined; }
  const declarations = value.split(';');
  if (declarations.length > 32) { return undefined; }
  const output = new Map<string, string>();
  for (const declaration of declarations) {
    const separator = declaration.indexOf(':');
    if (separator < 1) { continue; }
    const key = declaration.slice(0, separator).trim().toLowerCase();
    const setting = declaration.slice(separator + 1).trim();
    if (setting && INLINE_PRESENTATION.has(key)) { output.set(key, setting); }
  }
  return output;
}

function svgViewport(attributes: Object | undefined): DesktopSvgViewport | undefined {
  let width = pixelSize(getString(attributes, 'width'));
  let height = pixelSize(getString(attributes, 'height'));
  const raw = getString(attributes, 'viewBox')?.trim() ?? '';
  let viewBox = '';
  if (raw) {
    const parts = raw.split(SEPARATORS);
    if (parts.length !== 4 || !parts.every((part: string): boolean =>
      SCALAR.test(part) && !part.endsWith('px') && !part.endsWith('%') && Math.abs(Number(part)) <= MAX_COORDINATE)) {
      return undefined;
    }
    const boxWidth = Number(parts[2]);
    const boxHeight = Number(parts[3]);
    if (boxWidth <= 0 || boxHeight <= 0) { return undefined; }
    if (width === 0) { width = height === 0 ? boxWidth : height * boxWidth / boxHeight; }
    if (height === 0) { height = width * boxHeight / boxWidth; }
    viewBox = parts.join(' ');
  } else if (width > 0 && height > 0) {
    viewBox = '0 0 ' + width.toString() + ' ' + height.toString();
  }
  if (!viewBox || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return undefined; }
  const scale = Math.min(1, MAX_DIMENSION / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)), viewBox: viewBox };
}

/** Reserialize a finite scene; only the serializer's admitted tags and attributes reach ImageKit. */
class DesktopSvgDocument {
  private readonly ids = new Set<string>();
  private readonly definitions = new Map<string, string>();
  private readonly references: DesktopSvgReference[] = [];
  private readonly dependencies = new Map<string, string[]>();
  private nodes: number = 0;

  render(root: Object): string | undefined {
    if (getString(root, 'kind') !== 'element' || getString(root, 'tag') !== 'svg') { return undefined; }
    const viewport = svgViewport(getRecord(root, 'attributes'));
    if (viewport === undefined) { return undefined; }
    const result = this.element(root, '', 0, viewport);
    return result !== undefined && this.validReferences() ? result : undefined;
  }

  private element(node: Object, owner: string, depth: number, viewport?: DesktopSvgViewport): string | undefined {
    const tag = getString(node, 'tag') ?? '';
    if (getString(node, 'kind') !== 'element') { return undefined; }
    if (METADATA.has(tag)) { return ''; }
    if (!TAGS.has(tag) || (depth > 0 && tag === 'svg') || ++this.nodes > MAX_ELEMENTS || depth > MAX_DEPTH) {
      return undefined;
    }
    const attrs = getRecord(node, 'attributes');
    const id = getString(attrs, 'id') ?? '';
    let currentOwner = owner;
    if (id) {
      if (!IDENTIFIER.test(id) || this.ids.has(id)) { return undefined; }
      this.ids.add(id);
      if (DEFINITIONS.has(tag)) {
        if (owner) { return undefined; }
        this.definitions.set(id, tag);
        currentOwner = id;
      }
    }
    const parts: string[] = ['<' + tag];
    if (viewport !== undefined) {
      parts.push(' xmlns="' + SVG_NAMESPACE + '" width="' + viewport.width.toString() + '" height="' +
        viewport.height.toString() + '" viewBox="' + viewport.viewBox + '"');
    }
    if (attrs !== undefined) {
      const presentation = inlinePresentation(getString(attrs, 'style'));
      for (const key of Object.keys(attrs)) {
        if (presentation?.has(key) === true) { continue; }
        if (viewport !== undefined && (key === 'width' || key === 'height' || key === 'viewBox')) { continue; }
        const value = getString(attrs, key)?.trim() ?? '';
        if (value && !this.attribute(parts, key, value, currentOwner)) { return undefined; }
      }
      if (presentation !== undefined) {
        for (const key of presentation.keys()) {
          const value = presentation.get(key);
          if (value !== undefined && !this.attribute(parts, key, value, currentOwner)) { return undefined; }
        }
      }
    }
    parts.push('>');
    for (const child of getArray(node, 'children') ?? []) {
      const result = this.element(child, currentOwner, depth + 1);
      if (result === undefined) { return undefined; }
      parts.push(result);
    }
    parts.push('</' + tag + '>');
    return parts.join('');
  }

  private attribute(parts: string[], key: string, value: string, owner: string): boolean {
    let admitted = false;
    if (COLORS.has(key) || key === 'clip-path' || key === 'mask') {
      const fragment = FRAGMENT.exec(value);
      if (fragment !== null) {
        if ((key === 'color' || key === 'stop-color') || this.references.length >= MAX_REFERENCES) { return false; }
        if (owner && (key === 'clip-path' || key === 'mask')) { return false; }
        this.references.push({ owner: owner, target: fragment[2], property: key });
        value = 'url(#' + fragment[2] + ')';
        admitted = true;
      } else {
        admitted = key === 'clip-path' || key === 'mask' ? value === 'none' :
          SIMPLE_COLOR.test(value) || (COMPONENT_COLOR.test(value) && boundedNumbers(value, 4));
        if (!admitted) { return false; }
      }
    } else if (SCALARS.has(key)) {
      admitted = SCALAR.test(value) && boundedNumbers(value, 1);
    } else if (KEYWORDS.has(key)) {
      admitted = SAFE_KEYWORDS.test(value);
    } else if (key === 'id') {
      admitted = IDENTIFIER.test(value);
    } else if (key === 'transform' || key === 'gradientTransform') {
      admitted = boundedTransform(value);
    } else if (key === 'd') {
      admitted = PATH_COMMANDS.test(value) && boundedNumbers(value, 4096);
    } else if (key === 'points' || key === 'stroke-dasharray') {
      admitted = (NUMBERS_ONLY.test(value) && boundedNumbers(value, 1024)) ||
        (key === 'stroke-dasharray' && value === 'none');
    }
    // Only checked presentation values reach the output. CSS, links and event attributes are never serialized.
    if (admitted) { parts.push(' ' + key + '="' + value + '"'); }
    return true;
  }

  private validReferences(): boolean {
    for (const reference of this.references) {
      const kind = this.definitions.get(reference.target);
      if (reference.property === 'clip-path' ? kind !== 'clipPath' :
        reference.property === 'mask' ? kind !== 'mask' : kind !== 'linearGradient' && kind !== 'radialGradient') {
        return false;
      }
      if (reference.owner) {
        const edges = this.dependencies.get(reference.owner) ?? [];
        if (!edges.includes(reference.target)) { edges.push(reference.target); }
        this.dependencies.set(reference.owner, edges);
      }
    }
    const path = new Set<string>();
    const depths = new Map<string, number>();
    for (const id of this.definitions.keys()) {
      if (this.referenceDepth(id, path, depths, 0) > MAX_REFERENCE_DEPTH) { return false; }
    }
    return true;
  }

  private referenceDepth(id: string, path: Set<string>, depths: Map<string, number>, level: number): number {
    if (level > MAX_REFERENCE_DEPTH || path.has(id)) { return MAX_REFERENCE_DEPTH + 1; }
    const known = depths.get(id);
    if (known !== undefined) { return known; }
    path.add(id);
    let depth = 0;
    for (const next of this.dependencies.get(id) ?? []) {
      depth = Math.max(depth, 1 + this.referenceDepth(next, path, depths, level + 1));
    }
    path.delete(id);
    depths.set(id, depth);
    return depth;
  }
}

/** Return UTF-8 bytes for a static SVG the native image decoder may consume. */
export function desktopPluginSvg(bytes: ArrayBuffer): ArrayBuffer | undefined {
  if (bytes.byteLength <= 0 || bytes.byteLength > DESKTOP_PLUGIN_SVG_MAX_BYTES) { return undefined; }
  try {
    const decoder = util.TextDecoder.create('utf-8', { fatal: true });
    const text = decoder.decodeToString(new Uint8Array(bytes));
    const source = text.replace(XML_HEADER, '').replace(XML_COMMENT, '').trim();
    // Keep declarations and entity references away from the native parser itself.
    if (!source.startsWith('<svg') || source.includes('<!') || source.includes('<?') || source.includes('&') ||
        XML_CONTROL.test(source) || source.split('<').length > MAX_ELEMENTS * 2 + 1) { return undefined; }
    const parsed = new convertxml.ConvertXML().convertToJSObject(source, XML_OPTIONS);
    const roots = getArray(parsed, 'children');
    if (roots === undefined || roots.length !== 1) { return undefined; }
    const result = new DesktopSvgDocument().render(roots[0]);
    if (result === undefined) { return undefined; }
    const serialized = new util.TextEncoder().encodeInto(result);
    return serialized.byteLength <= DESKTOP_PLUGIN_SVG_MAX_BYTES ? serialized.buffer.slice(0) : undefined;
  } catch (_) {
    return undefined;
  }
}
