import { record } from 'rrweb';
import type { eventWithTime } from '@rrweb/types';

export interface CaptureIdentity {
  instanceId: string;
  url: string;
  layoutVersion: string;
  targetId: string;
  viewportWidth: number;
  viewportHeight: number;
  contentWidth: number;
  contentHeight: number;
}

export interface CaptureOptions {
  siteId: string;
  snapshotEndpoint: string;
  recordingEndpoint: string;
  identity: CaptureIdentity;
  captureSnapshot: boolean;
  captureRecording: boolean;
  recordingId: string;
}

const PROTOCOL_VERSION = 1;
const MAX_CHUNK_BYTES = 192 * 1024;

export function startCapture(options: CaptureOptions): () => void {
  let stopped = false;
  let snapshotSent = false;
  const snapshotEvents: eventWithTime[] = [];
  let sequence = 0;
  const pageStartedAt = Date.now();
  let recordingEvents: eventWithTime[] = [];
  let flushTimer: ReturnType<typeof setTimeout> | undefined;

  const send = async (endpoint: string, body: unknown, unload = false): Promise<boolean> => {
    const value = JSON.stringify(body);
    if (unload && globalThis.navigator?.sendBeacon?.(endpoint, new Blob([value], { type: 'application/json' }))) return true;
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: value,
        keepalive: unload,
      });
      return response.ok;
    } catch {
      return false;
    }
  };

  const flush = async (finalChunk = false, unload = false): Promise<void> => {
    if (!options.captureRecording || !recordingEvents.length) return;
    const events = recordingEvents;
    recordingEvents = [];
    const accepted = await send(options.recordingEndpoint, {
      protocolVersion: PROTOCOL_VERSION,
      recordingId: options.recordingId,
      instanceId: options.identity.instanceId,
      sequence,
      startedOffsetMs: Math.max(0, Number(events[0]?.timestamp ?? pageStartedAt) - pageStartedAt),
      finalChunk,
      url: options.identity.url,
      events,
    }, unload);
    if (accepted) sequence += 1;
    else if (!unload) recordingEvents.unshift(...events);
  };

  const schedule = (): void => {
    if (!flushTimer) flushTimer = setTimeout(() => {
      flushTimer = undefined;
      void flush();
    }, 5000);
  };

  const stop = record({
    emit(event) {
      if (stopped) return;
      if (options.captureSnapshot && !snapshotSent) {
        snapshotEvents.push(event);
        if (event.type === 2) {
          snapshotSent = true;
          void send(options.snapshotEndpoint, {
            protocolVersion: PROTOCOL_VERSION,
            ...options.identity,
            events: snapshotEvents,
          });
        }
      }
      if (options.captureRecording) {
        recordingEvents.push(event);
        if (JSON.stringify(recordingEvents).length >= MAX_CHUNK_BYTES) void flush();
        else schedule();
      }
    },
    maskAllInputs: true,
    maskTextSelector: '[data-seeray-mask]',
    blockSelector: '[data-seeray-ignore],[data-seeray-heatmap-ignore]',
    slimDOMOptions: {
      script: true,
      comment: true,
      headFavicon: true,
      headMetaDescKeywords: true,
      headMetaSocial: true,
      headMetaRobots: true,
      headMetaHttpEquiv: true,
      headMetaAuthorship: true,
      headMetaVerification: true,
    },
    recordCanvas: false,
    collectFonts: false,
  });

  const unload = (): void => { void flush(true, true); };
  globalThis.addEventListener?.('pagehide', unload);
  return () => {
    if (stopped) return;
    stopped = true;
    if (flushTimer) clearTimeout(flushTimer);
    flushTimer = undefined;
    stop?.();
    globalThis.removeEventListener?.('pagehide', unload);
    void flush(true);
  };
}
