/** Only called on hosts advertising the packed native workbook endpoint; schemas stay lazy. */
export function spreadsheetMethod(z) {
  let result;
  const create = () => {
    if (result) return result;
    const count = z.number().int().min(0);
    const style = {
      foreground: z.string().optional(),
      fontFamily: z.string().optional(),
      fontSize: z.number().positive().optional(),
      bold: z.boolean().optional(),
      italic: z.boolean().optional(),
      underline: z.boolean().optional(),
      strike: z.boolean().optional(),
    };
    const edge = z.strictObject({ style: z.number().int().min(1).max(13), color: z.string() }).optional();
    const cell = z.strictObject({
      row: count,
      column: count,
      value: z.string().optional(),
      display: z.string().optional(),
      formula: z.string().optional(),
      format: z.string().optional(),
      background: z.string().optional(),
      horizontal: z.enum(['left', 'center', 'right']).optional(),
      vertical: z.enum(['top', 'middle', 'bottom']).optional(),
      wrap: z.boolean().optional(),
      rotation: z.number().optional(),
      verticalText: z.boolean().optional(),
      borders: z.strictObject({ top: edge, right: edge, bottom: edge, left: edge }).optional(),
      runs: z.array(z.strictObject({ text: z.string(), ...style })).optional(),
      ...style,
    });
    const pixels = z.strictObject({ index: count, pixels: z.number().positive() });
    const merge = z.strictObject({ row: count, column: count, rows: count.min(1), columns: count.min(1) });
    const sheet = z.strictObject({
      id: z.string(), name: z.string(), hidden: z.boolean(), active: z.boolean(), rows: count.min(1), columns: count.min(1),
      cells: z.array(cell), merges: z.array(merge), rowHeights: z.array(pixels), columnWidths: z.array(pixels),
      hiddenRows: z.array(count), hiddenColumns: z.array(count),
      frozen: z.strictObject({ rows: count, columns: count }).optional(),
    });
    return result = z.strictObject({
      absolutePath: z.string(), version: z.string(), sheets: z.array(sheet).min(1),
      missingResults: count, unsupportedFeatures: z.array(z.enum(['charts', 'images', 'shapes', 'conditionalFormatting'])),
    });
  };
  const name = (typeSymbol) => ({ mode: 'strict', typeSymbol, create: () => z.string(), jsonSchema: { type: 'string' } });
  const scope = name('@deepseek-ai/dsh-session/types#SessionId');
  const path = name('@deepseek-ai/dsh-api-workspace-files#workspaceFiles/spreadsheet:path');
  return {
    service: 'workspaceFiles',
    description: 'Read a scoped XLS or XLSX worksheet preview without executing workbook formulas.',
    invocation: { kind: 'direct' },
    parameters: [
      { name: 'workspaceFileScope', wire: 'workspaceFileScopeId', source: 'lookup',
        lookup: 'workspaceFileScope', codec: scope, strictCodec: scope },
      { name: 'path', source: 'json', codec: path, strictCodec: path },
    ],
    cancellation: { parameter: 'signal' },
    result: { mode: 'strict', typeSymbol: '@deepseek-ai/dsh-api-workspace-files#DSHMSpreadsheetPreview', create },
    sourceLocation: { file: 'hostcore/spreadsheet/service.mjs', line: 1, column: 1 },
  };
}
