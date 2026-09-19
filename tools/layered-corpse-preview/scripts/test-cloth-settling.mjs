import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';
const [baselineDir,candidateDir]=process.argv.slice(2);
async function load(dir){
 const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
 const bytes=await readFile(resolve(dir,'scene.pzcloth'));
 return {source,...decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),source.sceneKey,source),
  report:JSON.parse(await readFile(resolve(dir,'scene-bake-report.json'),'utf8')),
  prepared:JSON.parse(await readFile(resolve(dir,'scene-prepared.json'),'utf8'))};
}
const baseline=await load(baselineDir),candidate=await load(candidateDir);
assert.equal(candidate.source.sceneKey,baseline.source.sceneKey);
for(const [i,launch] of candidate.report.launches.entries()){
 assert.deepEqual(launch.sourceVelocity,baseline.report.launches[i].sourceVelocity,'Planned launch changed');
 assert.ok(launch.velocity.every((v,j)=>Math.abs(v-baseline.report.launches[i].velocity[j])<1e-6),'Launch changed beyond float precision');
}
const center=(t,f)=>[0,1,2].map(j=>{
 let sum=0;for(let i=0;i<t.particleCount;i++)sum+=t.frames[(f*t.particleCount+i)*3+j];return sum/t.particleCount;
});
const rows=candidate.bake.tracks.map((t,index)=>{
 const old=baseline.bake.tracks[index],n=t.particleCount,last=candidate.bake.frameCount-1;
 for(const key of ['positions','uvs','indices','particleForVertex'])assert.deepEqual(t[key],old[key],key+' changed');
 let freeFlightCenterDelta=0,rawFlightCenterDelta=0;
 const shift=[0,1,2].map(j=>(candidate.prepared.items[index].releaseSeparation?.[j]??0)-(baseline.prepared.items[index].releaseSeparation?.[j]??0));
 assert.ok(Math.hypot(...shift)<=.05,'Unbounded release repair');
 const release=Math.round(t.releaseTime*60);
 for(let f=release;f<=release+9;f++){
  const u=Math.min(1,Math.max(0,(f/60-t.releaseTime)/.18)),blend=u*u*(3-2*u);
  const delta=center(t,f).map((v,j)=>v-center(old,f)[j]);
  rawFlightCenterDelta=Math.max(rawFlightCenterDelta,Math.hypot(...delta));
  freeFlightCenterDelta=Math.max(freeFlightCenterDelta,Math.hypot(...delta.map((v,j)=>v-shift[j]*blend)));
 }
 const end=center(t,last),oldEnd=center(old,last);
 const landingShift=Math.hypot(end[0]-oldEnd[0],end[2]-oldEnd[2]);
 const excursions=[];
 for(let i=0;i<n;i++){
  const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
  for(let f=last-30;f<=last;f++)for(let j=0;j<3;j++){
   const value=t.frames[(f*n+i)*3+j];min[j]=Math.min(min[j],value);max[j]=Math.max(max[j],value);
  }
  excursions.push(Math.hypot(...max.map((v,j)=>v-min[j])));
 }
 excursions.sort((a,b)=>a-b);
 return {index,freeFlightCenterDelta,rawFlightCenterDelta,releaseRepairShift:Math.hypot(...shift),landingShift,tailRms:candidate.report.tailMotion[index].rmsVertexSpeed,
  baselineRms:baseline.report.tailMotion[index].rmsVertexSpeed,excursionP95:excursions[Math.floor(n*.95)]};
});
console.log(JSON.stringify(rows,null,2));
if(!process.argv.includes('--report-only')){
 if(!process.argv.includes('--settling-only')){
  assert.ok(rows.every(r=>r.freeFlightCenterDelta<.01),'Early flight moved by >10 mm');
  assert.ok(rows.every(r=>r.landingShift<.08),'Landing changed by >80 mm');
 }
 assert.ok(rows.every(r=>r.tailRms<.012),'Residual RMS motion exceeds 12 mm/s');
 assert.ok(rows.every(r=>r.excursionP95<.006),'Late fold excursion exceeds 6 mm');
 console.log(process.argv.includes('--settling-only')?'PASS: same source, launch and UVs; settling thresholds. Relative path reported but not asserted.':'PASS: same source, launch and UVs; quieter folds; preserved throw');
}
