/* SeeRay Lens browser tracker. Stable public URL: /tracker.js */
(function (window, document) {
  'use strict';
  var scripts = document.getElementsByTagName('script');
  var current = document.currentScript || scripts[scripts.length - 1];
  var base = new URL('/', current.src || window.location.href).origin;
  var registry = window.__seerayLensTrackers || (window.__seerayLensTrackers = {});
  function uuid() {
    if (window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
    var bytes = new Uint8Array(16); window.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    return Array.prototype.map.call(bytes, function (b, i) { return ([4, 6, 8, 10].indexOf(i) >= 0 ? '-' : '') + b.toString(16).padStart(2, '0'); }).join('');
  }
  function stored(storage, key) { try { var value = storage.getItem(key); if (value) return value; value = uuid(); storage.setItem(key, value); return value; } catch (_) { return uuid(); } }
  function Tracker(options) {
    this.siteId = options.siteId; this.endpoint = options.endpoint || base + '/api/v1/collect';
    this.visitorId = stored(window.localStorage, 'seeray:' + this.siteId + ':visitor_id');
    this.sessionId = stored(window.sessionStorage, 'seeray:' + this.siteId + ':session_id');
    this.queue = []; this.pageUrls = {}; this.timer = null;
    var self = this; window.addEventListener('pagehide', function () { self.flush(true); });
  }
  Tracker.prototype.track = function (type, data) {
    if ((navigator.doNotTrack === '1' || navigator.doNotTrack === 'yes') || !type) return;
    data = data || {}; this.queue.push({ eventId: uuid(), type: type, occurredAt: new Date().toISOString(), url: data.url || window.location.href, title: data.title || document.title, referrer: data.referrer || document.referrer, properties: data.properties, category: data.category, action: data.action, name: data.name, visitorId: this.visitorId, sessionId: this.sessionId });
    if (!this.timer) { var self = this; this.timer = window.setTimeout(function () { self.flush(false); }, 1000); }
  };
  Tracker.prototype.trackPageView = function (data) { data = data || {}; var url = data.url || window.location.href; if (this.pageUrls[url]) return; this.pageUrls[url] = true; data.url = url; this.track('page_view', data); };
  Tracker.prototype.trackGoal = function (name, data) { if (!name) return; data = data || {}; data.name = name; this.track('goal', data); };
  Tracker.prototype.flush = function (unload) {
    if (this.timer) { window.clearTimeout(this.timer); this.timer = null; }
    if (!this.queue.length) return; var events = this.queue.splice(0, 100); var body = JSON.stringify({ schemaVersion: 1, siteId: this.siteId, sentAt: new Date().toISOString(), events: events });
    if (unload && navigator.sendBeacon && navigator.sendBeacon(this.endpoint, new Blob([body], { type: 'application/json' }))) return;
    fetch(this.endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body, keepalive: !!unload }).catch(function () {});
  };
  var api = window.SeeRay || {};
  api.init = function (options) { if (!options || !options.siteId) return null; return registry[options.siteId] || (registry[options.siteId] = new Tracker(options)); };
  api.trackPageView = function (options) { Object.keys(registry).forEach(function (key) { registry[key].trackPageView(options); }); };
  api.track = function (type, options) { Object.keys(registry).forEach(function (key) { registry[key].track(type, options); }); };
  api.trackGoal = function (name, options) { Object.keys(registry).forEach(function (key) { registry[key].trackGoal(name, options); }); };
  api.flush = function () { Object.keys(registry).forEach(function (key) { registry[key].flush(false); }); };
  window.SeeRay = api;
  var siteId = current.getAttribute('data-site-id');
  if (siteId) api.init({ siteId: siteId }).trackPageView();
}(window, document));
