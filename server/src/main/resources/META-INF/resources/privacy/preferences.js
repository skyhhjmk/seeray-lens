(() => {
  const root = document.getElementById('seeray-privacy-preferences');
  if (!root) return;

  const status = document.getElementById('seeray-privacy-status');
  const allow = document.getElementById('seeray-privacy-allow');
  const deny = document.getElementById('seeray-privacy-deny');
  const siteId = root.dataset.siteId;
  if (!status || !allow || !deny || !siteId) return;
  const zh = (navigator.language || '').toLowerCase().startsWith('zh');
  const copy = zh ? {
    heading: '隐私设置',
    description: '请选择是否允许此网站在当前浏览器收集匿名分析数据。',
    connecting: '正在连接此网站的追踪器…',
    allow: '允许分析',
    deny: '退出统计',
    unavailable: '无法连接到此网站的追踪器。请将此页面嵌入安装了 SeeRay 追踪器的网站。',
    saving: '正在保存你的选择…',
    unknown: '尚未记录选择。分析数据会等待你的决定。',
    granted: '此浏览器已允许匿名分析。',
    denied: '此浏览器已退出匿名分析。',
    note: '此选择由追踪器保存在当前浏览器中，仅适用于此网站。',
  } : {
    heading: 'Privacy preferences',
    description: 'Choose whether this site may collect anonymous analytics on this browser.',
    connecting: "Connecting to this site's tracker…",
    allow: 'Allow analytics',
    deny: 'Opt out',
    unavailable: 'This page cannot reach the site tracker. Embed it on the website where the SeeRay tracker is installed.',
    saving: 'Saving your choice…',
    unknown: 'No choice is recorded yet. Analytics will wait for your decision.',
    granted: 'Anonymous analytics is enabled in this browser.',
    denied: 'This browser has opted out of anonymous analytics.',
    note: 'The tracker stores this choice in this browser and applies it only to this site.',
  };

  document.documentElement.lang = zh ? 'zh' : 'en';
  document.title = copy.heading;
  for (const element of root.querySelectorAll('[data-copy]')) {
    const key = element.dataset.copy;
    if (key && copy[key]) element.textContent = copy[key];
  }
  const render = (state) => {
    status.textContent = state === 'granted' ? copy.granted : state === 'denied' ? copy.denied : copy.unknown;
    allow.disabled = false;
    deny.disabled = false;
  };
  const requestState = () => window.parent.postMessage({
    source: 'seeray-privacy',
    type: 'privacy-state-request',
    siteId,
  }, '*');
  const choose = (granted) => {
    allow.disabled = true;
    deny.disabled = true;
    status.textContent = copy.saving;
    window.parent.postMessage({
      source: 'seeray-privacy',
      type: 'privacy-consent-choice',
      siteId,
      granted,
    }, '*');
  };

  if (window.parent === window) {
    status.textContent = copy.unavailable;
    return;
  }
  window.addEventListener('message', (event) => {
    // The parent is intentionally cross-origin. The site's tracker validates this page's
    // origin, source window, site ID, and exact iframe URL before replying.
    if (event.source !== window.parent) return;
    const message = event.data;
    if (!message || message.source !== 'seeray-tracker' || message.type !== 'privacy-state' || message.siteId !== siteId) return;
    render(message.state);
  });
  allow.addEventListener('click', () => choose(true));
  deny.addEventListener('click', () => choose(false));
  requestState();
  window.setTimeout(() => {
    if (allow.disabled && deny.disabled && window.parent !== window) status.textContent = copy.unavailable;
  }, 1800);
})();
