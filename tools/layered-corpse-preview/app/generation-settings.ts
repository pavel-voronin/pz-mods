export const GENERATION_STORAGE_KEY = 'layered-corpse:generation:v1';
export const defaultGenerationLocks = {floor:false,pose:false,body:false,hair:false,hairColor:false,clothing:false,loot:false};
export type GenerationSettings<G extends string = string> = {
  selection: {body:string;pose:string;hair:string;hairColor:string};
  modelSet:'tomb'|'vanilla'; floor:string;
  garments:Array<{id:number;type:G;variant:string;fabricStiffness?:number}>;
  lootItems:Array<{id:number;kind:string;layer:number}>;
  locks:typeof defaultGenerationLocks; lockedGarmentIds:number[];
  addType:G; addLootKind:string;
};
type Catalog = {bodies:string[];poses:string[];floors:string[];
  hair:(sex:'m'|'f')=>string[];variants:(type:string,sex:'m'|'f')=>string[];
  loot:(kind:string,sex:'m'|'f')=>string|undefined};
const record=(v:unknown):v is Record<string,unknown>=>!!v && typeof v==='object' && !Array.isArray(v);
const id=(v:unknown):v is number=>Number.isSafeInteger(v) && Number(v)>0 && Number(v)<1e9;

/** Validate storage as untrusted input; obsolete catalog entries are discarded. */
export function decodeGenerationSettings<G extends string>(raw:string|null,defaults:GenerationSettings<G>,catalog:Catalog):GenerationSettings<G> {
  const result=structuredClone(defaults);
  try {
    const saved:unknown=JSON.parse(raw??'null');
    if(!record(saved) || saved.version!==1 || !record(saved.settings))return result;
    const s=saved.settings, selection=record(s.selection)?s.selection:{};
    if(typeof selection.body==='string' && catalog.bodies.includes(selection.body))result.selection.body=selection.body;
    const sex=result.selection.body[0] as 'm'|'f';
    for(const key of ['pose','hair'] as const) {
      const options=key==='pose'?catalog.poses:catalog.hair(sex);
      const value=selection[key];
      result.selection[key]=typeof value==='string' && options.includes(value)?value:options.includes(result.selection[key])?result.selection[key]:options[0];
    }
    if(typeof selection.hairColor==='string' && /^#[\da-f]{6}$/i.test(selection.hairColor))result.selection.hairColor=selection.hairColor;
    if(s.modelSet==='tomb'||s.modelSet==='vanilla')result.modelSet=s.modelSet;
    if(typeof s.floor==='string'&&catalog.floors.includes(s.floor))result.floor=s.floor;
    const garmentIds=new Set<number>(),lootIds=new Set<number>();
    if(Array.isArray(s.garments))result.garments=s.garments.slice(0,100).flatMap(g=>{
      if(!record(g)||!id(g.id)||garmentIds.has(g.id)||typeof g.type!=='string'||typeof g.variant!=='string'||!catalog.variants(g.type,sex).includes(g.variant))return [];
      garmentIds.add(g.id);return [{id:g.id,type:g.type as G,variant:g.variant,
        ...(typeof g.fabricStiffness==='number'&&Number.isFinite(g.fabricStiffness)?{fabricStiffness:Math.max(.2,Math.min(5,g.fabricStiffness))}:{})}];
    });
    if(!Array.isArray(s.garments))result.garments=result.garments.flatMap(g=>{
      const variants=catalog.variants(g.type,sex);
      return variants.length?[{...g,variant:variants.includes(g.variant)?g.variant:variants[0]}]:[];
    });
    if(Array.isArray(s.lootItems))result.lootItems=s.lootItems.slice(0,100).flatMap(item=>{
      if(!record(item)||!id(item.id)||lootIds.has(item.id)||typeof item.kind!=='string')return [];
      const kind=catalog.loot(item.kind,sex);if(!kind)return [];
      lootIds.add(item.id);return [{id:item.id,kind,layer:Number.isSafeInteger(item.layer)&&Number(item.layer)>=0&&Number(item.layer)<100?Number(item.layer):0}];
    });
    if(record(s.locks))for(const key of Object.keys(result.locks) as Array<keyof typeof result.locks>)result.locks[key]=s.locks[key]===true;
    if(Array.isArray(s.lockedGarmentIds))result.lockedGarmentIds=[...new Set(s.lockedGarmentIds.filter((n):n is number=>id(n)&&result.garments.some(g=>g.id===n)))];
    if(typeof s.addType==='string'&&catalog.variants(s.addType,sex).length)result.addType=s.addType as G;
    if(typeof s.addLootKind==='string')result.addLootKind=catalog.loot(s.addLootKind,sex)??result.addLootKind;
  } catch { /* Corrupt JSON or inaccessible/obsolete settings use safe defaults. */ }
  return result;
}

export function encodeGenerationSettings(settings:GenerationSettings) {
  return JSON.stringify({version:1,settings});
}
