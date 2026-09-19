import assert from 'node:assert/strict';
import {clothSceneKey,decodeBlenderCache} from '../app/blender-cache.ts';
const input={floor:0,duration:1/60,capsules:[],items:[{surfaces:[{positions:[0,0,0,1,0,0,0,1,0],uvs:[0,0,1,0,0,1],indices:[0,1,2]}],releaseTime:0,seed:1,target:[0,0,0]}]};
const key=await clothSceneKey(input);
assert.equal(key,await clothSceneKey({...input,items:input.items.map(i=>({...i,fabricStiffness:1}))}));
for(const mutation of [s=>s.items[0].fabricStiffness=3,s=>s.items[0].releaseTime=.1,s=>s.items[0].surfaces[0].positions[0]=.1,s=>s.items[0].target[0]=1]){
 const changed=structuredClone(input);mutation(changed);assert.notEqual(key,await clothSceneKey(changed));
}
const track={...input.items[0].surfaces[0],particleForVertex:[0,1,2],particleCount:3,releaseTime:0};
function pack(header,frames){const bytes=new TextEncoder().encode(JSON.stringify(header));const start=12+Math.ceil(bytes.length/4)*4;const b=new ArrayBuffer(start+frames.length*4);new Uint8Array(b).set(new TextEncoder().encode('PZCLOTH1'));new DataView(b).setUint32(8,bytes.length,true);new Uint8Array(b,12,bytes.length).set(bytes);new Float32Array(b,start).set(frames);return b;}
const header={sceneKey:key,fps:60,frameCount:2,tracks:[track],warnings:[]};
const frames=[...track.positions,...track.positions];const bytes=pack(header,frames);
assert.equal(decodeBlenderCache(bytes,key,input).bake.tracks[0].frames.length,18);
assert.throws(()=>decodeBlenderCache(bytes,'wrong',input),/сцена изменилась/);
assert.throws(()=>decodeBlenderCache(bytes.slice(0,-4),key,input),/обрезанные/);
assert.throws(()=>decodeBlenderCache(pack({...header,tracks:[{...track,particleForVertex:[0,1,9]}]},frames),key,input),/индексы/);
assert.throws(()=>decodeBlenderCache(pack(header,[NaN,...frames.slice(1)]),key,input),/нечисловые/);
assert.throws(()=>decodeBlenderCache(pack(header,[1,...frames.slice(1)]),key,input),/начальное/);
console.log('PASS Blender cache: round trip, scene changes, truncated/invalid data, initial state');
