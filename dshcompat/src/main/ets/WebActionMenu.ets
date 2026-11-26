/**
 * Mirrors supported workbench menus without painting the Web popup. The
 * capture listener installs the mask before React handles the trusted click.
 */
export const WEB_ACTION_MENU_SHIM_JS: string = `(function () {
  if (window.top !== window || !/^http:\\/\\/127\\.0\\.0\\.1:[0-9]+$/.test(location.origin) ||
    window.__DSHM_ACTION_MENU__) { return; }

  var accountTrigger = 'button[data-signed-out][data-collapsed][aria-haspopup="menu"]';
  var menuTrigger = '[aria-haspopup="menu"][aria-expanded]';
  var itemSelector = '[role="menuitem"],[role="menuitemcheckbox"],[role="menuitemradio"]';
  var menuSelector = '[role="menu"]';
  var existing = 'data-dshm-native-menu-existing';
  var capturing = 'data-dshm-native-menu-capture';
  var covered = 'data-dshm-native-menu-source';
  var style;
  var current;
  var requestId = 0;

  function startCapture(entry) {
    var root = document.documentElement;
    if (!style) {
      style = document.createElement('style');
      style.textContent = 'html[' + capturing + '] [role="menu"]:not([' + existing + ']),' +
        '[role="menu"][' + covered + '] { opacity: 0 !important; pointer-events: none !important; }' +
        '[role="menu"][' + covered + '] { visibility: hidden !important; }';
    }
    if (!style.isConnected) { (document.head || root).appendChild(style); }
    entry.before = Array.from(document.querySelectorAll(menuSelector)).filter(function (menu) {
      return !menu.hasAttribute(covered) && menu.getBoundingClientRect().width > 0;
    });
    entry.before.forEach(function (menu) { menu.setAttribute(existing, ''); });
    root.setAttribute(capturing, '');
  }

  function endCapture(entry) {
    document.documentElement.removeAttribute(capturing);
    entry.before.forEach(function (menu) { menu.removeAttribute(existing); });
  }

  function inspectMenu(node) {
    if (node.querySelector('[role="menu"], [aria-haspopup="menu"], input, select, textarea')) { return null; }
    var items = Array.from(node.querySelectorAll(itemSelector));
    if (!items.length || items.length > 32 || items.some(function (item) {
      return typeof item.click !== 'function';
    })) { return null; }
    var lines = items.map(function (item) {
      var text = item.querySelector('span[class*="itemLabel"]');
      var label = (item.getAttribute('aria-label') || (text || item).textContent).trim().replace(/\\s+/g, ' ');
      if (!label || label.length > 80) { return ''; }
      var disabled = item.disabled || item.getAttribute('aria-disabled') === 'true';
      var selected = item.getAttribute('aria-checked') === 'true' || item.getAttribute('aria-selected') === 'true' ||
        item.getAttribute('aria-current') === 'true';
      return String((disabled ? 1 : 0) | (selected ? 2 : 0)) + label;
    });
    if (lines.some(function (line) { return !line; })) { return null; }
    return { node: node, items: items, rows: lines.join('\\n') };
  }

  function whenOpen(entry, visit, frames) {
    requestAnimationFrame(function () {
      if (current !== entry) { return; }
      if (entry.trigger.isConnected && entry.trigger.getAttribute('aria-expanded') === 'true') {
        var menus = Array.from(document.querySelectorAll(menuSelector)).filter(function (menu) {
          return entry.before.indexOf(menu) < 0 && menu.getBoundingClientRect().width > 0 &&
            menu.getAttribute('aria-hidden') !== 'true' && !menu.hasAttribute(covered);
        });
        if (menus.length === 1) { visit(inspectMenu(menus[0])); return; }
        if (menus.length > 1) { visit(null); return; }
      }
      if (entry.trigger.isConnected && frames > 1) { whenOpen(entry, visit, frames - 1); }
      else { visit(null); }
    });
  }

  function cover(menu) {
    menu.node.setAttribute(covered, '');
  }

  function focusTrigger(entry) {
    if (entry.trigger.isConnected) { entry.trigger.focus({ preventScroll: true }); }
  }

  function select(menu, index) {
    var item = menu.items[index];
    if (item && item.isConnected && !item.disabled && item.getAttribute('aria-disabled') !== 'true') {
      item.click();
    }
  }

  document.addEventListener('click', function (event) {
    if (!event.isTrusted || current || !(event.target instanceof Element)) { return; }
    var trigger = event.target.closest(menuTrigger);
    if (!trigger || trigger.getAttribute('aria-expanded') !== 'false') { return; }
    var category = trigger.closest(accountTrigger) ? 'account' :
      trigger.closest('[class*="panelRow"]') ? 'sidebar' :
      trigger.closest('[class*="viewsMore"]') ? 'navigation' :
      trigger.hasAttribute('data-context-menu-trigger') ? 'context' : 'action';
    var b = window.__DSHM_BRIDGES__;
    if (!b || typeof b.openWebActionMenu !== 'function') { return; }

    var entry = { id: ++requestId, trigger: trigger, menu: null };
    current = entry;
    startCapture(entry);
    whenOpen(entry, function (menu) {
      var accepted = false;
      if (menu && window.getComputedStyle(menu.node).opacity === '0') {
        var anchor = trigger.getBoundingClientRect();
        var rect = menu.node.getBoundingClientRect();
        var above = category === 'account' || (category !== 'sidebar' && rect.bottom <= anchor.top + 1);
        var y = above ? anchor.top : anchor.bottom;
        try {
          accepted = b.openWebActionMenu(entry.id,
            Math.min(1, Math.max(0, anchor.left / window.innerWidth)),
            Math.min(1, Math.max(0, y / window.innerHeight)), category, menu.rows, above) === true;
        } catch (e) { /* Reveal the Web popup below. */ }
      }
      if (accepted) {
        entry.menu = menu;
        cover(menu);
      } else {
        current = null;
      }
      endCapture(entry);
    }, 4);
  }, true);

  window.__DSHM_ACTION_MENU__ = {
    finish: function (id, action) {
      var entry = current;
      if (!entry || entry.id !== id || !entry.menu) { return; }
      var menu = entry.menu;
      entry.menu = null;
      if (!entry.trigger.isConnected) { current = null; return; }
      var open = menu.node.isConnected && entry.trigger.getAttribute('aria-expanded') === 'true';

      if (action === -2 && open) {
        menu.node.removeAttribute(covered);
        current = null;
        return;
      }
      if (action === -1) {
        if (open) { entry.trigger.click(); }
        focusTrigger(entry);
        current = null;
        return;
      }
      if (open) {
        // Leave the source masked through its original closing animation.
        select(menu, action);
        current = null;
        return;
      }
      if (entry.trigger.getAttribute('aria-expanded') !== 'false') { current = null; return; }
      if (action === -2) {
        entry.trigger.click();
        current = null;
        return;
      }
      // ArkUI can take focus and dismiss the source. Reopen under the same
      // mask, and only dispatch when the original entries still match.
      startCapture(entry);
      entry.trigger.click();
      whenOpen(entry, function (reopened) {
        if (reopened && reopened.rows === menu.rows) {
          cover(reopened);
          select(reopened, action);
        }
        current = null;
        endCapture(entry);
      }, 4);
    }
  };
})();`;
