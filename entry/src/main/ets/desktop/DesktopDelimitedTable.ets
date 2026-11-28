/** Default byte and cell bounds of the bundled spreadsheet renderer. */
export const DESKTOP_TABLE_MAX_BYTES: number = 16 * 1024 * 1024;
export const DESKTOP_TABLE_MAX_CELLS: number = 250_000;
export const DESKTOP_TABLE_TIMEOUT_MS: number = 15_000;

export interface DesktopDelimitedTable {
  rows: string[][];
  columns: number;
}

export function desktopDelimitedFormat(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.csv')) { return 'CSV'; }
  if (lower.endsWith('.tsv')) { return 'TSV'; }
  return '';
}

export function desktopTableColumn(index: number): string {
  let label = '';
  for (let position = index + 1; position > 0; position = Math.floor((position - 1) / 26)) {
    label = String.fromCharCode(65 + (position - 1) % 26) + label;
  }
  return label;
}

function recordSeparator(text: string): string {
  const sample = text.slice(0, 1024 * 1024).replace(/"[^"]*"/g, '');
  const cr = sample.split('\r');
  const lf = sample.split('\n');
  if (cr.length === 1 || (lf.length > 1 && lf[0].length < cr[0].length)) { return '\n'; }
  let paired = 0;
  for (let index = 0; index < cr.length; index++) {
    if (cr[index].startsWith('\n')) { paired++; }
  }
  return paired >= cr.length / 2 ? '\r\n' : '\r';
}

/** Read the literal single-sheet value matrix used by the bundled CSV/TSV renderer. */
export function parseDesktopDelimited(text: string, delimiter: string, maxCells: number): DesktopDelimitedTable {
  if (!text) { return { rows: [['']], columns: 1 }; }
  const newline = recordSeparator(text);
  const rows: string[][] = [];
  let row: string[] = [];
  let columns = 1;
  let cursor = 0;
  while (cursor <= text.length) {
    let value = '';
    if (text[cursor] === '"') {
      let start = ++cursor;
      const parts: string[] = [];
      while (true) {
        const quote = text.indexOf('"', cursor);
        if (quote < 0) { throw new Error('invalid'); }
        if (text[quote + 1] === '"') {
          parts.push(text.slice(start, quote + 1));
          cursor = quote + 2;
          start = cursor;
          continue;
        }
        cursor = quote + 1;
        while (cursor < text.length && text[cursor] !== delimiter && !text.startsWith(newline, cursor) &&
          text[cursor].trim() === '') {
          cursor++;
        }
        if ((cursor === text.length && cursor > quote + 1) ||
          (cursor < text.length && text[cursor] !== delimiter && !text.startsWith(newline, cursor))) {
          throw new Error('invalid');
        }
        parts.push(text.slice(start, quote));
        value = parts.join('');
        break;
      }
    } else {
      const start = cursor;
      while (cursor < text.length && text[cursor] !== delimiter && !text.startsWith(newline, cursor)) {
        cursor++;
      }
      value = text.slice(start, cursor);
    }
    row.push(value);
    columns = Math.max(columns, row.length);
    if ((rows.length + 1) * columns > maxCells) { throw new Error('tooLarge'); }
    if (text[cursor] === delimiter) {
      cursor++;
    } else {
      rows.push(row);
      row = [];
      cursor += cursor === text.length ? 1 : newline.length;
    }
  }
  return { rows: rows, columns: columns };
}
