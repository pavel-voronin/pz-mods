const $=selector=>document.querySelector(selector);
const fmt=new Intl.NumberFormat('ru-RU');
const dateFmt=new Intl.DateTimeFormat('ru-RU',{day:'numeric',month:'short'});
const timeFmt=new Intl.DateTimeFormat('ru-RU',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'});
const esc=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const n=value=>Number.isFinite(value)?fmt.format(value):'—';
let data;
function error(message){$('#error').hidden=!message;$('#error').textContent=message||'';}
async function api(path,body){const options=body!==undefined?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{};const response=await fetch(path,options);const json=await response.json();if(!response.ok)throw new Error(json.error||'Не удалось загрузить данные.');return json;}
const date=day=>dateFmt.format(new Date(day+'T12:00:00Z'));
function sparkline(series){if(!series)return '<span class="muted">—</span>';const values=series.map(p=>p[1]);const max=Math.max(1,...values);const points=values.map((v,i)=>`${(2+i*86/29).toFixed(1)},${(27-v/max*23).toFixed(1)}`).join(' ');return `<svg class="sparkline" viewBox="0 0 90 30" role="img" aria-label="Новые подписки за 30 дней"><line x1="0" y1="28" x2="90" y2="28"/><polyline points="${points}"/></svg>`;}
function growth(value){return value==null?'<span class="muted">—</span>':`<span class="${value?'growth':'zero'}">${value?'+':''}${n(value)}</span>`;}
function render(next){
  data=next;const items=next.items;$('#mod-count').textContent=items.length||'';
  $('#status').textContent=next.capturedAt?`Счётчики: ${timeFmt.format(new Date(next.capturedAt))} · Steam Workshop`:'Ожидаю первый ответ Steam…';
  if(next.lastError)error(next.lastError);
  const sum=key=>items.reduce((total,item)=>total+(item[key]||0),0);
  const withHistory=items.filter(i=>i.history);
  const complete=items.length>0 && withHistory.length===items.length;
  const sameEnd=complete && new Set(withHistory.map(i=>i.history.end)).size===1;
  const up=withHistory.reduce((total,i)=>total+i.history.votesUp,0);
  const down=withHistory.reduce((total,i)=>total+i.history.votesDown,0);
  const week=sameEnd?withHistory.reduce((total,i)=>total+i.history.subscriptions[1],0):null;
  const summaries=[['♧','Подписчики',sum('subscriptions'),week===null?'Текущие подписки на все моды':`<span class="good">+${n(week)}</span> новых за 7 завершённых дней`],['☆','В избранном',sum('favorited'),'Текущее число добавлений'],['◉','Просмотры',sum('views'),'Посещения страниц за всё время'],['↑','Положительные оценки',complete?up:null,complete?`${n(down)} отрицательных${up+down?' · '+Math.round(up/(up+down)*100)+'% за':''}`:'Нужна история Steam']];
  $('#summary').innerHTML=summaries.map(([symbol,label,value,sub])=>`<div class="stat"><div class="stat-label"><span class="stat-symbol" aria-hidden="true">${symbol}</span>${label}</div><div class="stat-value">${items.length?n(value):'—'}</div><div class="stat-sub">${sub}</div></div>`).join('');
  const oldest=withHistory.map(i=>i.history.capturedAt).sort()[0];
  const stale=oldest && Date.now()-Date.parse(oldest)>86400000;
  $('#history-status').textContent=oldest?`История и оценки: ${timeFmt.format(new Date(oldest))}${stale?' · пора обновить':''}${complete?'':` · ${withHistory.length}/${items.length} модов`}`:'История ещё не загружена';
  const historyEnds=new Set(withHistory.map(i=>i.history.end));
  $('#day-header').textContent=historyEnds.size>1?'1 день':withHistory.length && withHistory[0].history.end!==new Date(Date.now()-86400000).toISOString().slice(0,10)?date(withHistory[0].history.end):'Вчера';
  $('#mod-rows').innerHTML=items.length?items.map(item=>{
    const h=item.history;const deprecated=/\[DEPRECATED\]/i.test(item.title);const title=item.title.replace(/\s*\[DEPRECATED\]/ig,'');
    const icon=/^https:\/\//.test(item.icon)?item.icon:'';
    return `<tr><td><div class="mod-cell"><img class="mod-icon" src="${esc(icon)}" alt="" width="48" height="48" loading="lazy"><div><a class="mod-name" href="https://steamcommunity.com/sharedfiles/filedetails/?id=${item.id}" target="_blank" rel="noreferrer">${esc(title)}</a><div class="mod-meta">${item.id}${deprecated?'<span class="deprecated">DEPRECATED</span>':''}</div></div></td><td class="count-primary" title="За всё время: ${n(item.lifetimeSubscriptions)} уникальных подписчиков">${n(item.subscriptions)}</td><td>${n(item.favorited)}</td><td title="${h?'По авторской статистике: '+timeFmt.format(new Date(h.capturedAt)):'История не загружена'}">${h?`<span class="rating-up">${n(h.votesUp)}</span><span class="rating-divider">/</span><span class="rating-down">${n(h.votesDown)}</span>`:'—'}</td><td>${n(item.views)}</td><td class="trend-column">${sparkline(h?.timeline)}</td>${[0,1,2].map(i=>`<td title="${h?`${i===0?'1 завершённый день':i===1?'7 завершённых дней':'30 завершённых дней'} по ${date(h.end)} включительно. Новые подписки, без вычета отписок.`:'История не загружена'}">${growth(h?.subscriptions[i])}</td>`).join('')}</tr>`;
  }).join(''):'<tr><td colspan="9" class="empty">Список ещё не получен. Нажми «Обновить счётчики».</td></tr>';
  if(sameEnd){const series=withHistory[0].history.timeline.map(([d],i)=>[d,withHistory.reduce((sum,item)=>sum+item.history.timeline[i][1],0)]);const max=Math.max(...series.map(p=>p[1]),1);$('#activity-chart').innerHTML=series.map(([d,v])=>`<div class="bar" tabindex="0" data-tip="${date(d)} · ${n(v)} новых подписок" aria-label="${date(d)}: ${n(v)} новых подписок"><div class="bar-fill" style="height:${Math.max(2,v/max*100)}%"></div></div>`).join('');$('#activity-total').textContent='+'+n(series.reduce((sum,p)=>sum+p[1],0));$('#chart-period').textContent=`${date(series[0][0])} — ${date(series.at(-1)[0])} · без вычета отписок`;$('#chart-axis').innerHTML=[0,7,14,21,29].map(i=>`<span>${date(series[i][0])}</span>`).join('');}
  else{$('#activity-chart').innerHTML='<span class="chart-empty">Импортируй историю Steam, чтобы увидеть график всех модов.</span>';$('#activity-total').textContent='—';$('#chart-axis').innerHTML='';}
}
async function refresh(){const button=$('#refresh-button');button.disabled=true;button.textContent='Обновляю…';error(null);try{render(await api('/api/refresh',{}));}catch(e){error(e.message);}finally{button.disabled=false;button.innerHTML='<span aria-hidden="true">↻</span> Обновить счётчики';}}
async function importHistory(payload){error(null);const next=await api('/api/import',payload);render(next);$('#history-json').value='';$('#status').textContent=`История ${next.imported} модов обновлена · ${timeFmt.format(new Date())}`;$('#history-panel').hidden=true;}
$('#refresh-button').addEventListener('click',refresh);
$('#history-button').addEventListener('click',()=>{$('#history-panel').hidden=!$('#history-panel').hidden;});
$('#close-history').addEventListener('click',()=>{$('#history-panel').hidden=true;});
$('#import-button').addEventListener('click',async()=>{const button=$('#import-button');button.disabled=true;try{await importHistory(JSON.parse($('#history-json').value));}catch(e){error(e.message);}finally{button.disabled=false;}});
const tooltip=document.createElement('div');tooltip.className='tooltip';tooltip.hidden=true;document.body.append(tooltip);
function showTip(target){if(!target?.dataset.tip)return;tooltip.textContent=target.dataset.tip;tooltip.hidden=false;const r=target.getBoundingClientRect();tooltip.style.left=Math.min(innerWidth-tooltip.offsetWidth-12,Math.max(12,r.x))+'px';tooltip.style.top=Math.max(8,r.y-tooltip.offsetHeight-8)+'px';}
$('#activity-chart').addEventListener('pointerover',e=>showTip(e.target.closest('.bar')));$('#activity-chart').addEventListener('focusin',e=>showTip(e.target.closest('.bar')));$('#activity-chart').addEventListener('pointerleave',()=>tooltip.hidden=true);$('#activity-chart').addEventListener('focusout',()=>tooltip.hidden=true);
fetch('/steam-sync.js').then(r=>r.text()).then(source=>{$('#sync-bookmark').href='javascript:'+encodeURIComponent(source.replace('__DASHBOARD_ORIGIN__',location.origin));});
$('#sync-bookmark').addEventListener('click',e=>{e.preventDefault();error('Перетащи «Статистика Workshop» на панель закладок и запускай её на странице Steam.');});
const nonce=location.hash.slice(1);
const narrow=matchMedia('(max-width:1150px)');
const resizeHeading=()=>document.querySelector('.group-row th').colSpan=narrow.matches?5:6;
narrow.addEventListener('change',resizeHeading);resizeHeading();
if(new URLSearchParams(location.search).has('steam-sync')&&window.opener&&/^[a-f0-9-]{36}$/.test(nonce)){
  $('#status').textContent='Получаю историю из открытой сессии Steam…';
  window.addEventListener('message',async event=>{if(event.origin!=='https://steamcommunity.com'||event.source!==window.opener||event.data?.nonce!==nonce)return;if(event.data.type==='workshop-error'){error(event.data.message);return;}if(event.data.type==='workshop-history'){try{await api('/api/refresh',{});await importHistory(event.data.payload);history.replaceState(null,'','/');}catch(e){error(e.message);}}});
  window.opener.postMessage({type:'workshop-ready',nonce},'https://steamcommunity.com');
}
try{render(await api('/api/dashboard'));if(!data.items.length)await refresh();}catch(e){error(e.message);}
setInterval(async()=>{try{render(await api('/api/dashboard'));}catch(e){error('Нет связи с локальным дашбордом. Запусти start.ps1.');}},60_000);
