import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repo = fileURLToPath(new URL('../', import.meta.url));
const require = createRequire(path.join(repo, 'package.json'));
const { patchManagerLifecycle } = await import(pathToFileURL(path.join(repo, 'tools/lib/manager-lifecycle.mjs')));
const { patchManagerCatalog } = await import(pathToFileURL(path.join(repo, 'tools/lib/manager-catalog-contract.mjs')));
const { currentToken, withProfileWriter } = require('./hostcore/app/dshm-profile-writer.cjs');
const { withUpdateTransaction } = require('./hostcore/app/dshm-update-transaction.cjs');
const { canInstallCatalogLink, installSpec } = require('./hostcore/app/dshm-installer.js');
const recipe = require('./hostcore/core-recipe.json');
const managerFile = path.join(repo, 'dist/core/work', 'dsh-core-' + recipe.coreVersion,
  'node_modules/@deepseek-ai/dsh-plugin-manager/lib/index.js');
const managerSource = patchManagerCatalog(patchManagerLifecycle(fs.readFileSync(managerFile, 'utf8')));
function extract(source, from, to) {
  const start = source.indexOf(from);
  const end = source.indexOf(to, start + from.length);
  assert.ok(start >= 0 && end > start, 'compiled manager anchors');
  return source.slice(start, end);
}
const list = extract(managerSource, '\n\t\tlistBundles() {', '\n\t\t/** The bundle inventory before update eligibility');
const update = extract(managerSource, 'async updateBundle(name, version, options)', 'async dshmUpdateBundleInner(name, version, options)');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dshm-catalog-update-'));
const external = path.join(root, 'checkout-package');
const previousCheckout = path.join(root, 'previous-checkout');
const name = '@deepseek-ai/test-catalog';
const rowId = 'catalog-plugin-row';
const oldVersion = '1.2.3';
const newVersion = '1.2.4';
const config = '- id: ' + rowId + '\n  config: { value: keep }\n';
const oldLock = 'snapshot-old-lockfile\n';
const changedLock = 'changed-lockfile\n';
const createManager = (updateMethods) => vm.runInNewContext('class Manager { ' + list + updateMethods + ' }\nManager', {
  __dshmProfileWriter: withProfileWriter,
  __dshmUpdateTransaction: withUpdateTransaction,
  __dshmCanInstallCatalogLink: (profileDir, spec) => canInstallCatalogLink(spec, { profileDir, trustedLinkRoot: root }),
  readFileSync: fs.readFileSync,
  process,
  assertBundlePlatform: () => {},
  evaluatePluginCompatibility: () => undefined,
  readProfileVersionExemptions: () => [],
  updateRefusal: () => 'official',
  managementError: error => ({ code: 'operation-error', diagnostic: error.message }),
});
function writeJson(file, value) {
  fs.writeFileSync(file, JSON.stringify(value));
}
function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function writePackage(directory, version) {
  fs.mkdirSync(directory, { recursive: true });
  writeJson(path.join(directory, 'package.json'), { name, version, main: 'index.js', dsh: { bundle: { patch: 'patch.yml' } } });
  fs.writeFileSync(path.join(directory, 'index.js'), 'module.exports = {};\n');
  fs.writeFileSync(path.join(directory, 'patch.yml'), '[]\n');
}
function createSourceLink(destination, source) {
  fs.rmSync(destination, { recursive: true, force: true });
  fs.symlinkSync(source, destination, process.platform === 'win32' ? 'junction' : 'dir');
}

async function verify(scenario, Manager = createManager(update)) {
  const profile = fs.mkdtempSync(path.join(root, scenario + '-'));
  const destination = path.join(profile, 'node_modules', name);
  const lockfile = path.join(profile, 'pnpm-lock.yaml');
  const configFile = path.join(profile, 'cordis.patch.yml');
  const profileFile = path.join(profile, 'package.json');
  const sameVersionLink = scenario === 'same-version-link';
  const startedWithLink = scenario === 'link-failure' || sameVersionLink;
  const unsupportedLink = scenario === 'no-advertisement';
  const enabled = scenario !== 'disabled' && !sameVersionLink;
  const version = sameVersionLink || unsupportedLink ? oldVersion : newVersion;
  const oldSource = startedWithLink ? 'link:' + previousCheckout : oldVersion;
  const targetSpec = sameVersionLink ? 'link:' + external : unsupportedLink ? 'link:' + root : name + '@' + version;
  const hmr = !sameVersionLink && scenario !== 'disabled';
  const requests = [];
  const events = [];
  let restores = 0;
  function setProfile(spec, selected) {
    writeJson(profileFile, { dependencies: { [name]: spec }, dsh: { profile: { bundles: selected ? [name] : [] } } });
  }

  writePackage(destination, oldVersion);
  if (startedWithLink) createSourceLink(destination, previousCheckout);
  setProfile(oldSource, enabled);
  fs.writeFileSync(lockfile, oldLock);
  fs.writeFileSync(configFile, config);

  const manager = new Manager();
  manager.profile = { dir: profile };
  manager.installedFrom = new Map([[name, 'old-registry']]);
  manager.ownerContext = { get: key => key === 'hmr' && hmr ? {} : undefined, emit: (event, value) => events.push([event, value]) };
  manager.configure = async run => run();
  manager.publishAndReload = async ids => {
    restores++;
    assert.equal(ids.join(','), enabled ? rowId : '');
    return { warnings: [] };
  };
  manager.readBundles = () => {
    if (!fs.existsSync(destination)) return [];
    const pkg = readJson(path.join(destination, 'package.json'));
    const state = readJson(profileFile);
    const source = state.dependencies[name];
    return [{
      name, official: true, removable: true, installed: typeof source === 'string', availability: 'profile',
      version: pkg.version, source: source?.startsWith('link:') ? source : name + '@' + source,
      enabled: state.dsh.profile.bundles.includes(name), rows: [{ rowId }], installTarget: { spec: targetSpec, version },
    }];
  };
  manager.checkRegistryUpdate = async (calledName, targetVersion) => {
    requests.push('preflight');
    assert.equal(calledName, name);
    assert.equal(targetVersion, version);
    return { registry: null };
  };
  manager.removeBundle = async () => {
    requests.push('remove');
    manager.installedFrom.delete(name);
    if (scenario === 'remove-failure') {
      setProfile(oldSource, false);
      fs.writeFileSync(lockfile, changedLock);
      return { application: 'failed', stage: 'remove', changed: true, error: { code: 'operation-error' } };
    }
    fs.rmSync(destination, { recursive: true, force: true });
    setProfile(undefined, false);
    fs.writeFileSync(configFile, '- id: other\n');
    return { application: 'applied', stage: 'remove', changed: true };
  };
  manager.installBundle = async (spec, options) => {
    assert.equal(spec, targetSpec);
    assert.equal(options.enabled, enabled);
    assert.equal(options.saveExact, !sameVersionLink);
    assert.equal(options.expected.name, name);
    assert.equal(options.expected.version, version);
    assert.equal(options.requestId, 'probe');
    assert.ok(fs.readFileSync(configFile, 'utf8').includes(config));
    requests.push('install');
    fs.writeFileSync(lockfile, changedLock);
    if (scenario === 'install-failure' || scenario === 'link-failure') {
      return { application: 'failed', stage: 'install', changed: false, error: { code: 'operation-error' } };
    }
    if (sameVersionLink) {
      const installed = await installSpec(spec, { homeDir: root, profileDir: profile,
        writerToken: currentToken(profile), expected: options.expected, enabled: options.enabled, trustedLinkRoot: root });
      assert.equal(installed.ok, true, installed.error);
      assert.equal(fs.realpathSync(destination), external);
    } else {
      writePackage(destination, version);
      setProfile(version, scenario === 'wrong-outcome' ? false : enabled);
    }
    return { application: hmr ? 'applied' : 'restart-required', stage: 'enable', changed: true };
  };

  const [offered] = await manager.listBundles();
  assert.equal(offered.installTarget.catalogUpdate, unsupportedLink ? undefined : true, scenario + ' capability');
  const outcome = await manager.updateBundle(name, version, {
    requestId: 'probe',
    catalog: { fromVersion: scenario === 'stale' ? '0.0.0' : oldVersion, fromSource: scenario === 'stale-source' ? 'old-source' : offered.source, targetSpec },
  });
  const failed = ['stale', 'stale-source', 'remove-failure', 'install-failure', 'wrong-outcome', 'link-failure', 'no-advertisement']
    .includes(scenario);
  assert.equal(outcome.result.application, failed ? 'failed' : hmr ? 'applied' : 'restart-required');
  assert.ok(events.every(([event, value]) => event === 'plugin-manager/update-state' && value.requestId === 'probe'));
  if (scenario === 'stale' || scenario === 'stale-source' || unsupportedLink) {
    assert.deepEqual(requests, []);
  } else if (failed) {
    assert.equal(restores, 1);
    assert.equal(outcome.restore.application, 'applied');
    assert.equal(manager.readBundles()[0].source, offered.source);
    assert.equal(manager.readBundles()[0].enabled, enabled);
    assert.equal(fs.readFileSync(lockfile, 'utf8'), oldLock);
    assert.equal(manager.installedFrom.get(name), 'old-registry');
    if (startedWithLink) assert.equal(fs.realpathSync(destination), previousCheckout);
  } else {
    const [current] = manager.readBundles();
    assert.equal(current.source, targetSpec);
    assert.equal(current.enabled, enabled);
    assert.equal(requests.includes('remove'), hmr);
    assert.equal(restores, 0);
  }
  assert.equal(fs.readdirSync(profile).some(entry => entry.startsWith('.dshm-update-')), false);
  console.log('PASS ' + scenario);
}

try {
  writePackage(external, oldVersion);
  writePackage(previousCheckout, oldVersion);
  const checkoutManifest = path.join(external, 'package.json');
  const originalBytes = fs.readFileSync(checkoutManifest, 'utf8');
  for (const scenario of ['ok', 'disabled', 'stale', 'stale-source', 'remove-failure', 'install-failure', 'wrong-outcome',
    'same-version-link', 'link-failure', 'no-advertisement']) {
    await verify(scenario);
    assert.equal(fs.readFileSync(checkoutManifest, 'utf8'), originalBytes);
  }
  if (process.argv.includes('--self-test')) {
    const mutant = update.replace('catalog.fromSource !== bundle.source', 'false');
    assert.notEqual(mutant, update, 'stale-source check mutation must apply');
    await assert.rejects(verify('stale-source', createManager(mutant)), { name: 'AssertionError' });
    console.log('PASS stale-source guard mutation rejected');
  }
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
