import { afterEach, describe, expect, it, vi } from 'vitest';
import { SeeRay, TRACKER_VERSION, Tracker } from '../src/index.js';

const storageStub = (values: Map<string, string>) => ({
  get length(): number { return values.size; },
  key(index: number): string | null { return [...values.keys()][index] ?? null; },
  getItem(key: string): string | null { return values.get(key) ?? null; },
  setItem(key: string, value: string): void { values.set(key, value); },
  removeItem(key: string): void { values.delete(key); },
});

describe('tracker package', () => {
  it('exposes the tracker version', () => {
    expect(TRACKER_VERSION).toBe('0.8.0');
  });

  afterEach(() => vi.unstubAllGlobals());

  it('does not send when Do Not Track is enabled', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '1' });
    const fetch = vi.fn();
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_public', flushInterval: 100 });
    tracker.track('signup');
    await tracker.flush();
    expect(fetch).not.toHaveBeenCalled();
  });

  it('requires explicit consent when configured and stops after opt-out', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const storage = new Map<string, string>();
    const session = new Map<string, string>();
    vi.stubGlobal('localStorage', storageStub(storage));
    vi.stubGlobal('sessionStorage', storageStub(session));
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_consent', requireConsent: true });
    expect(tracker.getConsentState()).toBe('unknown');
    expect(storage.has('seeray:srl_consent:visitor_id')).toBe(false);
    expect(session.has('seeray:srl_consent:session_id')).toBe(false);
    tracker.track('before-consent');
    await tracker.flush();
    expect(fetch).not.toHaveBeenCalled();
    tracker.setConsent(true);
    expect(storage.has('seeray:srl_consent:visitor_id')).toBe(true);
    expect(session.has('seeray:srl_consent:session_id')).toBe(true);
    tracker.track('after-consent');
    await tracker.flush();
    expect(fetch).toHaveBeenCalledTimes(1);
    tracker.optOut();
    expect(tracker.getConsentState()).toBe('denied');
    expect(storage.has('seeray:srl_consent:visitor_id')).toBe(false);
    expect(session.has('seeray:srl_consent:session_id')).toBe(false);
    tracker.track('after-opt-out');
    await tracker.flush();
    expect(fetch).toHaveBeenCalledTimes(1);
    const internal = tracker as unknown as { heatmapQueue: unknown[]; flushHeatmap: () => Promise<void> };
    internal.heatmapQueue.push({ type: 'start' });
    await internal.flushHeatmap();
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('honors opt-out even when consent is not required by site policy', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const local = new Map<string, string>();
    vi.stubGlobal('localStorage', storageStub(local));
    vi.stubGlobal('sessionStorage', storageStub(new Map<string, string>()));
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);

    const tracker = new Tracker({ siteId: 'srl_optional_consent' });
    expect(tracker.getConsentState()).toBe('granted');
    tracker.track('before-opt-out');
    await tracker.flush();
    expect(fetch).toHaveBeenCalledTimes(1);

    tracker.optOut();
    tracker.track('after-opt-out');
    await tracker.flush();
    expect(tracker.getConsentState()).toBe('denied');
    expect(local.has('seeray:srl_optional_consent:visitor_id')).toBe(false);
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('exposes per-site consent state and updates one tracker through the facade', () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('localStorage', storageStub(new Map<string, string>()));
    vi.stubGlobal('sessionStorage', storageStub(new Map<string, string>()));
    SeeRay.init({ siteId: 'srl_consent_facade_a', requireConsent: true });
    SeeRay.init({ siteId: 'srl_consent_facade_b', requireConsent: true });

    expect(SeeRay.getConsentState('srl_consent_facade_a')).toBe('unknown');
    SeeRay.setConsent(true, 'srl_consent_facade_a');
    expect(SeeRay.getConsentState('srl_consent_facade_a')).toBe('granted');
    expect(SeeRay.getConsentState('srl_consent_facade_b')).toBe('unknown');
  });

  it('collects only opted-in Core Web Vital measurements behind consent and DNT', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const storage = new Map<string, string>();
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => storage.get(key) ?? null,
      setItem: (key: string, value: string) => storage.set(key, value),
    });
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_web_vitals', webVitals: true, requireConsent: true });
    const internal = tracker as unknown as {
      recordWebVital: (metric: { id: string; name: string; value: number }) => void;
    };
    const sample = { id: 'v5-123', name: 'LCP', value: 2400 };

    internal.recordWebVital(sample);
    await tracker.flush();
    expect(fetch).not.toHaveBeenCalled();

    tracker.setConsent(true);
    internal.recordWebVital(sample);
    await tracker.flush();
    const events = JSON.parse(fetch.mock.calls[0][1].body as string).events;
    expect(events).toEqual([
      expect.objectContaining({
        type: 'web_vital',
        category: 'performance',
        action: 'LCP',
        properties: { metric: 'LCP', metricId: 'v5-123', value: 2400 },
      }),
    ]);

    tracker.optOut();
    internal.recordWebVital({ ...sample, value: 2600 });
    await tracker.flush();
    expect(fetch).toHaveBeenCalledTimes(1);

    vi.stubGlobal('navigator', { doNotTrack: '1' });
    const dntTracker = new Tracker({ siteId: 'srl_web_vitals_dnt', webVitals: true });
    const dntInternal = dntTracker as unknown as {
      recordWebVital: (metric: { id: string; name: string; value: number }) => void;
    };
    dntInternal.recordWebVital(sample);
    await dntTracker.flush();
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it('keeps an experiment assignment stable for one site visitor', () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const storage = new Map<string, string>();
    vi.stubGlobal('localStorage', { getItem: (key: string) => storage.get(key) ?? null, setItem: (key: string, value: string) => storage.set(key, value) });
    const tracker = new Tracker({ siteId: 'srl_experiment' });
    const first = tracker.assignExperiment('hero', ['control', 'variant']);
    const second = tracker.assignExperiment('hero', ['control', 'variant']);
    expect(first).toBe(second);
    expect(first).toMatch(/control|variant/);
  });

  it('loads enabled experiment variants and assigns by definition name', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [{ name: 'hero', variants: ['control', 'variant'] }],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_experiment_config',
      apiOrigin: 'https://lens.example.test/tracker.js',
      experiments: true,
      flushInterval: 100,
    });
    await tracker.ready();
    const selected = tracker.assignExperiment('hero');
    await tracker.flush();
    expect(selected).toMatch(/control|variant/);
    const definitionsUrl = new URL(fetch.mock.calls[0][0] as string);
    expect(definitionsUrl.pathname).toBe('/api/v1/experiments/srl_experiment_config/definitions');
    expect(definitionsUrl.searchParams.get('visitorId')).toMatch(/^[0-9a-f-]{36}$/i);
    expect(fetch.mock.calls[0][1]).toMatchObject({ cache: 'no-store' });
    const collectorCall = fetch.mock.calls.find((call) => call[1]?.method === 'POST');
    expect(JSON.parse(collectorCall?.[1].body as string).events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: 'experiment_exposure', action: 'hero', name: selected }),
      ]),
    );
  });

  it('assigns a visitor to at most one experiment in a shared layer', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const storage = new Map<string, string>();
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => storage.get(key) ?? null,
      setItem: (key: string, value: string) => storage.set(key, value),
    });
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [
          { name: 'checkout-copy', variants: ['control', 'new'], allocationGroup: 'checkout' },
          { name: 'checkout-layout', variants: ['control', 'compact'], allocationGroup: 'checkout' },
        ],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_experiment_layers',
      apiOrigin: 'https://lens.example.test/tracker.js',
      experiments: true,
      flushInterval: 100,
    });
    await tracker.ready();

    const first = tracker.assignExperiment('checkout-copy');
    const second = tracker.assignExperiment('checkout-layout');
    const repeatedFirst = tracker.assignExperiment('checkout-copy');
    const repeatedSecond = tracker.assignExperiment('checkout-layout');
    expect([first, second].filter((value) => value !== undefined)).toHaveLength(1);
    expect(first).toBe(repeatedFirst);
    expect(second).toBe(repeatedSecond);
    expect(storage.get('seeray:srl_experiment_layers:experiment-layer:checkout')).toBe(
      first === undefined ? 'checkout-layout' : 'checkout-copy',
    );

    await tracker.flush();
    const collectorCall = fetch.mock.calls.find((call) => call[1]?.method === 'POST');
    const exposures = JSON.parse(collectorCall?.[1].body as string).events
      .filter((event: { type: string }) => event.type === 'experiment_exposure');
    expect(exposures).toHaveLength(2);
    expect(exposures.map((event: { action: string }) => event.action)).toEqual(
      [first === undefined ? 'checkout-layout' : 'checkout-copy',
        first === undefined ? 'checkout-layout' : 'checkout-copy'],
    );
  });

  it('checks configured path and device targeting before assigning or exposing', async () => {
    const browser = { doNotTrack: '0', userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Chrome/124.0.0.0 Safari/537.36' };
    const location = { href: 'https://shop.example.test/pricing-old' };
    vi.stubGlobal('navigator', browser);
    vi.stubGlobal('location', location);
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [{
          name: 'hero',
          variants: ['control', 'variant'],
          targeting: { pathPrefixes: ['/pricing'], deviceTypes: ['mobile'] },
        }],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_experiment_targeting', experiments: true });
    await tracker.ready();

    expect(tracker.assignExperiment('hero')).toBeUndefined();
    expect(tracker.assignExperiment('hero', ['control', 'variant'])).toBeUndefined();
    location.href = 'https://shop.example.test/pricing/checkout';
    expect(tracker.assignExperiment('hero')).toBeUndefined();
    browser.userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile';
    expect(tracker.assignExperiment('hero')).toMatch(/control|variant/);

    await tracker.flush();
    const collectionCalls = fetch.mock.calls.filter((call) => call[1]?.method === 'POST');
    expect(collectionCalls).toHaveLength(1);
    expect(JSON.parse(collectionCalls[0][1].body as string).events).toEqual([
      expect.objectContaining({ type: 'experiment_exposure', action: 'hero' }),
    ]);
  });

  it('batches events and posts the versioned envelope', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 202 }));
    const tracker = new Tracker({ siteId: 'srl_public', endpoint: '/api/v1/collect', maxBatchSize: 2 });
    tracker.track('page_view', { url: 'https://example.com/docs?token=secret' });
    tracker.track('signup');
    await tracker.flush();
    const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    const envelope = JSON.parse(call[1].body as string);
    expect(envelope.schemaVersion).toBe(1);
    expect(envelope.siteId).toBe('srl_public');
    expect(envelope.events).toHaveLength(2);
    expect(envelope.events[0].eventId).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('tracks explicit site searches with normalized terms and known zero results', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_search', flushInterval: 100 });
    tracker.trackSiteSearch('  red   shoes\n', { category: 'catalog', resultsCount: 0 });
    tracker.trackSiteSearch('  \u0000  ');
    await tracker.flush();

    const events = JSON.parse(fetch.mock.calls[0][1].body as string).events;
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({
      type: 'site_search',
      category: 'site_search',
      action: 'catalog',
      name: 'red shoes',
      properties: {
        keyword: 'red shoes',
        searchCategory: 'catalog',
        resultsCount: 0,
      },
    });
  });

  it('captures only explicitly marked search forms and honors consent gating', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    let submit: ((event: Event) => void) | undefined;
    vi.stubGlobal('document', {
      addEventListener: (type: string, listener: (event: Event) => void) => {
        if (type === 'submit') submit = listener;
      },
    });
    const storage = new Map<string, string>();
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => storage.get(key) ?? null,
      setItem: (key: string, value: string) => storage.set(key, value),
    });
    const tracker = new Tracker({
      siteId: 'srl_search_form',
      requireConsent: true,
      trackDownloads: false,
      trackOutlinks: false,
    });
    const form = {
      tagName: 'FORM',
      hasAttribute: (name: string) => name === 'data-seeray-search',
      closest: () => null,
      getAttribute: (name: string) => name === 'data-seeray-search-category' ? 'docs' : null,
      querySelector: () => ({ value: 'analytics setup' }),
    };
    submit?.({ target: form } as unknown as Event);
    await tracker.flush();
    expect(fetch).not.toHaveBeenCalled();

    tracker.setConsent(true);
    submit?.({ target: form } as unknown as Event);
    await tracker.flush();
    const events = JSON.parse(fetch.mock.calls[0][1].body as string).events;
    expect(events[0]).toMatchObject({
      type: 'site_search',
      name: 'analytics setup',
      properties: { keyword: 'analytics setup', searchCategory: 'docs' },
    });
    expect(events[0].properties.resultsCount).toBeUndefined();
  });

  it('tracks visible marked content and explicit interactions without query-string targets', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    let click: ((event: Event) => void) | undefined;

    class FakeElement {
      constructor(
        readonly attributes: Record<string, string>,
        readonly parentElement?: FakeElement,
      ) {}
      getAttribute(name: string): string | null {
        return this.attributes[name] ?? null;
      }
      closest(selector: string): FakeElement | null {
        const findMatch = (element: FakeElement | undefined): FakeElement | null => {
          if (!element) return null;
          if (selector === '[data-seeray-content-action]' && 'data-seeray-content-action' in element.attributes) return element;
          if (selector === '[data-seeray-content-name]' && 'data-seeray-content-name' in element.attributes) return element;
          if (selector === '[data-seeray-no-track]' && 'data-seeray-no-track' in element.attributes) return element;
          return findMatch(element.parentElement);
        };
        return findMatch(this);
      }
    }
    const content = new FakeElement({
      'data-seeray-content-name': ' Spring hero ',
      'data-seeray-content-piece': ' spring banner ',
      'data-seeray-content-target': '/spring?email=private@example.test#details',
    });
    const action = new FakeElement({ 'data-seeray-content-action': 'cta_click' }, content);
    vi.stubGlobal('Element', FakeElement);
    vi.stubGlobal('IntersectionObserver', class {
      constructor(private readonly callback: (entries: Array<{ target: FakeElement; isIntersecting: boolean; intersectionRatio: number }>) => void) {}
      observe(target: FakeElement): void {
        this.callback([{ target, isIntersecting: true, intersectionRatio: 0.5 }]);
      }
      disconnect(): void {}
    });
    vi.stubGlobal('document', {
      addEventListener: (type: string, listener: (event: Event) => void) => {
        if (type === 'click') click = listener;
      },
      querySelectorAll: () => [content],
    });

    const tracker = new Tracker({ siteId: 'srl_content', trackDownloads: false, trackOutlinks: false });
    tracker.refreshContentTracking();
    click?.({ target: action } as unknown as Event);
    await tracker.flush();

    const events = JSON.parse(fetch.mock.calls[0][1].body as string).events;
    expect(events).toHaveLength(2);
    expect(events[0]).toMatchObject({
      type: 'content_impression',
      category: 'content',
      action: 'impression',
      name: 'Spring hero',
      properties: {
        contentName: 'Spring hero',
        contentPiece: 'spring banner',
        contentTarget: '/spring',
      },
    });
    expect(events[1]).toMatchObject({
      type: 'content_interaction',
      action: 'cta_click',
      name: 'Spring hero',
      properties: { interaction: 'cta_click' },
    });
    expect(JSON.stringify(events)).not.toContain('private@example.test');
  });

  it('collects normalized technology context without transmitting the raw user agent', async () => {
    vi.stubGlobal('navigator', {
      doNotTrack: '0',
      language: 'zh-CN',
      userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/132.4.1.0 Safari/537.36',
    });
    vi.stubGlobal('screen', { width: 1920, height: 1080 });
    vi.stubGlobal('innerWidth', 1440);
    vi.stubGlobal('innerHeight', 900);
    vi.stubGlobal('devicePixelRatio', 1.5);
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_technology' });
    tracker.track('page_view');
    await tracker.flush();
    const body = JSON.parse(fetch.mock.calls[0][1].body as string);
    expect(body.events[0].context).toMatchObject({
      browser: 'Chrome',
      browserVersion: '132',
      operatingSystem: 'Linux',
      deviceType: 'desktop',
      language: 'zh-CN',
      screenWidth: 1920,
      screenHeight: 1080,
      viewportWidth: 1440,
      viewportHeight: 900,
      pixelRatio: 1.5,
    });
    expect(JSON.stringify(body)).not.toContain('Mozilla/5.0');
  });

  it('derives absolute collector URLs from the tracker script origin', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 202 }));
    const tracker = new Tracker({ siteId: 'srl_absolute', apiOrigin: 'https://lens.example.test/tracker.js' });
    tracker.track('page_view');
    await tracker.flush();
    expect((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][0]).toBe('https://lens.example.test/api/v1/collect');
    const internal = tracker as unknown as { heatmapEndpoint: string; heatmapConfigEndpoint: string };
    expect(internal.heatmapEndpoint).toBe('https://lens.example.test/api/v1/collect/heatmaps');
    expect(internal.heatmapConfigEndpoint).toBe('https://lens.example.test/api/v1/heatmap-config/srl_absolute');
  });

  it('reuses a site tracker and de-duplicates page views from repeated embeds', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 202 }));
    const first = SeeRay.init({ siteId: 'srl_shared', flushInterval: 100 });
    const second = SeeRay.init({ siteId: 'srl_shared', flushInterval: 100 });
    expect(second).toBe(first);
    first.trackPageView({ url: 'https://example.com/' });
    second.trackPageView({ url: 'https://example.com/' });
    await first.flush();
    const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(JSON.parse(call[1].body as string).events).toHaveLength(1);
  });

  it('de-duplicates only within one page lifecycle and permits same-URL navigation', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 202 }));
    const tracker = new Tracker({ siteId: 'srl_lifecycle', flushInterval: 100 });
    tracker.pageReady({ url: 'https://example.com/catalog' });
    tracker.pageReady({ url: 'https://example.com/catalog' });
    tracker.beginNavigation();
    tracker.pageReady({ url: 'https://example.com/catalog' });
    await tracker.flush();
    const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    const events = JSON.parse(call[1].body as string).events;
    expect(events.filter((event: { type: string }) => event.type === 'page_view')).toHaveLength(2);
  });

  it('cancels a PJAX navigation without recording another page view', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 202 }));
    const tracker = new Tracker({ siteId: 'srl_cancel_navigation', flushInterval: 100 });
    tracker.pageReady({ url: 'https://example.com/catalog' });
    tracker.beginNavigation();
    tracker.cancelNavigation();
    tracker.trackPageView({ url: 'https://example.com/catalog' });
    await tracker.flush();
    const events = JSON.parse((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][1].body as string).events;
    expect(events.filter((event: { type: string }) => event.type === 'page_view')).toHaveLength(1);
  });

  it('exposes navigation lifecycle methods through the global facade', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 202 }));
    const tracker = SeeRay.init({ siteId: 'srl_global_lifecycle', flushInterval: 100 });
    SeeRay.pageReady({ url: 'https://example.com/pjax' });
    SeeRay.beginNavigation();
    SeeRay.pageReady({ url: 'https://example.com/pjax' });
    await tracker.flush();
    const events = JSON.parse((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][1].body as string).events;
    expect(events.filter((event: { type: string }) => event.type === 'page_view')).toHaveLength(2);
  });

  it('keeps the same heatmap batch id when a retry follows a transient failure', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn().mockRejectedValueOnce(new Error('offline')).mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_heatmap_retry' });
    const internal = tracker as unknown as { heatmapQueue: unknown[]; flushHeatmap: () => Promise<void>; heatmapTimer?: ReturnType<typeof setTimeout> };
    internal.heatmapQueue.push({ type: 'start', instanceId: '00000000-0000-4000-8000-000000000001', url: 'https://example.com/', layoutVersion: 'v1', targetId: 'page', viewportWidth: 100, viewportHeight: 100, contentWidth: 100, contentHeight: 100 });
    await internal.flushHeatmap();
    if (internal.heatmapTimer) clearTimeout(internal.heatmapTimer);
    await internal.flushHeatmap();
    const first = JSON.parse(fetch.mock.calls[0][1].body as string);
    const second = JSON.parse(fetch.mock.calls[1][1].body as string);
    expect(second.clientBatchId).toBe(first.clientBatchId);
    expect(second.events).toEqual(first.events);
  });

  it('uses a registered container viewport rather than the window viewport', () => {
    const tracker = new Tracker({ siteId: 'srl_container_geometry' });
    const internal = tracker as unknown as { geometry: (targetId: string, element?: HTMLElement) => { viewportWidth: number; viewportHeight: number; contentWidth: number; contentHeight: number } };
    const element = { clientWidth: 320, clientHeight: 180, scrollWidth: 640, scrollHeight: 720 } as HTMLElement;
    expect(internal.geometry('results', element)).toEqual({ targetId: 'results', viewportWidth: 320, viewportHeight: 180, contentWidth: 640, contentHeight: 720 });
  });

  it('starts a new geometry segment only after an observed target size changes', () => {
    const tracker = new Tracker({ siteId: 'srl_layout_segment' });
    const internal = tracker as unknown as {
      heatmapInstance: string;
      heatmapSelected: boolean;
      heatmapUrl: string;
      heatmapLayoutVersion: string;
      heatmapQueue: Array<{ type: string; contentHeight: number }>;
      heatmapTimer?: ReturnType<typeof setTimeout>;
      containers: Map<string, { element: HTMLElement; remove: () => void }>;
      captureTargetStart: (targetId: string, element: HTMLElement, force?: boolean) => void;
    };
    internal.heatmapInstance = '00000000-0000-4000-8000-000000000001';
    internal.heatmapSelected = true;
    internal.heatmapUrl = 'https://example.com/long';
    internal.heatmapLayoutVersion = 'v1';
    const element = {
      clientWidth: 320,
      clientHeight: 180,
      scrollWidth: 320,
      scrollHeight: 720,
      scrollTop: 0,
      getBoundingClientRect: () => ({ top: 0, bottom: 180 }),
    };
    internal.containers.set('results', {
      element: element as unknown as HTMLElement,
      remove: () => undefined,
    });
    internal.captureTargetStart('results', element as unknown as HTMLElement);
    internal.captureTargetStart('results', element as unknown as HTMLElement);
    element.scrollHeight = 960;
    internal.captureTargetStart('results', element as unknown as HTMLElement);
    expect(internal.heatmapQueue.filter((event) => event.type === 'start').map((event) => event.contentHeight)).toEqual([720, 960]);
    if (internal.heatmapTimer) clearTimeout(internal.heatmapTimer);
  });

  it('sends goal name and dimensions as event fields', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 202 }));
    const tracker = new Tracker({ siteId: 'srl_goal', flushInterval: 100 });
    tracker.trackGoal('signup_completed', { category: 'conversion', action: 'submit' });
    await tracker.flush();
    const call = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(JSON.parse(call[1].body as string).events[0]).toMatchObject({
      type: 'goal', name: 'signup_completed', category: 'conversion', action: 'submit',
    });
  });

  it('loads and executes safe event tags from a published container', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [{
          type: 'event',
          trigger: 'signup',
          eventType: 'tag_signup',
          category: 'tag',
          name: 'signup_tag',
        }],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_tag_manager',
      apiOrigin: 'https://lens.example.test/tracker.js',
      tagManager: true,
      flushInterval: 100,
    });
    await new Promise((resolve) => setTimeout(resolve, 0));
    tracker.push({ event: 'signup', properties: { plan: 'pro' } });
    await tracker.flush();
    const collectorCall = fetch.mock.calls.find((call) => call[1]?.method === 'POST');
    expect(collectorCall?.[0]).toBe('https://lens.example.test/api/v1/collect');
    expect(JSON.parse(collectorCall?.[1].body as string).events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ type: 'signup' }),
        expect.objectContaining({ type: 'tag_signup', name: 'signup_tag', category: 'tag' }),
      ]),
    );
  });

  it('requests the selected tag manager environment and defaults safely to production', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => [],
    });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_tag_environment',
      apiOrigin: 'https://lens.example.test',
      tagManager: true,
      tagManagerEnvironment: 'staging',
    });
    await tracker.ready();
    expect(fetch.mock.calls[0][0]).toBe(
      'https://lens.example.test/api/v1/tag-manager/srl_tag_environment/container?environment=staging',
    );
  });

  it('previews tags on a live page without sending analytics or running code by default', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const appended: unknown[] = [];
    vi.stubGlobal('document', {
      addEventListener: vi.fn(),
      head: { appendChild: (node: unknown) => appended.push(node) },
      createElement: () => ({ type: '', textContent: '' }),
    });
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          executeCustomCode: false,
          tags: [
            { type: 'event', trigger: 'signup', eventType: 'tag_signup', name: 'Signup event' },
            { type: 'custom_html', trigger: 'signup', name: 'Signup pixel', code: '<script>window.previewRan = true;</script>' },
            { type: 'event', triggers: [{ type: 'custom_js', functionName: 'previewPredicate', code: '() => true' }], eventType: 'tag_custom_js' },
            { type: 'event', trigger: 'purchase', eventType: 'tag_purchase' },
          ],
        }),
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_tag_preview',
      apiOrigin: 'https://lens.example.test',
      experiments: true,
      heatmap: { enabled: true },
      tagManagerPreview: { sessionId: 'session-1', token: 'preview-secret' },
    });

    await tracker.ready();
    tracker.push({
      event: 'signup',
      url: 'https://shop.example.test/signup?email=private@example.test#form',
      properties: { email: 'private@example.test' },
    });

    expect(fetch).toHaveBeenCalledTimes(2);
    expect(fetch.mock.calls[0][0]).toBe('https://lens.example.test/api/v1/tag-manager/srl_tag_preview/preview/session-1');
    expect(fetch.mock.calls[0][1]?.headers).toEqual({ Authorization: 'Bearer preview-secret' });
    expect(fetch.mock.calls[1][0]).toBe('https://lens.example.test/api/v1/tag-manager/srl_tag_preview/preview/session-1/events');
    expect(fetch.mock.calls[1][1]?.headers).toEqual({
      Authorization: 'Bearer preview-secret',
      'Content-Type': 'application/json',
    });
    expect(JSON.parse(fetch.mock.calls[1][1]?.body as string)).toEqual([
      { tagIndex: 0, triggerEvent: 'signup', outcome: 'fired', pagePath: '/signup' },
      { tagIndex: 1, triggerEvent: 'signup', outcome: 'blocked', pagePath: '/signup' },
      { tagIndex: 2, triggerEvent: 'signup', outcome: 'blocked', pagePath: '/signup' },
      { tagIndex: 3, triggerEvent: 'signup', outcome: 'no_match', pagePath: '/signup' },
    ]);
    expect(JSON.stringify(fetch.mock.calls[1][1]?.body)).not.toContain('private@example.test');
    expect(fetch.mock.calls.some((call) => String(call[0]).includes('/collect'))).toBe(false);
    expect(fetch.mock.calls.some((call) => String(call[0]).includes('/heatmap'))).toBe(false);
    expect(fetch.mock.calls.some((call) => String(call[0]).includes('/experiments'))).toBe(false);
    expect(appended).toHaveLength(0);
    expect((globalThis as unknown as Record<string, unknown>).previewPredicate).toBeUndefined();
  });

  it('requires every event-trigger property condition before firing a tag', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [{
          type: 'event',
          eventType: 'qualified_signup',
          triggers: [{
            type: 'event',
            event: 'signup',
            conditions: [
              { property: 'plan', operator: 'equals', value: 'pro' },
              { property: 'campaign', operator: 'starts_with', value: 'spring_' },
            ],
          }],
        }],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_tag_event_filters',
      tagManager: true,
      flushInterval: 100,
    });
    await tracker.ready();
    tracker.push({ event: 'signup', properties: { plan: 'pro', campaign: 'spring_launch' } });
    tracker.push({ event: 'signup', properties: { plan: 'pro', campaign: 'winter_launch' } });
    tracker.push({ event: 'signup', properties: { plan: 'free', campaign: 'spring_launch' } });
    await tracker.flush();
    const collectorCall = fetch.mock.calls.find((call) => call[1]?.method === 'POST');
    const events = JSON.parse(collectorCall?.[1].body as string).events as Array<{ type: string }>;
    expect(events.filter((event) => event.type === 'qualified_signup')).toHaveLength(1);
  });

  it('resolves built-in and event-property variables in tag properties', async () => {
    vi.stubGlobal('navigator', {
      doNotTrack: '0',
      language: 'zh-CN',
      userAgent: 'Mozilla/5.0 Chrome/132.1.0.0 Safari/537.36',
    });
    vi.stubGlobal('screen', { width: 1920, height: 1080 });
    vi.stubGlobal('innerWidth', 1440);
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [{
          type: 'event',
          trigger: 'signup',
          eventType: 'tag_signup',
          properties: {
            page: '{{Page URL}}',
            title: '{{Page Title}}',
            referrer: '{{Referrer}}',
            event: '{{Event}}',
            eventName: '{{Event Name}}',
            category: '{{Event Category}}',
            action: '{{Event Action}}',
            plan: '{{Event Property: plan}}',
            browser: '{{Browser}}',
            viewport: '{{Viewport Width}}',
            unknown: '{{Not Registered}}',
          },
        }],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_tag_variables',
      tagManager: true,
      flushInterval: 100,
    });
    await tracker.ready();
    tracker.push({
      event: 'signup',
      eventName: 'Account created',
      eventCategory: 'account',
      eventAction: 'register',
      url: 'https://example.test/signup?source=campaign',
      title: 'Create account',
      referrer: 'https://example.test/pricing',
      properties: { plan: 'pro' },
    });
    await tracker.flush();
    const collectorCall = fetch.mock.calls.find((call) => call[1]?.method === 'POST');
    const events = JSON.parse(collectorCall?.[1].body as string).events;
    expect(events).toEqual(expect.arrayContaining([
      expect.objectContaining({
        type: 'tag_signup',
        properties: {
          plan: 'pro',
          page: 'https://example.test/signup?source=campaign',
          title: 'Create account',
          referrer: 'https://example.test/pricing',
          event: 'signup',
          eventName: 'Account created',
          category: 'account',
          action: 'register',
          browser: 'Chrome',
          viewport: '1440',
          unknown: '{{Not Registered}}',
        },
      }),
    ]));
  });

  it('loads and runs a custom HTML or JavaScript tag on its trigger', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const appended: Array<{ type?: string; textContent?: string }> = [];
    vi.stubGlobal('document', {
      addEventListener: vi.fn(),
      head: {
        appendChild: (node: { type?: string; textContent?: string }) => {
          appended.push(node);
        },
      },
      createElement: () => ({ type: '', textContent: '' }),
    });
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [{
          type: 'custom_html',
          trigger: 'signup',
          name: 'Signup pixel',
          code: 'window.__seeraySignupPixel = true;',
        }],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_custom_html',
      apiOrigin: 'https://lens.example.test/tracker.js',
      tagManager: true,
      flushInterval: 100,
    });
    await tracker.ready();
    tracker.push({ event: 'signup' });
    expect(appended).toEqual([
      { type: 'text/javascript', textContent: 'window.__seeraySignupPixel = true;' },
    ]);
  });

  it('supports predefined multi-triggers and mounts custom trigger functions on window', async () => {
    vi.stubGlobal('navigator', { doNotTrack: '0' });
    const appended: Array<{ type?: string; textContent?: string }> = [];
    vi.stubGlobal('document', {
      addEventListener: vi.fn(),
      head: { appendChild: (node: { type?: string; textContent?: string }) => appended.push(node) },
      createElement: () => ({ type: '', textContent: '' }),
    });
    const fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => [{
          type: 'custom_html',
          name: 'Purchase snippet',
          triggers: [
            { type: 'predefined', event: 'page_view' },
            {
              type: 'custom_js',
              functionName: 'shouldFirePurchaseSnippet',
              code: '(event) => event.event === "purchase"',
            },
          ],
          code: 'window.purchaseSnippet = true;',
        }],
      })
      .mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({
      siteId: 'srl_custom_trigger',
      apiOrigin: 'https://lens.example.test/tracker.js',
      tagManager: true,
      flushInterval: 100,
    });
    await tracker.ready();
    tracker.push({ event: 'purchase' });
    expect((globalThis as Record<string, unknown>).shouldFirePurchaseSnippet).toEqual(expect.any(Function));
    expect(appended).toEqual([{ type: 'text/javascript', textContent: 'window.purchaseSnippet = true;' }]);
  });
});
