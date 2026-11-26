import { webview } from '@kit.ArkWeb';

export function finishWebTouchFeedback(event: TouchEvent, controller: webview.WebviewController): void {
  if (event.type !== TouchType.Up && event.type !== TouchType.Cancel) return;
  try {
    controller.runJavaScript(`window.__DSHM_FINISH_TOUCH__?.(${Date.now()});`).catch((): void => {});
  } catch (error) {
    // Navigation or window teardown can detach the controller before the gesture ends.
  }
}

/** Round touch feedback for the loopback workbench, preserving keyboard focus. */
export const TOUCH_FEEDBACK_SHIM_JS: string = `(function () {
  if (window.top !== window || !/^http:\\/\\/127\\.0\\.0\\.1:[0-9]+$/.test(location.origin)) { return; }

  function install() {
    var root = document.documentElement;
    if (!root || document.getElementById('dshm-touch-feedback')) { return; }
    var buttons = 'button, input[type="button"], input[type="submit"], input[type="checkbox"],' +
      ' input[type="radio"], [role="button"], [role="switch"], [role="tab"], [role="option"], [role^="menuitem"]';
    var controls = ':where(' + buttons + ', a[href])';
    var touch = 'html[data-dshm-touch] ' + controls;
    var pressedAttribute = 'data-dshm-touch-pressed';
    var pressed;
    var pointerId;
    var pressedAt;
    var style = document.createElement('style');
    style.id = 'dshm-touch-feedback';
    style.textContent = controls + ' { -webkit-tap-highlight-color: transparent; }' +
      ':where(' + buttons + ') { -webkit-user-select: none; user-select: none; }' +
      touch + ':focus { outline: none !important; }' +
      touch + '[' + pressedAttribute + '] {' +
        ' background-image: linear-gradient(var(--dshm-touch-ink), var(--dshm-touch-ink)) !important; }' +
      'html { --dshm-touch-ink: rgba(40, 44, 53, .12); }' +
      '@media (prefers-color-scheme: dark) { html { --dshm-touch-ink: rgba(225, 230, 242, .16); } }' +
      '[data-theme="light"] { --dshm-touch-ink: rgba(40, 44, 53, .12); }' +
      '[data-theme="dark"] { --dshm-touch-ink: rgba(225, 230, 242, .16); }';
    (document.head || root).appendChild(style);

    function release() {
      if (pressed) { pressed.removeAttribute(pressedAttribute); }
      pressed = null;
      pointerId = null;
      pressedAt = null;
    }
    function releasePointer(event) { if (event.pointerId === pointerId) { release(); } }
    function reset() { release(); root.removeAttribute('data-dshm-touch'); }

    // ArkWeb may cancel the DOM gesture while the finger is still down.
    window.__DSHM_FINISH_TOUCH__ = function (endedAt) {
      if (pressed && endedAt >= pressedAt) { release(); }
    };

    var passiveCapture = { capture: true, passive: true };
    document.addEventListener('pointerdown', function (event) {
      if (event.pointerType !== 'touch') { reset(); return; }
      if (!event.isPrimary) { return; }
      release();
      root.setAttribute('data-dshm-touch', '');
      var control = event.target instanceof Element ? event.target.closest(controls) : null;
      if (!control || control.matches(':disabled, [aria-disabled="true"]')) { return; }
      pressed = control;
      pointerId = event.pointerId;
      pressedAt = Date.now();
      pressed.setAttribute(pressedAttribute, '');
    }, passiveCapture);
    document.addEventListener('pointerup', releasePointer, passiveCapture);
    document.addEventListener('keydown', reset, true);
    // The long-press UI can briefly take focus while the finger remains down.
    window.addEventListener('pagehide', release);
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) { release(); }
    });
  }

  if (document.documentElement) { install(); }
  else { document.addEventListener('DOMContentLoaded', install, { once: true }); }
})();`;
