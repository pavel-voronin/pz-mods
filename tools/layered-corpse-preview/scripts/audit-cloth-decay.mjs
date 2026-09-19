import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {decodeBlenderCache} from '../app/blender-cache.ts';

// Read-only measurements; no filtering, freezing or changes to the cache.
for (const dir of process.argv.slice(2)) {
  const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
  const bytes=await readFile(resolve(dir,'scene.pzcloth'));
  const {bake}=decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),source.sceneKey,source);
  const rows=bake.tracks.map((track,index)=>{
    const n=track.particleCount, windows=[];
    for (let end=bake.frameCount-1;end>=120;end-=30) {
      let total=0,internal=0,centroid=0;
      for(let f=end-29;f<=end;f++) {
        const mean=[0,0,0];let square=0;
        for(let i=0;i<n;i++)for(let j=0;j<3;j++) {
          const v=(track.frames[(f*n+i)*3+j]-track.frames[((f-1)*n+i)*3+j])*60;
          mean[j]+=v/n;square+=v*v/n;
        }
        const rigid=mean.reduce((a,v)=>a+v*v,0);
        total+=square;centroid+=rigid;internal+=Math.max(0,square-rigid);
      }
      windows.push({endSeconds:end/60,rmsMmPerSec:1000*Math.sqrt(total/30),
        deformationMmPerSec:1000*Math.sqrt(internal/30),centroidMmPerSec:1000*Math.sqrt(centroid/30)});
    }
    return {index,releaseTime:track.releaseTime,windows:windows.reverse()};
  });
  console.log(JSON.stringify({dir,rows},null,2));
}
