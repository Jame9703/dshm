/**
 * Native picker transport for the desktop shell. The packaged Web components
 * hand us option metadata and keep ownership of their actions.
 */
export const WEB_PICKER_SHIM_JS: string = `(function () {
  if (window.top !== window || !/^http:\\/\\/127\\.0\\.0\\.1:[0-9]+$/.test(location.origin) ||
    window.__DSHM_NATIVE_PICKERS__) { return; }

  var active;
  var serial = 0;
  function wire(page) {
    var header = [page.title, page.search, page.query, page.status, page.empty].map(field).join('|');
    var rows = page.rows.map(function (row) {
      var flags = Number(!!row.selected) | Number(!!row.disabled) << 1 |
        Number(!!row.stay) << 2 | Number(!!row.drill) << 3;
      return [String(flags), field(row.key), field(row.label), field(row.detail), field(row.group)].join('|');
    });
    return [header].concat(rows).join('\\n');
  }

  function field(text) { return encodeURIComponent(text || ''); }

  function show(anchor, page, onClose, onFallback) {
    var b = window.__DSHM_BRIDGES__;
    if (active || !anchor || !anchor.isConnected || !b || typeof b.openWebPicker !== 'function') { return 0; }
    var bounds = anchor.getBoundingClientRect();
    var width = window.innerWidth;
    var height = window.innerHeight;
    if (bounds.width <= 0 || width <= 0 || height <= 0) { return 0; }
    var clamp = function (n) { return Math.max(0, Math.min(1, n)); };
    try {
      var session = { id: ++serial, anchor: anchor, page: page, onClose: onClose, onFallback: onFallback, wire: wire(page) };
      active = session;
      if (b.openWebPicker(session.id, clamp(bounds.left / width), clamp(bounds.top / height),
        clamp(bounds.bottom / height), session.wire) === true) { return session.id; }
    } catch (e) { /* The Web component uses its own surface. */ }
    active = undefined;
    return 0;
  }

  function close(id) {
    if (!active || active.id !== id) { return; }
    active = undefined;
    try { window.__DSHM_BRIDGES__.closeWebPicker(id); } catch (e) { /* View may have navigated. */ }
  }

  function update(id, page) {
    if (!active || active.id !== id) { return; }
    active.page = page;
    try {
      var payload = wire(page);
      if (active.wire === payload) { return; }
      if (window.__DSHM_BRIDGES__.updateWebPicker(id, payload) === true) {
        active.wire = payload;
        return;
      }
    } catch (e) { /* Fall back to the original choice list. */ }
    var fallback = active.onFallback;
    close(id);
    fallback();
  }

  // Called unconditionally by each packaged React picker on the desktop shell.
  // A layout effect picks the presentation before its Web portal can mount.
  function usePicker(React, open, anchor, getPage, onClose) {
    var session = React.useRef(0);
    var latestClose = React.useRef(onClose);
    latestClose.current = onClose;
    var state = React.useState('');
    var phase = state[0];
    var setPhase = state[1];

    React.useLayoutEffect(function () {
      if (!open) {
        close(session.current);
        session.current = 0;
        if (phase) { setPhase(''); }
        return;
      }
      if (phase) { return; }
      var page = getPage();
      if (!page) {
        close(session.current);
        session.current = 0;
        setPhase('web');
        return;
      }
      if (session.current) {
        update(session.current, page);
        return;
      }
      session.current = show(anchor(), page, function () {
        session.current = 0;
        setPhase('closed');
        latestClose.current();
      }, function () {
        session.current = 0;
        setPhase('web');
      });
      if (!session.current) { setPhase('web'); }
    });

    React.useLayoutEffect(function () {
      return function () { close(session.current); session.current = 0; };
    }, []);

    return open && phase === 'web';
  }

  window.__DSHM_NATIVE_PICKERS__ = {
    owns: function (anchor) { return !!active && active.anchor === anchor; },
    usePicker: usePicker,
    event: function (id, type, value) {
      var entry = active;
      if (!entry || entry.id !== id) { return; }
      if (type === 'search') {
        if (entry.page.onSearch) { entry.page.onSearch(value); }
        return;
      }
      if (type === 'dismiss' || type === 'fallback') {
        active = undefined;
        if (type === 'dismiss') { entry.onClose(); }
        else { entry.onFallback(); }
        return;
      }
      if (type !== 'select') { return; }
      var row = entry.page.rows.find(function (item) { return item.key === value; });
      if (!row || row.disabled) { return; }
      if (!row.stay) {
        active = undefined;
        entry.onClose();
      }
      row.run(function () { close(entry.id); entry.onFallback(); });
    }
  };
})();`;
