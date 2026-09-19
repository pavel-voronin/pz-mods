import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';
const dir=process.argv[2];
const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
const bytes=await readFile(resolve(dir,'scene.pzcloth'));
const {bake}=decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),source.sceneKey,source);
const center=(track,frame)=>{
 const c=[0,0,0];for(let i=0;i<track.particleCount;i++)for(let j=0;j<3;j++)c[j]+=track.frames[(frame*track.particleCount+i)*3+j]/track.particleCount;
 return c;
};
const layers=new Map(),rows=[];
for(const [i,track] of bake.tracks.entries()){
 const end=center(track,bake.frameCount-1),tail=center(track,bake.frameCount-31);
 const tailTravel=Math.hypot(...end.map((v,j)=>v-tail[j]));
 const row={index:i,end,tailTravel};rows.push(row);
 const key=source.items[i].layerId??`item-${i}`;
 if(!layers.has(key))layers.set(key,[]);layers.get(key).push(i);
}
const landing=[...layers].map(([layer,ids])=>{
 const average=(get)=>[0,1,2].map(j=>ids.reduce((sum,i)=>sum+get(i)[j],0)/ids.length);
 const end=average(i=>rows[i].end),target=average(i=>source.items[i].target);
 return {layer,error:Math.hypot(end[0]-target[0],end[2]-target[2])};
});
console.log(JSON.stringify({rows,landing},null,2));
if(!process.argv.includes('--report-only')){
 assert.ok(rows.every(r=>r.tailTravel<.015),'garment still travels >15 mm in the last half-second');
 assert.ok(landing.every(r=>r.error<.15),'release layer missed the pile by >150 mm');
 console.log('PASS: compact landing and no late runaway');
}
