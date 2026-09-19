import catalog from './pz-pocket-loot.json' with {type:'json'};

export type PocketItem = {
  id: string; label: string; category: string; model: string; texture: string;
  scale: number; mass: number; airDrag: number; restitution: number;
  source: string; line: number; modelFile: string; textureFile: string;
  modelSource: string; modelLine: number; modelName: string; weapon: boolean; pools: string[];
};
export type SequencePropKind = string;
export const sequencePropDefinitions: Record<string, PocketItem> = catalog.items;
export const sequencePropLabels = Object.fromEntries(Object.entries(sequencePropDefinitions).map(([id,item])=>[id,item.label]));
export const sequencePropOptions = Object.values(sequencePropDefinitions)
  .sort((a,b)=>a.label.localeCompare(b.label,'ru'))
  .map((item)=>({value:item.id,label:item.label,title:item.id+' · '+item.mass+' · '+item.pools.join(', ')}));

/** Old editor state survives HMR; explicitly remove notebooks from it as well. */
export function normalizePocketId(id: string, sex: 'm'|'f'): string | undefined {
  const legacy: Record<string,string> = {
    wallet:sex==='m'?'Base.Wallet_Male':'Base.Wallet_Female', money:'Base.MoneyBundle',
    cigarettes:'Base.CigarettePack', lighter:'Base.LighterDisposable',
  };
  const next=legacy[id]??id;
  return sequencePropDefinitions[next] ? next : undefined;
}

/** Pick one actual pocket recipe, then weighted distinct props for the preview.
 * Population/outfit frequencies and sandbox multipliers are not game-emulated.
 * Item eligibility and relative draw weights come directly from the game table.
 */
export function generatePocketLoot(sex:'m'|'f',count:number,random:()=>number=Math.random) {
  const general=catalog.pools.find((pool)=>pool.id===(sex==='m'?'inventorymale':'inventoryfemale'))!;
  const outfits=catalog.pools.filter((pool)=>pool.id.startsWith('Outfit_'));
  const pool=random()<.5 ? general : outfits[Math.min(outfits.length-1,Math.floor(random()*outfits.length))];
  const weights=new Map<string,number>();
  pool.entries.forEach((entry)=>weights.set(entry.id,(weights.get(entry.id)??0)+entry.weight));
  const items:string[]=[];
  while(items.length<count && weights.size) {
    const total=[...weights.values()].reduce((a,b)=>a+b,0);
    let cursor=random()*total,selected=[...weights.keys()].at(-1)!;
    for(const [id,weight] of weights) {cursor-=weight;if(cursor<=0){selected=id;break;}}
    items.push(selected);weights.delete(selected);
  }
  return {recipe:pool.id,items};
}
