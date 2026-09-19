import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const gameRoot = process.env.PZ_GAME_ROOT ?? 'C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid';
const clean = (text) => text.replace(/\/\*[\s\S]*?\*\//g, match => match.replace(/[^\r\n]/g, ' ')).replace(/--[^\n]*|\/\/[^\n]*/g, '');
function closing(text, start) {
  let depth=1, quote='';
  for(let i=start+1;i<text.length;i++) {
    const c=text[i];
    if(quote) { if(c===quote && text[i-1]!=='\\') quote=''; continue; }
    if(c==='"'||c==="'") {quote=c;continue;}
    if(c==='{') depth++;
    if(c==='}' && --depth===0) return i;
  }
  throw new Error('Unclosed source block');
}
export function sourceBlocks(text, pattern) {
  const blocks=[];
  for(const match of text.matchAll(pattern)) {
    const start=match.index+match[0].lastIndexOf('{'), end=closing(text,start);
    blocks.push({name:match[1],body:text.slice(start+1,end),line:text.slice(0,match.index).split('\n').length});
  }
  return blocks;
}
const props = (body) => Object.fromEntries([...body.split(/\battachment\s/)[0].matchAll(/^\s*(\w+)\s*=\s*([^,\r\n]+)[,\r\n]/gm)]
  .map((m)=>[m[1].toLowerCase(),m[2].trim()]));
const listFiles = (folder) => fs.readdirSync(folder,{withFileTypes:true}).flatMap((e)=>e.isDirectory()?listFiles(path.join(folder,e.name)):[path.join(folder,e.name)]);
const read = (relative) => fs.readFileSync(path.join(gameRoot,relative),'utf8');
const hash = (text) => createHash('sha256').update(text).digest('hex');
const excludedNotebook = /^(Notebook|Notepad|Diary|Journal|EmptyNote|Sketchbook)/i;

export function importPocketLoot() {
  const sourcePath='media/lua/server/Items/Distributions.lua', original=read(sourcePath);
  const source=clean(original);
  const pools=sourceBlocks(source,/\b(inventorymale|inventoryfemale|Outfit_\w+)\s*=\s*\{/g).map((block)=>({
    id:block.name,source:sourcePath,line:block.line,
    rolls:Number(block.body.match(/rolls\s*=\s*(\d+)/)?.[1] ?? 1),
    entries:[...block.body.matchAll(/"([\w.]+)"\s*,\s*([\d.]+)/g)].map((m)=>({id:m[1].includes('.')?m[1]:'Base.'+m[1],weight:Number(m[2])})),
  }));
  const definitions=new Map(), models=new Map();
  for(const file of listFiles(path.join(gameRoot,'media/scripts/generated')).filter((f)=>f.endsWith('.txt'))) {
    const text=clean(fs.readFileSync(file,'utf8')), relative=path.relative(gameRoot,file).replaceAll('\\','/');
    for(const block of sourceBlocks(text,/\bitem\s+(\w+)\s*\{/g)) definitions.set('Base.'+block.name,{...props(block.body),source:relative,line:block.line});
    for(const block of sourceBlocks(text,/\bmodel\s+([\w.]+)\s*\{/g)) models.set(block.name,{...props(block.body),source:relative,line:block.line});
  }
  const translations=JSON.parse(read('media/lua/shared/Translate/RU/ItemName.json'));
  const names=[...new Set(pools.flatMap((pool)=>pool.entries.map((entry)=>entry.id)))].sort();
  const items={}, excluded=[];
  for(const id of names) {
    const name=id.split('.').at(-1), d=definitions.get(id);
    let reason='';
    if(!d) reason='missing item definition';
    else if(excludedNotebook.test(name)) reason='notebook removed by request';
    else if(!Number.isFinite(Number(d.weight)) || Number(d.weight)>1.5) reason='weight over 1.5 or unspecified';
    else if((d.clothingitem || /clothing/.test(d.itemtype)) && !/Locket|Necklace|Ring|Earring|Gloves|Glasses|Mask/.test(name)) reason='worn clothing, not pocket loot';
    else if(/container/.test(d.itemtype) && !/^(Wallet|KeyRing)/.test(name)) reason='external container';
    else if(d.twohandweapon==='TRUE' || d.twohandweapon==='true' || /BigWeapon|Rifle|Shotgun|Shovel|Spear|Guitar/i.test(d.attachmenttype??'')
      || /shotgun|rifle|longblade|spear|axe|longblunt/i.test(d.categories??'')) reason='external or long weapon';
    const modelNames=d ? (d.worldstaticmodelsbyindex ?? d.worldstaticmodel ?? d.weaponspritesbyindex ?? d.weaponsprite ?? '').split(';') : [];
    let asset;
    for(const modelName of modelNames) {
      const m=models.get(modelName.replace(/^Base\./,'')); if(!m?.mesh) continue;
      const modelFile=['.fbx','.x'].map((ext)=>'media/models_X/'+m.mesh+ext).find((file)=>fs.existsSync(path.join(gameRoot,file)));
      const textureFile='media/textures/'+(m.texture??m.mesh)+'.png';
      if(modelFile && fs.existsSync(path.join(gameRoot,textureFile))) {
        asset={modelName,modelFile,textureFile,scale:Number(m.scale??1),modelSource:m.source,modelLine:m.line};break;
      }
    }
    if(!reason && !asset) reason='no complete world mesh/texture in installed game';
    if(reason) {excluded.push({id,reason});continue;}
    const weapon=/weapon/.test(d.itemtype), label=translations[id] ?? name;
    items[id]={id,label,category:weapon?'Оружие':/food/.test(d.itemtype)?'Еда':/drainable/.test(d.itemtype)?'Расходники':'Предметы',
      model:'/pz-game/pocket/models/'+name+path.extname(asset.modelFile),
      texture:'/pz-game/pocket/textures/'+name+'.png',
      scale:asset.scale,mass:Math.max(.001,Number(d.weight)),airDrag:.03,restitution:.025,
      source:d.source,line:d.line,...asset,weapon,
      pools:pools.filter((pool)=>pool.entries.some((e)=>e.id===id)).map((pool)=>pool.id),
    };
  }
  const result={source:sourcePath,sha256:hash(original),weightLimit:1.5,
    note:'Pocket tables only. AttachedWeaponDefinitions is deliberately excluded. Weights are source draw weights, not percentages.',
    items,pools:pools.map((pool)=>({...pool,entries:pool.entries.filter((e)=>items[e.id])})).filter((pool)=>pool.entries.length),excluded};
  return result;
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const catalog=importPocketLoot();
  fs.writeFileSync(path.join(project,'app/pz-pocket-loot.json'),JSON.stringify(catalog,null,2)+'\n');
  console.log(JSON.stringify({items:Object.keys(catalog.items).length,pools:catalog.pools.length,weapons:Object.values(catalog.items).filter((x)=>x.weapon).map((x)=>x.id),excluded:catalog.excluded},null,2));
}
