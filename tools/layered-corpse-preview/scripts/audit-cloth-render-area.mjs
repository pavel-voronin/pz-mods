import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';
for(const dir of process.argv.slice(2)){
 const s=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8')),b=await readFile(resolve(dir,'scene.pzcloth'));
 const {bake}=decodeBlenderCache(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),s.sceneKey,s);
 const rows=bake.tracks.map((t,index)=>{
  const ratios=[];
  function area(frame,a,b,c){
   const p=i=>[0,1,2].map(j=>t.frames[(frame*t.particleCount+t.particleForVertex[i])*3+j]);
   const x=p(a),y=p(b).map((v,j)=>v-x[j]),z=p(c).map((v,j)=>v-x[j]);
   return Math.hypot(y[1]*z[2]-y[2]*z[1],y[2]*z[0]-y[0]*z[2],y[0]*z[1]-y[1]*z[0]);
  }
  for(let i=0;i<t.indices.length;i+=3){const ids=t.indices.slice(i,i+3),a=area(0,...ids);if(a>1e-10)ratios.push(area(bake.frameCount-1,...ids)/a);}
  ratios.sort((a,b)=>a-b);return {index,medianAreaRatio:ratios[Math.floor(ratios.length/2)],p01AreaRatio:ratios[Math.floor(ratios.length*.01)],below10Percent:ratios.filter(r=>r<.1).length};
 });console.log(JSON.stringify({dir,rows},null,2));
}
