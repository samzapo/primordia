(() => {
  if (window.primordiaReaders) return;
  const style = document.createElement('style');
  style.textContent = [
'#primordia-reader {position:fixed;inset:0;z-index:2147483000;background:#000a;display:flex;align-items:center;justify-content:center;padding:16px;box-sizing:border-box;color:#e5f5ec;font:18px/1.45 system-ui,sans-serif;touch-action:pan-y}',
'#primordia-reader[hidden] {display:none!important}',
'#primordia-reader .reader-card {width:100%;max-width:620px;max-height:calc(100vh - 32px);max-height:calc(100dvh - 32px);display:flex;flex-direction:column;min-height:0;background:#152a47;border:1px solid #527b9d;border-radius:12px;box-shadow:0 8px 32px #0008}',
'#primordia-reader .reader-header {display:flex;align-items:center;gap:12px;flex:none;padding:12px 16px;border-bottom:1px solid #527b9d}',
'#primordia-reader h1 {font:700 23px/1.2 system-ui,sans-serif;margin:0;flex:1;min-width:0}',
'#primordia-reader h2 {font-size:21px;margin:24px 0 14px}',
'#primordia-reader h3 {font-size:18px;margin:20px 0 6px}',
'#primordia-reader p {margin:0 0 12px}',
'#primordia-reader ul {padding-left:24px;margin:0}',
'#primordia-reader li {margin:0 0 16px}',
'#primordia-reader button,#primordia-reader select {color:#e5f5ec;background:#254361;font:inherit;border:1px solid #80efce;border-radius:7px;min-height:48px;padding:8px 12px;cursor:pointer;touch-action:manipulation;box-sizing:border-box}',
'#primordia-reader .reader-close {width:48px;height:48px;padding:0;font-size:30px;flex:none}',
'#primordia-reader .reader-body {flex:1 1 auto;min-height:0;overflow-y:auto;overflow-x:hidden;overscroll-behavior:contain;padding:16px;-webkit-overflow-scrolling:touch;overflow-wrap:anywhere}',
'#primordia-reader a {color:#80efce;text-decoration:underline;display:block;padding:5px 0}',
'#primordia-reader select {width:100%;margin-bottom:16px}',
'#primordia-reader .reader-footer {flex:none;padding:12px 16px;border-top:1px solid #527b9d}',
'#primordia-reader .reader-footer p {font-size:16px}',
'#primordia-reader .reader-back {width:100%}',
'#primordia-reader :focus-visible {outline:3px solid #f5d47b;outline-offset:2px}',
'@media(max-height:420px) {#primordia-reader {padding:8px} #primordia-reader .reader-card {max-height:calc(100vh - 16px);max-height:calc(100dvh - 16px)} #primordia-reader .reader-header,#primordia-reader .reader-footer {padding:6px 12px} #primordia-reader .reader-footer p {display:none}}'
].join('\n');
  document.head.append(style);
  const root = document.createElement('div'); root.id = 'primordia-reader'; root.hidden = true;
  const card = document.createElement('section'); card.className = 'reader-card';
  card.setAttribute('role', 'dialog'); card.setAttribute('aria-modal', 'true');
  card.setAttribute('aria-labelledby', 'primordia-reader-title');
  const header = document.createElement('header'); header.className = 'reader-header';
  const title = document.createElement('h1'); title.id = 'primordia-reader-title';
  const close = document.createElement('button'); close.type = 'button'; close.className = 'reader-close';
  close.textContent = '×'; close.setAttribute('aria-label', 'Close this message');
  header.append(title, close);
  const body = document.createElement('div'); body.className = 'reader-body';
  const footer = document.createElement('footer'); footer.className = 'reader-footer';
  const note = document.createElement('p');
  const back = document.createElement('button'); back.type = 'button'; back.className = 'reader-back';
  footer.append(note, back); card.append(header, body, footer); root.append(card); document.body.append(root);
  let active = '', release = '', previousFocus = null;
  const queues = {update: [], help: [], lineage: []};
  function hide() {
    root.hidden = true;
    if (previousFocus?.isConnected) previousFocus.focus({preventScroll:true});
  }
  function dismiss() {
    if (root.hidden) return;
    queues[active].push({close:true, id:release});
    hide(); // Never wait for the game/server before letting the player leave.
  }
  close.addEventListener('click', dismiss); back.addEventListener('click', () => {
    if (active === 'lineage') {queues.lineage.push({confirmed:true});hide();}
    else dismiss();
  });
  root.addEventListener('keydown', event => {
    if (event.key !== 'Tab') return;
    const targets = Array.from(card.querySelectorAll('button,select,a[href]')).filter(e => !e.disabled && e.getClientRects().length);
    if (!targets.length) return;
    const first = targets[0], last = targets[targets.length-1];
    if (event.shiftKey && document.activeElement === first) {event.preventDefault();last.focus();}
    else if (!event.shiftKey && document.activeElement === last) {event.preventDefault();first.focus();}
  });
  function open(kind, text, footerText, buttonText) {
    previousFocus = document.activeElement; active = kind; queues[kind] = []; release = '';
    title.textContent = text; note.textContent = footerText; note.hidden = !footerText;
    back.textContent = buttonText; body.replaceChildren(); body.scrollTop = 0; root.hidden = false;
    root.dataset.panel = kind; close.focus({preventScroll:true});
  }
  function paragraph(parent, text, tag='p') {
    const node = document.createElement(tag); node.textContent = text; parent.append(node); return node;
  }
  function section(parent, group, science) {
    if (group.title) paragraph(parent, group.title, 'h2');
    for (const item of group.items) {
      paragraph(parent, item.title, 'h3'); paragraph(parent, item.text);
      if (science) for (const source of item.sources || []) {
        if (!String(source.url).startsWith('https://')) continue;
        const link = document.createElement('a'); link.href = source.url; link.textContent = source.title + ' ↗';
        link.target = '_blank'; link.rel = 'noopener noreferrer'; parent.append(link);
      }
    }
  }
  window.primordiaReaders = {
    openLineage() {
      open('lineage', 'Start a new lineage?', 'The shared pond will continue.', 'Start new lineage');
      paragraph(body, 'Your current family will stay alive in the pond under computer control. You will begin with a new cell.');
      paragraph(body, 'Close this message to keep your current lineage.');
    },
    openUpdate(notes) {
      open('update', notes.title, notes.footer, notes.button); release = notes.id;
      const list = document.createElement('ul'); body.append(list);
      for (const item of notes.items) paragraph(list, item, 'li');
    },
    openHelp(payload) {
      open('help', payload.title, '', 'Back to Pause');
      if (!payload.science) {
        for (const group of payload.groups) section(body, group, false);
      } else {
        const select = document.createElement('select'); select.setAttribute('aria-label', 'Mechanics topic');
        const all = document.createElement('option'); all.value = '-1'; all.textContent = 'All mechanics'; select.append(all);
        payload.groups.forEach((group,index) => {
          const option = document.createElement('option'); option.value = String(index); option.textContent = group.title; select.append(option);
        });
        const content = document.createElement('div');
        paragraph(body,'These are simple game rules inspired by living cells. Links explain the real science; the recipes, rates and costs are game choices.');
        body.append(select,content);
        function refresh() {
          content.replaceChildren();
          payload.groups.forEach((group,index) => {if (select.value === '-1' || Number(select.value) === index) section(content,group,true);});
        }
        select.addEventListener('change',refresh); refresh();
      }
      body.scrollTop = 0;
    },
    close(kind) {if (active === kind) hide();queues[kind] = [];},
    take(kind) {return JSON.stringify(queues[kind].shift() || null);}
  };
})();
