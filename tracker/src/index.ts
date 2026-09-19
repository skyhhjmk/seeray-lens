import { onCLS, onINP, onLCP, type Metric } from 'web-vitals';

export const TRACKER_VERSION = '0.9.0';

export interface HeatmapOptions { enabled?: boolean; sampleRate?: number; navigationMode?: 'auto' | 'manual'; layoutVersion?: string; }
export interface PageReadyOptions { url?: string; layoutVersion?: string; }
export interface ScrollContainerOptions { id: string; element: HTMLElement; }
export interface TagManagerPreviewOptions { sessionId: string; token: string; }
export interface TrackOptions { url?: string; title?: string; referrer?: string; durationMs?: number; properties?: Record<string, unknown>; category?: string; action?: string; name?: string; anonymous?: boolean; }
export type TrackerHook = 'track' | 'navigation' | 'consent';
export interface TrackerEvent {
  readonly eventId: string;
  readonly type: string;
  readonly occurredAt: string;
  readonly url?: string;
  readonly title?: string;
  readonly referrer?: string;
  readonly durationMs?: number;
  readonly properties?: Readonly<Record<string, unknown>>;
  readonly category?: string;
  readonly action?: string;
  readonly name?: string;
}
export interface TrackerNavigationEvent {
  readonly phase: 'begin' | 'cancel' | 'ready';
  readonly url?: string;
}
export interface TrackerConsentEvent {
  readonly state: 'granted' | 'denied';
  readonly granted: boolean;
}
export type TrackerPluginPayload = TrackerEvent | TrackerNavigationEvent | TrackerConsentEvent;
export type TrackerPluginListener = (payload: TrackerPluginPayload) => void;
export interface TrackerPluginContext {
  readonly siteId: string;
  readonly trackerVersion: string;
  on(hook: TrackerHook, listener: TrackerPluginListener): () => void;
  track(type: string, options?: TrackOptions): void;
  getConsentState(): 'granted' | 'denied' | 'unknown';
}
export interface TrackerPlugin {
  readonly name: string;
  readonly version?: string;
  setup(context: TrackerPluginContext): void | (() => void);
}
export interface TrackerOptions { siteId: string; endpoint?: string; apiOrigin?: string; maxBatchSize?: number; flushInterval?: number; requireConsent?: boolean; trackDownloads?: boolean; trackOutlinks?: boolean; trackForms?: boolean; trackMedia?: boolean; trackErrors?: boolean; crashRelease?: string; tagManager?: boolean; tagManagerEnvironment?: string; tagManagerPreview?: TagManagerPreviewOptions; experiments?: boolean; webVitals?: boolean; heatmap?: HeatmapOptions; plugins?: TrackerPlugin[]; }
export interface SiteSearchOptions extends Omit<TrackOptions, 'category' | 'action' | 'name' | 'properties'> { category?: string; resultsCount?: number; }
export interface ContentTrackingOptions extends Omit<TrackOptions, 'category' | 'action' | 'name' | 'properties'> { piece?: string; target?: string; interaction?: string; }
interface ClientContext { browser: string; browserVersion?: string; operatingSystem: string; operatingSystemVersion?: string; deviceType: string; language?: string; screenWidth?: number; screenHeight?: number; viewportWidth?: number; viewportHeight?: number; pixelRatio?: number; }
interface EventPayload extends TrackOptions { eventId: string; type: string; occurredAt: string; visitorId?: string; sessionId?: string; userId?: string; context: ClientContext; }
interface HeatmapConfig { enabled: boolean; sampleRate: number; version?: number; autoSnapshotEnabled: boolean; recordingEnabled: boolean; recordingSampleRate: number; }
interface TagDefinition { type?: unknown; trigger?: unknown; triggers?: unknown; eventType?: unknown; category?: unknown; action?: unknown; name?: unknown; code?: unknown; properties?: unknown; }
interface TagPreviewEvent { tagIndex: number; triggerEvent: string; outcome: 'fired' | 'no_match' | 'blocked'; pagePath: string; }
interface ExperimentDefinition { name?: unknown; variants?: unknown; targeting?: unknown; allocationGroup?: unknown; }
interface ExperimentTargeting { pathPrefixes: string[]; deviceTypes: string[]; }
interface LoadedExperiment { variants: string[]; targeting: ExperimentTargeting; allocationGroup?: string; }
const EXPERIMENT_DEVICE_TYPES = new Set(['desktop', 'mobile', 'tablet', 'other']);
interface HeatmapEvent { type: 'start' | 'click' | 'move' | 'scroll'; instanceId: string; url: string; layoutVersion: string; targetId: string; viewportWidth: number; viewportHeight: number; contentWidth: number; contentHeight: number; x?: number; y?: number; scrollBins?: number[]; truncated?: boolean; dropped?: number; }
interface ContainerRegistration { element: HTMLElement; remove: () => void; }
interface HeatmapBatch { clientBatchId: string; events: HeatmapEvent[]; }
interface PageOverlayData { storageKey: string; sourcePath: string; from: string; to: string; targets: Array<{ sourcePath: string; path: string; sessions: number }>; }
interface RecorderModule { startCapture(options: { siteId: string; snapshotEndpoint: string; recordingEndpoint: string; identity: HeatmapEvent; captureSnapshot: boolean; captureRecording: boolean; recordingId: string }): () => void; }

const uuid = (): string => { const c = globalThis.crypto as Crypto & { randomUUID?: () => string } | undefined; if (c?.randomUUID) return c.randomUUID(); const b = new Uint8Array(16); c?.getRandomValues?.(b); b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80; return [...b].map((x, i) => `${[4, 6, 8, 10].includes(i) ? '-' : ''}${x.toString(16).padStart(2, '0')}`).join(''); };
const doNotTrack = (): boolean => ['1', 'yes'].includes(globalThis.navigator?.doNotTrack ?? '');
const storageId = (storage: Storage | undefined, key: string): string => { try { const old = storage?.getItem(key); if (old) return old; const value = uuid(); storage?.setItem(key, value); return value; } catch { return uuid(); } };
const rate = (value: number | undefined): number => Math.max(0, Math.min(100, value ?? 10));
const text = (value: unknown): string | undefined => typeof value === 'string' && value.trim() ? value.trim() : undefined;
const stripControls = (value: string): string => Array.from(value)
  .filter(character => {
    const code = character.codePointAt(0)!;
    return code >= 32 && !(code >= 0x7f && code <= 0x9f);
  })
  .join('');
const boundedText = (value: unknown, max: number): string | undefined => typeof value === 'string'
  ? stripControls(value).trim().replace(/\s+/g, ' ').slice(0, max) || undefined
  : undefined;
const contentTarget = (value: unknown): string | undefined => {
  const target = boundedText(value, 2048);
  return target?.split(/[?#]/, 1)[0].trim() || undefined;
};
const crashText = (value: unknown, max: number): string | undefined => {
  if (typeof value !== 'string') return undefined;
  const safe = stripControls(value)
    .replace(/https?:\/\/\S+/gi, '<url>')
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, '<email>')
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi, '<id>')
    .replace(/\b(?:[A-Za-z0-9_-]{32,}|\d{4,})\b/g, '<value>')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
  return safe || undefined;
};
const crashRelease = (value: unknown): string | undefined =>
  typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$/.test(value.trim()) ? value.trim() : undefined;
const crashPath = (value: string | undefined): string => {
  let path = (value?.split(/[?#]/, 1)[0] || '/').replace(/\\/g, '/');
  try {
    if (/^https?:\/\//i.test(path)) path = new URL(path).pathname;
  } catch { path = '/'; }
  return path
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, '<email>')
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi, '<id>')
    .replace(/(^|\/)\d{4,}(?=\/|$)/g, '$1<id>')
    .replace(/(^|\/)[A-Za-z0-9_-]{32,}(?=\/|$)/g, '$1<id>')
    .slice(0, 1024) || '/';
};
const isProperties = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value);
const absoluteApiUrl = (path: string, base?: string): string => {
  try {
    const reference = base ?? globalThis.location?.href;
    return reference ? new URL(path, reference).toString() : path;
  } catch {
    return path;
  }
};
export const resolveApiOrigin = (scriptSrc?: string): string | undefined => {
  try {
    const reference = scriptSrc ?? globalThis.location?.href;
    const base = globalThis.document?.baseURI ?? globalThis.location?.href;
    if (!reference) return undefined;
    const url = new URL(reference, base);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.origin : undefined;
  } catch {
    return undefined;
  }
};
const ignored = (target: EventTarget | null): boolean => target instanceof Element && !!target.closest('[data-seeray-heatmap-ignore]');
const fixed = (target: EventTarget | null): boolean => { for (let e = target instanceof Element ? target : null; e; e = e.parentElement) { const p = globalThis.getComputedStyle?.(e).position; if (p === 'fixed' || p === 'sticky') return true; } return false; };
const majorVersion = (ua: string, expression: RegExp): string | undefined => expression.exec(ua)?.[1];
const clientContext = (): ClientContext => {
  const nav = globalThis.navigator;
  const ua = nav?.userAgent ?? '';
  let browser = 'Other';
  let browserVersion: string | undefined;
  if (/SamsungBrowser\//.test(ua)) { browser = 'Samsung Internet'; browserVersion = majorVersion(ua, /SamsungBrowser\/(\d+)/); }
  else if (/Edg(?:A|iOS)?\//.test(ua)) { browser = 'Edge'; browserVersion = majorVersion(ua, /Edg(?:A|iOS)?\/(\d+)/); }
  else if (/OPR\//.test(ua) || /Opera\//.test(ua) || /OPiOS\//.test(ua)) { browser = 'Opera'; browserVersion = majorVersion(ua, /(?:OPR|Opera|OPiOS)\/(\d+)/); }
  else if (/Firefox\//.test(ua) || /FxiOS\//.test(ua)) { browser = 'Firefox'; browserVersion = majorVersion(ua, /(?:Firefox|FxiOS)\/(\d+)/); }
  else if ((/Chrome\//.test(ua) || /CriOS\//.test(ua)) && !/Chromium\//.test(ua)) { browser = 'Chrome'; browserVersion = majorVersion(ua, /(?:Chrome|CriOS)\/(\d+)/); }
  else if (/Safari\//.test(ua)) { browser = 'Safari'; browserVersion = majorVersion(ua, /Version\/(\d+)/); }
  let operatingSystem = 'Other';
  let operatingSystemVersion: string | undefined;
  if (/Android/.test(ua)) { operatingSystem = 'Android'; operatingSystemVersion = majorVersion(ua, /Android ([\d.]+)/); }
  else if (/iPhone|iPad|iPod/.test(ua) || nav?.platform === 'MacIntel' && nav.maxTouchPoints > 1) { operatingSystem = 'iOS'; operatingSystemVersion = majorVersion(ua, /OS ([\d_]+)/)?.replaceAll('_', '.'); }
  else if (/Windows NT/.test(ua)) { operatingSystem = 'Windows'; operatingSystemVersion = majorVersion(ua, /Windows NT ([\d.]+)/); }
  else if (/Mac OS X/.test(ua)) { operatingSystem = 'macOS'; operatingSystemVersion = majorVersion(ua, /Mac OS X ([\d_]+)/)?.replaceAll('_', '.'); }
  else if (/CrOS/.test(ua)) { operatingSystem = 'ChromeOS'; operatingSystemVersion = majorVersion(ua, /CrOS [^ ]+ ([\d.]+)/); }
  else if (/Linux/.test(ua)) operatingSystem = 'Linux';
  const isTablet = /iPad|Tablet|Android(?!.*Mobile)/i.test(ua) || nav?.platform === 'MacIntel' && nav.maxTouchPoints > 1;
  const deviceType = isTablet ? 'tablet' : /Mobile|iPhone|iPod|Android/i.test(ua) ? 'mobile' : ua ? 'desktop' : 'other';
  const screen = globalThis.screen;
  const width = (value: number | undefined): number | undefined => Number.isFinite(value) && value! > 0 && value! <= 10000 ? Math.round(value!) : undefined;
  return {
    browser,
    browserVersion,
    operatingSystem,
    operatingSystemVersion,
    deviceType,
    language: text(nav?.language)?.slice(0, 35),
    screenWidth: width(screen?.width),
    screenHeight: width(screen?.height),
    viewportWidth: width(globalThis.innerWidth),
    viewportHeight: width(globalThis.innerHeight),
    pixelRatio: Number.isFinite(globalThis.devicePixelRatio) && globalThis.devicePixelRatio > 0 ? Math.min(8, globalThis.devicePixelRatio) : undefined,
  };
};

export class Tracker {
  private readonly endpoint: string; private readonly heatmapEndpoint: string; private readonly heatmapConfigEndpoint: string; private readonly tagManagerEndpoint: string; private readonly experimentsEndpoint: string; private readonly snapshotPlanEndpoint: string; private readonly snapshotEndpoint: string; private readonly recordingEndpoint: string; private readonly recorderEndpoint: string; private readonly maxBatchSize: number; private readonly flushInterval: number; private visitorId!: string; private sessionId!: string; private recordingId!: string; private identityPersisted = false; private consentOverride?: 'granted' | 'denied';
  private readonly tagManagerPreviewEndpoint?: string;
  private readonly tagManagerPreviewEventsEndpoint?: string;
  private readonly tagManagerPreviewToken?: string;
  private queue: EventPayload[] = []; private timer: ReturnType<typeof setTimeout> | undefined; private currentPageStartedAt: number | undefined; private pageViewRecorded = false; private userId: string | undefined;
  private heatmapConfig: HeatmapConfig | undefined; private heatmapQueue: HeatmapEvent[] = []; private heatmapTimer: ReturnType<typeof setTimeout> | undefined; private heatmapInstance: string | undefined; private heatmapUrl = ''; private heatmapLayoutVersion = 'unversioned'; private heatmapSelected = false; private heatmapNavigating = false;
  private moveCount = 0; private clickCount = 0; private dropped = 0; private moveTruncated = false; private clickTruncated = false; private lastMove = 0; private listenersInstalled = false; private behaviourListenerInstalled = false; private siteSearchListenerInstalled = false; private contentListenerInstalled = false; private formListenerInstalled = false; private mediaListenerInstalled = false; private errorListenerInstalled = false; private webVitalsStarted = false; private historyInstalled = false; private navigationSerial = 0; private layoutTimer: ReturnType<typeof setTimeout> | undefined; private heatmapRetry: HeatmapBatch | undefined; private heatmapFlushInFlight = false; private resizeObserver: ResizeObserver | undefined; private contentObserver: IntersectionObserver | undefined; private formViewObserver: IntersectionObserver | undefined; private formMutationObserver: MutationObserver | undefined; private contentSeen = new WeakSet<Element>(); private contentObserved = new WeakSet<Element>(); private formSeen = new WeakSet<Element>(); private formStarted = new WeakSet<Element>(); private interactedFormFields = new WeakSet<Element>(); private activeFormFields = new WeakMap<Element, { formId: string; startedAt: number; fieldType: string }>(); private mediaStarted = new WeakSet<Element>(); private mediaCompleted = new WeakSet<Element>(); private mediaMilestones = new WeakMap<Element, Set<number>>(); private recordingSelected = false; private recorderStop: (() => void) | undefined;
  private readonly containers = new Map<string, ContainerRegistration>(); private readonly scrollBins = new Map<string, Set<number>>(); private readonly lastScroll = new Map<string, number>();
  private readonly layoutSegments = new Map<string, string>();
  private tagDefinitions: TagDefinition[] = [];
  private previewExecuteCustomCode = false;
  private readonly experimentDefinitions = new Map<string, LoadedExperiment>();
  private readonly experimentLayerAssignments = new Map<string, string>();
  private pageOverlayData?: PageOverlayData;
  private pageOverlayNavigationInstalled = false;
  private readyPromise: Promise<void> = Promise.resolve();
  private readonly pluginListeners = new Map<TrackerHook, Set<TrackerPluginListener>>();
  private readonly pluginCleanups = new Map<string, () => void>();

  constructor(private readonly options: TrackerOptions) {
    const apiBase = options.apiOrigin ?? options.endpoint;
    this.endpoint = options.endpoint ?? absoluteApiUrl('/api/v1/collect', apiBase); this.heatmapEndpoint = absoluteApiUrl('/api/v1/collect/heatmaps', apiBase); this.heatmapConfigEndpoint = absoluteApiUrl(`/api/v1/heatmap-config/${encodeURIComponent(options.siteId)}`, apiBase); const requestedTagEnvironment = options.tagManagerEnvironment ?? 'production'; const tagEnvironment = ['development', 'staging', 'production'].includes(requestedTagEnvironment) ? requestedTagEnvironment : 'production'; this.tagManagerEndpoint = `${absoluteApiUrl(`/api/v1/tag-manager/${encodeURIComponent(options.siteId)}/container`, apiBase)}?environment=${encodeURIComponent(tagEnvironment)}`; this.experimentsEndpoint = absoluteApiUrl(`/api/v1/experiments/${encodeURIComponent(options.siteId)}/definitions`, apiBase); this.snapshotPlanEndpoint = absoluteApiUrl(`/api/v1/collect/dom-snapshots/plan/${encodeURIComponent(options.siteId)}`, apiBase); this.snapshotEndpoint = absoluteApiUrl(`/api/v1/collect/dom-snapshots/${encodeURIComponent(options.siteId)}`, apiBase); this.recordingEndpoint = absoluteApiUrl(`/api/v1/collect/recordings/${encodeURIComponent(options.siteId)}`, apiBase); this.recorderEndpoint = absoluteApiUrl('/recorder.js', apiBase); this.maxBatchSize = Math.max(1, Math.min(options.maxBatchSize ?? 10, 100)); this.flushInterval = Math.max(100, options.flushInterval ?? 2000);
    this.startPageOverlay(apiBase);
    if (this.getConsentState() === 'granted' && !doNotTrack()) this.persistIdentity();
    else this.useEphemeralIdentity();
    const preview = options.tagManagerPreview;
    if (preview?.sessionId && preview.token) {
      const previewPath = `/api/v1/tag-manager/${encodeURIComponent(options.siteId)}/preview/${encodeURIComponent(preview.sessionId)}`;
      this.tagManagerPreviewEndpoint = absoluteApiUrl(previewPath, apiBase);
      this.tagManagerPreviewEventsEndpoint = absoluteApiUrl(`${previewPath}/events`, apiBase);
      this.tagManagerPreviewToken = preview.token;
    }
    // Install collection listeners only after the policy permits measurement.
    globalThis.addEventListener?.('pagehide', () => { void this.flush(true); void this.flushHeatmap(true); this.stopRecorder(); }); globalThis.addEventListener?.('visibilitychange', () => { if (globalThis.document?.visibilityState === 'hidden') { void this.flush(true); void this.flushHeatmap(true); } else this.refreshHeatmapLayout(); });
    this.activateCollectionListeners();
    this.installPrivacyPreferencesBridge();
    this.readyPromise = this.loadConfigured();
    for (const plugin of options.plugins ?? []) this.use(plugin);
  }
  private installPrivacyPreferencesBridge(): void {
    globalThis.addEventListener?.('message', (event: MessageEvent) => {
      const apiOrigin = resolveApiOrigin(this.endpoint);
      if (!apiOrigin || event.origin !== apiOrigin || !isProperties(event.data)) return;
      const message = event.data;
      if (message.source !== 'seeray-privacy' || message.siteId !== this.options.siteId) return;
      const frame = [...(globalThis.document?.querySelectorAll<HTMLIFrameElement>('iframe[data-seeray-privacy]') ?? [])]
        .find(candidate => candidate.contentWindow === event.source);
      if (!frame) return;
      let frameUrl: URL;
      try { frameUrl = new URL(frame.src, globalThis.document?.baseURI ?? globalThis.location?.href); } catch { return; }
      if (frameUrl.origin !== apiOrigin || frameUrl.pathname !== '/privacy/preferences' || frameUrl.searchParams.get('siteId') !== this.options.siteId) return;
      const reply = (): void => frame.contentWindow?.postMessage({
        source: 'seeray-tracker',
        type: 'privacy-state',
        siteId: this.options.siteId,
        state: this.getConsentState(),
      }, apiOrigin);
      if (message.type === 'privacy-state-request') {
        reply();
      } else if (message.type === 'privacy-consent-choice' && typeof message.granted === 'boolean') {
        this.setConsent(message.granted);
        reply();
      }
    });
  }
  getConsentState(): 'granted' | 'denied' | 'unknown' {
    if (this.consentOverride) return this.consentOverride;
    try {
      const saved = globalThis.localStorage?.getItem(this.consentKey());
      if (saved === 'granted' || saved === 'denied') return saved;
    } catch { /* Treat unavailable storage as an undecided visitor. */ }
    return this.options.requireConsent ? 'unknown' : 'granted';
  }
  hasConsent(): boolean { return this.getConsentState() === 'granted'; }
  setUserId(userId: string | null): void { this.userId = userId === null || !this.collectionAllowed() ? undefined : boundedText(userId, 256); }
  setConsent(granted: boolean): void {
    const state = granted ? 'granted' : 'denied';
    this.consentOverride = state;
    try { globalThis.localStorage?.setItem(this.consentKey(), state); } catch { /* Storage may be unavailable in restrictive browser contexts. */ }
    if (!granted) {
      this.userId = undefined;
      this.queue = [];
      this.heatmapQueue = [];
      this.heatmapRetry = undefined;
      if (this.timer) clearTimeout(this.timer);
      if (this.heatmapTimer) clearTimeout(this.heatmapTimer);
      this.timer = this.heatmapTimer = undefined;
      this.tagDefinitions = [];
      this.experimentDefinitions.clear();
      this.experimentLayerAssignments.clear();
      this.contentObserver?.disconnect();
      this.formViewObserver?.disconnect();
      this.formMutationObserver?.disconnect();
      this.mediaStarted = new WeakSet<Element>();
      this.mediaCompleted = new WeakSet<Element>();
      this.mediaMilestones = new WeakMap<Element, Set<number>>();
      this.stopRecorder();
      this.removeStoredIdentity();
      this.useEphemeralIdentity();
    } else {
      if (!doNotTrack()) this.persistIdentity();
      this.activateCollectionListeners();
      this.readyPromise = this.loadConfigured();
    }
    this.emitPlugin('consent', { state, granted });
    try {
      globalThis.dispatchEvent?.(new CustomEvent('seeray:consent', { detail: { state, granted } }));
    } catch { /* CustomEvent is unavailable in non-browser runtimes. */ }
  }
  optOut(): void { this.setConsent(false); }
  ready(): Promise<void> { return this.readyPromise; }
  use(plugin: TrackerPlugin): () => void {
    if (!plugin || !/^[a-z][a-z0-9._-]{1,63}$/.test(plugin.name)) {
      throw new TypeError('Tracker plugin names must use 2-64 lowercase characters');
    }
    const previous = this.pluginCleanups.get(plugin.name);
    if (previous) return previous;
    const registrations = new Set<() => void>();
    const context: TrackerPluginContext = {
      siteId: this.options.siteId,
      trackerVersion: TRACKER_VERSION,
      on: (hook, listener) => {
        if (typeof listener !== 'function') return () => undefined;
        const listeners = this.pluginListeners.get(hook) ?? new Set<TrackerPluginListener>();
        listeners.add(listener);
        this.pluginListeners.set(hook, listeners);
        const remove = (): void => { listeners.delete(listener); };
        registrations.add(remove);
        return remove;
      },
      track: (type, options) => this.track(type, options),
      getConsentState: () => this.getConsentState(),
    };
    let setupCleanup: void | (() => void);
    try {
      setupCleanup = plugin.setup(context);
    } catch {
      setupCleanup = undefined;
    }
    const dispose = (): void => {
      if (this.pluginCleanups.get(plugin.name) !== dispose) return;
      for (const remove of registrations) remove();
      try { setupCleanup?.(); } catch { /* A plugin cleanup must not break tracking. */ }
      this.pluginCleanups.delete(plugin.name);
    };
    this.pluginCleanups.set(plugin.name, dispose);
    return dispose;
  }
  private emitPlugin(hook: TrackerHook, payload: TrackerPluginPayload): void {
    for (const listener of this.pluginListeners.get(hook) ?? []) {
      try { listener(payload); } catch { /* A plugin must never interrupt collection. */ }
    }
  }
  assignExperiment(experiment: string, variations?: string[]): string | undefined { const name = experiment.trim(); const configured = name ? this.experimentDefinitions.get(name) : undefined; const choices = (variations?.length ? variations : configured?.variants ?? []).filter(value => value.trim()); if (!this.collectionAllowed() || !name || !choices.length || this.options.experiments && !configured || configured && !this.matchesExperimentTarget(configured.targeting)) return undefined; if (configured?.allocationGroup && !this.matchesExperimentLayer(name, configured.allocationGroup)) return undefined; const key = `seeray:${this.options.siteId}:experiment:${name}`; let selected: string | null = null; try { selected = globalThis.localStorage?.getItem(key) ?? null; if (!selected || !choices.includes(selected)) { selected = choices[Math.floor(Math.random() * choices.length)]; globalThis.localStorage?.setItem(key, selected); } } catch { selected = choices[Math.floor(Math.random() * choices.length)]; } this.track('experiment_exposure', { category: 'experiment', action: name, name: selected }); return selected; }
  trackPageView(options: TrackOptions = {}): void { if (!this.collectionAllowed() || this.pageViewRecorded) return; this.pageViewRecorded = true; const durationMs = this.currentPageStartedAt === undefined ? options.durationMs : Math.max(0, Date.now() - this.currentPageStartedAt); this.currentPageStartedAt = Date.now(); this.track('page_view', { ...options, durationMs }); this.fireTagTriggers({ event: 'page_view', ...options }); }
  trackGoal(name: string, options: Omit<TrackOptions, 'name'> = {}): void { if (name.trim()) this.track('goal', { ...options, name: name.trim() }); }
  trackSiteSearch(keyword: string, options: SiteSearchOptions = {}): void {
    const normalized = stripControls(keyword).trim().replace(/\s+/g, ' ').slice(0, 256);
    if (!normalized) return;
    const category = text(options.category) ? stripControls(options.category!.trim()).slice(0, 120) : undefined;
    const resultsCount = Number.isSafeInteger(options.resultsCount) && options.resultsCount! >= 0 && options.resultsCount! <= 1_000_000_000
      ? options.resultsCount
      : undefined;
    const properties: Record<string, unknown> = { keyword: normalized };
    if (category) properties.searchCategory = category;
    if (resultsCount !== undefined) properties.resultsCount = resultsCount;
    this.track('site_search', {
      url: options.url,
      title: options.title,
      referrer: options.referrer,
      category: 'site_search',
      action: category,
      name: normalized,
      properties,
    });
  }
  trackContentImpression(contentName: string, options: ContentTrackingOptions = {}): void {
    this.trackContentEvent('content_impression', contentName, 'impression', options);
  }
  trackContentInteraction(contentName: string, options: ContentTrackingOptions = {}): void {
    this.trackContentEvent('content_interaction', contentName, boundedText(options.interaction, 120) ?? 'click', options);
  }
  private normalizeFormId(value: unknown): string | undefined {
    return typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(value) ? value : undefined;
  }
  private formId(form: Element): string | undefined {
    if (form.closest('[data-seeray-no-track]')) return undefined;
    return this.normalizeFormId(form.getAttribute('data-seeray-form'));
  }
  private elementVisible(element: Element): boolean {
    const rect = element.getBoundingClientRect?.();
    if (!rect || rect.width <= 0 || rect.height <= 0) return false;
    const width = globalThis.innerWidth || globalThis.document?.documentElement?.clientWidth || 0;
    const height = globalThis.innerHeight || globalThis.document?.documentElement?.clientHeight || 0;
    return rect.bottom > 0 && rect.right > 0 && rect.top < height && rect.left < width;
  }
  private recordFormView(form: Element): void {
    const formId = this.formId(form);
    if (!formId || !this.collectionAllowed()) return;
    this.track('form_view', { category: 'form', action: 'view', name: formId, properties: { formId } });
  }
  private recordFormStart(form: Element): string | undefined {
    const formId = this.formId(form);
    if (!formId || !this.collectionAllowed()) return undefined;
    if (!this.formStarted.has(form)) {
      this.formStarted.add(form);
      this.track('form_start', { category: 'form', action: 'start', name: formId, properties: { formId } });
    }
    return formId;
  }
  private formField(target: EventTarget | null): { field: HTMLElement; form: HTMLFormElement; formId: string; fieldType: string } | undefined {
    if (!(target instanceof HTMLElement) || target.closest('[data-seeray-no-track]')) return undefined;
    const field = target.closest<HTMLElement>('input,select,textarea');
    const form = field?.closest<HTMLFormElement>('form[data-seeray-form]');
    if (!field || !form) return undefined;
    const formId = this.formId(form);
    if (!formId || ('disabled' in field && field.disabled)) return undefined;
    const tag = field.tagName.toLowerCase();
    const type = tag === 'input' ? ((field as HTMLInputElement).type || 'text').toLowerCase() : tag;
    if (['hidden', 'password', 'file', 'button', 'reset', 'submit', 'image'].includes(type)) return undefined;
    const autocomplete = field.getAttribute('autocomplete')?.toLowerCase() ?? '';
    if (/password|cc-|one-time-code|current-password|new-password/.test(autocomplete)) return undefined;
    const fieldType = type === 'email' || type === 'tel' || type === 'url' || type === 'search' || type === 'text' || type === 'textarea'
      ? 'text'
      : type === 'number' || type === 'range' ? 'number'
        : ['checkbox', 'radio', 'select', 'select-one', 'select-multiple'].includes(type) ? 'choice'
          : type === 'date' || type === 'time' || type === 'datetime-local' ? 'date_time'
            : 'other';
    return { field, form, formId, fieldType };
  }
  private recordFormField(target: EventTarget | null): void {
    if (!this.collectionAllowed()) return;
    const item = this.formField(target);
    if (!item) return;
    if (this.interactedFormFields.has(item.field)) return;
    this.interactedFormFields.add(item.field);
    if (!this.recordFormStart(item.form)) return;
    this.activeFormFields.set(item.field, { formId: item.formId, startedAt: Date.now(), fieldType: item.fieldType });
    this.track('form_field', { category: 'form', action: 'field', name: item.formId, properties: { formId: item.formId, fieldType: item.fieldType } });
  }
  private installFormTracking(): void {
    if (this.formListenerInstalled || !this.options.trackForms) return;
    this.formListenerInstalled = true;
    const document = globalThis.document;
    if (!document?.addEventListener) return;
    document.addEventListener('focusin', event => {
      if (!this.collectionAllowed()) return;
      const item = this.formField(event.target);
      if (!item) return;
      this.recordFormField(event.target);
      if (!this.activeFormFields.has(item.field)) this.activeFormFields.set(item.field, { formId: item.formId, startedAt: Date.now(), fieldType: item.fieldType });
    }, true);
    document.addEventListener('input', event => this.recordFormField(event.target), true);
    document.addEventListener('change', event => this.recordFormField(event.target), true);
    document.addEventListener('focusout', event => {
      if (!this.collectionAllowed()) return;
      const item = this.formField(event.target);
      const active = item && this.activeFormFields.get(item.field);
      if (!item || !active) return;
      this.activeFormFields.delete(item.field);
      const durationMs = Math.min(3_600_000, Math.max(0, Date.now() - active.startedAt));
      if (durationMs > 0) this.track('form_field_time', { category: 'form', action: 'field_time', name: active.formId, durationMs, properties: { formId: active.formId, fieldType: active.fieldType } });
    }, true);
    document.addEventListener('invalid', event => {
      if (!this.collectionAllowed()) return;
      const item = this.formField(event.target);
      if (!item || !this.recordFormStart(item.form)) return;
      this.track('form_error', { category: 'form', action: 'validation_error', name: item.formId, properties: { formId: item.formId, fieldType: item.fieldType } });
    }, true);
    document.addEventListener('submit', event => {
      if (!this.collectionAllowed() || !(event.target instanceof HTMLFormElement)) return;
      const formId = this.formId(event.target);
      if (!formId) return;
      this.recordFormStart(event.target);
      this.track('form_submit', { category: 'form', action: 'submit', name: formId, properties: { formId } });
    }, true);
  }
  refreshFormTracking(reset = false): void {
    if (!this.options.trackForms) return;
    const document = globalThis.document;
    if (!document || !this.collectionAllowed()) {
      this.formViewObserver?.disconnect();
      this.formMutationObserver?.disconnect();
      return;
    }
    if (reset) {
      this.formViewObserver?.disconnect();
      this.formMutationObserver?.disconnect();
      this.formSeen = new WeakSet<Element>();
      this.formStarted = new WeakSet<Element>();
      this.interactedFormFields = new WeakSet<Element>();
      this.activeFormFields = new WeakMap<Element, { formId: string; startedAt: number; fieldType: string }>();
    }
    const observe = (form: Element): void => {
      if (this.formSeen.has(form) || !this.formId(form)) return;
      this.formSeen.add(form);
      if (typeof IntersectionObserver !== 'undefined') {
        this.formViewObserver ??= new IntersectionObserver(entries => {
          for (const entry of entries) {
            if (entry.isIntersecting && entry.intersectionRatio >= 0.1) {
              this.recordFormView(entry.target);
              this.formViewObserver?.unobserve(entry.target);
            }
          }
        }, { threshold: [0.1] });
        this.formViewObserver.observe(form);
      } else if (this.elementVisible(form)) this.recordFormView(form);
    };
    const scan = (root: ParentNode): void => {
      root.querySelectorAll?.('form[data-seeray-form]')?.forEach(observe);
      if (root instanceof Element && root.matches('form[data-seeray-form]')) observe(root);
    };
    scan(document);
    if (typeof MutationObserver !== 'undefined') {
      const target = document.body ?? document.documentElement;
      if (target) {
        this.formMutationObserver ??= new MutationObserver(records => {
          for (const record of records) record.addedNodes.forEach(node => {
            if (node instanceof Element) scan(node);
          });
        });
        this.formMutationObserver.observe(target, { childList: true, subtree: true });
      }
    }
  }
  trackFormResult(formId: string, successful: boolean): void {
    if (!this.options.trackForms || typeof successful !== 'boolean') return;
    const id = this.normalizeFormId(formId);
    if (!id) return;
    this.track(successful ? 'form_success' : 'form_failure', {
      category: 'form',
      action: successful ? 'success' : 'failure',
      name: id,
      properties: { formId: id },
    });
  }
  private mediaId(element: Element): string | undefined {
    if (element.closest('[data-seeray-no-track]')) return undefined;
    const raw = element.getAttribute('data-seeray-media');
    return typeof raw === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(raw) ? raw : undefined;
  }
  private recordMediaEvent(
    type: 'media_start' | 'media_progress' | 'media_complete',
    element: HTMLMediaElement,
    progressPercent?: number,
  ): void {
    if (!this.collectionAllowed()) return;
    const mediaId = this.mediaId(element);
    if (!mediaId) return;
    const mediaType = element.tagName.toLowerCase() === 'audio' ? 'audio' : 'video';
    const properties: Record<string, unknown> = { mediaId, mediaType };
    if (progressPercent !== undefined) properties.progressPercent = progressPercent;
    if (type === 'media_complete' && Number.isFinite(element.duration) && element.duration > 0)
      properties.mediaDurationSeconds = Math.min(604_800, Math.round(element.duration));
    this.track(type, {
      category: 'media',
      action: type === 'media_progress' ? `progress_${progressPercent}` : type.slice('media_'.length),
      name: mediaId,
      properties,
    });
  }
  private installMediaTracking(): void {
    if (this.mediaListenerInstalled || !this.options.trackMedia) return;
    this.mediaListenerInstalled = true;
    const document = globalThis.document;
    if (!document?.addEventListener) return;
    document.addEventListener('play', event => {
      if (!this.collectionAllowed() || !(event.target instanceof HTMLMediaElement)) return;
      const element = event.target;
      if (!this.mediaId(element) || this.mediaStarted.has(element)) return;
      this.mediaStarted.add(element);
      this.recordMediaEvent('media_start', element);
    }, true);
    document.addEventListener('timeupdate', event => {
      if (!this.collectionAllowed() || !(event.target instanceof HTMLMediaElement)) return;
      const element = event.target;
      const id = this.mediaId(element);
      if (!id || !this.mediaStarted.has(element) || !Number.isFinite(element.duration) || element.duration <= 0 || !Number.isFinite(element.currentTime)) return;
      const progress = Math.max(0, Math.min(100, element.currentTime / element.duration * 100));
      const milestones = this.mediaMilestones.get(element) ?? new Set<number>();
      this.mediaMilestones.set(element, milestones);
      for (const milestone of [25, 50, 75, 90]) {
        if (progress >= milestone && !milestones.has(milestone)) {
          milestones.add(milestone);
          this.recordMediaEvent('media_progress', element, milestone);
        }
      }
    }, true);
    document.addEventListener('ended', event => {
      if (!this.collectionAllowed() || !(event.target instanceof HTMLMediaElement)) return;
      const element = event.target;
      if (!this.mediaId(element) || this.mediaCompleted.has(element)) return;
      this.mediaCompleted.add(element);
      this.recordMediaEvent('media_complete', element);
    }, true);
  }
  private installErrorTracking(): void {
    if (this.errorListenerInstalled || !this.options.trackErrors) return;
    this.errorListenerInstalled = true;
    globalThis.addEventListener?.('error', event => {
      if (event.target && event.target !== globalThis) return; // Ignore resource failures; capture script exceptions only.
      const error = event as ErrorEvent;
      const detail = error.error as { name?: unknown; message?: unknown } | null;
      this.recordClientError(
        'javascript',
        detail?.name,
        detail?.message ?? error.message,
        error.filename,
        error.lineno,
        error.colno,
      );
    });
    globalThis.addEventListener?.('unhandledrejection', event => {
      const reason = (event as PromiseRejectionEvent).reason;
      let errorName: unknown;
      let message: unknown;
      try {
        if (reason instanceof Error) {
          errorName = reason.name;
          message = reason.message;
        } else if (typeof reason === 'string') {
          errorName = 'UnhandledRejection';
          message = reason;
        } else {
          errorName = 'UnhandledRejection';
          message = 'Unhandled promise rejection';
        }
      } catch {
        errorName = 'UnhandledRejection';
        message = 'Unhandled promise rejection';
      }
      this.recordClientError('unhandled_rejection', errorName, message);
    });
  }
  private recordClientError(
    kind: 'javascript' | 'unhandled_rejection',
    rawName: unknown,
    rawMessage: unknown,
    rawSource?: string,
    line?: number,
    column?: number,
  ): void {
    if (!this.collectionAllowed()) return;
    const errorName = crashText(rawName, 80)?.replace(/[^A-Za-z0-9_.$-]/g, '') || (kind === 'javascript' ? 'Error' : 'UnhandledRejection');
    const message = crashText(rawMessage, 240) ?? 'No error message';
    const sourcePath = crashPath(rawSource);
    const validPosition = (value: number | undefined): number | undefined =>
      Number.isSafeInteger(value) && value! > 0 && value! <= 10_000_000 ? value : undefined;
    const validColumn = (value: number | undefined): number | undefined =>
      Number.isSafeInteger(value) && value! >= 0 && value! <= 10_000_000 ? Math.max(1, value!) : undefined;
    const pagePath = crashPath(globalThis.location?.pathname);
    const origin = globalThis.location?.origin;
    this.track('client_error', {
      url: origin ? `${origin}${pagePath}` : undefined,
      title: '',
      referrer: '',
      category: 'error',
      action: kind,
      name: errorName,
      anonymous: true,
      properties: {
        errorName,
        message,
        sourcePath,
        line: validPosition(line),
        column: validColumn(column),
        releaseId: crashRelease(this.options.crashRelease),
      },
    });
  }
  private refreshMediaTracking(reset = false): void {
    if (!this.options.trackMedia) return;
    if (reset) {
      this.mediaStarted = new WeakSet<Element>();
      this.mediaCompleted = new WeakSet<Element>();
      this.mediaMilestones = new WeakMap<Element, Set<number>>();
    }
    if (!this.collectionAllowed()) return;
    globalThis.document?.querySelectorAll?.('audio[data-seeray-media],video[data-seeray-media]')?.forEach(element => {
      if (!(element instanceof HTMLMediaElement) || element.paused || !this.mediaId(element) || this.mediaStarted.has(element)) return;
      this.mediaStarted.add(element);
      const milestones = new Set<number>();
      const progress = Number.isFinite(element.duration) && element.duration > 0
        ? element.currentTime / element.duration * 100
        : 0;
      for (const milestone of [25, 50, 75, 90]) if (progress >= milestone) milestones.add(milestone);
      this.mediaMilestones.set(element, milestones);
      this.recordMediaEvent('media_start', element);
    });
  }
  push(data: DataLayerEvent): void { if (!data?.event) return; this.track(data.event, { url: data.url, title: data.title, referrer: data.referrer, category: data.eventCategory, action: data.eventAction, name: data.eventName, properties: data.properties }); this.fireTagTriggers(data); }
  track(type: string, options: TrackOptions = {}): void {
    if (this.options.tagManagerPreview || !this.collectionAllowed() || !type || type.length > 64) return;
    const eventId = uuid();
    const occurredAt = new Date().toISOString();
    const event = {
      eventId,
      type,
      occurredAt,
      url: options.url ?? globalThis.location?.href,
      title: options.title === null ? undefined : options.title ?? globalThis.document?.title,
      referrer: options.referrer === null ? undefined : options.referrer ?? globalThis.document?.referrer,
      durationMs: options.durationMs,
      properties: options.properties,
      category: options.category,
      action: options.action,
      name: options.name,
      visitorId: options.anonymous ? undefined : this.visitorId,
      sessionId: options.anonymous ? undefined : this.sessionId,
      userId: options.anonymous ? undefined : this.userId,
      context: clientContext(),
    };
    this.queue.push(event);
    this.emitPlugin('track', {
      eventId,
      type,
      occurredAt,
      url: event.url,
      title: event.title,
      referrer: event.referrer,
      durationMs: event.durationMs,
      properties: event.properties ? { ...event.properties } : undefined,
      category: event.category,
      action: event.action,
      name: event.name,
    });
    if (this.queue.length >= this.maxBatchSize) void this.flush(); else this.schedule();
  }
  async flush(unload = false): Promise<void> { if (this.timer) clearTimeout(this.timer); this.timer = undefined; if (!this.queue.length || !this.collectionAllowed()) return; const events = this.queue.splice(0, this.maxBatchSize); const body = JSON.stringify({ schemaVersion: 1, siteId: this.options.siteId, sentAt: new Date().toISOString(), events }); if (unload && globalThis.navigator?.sendBeacon && globalThis.navigator.sendBeacon(this.endpoint, new Blob([body], { type: 'application/json' }))) return; try { const response = await fetch(this.endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, keepalive: unload }); if (!response.ok) throw new Error(`collector returned ${response.status}`); } catch { this.queue.unshift(...events); this.schedule(); } }

  beginNavigation(): void { if (!this.heatmapNavigating) { this.heatmapNavigating = true; void this.flushHeatmap(); this.stopRecorder(); this.contentObserver?.disconnect(); this.formViewObserver?.disconnect(); } this.pageViewRecorded = false; this.emitPlugin('navigation', { phase: 'begin', url: globalThis.location?.href }); }
  cancelNavigation(): void { if (!this.heatmapNavigating) return; this.heatmapNavigating = false; this.navigationSerial++; this.pageViewRecorded = this.currentPageStartedAt !== undefined; this.refreshHeatmapLayout(); this.refreshContentTracking(true); this.refreshFormTracking(true); this.emitPlugin('navigation', { phase: 'cancel', url: globalThis.location?.href }); }
  pageReady(options: PageReadyOptions = {}): void { const newLifecycle = this.heatmapNavigating || this.currentPageStartedAt === undefined; this.heatmapNavigating = false; if (newLifecycle) { this.pageViewRecorded = false; this.trackPageView({ url: options.url }); this.refreshContentTracking(true); this.refreshFormTracking(true); this.refreshMediaTracking(true); } this.emitPlugin('navigation', { phase: 'ready', url: options.url ?? globalThis.location?.href }); if (!this.captureEnabled()) return; if (!newLifecycle && this.heatmapInstance) { this.refreshHeatmapLayout(); return; } this.stopRecorder(); this.heatmapInstance = uuid(); this.heatmapUrl = options.url ?? globalThis.location?.href ?? ''; this.heatmapLayoutVersion = options.layoutVersion ?? this.options.heatmap?.layoutVersion ?? 'unversioned'; this.heatmapSelected = !!this.heatmapConfig?.enabled && Math.random() * 100 < this.heatmapConfig.sampleRate; this.recordingSelected = !!this.heatmapConfig?.recordingEnabled && Math.random() * 100 < this.heatmapConfig.recordingSampleRate; this.moveCount = this.clickCount = this.dropped = 0; this.moveTruncated = this.clickTruncated = false; this.scrollBins.clear(); this.layoutSegments.clear(); if (this.heatmapSelected) { this.installHeatmapListeners(); this.captureStart(true); this.observeLayouts(); } if ((this.heatmapSelected && this.heatmapConfig?.autoSnapshotEnabled) || this.recordingSelected) void this.startRecorder(); }
  registerScrollContainer(options: ScrollContainerOptions): () => void { if (!options.id.trim() || this.containers.has(options.id)) return () => undefined; const listener = () => this.recordScroll(options.id); options.element.addEventListener('scroll', listener, { passive: true }); this.containers.set(options.id, { element: options.element, remove: () => options.element.removeEventListener('scroll', listener) }); this.resizeObserver?.observe(options.element); if (this.heatmapInstance && this.heatmapSelected) this.captureTargetStart(options.id, options.element, true); return () => { const entry = this.containers.get(options.id); entry?.remove(); this.resizeObserver?.unobserve(options.element); this.containers.delete(options.id); this.scrollBins.delete(options.id); this.lastScroll.delete(options.id); this.layoutSegments.delete(options.id); }; }
  refreshHeatmapLayout(): void { if (!this.heatmapInstance || !this.heatmapSelected) return; if (this.layoutTimer) clearTimeout(this.layoutTimer); this.layoutTimer = setTimeout(() => this.captureStart(), 200); }
  private collectionAllowed(): boolean { return !doNotTrack() && this.hasConsent(); }
  private activateCollectionListeners(): void {
    if (!this.collectionAllowed()) return;
    // Register metric listeners before unload flush listeners so final CLS/INP
    // callbacks can enqueue their sample while the page is still active.
    this.startWebVitals();
    this.installSiteSearchListener();
    this.installContentTracking();
    this.refreshContentTracking(true);
    this.installFormTracking();
    this.refreshFormTracking(true);
    this.installMediaTracking();
    this.refreshMediaTracking(true);
    this.installErrorTracking();
    if (this.options.trackDownloads !== false || this.options.trackOutlinks !== false)
      this.installBehaviourListener();
  }
  private consentKey(): string { return `seeray:${this.options.siteId}:consent`; }
  private persistIdentity(): void {
    if (this.identityPersisted) return;
    this.visitorId = storageId(globalThis.localStorage, `seeray:${this.options.siteId}:visitor_id`);
    this.sessionId = storageId(globalThis.sessionStorage, `seeray:${this.options.siteId}:session_id`);
    this.recordingId = storageId(globalThis.sessionStorage, `seeray:${this.options.siteId}:recording_id`);
    this.identityPersisted = true;
  }
  private useEphemeralIdentity(): void {
    this.visitorId = uuid();
    this.sessionId = uuid();
    this.recordingId = uuid();
    this.identityPersisted = false;
  }
  private removeStoredIdentity(): void {
    const prefix = `seeray:${this.options.siteId}:`;
    try {
      const localStorage = globalThis.localStorage;
      for (let index = (localStorage?.length ?? 0) - 1; index >= 0; index--) {
        const key = localStorage?.key(index);
        if (key?.startsWith(prefix) && key !== this.consentKey()) localStorage?.removeItem(key);
      }
      const sessionStorage = globalThis.sessionStorage;
      for (let index = (sessionStorage?.length ?? 0) - 1; index >= 0; index--) {
        const key = sessionStorage?.key(index);
        if (key?.startsWith(prefix)) sessionStorage?.removeItem(key);
      }
      localStorage?.removeItem?.(`seeray:${this.options.siteId}:visitor_id`);
      sessionStorage?.removeItem?.(`seeray:${this.options.siteId}:session_id`);
      sessionStorage?.removeItem?.(`seeray:${this.options.siteId}:recording_id`);
    } catch { /* Rejection must still stop this page when storage is unavailable. */ }
  }
  private installSiteSearchListener(): void {
    if (this.siteSearchListenerInstalled) return;
    this.siteSearchListenerInstalled = true;
    globalThis.document?.addEventListener?.('submit', event => {
      if (!this.collectionAllowed()) return;
      const candidate = event.target as (HTMLFormElement & Element) | null;
      const form = candidate?.tagName === 'FORM'
        ? candidate
        : candidate?.closest?.('form[data-seeray-search]') as HTMLFormElement | null;
      if (!form?.hasAttribute('data-seeray-search') || form.closest('[data-seeray-no-track]')) return;
      const input = form.querySelector<HTMLInputElement>(
        'input[data-seeray-search-term],input[type="search"],input[name="q"],input[name="query"],input[name="search"]',
      );
      if (!input) return;
      const rawResultsCount = form.getAttribute('data-seeray-search-results-count');
      const parsedResultsCount = rawResultsCount === null ? undefined : Number(rawResultsCount);
      this.trackSiteSearch(input.value, {
        category: form.getAttribute('data-seeray-search-category') ?? undefined,
        resultsCount: Number.isSafeInteger(parsedResultsCount) ? parsedResultsCount : undefined,
      });
    }, true);
  }

  private trackContentEvent(type: 'content_impression' | 'content_interaction', contentName: string, interaction: string, options: ContentTrackingOptions): void {
    const name = boundedText(contentName, 256);
    if (!name) return;
    const piece = boundedText(options.piece, 256);
    const target = contentTarget(options.target);
    const properties: Record<string, string> = { contentName: name };
    if (piece) properties.contentPiece = piece;
    if (target) properties.contentTarget = target;
    if (type === 'content_interaction') properties.interaction = interaction;
    this.track(type, {
      url: options.url,
      title: options.title,
      referrer: options.referrer,
      category: 'content',
      action: interaction,
      name,
      properties,
    });
  }

  private installContentTracking(): void {
    if (this.contentListenerInstalled) return;
    this.contentListenerInstalled = true;
    globalThis.document?.addEventListener?.('click', event => {
      if (!this.collectionAllowed()) return;
      const actionElement = event.target instanceof Element
        ? event.target.closest<HTMLElement>('[data-seeray-content-action]')
        : null;
      if (!actionElement || actionElement.closest('[data-seeray-no-track]')) return;
      const content = actionElement.closest<HTMLElement>('[data-seeray-content-name]');
      const name = content?.getAttribute('data-seeray-content-name');
      if (!content || !name) return;
      this.trackContentInteraction(name, {
        piece: content.getAttribute('data-seeray-content-piece') ?? undefined,
        target: content.getAttribute('data-seeray-content-target') || actionElement.getAttribute('href') || undefined,
        interaction: actionElement.getAttribute('data-seeray-content-action') ?? 'click',
      });
    }, { passive: true });
    globalThis.document?.addEventListener?.('DOMContentLoaded', () => this.refreshContentTracking(), { once: true });
  }

  refreshContentTracking(reset = false): void {
    const document = globalThis.document;
    if (!document || !this.collectionAllowed()) {
      if (!this.collectionAllowed()) this.contentObserver?.disconnect();
      return;
    }
    if (reset) {
      this.contentObserver?.disconnect();
      this.contentSeen = new WeakSet<Element>();
      this.contentObserved = new WeakSet<Element>();
    }
    const elements = document.querySelectorAll?.('[data-seeray-content-name]') as NodeListOf<HTMLElement> | undefined;
    if (!elements?.length) return;
    if (typeof IntersectionObserver === 'undefined') {
      elements.forEach(element => this.recordContentImpression(element));
      return;
    }
    if (!this.contentObserver) {
      this.contentObserver = new IntersectionObserver(entries => {
        for (const entry of entries) {
          const element = entry.target as HTMLElement;
          if (!entry.isIntersecting || entry.intersectionRatio < 0.1 || this.contentSeen.has(element)) continue;
          this.recordContentImpression(element);
        }
      }, { threshold: [0.1] });
    }
    elements.forEach(element => {
      if (this.contentObserved.has(element)) return;
      this.contentObserved.add(element);
      this.contentObserver?.observe(element);
    });
  }

  private recordContentImpression(element: HTMLElement): void {
    if (!this.collectionAllowed() || this.contentSeen.has(element)) return;
    const name = element.getAttribute('data-seeray-content-name');
    if (!name || element.closest('[data-seeray-no-track]')) return;
    this.contentSeen.add(element);
    this.trackContentImpression(name, {
      piece: element.getAttribute('data-seeray-content-piece') ?? undefined,
      target: element.getAttribute('data-seeray-content-target') ?? undefined,
    });
  }
  private async loadConfigured(): Promise<void> {
    if (!this.collectionAllowed()) return;
    if (this.options.tagManagerPreview) {
      await this.loadTagManager();
      return;
    }
    const tasks: Promise<void>[] = [];
    if (this.options.tagManager) tasks.push(this.loadTagManager());
    if (this.options.experiments) tasks.push(this.loadExperiments());
    if (this.options.heatmap?.enabled) tasks.push(this.loadHeatmapConfig());
    await Promise.all(tasks);
  }
  private async loadTagManager(): Promise<void> {
    if (!this.collectionAllowed()) return;
    try {
      if (this.options.tagManagerPreview) {
        if (!this.tagManagerPreviewEndpoint || !this.tagManagerPreviewToken) return;
        const response = await fetch(this.tagManagerPreviewEndpoint, {
          headers: { Authorization: `Bearer ${this.tagManagerPreviewToken}` },
        });
        if (!response.ok) return;
        const bundle = await response.json() as { tags?: unknown; executeCustomCode?: unknown };
        if (!Array.isArray(bundle.tags)) return;
        this.tagDefinitions = bundle.tags.filter((tag): tag is TagDefinition => !!tag && typeof tag === 'object').slice(0, 100);
        this.previewExecuteCustomCode = bundle.executeCustomCode === true;
        return;
      }
      const response = await fetch(this.tagManagerEndpoint);
      if (!response.ok) return;
      const tags = await response.json();
      if (Array.isArray(tags)) this.tagDefinitions = tags.filter((tag): tag is TagDefinition => !!tag && typeof tag === 'object').slice(0, 100);
    } catch { /* Tag execution is optional and must not affect ordinary tracking. */ }
  }
  private async loadExperiments(): Promise<void> { if (!this.collectionAllowed()) return; try { const response = await fetch(`${this.experimentsEndpoint}?visitorId=${encodeURIComponent(this.visitorId)}`, { cache: 'no-store' }); if (!response.ok) return; const definitions = await response.json(); if (!Array.isArray(definitions)) return; this.experimentDefinitions.clear(); for (const definition of definitions as ExperimentDefinition[]) { const name = text(definition.name); const variants = Array.isArray(definition.variants) ? definition.variants.filter((variant): variant is string => typeof variant === 'string' && !!variant.trim()) : []; if (!name || variants.length < 2) continue; const rawTargeting = isProperties(definition.targeting) ? definition.targeting : {}; const rawPaths = rawTargeting.pathPrefixes ?? []; const rawDevices = rawTargeting.deviceTypes ?? []; if (!Array.isArray(rawPaths) || !Array.isArray(rawDevices)) continue; const pathPrefixes = rawPaths.filter((path): path is string => typeof path === 'string' && path.startsWith('/') && !path.includes('?') && !path.includes('#') && path.length <= 512); const deviceTypes = rawDevices.filter((device): device is string => typeof device === 'string' && EXPERIMENT_DEVICE_TYPES.has(device)); if (pathPrefixes.length !== rawPaths.length || deviceTypes.length !== rawDevices.length || new Set(pathPrefixes).size !== pathPrefixes.length || new Set(deviceTypes).size !== deviceTypes.length) continue; const rawGroup = text(definition.allocationGroup)?.toLowerCase(); const allocationGroup = rawGroup && /^[a-z0-9][a-z0-9_-]{0,63}$/.test(rawGroup) ? rawGroup : undefined; this.experimentDefinitions.set(name, { variants, targeting: { pathPrefixes, deviceTypes }, allocationGroup }); } } catch { /* Experiment configuration is optional and must not affect ordinary tracking. */ } }
  private matchesExperimentLayer(name: string, group: string): boolean { const candidates = [...this.experimentDefinitions.entries()].filter(([, definition]) => definition.allocationGroup === group).map(([candidate]) => candidate).sort(); if (!candidates.length) return false; const key = `seeray:${this.options.siteId}:experiment-layer:${group}`; let assigned = this.experimentLayerAssignments.get(group); try { assigned = globalThis.localStorage?.getItem(key) ?? assigned; } catch { /* Keep the in-memory assignment when storage is unavailable. */ } if (!assigned || !candidates.includes(assigned)) { let hash = 0x811c9dc5; for (const character of `${this.visitorId}:${group}`) hash = Math.imul(hash ^ character.charCodeAt(0), 0x01000193); assigned = candidates[(hash >>> 0) % candidates.length]; this.experimentLayerAssignments.set(group, assigned); try { globalThis.localStorage?.setItem(key, assigned); } catch { /* Layer exclusivity remains effective for this page lifetime. */ } } else { this.experimentLayerAssignments.set(group, assigned); } return assigned === name; }
  private matchesExperimentTarget(targeting: ExperimentTargeting): boolean { if (targeting.pathPrefixes.length) { let pathname: string; try { pathname = new URL(globalThis.location?.href ?? '').pathname; } catch { return false; } if (!targeting.pathPrefixes.some(prefix => prefix === '/' || pathname === prefix || pathname.startsWith(prefix.endsWith('/') ? prefix : `${prefix}/`))) return false; } if (targeting.deviceTypes.length && !targeting.deviceTypes.includes(clientContext().deviceType)) return false; return true; }
  private fireTagTriggers(data: DataLayerEvent | TrackOptions): void {
    if (!this.collectionAllowed()) return;
    const event = typeof (data as DataLayerEvent).event === 'string' ? (data as DataLayerEvent).event : undefined;
    if (!event) return;
    if (this.options.tagManagerPreview) {
      this.firePreviewTagTriggers(event, data);
      return;
    }
    for (const tag of this.tagDefinitions) {
      const type = text(tag.type);
      if (type !== 'event' && type !== 'page_view' && type !== 'custom_html') continue;
      if (!this.tagMatches(tag, event, data)) continue;
      if (type === 'custom_html') { this.executeCustomHtml(tag); continue; }
      const eventType = text(tag.eventType) ?? text(tag.name);
      if (!eventType) continue;
      const properties = { ...(isProperties((data as DataLayerEvent).properties) ? (data as DataLayerEvent).properties : {}), ...this.resolveTagProperties(tag.properties, data) };
      this.track(eventType, { category: text(tag.category), action: text(tag.action), name: text(tag.name), properties: Object.keys(properties).length ? properties : undefined });
    }
  }
  private firePreviewTagTriggers(event: string, data: DataLayerEvent | TrackOptions): void {
    const logs: TagPreviewEvent[] = [];
    for (let tagIndex = 0; tagIndex < this.tagDefinitions.length; tagIndex++) {
      const tag = this.tagDefinitions[tagIndex];
      const type = text(tag.type);
      if (type !== 'event' && type !== 'page_view' && type !== 'custom_html') continue;
      const triggers = Array.isArray(tag.triggers) ? tag.triggers : [];
      const hasCustomJavaScript = triggers.some(trigger => !!trigger && typeof trigger === 'object' && text((trigger as { type?: unknown }).type) === 'custom_js');
      let matched = false;
      let blockedByCustomJavaScript = false;
      if (hasCustomJavaScript && !this.previewExecuteCustomCode) {
        const withoutCode = { ...tag, triggers: triggers.filter(trigger => !trigger || typeof trigger !== 'object' || text((trigger as { type?: unknown }).type) !== 'custom_js') };
        matched = this.tagMatches(withoutCode, event, data);
        blockedByCustomJavaScript = !matched;
      } else {
        matched = this.tagMatches(tag, event, data);
      }
      let outcome: TagPreviewEvent['outcome'];
      if (blockedByCustomJavaScript) {
        outcome = 'blocked';
      } else if (!matched) {
        outcome = 'no_match';
      } else if (type === 'custom_html' && !this.previewExecuteCustomCode) {
        outcome = 'blocked';
      } else {
        if (type === 'custom_html') this.executeCustomHtml(tag);
        outcome = 'fired';
      }
      logs.push({ tagIndex, triggerEvent: event.slice(0, 64), outcome, pagePath: this.previewPagePath(data) });
    }
    if (logs.length) void this.recordPreviewEvents(logs);
  }
  private previewPagePath(data: DataLayerEvent | TrackOptions): string {
    try {
      const rawUrl = (data as TrackOptions).url ?? globalThis.location?.href ?? '/';
      return new URL(rawUrl, globalThis.location?.href).pathname.slice(0, 512) || '/';
    } catch {
      return '/';
    }
  }
  private async recordPreviewEvents(events: TagPreviewEvent[]): Promise<void> {
    if (!this.tagManagerPreviewEventsEndpoint || !this.tagManagerPreviewToken) return;
    try {
      await fetch(this.tagManagerPreviewEventsEndpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.tagManagerPreviewToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(events),
      });
    } catch { /* Debug logging must never disrupt the site under test. */ }
  }
  private resolveTagProperties(value: unknown, data: DataLayerEvent | TrackOptions): Record<string, unknown> {
    if (!isProperties(value)) return {};
    const properties: Record<string, unknown> = {};
    for (const [key, configuredValue] of Object.entries(value)) {
      if (typeof configuredValue !== 'string') { properties[key] = configuredValue; continue; }
      properties[key] = configuredValue.replace(/\{\{\s*([^{}]+?)\s*\}\}/g, (token, variable: string) => {
        const resolved = this.resolveTagVariable(variable.trim(), data);
        return resolved === undefined ? token : this.variableText(resolved);
      });
    }
    return properties;
  }
  private resolveTagVariable(name: string, data: DataLayerEvent | TrackOptions): unknown {
    const event = data as DataLayerEvent;
    const context = clientContext();
    const known: Record<string, unknown> = {
      'Page URL': event.url ?? globalThis.location?.href,
      'Page Title': event.title ?? globalThis.document?.title,
      Referrer: event.referrer ?? globalThis.document?.referrer,
      Event: event.event,
      'Event Name': event.eventName ?? event.name,
      'Event Category': event.eventCategory ?? event.category,
      'Event Action': event.eventAction ?? event.action,
      Browser: context.browser,
      'Operating System': context.operatingSystem,
      'Device Type': context.deviceType,
      Language: context.language,
      'Screen Width': context.screenWidth,
      'Screen Height': context.screenHeight,
      'Viewport Width': context.viewportWidth,
      'Viewport Height': context.viewportHeight,
    };
    if (Object.prototype.hasOwnProperty.call(known, name)) return known[name];
    const propertyMatch = /^Event Property:\s*(.+)$/.exec(name);
    const eventProperties = isProperties(event.properties) ? event.properties : undefined;
    if (propertyMatch && eventProperties && Object.prototype.hasOwnProperty.call(eventProperties, propertyMatch[1])) return eventProperties[propertyMatch[1]];
    return undefined;
  }
  private variableText(value: unknown): string {
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    try { return JSON.stringify(value) ?? ''; } catch { return ''; }
  }
  private tagMatches(tag: TagDefinition, event: string, data: DataLayerEvent | TrackOptions): boolean {
    const triggers = Array.isArray(tag.triggers) ? tag.triggers : [];
    if (triggers.length) return triggers.some(trigger => this.triggerMatches(trigger, event, data));
    const type = text(tag.type);
    const trigger = typeof tag.trigger === 'string' ? tag.trigger : tag.trigger && typeof tag.trigger === 'object' && typeof (tag.trigger as { event?: unknown }).event === 'string' ? (tag.trigger as { event: string }).event : type === 'page_view' ? 'page_view' : text(tag.name);
    return trigger === event;
  }
  private triggerMatches(trigger: unknown, event: string, data: DataLayerEvent | TrackOptions): boolean {
    if (typeof trigger === 'string') return trigger.trim() === event;
    if (!trigger || typeof trigger !== 'object') return false;
    const value = trigger as { type?: unknown; event?: unknown; functionName?: unknown; code?: unknown; conditions?: unknown };
    if (text(value.type) === 'custom_js') return this.runCustomTrigger(value, data);
    return text(value.event) === event && this.eventConditionsMatch(value.conditions, data);
  }
  private eventConditionsMatch(conditions: unknown, data: DataLayerEvent | TrackOptions): boolean {
    if (conditions === undefined || conditions === null) return true;
    if (!Array.isArray(conditions) || conditions.length > 20) return false;
    const eventProperties = (data as DataLayerEvent).properties;
    const properties = isProperties(eventProperties) ? eventProperties : {};
    return conditions.every(condition => {
      if (!isProperties(condition)) return false;
      const property = text(condition.property);
      const operator = text(condition.operator);
      if (!property || !operator) return false;
      const exists = Object.prototype.hasOwnProperty.call(properties, property) && properties[property] !== undefined && properties[property] !== null;
      if (operator === 'exists') return exists;
      if (!exists || typeof condition.value !== 'string') return false;
      const actual = properties[property];
      const actualText = typeof actual === 'string' ? actual : typeof actual === 'number' || typeof actual === 'boolean' ? String(actual) : undefined;
      if (actualText === undefined) return false;
      switch (operator) {
        case 'equals': return actualText === condition.value;
        case 'not_equals': return actualText !== condition.value;
        case 'contains': return actualText.includes(condition.value);
        case 'starts_with': return actualText.startsWith(condition.value);
        case 'ends_with': return actualText.endsWith(condition.value);
        default: return false;
      }
    });
  }
  private runCustomTrigger(trigger: { functionName?: unknown; code?: unknown }, data: DataLayerEvent | TrackOptions): boolean {
    const functionName = text(trigger.functionName);
    if (!functionName) return false;
    const host = globalThis as unknown as Record<string, unknown>;
    let candidate = host[functionName];
    if (typeof candidate !== 'function' && text(trigger.code)) {
      try {
        candidate = Function(`return (${text(trigger.code)});`)();
        if (typeof candidate === 'function') host[functionName] = candidate;
      } catch {
        return false;
      }
    }
    if (typeof candidate !== 'function') return false;
    try {
      const context = { siteId: this.options.siteId, url: (data as TrackOptions).url ?? globalThis.location?.href, title: (data as TrackOptions).title ?? globalThis.document?.title };
      return (candidate as (event: DataLayerEvent | TrackOptions, context: Record<string, unknown>) => unknown)(data, context) === true;
    } catch {
      return false;
    }
  }
  private executeCustomHtml(tag: TagDefinition): void {
    const code = text(tag.code);
    const document = globalThis.document;
    if (!code || !document) return;
    try {
      const target = document.head ?? document.body ?? document.documentElement;
      if (!target) return;
      if (!/^\s*<(?:[a-z][\w:-]*|!doctype|!--|\/)/i.test(code)) {
        const script = document.createElement('script');
        script.type = 'text/javascript';
        script.textContent = code;
        target.appendChild(script);
        return;
      }
      const template = document.createElement('template');
      template.innerHTML = code;
      const nodes = [...template.content.childNodes];
      for (const node of nodes) {
        if (node.nodeType === 1 && (node as Element).tagName.toLowerCase() === 'script') {
          const source = node as HTMLScriptElement;
          const script = document.createElement('script');
          for (const attribute of [...source.attributes]) script.setAttribute(attribute.name, attribute.value);
          script.textContent = source.textContent ?? '';
          target.appendChild(script);
        } else {
          target.appendChild(node.cloneNode(true));
        }
      }
    } catch {
      // A CSP or malformed snippet must not disable ordinary analytics.
    }
  }
  private startWebVitals(): void {
    if (!this.options.webVitals || this.webVitalsStarted || !this.collectionAllowed()
      || !globalThis.document || typeof globalThis.PerformanceObserver === 'undefined') return;
    this.webVitalsStarted = true;
    const record = (metric: Metric): void => this.recordWebVital(metric);
    onCLS(record);
    onINP(record);
    onLCP(record);
  }
  private recordWebVital(metric: Metric): void {
    const supportedMetric = metric.name === 'LCP' || metric.name === 'INP' || metric.name === 'CLS';
    if (!this.options.webVitals || !this.collectionAllowed() || !supportedMetric
      || typeof metric.id !== 'string' || metric.id.length < 1 || metric.id.length > 128
      || !Number.isFinite(metric.value) || metric.value < 0) return;
    this.track('web_vital', {
      category: 'performance',
      action: metric.name,
      name: metric.name,
      properties: {
        metric: metric.name,
        metricId: metric.id,
        value: Math.min(metric.value, 1_000_000_000),
      },
    });
    // Final CLS/INP values are commonly emitted as the page becomes hidden.
    // Send that just-created sample immediately because timers may be suspended.
    if (globalThis.document?.visibilityState === 'hidden') void this.flush(true);
  }
  private heatmapEnabled(): boolean { return !!this.heatmapConfig?.enabled && this.heatmapConfig.sampleRate > 0 && this.collectionAllowed(); }
  private captureEnabled(): boolean { return (this.heatmapEnabled() || !!this.heatmapConfig?.recordingEnabled && this.heatmapConfig.recordingSampleRate > 0) && this.collectionAllowed(); }
  private async loadHeatmapConfig(): Promise<void> { if (!this.collectionAllowed()) return; try { const response = await fetch(this.heatmapConfigEndpoint); if (!response.ok) return; const config = await response.json() as Partial<HeatmapConfig>; const configuredRate = rate(config.sampleRate); const clientRate = this.options.heatmap?.sampleRate; this.heatmapConfig = { enabled: config.enabled === true, sampleRate: clientRate === undefined ? configuredRate : Math.min(configuredRate, rate(clientRate)), version: config.version, autoSnapshotEnabled: config.autoSnapshotEnabled !== false, recordingEnabled: config.recordingEnabled === true, recordingSampleRate: rate(config.recordingSampleRate ?? 1) }; if (this.options.heatmap?.navigationMode !== 'manual') this.installHistory(); this.pageReady(); } catch { /* Capture failure never disables ordinary tracking. */ } }
  private startPageOverlay(apiBase?: string): void {
    const location = globalThis.location;
    if (!location || !globalThis.document) return;
    let url: URL;
    try { url = new URL(location.href); } catch { return; }
    const fragment = new URLSearchParams(url.hash.slice(1));
    let sessionId = url.searchParams.get('__seeray_overlay_session') ?? fragment.get('__seeray_overlay_session');
    let token = url.searchParams.get('__seeray_overlay_token') ?? fragment.get('__seeray_overlay_token');
    const storageKey = `seeray:${this.options.siteId}:page_overlay`;
    if (sessionId || token) {
      url.searchParams.delete('__seeray_overlay_session');
      url.searchParams.delete('__seeray_overlay_token');
      fragment.delete('__seeray_overlay_session');
      fragment.delete('__seeray_overlay_token');
      const remainingFragment = fragment.toString();
      url.hash = remainingFragment ? `#${remainingFragment}` : '';
      try { globalThis.history?.replaceState(globalThis.history.state, '', `${url.pathname}${url.search}${url.hash}`); } catch { /* Some embedded browsers deny URL cleanup; the capability expires shortly. */ }
      if (sessionId && token) {
        try { globalThis.sessionStorage?.setItem(storageKey, JSON.stringify({ sessionId, token })); } catch { /* The one-page link still works if session storage is unavailable. */ }
      }
    } else {
      try {
        const saved = globalThis.sessionStorage?.getItem(storageKey);
        if (saved) ({ sessionId, token } = JSON.parse(saved) as { sessionId: string; token: string });
      } catch { /* Continue without a saved overlay capability. */ }
    }
    if (!sessionId && !token) return;
    if (!sessionId || !token || sessionId.length > 64 || token.length > 128) return;
    const endpoint = absoluteApiUrl(`/api/v1/page-overlay/${encodeURIComponent(this.options.siteId)}/${encodeURIComponent(sessionId)}`, apiBase);
    void fetch(endpoint, { headers: { Authorization: `Bearer ${token}` }, credentials: 'omit' })
      .then(async response => {
        if (!response.ok) throw new Error('The page overlay session is unavailable or expired.');
        const data = await response.json() as { sourcePath?: unknown; from?: unknown; to?: unknown; targets?: unknown };
        if (typeof data.sourcePath !== 'string' || !Array.isArray(data.targets)) throw new Error('The page overlay response is invalid.');
        const targets = data.targets.filter((target): target is { sourcePath: string; path: string; sessions: number } =>
          !!target && typeof target === 'object' && typeof (target as { sourcePath?: unknown }).sourcePath === 'string'
          && typeof (target as { path?: unknown }).path === 'string'
          && Number.isFinite((target as { sessions?: unknown }).sessions) && Number((target as { sessions: number }).sessions) > 0);
        this.pageOverlayData = {
          storageKey,
          sourcePath: data.sourcePath,
          from: typeof data.from === 'string' ? data.from : '',
          to: typeof data.to === 'string' ? data.to : '',
          targets,
        };
        this.installPageOverlayNavigation();
        this.refreshPageOverlay();
      })
      .catch(error => {
        try { globalThis.sessionStorage?.removeItem(storageKey); } catch { /* Storage may be blocked. */ }
        this.renderPageOverlayError(error instanceof Error ? error.message : 'Could not load page overlay data.');
      });
  }
  private installPageOverlayNavigation(): void {
    if (this.pageOverlayNavigationInstalled || !globalThis.history) return;
    this.pageOverlayNavigationInstalled = true;
    const history = globalThis.history;
    const wrap = (name: 'pushState' | 'replaceState'): void => {
      const original = history[name];
      history[name] = ((...args: Parameters<History['pushState']>) => {
        const before = globalThis.location?.href;
        const result = original.apply(history, args);
        if (before !== globalThis.location?.href) setTimeout(() => this.refreshPageOverlay(), 0);
        return result;
      }) as History[typeof name];
    };
    wrap('pushState');
    wrap('replaceState');
    globalThis.addEventListener?.('popstate', () => this.refreshPageOverlay());
  }
  private refreshPageOverlay(): void {
    const data = this.pageOverlayData;
    if (data) this.renderPageOverlay(data.storageKey, data.sourcePath, data.from, data.to, data.targets);
  }
  private renderPageOverlay(storageKey: string, sourcePath: string, from: string, to: string, targets: Array<{ sourcePath: string; path: string; sessions: number }>): void {
    const document = globalThis.document;
    if (!document?.body) return;
    const previous = document.getElementById('seeray-page-overlay') as (HTMLElement & { __seerayDispose?: () => void }) | null;
    previous?.__seerayDispose?.();
    previous?.remove();
    const root = document.createElement('div');
    root.id = 'seeray-page-overlay';
    root.setAttribute('data-seeray-no-track', '');
    root.setAttribute('aria-label', 'SeeRay page overlay');
    root.style.cssText = 'position:fixed;inset:0;z-index:2147483646;pointer-events:none;font:14px/1.4 system-ui,-apple-system,sans-serif;color:#172033;';
    const panel = document.createElement('section');
    panel.style.cssText = 'position:fixed;right:16px;top:16px;width:min(340px,calc(100vw - 32px));max-height:calc(100vh - 32px);overflow:auto;padding:16px;border-radius:12px;background:#fff;box-shadow:0 8px 32px #07142940;border:1px solid #d5dfeb;pointer-events:auto;';
    const heading = document.createElement('div');
    heading.style.cssText = 'display:flex;align-items:center;gap:8px;font-weight:700;font-size:16px;';
    const title = document.createElement('span');
    title.textContent = 'SeeRay page overlay';
    title.style.flex = '1';
    const close = document.createElement('button');
    close.type = 'button'; close.textContent = '×'; close.setAttribute('aria-label', 'Close page overlay');
    close.style.cssText = 'border:0;background:transparent;font-size:22px;cursor:pointer;color:#42536b;';
    close.addEventListener('click', () => {
      root.remove();
      this.pageOverlayData = undefined;
      try { globalThis.sessionStorage?.removeItem(storageKey); } catch { /* Storage may be blocked. */ }
    });
    heading.append(title, close);
    panel.append(heading);
    const description = document.createElement('p');
    description.style.cssText = 'margin:8px 0;color:#53647a;font-size:12px;';
    description.textContent = `Next-page sessions · ${from || 'selected range'} to ${to || 'selected range'}`;
    panel.append(description);
    const currentPath = globalThis.location?.pathname ?? '';
    const pageTargets = targets.filter(target => target.sourcePath === currentPath);
    const rows = document.createElement('div');
    if (!pageTargets.length) {
      const note = document.createElement('p');
      note.textContent = currentPath === sourcePath
        ? 'No next-page transitions were recorded for this page in the selected range.'
        : `No next-page transitions were recorded for ${currentPath || 'this page'} in the selected range.`;
      note.style.color = '#53647a'; rows.append(note);
    } else {
      const summary = document.createElement('p'); summary.style.cssText = 'margin:6px 0 10px;font-weight:600;';
      summary.textContent = `${currentPath} · ${pageTargets.reduce((sum, target) => sum + target.sessions, 0).toLocaleString()} measured next-page transitions`;
      rows.append(summary);
      for (const target of pageTargets.slice(0, 100)) {
        const row = document.createElement('div');
        row.style.cssText = 'display:flex;justify-content:space-between;gap:12px;padding:5px 0;border-top:1px solid #edf1f5;';
        const path = document.createElement('span'); path.textContent = target.path; path.style.cssText = 'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
        const count = document.createElement('strong'); count.textContent = target.sessions.toLocaleString();
        row.append(path, count); rows.append(row);
      }
    }
    panel.append(rows); root.append(panel); document.body.append(root);
    if (!pageTargets.length) return;
    const counts = new Map(pageTargets.map(target => [target.path, target.sessions]));
    const bubbles = new Set<HTMLElement>();
    const refresh = (): void => {
      for (const bubble of bubbles) bubble.remove();
      bubbles.clear();
      for (const anchor of Array.from(document.querySelectorAll('a[href]'))) {
        if (anchor.closest('#seeray-page-overlay,[data-seeray-no-track]')) continue;
        let link: URL;
        try { link = new URL((anchor as HTMLAnchorElement).href, globalThis.location?.href); } catch { continue; }
        if (link.origin !== globalThis.location?.origin) continue;
        const count = counts.get(link.pathname);
        if (!count) continue;
        const rect = anchor.getBoundingClientRect();
        if (!rect.width || !rect.height) continue;
        const bubble = document.createElement('span');
        bubble.textContent = count.toLocaleString();
        bubble.setAttribute('aria-hidden', 'true');
        bubble.style.cssText = `position:absolute;left:${Math.round(rect.left + (globalThis.scrollX ?? 0) + rect.width / 2)}px;top:${Math.round(rect.top + (globalThis.scrollY ?? 0) - 12)}px;transform:translate(-50%,-100%);padding:3px 8px;border-radius:999px;background:#f04438;color:white;border:2px solid white;box-shadow:0 2px 8px #0004;font:700 12px/1.2 system-ui,sans-serif;white-space:nowrap;`;
        root.append(bubble); bubbles.add(bubble);
      }
    };
    refresh();
    globalThis.addEventListener?.('scroll', refresh, { passive: true });
    globalThis.addEventListener?.('resize', refresh, { passive: true });
    const observer = typeof MutationObserver === 'undefined' ? undefined : new MutationObserver(records => {
      if (records.some(record => !root.contains(record.target))) refresh();
    });
    observer?.observe(document.body, { childList: true, subtree: true });
    const dispose = (): void => {
      globalThis.removeEventListener?.('scroll', refresh);
      globalThis.removeEventListener?.('resize', refresh);
      observer?.disconnect();
    };
    (root as HTMLElement & { __seerayDispose?: () => void }).__seerayDispose = dispose;
    close.addEventListener('click', dispose);
  }
  private renderPageOverlayError(message: string): void {
    const document = globalThis.document;
    if (!document?.body) return;
    const root = document.createElement('div'); root.id = 'seeray-page-overlay';
    root.style.cssText = 'position:fixed;right:16px;top:16px;z-index:2147483646;max-width:360px;padding:14px 18px;border-radius:10px;background:#fff5f2;color:#8a2c0d;box-shadow:0 8px 32px #07142940;font:14px/1.4 system-ui,sans-serif;';
    root.textContent = `SeeRay page overlay: ${message}`; document.body.append(root);
  }
  private async startRecorder(forceSnapshot = false): Promise<void> { if (!this.heatmapInstance || this.recorderStop || !this.collectionAllowed()) return; try { const geometry = this.geometry('page'); const identity = { type: 'start' as const, ...this.identity(geometry) }; let captureSnapshot = forceSnapshot || !!this.heatmapConfig?.autoSnapshotEnabled && this.heatmapSelected; if (captureSnapshot && !forceSnapshot) { const plan = await fetch(this.snapshotPlanEndpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(identity) }); if (plan.ok) captureSnapshot = (await plan.json() as { captureRequired?: boolean }).captureRequired === true; else captureSnapshot = false; } if (!captureSnapshot && !this.recordingSelected) return; const module = await import(/* @vite-ignore */ this.recorderEndpoint) as RecorderModule; if (!this.heatmapInstance || this.recorderStop || this.heatmapNavigating || !this.collectionAllowed()) return; this.recorderStop = module.startCapture({ siteId: this.options.siteId, snapshotEndpoint: this.snapshotEndpoint, recordingEndpoint: this.recordingEndpoint, identity, captureSnapshot, captureRecording: this.recordingSelected, recordingId: this.recordingId }); } catch { /* Optional recorder failure must not affect analytics. */ } }
  private stopRecorder(): void { const stop = this.recorderStop; this.recorderStop = undefined; stop?.(); }
  captureHeatmapSnapshot(): void { if (!this.captureEnabled()) return; this.stopRecorder(); void this.startRecorder(true); }
  private installHistory(): void { if (this.historyInstalled || !globalThis.history) return; this.historyInstalled = true; const wrap = (name: 'pushState' | 'replaceState') => { const original = globalThis.history[name]; globalThis.history[name] = ((...args: Parameters<History['pushState']>) => { const before = globalThis.location?.href; const result = original.apply(globalThis.history, args); if (before !== globalThis.location?.href) this.autoNavigation(); return result; }) as History['pushState']; }; wrap('pushState'); wrap('replaceState'); globalThis.addEventListener?.('popstate', () => this.autoNavigation()); globalThis.addEventListener?.('pageshow', event => { if ((event as PageTransitionEvent).persisted) { this.beginNavigation(); this.pageReady(); } }); }
  private autoNavigation(): void { this.beginNavigation(); const serial = ++this.navigationSerial; let stable = Date.now(); let previous = this.layoutKey(); const wait = () => { if (serial !== this.navigationSerial) return; const current = this.layoutKey(); if (current !== previous) stable = Date.now(); previous = current; if (Date.now() - stable >= 200) this.pageReady(); else if (Date.now() - stable < 2000) setTimeout(wait, 50); }; setTimeout(wait, 50); }
  private installBehaviourListener(): void { if (this.behaviourListenerInstalled) return; this.behaviourListenerInstalled = true; globalThis.document?.addEventListener('click', event => { if (!this.collectionAllowed()) return; const link = event.target instanceof Element ? event.target.closest('a[href]') as HTMLAnchorElement | null : null; if (!link || link.closest('[data-seeray-no-track]')) return; let url: URL; try { url = new URL(link.href, globalThis.location?.href); } catch { return; } if (!(url.protocol === 'http:' || url.protocol === 'https:')) return; const download = /\.(?:7z|avi|csv|docx?|epub|gz|ics|jpe?g|mp[34]|odp|ods|odt|pdf|png|pptx?|rar|tar|txt|webp|xlsx?|zip)$/i.test(url.pathname); if (download && this.options.trackDownloads !== false) this.track('download', { name: url.pathname, properties: { url: url.href } }); else if (!download && url.host !== globalThis.location?.host && this.options.trackOutlinks !== false) this.track('outlink', { name: url.hostname, properties: { url: url.href } }); }, { passive: true }); }
  private installHeatmapListeners(): void { if (this.listenersInstalled) return; this.listenersInstalled = true; globalThis.document?.addEventListener('click', event => this.capturePoint('click', event as MouseEvent), { passive: true }); globalThis.document?.addEventListener('pointermove', event => { const pointer = event as PointerEvent; if (pointer.pointerType === 'mouse') this.capturePoint('move', pointer); }, { passive: true }); globalThis.addEventListener?.('scroll', () => this.recordScroll('page'), { passive: true }); globalThis.addEventListener?.('resize', () => this.refreshHeatmapLayout(), { passive: true }); }
  private capturePoint(type: 'click' | 'move', event: MouseEvent): void { if (!this.collectionAllowed() || !this.heatmapInstance || !this.heatmapSelected || this.heatmapNavigating || ignored(event.target) || fixed(event.target)) return; if (type === 'move') { if (Date.now() - this.lastMove < 100 || this.moveCount >= 1000) { if (this.moveCount >= 1000) this.moveTruncated = true; return; } this.lastMove = Date.now(); this.moveCount++; } else { if (this.clickCount >= 500) { this.clickTruncated = true; return; } this.clickCount++; } const container = this.containerFor(event.target); if (!container && this.inUnregisteredScrollable(event.target)) return; const geometry = this.geometry(container?.[0] ?? 'page', container?.[1]); const x = container ? event.clientX - container[1].getBoundingClientRect().left - container[1].clientLeft + container[1].scrollLeft : event.clientX + (globalThis.scrollX ?? 0); const y = container ? event.clientY - container[1].getBoundingClientRect().top - container[1].clientTop + container[1].scrollTop : event.clientY + (globalThis.scrollY ?? 0); if (x < 0 || y < 0 || x > geometry.contentWidth || y > geometry.contentHeight) return; this.enqueueHeatmap({ type, ...this.identity(geometry), x: Math.round(x), y: Math.round(y) }); }
  private recordScroll(targetId: string): void { if (!this.collectionAllowed() || !this.heatmapInstance || !this.heatmapSelected || this.heatmapNavigating || Date.now() - (this.lastScroll.get(targetId) ?? 0) < 250) return; this.lastScroll.set(targetId, Date.now()); const element = targetId === 'page' ? undefined : this.containers.get(targetId)?.element; if (element && !this.pageVisible(element)) return; const g = this.geometry(targetId, element); const top = targetId === 'page' ? globalThis.scrollY ?? 0 : element!.scrollTop; const visible = targetId === 'page' ? globalThis.innerHeight ?? 0 : element!.clientHeight; const bins = this.scrollBins.get(targetId) ?? new Set<number>(); const first = Math.max(0, Math.floor((top / Math.max(1, g.contentHeight)) * 100)); const last = Math.min(99, Math.floor(((top + visible - 1) / Math.max(1, g.contentHeight)) * 100)); for (let i = first; i <= last; i++) bins.add(i); this.scrollBins.set(targetId, bins); this.enqueueHeatmap({ type: 'scroll', ...this.identity(g), scrollBins: [...bins] }); }
  private observeLayouts(): void { if (this.resizeObserver || typeof ResizeObserver === 'undefined') return; this.resizeObserver = new ResizeObserver(() => this.refreshHeatmapLayout()); if (globalThis.document?.documentElement) this.resizeObserver.observe(globalThis.document.documentElement); if (globalThis.document?.body) this.resizeObserver.observe(globalThis.document.body); for (const entry of this.containers.values()) this.resizeObserver.observe(entry.element); }
  private captureStart(force = false): void { if (this.heatmapNavigating) return; this.captureTargetStart('page', undefined, force); for (const [id, entry] of this.containers) this.captureTargetStart(id, entry.element, force); }
  private captureTargetStart(targetId: string, element?: HTMLElement, force = false): void { const geometry = this.geometry(targetId, element); const segment = `${geometry.viewportWidth}x${geometry.viewportHeight}:${geometry.contentWidth}x${geometry.contentHeight}`; if (!force && this.layoutSegments.get(targetId) === segment) return; this.layoutSegments.set(targetId, segment); this.scrollBins.delete(targetId); this.lastScroll.delete(targetId); this.enqueueHeatmap({ type: 'start', ...this.identity(geometry) }); this.recordScroll(targetId); }
  private identity(g: ReturnType<Tracker['geometry']>) { return { instanceId: this.heatmapInstance!, url: this.heatmapUrl, layoutVersion: this.heatmapLayoutVersion, ...g, truncated: this.moveTruncated || this.clickTruncated, dropped: this.dropped }; }
  private geometry(targetId: string, element?: HTMLElement) { return { targetId, viewportWidth: Math.round(element?.clientWidth ?? globalThis.innerWidth ?? 0), viewportHeight: Math.round(element?.clientHeight ?? globalThis.innerHeight ?? 0), contentWidth: Math.round(element?.scrollWidth ?? globalThis.document?.documentElement?.scrollWidth ?? 0), contentHeight: Math.round(element?.scrollHeight ?? globalThis.document?.documentElement?.scrollHeight ?? 0) }; }
  private layoutKey(): string { const g = this.geometry('page'); return `${globalThis.location?.href}|${g.viewportWidth}x${g.viewportHeight}|${g.contentWidth}x${g.contentHeight}`; }
  private containerFor(target: EventTarget | null): [string, HTMLElement] | undefined { for (const [id, entry] of this.containers) if (target instanceof Node && entry.element.contains(target)) return [id, entry.element]; return undefined; }
  private inUnregisteredScrollable(target: EventTarget | null): boolean { for (let e = target instanceof Element ? target.parentElement : null; e; e = e.parentElement) { const s = globalThis.getComputedStyle?.(e); if ((s?.overflowY === 'auto' || s?.overflowY === 'scroll') && e.scrollHeight > e.clientHeight) return true; } return false; }
  private pageVisible(element: HTMLElement): boolean { const r = element.getBoundingClientRect(); return r.bottom > 0 && r.top < (globalThis.innerHeight ?? 0); }
  private enqueueHeatmap(event: HeatmapEvent): void { const size = JSON.stringify(event).length; while (this.heatmapQueue.length && this.heatmapQueue.reduce((sum, value) => sum + JSON.stringify(value).length, size) > 256 * 1024) { this.heatmapQueue.shift(); this.dropped++; } this.heatmapQueue.push(event); if (this.heatmapQueue.length >= 20) void this.flushHeatmap(); else if (!this.heatmapTimer) this.heatmapTimer = setTimeout(() => void this.flushHeatmap(), 2000); }
  private async flushHeatmap(unload = false): Promise<void> { if (this.heatmapTimer) clearTimeout(this.heatmapTimer); this.heatmapTimer = undefined; if (this.heatmapFlushInFlight || !this.collectionAllowed()) return; const batch = this.heatmapRetry ?? this.nextHeatmapBatch(); if (!batch) return; this.heatmapFlushInFlight = true; const body = JSON.stringify({ schemaVersion: 1, siteId: this.options.siteId, clientBatchId: batch.clientBatchId, events: batch.events }); const endpoint = this.heatmapEndpoint; if (unload && globalThis.navigator?.sendBeacon && globalThis.navigator.sendBeacon(endpoint, new Blob([body], { type: 'application/json'}))) { this.heatmapRetry = undefined; this.heatmapFlushInFlight = false; return; } try { const response = await fetch(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, keepalive: unload }); if (!response.ok && response.status < 500 && response.status !== 429) { this.heatmapRetry = undefined; return; } if (!response.ok) throw new Error('collector unavailable'); this.heatmapRetry = undefined; } catch { this.heatmapRetry = batch; if (!unload) this.heatmapTimer = setTimeout(() => void this.flushHeatmap(), 1000 + Math.random() * 1000); } finally { this.heatmapFlushInFlight = false; if (!unload && this.heatmapQueue.length && !this.heatmapRetry && !this.heatmapTimer) this.heatmapTimer = setTimeout(() => void this.flushHeatmap(), 0); } }
  private nextHeatmapBatch(): HeatmapBatch | undefined { if (!this.heatmapQueue.length) return undefined; const events: HeatmapEvent[] = []; while (this.heatmapQueue.length) { const event = this.heatmapQueue[0]; const candidate = JSON.stringify({ schemaVersion: 1, siteId: this.options.siteId, clientBatchId: '00000000-0000-4000-8000-000000000000', events: [...events, event] }); if (candidate.length > 48 * 1024) break; events.push(this.heatmapQueue.shift()!); } if (!events.length) { this.heatmapQueue.shift(); this.dropped++; return this.nextHeatmapBatch(); } return { clientBatchId: uuid(), events }; }
  private schedule(): void { if (!this.timer) this.timer = setTimeout(() => void this.flush(), this.flushInterval); }
}

export interface DataLayerEvent extends TrackOptions { event: string; eventCategory?: string; eventAction?: string; eventName?: string; }
const trackers = new Map<string, Tracker>();
export const SeeRay = {
  init(options: TrackerOptions): Tracker {
    const old = trackers.get(options.siteId);
    if (old) return old;
    const tracker = new Tracker(options);
    trackers.set(options.siteId, tracker);
    return tracker;
  },
  use(plugin: TrackerPlugin): () => void {
    const removers = [...trackers.values()].map(tracker => tracker.use(plugin));
    return () => removers.forEach(remove => remove());
  },
  ready(): Promise<void> { return Promise.all([...trackers.values()].map(t => t.ready())).then(() => undefined); },
  trackPageView(options?: TrackOptions): void { trackers.forEach(t => t.trackPageView(options)); },
  setUserId(userId: string | null, siteId?: string): void { if (siteId) trackers.get(siteId)?.setUserId(userId); else trackers.forEach(t => t.setUserId(userId)); },
  track(type: string, options?: TrackOptions): void { trackers.forEach(t => t.track(type, options)); },
  push(data: DataLayerEvent): void { if (!data || !data.event) return; trackers.forEach(t => t.push(data)); },
  assignExperiment(experiment: string, variations?: string[]): string | undefined { return [...trackers.values()][0]?.assignExperiment(experiment, variations); },
  trackExperiment(experiment: string, variation: string): void { if (experiment.trim() && variation.trim()) trackers.forEach(t => t.track('experiment_exposure', { category: 'experiment', action: experiment.trim(), name: variation.trim() })); },
  trackGoal(name: string, options?: Omit<TrackOptions, 'name'>): void { trackers.forEach(t => t.trackGoal(name, options)); },
  trackSiteSearch(keyword: string, options?: SiteSearchOptions): void { trackers.forEach(t => t.trackSiteSearch(keyword, options)); },
  trackContentImpression(name: string, options?: ContentTrackingOptions): void { trackers.forEach(t => t.trackContentImpression(name, options)); },
  trackContentInteraction(name: string, options?: ContentTrackingOptions): void { trackers.forEach(t => t.trackContentInteraction(name, options)); },
  trackFormResult(formId: string, successful: boolean): void { trackers.forEach(t => t.trackFormResult(formId, successful)); },
  refreshContentTracking(): void { trackers.forEach(t => t.refreshContentTracking()); },
  refreshFormTracking(): void { trackers.forEach(t => t.refreshFormTracking()); },
  getConsentState(siteId?: string): 'granted' | 'denied' | 'unknown' {
    if (siteId) return trackers.get(siteId)?.getConsentState() ?? 'unknown';
    const states = [...trackers.values()].map(t => t.getConsentState());
    if (states.includes('denied')) return 'denied';
    return states.length && states.every(state => state === 'granted') ? 'granted' : 'unknown';
  },
  setConsent(granted: boolean, siteId?: string): void {
    if (siteId) trackers.get(siteId)?.setConsent(granted);
    else trackers.forEach(t => t.setConsent(granted));
  },
  optOut(siteId?: string): void {
    if (siteId) trackers.get(siteId)?.optOut();
    else trackers.forEach(t => t.optOut());
  },
  beginNavigation(): void { trackers.forEach(t => t.beginNavigation()); },
  cancelNavigation(): void { trackers.forEach(t => t.cancelNavigation()); },
  pageReady(options?: PageReadyOptions): void { trackers.forEach(t => t.pageReady(options)); },
  captureHeatmapSnapshot(): void { trackers.forEach(t => t.captureHeatmapSnapshot()); },
  registerScrollContainer(options: ScrollContainerOptions): () => void {
    const unregister = [...trackers.values()].map(t => t.registerScrollContainer(options));
    return () => unregister.forEach(remove => remove());
  },
  refreshHeatmapLayout(): void { trackers.forEach(t => t.refreshHeatmapLayout()); },
  flush(): Promise<void> { return Promise.all([...trackers.values()].map(t => t.flush())).then(() => undefined); },
};
export const init = (options: TrackerOptions): Tracker => SeeRay.init(options);
