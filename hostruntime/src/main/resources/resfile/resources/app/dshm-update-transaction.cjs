// Local lifecycle boundary around the official manager, not a replacement manager.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const pending = new Set();

function packageName(name) {
  return typeof name === 'string' && /^(?:@[a-zA-Z0-9._-]+\/)?[a-zA-Z0-9._-]+$/.test(name) &&
    !['.', '..', '__proto__'].includes(name.split('/').pop());
}

function readJson(p) { return JSON.parse(fs.readFileSync(p, 'utf8')); }

function packageSnapshot(profile, name, version, source, before) {
  const saved = before.dependencies?.[name];
  if (typeof saved !== 'string') throw new Error('The installed catalog package has no profile dependency.');
  const root = fs.realpathSync(profile);
  const modules = path.join(root, 'node_modules');
  const dest = path.join(modules, name);
  if (fs.realpathSync(path.dirname(dest)) !== path.dirname(dest)) {
    throw new Error('The catalog package is outside its profile package directory.');
  }
  const entry = fs.lstatSync(dest);
  if (entry.isSymbolicLink()) {
    const destination = fs.realpathSync(dest);
    const relative = path.relative(modules, destination);
    const outsideModules = relative.startsWith('..' + path.sep) || path.isAbsolute(relative);
    if (!saved.startsWith('link:') || !source.startsWith('link:') || !outsideModules ||
        fs.realpathSync(source.slice(5)) !== destination) {
      throw new Error('The catalog package link cannot be restored from the profile snapshot.');
    }
  } else if (!entry.isDirectory()) {
    throw new Error('The catalog package is not an installed directory.');
  }
  const manifest = readJson(path.join(dest, 'package.json'));
  if (manifest.name !== name || manifest.version !== version || !manifest.dsh?.bundle) {
    throw new Error('The installed catalog package no longer matches its profile inventory.');
  }
  return entry;
}

function catalogLockfileStat(profile) {
  const file = path.join(profile, 'pnpm-lock.yaml');
  try {
    const stat = fs.lstatSync(file);
    if (!stat.isFile()) throw new Error('The profile package lockfile is not a regular file.');
    return stat;
  }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return undefined;
  }
}

function readCatalogLockfile(profile) {
  const stat = catalogLockfileStat(profile);
  return stat ? { mode: stat.mode, bytes: fs.readFileSync(path.join(profile, 'pnpm-lock.yaml')) } : undefined;
}

function canReplaceCatalog(profile, name, version, source, rowIds) {
  if (!packageName(name)) return false;
  try {
    packageSnapshot(profile, name, version, source, readJson(path.join(profile, 'package.json')));
    catalogLockfileStat(profile);
    captureRows(profile, new Set([name, ...rowIds]));
    return true;
  } catch {
    return false;
  }
}

// DSHM writes top-level YAML sequence blocks. Preserve complete target blocks,
// including config/disabled fields; never restore an entire mutable user file.
function blocks(text) {
  return text.match(/^- [\s\S]*?(?=^- |$(?![\s\S]))/gm) || [];
}

function blockKey(block) {
  const id = /^(?:- |  )id:\s*(?:'([^']*)'|"([^"]*)"|([^\s#]+))/m.exec(block);
  const match = id || /^(?:- |  )name:\s*(?:'([^']*)'|"([^"]*)"|([^\s#]+))/m.exec(block);
  return match ? (match[1] || match[2] || match[3]) : '';
}

function captureRows(profile, identities) {
  return ['.dshm-plugin-rows.yml', 'cordis.patch.yml'].map(file => {
    const location = path.join(profile, file);
    const text = fs.existsSync(location) ? fs.readFileSync(location, 'utf8') : '';
    // Reject non-block/anchor/tag forms before any remove. No regex rewriting of
    // legal YAML whose reference graph cannot safely be preserved locally.
    if (/^[ \t]*[^#\n]*[&*][A-Za-z0-9_-]+/m.test(text) ||
      /^(?:\[|\{|---)|^-\s*(?:\{|&|!)/m.test(text)) {
      throw new Error('此配置含YAML引用/flow/tag结构，无法安全局部恢复；更新未开始，旧包保持不变：' + location);
    }
    const sequence = blocks(text);
    return { location, original: sequence, saved: sequence.filter(block => identities.has(blockKey(block))) };
  });
}

function restoreRows(rows, identities) {
  for (const item of rows) {
    const current = fs.existsSync(item.location) ? fs.readFileSync(item.location, 'utf8') : '';
    const all = blocks(current);
    let restored = current;
    for (const block of all) {
      if (identities.has(blockKey(block))) restored = restored.replace(block, '');
    }
    // Reinsert at the original neighbour, not at EOF (preserve ordering).
    for (const block of item.saved) {
      const index = item.original.indexOf(block);
      const currentBlocks = blocks(restored);
      const nextIdentity = item.original.slice(index + 1).map(blockKey).find(key =>
        key && !identities.has(key) && currentBlocks.some(candidate => blockKey(candidate) === key));
      const next = nextIdentity ? currentBlocks.find(candidate => blockKey(candidate) === nextIdentity) : undefined;
      if (next) restored = restored.replace(next, block + next);
      else restored += (restored.endsWith('\n') || !restored ? '' : '\n') + block;
    }
    if (restored !== current) {
      const tmp = item.location + '.restore-' + crypto.randomUUID();
      fs.writeFileSync(tmp, restored);
      fs.renameSync(tmp, item.location);
    }
  }
}

function restoreManifest(profile, before, name) {
  const file = path.join(profile, 'package.json');
  const current = readJson(file);
  for (const field of ['dependencies', 'peerDependencies']) {
    if (before[field] && Object.hasOwn(before[field], name)) {
      current[field] ||= {};
      current[field][name] = before[field][name];
    } else if (current[field]) {
      delete current[field][name];
    }
  }
  const oldBundles = before.dsh?.profile?.bundles;
  const currentBundles = current.dsh?.profile?.bundles;
  if (Array.isArray(oldBundles) || (Array.isArray(currentBundles) && currentBundles.includes(name))) {
    current.dsh ||= {};
    current.dsh.profile ||= {};
    const bundles = Array.isArray(currentBundles) ? currentBundles : [];
    const kept = bundles.filter(x => x !== name);
    const at = Array.isArray(oldBundles) ? oldBundles.indexOf(name) : -1;
    if (at >= 0) kept.splice(Math.min(at, kept.length), 0, name);
    current.dsh.profile.bundles = kept;
  }
  const tmp = file + '.dshm-restore-' + crypto.randomUUID();
  fs.writeFileSync(tmp, JSON.stringify(current, null, 2) + '\n');
  fs.renameSync(tmp, file);
}

async function withUpdateTransaction(profile, name, from, to, operation, lifecycle = {}) {
  if (!packageName(name)) throw new Error('Unsafe update package identity');
  profile = path.resolve(profile);
  const key = profile + '\0' + name;
  if (pending.has(key)) throw new Error('Package update already in progress');
  const catalog = typeof lifecycle.catalogSource === 'string';
  const dest = path.join(profile, 'node_modules', name);
  if (!catalog && !fs.existsSync(dest)) return operation();
  const before = readJson(path.join(profile, 'package.json'));
  if (!catalog && !Object.hasOwn(before.dependencies || {}, name)) return operation();
  const previousEntry = catalog ? packageSnapshot(profile, name, from, lifecycle.catalogSource, before) : undefined;
  const lockfile = catalog ? readCatalogLockfile(profile) : undefined;
  const lockfilePath = path.join(profile, 'pnpm-lock.yaml');
  const rowIds = typeof lifecycle.rowIds === 'function' ? lifecycle.rowIds() : lifecycle.rowIds;
  const identities = new Set([name, ...(rowIds || [])]);
  const rows = captureRows(profile, identities);
  const restoreCatalogRows = () => restoreRows(rows, identities);
  const restoreLockfile = () => {
    if (!catalog) return;
    if (lockfile === undefined) {
      fs.rmSync(lockfilePath, { force: true });
      return;
    }
    const temp = lockfilePath + '.dshm-restore-' + crypto.randomUUID();
    fs.writeFileSync(temp, lockfile.bytes, { mode: lockfile.mode });
    fs.renameSync(temp, lockfilePath);
  };
  const restoreConfiguration = async () => {
    restoreManifest(profile, before, name);
    restoreRows(rows, identities);
    restoreLockfile();
    const selected = (before.dsh?.profile?.bundles || []).includes(name);
    const runtime = typeof lifecycle.reconcile === 'function'
      ? await lifecycle.reconcile(selected ? [...(rowIds || [])] : [])
      : { restartReason: 'local-package-restored' };
    return lifecycle.hasHmr === false ? { ...runtime, restartReason: 'no-hmr' } : runtime;
  };
  const owned = fs.mkdtempSync(path.join(profile, '.dshm-update-'));
  const backup = path.join(owned, 'package');
  const copyOptions = { recursive: true, dereference: false, verbatimSymlinks: catalog };
  const restorePackage = () => {
    fs.rmSync(dest, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.cpSync(backup, dest, copyOptions);
  };
  const originalStillPresent = () => {
    if (!previousEntry) return false;
    try {
      const currentEntry = packageSnapshot(profile, name, from, lifecycle.catalogSource,
        readJson(path.join(profile, 'package.json')));
      const currentLockfile = readCatalogLockfile(profile);
      return previousEntry.ino === currentEntry.ino && previousEntry.dev === currentEntry.dev &&
        (lockfile ? currentLockfile?.bytes.equals(lockfile.bytes) === true : currentLockfile === undefined);
    } catch {
      return false;
    }
  };
  let prepared = false;
  let operationStarted = false;
  let recoveryAttempted = false;
  pending.add(key);
  try {
    if (catalog) fs.cpSync(dest, backup, copyOptions);
    else fs.cpSync(dest, backup, { recursive: true, dereference: false });
    fs.writeFileSync(path.join(owned, 'transaction.json'), JSON.stringify({
      id: crypto.randomUUID(), profile, name, from, to,
      source: before.dependencies?.[name], state: 'prepared'
    }));
    prepared = true;
    // Official code still performs remove/install/enable and previous-source recovery.
    operationStarted = true;
    const result = await operation(restoreCatalogRows);
    // Official refusal is not permission to replace an untouched installation.
    if (result?.step === 'check' || result?.step === 'remove') {
      const partialRemoval = catalog && result.step === 'remove' && (result.result.changed || !originalStillPresent());
      if (!partialRemoval) {
        fs.rmSync(owned, { recursive: true, force: true });
        return result;
      }
    }
    const application = result?.result?.application;
    const failed = application === 'failed' || application === 'cancelled' || (catalog && application !== 'applied' &&
      application !== 'restart-required');
    if (!failed) {
      fs.rmSync(owned, { recursive: true, force: true });
      return result;
    }
    if (result.restore && result.restore.application !== 'failed' && result.restore.application !== 'cancelled') {
      const runtime = await restoreConfiguration();
      Object.assign(result.restore, runtime);
      if (runtime.restartReason) result.restore.application = 'restart-required';
      fs.rmSync(owned, { recursive: true, force: true });
      return result;
    }
    // Final recovery is local and cannot lose the first snapshot to a failed enable/remove.
    recoveryAttempted = true;
    // Keep complete backup until both package and configuration have recovered.
    restorePackage();
    const runtime = await restoreConfiguration();
    const notice = runtime.restartReason
      ? '旧包及用户配置已本地恢复；需要重启应用完成恢复' : '旧包、用户配置及运行态已本地恢复';
    result.result.error ||= { code: 'operation-error', diagnostic: '' };
    result.result.error.diagnostic = (result.result.error.diagnostic || '') + '；' + notice;
    result.restore = { changed: true, application: runtime.restartReason ? 'restart-required' : 'applied',
      stage: 'install', target: name, ...runtime };
    result.localRestore = { application: 'restart-required', target: name, diagnostic: notice };
    fs.rmSync(owned, { recursive: true, force: true });
    return result;
  } catch (error) {
    // Preserve evidence/backup if recovery itself cannot safely finish.
    if (!prepared || !operationStarted) {
      // A partial copy is never a recovery source. Original dest was not touched.
      try { fs.rmSync(owned, { recursive: true, force: true }); } catch {}
    } else if (!recoveryAttempted && (catalog || fs.existsSync(backup))) {
      try {
        restorePackage();
        await restoreConfiguration();
        fs.rmSync(owned, { recursive: true, force: true });
      } catch (restoreError) {
        error.message += '; local restore pending at ' + owned + ': ' + restoreError.message;
      }
    }
    throw error;
  } finally {
    pending.delete(key);
  }
}

withUpdateTransaction.canReplaceCatalog = canReplaceCatalog;
module.exports = { withUpdateTransaction };
