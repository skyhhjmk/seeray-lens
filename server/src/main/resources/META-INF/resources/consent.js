(() => {
  const script = document.currentScript;
  const siteId = script?.getAttribute('data-site-id');
  if (!siteId || !window.SeeRay) return;
  const key = `seeray:${siteId}:consent`;
  if (localStorage.getItem(key)) return;
  const language = script.getAttribute('data-language') || document.documentElement.lang || 'en';
  const zh = language.toLowerCase().startsWith('zh');
  const panel = document.createElement('section');
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', zh ? '统计数据同意' : 'Analytics consent');
  panel.style.cssText = 'position:fixed;z-index:2147483647;left:16px;right:16px;bottom:16px;max-width:680px;margin:auto;padding:16px;background:#172033;color:#fff;border-radius:10px;box-shadow:0 8px 32px #0008;font:14px/1.5 system-ui,sans-serif';
  panel.innerHTML = `<div style="margin-bottom:12px">${zh ? '我们使用匿名统计数据来改进本站体验。你可以选择接受或拒绝；拒绝后不会发送分析数据。' : 'We use anonymous analytics to improve this site. You can accept or decline; declining sends no analytics data.'}</div><div style="display:flex;gap:8px;justify-content:flex-end"><button type="button" data-seeray-decline>${zh ? '拒绝' : 'Decline'}</button><button type="button" data-seeray-accept>${zh ? '接受' : 'Accept'}</button></div>`;
  const close = granted => { window.SeeRay.setConsent(granted); panel.remove(); };
  panel.querySelector('[data-seeray-accept]').addEventListener('click', () => close(true));
  panel.querySelector('[data-seeray-decline]').addEventListener('click', () => close(false));
  document.body.append(panel);
})();
