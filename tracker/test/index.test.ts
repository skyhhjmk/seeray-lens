import { afterEach, describe, expect, it, vi } from 'vitest';
import { SeeRay, TRACKER_VERSION, Tracker } from '../src/index.js';

describe('tracker package', () => {
  it('exposes the tracker version', () => {
    expect(TRACKER_VERSION).toBe('0.4.0');
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
    vi.stubGlobal('localStorage', { getItem: (key: string) => storage.get(key) ?? null, setItem: (key: string, value: string) => storage.set(key, value) });
    const fetch = vi.fn().mockResolvedValue({ ok: true, status: 202 });
    vi.stubGlobal('fetch', fetch);
    const tracker = new Tracker({ siteId: 'srl_consent', requireConsent: true });
    tracker.track('before-consent');
    await tracker.flush();
    expect(fetch).not.toHaveBeenCalled();
    tracker.setConsent(true);
    tracker.track('after-consent');
    await tracker.flush();
    expect(fetch).toHaveBeenCalledTimes(1);
    tracker.optOut();
    tracker.track('after-opt-out');
    await tracker.flush();
    expect(fetch).toHaveBeenCalledTimes(1);
    const internal = tracker as unknown as { heatmapQueue: unknown[]; flushHeatmap: () => Promise<void> };
    internal.heatmapQueue.push({ type: 'start' });
    await internal.flushHeatmap();
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
});
