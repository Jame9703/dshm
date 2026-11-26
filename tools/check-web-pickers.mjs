#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../dshcompat/src/main/ets/WebPicker.ets', import.meta.url), 'utf8');
const literal = source.match(/= (`[\s\S]+`);/)[1];
const shell = readFileSync(new URL('../entry/src/main/ets/pages/WebApp.ets', import.meta.url), 'utf8');
const nativePicker = readFileSync(new URL('../entry/src/main/ets/common/DesktopWebPicker.ets', import.meta.url), 'utf8');
const nativePanel = readFileSync(new URL('../entry/src/main/ets/common/WebPickerPanel.ets', import.meta.url), 'utf8');

const choiceCheck = nativePicker.match(/function canUsePickerMenu\([^]*?\n\}/)[0];
const canUsePickerMenu = runInNewContext(stripTypeScriptTypes(choiceCheck + '\ncanUsePickerMenu'));
const choice = { title: '', search: '', status: '', empty: '',
  rows: [{ label: 'Standard', detail: 'Daily tasks', group: '', stay: false, drill: false }] };
assert.equal(canUsePickerMenu(choice), true);
assert.equal(canUsePickerMenu({ ...choice, rows: Array.from({ length: 12 }, () => choice.rows[0]) }), true);
for (const state of [{ search: 'Search' }, { status: 'Loading' }, { title: 'Model' },
  { rows: [{ ...choice.rows[0], group: 'Provider' }] },
  { rows: [{ ...choice.rows[0], stay: true, drill: true }] }]) {
  assert.equal(canUsePickerMenu({ ...choice, ...state }), false);
}
assert.match(nativePicker, /\? this\.openMenu\(dialog, left,[^]*?: this\.openPanel\(dialog,/);
assert.match(nativePicker, /systemMaterial:\s*pickerMaterial\(true\),[^]*?getPromptAction\(\)\.openMenu\(dialog\.content/);
assert.match(nativePanel, /MenuItem\(\{ content: row\.detail\.length > 0 \? row\.label \+ '\\n' \+ row\.detail : row\.label \}\)/);

function fixture(script, accept = true) {
  const events = [];
  const native = {
    openWebPicker(id, x, top, bottom, wire) {
      events.push({ type: 'open', id, x, top, bottom, wire });
      return accept;
    },
    updateWebPicker(id, wire) {
      events.push({ type: 'update', id, wire });
      return true;
    },
    closeWebPicker(id) { events.push({ type: 'close', id }); }
  };
  const window = { innerWidth: 200, innerHeight: 120, __DSHM_BRIDGES__: native };
  window.top = window;
  runInNewContext(script, { window, location: { origin: 'http://127.0.0.1:3120' } });
  const controller = window.__DSHM_NATIVE_PICKERS__;
  const anchor = { isConnected: true, getBoundingClientRect: () => ({ left: 40, top: 30, bottom: 60, width: 30 }) };
  const slots = [];
  const cleanups = [];
  let frame = [];
  let index = 0;
  let needsRender = false;
  const React = {
    useRef(value) {
      const at = index++;
      return slots[at] ??= { current: value };
    },
    useState(initial) {
      const at = index++;
      slots[at] ??= initial;
      return [slots[at], value => {
        if (slots[at] !== value) { slots[at] = value; needsRender = true; }
      }];
    },
    useLayoutEffect(effect, dependencies) {
      const at = index++;
      if (dependencies?.length === 0 && slots[at]) { return; }
      slots[at] = true;
      frame.push(() => {
        const cleanup = effect();
        if (cleanup) { cleanups.push(cleanup); }
      });
    }
  };
  return {
    events, controller, anchor,
    render(open, page, onClose) {
      const observed = [];
      for (let iteration = 0; iteration < 8; iteration++) {
        index = 0;
        frame = [];
        needsRender = false;
        observed.push(controller.usePicker(React, open, () => anchor, () => page, onClose));
        frame.forEach(effect => effect());
        if (!needsRender) { return observed; }
      }
      throw new Error('Native picker layout did not settle');
    },
    unmount() { cleanups.forEach(cleanup => cleanup()); }
  };
}

function verify(sourceLiteral) {
  const script = runInNewContext(sourceLiteral);
  const picker = fixture(script);
  const chosen = [];
  const queries = [];
  let closed = 0;
  const close = () => { closed++; };
  const start = { title: 'Model', rows: [
    { key: 'drill', label: 'Models', stay: true, drill: true, run: () => chosen.push('drill') }
  ] };
  assert.deepEqual(picker.render(true, start, close), [false], 'Web portal must stay unmounted');
  const { id } = picker.events[0];
  assert.deepEqual(picker.events[0], { type: 'open', id, x: .2, top: .25, bottom: .5,
    wire: 'Model||||\n12|drill|Models||' });
  assert.equal(picker.controller.owns(picker.anchor), true);
  picker.controller.event(id, 'select', 'drill');
  assert.deepEqual(chosen, ['drill']);
  assert.equal(closed, 0);

  const models = { title: '模型', search: '搜索', query: 'x|中', onSearch: value => queries.push(value),
    rows: [
      { key: 'unavailable', label: 'Busy', disabled: true, run: () => chosen.push('wrong') },
      { key: 'a|b', label: '已选\n中', group: 'Provider', selected: true, run: () => chosen.push('model') }
    ] };
  assert.deepEqual(picker.render(true, models, close), [false]);
  assert.equal(picker.events.length, 2);
  assert.equal(picker.events[1].type, 'update');
  const wire = picker.events[1].wire.split('\n');
  assert.equal(decodeURIComponent(wire[0].split('|')[2]), 'x|中');
  assert.deepEqual(wire[2].split('|').map(decodeURIComponent), ['1', 'a|b', '已选\n中', '', 'Provider']);
  picker.render(true, models, close);
  assert.equal(picker.events.length, 2, 'Identical React renders must not update the native dialog');
  picker.controller.event(id + 1, 'select', 'a|b');
  picker.controller.event(id, 'select', 'unavailable');
  picker.controller.event(id, 'search', 'typed');
  assert.deepEqual(queries, ['typed']);
  picker.controller.event(id, 'select', 'a|b');
  assert.deepEqual(chosen, ['drill', 'model']);
  assert.equal(closed, 1);
  assert.deepEqual(picker.render(false, models, close), [false, false]);

  const rejection = fixture(script, false);
  assert.deepEqual(rejection.render(true, models, close), [false, true]);

  const exit = fixture(script);
  exit.render(true, models, close);
  exit.unmount();
  assert.deepEqual(exit.events.map(event => event.type), ['open', 'close']);

  const extension = fixture(script);
  const custom = { rows: [{ key: 'extra', label: 'Extension', stay: true, run: fallback => fallback() }] };
  assert.deepEqual(extension.render(true, custom, close), [false]);
  extension.controller.event(extension.events[0].id, 'select', 'extra');
  assert.deepEqual(extension.events.map(event => event.type), ['open', 'close']);
  assert.deepEqual(extension.render(true, custom, close), [true]);
}

for (const method of ['openWebPicker', 'updateWebPicker', 'closeWebPicker']) {
  assert.ok(shell.includes("'" + method + "':") && shell.match(/methodList:\s*\[[^\]]*\]/)[0].includes("'" + method + "'"),
    method + ' is not registered in the desktop bridge');
}
verify(literal);
if (process.argv.includes('--self-test')) {
  for (const mutation of [
    literal.replace("return open && phase === 'web';", 'return open;'),
    literal.replace('entry.id !== id', 'false'),
    literal.replace('active.wire === payload', 'false')
  ]) {
    assert.notEqual(mutation, literal);
    assert.throws(() => verify(mutation), assert.AssertionError);
  }
}
console.log('PASS native picker pre-render gate, updates, nested actions, search and Web fallback');
