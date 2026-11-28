import { crc32, inflateRawSync } from 'node:zlib';

export const MAX_FILE_BYTES = 16 * 1024 * 1024;
export const MAX_CELLS = 250_000;
export const TIMEOUT_MS = 15_000;
export const MAX_RESPONSE_BYTES = 32 * 1024 * 1024;
const MAX_ARCHIVE_BYTES = 64 * 1024 * 1024;
const MAX_ARCHIVE_ENTRIES = 4096;
const FEATURES = ['charts', 'images', 'shapes', 'conditionalFormatting'];
const XML_DECLARATIONS = ['<!DOCTYPE', '<!ENTITY'].flatMap((entry) =>
  [Buffer.from(entry), Buffer.from(entry, 'utf16le'), Buffer.from(entry, 'utf16le').swap16()]);

/** Check the central-directory summary before the browser decoder inflates XLSX entries. */
export function validateArchive(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const u16 = (at) => view.getUint16(at, true);
  const u32 = (at) => view.getUint32(at, true);
  let end = bytes.length - 22;
  const minimum = Math.max(0, end - 65535);
  while (end >= minimum && (u32(end) !== 0x06054b50 || end + 22 + u16(end + 20) !== bytes.length)) end--;
  if (end < minimum || u32(end + 4) !== 0 || u16(end + 8) !== u16(end + 10)) throw Error('invalid');
  const count = u16(end + 10);
  const size = u32(end + 12);
  const directory = u32(end + 16);
  if (count > MAX_ARCHIVE_ENTRIES) throw Error('tooLarge');
  if (!count || directory + size !== end) throw Error('invalid');

  const decoder = new TextDecoder('utf-8', { fatal: true });
  const names = new Set();
  let expanded = 0;
  let offset = directory;
  for (let index = 0; index < count; index++) {
    if (offset + 46 > end || u32(offset) !== 0x02014b50) throw Error('invalid');
    const flags = u16(offset + 8);
    const method = u16(offset + 10);
    const compressedBytes = u32(offset + 20);
    const uncompressedBytes = u32(offset + 24);
    const nameBytes = u16(offset + 28);
    const local = u32(offset + 42);
    const entryEnd = offset + 46 + nameBytes + u16(offset + 30) + u16(offset + 32);
    expanded += uncompressedBytes;
    if (expanded > MAX_ARCHIVE_BYTES) throw Error('tooLarge');
    if ((flags & 1) || (method !== 0 && method !== 8) || u16(offset + 34) !== 0 || entryEnd > end ||
      local + 30 > directory || u32(local) !== 0x04034b50 || u16(local + 8) !== method ||
      u16(local + 6) !== flags || u16(local + 26) !== nameBytes ||
      local + 30 + nameBytes + u16(local + 28) + compressedBytes > directory) throw Error('invalid');
    if (method === 0 && compressedBytes !== uncompressedBytes) throw Error('invalid');
    if (!(flags & 8) && (u32(local + 18) !== compressedBytes || u32(local + 22) !== uncompressedBytes)) throw Error('invalid');
    const rawName = bytes.subarray(offset + 46, offset + 46 + nameBytes);
    if (rawName.some((byte, index) => bytes[local + 30 + index] !== byte)) throw Error('invalid');
    const name = decoder.decode(rawName).replace(/\/$/, '');
    if (!name || /[\\:\x00-\x1f]/.test(name) || name.split('/').some((part) => !part || part === '.' || part === '..')) {
      throw Error('invalid');
    }
    const key = name.replace(/[A-Z]/g, (character) => character.toLowerCase());
    if (names.has(key)) throw Error('invalid');
    names.add(key);
    const body = local + 30 + nameBytes + u16(local + 28);
    const compressed = bytes.subarray(body, body + compressedBytes);
    const content = method === 8 ? inflateRawSync(compressed, { maxOutputLength: Math.max(1, uncompressedBytes) }) : compressed;
    if (content.length !== uncompressedBytes || crc32(content) !== u32(offset + 16)) throw Error('invalid');
    if (/\.(xml|rels)$/i.test(name)) {
      const binary = Buffer.from(content.buffer, content.byteOffset, content.byteLength);
      if (XML_DECLARATIONS.some((value) => binary.includes(value))) throw Error('invalid');
    }
    offset = entryEnd;
  }
  if (offset !== end) throw Error('invalid');
}

/** Refuse impossible compound-file allocations before SheetJS walks the BIFF stream. */
export function validateLegacyWorkbook(bytes) {
  const magic = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
  if (!magic.every((byte, index) => bytes[index] === byte)) {
    if (bytes[0] === 9 && [0, 2, 4, 8].includes(bytes[1])) return;
    throw Error('invalid');
  }
  if (bytes.length < 512) throw Error('invalid');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const u16 = (at) => view.getUint16(at, true);
  const u32 = (at) => view.getUint32(at, true);
  const version = u16(26);
  const shift = u16(30);
  if (!((version === 3 && shift === 9) || (version === 4 && shift === 12)) ||
    u16(28) !== 0xfffe || u16(32) !== 6) throw Error('invalid');
  const sectorBytes = 1 << shift;
  const sectors = bytes.length / sectorBytes - 1;
  const entries = sectorBytes / 4;
  const sector = (index) => {
    if (!position(index, sectors)) throw Error('invalid');
    return (index + 1) * sectorBytes;
  };
  const fatCount = u32(44);
  const diFatCount = u32(72);
  if (!Number.isInteger(sectors) || sectors < 2 || !position(fatCount, sectors) || fatCount === 0 ||
    diFatCount >= sectors || u32(64) >= sectors || u32(40) >= sectors) throw Error('invalid');
  const fat = new Set();
  const addFat = (index) => {
    if (index === 0xffffffff) return;
    sector(index);
    if (fat.has(index)) throw Error('invalid');
    fat.add(index);
  };
  for (let entry = 0; entry < 109; entry++) addFat(u32(76 + 4 * entry));
  const visited = new Set();
  let next = u32(68);
  for (let index = 0; index < diFatCount; index++) {
    if (visited.has(next)) throw Error('invalid');
    visited.add(next);
    const at = sector(next);
    for (let i = 0; i < entries - 1; i++) addFat(u32(at + 4 * i));
    next = u32(at + sectorBytes - 4);
  }
  if (fat.size !== fatCount || [...visited].some((index) => fat.has(index))) throw Error('invalid');
  const fatSectors = [...fat];
  next = u32(48);
  let streamBytes = 0;
  while (next !== 0xfffffffe) {
    if (visited.has(next) || fat.has(next)) throw Error('invalid');
    visited.add(next);
    const at = sector(next);
    for (let offset = at; offset < at + sectorBytes; offset += 128) {
      const type = bytes[offset + 66];
      if (type !== 2 && type !== 5) continue;
      const size = u32(offset + 120);
      if (u32(offset + 124) || size > bytes.length) throw Error('invalid');
      streamBytes += size;
      if (streamBytes > bytes.length * 2) throw Error('tooLarge');
    }
    next = u32(sector(fatSectors[Math.floor(next / entries)]) + (next % entries) * 4);
  }
}

function position(index, limit) {
  return Number.isSafeInteger(index) && index >= 0 && index < limit;
}

function textOf(value) {
  return typeof value === 'string' || typeof value === 'boolean' ||
    (typeof value === 'number' && Number.isFinite(value)) ? String(value) : undefined;
}

function metrics(values, length) {
  return Object.entries(values ?? {}).flatMap(([key, pixels]) => {
    const index = Number(key);
    return position(index, length) && Number.isFinite(pixels) && pixels > 0 ? [{ index, pixels }] : [];
  });
}

function hidden(values, length) {
  return Object.keys(values ?? {}).map(Number).filter((index) => position(index, length));
}

function font(input, string, result = {}) {
  const foreground = string(input.fc);
  const fontFamily = string(input.ff);
  if (foreground) result.foreground = foreground;
  if (fontFamily) result.fontFamily = fontFamily;
  if (Number.isFinite(input.fs) && input.fs > 0) result.fontSize = input.fs;
  if (input.bl === 1 || input.bl === true) result.bold = true;
  if (input.it === 1 || input.it === true) result.italic = true;
  if (input.un === 1 || input.un === true) result.underline = true;
  if (input.cl === 1 || input.cl === true) result.strike = true;
  return result;
}

function borderOf(info, string) {
  const borders = {};
  for (const [edge, key] of [['top', 't'], ['right', 'r'], ['bottom', 'b'], ['left', 'l']]) {
    const value = info?.[key];
    if (Number.isInteger(value?.style) && value.style > 0 && value.style <= 13) {
      borders[edge] = { style: value.style, color: string(value.color) || '#000000' };
    }
  }
  return Object.keys(borders).length ? borders : undefined;
}

function normalizeSheet(sheet, string, charge) {
  const rows = sheet.row;
  const columns = sheet.column;
  const config = sheet.config ?? {};
  const hiddenSheet = Boolean(sheet.hide);
  const bordersByCell = new Map();
  for (const info of config.borderInfo ?? []) {
    const value = info.value;
    if (info.rangeType === 'cell' && position(value?.row_index, rows) && position(value?.col_index, columns)) {
      bordersByCell.set(value.row_index * columns + value.col_index, value);
    }
  }
  const cells = [];
  for (const input of sheet.celldata) {
    const { r: row, c: column, v: value } = input;
    if (!position(row, rows) || !position(column, columns) || value === null || typeof value !== 'object') throw Error('invalid');
    const borders = borderOf(bordersByCell.get(row * columns + column), string);
    const cell = font(value, string, { row, column });
    const raw = string(value.v);
    const display = string(value.m) ?? raw;
    if (raw !== undefined) cell.value = raw;
    if (display !== undefined) cell.display = display;
    const formula = string(value.f);
    const format = string(value.ct?.fa);
    const background = string(value.bg);
    if (formula) cell.formula = formula;
    if (format) cell.format = format;
    if (background) cell.background = background;
    if (borders) cell.borders = borders;
    if (value.ht === 0 || value.ht === 1 || value.ht === 2) cell.horizontal = ['center', 'left', 'right'][value.ht];
    if (value.vt === 0 || value.vt === 1 || value.vt === 2) cell.vertical = ['middle', 'top', 'bottom'][value.vt];
    if (value.tb === '1' || value.tb === '2') cell.wrap = value.tb === '2';
    if (Number.isFinite(value.rt)) cell.rotation = value.rt;
    if (value.tr === '3') cell.verticalText = true;
    if (Array.isArray(value.ct?.s)) {
      cell.runs = value.ct.s.flatMap((run) => {
        const text = string(run.v);
        if (text === undefined) return [];
        charge(48);
        return [font(run, string, { text })];
      });
    }
    if (Object.keys(cell).length > 2) {
      charge(68);
      cells.push(cell);
    }
  }
  const merges = Object.values(config.merge ?? {}).map((merge) => {
    if (!position(merge.r, rows) || !position(merge.c, columns) ||
      !Number.isSafeInteger(merge.rs) || !Number.isSafeInteger(merge.cs) || merge.rs <= 0 || merge.cs <= 0 ||
      merge.r + merge.rs > rows || merge.c + merge.cs > columns) throw Error('invalid');
    return { row: merge.r, column: merge.c, rows: merge.rs, columns: merge.cs };
  });
  return { id: string(sheet.id), name: string(sheet.name), hidden: hiddenSheet, active: !hiddenSheet && sheet.status === 1,
    rows, columns, cells, merges, rowHeights: metrics(config.rowlen, rows), columnWidths: metrics(config.columnlen, columns),
    hiddenRows: hidden(config.rowhidden, rows), hiddenColumns: hidden(config.colhidden, columns) };
}

/** Project the exact bundled Worker's result onto a bounded, sparse native wire shape. */
export function normalizeWorkbook(workbook) {
  if (!Array.isArray(workbook?.sheets) || !workbook.sheets.length ||
    !Number.isSafeInteger(workbook.missingResults) || workbook.missingResults < 0 ||
    !Array.isArray(workbook.unsupportedFeatures)) throw Error('invalid');
  let area = 0;
  let estimatedBytes = 0;
  const charge = (bytes) => {
    estimatedBytes += bytes;
    if (estimatedBytes > MAX_RESPONSE_BYTES) throw Error('tooLarge');
  };
  const string = (value) => {
    const result = textOf(value);
    if (result !== undefined) charge(Buffer.byteLength(result));
    return result;
  };
  const ids = new Set();
  const sheets = workbook.sheets.map((sheet) => {
    if (typeof sheet.id !== 'string' || !sheet.id || ids.has(sheet.id) || typeof sheet.name !== 'string' ||
      !Number.isSafeInteger(sheet.row) || sheet.row <= 0 || !Number.isSafeInteger(sheet.column) || sheet.column <= 0 ||
      !Array.isArray(sheet.celldata) || sheet.celldata.length > sheet.row * sheet.column) throw Error('invalid');
    ids.add(sheet.id);
    area += sheet.row * sheet.column;
    if (area > MAX_CELLS) throw Error('tooLarge');
    return normalizeSheet(sheet, string, charge);
  });
  const active = sheets.find((sheet) => sheet.active) ?? sheets.find((sheet) => !sheet.hidden);
  if (active === undefined) throw Error('invalid');
  for (const sheet of sheets) sheet.active = sheet === active;
  const result = { sheets, missingResults: workbook.missingResults,
    unsupportedFeatures: FEATURES.filter((feature) => workbook.unsupportedFeatures.includes(feature)) };
  if (Buffer.byteLength(JSON.stringify(result)) > MAX_RESPONSE_BYTES) throw Error('tooLarge');
  return result;
}
