import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {decodeBlenderCache} from '../app/blender-cache.ts';
import {finalizeClothRest} from './finalize-cloth-rest.ts';
for(const dir of process.argv.slice(2)){
 const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
 const raw=await readFile(resolve(dir,'scene.pzcloth'));
 const {bytes,rest}=finalizeClothRest(raw,source);
 assert.notEqual(rest.frame,null,'Fixture did not settle: '+dir);
 const decode=b=>decodeBlenderCache(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),source.sceneKey,source).bake;
 const before=decode(raw),after=decode(bytes);
 for(let i=0;i<before.tracks.length;i++){
  const a=before.tracks[i],b=after.tracks[i],stride=a.particleCount*3;
  assert.deepEqual(b.frames.slice(0,(rest.frame+1)*stride),a.frames.slice(0,(rest.frame+1)*stride),'Pre-sleep motion changed');
  for(let f=rest.frame+1;f<after.frameCount;f++)assert.deepEqual(b.frames.slice(f*stride,(f+1)*stride),a.frames.slice(rest.frame*stride,(rest.frame+1)*stride),'Not the same shared solver frame');
 }
 console.log('PASS',dir,rest.seconds+'s: unchanged throws; shared snapshot; zero later motion');
}
