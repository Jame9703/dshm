#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../dshcompat/src/main/ets/WebActionMenu.ets', import.meta.url), 'utf8');
const literal = source.match(/= (`[\s\S]+`);/)[1];
const touchSource = readFileSync(new URL('../dshcompat/src/main/ets/TouchFeedback.ets', import.meta.url), 'utf8');
const touchLiteral = touchSource.match(/= (`[\s\S]+`);/)[1];

function fixture(script, options = {}) {
  class Element {
    attrs = new Map();
    isConnected = true;
    tagName = 'BUTTON';
    setAttribute(key, value) { this.attrs.set(key, value); }
    getAttribute(key) { return this.attrs.get(key) ?? null; }
    hasAttribute(key) { return this.attrs.has(key); }
    removeAttribute(key) { this.attrs.delete(key); }
    getBoundingClientRect() { return { width: 120, left: 40, top: 50, bottom: 60 }; }
  }
  const root = new Element();
  const trigger = new Element();
  let menus = [];
  let style;
  let onClick;
  let focusRestored = false;
  const frames = [];
  const calls = [];
  const selections = [];
  const category = options.category ?? 'account';
  trigger.setAttribute('aria-expanded', 'false');
  if (category === 'context') trigger.setAttribute('data-context-menu-trigger', '');
  trigger.closest = selector => (selector.startsWith('[aria-haspopup') ||
    (category === 'account' && selector.includes('data-signed-out')) ||
    (category === 'sidebar' && selector.includes('panelRow')) ||
    (category === 'navigation' && selector.includes('viewsMore'))) ? trigger : null;
  trigger.focus = () => { focusRestored = true; };

  function opacity(menu) {
    const capture = 'data-dshm-native-menu-capture';
    const existing = 'data-dshm-native-menu-existing';
    const covered = 'data-dshm-native-menu-source';
    const rule = style?.textContent ?? '';
    const beforePaint = rule.includes('html[' + capture + '] [role="menu"]:not([' + existing + '])')
      && root.hasAttribute(capture) && !menu.hasAttribute(existing);
    const remainsMasked = rule.includes('[role="menu"][' + covered + ']') && menu.hasAttribute(covered);
    return rule.includes('opacity: 0 !important') && (beforePaint || remainsMasked) ? '0' : '1';
  }

  function newMenu() {
    const menu = new Element();
    menu.getBoundingClientRect = () => ({ width: 120, left: 55, bottom: options.above ? 45 : 95 });
    const items = ['Settings', 'Feedback', 'Account'].map((label, index) => {
      const item = new Element();
      item.textContent = label;
      item.querySelector = () => null;
      item.disabled = index === 1;
      if (options.checked && index === 2) {
        item.setAttribute('aria-checked', 'true');
        item.setAttribute('role', 'menuitemcheckbox');
      }
      item.click = () => {
        selections.push({ index, opacity: opacity(menu) });
        closeMenu();
      };
      return item;
    });
    menu.querySelector = () => options.unsupported ? {} : null;
    menu.querySelectorAll = () => items;
    return menu;
  }

  function closeMenu() {
    trigger.setAttribute('aria-expanded', 'false');
    menus = menus.filter(menu => {
      if (menu.unrelated) { return true; }
      menu.isConnected = false;
      return false;
    });
  }

  trigger.click = () => {
    // The portal mounts in the Web handler, before the next animation frame.
    if (trigger.getAttribute('aria-expanded') === 'true') { closeMenu(); }
    else {
      trigger.setAttribute('aria-expanded', 'true');
      menus.push(newMenu());
    }
  };
  const document = {
    documentElement: root,
    head: { appendChild(value) { style = value; style.isConnected = true; } },
    createElement() { return { isConnected: false, textContent: '' }; },
    querySelectorAll() { return menus; },
    addEventListener(type, callback, capture) {
      assert.equal(type, 'click');
      assert.equal(capture, true);
      onClick = callback;
    }
  };
  const window = {
    innerWidth: 200,
    innerHeight: 100,
    getComputedStyle: menu => ({ opacity: opacity(menu) }),
    __DSHM_BRIDGES__: {
      openWebActionMenu(id, x, y, category, rows, above) {
        calls.push({ id, x, y, category, rows, above, opacity: opacity(menus.at(-1)) });
        if (options.closeOnFocus) { closeMenu(); }
        return options.accept ?? true;
      }
    }
  };
  window.top = window;
  runInNewContext(script, {
    window, document, Element, location: { origin: 'http://127.0.0.1:3120' },
    requestAnimationFrame: fn => frames.push(fn)
  });
  return {
    calls, selections, opacity,
    isHidden(menu) {
      const covered = 'data-dshm-native-menu-source';
      return menu.hasAttribute(covered) &&
        style.textContent.includes('[role="menu"][' + covered + '] { visibility: hidden !important; }');
    },
    get menu() { return menus.at(-1); },
    get focused() { return focusRestored; },
    addUnrelated() {
      const unrelated = newMenu();
      unrelated.unrelated = true;
      menus.push(unrelated);
      return unrelated;
    },
    open() { onClick({ isTrusted: true, target: trigger }); trigger.click(); },
    draw() { frames.splice(0).forEach(callback => callback()); },
    finish(action) { window.__DSHM_ACTION_MENU__.finish(calls.at(-1).id, action); }
  };
}

function verify(template) {
  const script = runInNewContext(template);
  const account = fixture(script);
  const unrelated = account.addUnrelated();
  account.open();
  const accountSource = account.menu;
  assert.equal(account.opacity(accountSource), '0', 'Web menu was visible before the first frame');
  assert.equal(account.opacity(unrelated), '1');
  account.draw();
  assert.deepEqual(account.calls[0], {
    id: 1, x: 0.2, y: 0.5, category: 'account', rows: '0Settings\n1Feedback\n0Account', above: true, opacity: '0'
  });
  assert.equal(account.opacity(accountSource), '0', 'Web menu became visible after native acceptance');
  assert.equal(account.isHidden(accountSource), true, 'Web menu remains visible to accessibility');
  account.finish(0);
  assert.deepEqual(account.selections, [{ index: 0, opacity: '0' }]);

  const context = fixture(script, { category: 'context', closeOnFocus: true });
  context.open();
  assert.equal(context.opacity(context.menu), '0');
  context.draw();
  assert.equal(context.calls[0].category, 'context');
  assert.equal(context.calls[0].y, 0.6);
  assert.equal(context.calls[0].above, false);
  context.finish(2);
  assert.equal(context.opacity(context.menu), '0');
  context.draw();
  assert.deepEqual(context.selections, [{ index: 2, opacity: '0' }]);

  for (const [category, above] of [['sidebar', true], ['navigation', false], ['action', true]]) {
    const menu = fixture(script, { category, above: category === 'action', checked: true });
    menu.open();
    assert.equal(menu.opacity(menu.menu), '0');
    menu.draw();
    assert.deepEqual(menu.calls[0], {
      id: 1, x: 0.2, y: above ? 0.5 : 0.6, category, rows: '0Settings\n1Feedback\n2Account', above, opacity: '0'
    });
    menu.finish(2);
    assert.deepEqual(menu.selections, [{ index: 2, opacity: '0' }]);
  }

  const cancel = fixture(script);
  cancel.open();
  cancel.draw();
  cancel.finish(-1);
  assert.equal(cancel.focused, true);
  assert.equal(cancel.menu, undefined);
  assert.equal(cancel.selections.length, 0);

  for (const options of [{ accept: false }, { unsupported: true }, {}]) {
    const fallback = fixture(script, options);
    fallback.open();
    assert.equal(fallback.opacity(fallback.menu), '0');
    fallback.draw();
    if (!Object.keys(options).length) { fallback.finish(-2); }
    assert.equal(fallback.opacity(fallback.menu), '1', 'the Web fallback did not reappear');
    if (options.unsupported) { assert.equal(fallback.calls.length, 0); }
  }
}

function verifyTouch(template) {
  class Element {
    attrs = new Map();
    setAttribute(key, value) { this.attrs.set(key, value); }
    removeAttribute(key) { this.attrs.delete(key); }
    closest() { return this; }
    matches() { return false; }
  }
  const root = new Element();
  const button = new Element();
  const listeners = new Map();
  let sheet;
  const document = {
    documentElement: root,
    getElementById: () => null,
    createElement: () => ({}),
    head: { appendChild: style => { sheet = style.textContent; } },
    addEventListener: (type, fn) => { listeners.set(type, fn); }
  };
  const window = { addEventListener() {} };
  window.top = window;
  runInNewContext(runInNewContext(template), { window, document, Element, location: { origin: 'http://127.0.0.1:3120' } });
  assert.match(sheet, /:where\(button,[^{}]*\) \{ -webkit-user-select: none; user-select: none; \}/);
  assert.match(sheet, /\[data-dshm-touch\][^{}]+:focus \{ outline: none/);
  assert.match(sheet, /\[data-dshm-touch-pressed\][^{}]* \{ background-image: linear-gradient/);
  const event = { pointerType: 'touch', isPrimary: true, pointerId: 3, target: button };
  listeners.get('pointerdown')(event);
  assert.equal(button.attrs.has('data-dshm-touch-pressed'), true);
  listeners.get('pointerup')({ pointerId: 4 });
  assert.equal(button.attrs.has('data-dshm-touch-pressed'), true);
  listeners.get('pointercancel')(event);
  assert.equal(button.attrs.has('data-dshm-touch-pressed'), false);
  assert.equal(root.attrs.has('data-dshm-touch'), true);
  listeners.get('keydown')();
  assert.equal(root.attrs.has('data-dshm-touch'), false);
}

verify(literal);
verifyTouch(touchLiteral);
if (process.argv.includes('--self-test')) {
  for (const mutation of [
    literal.replace('    startCapture(entry);\n    whenOpen(entry, function (menu)', '    whenOpen(entry, function (menu)'),
    literal.replace('        cover(menu);', ''),
    literal.replace('visibility: hidden !important;', ''),
    literal.replace('        menu.node.removeAttribute(covered);', '')
  ]) {
    assert.notEqual(mutation, literal);
    assert.throws(() => verify(mutation), assert.AssertionError);
  }
}
console.log('PASS Web action menu capture, retained masking, action replay, focus and fallback');
