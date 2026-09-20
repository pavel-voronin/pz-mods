import http from 'node:http';
import {readFile, writeFile, mkdir, rename} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {OWNER, APP_ID, PROFILE, normalizeHistory, historySummary} from './stats.mjs';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const DATA = path.join(ROOT, '.data');
const PORT = Number(process.env.WORKSHOP_DASHBOARD_PORT || 8779);
const ORIGIN = `http://127.0.0.1:${PORT}`;
await mkdir(DATA, {recursive:true});
const load = async (name, fallback) => {try {return JSON.parse(await readFile(path.join(DATA,name),'utf8'));} catch(error) {if(error.code==='ENOENT')return fallback; throw error;}};
const save = async (name, value) => {await writeFile(path.join(DATA,name+'.tmp'),JSON.stringify(value));await rename(path.join(DATA,name+'.tmp'),path.join(DATA,name));};
let state = await load('current.json', {items:[],capturedAt:null});
let histories = await load('history.json', {});
let lastError = null;
let refreshPromise;
let importPromise;
async function steamFetch(url, options={}) {
  const response = await fetch(url, {...options, signal:AbortSignal.timeout(25000)});
  if (!response.ok) throw new Error(`Steam ответил HTTP ${response.status}. Сохранённые данные не изменены.`);
  return response;
}
async function discoverItems() {
  const ids = new Set();
  let expected = null;
  for(let page=1;page<=30;page++) {
    const html=await (await steamFetch(PROFILE+`&l=english&p=${page}`)).text();
    const total=html.match(/Showing\s+[\d,]+\s*-\s*[\d,]+\s+of\s+([\d,]+)\s+entries/);
    if(total)expected=Number(total[1].replaceAll(',',''));
    const found=[...html.matchAll(/sharedfiles\/filedetails\/\?id=(\d+)/g)].map(m=>m[1]);
    const before=ids.size;
    found.forEach(id=>ids.add(id));
    if(expected!==null && ids.size>=expected)break;
    if(ids.size===before)break;
  }
  if(!ids.size || (expected!==null && ids.size<expected))throw new Error('Steam не вернул полный список модов. Сохранённые данные не изменены.');
  return [...ids];
}
async function refresh() {
  if(refreshPromise)return refreshPromise;
  refreshPromise=(async()=>{
    const ids=await discoverItems();
    const items=[];
    for(let offset=0;offset<ids.length;offset+=50) {
      const batch=ids.slice(offset,offset+50);
      const body=new URLSearchParams({itemcount:String(batch.length)});
      batch.forEach((id,i)=>body.set(`publishedfileids[${i}]`,id));
      const json=await (await steamFetch('https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/',{method:'POST',body})).json();
      const details=json.response?.publishedfiledetails;
      if(!Array.isArray(details) || details.length!==batch.length || details.some(d=>d.result!==1))throw new Error('Steam вернул неполные данные. Предыдущий снимок сохранён.');
      for(const d of details) {
        if(d.creator!==OWNER || d.consumer_app_id!==APP_ID)continue;
        for(const field of ['subscriptions','favorited','views','lifetime_subscriptions','lifetime_favorited'])if(!Number.isSafeInteger(d[field])||d[field]<0)throw new Error('Steam вернул некорректные счётчики.');
        items.push({id:d.publishedfileid,title:d.title,icon:d.preview_url,subscriptions:d.subscriptions,favorited:d.favorited,views:d.views,lifetimeSubscriptions:d.lifetime_subscriptions,lifetimeFavorites:d.lifetime_favorited,createdAt:d.time_created,updatedAt:d.time_updated});
      }
    }
    if(!items.length)throw new Error('Не найдены авторские моды Project Zomboid.');
    const next={items,capturedAt:new Date().toISOString()};
    await save('current.json',next);
    const snapshots=await load('snapshots.json',[]);
    // At most one successful snapshot per hour; keep a year for real net-change baselines.
    const hour=next.capturedAt.slice(0,13);
    const retained=snapshots.filter(s=>s.capturedAt.slice(0,13)!==hour && Date.parse(s.capturedAt)>Date.now()-366*86400000);
    retained.push({capturedAt:next.capturedAt,items:items.map(({id,subscriptions,favorited,views})=>({id,subscriptions,favorited,views}))});
    await save('snapshots.json',retained);
    state=next;lastError=null;
  })().catch(error=>{lastError=error.message;throw error;}).finally(()=>{refreshPromise=null;});
  return refreshPromise;
}
function dashboard() {
  return {owner:'kolpaque',profile:PROFILE,capturedAt:state.capturedAt,lastError,
    items:state.items.map(item=>({...item,history:historySummary(histories[item.id])})),
  };
}
const files={'/':['index.html','text/html; charset=utf-8'],'/app.js':['app.js','text/javascript; charset=utf-8'],'/styles.css':['styles.css','text/css; charset=utf-8'],'/steam-sync.js':['steam-sync.js','text/javascript; charset=utf-8']};
function json(res,status,data){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(data));}
async function readJson(req) {
  let body='';
  for await(const part of req){body+=part;if(Buffer.byteLength(body)>5_000_000)throw new Error('Импорт слишком большой.');}
  return JSON.parse(body);
}
const server=http.createServer(async(req,res)=>{
  try {
    if(req.headers.host!==`127.0.0.1:${PORT}` && req.headers.host!==`localhost:${PORT}`){json(res,403,{error:'Недопустимый адрес.'});return;}
    const url=new URL(req.url,ORIGIN);
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Referrer-Policy','no-referrer');
    res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https: data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    if(req.method==='GET' && url.pathname==='/api/dashboard'){json(res,200,dashboard());return;}
    if(req.method==='POST') {
      if(req.headers.origin!==ORIGIN && req.headers.origin!==`http://localhost:${PORT}`){json(res,403,{error:'Обновление доступно только со страницы дашборда.'});return;}
      if(url.pathname==='/api/refresh'){await refresh();json(res,200,dashboard());return;}
      if(url.pathname==='/api/import') {
        if(importPromise){json(res,409,{error:'Импорт уже выполняется.'});return;}
        const data=await readJson(req);
        if(!Array.isArray(data.items)||!data.items.length||data.items.length>500)throw new Error('Нет данных модов для импорта.');
        if(!state.items.length)await refresh();
        const allowed=new Set(state.items.map(item=>item.id));
        const timestamp=data.capturedAt===undefined?Date.now():Date.parse(data.capturedAt);
        if(!Number.isFinite(timestamp)||timestamp>Date.now()+60000)throw new Error('Некорректная дата выгрузки.');
        const capturedAt=new Date(timestamp).toISOString();
        const normalized=data.items.map(raw=>{
          if(!allowed.has(raw.id))throw new Error('В импорте есть мод, отсутствующий в авторском списке. Обновите список модов.');
          return normalizeHistory(raw,capturedAt);
        });
        if(new Set(normalized.map(item=>item.id)).size!==normalized.length)throw new Error('Повторяющиеся моды в импорте.');
        const merged={...histories};normalized.forEach(item=>{merged[item.id]=item;});
        importPromise=save('history.json',merged);
        try{await importPromise;histories=merged;}finally{importPromise=null;}
        json(res,200,{...dashboard(),imported:normalized.length});return;
      }
    }
    if(req.method==='GET' && files[url.pathname]) {
      const [filename,type]=files[url.pathname];res.writeHead(200,{'Content-Type':type,'Cache-Control':'no-cache'});res.end(await readFile(path.join(ROOT,'public',filename)));return;
    }
    json(res,404,{error:'Страница не найдена.'});
  } catch(error){json(res,502,{error:error.message});}
});
server.listen(PORT,'127.0.0.1',()=>console.log(`Workshop dashboard: ${ORIGIN}`));
refresh().catch(error=>console.error(error.message));
setInterval(()=>refresh().catch(error=>console.error(error.message)),15*60*1000).unref();
