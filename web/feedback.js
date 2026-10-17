(() => {
  if (window.primordiaFeedback) return;
  const overlay = document.createElement('div');
  overlay.id = 'primordia-feedback';
  overlay.hidden = true;
  overlay.innerHTML = '<form role="dialog" aria-modal="true" aria-labelledby="feedback-heading"><h2 id="feedback-heading">Feedback</h2><label>Type<select name="category"><option value="bug">Bug report</option><option value="feature">Feature request</option></select></label><label>Short title<input name="title" maxlength="120" required autocomplete="off"></label><label>Details<textarea name="description" maxlength="6000" rows="5" required placeholder="What happened, or what would you like to add?"></textarea></label><p>Game version and simulation tick are included automatically.</p><p role="status" aria-live="polite"></p><button type="submit">Submit</button><button type="button" data-close>Back</button></form>';
  const style = document.createElement('style');
  style.textContent = '#primordia-feedback[hidden]{display:none}#primordia-feedback{position:fixed;inset:0;z-index:10000;background:#030b18cc;display:flex;align-items:center;justify-content:center;padding:12px;box-sizing:border-box;touch-action:auto;overscroll-behavior:contain}#primordia-feedback form{box-sizing:border-box;width:min(100%,500px);max-height:calc(100dvh - 24px);overflow:auto;background:#142b46;color:#e6f7ff;border:1px solid #81c5ce;border-radius:12px;padding:18px;font:18px "Comic Sans MS","Comic Neue",sans-serif}#primordia-feedback h2{margin:0 0 12px}#primordia-feedback label{display:block;margin-bottom:12px}#primordia-feedback input,#primordia-feedback textarea,#primordia-feedback select,#primordia-feedback button{box-sizing:border-box;width:100%;font:inherit;color:inherit;background:#203e59;border:1px solid #81a5bf;border-radius:6px;padding:10px;min-height:44px}#primordia-feedback input,#primordia-feedback textarea,#primordia-feedback select{display:block;margin-top:5px}#primordia-feedback textarea{resize:vertical;min-height:90px;max-height:35dvh}#primordia-feedback p{font-size:15px}#primordia-feedback button{margin-top:8px}#primordia-feedback button:disabled{opacity:.6}';
  document.head.append(style);document.body.append(overlay);
  const form = overlay.querySelector('form'), send = form.querySelector('[type=submit]');
  const fields = ['category','title','description'];
  const storageKey = 'primordia.feedback.draft' + (location.pathname.startsWith('/experimental/') ? '.experimental' : '');
  let action = null, reportId = "", signature = "";
  const draft = () => Object.fromEntries(fields.map(name => [name,form.elements[name].value]));
  const remember = () => { try { localStorage.setItem(storageKey,JSON.stringify({...draft(),id:reportId,signature})); } catch (_) {} };
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey) || '{}');
    if (/^[a-f0-9]{32}$/.test(saved.id || '')) reportId=saved.id;
    if (typeof saved.signature === 'string') signature=saved.signature;
    for (const name of fields) if (typeof saved[name] === 'string') form.elements[name].value=saved[name];
  } catch (_) {}
  form.addEventListener('input',remember);
  form.addEventListener('submit',event => {
    event.preventDefault();if (send.disabled || !form.reportValidity()) return;
    const content=draft(), next=JSON.stringify(content);
    if (!reportId || signature!==next) {
      reportId=Array.from(crypto.getRandomValues(new Uint8Array(16)),v=>v.toString(16).padStart(2,'0')).join('');
      signature=next;
    }
    action={...content,id:reportId};remember();send.disabled=true;
  });
  form.querySelector('[data-close]').addEventListener('click',() => { action={close:true}; });
  for (const eventName of ['keydown','keyup','keypress']) {
    window.addEventListener(eventName,event => {
      if (!overlay.hidden && overlay.contains(event.target)) event.stopImmediatePropagation();
    },true);
  }
  const fit = () => {
    const viewport=window.visualViewport, height=viewport?.height || window.innerHeight;
    overlay.style.height=height+'px';overlay.style.bottom='auto';
    overlay.style.top=(viewport?.offsetTop || 0)+'px';
    form.style.maxHeight=Math.max(100,height-24)+'px';
  };
  window.visualViewport?.addEventListener('resize',fit);
  window.visualViewport?.addEventListener('scroll',fit);
  window.addEventListener('resize',fit);
  window.primordiaFeedback = {
    open() { overlay.hidden=false;fit();send.disabled=false;form.querySelector('[role=status]').textContent='';form.elements.title.focus(); },
    close() { overlay.hidden=true;action=null;remember();document.getElementById('canvas')?.focus(); },
    take() { const next=action;action=null;return JSON.stringify(next); },
    result(value) {
      send.disabled=value.busy;for (const name of fields) form.elements[name].disabled=value.busy;form.querySelector('[role=status]').textContent=value.message;
      if (value.saved) { if (JSON.stringify(draft())===signature) { form.elements.title.value='';form.elements.description.value=''; } reportId='';signature='';remember(); }
    }
  };
})();
