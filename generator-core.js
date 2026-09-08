/* Shared application utilities and navigation; IDs are loaded only once. */
(() => {
  'use strict';
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  const data = window.WBF_DATA || {pals:[],items:[]};
  const name = (kind, id) => (data[kind] || []).find(row => String(row.id).toLowerCase() === String(id).toLowerCase())?.name || id;
  async function copy(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try { await navigator.clipboard.writeText(text); return true; } catch (_) { /* local-file fallback */ }
    }
    const area = document.createElement('textarea'); area.value = text;
    area.style.position = 'fixed'; area.style.left = '-10000px'; document.body.append(area); area.select();
    let ok = false; try { ok = document.execCommand('copy'); } finally { area.remove(); } return ok;
  }
  const download = (name, text) => {
    const url = URL.createObjectURL(new Blob([text], {type:'text/plain;charset=utf-8'}));
    const link = document.createElement('a'); link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  window.GeneratorCore = Object.freeze({escapeHtml, data, name, copy, download});
  for (const page of ['worldboss','shop']) document.getElementById(`page-${page}`).addEventListener('click', () => {
    for (const other of ['worldboss','shop']) {
      document.getElementById(`${other}-page`).hidden = page !== other;
      document.getElementById(`${other}-actions`).hidden = page !== other;
      document.getElementById(`page-${other}`).setAttribute('aria-pressed', String(page === other));
    }
    document.querySelector('.brand h1').textContent = page === 'shop' ? 'Server Shop Config Generator' : 'Spawner Config Generator';
    window.dispatchEvent(new Event('resize'));
  });
})();
