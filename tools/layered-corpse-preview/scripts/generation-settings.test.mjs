import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {decodeGenerationSettings,encodeGenerationSettings,defaultGenerationLocks,GENERATION_STORAGE_KEY} from '../app/generation-settings.ts';
const defaults={selection:{body:'m-1',pose:'front',hair:'none',hairColor:'#704322'},modelSet:'tomb',floor:'asphalt',
 garments:[{id:1,type:'shirt',variant:'white'}],lootItems:[{id:1,kind:'wallet',layer:0}],locks:defaultGenerationLocks,
 lockedGarmentIds:[],addType:'shirt',addLootKind:'wallet'};
const catalog={bodies:['m-1','f-1'],poses:['front','back'],floors:['asphalt','wood'],hair:()=>['none','long'],
 variants:(t)=>t==='shirt'?['white','blue']:[],loot:k=>['wallet','key'].includes(k)?k:undefined};
const decode=raw=>decodeGenerationSettings(raw,defaults,catalog);
test('all generation parameters and per-item locks survive JSON roundtrip',()=>{
 const settings={...structuredClone(defaults),selection:{body:'f-1',pose:'back',hair:'long',hairColor:'#abcdef'},modelSet:'vanilla',floor:'wood',
  garments:[{id:81,type:'shirt',variant:'blue'}],lootItems:[{id:42,kind:'key',layer:2}],locks:{...defaultGenerationLocks,body:true,loot:true},lockedGarmentIds:[81],addLootKind:'key'};
 assert.deepEqual(decode(encodeGenerationSettings(settings)),settings);
});
test('fabric stiffness persists, clamps safely, and is removed by defaults reset',()=>{
 for(const [value,expected] of [[.3,.3],[3,3],[99,5],[-1,.2],['bad',undefined]]){
  const s={...defaults,garments:[{...defaults.garments[0],fabricStiffness:value}]};
  assert.equal(decode(encodeGenerationSettings(s)).garments[0].fabricStiffness,expected);
 }
 assert.equal(decode(encodeGenerationSettings(defaults)).garments[0].fabricStiffness,undefined);
});
test('missing, corrupted and incompatible storage return independent defaults',()=>{
 for(const raw of [null,'bad','[]','null','{"version":2,"settings":{}}']) {
  const actual=decode(raw);assert.deepEqual(actual,defaults);actual.locks.body=true;assert.equal(defaults.locks.body,false);
 }
});
test('stale catalog IDs, duplicate IDs and orphan locks cannot enter scene',()=>{
 const settings={...defaults,selection:{body:'gone',pose:'gone',hair:'gone',hairColor:'javascript:bad'},
  garments:[{id:2,type:'shirt',variant:'blue'},{id:2,type:'shirt',variant:'white'},{id:3,type:'gone',variant:'white'}],
  lootItems:[{id:2,kind:'gone',layer:0},{id:3,kind:'key',layer:-7}],lockedGarmentIds:[2,2,999],locks:{body:'true',hair:true}};
 const actual=decode(encodeGenerationSettings(settings));
 assert.deepEqual(actual.selection,defaults.selection);
 assert.deepEqual(actual.garments,[{id:2,type:'shirt',variant:'blue'}]);
 assert.deepEqual(actual.lootItems,[{id:3,kind:'key',layer:0}]);
 assert.deepEqual(actual.lockedGarmentIds,[2]);assert.equal(actual.locks.body,false);assert.equal(actual.locks.hair,true);
});
test('empty item lists remain empty and reset clears generation locks after reload',()=>{
 const empty={...defaults,garments:[],lootItems:[]};assert.deepEqual(decode(encodeGenerationSettings(empty)),empty);
 const stored=encodeGenerationSettings(defaults);assert.deepEqual(decode(stored).locks,defaultGenerationLocks);
 assert.deepEqual(decode(stored).lockedGarmentIds,[]);
});
test('hydration gates scene/save and reset only writes the application key',()=>{
 const source=fs.readFileSync(new URL('../app/page.tsx',import.meta.url),'utf8');
 assert.ok(source.includes('if(!settingsLoaded)return;'));
 assert.ok(source.includes('if (!mountRef.current || !settingsLoaded) return;'));
 assert.ok(source.includes('Math.max(0,...settings.garments.map(g=>g.id))+1'));
 assert.ok(source.includes('Math.max(0,...settings.lootItems.map(item=>item.id))+1'));
 assert.ok(!source.includes('localStorage.clear('));
 assert.ok(GENERATION_STORAGE_KEY.endsWith(':v1'));
});
