import { Replayer } from 'rrweb';
import type { eventWithTime } from '@rrweb/types';

class SeeRayReplayerElement extends HTMLElement {
  private root?: HTMLDivElement;
  private replayer?: Replayer;

  connectedCallback(): void { void this.load(); }

  renderCapture(events: eventWithTime[], mode = 'snapshot'): void {
    this.replaceChildren();
    this.root = document.createElement('div');
    this.root.style.cssText = 'width:100%;height:100%;overflow:auto;background:white';
    this.append(this.root);
    if (!events.length) {
      this.showError('No events');
      return;
    }
    this.replayer = new Replayer(events, {
      root: this.root,
      mouseTail: mode === 'recording',
      UNSAFE_replayCanvas: false,
    });
    if (mode === 'recording') this.addControls();
    else {
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

  private addControls(): void {
    if (!this.root || !this.replayer) return;
    const controls = document.createElement('div');
    controls.style.cssText = 'position:sticky;bottom:0;display:flex;gap:8px;padding:8px;background:#fffffff2;border-top:1px solid #ddd;z-index:10';
    const button = (label: string, action: () => void): HTMLButtonElement => {
      const value = document.createElement('button');
      value.textContent = label;
      value.onclick = action;
      return value;
    };
    controls.append(
      button('Play', () => this.replayer?.play()),
      button('Pause', () => this.replayer?.pause()),
      button('1×', () => this.replayer?.setConfig({ speed: 1 })),
      button('2×', () => this.replayer?.setConfig({ speed: 2 })),
      button('4×', () => this.replayer?.setConfig({ speed: 4 })),
    );
    this.root.append(controls);
  }
}

if (!customElements.get('seeray-replayer')) customElements.define('seeray-replayer', SeeRayReplayerElement);
