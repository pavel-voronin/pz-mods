(async()=>{
  if(location.origin!=='https://steamcommunity.com'){alert('Открой свою мастерскую на steamcommunity.com и нажми эту закладку.');return;}
  const origin='__DASHBOARD_ORIGIN__';
  const nonce=crypto.randomUUID();
  const popup=window.open(origin+'/?steam-sync=1#'+nonce,'_blank');
  if(!popup){alert('Разреши открыть вкладку дашборда и нажми закладку ещё раз.');return;}
  let ready=false,payload=null,failure=null;
  const deliver=()=>{if(!ready)return;if(failure)popup.postMessage({type:'workshop-error',nonce,message:failure},origin);else if(payload)popup.postMessage({type:'workshop-history',nonce,payload},origin);};
  const listener=event=>{if(event.origin===origin&&event.source===popup&&event.data?.type==='workshop-ready'&&event.data.nonce===nonce){ready=true;deliver();}};
  window.addEventListener('message',listener);
  const fetchHtml=async url=>{const response=await fetch(url,{credentials:'same-origin'});if(!response.ok)throw Error('Steam ответил HTTP '+response.status);return new DOMParser().parseFromString(await response.text(),'text/html');};
  try{
    const ids=new Set();let expected=null;
    for(let page=1;page<=30;page++){
      const doc=await fetchHtml('/id/huzeru/myworkshopfiles/?appid=108600&numperpage=30&l=english&p='+page);
      const text=doc.body.textContent;
      const total=text.match(/Showing\s+[\d,]+\s*-\s*[\d,]+\s+of\s+([\d,]+)\s+entries/);
      if(total)expected=Number(total[1].replaceAll(',',''));
      const before=ids.size;
      for(const a of doc.querySelectorAll('a[href*="sharedfiles/filedetails/?id="]')){const id=new URL(a.href).searchParams.get('id');if(/^\d+$/.test(id))ids.add(id);}
      if(expected!==null&&ids.size>=expected)break;
      if(before===ids.size)break;
    }
    if(!ids.size||(expected!==null&&ids.size<expected))throw Error('Steam не вернул полный список модов.');
    const items=[];
    for(const id of ids){
      const doc=await fetchHtml('/sharedfiles/filedetails/stats/'+id+'?l=english');
      const script=Array.from(doc.scripts).find(s=>/cumulativeSubscriptionsData\s*=/.test(s.textContent))?.textContent;
      const match=script?.match(/dailyData\s*=\s*(\[[\s\S]*?\])\s*;/);
      const table=Array.from(doc.querySelectorAll('table')).map(t=>Array.from(t.querySelectorAll('tr')).map(r=>Array.from(r.querySelectorAll('td,th')).map(c=>c.textContent.trim()).join('\t')).join('\n')).find(t=>/Negative ratings/.test(t));
      if(!match||!table)throw Error('Нет доступа к статистике '+id+'. Войди в Steam под аккаунтом kolpaque.');
      items.push({id,daily:JSON.parse(match[1].replace(/'/g,'"')),table});
    }
    payload={items,capturedAt:new Date().toISOString()};deliver();
  }catch(e){failure=e.message;deliver();}
  setTimeout(()=>window.removeEventListener('message',listener),300000);
})();
