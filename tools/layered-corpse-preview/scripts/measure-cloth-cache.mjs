import {readFile} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';
for(const file of process.argv.slice(2)){
 const source=JSON.parse(await readFile(resolve(dirname(file),'scene-source.json'),'utf8'));
 const bytes=await readFile(file),{bake}=decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),source.sceneKey,source);
 const report=bake.tracks.map((t,index)=>{
   const n=t.particleCount,f=t.frames,tail=[];let maxStretch=1;
   const edges=new Map();
   for(let k=0;k<t.indices.length;k+=3)for(let e=0;e<3;e++){
     const a=t.particleForVertex[t.indices[k+e]],b=t.particleForVertex[t.indices[k+(e+1)%3]],key=[Math.min(a,b),Math.max(a,b)].join(',');
     const len=Math.hypot(...[0,1,2].map(j=>f[a*3+j]-f[b*3+j]));if(len>1e-6)edges.set(key,[a,b,len]);
   }
   for(let frame=1;frame<bake.frameCount;frame++){
     if(frame>bake.frameCount-31){let sum=0;for(let i=0;i<n*3;i++)sum+=((f[(frame*n)*3+i]-f[((frame-1)*n)*3+i])*bake.fps)**2;tail.push(Math.sqrt(sum/n));}
     if(frame%6===0)for(const [a,b,len] of edges.values()){const d=Math.hypot(...[0,1,2].map(j=>f[(frame*n+a)*3+j]-f[(frame*n+b)*3+j]));maxStretch=Math.max(maxStretch,d/len);}
   }
   const time=Math.min(source.duration,t.releaseTime+.8),frame=Math.round(time*bake.fps),dist=[];
   for(let i=0;i<n;i++)dist.push(Math.hypot(...[0,1,2].map(j=>f[(frame*n+i)*3+j]-f[i*3+j])));
   dist.sort((a,b)=>a-b);
   return {index,tailRmsSpeed:tail.reduce((a,b)=>a+b,0)/tail.length,maxEdgeStretch:maxStretch,releaseDisplacementP10:dist[Math.floor(n*.1)],releaseDisplacementP50:dist[Math.floor(n*.5)]};
 });
 console.log(file,JSON.stringify(report,null,2));
}
