import { Replayer, ReplayerEvents } from 'rrweb';
import {
  EventType,
  IncrementalSource,
  MediaInteractions,
  MouseInteractions,
  type eventWithTime,
} from '@rrweb/types';

interface TimelineMarker {
  offset: number;
  label: string;
}

function formatTime(milliseconds: number): string {
  const totalSeconds = Math.floor(Math.max(0, milliseconds) / 1000);
  const seconds = String(totalSeconds % 60).padStart(2, '0');
  const minutes = String(Math.floor(totalSeconds / 60) % 60).padStart(2, '0');
  const hours = Math.floor(totalSeconds / 3600);
  return hours > 0 ? `${hours}:${minutes}:${seconds}` : `${minutes}:${seconds}`;
}

function eventLabel(event: eventWithTime, chinese: boolean): string | undefined {
  if (event.type !== EventType.IncrementalSnapshot) return undefined;
  const data = event.data;
  if (data.source === IncrementalSource.MouseInteraction) {
    switch (data.type) {
      case MouseInteractions.Click: return chinese ? '点击' : 'Click';
      case MouseInteractions.DblClick: return chinese ? '双击' : 'Double click';
      case MouseInteractions.ContextMenu: return chinese ? '右键' : 'Context menu';
      case MouseInteractions.TouchStart: return chinese ? '触摸' : 'Touch';
      default: return undefined;
    }
  }
  if (data.source === IncrementalSource.Scroll) return chinese ? '滚动' : 'Scroll';
  if (data.source === IncrementalSource.Input) return chinese ? '输入' : 'Input';
  if (data.source === IncrementalSource.Drag) return chinese ? '拖动' : 'Drag';
  if (data.source === IncrementalSource.ViewportResize) return chinese ? '窗口调整' : 'Resize';
  if (data.source === IncrementalSource.MediaInteraction) {
    switch (data.type) {
      case MediaInteractions.Play: return chinese ? '媒体播放' : 'Media play';
      case MediaInteractions.Pause: return chinese ? '媒体暂停' : 'Media pause';
      case MediaInteractions.Seeked: return chinese ? '媒体定位' : 'Media seek';
      default: return chinese ? '媒体控制' : 'Media control';
    }
  }
  return undefined;
}

class SeeRayReplayerElement extends HTMLElement {
  private root?: HTMLDivElement;
  private captureViewport?: HTMLDivElement;
  private stage?: HTMLDivElement;
  private replayer?: Replayer;
  private progressTimer?: number;
  private resizeObserver?: ResizeObserver;
  private replayWidth = 0;
  private replayHeight = 0;
  private replayScale = 1;

  connectedCallback(): void { void this.load(); }

  disconnectedCallback(): void {
    if (this.progressTimer !== undefined) window.clearInterval(this.progressTimer);
    this.progressTimer = undefined;
    this.resizeObserver?.disconnect();
    this.resizeObserver = undefined;
    this.replayer?.destroy();
    this.replayer = undefined;
  }

  renderCapture(events: eventWithTime[], mode = 'snapshot'): void {
    this.resizeObserver?.disconnect();
    this.resizeObserver = undefined;
    this.replayer?.destroy();
    this.replayer = undefined;
    this.captureViewport = undefined;
    this.stage = undefined;
    this.replaceChildren();
    this.root = document.createElement('div');
    const recording = mode === 'recording';
    this.root.style.cssText = recording
      ? 'display:flex;flex-direction:column;width:100%;height:100%;min-width:0;min-height:0;overflow:hidden;background:white;box-sizing:border-box'
      : 'width:100%;height:100%;overflow:auto;background:white';
    this.append(this.root);
    const playerStyles = document.createElement('style');
    playerStyles.textContent = `
      .replayer-wrapper { position: relative; }
      .replayer-wrapper > iframe { display: block; }
      .seeray-replay-stage > .replayer-wrapper {
        position: absolute;
        left: 0;
        top: 0;
        transform-origin: top left;
      }
      .replayer-mouse {
        position: absolute;
        z-index: 1;
        width: 20px;
        height: 20px;
        border-radius: 50%;
        background: rgb(73, 80, 246);
        opacity: 0.35;
        pointer-events: none;
        transform: translate(-50%, -50%);
      }
      .replayer-mouse-tail {
        position: absolute;
        z-index: 1;
        pointer-events: none;
      }
    `;
    this.root.append(playerStyles);
    let playerRoot: HTMLDivElement = this.root;
    if (recording) {
      this.captureViewport = document.createElement('div');
      this.captureViewport.style.cssText = 'position:relative;flex:1 1 auto;min-width:0;min-height:0;width:100%;overflow:hidden;background:white;scrollbar-width:none;-ms-overflow-style:none';
      this.stage = document.createElement('div');
      this.stage.className = 'seeray-replay-stage';
      this.stage.style.cssText = 'position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);overflow:visible;box-sizing:border-box';
      this.captureViewport.append(this.stage);
      this.root.append(this.captureViewport);
      playerRoot = this.stage;
    }
    if (!events.length) {
      this.showError('No events');
      return;
    }
    const orderedEvents = [...events].sort((a, b) => a.timestamp - b.timestamp);
    const firstMeta = orderedEvents.find(event => event.type === EventType.Meta);
    if (recording && firstMeta?.type === EventType.Meta) {
      this.replayWidth = firstMeta.data.width;
      this.replayHeight = firstMeta.data.height;
    } else if (recording) {
      const firstResize = orderedEvents.find(event =>
        event.type === EventType.IncrementalSnapshot && event.data.source === IncrementalSource.ViewportResize,
      );
      if (firstResize?.type === EventType.IncrementalSnapshot && firstResize.data.source === IncrementalSource.ViewportResize) {
        this.replayWidth = firstResize.data.width;
        this.replayHeight = firstResize.data.height;
      }
    }
    this.replayer = new Replayer(orderedEvents, {
      root: playerRoot,
      mouseTail: mode === 'recording',
      UNSAFE_replayCanvas: false,
    });
    if (recording) {
      this.replayer.on(ReplayerEvents.Resize, size => {
        this.replayWidth = size.width;
        this.replayHeight = size.height;
        this.applyReplaySizing();
      });
      this.resizeObserver = new ResizeObserver(() => this.applyReplaySizing());
      this.resizeObserver.observe(this.captureViewport!);
      this.enableManualScroll();
      this.addControls(orderedEvents);
      this.applyReplaySizing();
    } else {
      this.replayer.pause(0);
      this.root.querySelectorAll<HTMLElement>('.replayer-wrapper,iframe').forEach(element => {
        element.style.width = '100%';
        element.style.height = '100%';
        element.style.maxHeight = 'none';
      });
    }
  }

  private async load(): Promise<void> {
    const base = this.getAttribute('api-base') ?? '';
    const site = this.getAttribute('site-id');
    const resource = this.getAttribute('resource-id');
    const mode = this.getAttribute('mode') ?? 'snapshot';
    const token = this.getAttribute('access-token');
    this.removeAttribute('access-token');
    if (!site || !resource) return;
    this.replaceChildren();
    this.root = document.createElement('div');
    this.root.style.cssText = 'width:100%;height:100%;overflow:auto;background:white';
    this.append(this.root);
    const path = mode === 'recording'
      ? `/api/v1/sites/${site}/heatmaps/recordings/${resource}`
      : `/api/v1/sites/${site}/heatmaps/dom-snapshots/${resource}`;
    try {
      const response = await fetch(`${base.replace(/\/$/, '')}${path}`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const body = await response.json() as unknown;
      const events = mode === 'recording'
        ? (body as Array<{ events: eventWithTime[] }>).flatMap(chunk => chunk.events)
        : body as eventWithTime[];
      this.renderCapture(events, mode);
    } catch (error) {
      this.showError(String(error));
    }
  }

  private showError(message: string): void {
    if (!this.root) return;
    this.root.textContent = `Unable to render capture: ${message}`;
    this.root.style.padding = '16px';
  }

  private enableManualScroll(): void {
    this.root?.addEventListener('wheel', event => {
      if (event.target instanceof Element && event.target.closest('.seeray-replay-controls')) return;
      const frame = this.root?.querySelector('iframe');
      const frameWindow = frame?.contentWindow;
      if (!frameWindow) return;
      const scale = Math.max(this.replayScale, 0.01);
      frameWindow.scrollBy(event.deltaX / scale, event.deltaY / scale);
      event.preventDefault();
    }, { passive: false });
  }

  private applyReplaySizing(): void {
    const viewport = this.captureViewport;
    const stage = this.stage;
    if (!viewport || !stage || this.replayWidth <= 0 || this.replayHeight <= 0) return;
    const availableWidth = viewport.clientWidth;
    const availableHeight = viewport.clientHeight;
    if (availableWidth <= 0 || availableHeight <= 0) return;
    const scale = Math.min(availableWidth / this.replayWidth, availableHeight / this.replayHeight);
    this.replayScale = scale;
    stage.style.width = `${this.replayWidth * scale}px`;
    stage.style.height = `${this.replayHeight * scale}px`;
    const wrapper = stage.querySelector<HTMLElement>('.replayer-wrapper');
    if (!wrapper) return;
    wrapper.style.position = 'absolute';
    wrapper.style.left = '0';
    wrapper.style.top = '0';
    wrapper.style.width = `${this.replayWidth}px`;
    wrapper.style.height = `${this.replayHeight}px`;
    wrapper.style.transformOrigin = 'top left';
    wrapper.style.transform = `scale(${scale})`;
  }

  private addControls(events: eventWithTime[]): void {
    if (!this.root || !this.replayer) return;
    const replayer = this.replayer;
    const chinese = navigator.language.toLowerCase().startsWith('zh');
    const firstTimestamp = events[0].timestamp;
    const duration = Math.max(1, events[events.length - 1].timestamp - firstTimestamp);
    const controls = document.createElement('div');
    controls.className = 'seeray-replay-controls';
    controls.style.cssText = 'position:relative;flex:0 0 auto;display:flex;flex-direction:column;gap:6px;padding:8px;background:#fffffff2;border-top:1px solid #ddd;z-index:10;font:12px sans-serif';
    const button = (label: string, action: () => void): HTMLButtonElement => {
      const value = document.createElement('button');
      value.textContent = label;
      value.onclick = action;
      return value;
    };
    const timeline = document.createElement('div');
    timeline.style.cssText = 'position:relative;height:22px;width:100%';
    const progress = document.createElement('input');
    progress.type = 'range';
    progress.min = '0';
    progress.max = String(duration);
    progress.step = '1';
    progress.value = '0';
    progress.setAttribute('aria-label', chinese ? '回放进度' : 'Playback progress');
    progress.style.cssText = 'position:absolute;inset:0;width:100%;height:22px;margin:0;accent-color:#4950f6;cursor:pointer';
    timeline.append(progress);
    const timeLabel = document.createElement('span');
    timeLabel.textContent = `00:00 / ${formatTime(duration)}`;
    timeLabel.style.cssText = 'min-width:78px;text-align:center;font-variant-numeric:tabular-nums';
    const updateProgress = (offset: number): void => {
      const clamped = Math.max(0, Math.min(duration, offset));
      progress.value = String(clamped);
      timeLabel.textContent = `${formatTime(clamped)} / ${formatTime(duration)}`;
    };
    let scrubbing = false;
    progress.addEventListener('pointerdown', () => { scrubbing = true; });
    progress.addEventListener('keydown', () => { scrubbing = true; });
    progress.addEventListener('input', () => {
      timeLabel.textContent = `${formatTime(Number(progress.value))} / ${formatTime(duration)}`;
    });
    const seek = (offset: number): void => {
      replayer.pause(offset);
      scrubbing = false;
      updateProgress(offset);
    };
    progress.addEventListener('change', () => seek(Number(progress.value)));

    const markers: TimelineMarker[] = [];
    let lastUrl: string | undefined;
    for (const event of events) {
      let label = eventLabel(event, chinese);
      if (event.type === EventType.Meta) {
        if (lastUrl !== undefined && lastUrl !== event.data.href) {
          label = chinese ? '页面跳转' : 'Page navigation';
        }
        lastUrl = event.data.href;
      }
      if (label) markers.push({ offset: event.timestamp - firstTimestamp, label });
    }
    const markerGroups = new Map<number, TimelineMarker[]>();
    for (const marker of markers) {
      const bucket = Math.round(marker.offset / duration * 1000);
      markerGroups.set(bucket, [...(markerGroups.get(bucket) ?? []), marker]);
    }
    for (const group of markerGroups.values()) {
      const marker = document.createElement('button');
      marker.type = 'button';
      marker.textContent = group.length > 1 ? String(group.length) : '';
      const names = [...new Set(group.map(item => item.label))];
      const position = Math.max(0, Math.min(100, group[0].offset / duration * 100));
      const markerTime = formatTime(group[0].offset);
      const title = `${markerTime} · ${names.join(', ')}${group.length > names.length ? ` (+${group.length - names.length})` : ''}`;
      marker.title = title;
      marker.setAttribute('aria-label', title);
      marker.style.cssText = `position:absolute;left:${position}%;top:50%;transform:translate(-50%,-50%);z-index:2;min-width:7px;width:${group.length > 1 ? 'auto' : '7px'};height:7px;padding:0 2px;border:1px solid white;border-radius:8px;background:#f97316;color:white;font:9px sans-serif;line-height:6px;cursor:pointer`;
      marker.addEventListener('click', () => seek(group[0].offset));
      timeline.append(marker);
    }

    const controlsRow = document.createElement('div');
    controlsRow.style.cssText = 'display:flex;align-items:center;gap:8px;flex-wrap:wrap';
    const scrollHint = document.createElement('span');
    scrollHint.textContent = chinese
      ? '可手动滚动；播放时跟随访客视角'
      : 'Scroll manually; playback follows the visitor';
    scrollHint.style.cssText = 'margin-right:auto;color:#555';
    const play = (): void => {
      const current = replayer.getCurrentTime();
      replayer.play(current >= duration ? 0 : current);
    };
    replayer.on(ReplayerEvents.Start, () => {
      if (this.progressTimer !== undefined) window.clearInterval(this.progressTimer);
      this.progressTimer = window.setInterval(() => updateProgress(replayer.getCurrentTime()), 100);
    });
    replayer.on(ReplayerEvents.Pause, () => {
      if (this.progressTimer !== undefined) window.clearInterval(this.progressTimer);
      this.progressTimer = undefined;
      updateProgress(replayer.getCurrentTime());
    });
    replayer.on(ReplayerEvents.Finish, () => {
      if (this.progressTimer !== undefined) window.clearInterval(this.progressTimer);
      this.progressTimer = undefined;
      updateProgress(duration);
    });
    replayer.on(ReplayerEvents.EventCast, () => {
      if (!scrubbing) updateProgress(replayer.getCurrentTime());
    });
    controls.append(
      timeline,
      controlsRow,
    );
    controlsRow.append(
      timeLabel,
      button(chinese ? '播放' : 'Play', play),
      button(chinese ? '暂停' : 'Pause', () => replayer.pause()),
      button('1×', () => replayer.setConfig({ speed: 1 })),
      button('2×', () => replayer.setConfig({ speed: 2 })),
      button('4×', () => replayer.setConfig({ speed: 4 })),
      scrollHint,
    );
    this.root.append(controls);
  }
}

if (!customElements.get('seeray-replayer')) customElements.define('seeray-replayer', SeeRayReplayerElement);
