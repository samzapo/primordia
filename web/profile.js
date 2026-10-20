(() => {
  if (window.primordiaProfile) return;
  const overlay=document.createElement('div');overlay.id='primordia-profile';overlay.hidden=true;
  overlay.innerHTML='<form role="dialog" aria-modal="true" aria-labelledby="profile-heading"><h2 id="profile-heading">Family and favorite cell</h2><label>Family name<input name="playerName" maxlength="24" required autocomplete="nickname"></label><label>Favorite cell first name (optional)<input name="favoriteName" maxlength="24"></label><p>Shown above cells in your lineage. Highlighted while you are connected.</p><p role="status" aria-live="polite"></p><button type="submit">Save name</button><button type="button" data-close>Back</button></form>';
  const style=document.createElement('style');
  style.textContent='#primordia-profile[hidden]{display:none}#primordia-profile{position:fixed;inset:0;z-index:10000;display:flex;align-items:center;justify-content:center;padding:12px;box-sizing:border-box;background:#030b18cc;touch-action:auto}#primordia-profile form{box-sizing:border-box;width:min(100%,500px);max-height:calc(100dvh - 24px);overflow:auto;background:#142b46;color:#e6f7ff;border:1px solid #81c5ce;border-radius:12px;padding:18px;font:18px "Comic Sans MS","Comic Neue",sans-serif}#primordia-profile h2{margin:0 0 12px}#primordia-profile input,#primordia-profile button{box-sizing:border-box;display:block;width:100%;font:inherit;color:inherit;background:#203e59;border:1px solid #81a5bf;border-radius:6px;padding:10px;min-height:44px;margin-top:8px}#primordia-profile p{font-size:15px}#primordia-profile button:disabled{opacity:.6}';
  document.head.append(style);document.body.append(overlay);
  const form=overlay.querySelector('form'),input=form.elements.playerName,send=form.querySelector('[type=submit]');let action=null;
  const fit=()=>{const v=window.visualViewport,h=v?.height||innerHeight;overlay.style.top=(v?.offsetTop||0)+'px';overlay.style.height=h+'px';overlay.style.bottom='auto';form.style.maxHeight=Math.max(100,h-24)+'px';};
  window.visualViewport?.addEventListener('resize',fit);window.visualViewport?.addEventListener('scroll',fit);window.addEventListener('resize',fit);
  form.addEventListener('submit',event=>{event.preventDefault();if(send.disabled||!form.reportValidity())return;action={name:input.value,favorite_name:form.elements.favoriteName.value};send.disabled=true;});
  form.querySelector('[data-close]').addEventListener('click',()=>{action={close:true};});
  for(const type of ['keydown','keyup','keypress'])window.addEventListener(type,event=>{if(!overlay.hidden&&overlay.contains(event.target))event.stopImmediatePropagation();},true);
  window.primordiaProfile={
    open(name,favorite=""){input.value=name;form.elements.favoriteName.value=favorite;action=null;overlay.hidden=false;fit();send.disabled=false;input.disabled=false;form.querySelector('[role=status]').textContent='';input.focus();},
    close(){overlay.hidden=true;action=null;document.getElementById('canvas')?.focus();},
    take(){const next=action;action=null;return JSON.stringify(next);},
    result(value){send.disabled=value.busy;input.disabled=value.busy;form.querySelector('[role=status]').textContent=value.message;}
  };
})();
