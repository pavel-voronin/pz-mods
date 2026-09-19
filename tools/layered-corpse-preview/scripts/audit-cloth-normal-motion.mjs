import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';
import {sampleCloth} from '../app/cloth-physics.ts';
import {clothNormals} from '../app/cloth-normals.ts';
import {clothNormals as oldNormals} from '../outputs/checkpoints/accepted-damped-v2-20260916-152343/app/cloth-normals.ts';
const dir=process.argv[2];
const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
const bytes=await readFile(resolve(dir,'scene.pzcloth'));
const {bake}=decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),source.sceneKey,source);
const rows=[];
for(const [index,track] of bake.tracks.entries()){
 const p=track.positions.slice(),prev=p.slice(),a=p.slice(),b=p.slice(),pa=p.slice(),pb=p.slice();
 const scratch=new Float32Array(track.particleCount*3);let oldJumps=0,newJumps=0,oldMax=0,newMax=0;
 for(let f=bake.frameCount-32;f<bake.frameCount;f++){
  sampleCloth(track,bake,f/60,p);oldNormals(track,p,a,scratch);clothNormals(track,p,b,scratch);
  if(f>bake.frameCount-32)for(let i=0;i<p.length;i+=3){
   if(Math.hypot(p[i]-prev[i],p[i+1]-prev[i+1],p[i+2]-prev[i+2])>.001)continue;
   const angle=(n,last)=>Math.acos(Math.max(-1,Math.min(1,n[i]*last[i]+n[i+1]*last[i+1]+n[i+2]*last[i+2])))*180/Math.PI;
   const da=angle(a,pa),db=angle(b,pb);oldMax=Math.max(oldMax,da);newMax=Math.max(newMax,db);
   if(da>10)oldJumps++;if(db>10)newJumps++;
  }
  prev.set(p);pa.set(a);pb.set(b);
 }
 rows.push({index,oldJumps,newJumps,oldMax,newMax});
}
console.log(JSON.stringify(rows,null,2));
