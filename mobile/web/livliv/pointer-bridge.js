// Forward pointer direction to the same-origin, non-interactive player frame.
// The iframe cannot see pointer events because Flutter must receive dragging.
(() => {
  let latest = null;
  let scheduled = false;
  let activeTouch = null;
  let resetTimer = null;
  function resetGaze() {
    latest = null;
    const frame = document.querySelector('iframe[title="LivLiv 测试角色"]');
    frame?.contentWindow?.postMessage(JSON.stringify({type: 'dentstudy-livliv-gaze', reset: true}), location.origin);
  }
  function send() {
    scheduled = false;
    const frame = document.querySelector('iframe[title="LivLiv 测试角色"]');
    if (!frame?.contentWindow || !latest) return;
    const r = frame.getBoundingClientRect();
    if (!r.width || !r.height) return;
    const clamp = n => Math.max(-1, Math.min(1, n));
    const x = clamp((latest.x - (r.left + r.width / 2)) / Math.max(r.width, innerWidth * .45));
    const y = clamp(((r.top + r.height * .36) - latest.y) / Math.max(r.height, innerHeight * .45));
    frame.contentWindow.postMessage(JSON.stringify({type: 'dentstudy-livliv-gaze', x, y}), location.origin);
  }
  function track(event) {
    if (resetTimer) { clearTimeout(resetTimer); resetTimer = null; }
    latest = {x: event.clientX, y: event.clientY};
    if (!scheduled) { scheduled = true; requestAnimationFrame(send); }
  }
  window.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'touch' || !event.isPrimary) return;
    activeTouch = event.pointerId;
    track(event);
  }, {capture: true, passive: true});
  window.addEventListener('pointermove', event => {
    if (event.pointerType === 'touch' && event.pointerId !== activeTouch) return;
    if (!['mouse', 'pen', 'touch'].includes(event.pointerType)) return;
    track(event);
  }, {capture: true, passive: true});
  function finishTouch(event) {
    if (event.pointerType !== 'touch' || event.pointerId !== activeTouch) return;
    activeTouch = null;
    if (resetTimer) clearTimeout(resetTimer);
    resetTimer = setTimeout(resetGaze, 900);
  }
  window.addEventListener('pointerup', finishTouch, {capture: true, passive: true});
  window.addEventListener('pointercancel', finishTouch, {capture: true, passive: true});
  document.addEventListener('pointerleave', () => {
    if (activeTouch === null) resetGaze();
  });
})();
