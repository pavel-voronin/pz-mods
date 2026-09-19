import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';
const dir=process.argv[2];
const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
const bytes=await readFile(resolve(dir,'scene.pzcloth'));
const {bake}=decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),source.sceneKey,source);
for(const [i,t] of bake.tracks.entries()){
 const center=(frame)=>{
  const c=[0,0,0];let bottom=Infinity,top=-Infinity;
  for(let p=0;p<t.particleCount;p++)for(let j=0;j<3;j++){
   const v=t.frames[(frame*t.particleCount+p)*3+j];c[j]+=v/t.particleCount;
   if(j===1){bottom=Math.min(bottom,v);top=Math.max(top,v);}
  }
  return {c,bottom,top};
 };
 const rows=[0,.033,.1,.2,.4,.55,.8,1.2,2].map(dt=>{
  const frame=Math.min(bake.frameCount-1,Math.round((t.releaseTime+dt)*bake.fps));
  const state=center(frame),prev=center(Math.max(0,frame-1));
  return {dt,...state,speed:state.c.map((v,j)=>(v-prev.c[j])*bake.fps)};
 });
 console.log(JSON.stringify({index:i,target:source.items[i].target,launch:source.velocities[i],rows,final:center(bake.frameCount-1)}));
}
