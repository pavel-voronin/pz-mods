import {GameModels} from './models.js';
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const N=1024, art=$('#art'),ctx=art.getContext('2d'),overlay=$('#interaction'),ui=overlay.getContext('2d');
const catalog=await fetch('catalog.json').then(r=>r.json()), assets=new Map(catalog.map(a=>[a.id,a]));
let engine;
try{engine=new GameModels()}catch(e){$('#loading').textContent='Не удалось включить WebGL: '+e.message;throw e}
const clone=o=>JSON.parse(JSON.stringify(o)),uid=()=>crypto.randomUUID();
const canvas=()=>{const c=document.createElement('canvas');c.width=c.height=N;return c};
const blankLayer=(kind,extra={})=>({id:uid(),kind,name:'',x:512,y:512,scale:1,rotation:0,opacity:1,visible:true,locked:false,mask:[],...extra});
function initial(){return {version:1,sex:'Male',background:'#202923',background2:'#0c100e',gradient:true,yaw:-8,pitch:0,chestY:.675,span:.38,light:2.1,groupX:0,groupY:120,groupScale:1,groupRotation:0,layers:[
  blankLayer('body',{asset:'body_2_level2',name:'Тело зомби'}),
  blankLayer('shirt',{asset:'Shirt_Denim_0',name:'Джинсовая рубашка',opening:.4,tint:'#ffffff'}),
  blankLayer('item',{asset:'Wallet',name:'Кошелёк',x:705,y:472,scale:.24,rotation:-12,rx:90,ry:-15,rz:0}),
  blankLayer('item',{asset:'LighterDisposable',name:'Зажигалка',x:388,y:511,scale:.115,rotation:12,rx:90,ry:0,rz:90}),
  blankLayer('jacket',{asset:'Jacket_Leather_1',name:'Кожаная куртка',opening:.5,tint:'#ffffff'}),
  blankLayer('text',{name:'Название',text:'DEAD\nPOCKETS',x:512,y:166,size:128,font:'Impact',weight:'700',color:'#eee9d6',stroke:'#151914',strokeWidth:3,shadow:12,tracking:2,lineHeight:.94,align:'center'})
]}}
function validProject(p){
  if(!p||p.version!==1||!Array.isArray(p.layers)||p.layers.length>80)throw Error('Это не проект Dead Pockets');
  for(const l of p.layers){if(!['text','body','shirt','jacket','item'].includes(l.kind))throw Error('Неизвестный тип слоя');if(l.kind!=='text'&&!assets.has(l.asset))throw Error('Нет игровой модели '+l.asset);for(const k of ['x','y','scale','rotation','opacity'])if(!Number.isFinite(l[k]))throw Error('Некорректные координаты');if(!Array.isArray(l.mask)||l.mask.length>20000)throw Error('Некорректная маска')}
  return p;
}
let state=initial();
try{const local=localStorage.getItem('dead-pockets-studio-v1');const saved=local?JSON.parse(local):await fetch('/api/project').then(r=>r.json());if(saved)state=validProject(saved)}catch(e){console.warn('Restoring project:',e.message)}
let selected=state.layers.at(-1).id,tool='move',libraryKind='item',history=[],future=[],cache=new Map(),dirty=true,rendering=false,renderAgain=false,autosaveTimer,revision=0,drag=null,pointer=null;
let thumbnailQueue=Promise.resolve(),loaded=false;
const selectedLayer=()=>state.layers.find(l=>l.id===selected);
function toast(text,error=false){$('#toast').textContent=text;$('#toast').style.display='block';$('#toast').style.background=error?'#ffc2ac':'#d3dfbb';clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('#toast').style.display='none',4500)}
function snapshot(){history.push(clone(state));if(history.length>60)history.shift();future=[];updateUndo()}
function updateUndo(){$('#undo').disabled=!history.length;$('#redo').disabled=!future.length}
function changed(refresh=false){revision++;dirty=true;scheduleRender();saveSoon();if(refresh)refreshUI()}
function saveSoon(){clearTimeout(autosaveTimer);$('#saveStatus').textContent='Изменения…';autosaveTimer=setTimeout(async()=>{
  try{const data=JSON.stringify(state);localStorage.setItem('dead-pockets-studio-v1',data);const r=await fetch('/api/project',{method:'POST',headers:{'Content-Type':'application/json'},body:data});if(!r.ok)throw Error('Сервер недоступен');$('#saveStatus').textContent='Сохранено на этом компьютере'}catch(e){$('#saveStatus').textContent='Сохранено в браузере · '+e.message}
},600)}
function select(id){selected=id;renderLayers();renderProperties();drawOverlay()}
function layerLabel(l){return l.name||(l.kind==='text'?'Текст':assets.get(l.asset)?.label)||'Слой'}
const kindName={text:'Текст',body:'Тело',shirt:'Рубашка',jacket:'Верхняя одежда',item:'Предмет'};
function renderLayers(){
  const list=$('#layers');list.replaceChildren();
  [...state.layers].reverse().forEach(l=>{
    const el=document.createElement('div');el.className='layer'+(l.id===selected?' active':'')+(!l.visible?' hiddenlayer':'');el.draggable=true;el.dataset.id=l.id;
    const grip=document.createElement('span');grip.textContent='⠿';grip.className='grip';el.append(grip);
    const name=document.createElement('div');name.className='name';name.textContent=layerLabel(l);const small=document.createElement('small');small.textContent=kindName[l.kind];name.append(small);el.append(name);
    for(const [prop,title,a,b] of [['locked','Блокировка','◆','◇'],['visible','Видимость','◉','○']]){
      const btn=document.createElement('button');btn.textContent=l[prop]?a:b;btn.title=title;btn.onclick=e=>{e.stopPropagation();snapshot();l[prop]=!l[prop];changed(true)};el.append(btn);
    }
    el.onclick=()=>select(l.id);el.ondragstart=e=>e.dataTransfer.setData('text/plain',l.id);
    el.ondragover=e=>{e.preventDefault();el.classList.add('dragover')};el.ondragleave=()=>el.classList.remove('dragover');
    el.ondrop=e=>{e.preventDefault();const id=e.dataTransfer.getData('text/plain');const from=state.layers.findIndex(l=>l.id===id);if(from<0||id===l.id)return;snapshot();const [moved]=state.layers.splice(from,1);const target=state.layers.findIndex(x=>x.id===l.id);state.layers.splice(target+1,0,moved);changed(true)};
    list.append(el);
  });
}
function field(parent,label,input){const wrap=document.createElement('label');wrap.className='field';const span=document.createElement('span');span.textContent=label;wrap.append(span,input);parent.append(wrap);return input}
function changeControl(el,read,write,rerender=false){
  let started=false;
  const start=()=>{if(!started){snapshot();started=true}};
  el.addEventListener('input',()=>{start();write(read(el));changed()});
  el.addEventListener('change',()=>{if(!started){snapshot();write(read(el));changed()}started=false;if(rerender)renderProperties();renderLayers()});
  el.addEventListener('blur',()=>{started=false});
}
function numberField(parent,label,obj,key,min,max,step=1){
  const row=document.createElement('div');row.className='range';const range=document.createElement('input');range.type='range';range.min=min;range.max=max;range.step=step;range.value=obj[key];
  const number=document.createElement('input');number.type='number';number.min=min;number.max=max;number.step=step;number.value=obj[key];row.append(range,number);field(parent,label,row);
  [range,number].forEach(el=>changeControl(el,e=>Math.max(min,Math.min(max,Number(e.value))),v=>{obj[key]=v;range.value=number.value=v}));return row;
}
function colorField(parent,label,obj,key){const el=document.createElement('input');el.type='color';el.value=obj[key]||'#ffffff';field(parent,label,el);changeControl(el,e=>e.value,v=>obj[key]=v);return el}
function selectField(parent,label,choices,value,onchange){const el=document.createElement('select');for(const [val,text] of choices){const opt=new Option(text,val);el.add(opt)}el.value=value;field(parent,label,el);el.onchange=()=>{snapshot();onchange(el.value);changed(true)};return el}
function section(parent,text){const el=document.createElement('div');el.className='sectionlabel';el.textContent=text;parent.append(el)}
function renderProperties(){
  const p=$('#properties');p.replaceChildren();p.className='controls';const l=selectedLayer();
  $('#selectedTitle').textContent=l?layerLabel(l):'Свойства слоя';if(!l)return;
  const name=document.createElement('input');name.value=l.name;field(p,'Название слоя',name);changeControl(name,e=>e.value,v=>l.name=v);
  if(l.kind==='text'){
    const text=document.createElement('textarea');text.value=l.text;field(p,'Текст',text);changeControl(text,e=>e.value,v=>l.text=v);
    selectField(p,'Шрифт',[['Impact','Impact'],['Arial','Arial'],['Arial Black','Arial Black'],['Georgia','Georgia'],['Trebuchet MS','Trebuchet MS'],['Courier New','Courier New']],l.font,v=>l.font=v);
    selectField(p,'Начертание',[['400','Обычное'],['700','Жирное'],['900','Очень жирное']],l.weight||'700',v=>l.weight=v);
    numberField(p,'Размер шрифта',l,'size',12,300);numberField(p,'Межбуквенный интервал',l,'tracking',-8,20,.5);numberField(p,'Межстрочный интервал',l,'lineHeight',.7,1.8,.01);
    colorField(p,'Цвет текста',l,'color');numberField(p,'Толщина обводки',l,'strokeWidth',0,15,.5);colorField(p,'Обводка',l,'stroke');numberField(p,'Тень',l,'shadow',0,40);
  }else{
    selectField(p,'Заменить игровой материал',catalog.filter(a=>a.kind===l.kind).map(a=>[a.id,a.label]),l.asset,v=>{l.asset=v;l.name=assets.get(v).label});
    colorField(p,'Оттенок',l,'tint');
    if(l.kind==='shirt'||l.kind==='jacket'){l.opening??=0;numberField(p,'Раскрытие одежды',l,'opening',0,1,.01);const tip=document.createElement('p');tip.className='tip';tip.textContent='Раскрытие — маска для обложки поверх игровой одежды. Точный край можно доработать кистью.';p.append(tip)}
    if(l.kind==='item'){
      section(p,'Поворот модели');numberField(p,'Наклон X',l,'rx',-180,180);numberField(p,'Поворот Y',l,'ry',-180,180);numberField(p,'Поворот Z',l,'rz',-180,180);
    }
  }
  section(p,'Положение на холсте');const row=document.createElement('div');row.className='row2';p.append(row);
  for(const k of ['x','y']){const el=document.createElement('input');el.type='number';el.value=Math.round(l[k]);field(row,k.toUpperCase(),el);changeControl(el,e=>Number(e.value),v=>l[k]=v)}
  numberField(p,'Масштаб',l,'scale',.02,3,.01);numberField(p,'Поворот слоя',l,'rotation',-180,180);numberField(p,'Непрозрачность',l,'opacity',0,1,.01);
  const clear=document.createElement('button');clear.textContent='Очистить маску слоя';clear.disabled=!l.mask.length;clear.onclick=()=>{snapshot();l.mask=[];changed(true)};p.append(clear);
}
function renderScene(){
  const p=$('#sceneControls');p.replaceChildren();
  selectField(p,'Модель тела',[['Male','Мужская'],['Female','Женская']],state.sex,v=>state.sex=v);
  numberField(p,'Ракурс по горизонтали',state,'yaw',-70,70);numberField(p,'Ракурс по вертикали',state,'pitch',-25,25);
  numberField(p,'Центр кадра по высоте',state,'chestY',.45,.9,.005);numberField(p,'Область обзора (меньше — ближе)',state,'span',.23,.7,.005);
  numberField(p,'Свет',state,'light',.3,4,.1);numberField(p,'Масштаб всей композиции',state,'groupScale',.4,2,.01);
  numberField(p,'Сдвиг композиции X',state,'groupX',-500,500);numberField(p,'Сдвиг композиции Y',state,'groupY',-500,500);
  colorField(p,'Фон',state,'background');colorField(p,'Цвет краёв',state,'background2');
}
function refreshUI(){renderLayers();renderProperties();renderScene();updateUndo()}

function renderLibrary(){
  const q=$('#assetSearch').value.toLowerCase();const list=catalog.filter(a=>a.kind===libraryKind&&a.label.toLowerCase().includes(q));$('#assetCount').textContent=catalog.length+' вариантов';$('#library').replaceChildren();
  list.forEach(a=>{const btn=document.createElement('button');btn.className='asset';btn.title='Добавить: '+a.label;const img=document.createElement('img');img.src=a.texture;img.alt='';const label=document.createElement('span');label.textContent=a.label;btn.append(img,label);btn.onclick=()=>addAsset(a);$('#library').append(btn);
    // Thumbnail work uses the same renderer, so it runs only after the canvas
    // has finished rendering. Actual model thumbnails replace texture atlases.
    thumbnailQueue=thumbnailQueue.then(async()=>{while(rendering)await new Promise(r=>setTimeout(r,40));if(!btn.isConnected)return;const c=canvas();rendering=true;try{await engine.render(a,{opening:a.kind==='shirt'||a.kind==='jacket'?.6:0,rx:90,ry:0,rz:a.id==='LighterDisposable'?90:0,tint:'#ffffff'},{...state,sex:'Male',yaw:0,pitch:0,groupX:0,groupY:0,span:a.kind==='body'?.45:.42,chestY:.68},c);img.src=c.toDataURL()}catch(e){console.warn(a.id,e)}finally{rendering=false;if(dirty)scheduleRender()}});
  });
}
function addAsset(a){snapshot();const l=blankLayer(a.kind,{asset:a.id,name:a.label,tint:'#ffffff',opening:a.kind==='shirt'||a.kind==='jacket'?.7:0,rx:90,ry:0,rz:a.id==='LighterDisposable'?90:0,scale:a.kind==='item'?.22:1});
  const lastText=state.layers.findIndex(x=>x.kind==='text');state.layers.splice(lastText<0?state.layers.length:lastText,0,l);selected=l.id;changed(true)}
$$('#assetTabs button').forEach(b=>b.onclick=()=>{libraryKind=b.dataset.kind;$$('#assetTabs button').forEach(x=>x.classList.toggle('active',x===b));renderLibrary()});$('#assetSearch').oninput=renderLibrary;
$('#addText').onclick=()=>{snapshot();const l=blankLayer('text',{name:'Текст',text:'Новый текст',size:90,font:'Impact',weight:'700',color:'#eee9d6',stroke:'#151914',strokeWidth:0,shadow:0,tracking:0,lineHeight:1,align:'center'});state.layers.push(l);selected=l.id;changed(true)};
$('#duplicate').onclick=()=>{const l=selectedLayer();if(!l)return;snapshot();const copy={...clone(l),id:uid(),name:layerLabel(l)+' · копия',x:l.x+20,y:l.y+20};state.layers.splice(state.layers.indexOf(l)+1,0,copy);selected=copy.id;changed(true)};
function remove(){const l=selectedLayer();if(!l||l.locked)return;snapshot();state.layers=state.layers.filter(x=>x!==l);selected=state.layers.at(-1)?.id;changed(true)}$('#delete').onclick=remove;
function reorder(delta){const i=state.layers.findIndex(l=>l.id===selected),to=i+delta;if(i<0||to<0||to>=state.layers.length)return;snapshot();[state.layers[i],state.layers[to]]=[state.layers[to],state.layers[i]];changed(true)}$('#up').onclick=()=>reorder(1);$('#down').onclick=()=>reorder(-1);
function undo(){if(!history.length)return;future.push(clone(state));state=history.pop();if(!state.layers.some(l=>l.id===selected))selected=state.layers.at(-1)?.id;changed(true)}
function redo(){if(!future.length)return;history.push(clone(state));state=future.pop();changed(true)}$('#undo').onclick=undo;$('#redo').onclick=redo;
$('#reset').onclick=()=>{snapshot();state=initial();selected=state.layers.at(-1).id;changed(true)};

function layerMatrix(l){let m=new DOMMatrix();if(l.kind!=='text')m=m.translate(512+state.groupX,512+state.groupY).rotate(state.groupRotation||0).scale(state.groupScale).translate(-512,-512);return m.translate(l.x,l.y).rotate(l.rotation).scale(l.scale).translate(-512,-512)}
function point(m,x,y){const p=new DOMPoint(x,y).matrixTransform(m);return {x:p.x,y:p.y}}
function drawText(l,c){const t=c.getContext('2d');t.clearRect(0,0,N,N);t.textAlign='center';t.textBaseline='middle';t.font=`${l.weight||700} ${l.size}px "${l.font}"`;t.letterSpacing=(l.tracking||0)+'px';t.fillStyle=l.color;t.strokeStyle=l.stroke;t.lineWidth=l.strokeWidth||0;t.lineJoin='round';
  const lines=(l.text||'').split('\n'),spacing=l.size*(l.lineHeight||1);let width=0;
  for(let i=0;i<lines.length;i++){const y=512+(i-(lines.length-1)/2)*spacing;const metrics=t.measureText(lines[i]);width=Math.max(width,metrics.width);t.shadowColor='#000c';t.shadowBlur=l.shadow||0;t.shadowOffsetY=(l.shadow||0)*.2;if(l.strokeWidth)t.strokeText(lines[i],512,y);t.fillText(lines[i],512,y)}
  return {x:512-width/2-8,y:512-lines.length*spacing/2-8,w:width+16,h:lines.length*spacing+16};
}
function applyMask(l,source,dest){const d=dest.getContext('2d');d.clearRect(0,0,N,N);d.drawImage(source,0,0);if(!l.mask.length)return;
  const mask=canvas(),m=mask.getContext('2d');m.fillStyle='#fff';m.fillRect(0,0,N,N);m.lineCap=m.lineJoin='round';
  for(const s of l.mask){m.globalCompositeOperation=s.mode==='restore'?'source-over':'destination-out';m.strokeStyle=m.fillStyle='#fff';const diameter=s.size+(s.mode==='restore'?3:0);m.lineWidth=diameter;m.beginPath();s.points.forEach(([x,y],i)=>i?m.lineTo(x,y):m.moveTo(x,y));m.stroke();if(s.points.length===1){m.beginPath();m.arc(s.points[0][0],s.points[0][1],diameter/2,0,Math.PI*2);m.fill()}}
  d.globalCompositeOperation='destination-in';d.drawImage(mask,0,0);d.globalCompositeOperation='source-over';
}
function bounds(c){const d=c.getContext('2d').getImageData(0,0,N,N).data;let x1=N,y1=N,x2=0,y2=0;for(let y=0;y<N;y+=4)for(let x=0;x<N;x+=4)if(d[(y*N+x)*4+3]>10){x1=Math.min(x1,x);x2=Math.max(x2,x);y1=Math.min(y1,y);y2=Math.max(y2,y)}return x1>x2?{x:0,y:0,w:0,h:0}:{x:x1,y:y1,w:x2-x1+4,h:y2-y1+4}}
async function prepareLayer(l){
  let c=cache.get(l.id);if(!c){c={raw:canvas(),masked:canvas(),sig:null,maskSig:null};cache.set(l.id,c)}
  const sig=l.kind==='text'?JSON.stringify([l.text,l.size,l.font,l.weight,l.tracking,l.lineHeight,l.color,l.stroke,l.strokeWidth,l.shadow]):JSON.stringify([l.asset,state.sex,state.yaw,state.pitch,state.chestY,state.span,state.light,l.tint,l.opening,l.rx,l.ry,l.rz]);
  if(c.sig!==sig){if(l.kind==='text')c.bounds=drawText(l,c.raw);else{await engine.render(assets.get(l.asset),l,state,c.raw);c.bounds=bounds(c.raw)}c.sig=sig;c.maskSig=null}
  const maskSig=JSON.stringify(l.mask);if(c.maskSig!==maskSig){applyMask(l,c.raw,c.masked);c.maskSig=maskSig;c.pixels=c.masked.getContext('2d').getImageData(0,0,N,N).data}
  return c;
}
function drawBackground(){ctx.clearRect(0,0,N,N);if(state.gradient){const g=ctx.createRadialGradient(500,420,50,512,512,740);g.addColorStop(0,state.background);g.addColorStop(1,state.background2);ctx.fillStyle=g}else ctx.fillStyle=state.background;ctx.fillRect(0,0,N,N)}
function composite(){drawBackground();for(const l of state.layers){const c=cache.get(l.id);if(!l.visible||!c)continue;ctx.save();const m=layerMatrix(l);ctx.setTransform(m.a,m.b,m.c,m.d,m.e,m.f);ctx.globalAlpha=l.opacity;ctx.drawImage(c.masked,0,0);ctx.restore()}}
function scheduleRender(){if(rendering){renderAgain=true;return}requestAnimationFrame(render)}
async function render(){if(rendering||!dirty)return;rendering=true;dirty=false;const startRevision=revision;
  try{for(const l of state.layers)if(l.visible)await prepareLayer(l);composite();drawOverlay();$('#loading').style.display='none';loaded=true;window.studioReady=true;}
  catch(e){console.error(e);toast('Ошибка модели: '+e.message,true);$('#loading').textContent='Ошибка загрузки: '+e.message}
  finally{rendering=false;if(renderAgain||revision!==startRevision){renderAgain=false;dirty=true;scheduleRender()}}
}
function selectionBox(){const l=selectedLayer(),c=l&&cache.get(l.id);if(!l||!c||!l.visible||!c.bounds.w)return null;const b=c.bounds,m=layerMatrix(l);return {l,c,m,points:[[b.x,b.y],[b.x+b.w,b.y],[b.x+b.w,b.y+b.h],[b.x,b.y+b.h]].map(([x,y])=>point(m,x,y))}}
function drawOverlay(){ui.clearRect(0,0,N,N);const ratio=N/overlay.clientWidth,box=selectionBox();
  if($('#guides').checked){ui.strokeStyle='#dceab93a';ui.lineWidth=ratio;ui.setLineDash([4*ratio,6*ratio]);ui.strokeRect(64,64,896,896);ui.beginPath();ui.moveTo(512,0);ui.lineTo(512,1024);ui.moveTo(0,512);ui.lineTo(1024,512);ui.stroke();ui.setLineDash([])}
  if(box&&tool==='move'){ui.strokeStyle=box.l.locked?'#999':'#dceaa1';ui.lineWidth=ratio;ui.setLineDash([4*ratio,3*ratio]);ui.beginPath();box.points.forEach((p,i)=>i?ui.lineTo(p.x,p.y):ui.moveTo(p.x,p.y));ui.closePath();ui.stroke();ui.setLineDash([]);if(!box.l.locked)for(const p of box.points){ui.fillStyle='#1b201a';ui.fillRect(p.x-4*ratio,p.y-4*ratio,8*ratio,8*ratio);ui.strokeRect(p.x-4*ratio,p.y-4*ratio,8*ratio,8*ratio)}}
  if(pointer&&(tool==='erase'||tool==='restore')){ui.lineWidth=ratio;ui.strokeStyle=tool==='erase'?'#ffa28f':'#dceaa1';ui.beginPath();ui.arc(pointer.x,pointer.y,Number($('#brushSize').value)/2,0,Math.PI*2);ui.stroke()}
}
function hit(p){for(const l of [...state.layers].reverse()){if(!l.visible||l.locked||l.opacity<.05)continue;const c=cache.get(l.id);if(!c)continue;const q=point(layerMatrix(l).inverse(),p.x,p.y),x=Math.floor(q.x),y=Math.floor(q.y);if(x>=0&&y>=0&&x<N&&y<N&&c.pixels[(y*N+x)*4+3]>25)return l}return null}
const eventPoint=e=>{const r=overlay.getBoundingClientRect();return {x:(e.clientX-r.left)/r.width*N,y:(e.clientY-r.top)/r.height*N}};
function toolSelect(t){tool=t;$$('[data-tool]').forEach(b=>b.classList.toggle('active',b.dataset.tool===t));$('.brush').hidden=t!=='erase'&&t!=='restore';overlay.style.cursor=t==='group'?'grab':t==='move'?'default':'crosshair';drawOverlay()}
$$('[data-tool]').forEach(b=>b.onclick=()=>toolSelect(b.dataset.tool));$('#guides').onchange=drawOverlay;$('#brushSize').oninput=()=>{$('#brushValue').textContent=$('#brushSize').value;drawOverlay()};
overlay.onpointerdown=e=>{if(!loaded)return;overlay.focus();const p=eventPoint(e);pointer=p;const l=selectedLayer();
  if(tool==='group'){snapshot();drag={type:'group',start:p,x:state.groupX,y:state.groupY};overlay.setPointerCapture(e.pointerId);return}
  if(tool==='erase'||tool==='restore'){
    if(!l||l.locked||!l.visible){toast('Выбери видимый разблокированный слой');return}snapshot();const inv=layerMatrix(l).inverse(),q=point(inv,p.x,p.y);const effective=l.scale*(l.kind==='text'?1:state.groupScale);const stroke={mode:tool,size:Number($('#brushSize').value)/effective,points:[[q.x,q.y]]};l.mask.push(stroke);drag={type:'mask',stroke,inv};overlay.setPointerCapture(e.pointerId);changed();return;
  }
  const box=selectionBox();if(box&&!l.locked){const threshold=12*N/overlay.clientWidth;const index=box.points.findIndex(q=>Math.hypot(q.x-p.x,q.y-p.y)<threshold);if(index>=0){snapshot();const center=point(layerMatrix(l),512,512);drag={type:'scale',layer:l,center,startDistance:Math.hypot(p.x-center.x,p.y-center.y),scale:l.scale};overlay.setPointerCapture(e.pointerId);return}}
  const found=hit(p);if(!found){selected=null;refreshUI();drawOverlay();return}select(found.id);snapshot();const groupScale=found.kind==='text'?1:state.groupScale;drag={type:'move',layer:found,start:p,x:found.x,y:found.y,groupScale};overlay.setPointerCapture(e.pointerId);
};
overlay.onpointermove=e=>{const p=eventPoint(e);pointer=p;if(!drag){drawOverlay();return}
  if(drag.type==='group'){state.groupX=drag.x+p.x-drag.start.x;state.groupY=drag.y+p.y-drag.start.y}
  if(drag.type==='move'){drag.layer.x=drag.x+(p.x-drag.start.x)/drag.groupScale;drag.layer.y=drag.y+(p.y-drag.start.y)/drag.groupScale}
  if(drag.type==='scale')drag.layer.scale=Math.max(.02,Math.min(3,drag.scale*Math.hypot(p.x-drag.center.x,p.y-drag.center.y)/Math.max(1,drag.startDistance)));
  if(drag.type==='mask'){const q=point(drag.inv,p.x,p.y);drag.stroke.points.push([q.x,q.y])}changed();
};
function endDrag(){if(!drag)return;drag=null;renderProperties();renderScene()};overlay.onpointerup=endDrag;overlay.onpointercancel=endDrag;overlay.onpointerleave=()=>{pointer=null;drawOverlay()};
overlay.addEventListener('wheel',e=>{const l=selectedLayer();if(!l||l.locked)return;e.preventDefault();if(!overlay.wheelTimer)snapshot();clearTimeout(overlay.wheelTimer);l.scale=Math.min(3,Math.max(.02,l.scale*Math.exp(-e.deltaY*(e.shiftKey?.0003:.001))));changed();overlay.wheelTimer=setTimeout(()=>{overlay.wheelTimer=null;renderProperties()},220)},{passive:false});
document.onkeydown=e=>{const editing=['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName);if(editing)return;
  if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();e.shiftKey?redo():undo();return}
  if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='s'){e.preventDefault();saveProject();return}
  if(e.key==='Delete'){remove();return}const l=selectedLayer();if(l&&!l.locked&&['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();if(!e.repeat)snapshot();const n=e.shiftKey?10:1;if(e.key==='ArrowLeft')l.x-=n;if(e.key==='ArrowRight')l.x+=n;if(e.key==='ArrowUp')l.y-=n;if(e.key==='ArrowDown')l.y+=n;changed();renderProperties()}
};

function download(url,name){const a=document.createElement('a');a.href=url;a.download=name;a.click()}
function saveProject(){download(URL.createObjectURL(new Blob([JSON.stringify(state,null,2)],{type:'application/json'})),'dead-pockets-composition.json');toast('Проект сохранён. Его можно открыть снова в редакторе.')}
$('#saveProject').onclick=saveProject;$('#loadProject').onclick=()=>$('#projectFile').click();$('#projectFile').onchange=async e=>{try{const p=validProject(JSON.parse(await e.target.files[0].text()));snapshot();state=p;selected=state.layers.at(-1)?.id;changed(true);toast('Проект открыт')}catch(err){toast(err.message,true)}e.target.value=''};
async function exportPNG(size){
  while(rendering)await new Promise(r=>setTimeout(r,40));if(dirty)await render();
  const c=document.createElement('canvas');c.width=c.height=size;c.getContext('2d').drawImage(art,0,0,size,size);
  const r=await fetch('/api/export',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({size,png:c.toDataURL('image/png')})});const result=await r.json();if(!r.ok)throw Error(result.error);
  return result;
}
$('#export').onclick=async()=>{const b=$('#export');b.disabled=true;try{const size=Number($('#exportSize').value),r=await exportPNG(size);download(r.url+'?t='+Date.now(),r.name);toast(`PNG ${size} × ${size} · ${Math.round(r.bytes/1024)} КБ сохранён`)}catch(e){toast(e.message,true)}finally{b.disabled=false}};
function sizeStage(){const wrap=$('.canvaswrap'),s=Math.floor(Math.min(wrap.clientWidth-36,wrap.clientHeight-36));$('#stage').style.width=Math.max(200,s)+'px';$('#stage').style.height=Math.max(200,s)+'px';drawOverlay()}
new ResizeObserver(sizeStage).observe($('.canvaswrap'));refreshUI();sizeStage();await render();renderLibrary();saveSoon();
// A narrow inspection surface for the local editor's regression checks.
window.studio={getState:()=>clone(state),select,addAsset:(id)=>addAsset(assets.get(id)),setState:p=>{state=validProject(clone(p));selected=state.layers.at(-1)?.id;changed(true)},render:async()=>{while(rendering)await new Promise(r=>setTimeout(r,40));dirty=true;await render()},exportPNG,undo,redo,toolSelect,catalog,layerMatrix:id=>layerMatrix(state.layers.find(l=>l.id===id)).toString()};
