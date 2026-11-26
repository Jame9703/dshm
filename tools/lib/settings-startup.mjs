import { createHash } from 'node:crypto';
import { readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const settingsFile = 'node_modules/@deepseek-ai/dsh-settings/lib/index.js';
const upstreamHash = '411ae83e6ce9c082ba965f04f9104b42bc3400f98ff4f5546af49c0c54ad7747';
const marker = 'const dshmDescribeForms = Symbol("dshmDescribeForms");';
const describe = '\tdescribe(options) {\n\t\tconst active';
const listForms = '\t\tconst descriptors = this.ownerContext.configEditor.configuration().flatMap(({ entry, inherited, override }) => {';
const renderValues = '\t\t\tconst value = projectForm(form, plainConfig(entry.fiber.effectiveConfig));';
const touchMarker = 'const dshmTouchEntry = Symbol("dshmTouchEntry");';
const entrySchema = [
  '\t\t\tconst schema = this.schema(entry);',
  '\t\t\tif (schema === void 0 || entry.fiber === void 0 || entry.fiber.runtime === null || entry.fiber.state !== 2) return [];',
  '\t\t\tconst form = volatileForm(schema);',
  '\t\t\tif (form === void 0) return [];',
].join('\n');
const entryRevision = [
  '\t\t\tconst raw = JSON.stringify([',
  '\t\t\t\tentry.fiber.uid,',
  '\t\t\t\tschema.toJSON(),',
  '\t\t\t\tentry.options.config ?? {}',
  '\t\t\t]);',
  '\t\t\tconst autoGenerate = this.presentations.get(entry.fiber.ctx.fiber)?.auto ?? true;',
  '\t\t\tconst previous = this.revisions.get(entry.id);',
  '\t\t\tconst revision = previous === void 0 ? 0 : previous.revision + Number(previous.raw !== raw);',
  '\t\t\tthis.revisions.set(entry.id, {',
  '\t\t\t\traw,',
  '\t\t\t\trevision,',
  '\t\t\t\tns: entry.options.id,',
  '\t\t\t\tautoGenerate',
  '\t\t\t});',
  '\t\t\tif (previous?.raw !== raw || previous.autoGenerate !== autoGenerate) this.ownerContext.emit("settings/document-updated", entry.options.id, revision);',
].join('\n');

const startupChanges = [
  ['var SettingsForms = class', marker + '\nvar SettingsForms = class'],
  ['\t\t\t\tthis.describe();',
    '\t\t\t\tif (globalThis.__dshmStartupSettingsRevisions === true) this[dshmDescribeForms](undefined, false);\n'
    + '\t\t\t\telse this.describe();'],
  [describe, '\tdescribe(options) {\n\t\treturn this[dshmDescribeForms](options, true);\n\t}\n'
    + '\t[dshmDescribeForms](options, includeValues) {\n\t\tconst active'],
  [listForms, '\t\tconst editor = this.ownerContext.configEditor;\n'
    + '\t\tconst entries = includeValues ? editor.configuration() : editor.entries().map(entry => ({ entry }));\n'
    + '\t\tconst descriptors = entries.flatMap(({ entry, inherited, override }) => {'],
  [renderValues, '\t\t\tif (!includeValues) return [];\n' + renderValues],
];

const writeChanges = [
  [marker, marker + '\n' + touchMarker],
  ['\t[dshmDescribeForms](options, includeValues) {',
    '\tdescribeNamespace(ns, options) {\n\t\treturn this[dshmDescribeForms](options, true, ns)[0];\n\t}\n'
    + '\t[dshmDescribeForms](options, includeValues, namespace) {'],
  ['\t\tconst descriptors = entries.flatMap(({ entry, inherited, override }) => {',
    '\t\tconst selected = namespace === void 0 ? entries : entries.filter(({ entry }) => entry.options.id === namespace);\n'
    + '\t\tconst descriptors = selected.flatMap(({ entry, inherited, override }) => {'],
  [entrySchema + '\n\t\t\tactive.add(entry.id);\n' + entryRevision,
    '\t\t\tconst touched = this[dshmTouchEntry](entry);\n'
    + '\t\t\tif (touched === void 0) return [];\n'
    + '\t\t\tactive.add(entry.id);\n'
    + '\t\t\tconst { form, autoGenerate, revision } = touched;'],
  ['\t\tfor (const [id, previous] of this.revisions) {',
    '\t\tif (namespace !== void 0) return descriptors;\n\t\tfor (const [id, previous] of this.revisions) {'],
  ['\t\t\tconst descriptor = this.describe().find((row) => row.ns === ns);',
    '\t\t\tconst descriptor = this[dshmTouchEntry](entry);'],
  ['\t\tthis.describe();\n\t}\n\tschema(entry) {',
    '\t\tthis[dshmTouchEntry](entry);\n\t}\n'
    + '\t[dshmTouchEntry](entry) {\n'
    + entrySchema.replaceAll('return [];', 'return;').replace(/^\t/gm, '') + '\n'
    + entryRevision.replace(/^\t/gm, '') + '\n'
    + '\t\treturn { form, autoGenerate, revision };\n'
    + '\t}\n\tschema(entry) {'],
];

function replaceOne(source, before, after) {
  if (source.split(before).length !== 2) throw new Error('Review settings startup anchor: ' + before.trim().slice(0, 64));
  return source.replace(before, () => after);
}

export function settingsStartupSource(source, enabled = true) {
  let original = source;
  if (original.includes(touchMarker)) {
    for (const [before, after] of writeChanges.toReversed()) original = replaceOne(original, after, before);
  }
  if (original.includes(marker)) {
    for (const [before, after] of startupChanges.toReversed()) original = replaceOne(original, after, before);
  }
  if (createHash('sha256').update(original).digest('hex') !== upstreamHash) {
    throw new Error('Review upstream settings revisions and startup configuration projection');
  }
  if (!enabled) return original;
  return [...startupChanges, ...writeChanges].reduce((text, [before, after]) => replaceOne(text, before, after), original);
}

export function patchSettingsStartup(stage) {
  const file = join(stage, settingsFile);
  const current = readFileSync(file, 'utf8');
  const next = settingsStartupSource(current);
  if (current === next) return;
  const temp = file + '.dshm-' + process.pid + '.tmp';
  writeFileSync(temp, next);
  renameSync(temp, file);
}
