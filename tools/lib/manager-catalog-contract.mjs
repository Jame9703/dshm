import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const MARK = 'DSHM_CATALOG_REPLACEMENT_V1';
const LIST_ANCHOR = 'const target = updateRefusal(bundle, bundle.name);';
const UPDATE_ANCHOR = 'const run = () => this.dshmUpdateBundleInner(name, version, options);';
const INNER_ANCHOR = 'async dshmUpdateBundleInner(name, version, options) {';

function replaceOne(text, anchor, replacement, label) {
  const first = text.indexOf(anchor);
  if (first < 0 || text.indexOf(anchor, first + anchor.length) >= 0) {
    throw new Error('Catalog replacement patch: expected one ' + label);
  }
  return text.replace(anchor, replacement);
}

export function patchManagerCatalog(text) {
  if (text.includes(MARK)) return text;
  text = replaceOne(text, LIST_ANCHOR, `/* ${MARK} */
        if (this.dshmCanReplaceCatalog(bundle)) {
          return { ...bundle, installTarget: { ...bundle.installTarget, catalogUpdate: true } };
        }
        ${LIST_ANCHOR}`, 'bundle inventory anchor');
  text = replaceOne(text, UPDATE_ANCHOR, `if (options?.catalog !== void 0) {
          return this.dshmUpdateCatalog(name, version, options);
        }
        ${UPDATE_ANCHOR}`, 'lifecycle writer anchor');
  return replaceOne(text, INNER_ANCHOR, functionSource() + INNER_ANCHOR, 'update implementation anchor');
}

function functionSource() {
  return String.raw`dshmCanReplaceCatalog(bundle) {
      const target = bundle?.installTarget;
      if (!bundle?.installed || !bundle.official || !bundle.removable || bundle.availability !== "profile" ||
          bundle.error || !bundle.version || !bundle.source || !target?.version ||
          typeof globalThis.__dshmProfileWriter !== "function") return false;
      const preflight = globalThis.__dshmUpdateTransaction?.canReplaceCatalog;
      if (typeof preflight !== "function") return false;
      const expectedRegistry = target.spec === bundle.name + "@" + target.version;
      const changedLink = target.spec !== bundle.source &&
        (target.spec.startsWith("link:") || bundle.source.startsWith("link:"));
      if (target.version === bundle.version && !changedLink) return false;
      if (!expectedRegistry && (!target.spec.startsWith("link:") ||
          globalThis.__dshmCanInstallCatalogLink?.(this.profile.dir, target.spec) !== true)) return false;
      return preflight(this.profile.dir, bundle.name, bundle.version, bundle.source, bundle.rows.map(row => row.rowId));
    }
    async dshmUpdateCatalog(name, version, options) {
      const requestId = options.requestId;
      const announce = (step) => {
        if (requestId !== void 0) this.ownerContext.emit("plugin-manager/update-state", { requestId, step });
      };
      announce("checking");
      const bundle = this.readBundles().find(item => item.name === name);
      const from = bundle?.version ?? "";
      const report = (step, result) => ({ from, to: version, step, result });
      const failure = (stage, error) => ({ changed: false, application: "failed", stage, target: name, error });
      const catalog = options.catalog;
      if (!catalog || options.spec !== void 0 || !this.dshmCanReplaceCatalog(bundle) ||
          catalog.fromVersion !== from || catalog.fromSource !== bundle.source ||
          catalog.targetSpec !== bundle.installTarget.spec || version !== bundle.installTarget.version) {
        return report("check", failure("install", {
          code: "invalid-spec", diagnostic: "The installed plugin or catalog target changed. Refresh before updating."
        }));
      }
      const { enabled, source } = bundle;
      const { spec } = bundle.installTarget;
      const local = spec.startsWith("link:");
      let registry;
      if (local) {
        try {
          const manifest = JSON.parse(readFileSync(spec.slice(5) + "/package.json", "utf8"));
          if (manifest.name !== name || manifest.version !== version || !manifest.dsh?.bundle) {
            return report("check", failure("install", { code: "unexpected-package" }));
          }
          assertBundlePlatform(manifest.dsh.bundle.platforms, process.platform);
          const compatibility = evaluatePluginCompatibility(manifest, readProfileVersionExemptions(this.profile.dir));
          if (compatibility !== void 0 && !compatibility.exempted) {
            return report("check", failure("install", { code: "incompatible-version", incompatible: [incompatiblePlugin(compatibility)] }));
          }
        } catch (error) {
          return report("check", failure("install", managementError(error)));
        }
      } else {
        const plan = await this.checkRegistryUpdate(name, version, { registry: options.registry });
        if ("code" in plan) return report("check", failure("install", plan));
        registry = plan.registry;
      }
      const hasHmr = this.ownerContext.get("hmr") !== void 0;
      const failed = change => change.application !== "applied" && change.application !== "restart-required";
      const settled = async (stage, run) => {
        try { return await run(); } catch (error) { return failure(stage, managementError(error)); }
      };
      const rollBack = async result => {
        announce("restoring");
        if (hasHmr && result.stage === "enable") await settled("remove", () => this.removeBundle(name));
        return report("install", result);
      };
      const replace = async (restoreRows) => {
        if (hasHmr) {
          announce("removing");
          const removed = await settled("remove", () => this.removeBundle(name));
          if (failed(removed)) {
            if (removed.changed) announce("restoring");
            return report("remove", removed);
          }
          restoreRows();
        }
        announce("installing");
        const result = await settled("install", () => this.installBundle(spec, {
          enabled, saveExact: !local, expected: { name, version }, requestId, registry,
        }));
        if (failed(result)) return rollBack(result);
        const current = this.readBundles().find(item => item.name === name);
        if (current?.version === version && current.source === spec && current.enabled === enabled) {
          return report("install", result);
        }
        return rollBack({ ...result, application: "failed", changed: true, error: {
          code: "unexpected-package", diagnostic: "The updated plugin does not match the confirmed catalog target or selection."
        } });
      };
      const priorRegistry = this.installedFrom.get(name);
      let accepted = false;
      try {
        const outcome = await globalThis.__dshmUpdateTransaction(this.profile.dir, name, from, version, replace, {
          hasHmr, catalogSource: source, rowIds: bundle.rows.map(row => row.rowId),
          reconcile: ids => this.configure(() => this.publishAndReload(ids))
        });
        accepted = outcome.step === "install" && !failed(outcome.result);
        return outcome;
      } finally {
        if (!accepted) {
          if (priorRegistry === void 0) this.installedFrom.delete(name);
          else this.installedFrom.set(name, priorRegistry);
        }
      }
    }
    `;
}

export function patchManagerCatalogSchema(text) {
  const resultAnchor = "  'installTarget': z.object({";
  const wire = "'catalog': z.strictObject({";
  const marked = text.includes(wire);
  if (marked) return text;
  text = replaceOne(text, resultAnchor, resultAnchor +
    "\n  'catalogUpdate': z.boolean().optional(),", 'catalog target schema');
  const options = /^const _deepseek_ai_dsh_plugin_manager_pluginManager_updateBundle_parameter_2(?:_strict)?\$schema = .*z\.(?:strictObject|object)\(\{$/gm;
  if ([...text.matchAll(options)].length !== 2) throw new Error('Catalog replacement patch: update argument schemas missing');
  text = text.replace(options, (line) => line + `
  'catalog': z.strictObject({
    'fromVersion': z.string(),
    'fromSource': z.string(),
    'targetSpec': z.string(),
  }).optional(),`);
  const argumentContract = {
    type: 'object',
    properties: { fromVersion: { type: 'string' }, fromSource: { type: 'string' }, targetSpec: { type: 'string' } },
    required: ['fromVersion', 'fromSource', 'targetSpec'],
    additionalProperties: false,
  };
  const descriptor = /(create: _deepseek_ai_dsh_plugin_manager_pluginManager_updateBundle_parameter_2(?:_strict)?\$schema,\r?\n\s*jsonSchema: )([^\r\n]+),/g;
  if ([...text.matchAll(descriptor)].length !== 2) throw new Error('Catalog replacement patch: update argument descriptors missing');
  return text.replace(descriptor, (_, before, json) => {
    const schema = JSON.parse(json);
    schema.properties.catalog = argumentContract;
    return before + JSON.stringify(schema) + ',';
  });
}

export function patchManagerCatalogContract(stage) {
  const manager = join(stage, 'node_modules', '@deepseek-ai', 'dsh-plugin-manager', 'lib');
  const files = [
    ['index.js', patchManagerCatalog],
    ['typert.host.js', patchManagerCatalogSchema],
    ['typert.remote-client.js', patchManagerCatalogSchema],
  ].map(([name, patch]) => {
    const file = join(manager, name);
    const source = readFileSync(file, 'utf8');
    return { file, source, patched: patch(source) };
  });
  for (const { file, source, patched } of files) {
    if (source !== patched) writeFileSync(file, patched);
  }
}
