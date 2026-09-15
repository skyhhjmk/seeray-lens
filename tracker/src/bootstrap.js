(() => {
  const script = globalThis.document?.currentScript;
  const siteId = script?.getAttribute('data-site-id');
  if (!siteId || !globalThis.SeeRayLens) return;
  const apiOrigin = globalThis.SeeRayLens.resolveApiOrigin?.(script?.src);
  globalThis.SeeRay = globalThis.SeeRayLens.SeeRay;
  globalThis.SeeRayLens.init({
    siteId,
    apiOrigin,
    heatmap: {
      enabled: true,
      navigationMode: script.getAttribute('data-navigation-mode') === 'manual' ? 'manual' : 'auto',
      layoutVersion: script.getAttribute('data-layout-version') || undefined,
    },
  });
})();
