// primordia-touch-canvas: bound phone pixel work while keeping 2x text detail.
(() => {
  if (!window.matchMedia?.('(pointer: coarse)').matches || !navigator.maxTouchPoints) return;
  const canvas = document.getElementById('canvas');
  if (!canvas) return;
  GODOT_CONFIG.canvasResizePolicy = 0; // App-owned dimensions; engine observes changes.
  const fit = () => {
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    window.primordiaRenderPixelRatio = ratio;
    const width = Math.max(1, Math.floor(window.innerWidth * ratio));
    const height = Math.max(1, Math.floor(window.innerHeight * ratio));
    if (canvas.width !== width) canvas.width = width;
    if (canvas.height !== height) canvas.height = height;
    canvas.style.width = window.innerWidth + 'px';
    canvas.style.height = window.innerHeight + 'px';
  };
  window.addEventListener('resize', fit);
  document.addEventListener('fullscreenchange', fit);
  fit();
})();
