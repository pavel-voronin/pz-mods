import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';

export const REST_REVISION='isotropic-rest-v3';

/** Offline whole-contact-island sleeping. Never moves vertices toward a goal.
 * A single native solver frame is retained for ALL garments, so independently
 * sleeping surfaces cannot drift into one another. Only valid for this fixed,
 * finite scene: no future releases or external inputs may be discarded.
 */
export function finalizeClothRest(raw:Buffer,source:any){
  const buffer=raw.buffer.slice(raw.byteOffset,raw.byteOffset+raw.byteLength) as ArrayBuffer;
  const {bake}=decodeBlenderCache(buffer,source.sceneKey,source);
  const length=raw.readUInt32LE(8),header=JSON.parse(raw.toString('utf8',12,12+length));
  if(header.rest?.revision===REST_REVISION)return {bytes:raw,rest:header.rest};
  const fps=bake.fps,window=Math.ceil(.25*fps);
  const earliest=Math.ceil(Math.max(...source.items.map((i:any)=>i.releaseTime+Math.max(.8,(i.flightTime??.55)+.25)))*fps);
  const stats=bake.tracks.map(t=>{
    const n=t.particleCount,result=[];
    for(let f=0;f<bake.frameCount;f++){
      const center=[0,0,0],delta=[0,0,0];let sum=0,maxStep=0,minY=Infinity;
      for(let i=0;i<n;i++){
        let square=0;
        for(let j=0;j<3;j++){
          const k=(f*n+i)*3+j,v=t.frames[k];center[j]+=v/n;
          if(j===1)minY=Math.min(minY,v);
          if(f){const d=v-t.frames[k-n*3];square+=d*d;delta[j]+=d/n;}
        }
        sum+=square;maxStep=Math.max(maxStep,Math.sqrt(square));
      }
      result.push({center,minY,rms:Math.sqrt(sum/n)*fps,speed:Math.hypot(...delta)*fps,maxStep});
    }
    return result;
  });
  let frame:number|null=null;
  for(let f=Math.max(window,earliest+window);f<bake.frameCount;f++){
    const rows=stats.map(s=>s[f]);
    const nearFloor=rows.some(r=>r.minY<source.floor+.02)&&rows.every(r=>r.center[1]<source.floor+.15);
    const slow=stats.every(s=>{
      const w=s.slice(f-window+1,f+1);
      return Math.sqrt(w.reduce((v,r)=>v+r.rms*r.rms,0)/window)<.012&&
        w.reduce((v,r)=>v+r.speed,0)/window<.004&&w.every(r=>r.maxStep<.003);
    });
    if(!nearFloor||!slow)continue;
    // Offline look-ahead: reject temporary pauses preceding a slide or impact.
    const futureQuiet=stats.every(s=>s.slice(f+1).every(r=>r.rms<.06&&r.maxStep<.008&&
      Math.hypot(...r.center.map((v,j)=>v-s[f].center[j]))<.015));
    if(futureQuiet){frame=f;break;}
  }
  const rest={revision:REST_REVISION,mode:'whole-pile-sleep',frame,seconds:frame===null?null:frame/fps,
    thresholds:{quietSeconds:.25,rmsMPerS:.012,centroidMPerS:.004,maxStepM:.003},
    nativeMotionAtSleep:frame===null?null:stats.map(s=>s[frame!])};
  if(frame!==null){
    for(const t of bake.tracks){
      const stride=t.particleCount*3,pose=t.frames.slice(frame*stride,(frame+1)*stride);
      for(let f=frame+1;f<bake.frameCount;f++)t.frames.set(pose,f*stride);
    }
    header.warnings=header.warnings.filter((w:string)=>w!=='К концу секвенции ткань ещё движется')
      .map((w:string)=>w.startsWith('Финальный кадр:')?w.replace('Финальный кадр:','Исходный нативный финальный кадр до обработки покоя:'):w);
  }else header.warnings=[...header.warnings,'Покой не достигнут: секвенция сохранена без принудительной остановки'];
  header.rest=rest;
  const json=Buffer.from(JSON.stringify(header)),prefix=Buffer.alloc(12+Math.ceil(json.length/4)*4);
  prefix.write('PZCLOTH1');prefix.writeUInt32LE(json.length,8);json.copy(prefix,12);
  return {bytes:Buffer.concat([prefix,...bake.tracks.map(t=>Buffer.from(t.frames.buffer,t.frames.byteOffset,t.frames.byteLength))]),rest};
}

export async function finalizeClothRestFile(dir:string){
  const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
  const result=finalizeClothRest(await readFile(resolve(dir,'scene.pzcloth')),source);
  await writeFile(resolve(dir,'scene.pzcloth'),result.bytes);
  const path=resolve(dir,'scene-bake-report.json');
  const report=JSON.parse(await readFile(path,'utf8'));
  report.rest=result.rest;report.solverRevision=REST_REVISION;
  report.warnings=JSON.parse(result.bytes.toString('utf8',12,12+result.bytes.readUInt32LE(8))).warnings;
  report.nativeTailMotion??=report.tailMotion;
  if(result.rest.frame!==null){
    const {bake}=decodeBlenderCache(result.bytes.buffer.slice(result.bytes.byteOffset,result.bytes.byteOffset+result.bytes.byteLength) as ArrayBuffer,source.sceneKey,source);
    report.tailMotion=bake.tracks.map(t=>{
      const stride=t.particleCount*3;let rms=0,speed=0,count=0;
      for(let f=Math.max(1,bake.frameCount-31);f<bake.frameCount;f++){
        let sum=0;const mean=[0,0,0];
        for(let i=0;i<t.particleCount;i++)for(let j=0;j<3;j++){
          const k=f*stride+i*3+j,d=(t.frames[k]-t.frames[k-stride])*bake.fps;
          sum+=d*d;mean[j]+=d/t.particleCount;
        }
        rms+=Math.sqrt(sum/t.particleCount);speed+=Math.hypot(...mean);count++;
      }
      return {rmsVertexSpeed:rms/count,centroidSpeed:speed/count};
    });
    report.nativeFinalIntersections??=report.finalIntersections;
    report.finalIntersections=null; // Native report measured a later frame; do not mislabel it.
  }
  await writeFile(path,JSON.stringify(report,null,2));
  return result.rest;
}
