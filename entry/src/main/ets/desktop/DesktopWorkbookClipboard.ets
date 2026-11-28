import {
  DesktopWorkbookBorder, DesktopWorkbookCell, DesktopWorkbookMerge, DesktopWorkbookRun,
  DesktopWorkbookSheet, DesktopWorkbookTextStyle
} from './DesktopWorkbookModel';

const HTML_LIMIT: number = 32 * 1024 * 1024;
const TABLE: string = '<table data-type="fortune-copy-action-table">';
const SAFE_COLOR: RegExp = new RegExp('^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$', 'i');
const SAFE_FONT: RegExp = new RegExp("^[^\\x00-\\x1f\\x7f\\\\\"'<>:;()[\\]{}@,=&]+$");
const RAW_VALUE_FORMAT: RegExp = new RegExp('^w(?:0|0\\.0+)?$', 'i');

type BorderSide = 'left' | 'right' | 'top' | 'bottom';

function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function colorOf(value: string | undefined): string {
  return value !== undefined && SAFE_COLOR.test(value) ? value : '';
}

function numberText(value: number): string { return String(Math.round(value * 10000) / 10000); }

function fontCss(style: DesktopWorkbookTextStyle): string {
  let css = '';
  if (style.bold) { css += 'font-weight:bold;'; }
  if (style.italic) { css += 'font-style:italic;'; }
  const size = style.fontSize ?? 0;
  if (Number.isFinite(size) && size > 0 && size <= 256 && size * 0.75 !== 10) {
    css += 'font-size:' + numberText(size * 0.75) + 'pt;';
  }
  const family = style.fontFamily?.trim() ?? '';
  if (family && family.length <= 128 && SAFE_FONT.test(family)) { css += "font-family:'" + family + "';"; }
  const color = colorOf(style.foreground);
  if (color && color !== '#000000') { css += 'color:' + color + ';'; }
  const decor = style.underline && style.strike ? 'underline line-through' :
    style.underline ? 'underline' : style.strike ? 'line-through' : '';
  if (decor) { css += 'text-decoration:' + decor + ';'; }
  return css;
}

function cellCss(cell: DesktopWorkbookCell | undefined): string {
  if (cell === undefined) { return ''; }
  let css = '';
  const background = colorOf(cell.background);
  if (background) { css += 'background:' + background + ';'; }
  if (cell.horizontal === 'center' || cell.horizontal === 'right') {
    css += 'text-align:' + cell.horizontal + ';';
  }
  if (cell.vertical === 'middle') { css += 'align-items:center;vertical-align:middle;'; }
  if (cell.vertical === 'bottom') { css += 'align-items:flex-end;vertical-align:bottom;'; }
  if (cell.verticalText) { css += 'writing-mode:vertical-rl;'; }
  if (cell.wrap) { css += 'white-space:pre-wrap;'; }
  // FortuneSheet supplies rich run formatting separately from the cell font.
  if (!cell.runs.length) { css += fontCss(cell.decoration); }
  return css;
}

function appendRun(run: DesktopWorkbookRun): string {
  const style = fontCss(run.decoration);
  const content = escapeHtml(run.text);
  return style ? '<span style="' + escapeHtml(style) + '">' + content + '</span>' : content;
}

/** The cached value that FortuneSheet includes in a clipboard cell. */
export function desktopWorkbookClipboardValue(cell?: DesktopWorkbookCell): string {
  if (cell === undefined) { return ''; }
  return RAW_VALUE_FORMAT.test(cell.format ?? '') ? cell.value : cell.display;
}

function cellText(cell: DesktopWorkbookCell | undefined): string {
  if (cell === undefined) { return ''; }
  const text = desktopWorkbookClipboardValue(cell);
  let content = escapeHtml(text);
  if (cell.runs.length && cell.runs.map((run: DesktopWorkbookRun): string => run.text).join('') === text) {
    content = cell.runs.map(appendRun).join('');
  }
  const rotation = cell.rotation ?? 0;
  if (!cell.verticalText && Number.isFinite(rotation) && rotation !== 0 && Math.abs(rotation) <= 180) {
    content = '<span style="display:inline-block;transform:rotate(' + numberText(rotation) + 'deg);">' + content + '</span>';
  }
  return content;
}

function edgeOf(cell: DesktopWorkbookCell | undefined, side: BorderSide): DesktopWorkbookBorder | undefined {
  switch (side) {
    case 'left': return cell?.left;
    case 'right': return cell?.right;
    case 'top': return cell?.top;
    case 'bottom': return cell?.bottom;
  }
}

function borderCss(side: BorderSide, edge: DesktopWorkbookBorder | undefined): string {
  if (edge === undefined || !Number.isInteger(edge.style) || edge.style < 1 || edge.style > 13) { return ''; }
  const color = colorOf(edge.color);
  if (!color) { return ''; }
  const width = edge.style === 13 ? '1.5pt' : edge.style >= 8 && edge.style <= 11 ? '1pt' : '0.5pt';
  let line = 'solid';
  switch (edge.style) {
    case 2: line = 'double'; break;
    case 3:
    case 6:
    case 11: line = 'dotted'; break;
    case 4:
    case 5:
    case 9:
    case 10:
    case 12: line = 'dashed'; break;
    default: break;
  }
  return 'border-' + side + ':' + width + ' ' + line + ' ' + color + ';';
}

/** Resolve a merge's outside borders from the source perimeter before hiding covered cells. */
function mergeBorder(sheet: DesktopWorkbookSheet, merge: DesktopWorkbookMerge,
  side: BorderSide): DesktopWorkbookBorder | undefined {
  const alongRow = side === 'top' || side === 'bottom';
  const length = alongRow ? merge.columns : merge.rows;
  const colors = new Map<string, number>();
  const styles = new Map<number, number>();
  let maxStyle = 0;
  let outerColor = '';
  for (let position = 0; position < length; position++) {
    const row = alongRow ? merge.row + (side === 'bottom' ? merge.rows - 1 : 0) : merge.row + position;
    const column = alongRow ? merge.column + position : merge.column + (side === 'right' ? merge.columns - 1 : 0);
    if (sheet.rows.isHidden(row)) { continue; }
    const border = edgeOf(sheet.cells.get(sheet.key(row, column)), side);
    const color = colorOf(border?.color);
    if (border === undefined || !color || !Number.isInteger(border.style) || border.style < 1 || border.style > 13) {
      continue;
    }
    styles.set(border.style, (styles.get(border.style) ?? 0) + 1);
    colors.set(color, (colors.get(color) ?? 0) + 1);
  }
  styles.forEach((count: number, style: number): void => {
    if (count >= length / 2) { maxStyle = Math.max(maxStyle, style); }
  });
  colors.forEach((count: number, color: string): void => {
    if (count >= length / 2) { outerColor = color; }
  });
  return maxStyle && outerColor ? { style: maxStyle, color: outerColor } : undefined;
}

function bordersCss(sheet: DesktopWorkbookSheet, row: number, cell: DesktopWorkbookCell | undefined,
  merge: DesktopWorkbookMerge | undefined): string {
  if (merge !== undefined) {
    return borderCss('left', mergeBorder(sheet, merge, 'left')) + borderCss('right', mergeBorder(sheet, merge, 'right')) +
      borderCss('top', mergeBorder(sheet, merge, 'top')) + borderCss('bottom', mergeBorder(sheet, merge, 'bottom'));
  }
  if (sheet.rows.isHidden(row)) { return ''; }
  return borderCss('left', cell?.left) + borderCss('right', cell?.right) +
    borderCss('bottom', cell?.bottom) + borderCss('top', cell?.top);
}

/** Serialize one logical rectangle using the bundled FortuneSheet HTML clipboard table contract. */
export function desktopWorkbookRangeToHtml(sheet: DesktopWorkbookSheet, firstRow: number, firstColumn: number,
  lastRow: number, lastColumn: number): string | undefined {
  const r1 = Math.min(firstRow, lastRow);
  const r2 = Math.max(firstRow, lastRow);
  const c1 = Math.min(firstColumn, lastColumn);
  const c2 = Math.max(firstColumn, lastColumn);
  if (![r1, c1, r2, c2].every((index: number): boolean => Number.isSafeInteger(index)) ||
    r1 < 0 || c1 < 0 || r2 >= sheet.rows.logicalCount || c2 >= sheet.columns.logicalCount) { return undefined; }
  const html: string[] = [TABLE];
  let length = TABLE.length + '</table>'.length;
  for (let column = c1; column <= c2; column++) {
    const group = '<colgroup width="' + numberText(sheet.columns.copySize(column, 72)) + 'px"></colgroup>';
    html.push(group);
    length += group.length;
  }
  // Clipboard selection walks logical indices, including hidden rows and columns between the endpoints.
  for (let row = r1; row <= r2; row++) {
    html.push('<tr>');
    length += '<tr></tr>'.length;
    for (let column = c1; column <= c2; column++) {
      const merge = sheet.merge(row, column);
      if (merge !== undefined && (row !== merge.row || column !== merge.column)) { continue; }
      const cell = sheet.cells.get(sheet.key(row, column));
      const span = merge === undefined ? '' : 'rowspan="' + merge.rows + '" colspan="' + merge.columns + '"';
      const height = column === c1 ? 'height:' + numberText(sheet.rows.copySize(row, 19)) + 'px;' : '';
      const style = height + cellCss(cell) + bordersCss(sheet, row, cell, merge);
      const entry = '<td ' + span + ' style="' + escapeHtml(style) + '">' + cellText(cell) + '</td>';
      length += entry.length;
      if (length > HTML_LIMIT) { return undefined; }
      html.push(entry);
    }
    html.push('</tr>');
  }
  return html.join('') + '</table>';
}
