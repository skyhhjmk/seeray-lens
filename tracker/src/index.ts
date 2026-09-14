export const TRACKER_VERSION = '0.2.0';

export interface TrackerOptions {
  siteId: string;
  endpoint?: string;
  maxBatchSize?: number;
  flushInterval?: number;
}

export interface TrackOptions {
  url?: string;
  title?: string;
  referrer?: string;
  durationMs?: number;
  properties?: Record<string, unknown>;
  category?: string;
  action?: string;
  name?: string;
}

interface EventPayload extends TrackOptions {
  eventId: string;
  type: string;
  occurredAt: string;
  visitorId: string;
  sessionId: string;
}

const uuid = (): string => {
  const cryptoObject = globalThis.crypto as Crypto & { randomUUID?: () => string } | undefined;
  if (cryptoObject?.randomUUID) return cryptoObject.randomUUID();
  const bytes = new Uint8Array(16);
  cryptoObject?.getRandomValues?.(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return [...bytes].map((byte, index) => `${[4, 6, 8, 10].includes(index) ? '-' : ''}${byte.toString(16).padStart(2, '0')}`).join('');
};

const doNotTrack = (): boolean => {
  const value = globalThis.navigator?.doNotTrack;
  return value === '1' || value === 'yes';
};

const storageId = (storage: Storage | undefined, key: string): string => {
  try {
    const existing = storage?.getItem(key);
    if (existing) return existing;
    const created = uuid();
    storage?.setItem(key, created);
    return created;
  } catch {
    return uuid();
  }
};

export class Tracker {
  private readonly endpoint: string;
  private readonly maxBatchSize: number;
  private readonly flushInterval: number;
  private readonly visitorId: string;
  private readonly sessionId: string;
  private queue: EventPayload[] = [];
  private timer: ReturnType<typeof setTimeout> | undefined;
  private currentPageStartedAt: number | undefined;
  private readonly pageViewUrls = new Set<string>();

  constructor(private readonly options: TrackerOptions) {
    this.endpoint = options.endpoint ?? '/api/v1/collect';
    this.maxBatchSize = Math.max(1, Math.min(options.maxBatchSize ?? 10, 100));
    this.flushInterval = Math.max(100, options.flushInterval ?? 2000);
    this.visitorId = storageId(globalThis.localStorage, `seeray:${options.siteId}:visitor_id`);
    this.sessionId = storageId(globalThis.sessionStorage, `seeray:${options.siteId}:session_id`);
    globalThis.addEventListener?.('pagehide', () => void this.flush(true));
    globalThis.addEventListener?.('visibilitychange', () => {
      if (globalThis.document?.visibilityState === 'hidden') void this.flush(true);
    });
  }

  trackPageView(options: TrackOptions = {}): void {
    const pageUrl = options.url ?? globalThis.location?.href ?? '';
    if (this.pageViewUrls.has(pageUrl)) return;
    this.pageViewUrls.add(pageUrl);
    const durationMs = this.currentPageStartedAt === undefined ? options.durationMs : Math.max(0, Date.now() - this.currentPageStartedAt);
    this.currentPageStartedAt = Date.now();
    this.track('page_view', { ...options, durationMs });
  }

  trackGoal(name: string, options: Omit<TrackOptions, 'name'> = {}): void {
    if (!name.trim()) return;
    this.track('goal', { ...options, name: name.trim() });
  }

  track(type: string, options: TrackOptions = {}): void {
    if (doNotTrack() || !type || type.length > 64) return;
    const event: EventPayload = {
      eventId: uuid(),
      type,
      occurredAt: new Date().toISOString(),
      url: options.url ?? globalThis.location?.href,
      title: options.title ?? globalThis.document?.title,
      referrer: options.referrer ?? globalThis.document?.referrer,
      durationMs: options.durationMs,
      properties: options.properties,
      category: options.category,
      action: options.action,
      name: options.name,
      visitorId: this.visitorId,
      sessionId: this.sessionId,
    };
    this.queue.push(event);
    if (this.queue.length >= this.maxBatchSize) void this.flush();
    else this.schedule();
  }

  async flush(unload = false): Promise<void> {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    if (!this.queue.length || doNotTrack()) return;
    const events = this.queue.splice(0, this.maxBatchSize);
    const body = JSON.stringify({ schemaVersion: 1, siteId: this.options.siteId, sentAt: new Date().toISOString(), events });
    if (unload && globalThis.navigator?.sendBeacon) {
      if (globalThis.navigator.sendBeacon(this.endpoint, new Blob([body], { type: 'application/json' }))) return;
    }
    try {
      const response = await fetch(this.endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, keepalive: unload });
      if (!response.ok) throw new Error(`collector returned ${response.status}`);
    } catch {
      this.queue.unshift(...events);
      this.schedule();
    }
  }

  private schedule(): void {
    if (this.timer) return;
    this.timer = setTimeout(() => void this.flush(), this.flushInterval);
  }
}

const trackers = new Map<string, Tracker>();

export const SeeRay = {
  init(options: TrackerOptions): Tracker {
    const existing = trackers.get(options.siteId);
    if (existing) return existing;
    const tracker = new Tracker(options);
    trackers.set(options.siteId, tracker);
    return tracker;
  },
  trackPageView(options?: TrackOptions): void { trackers.forEach((tracker) => tracker.trackPageView(options)); },
  track(type: string, options?: TrackOptions): void { trackers.forEach((tracker) => tracker.track(type, options)); },
  trackGoal(name: string, options?: Omit<TrackOptions, 'name'>): void { trackers.forEach((tracker) => tracker.trackGoal(name, options)); },
  flush(): Promise<void> { return Promise.all([...trackers.values()].map((tracker) => tracker.flush())).then(() => undefined); },
};

export const init = (options: TrackerOptions): Tracker => SeeRay.init(options);
