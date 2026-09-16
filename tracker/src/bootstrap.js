(() => {
  const script = globalThis.document?.currentScript;
  const siteId = script?.getAttribute('data-site-id');
  if (!siteId || !globalThis.SeeRayLens) return;
  const apiOrigin = globalThis.SeeRayLens.resolveApiOrigin?.(script?.src);
  globalThis.SeeRay = globalThis.SeeRayLens.SeeRay;
  globalThis.SeeRayLens.init({
    siteId,
    apiOrigin,
    requireConsent: script.getAttribute('data-require-consent') === 'true',
    tagManager: script.getAttribute('data-tag-manager') === 'true',
    heatmap: {
      enabled: true,
      navigationMode: script.getAttribute('data-navigation-mode') === 'manual' ? 'manual' : 'auto',
      layoutVersion: script.getAttribute('data-layout-version') || undefined,
    },
  });
  const layer = globalThis.seerayDataLayer = globalThis.seerayDataLayer || [];
  const push = layer.push.bind(layer);
  layer.forEach(event => globalThis.SeeRay.push(event));
  layer.push = (...events) => {
    events.forEach(event => globalThis.SeeRay.push(event));
    return push(...events);
  };
})();
