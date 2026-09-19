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
  panel.innerHTML = `<div style="margin-bottom:12px">${zh ? '我们使用匿名统计数据来改进本站体验。你可以选择接受或拒绝；拒绝后不会发送分析数据。' : 'We use anonymous analytics to improve this site. You can accept or decline; declining sends no analytics data.'}</div><div style="display:flex;flex-wrap:wrap;gap:8px;justify-content:flex-end"><button type="button" data-seeray-decline>${zh ? '拒绝' : 'Decline'}</button><button type="button" data-seeray-accept>${zh ? '接受' : 'Accept'}</button></div>`;
  const decline = panel.querySelector('[data-seeray-decline]');
  const accept = panel.querySelector('[data-seeray-accept]');
  const buttonBase = {
    alignItems: 'center',
    borderRadius: '8px',
    cursor: 'pointer',
    display: 'inline-flex',
    font: 'inherit',
    fontWeight: '600',
    justifyContent: 'center',
    lineHeight: '1.2',
    minHeight: '36px',
    padding: '8px 16px',
    transition: 'background-color .15s ease, border-color .15s ease, box-shadow .15s ease',
  };
  const setButtonState = (button, state) => Object.assign(button.style, buttonBase, state);
  const addButtonInteractions = (button, normal, hover) => {
    setButtonState(button, normal);
    button.addEventListener('mouseenter', () => setButtonState(button, hover));
    button.addEventListener('mouseleave', () => setButtonState(button, normal));
    button.addEventListener('focus', () => { button.style.boxShadow = '0 0 0 3px rgba(56, 189, 248, .35)'; });
    button.addEventListener('blur', () => { button.style.boxShadow = normal.boxShadow || 'none'; });
  };
  addButtonInteractions(decline, {
    backgroundColor: '#26344d',
    border: '1px solid #64748b',
    color: '#e2e8f0',
    boxShadow: 'none',
  }, {
    backgroundColor: '#334765',
    borderColor: '#94a3b8',
    color: '#fff',
    boxShadow: 'none',
  });
  addButtonInteractions(accept, {
    backgroundColor: '#0ea5e9',
    border: '1px solid #38bdf8',
    color: '#fff',
    boxShadow: 'none',
  }, {
    backgroundColor: '#0284c7',
    borderColor: '#7dd3fc',
    color: '#fff',
    boxShadow: 'none',
  });
  const close = granted => { window.SeeRay.setConsent(granted); panel.remove(); };
  accept.addEventListener('click', () => close(true));
  decline.addEventListener('click', () => close(false));
  document.body.append(panel);
})();
