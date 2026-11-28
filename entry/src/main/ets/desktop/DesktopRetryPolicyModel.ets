import { getArray, getBoolean, getField, getNumber, getRecord, getString, isRecord } from 'connection';

export interface DesktopRetryField {
  key: string;
  path: string[];
  type: string;
  minimum?: number;
  maximum?: number;
  integer: boolean;
  fallback?: Object;
  choices: string[];
}

export interface DesktopRetryMode {
  id: string;
  fields: DesktopRetryField[];
}

export interface DesktopRetryDocument {
  revision: number;
  writable: boolean;
  inheritedMode: string;
  modes: DesktopRetryMode[];
  user?: Object;
}

export interface DesktopRetryDraft {
  mode: string;
  texts: Record<string, string>;
  codes: string[];
  knownCodes: string[];
  codesEdited: boolean;
}

export interface DesktopRetryChange {
  operations: Record<string, Object>[];
  problem: string;
  problemField: string;
}

export interface DesktopNewRetryPolicy {
  policy?: Record<string, Object>;
  valid: boolean;
}

function valueAt(root: Object | undefined, path: string[]): Object | undefined {
  let value = root;
  for (const field of path) { value = getField(value, field); }
  return value;
}

function schemaNode(refs: Object | undefined, value: Object | undefined): Object | undefined {
  return typeof value === 'number' ? getRecord(refs, String(value)) : undefined;
}

function schemaAt(schema: Object | undefined, path: string[]): Object | undefined {
  const refs = getRecord(schema, 'refs');
  let node = schemaNode(refs, getField(schema, 'uid'));
  for (const field of path) {
    const child = getString(node, 'type') === 'dict' ? getField(node, 'inner') :
      getField(getRecord(node, 'dict'), field);
    node = schemaNode(refs, child);
  }
  return node;
}

function codeChoices(refs: Object | undefined, node: Object | undefined): string[] {
  const choices: string[] = [];
  const item = schemaNode(refs, getField(node, 'inner'));
  for (const ref of getArray(item, 'list') ?? []) {
    const branch = schemaNode(refs, ref);
    const value = getString(branch, 'value') ?? '';
    if (getString(branch, 'type') === 'const' && value && !choices.includes(value)) { choices.push(value); }
  }
  return choices;
}

function fieldsOf(refs: Object | undefined, owner: Object | undefined, base: string[],
  inherited: Object | undefined): DesktopRetryField[] {
  const dict = getRecord(owner, 'dict');
  if (dict === undefined) { return []; }
  const fields: DesktopRetryField[] = [];
  for (const name of Object.keys(dict)) {
    if (name === 'mode') { continue; }
    const node = schemaNode(refs, getField(dict, name));
    const path = [...base, name];
    const type = getString(node, 'type') ?? '';
    if (type === 'object' && base.length === 0) {
      fields.push(...fieldsOf(refs, node, path, inherited));
    } else if (type === 'number' || type === 'array') {
      const meta = getRecord(node, 'meta');
      fields.push({ key: path.join('.'), path: path, type: type, minimum: getNumber(meta, 'min'),
        maximum: getNumber(meta, 'max'), integer: getNumber(meta, 'step') === 1,
        fallback: valueAt(inherited, path) ?? getField(meta, 'default'), choices: codeChoices(refs, node) });
    }
  }
  return fields;
}

export function readDesktopRetryDocument(describe: Object | undefined, namespace: string,
  path: string[]): DesktopRetryDocument | undefined {
  const view = getArray(describe, 'namespaces')?.find((row: Object): boolean => getString(row, 'ns') === namespace);
  const revision = getNumber(view, 'revision');
  const schema = getRecord(view, 'schema');
  const node = schemaAt(schema, path);
  if (revision === undefined || getString(node, 'type') !== 'union') { return undefined; }
  const refs = getRecord(schema, 'refs');
  const inherited = valueAt(getRecord(view, 'base'), path);
  const user = valueAt(getRecord(view, 'user'), path);
  const modes: DesktopRetryMode[] = [];
  for (const ref of getArray(node, 'list') ?? []) {
    const branch = schemaNode(refs, ref);
    const mode = schemaNode(refs, getField(getRecord(branch, 'dict'), 'mode'));
    const id = getString(mode, 'value') ?? '';
    if (getString(mode, 'type') !== 'const' || !id) { continue; }
    modes.push({ id: id, fields: fieldsOf(refs, branch, [], inherited) });
  }
  if (modes.length === 0) { return undefined; }
  const mode = getString(inherited, 'mode') ?? '';
  return { revision: revision, writable: getBoolean(describe, 'writable') === true,
    inheritedMode: modes.some((row: DesktopRetryMode): boolean => row.id === mode) ? mode : modes[0].id,
    modes: modes, user: user };
}

function strings(value: Object | undefined): string[] {
  const values: string[] = [];
  if (value === undefined) { return values; }
  const wrapped: Record<string, Object> = { 'items': value };
  for (const item of getArray(wrapped, 'items') ?? []) {
    if (typeof item === 'string') { values.push(item); }
  }
  return values;
}

export function desktopRetryMode(document: DesktopRetryDocument | undefined, id: string): DesktopRetryMode | undefined {
  return document?.modes.find((mode: DesktopRetryMode): boolean => mode.id === id);
}

export function desktopRetryDraft(document?: DesktopRetryDocument): DesktopRetryDraft {
  const texts: Record<string, string> = {};
  const id = isRecord(document?.user) ? getString(document?.user, 'mode') ?? document?.inheritedMode ?? '' : '';
  const fields = desktopRetryMode(document, id)?.fields ?? [];
  let codes: string[] = [];
  let knownCodes: string[] = [];
  for (const field of fields) {
    const stored = valueAt(document?.user, field.path);
    if (field.type === 'number') { texts[field.key] = stored === undefined ? '' : String(stored); }
    else {
      codes = strings(stored ?? field.fallback);
      knownCodes = Array.from(new Set<string>([...field.choices, ...strings(field.fallback), ...codes]));
    }
  }
  return { mode: id, texts: texts, codes: codes, knownCodes: knownCodes, codesEdited: false };
}

export function switchDesktopRetryMode(document: DesktopRetryDocument, draft: DesktopRetryDraft,
  id: string): DesktopRetryDraft {
  if (!id) { return desktopRetryDraft(); }
  const previous = desktopRetryMode(document, draft.mode);
  const next = desktopRetryMode(document, id);
  const texts: Record<string, string> = {};
  let codes: string[] = [];
  let knownCodes: string[] = [];
  let codesEdited = false;
  for (const field of next?.fields ?? []) {
    if (field.type === 'number') { texts[field.key] = draft.texts[field.key] ?? ''; }
    else {
      const carry = previous?.fields.some((old: DesktopRetryField): boolean => old.key === field.key) === true;
      codes = carry ? draft.codes : strings(field.fallback);
      knownCodes = Array.from(new Set<string>([...field.choices, ...strings(field.fallback), ...codes]));
      codesEdited = carry ? draft.codesEdited : true;
    }
  }
  return { mode: id, texts: texts, codes: codes, knownCodes: knownCodes, codesEdited: codesEdited };
}

export function desktopRetryChange(document: DesktopRetryDocument, path: string[], draft: DesktopRetryDraft):
  DesktopRetryChange {
  const operations: Record<string, Object>[] = [];
  const change: DesktopRetryChange = { operations: operations, problem: '', problemField: '' };
  if (!draft.mode) {
    if (document.user !== undefined) { operations.push({ 'op': 'unset', 'path': path }); }
    return change;
  }
  const branch = desktopRetryMode(document, draft.mode);
  if (branch === undefined) { change.problem = 'mode'; return change; }
  if (getString(document.user, 'mode') !== draft.mode) {
    operations.push({ 'op': 'set', 'path': [...path, 'mode'], 'value': draft.mode });
  }
  const effective: Map<string, number> = new Map<string, number>();
  const seen = new Set<string>();
  const decimal = new RegExp('^[+-]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?$');
  for (const field of branch.fields) {
    seen.add(field.key);
    const previous = valueAt(document.user, field.path);
    let next: Object | undefined;
    if (field.type === 'array') {
      const defaults = strings(field.fallback);
      if (!draft.codes.length || new Set<string>(draft.codes).size !== draft.codes.length ||
        draft.codes.some((code: string): boolean => !code.trim())) {
        change.problem = 'codes'; change.problemField = field.key; return change;
      }
      if (!draft.codesEdited) { next = previous; }
      else if (draft.codes.length !== defaults.length ||
        !draft.codes.every((code: string): boolean => defaults.includes(code))) { next = draft.codes; }
    } else {
      const raw = (draft.texts[field.key] ?? '').trim();
      const value = raw ? Number(raw) : field.fallback;
      if (raw && (!decimal.test(raw) || typeof value !== 'number' || !Number.isFinite(value))) { change.problem = 'number'; }
      else if (typeof value === 'number') {
        if (field.integer && !Number.isInteger(value)) { change.problem = 'integer'; }
        else if (field.minimum === Number.MIN_VALUE && value <= 0) { change.problem = 'positive'; }
        else if ((field.minimum !== undefined && value < field.minimum) ||
          (field.maximum !== undefined && value > field.maximum)) { change.problem = 'range'; }
        effective.set(field.key, value);
      }
      if (change.problem) { change.problemField = field.key; return change; }
      if (raw && typeof value === 'number') { next = value; }
    }
    if (JSON.stringify(next) === JSON.stringify(previous)) { continue; }
    const segments = [...path, ...field.path];
    if (next === undefined) { operations.push({ 'op': 'unset', 'path': segments }); }
    else { operations.push({ 'op': 'set', 'path': segments, 'value': next }); }
  }
  if ((effective.get('backoff.initialDelayMs') ?? 0) > (effective.get('backoff.maxDelayMs') ?? Infinity)) {
    change.problem = 'delay'; change.problemField = 'backoff.initialDelayMs'; return change;
  }
  for (const mode of document.modes) {
    for (const field of mode.fields) {
      if (seen.has(field.key)) { continue; }
      seen.add(field.key);
      if (valueAt(document.user, field.path) !== undefined) {
        operations.push({ 'op': 'unset', 'path': [...path, ...field.path] });
      }
    }
  }
  return change;
}

export function desktopNewRetryPolicy(document: DesktopRetryDocument, draft: DesktopRetryDraft): DesktopNewRetryPolicy {
  const change = desktopRetryChange(document, [], draft);
  if (change.problem) { return { valid: false }; }
  if (!draft.mode) { return { valid: true }; }
  const policy: Record<string, Object> = { 'mode': draft.mode };
  const backoff: Record<string, Object> = {};
  for (const operation of change.operations) {
    if (getString(operation, 'op') !== 'set') { continue; }
    const path = getArray(operation, 'path') ?? [];
    const value = getField(operation, 'value');
    const name = path[0];
    if (value === undefined || typeof name !== 'string') { continue; }
    if (path.length === 1) { policy[name] = value; }
    else if (name === 'backoff' && path.length === 2 && typeof path[1] === 'string') {
      backoff[String(path[1])] = value;
    }
  }
  if (Object.keys(backoff).length > 0) { policy['backoff'] = backoff; }
  return { valid: true, policy: policy };
}
