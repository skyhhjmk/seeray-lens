import { afterEach, describe, expect, it, vi } from 'vitest';
import { TRACKER_VERSION, Tracker } from '../src/index.js';

describe('tracker package', () => {
  it('exposes the tracker version', () => {
    expect(TRACKER_VERSION).toBe('0.2.0');
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
});
