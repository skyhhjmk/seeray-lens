(() => {
  const script = globalThis.document?.currentScript;
  const siteId = script?.getAttribute('data-site-id');
  if (!siteId || !globalThis.SeeRayLens) return;
  const apiOrigin = globalThis.SeeRayLens.resolveApiOrigin?.(script?.src);
  const previewSessionId = script.getAttribute('data-tag-manager-preview-session');
  const previewToken = script.getAttribute('data-tag-manager-preview-token');
  const tagManagerPreview = previewSessionId && previewToken
    ? { sessionId: previewSessionId, token: previewToken }
    : undefined;
  globalThis.SeeRay = globalThis.SeeRayLens.SeeRay;
  globalThis.SeeRayLens.init({
    siteId,
    apiOrigin,
    requireConsent: script.getAttribute('data-require-consent') === 'true',
    tagManager: tagManagerPreview !== undefined || script.getAttribute('data-tag-manager') === 'true',
    tagManagerEnvironment: script.getAttribute('data-tag-manager-environment') || 'production',
    tagManagerPreview,
    experiments: script.getAttribute('data-experiments') === 'true',
    webVitals: script.hasAttribute('data-web-vitals'),
    trackForms: script.hasAttribute('data-track-forms'),
    trackMedia: script.hasAttribute('data-track-media'),
    trackErrors: script.hasAttribute('data-track-errors'),
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
