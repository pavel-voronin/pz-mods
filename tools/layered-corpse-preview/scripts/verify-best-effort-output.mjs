// Validate a completed regression bake, register it, then exercise the real
// application's ready/cache endpoints without running the solver a second time.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {clothSceneKey,decodeBlenderCache} from '../app/blender-cache.ts';
const dir=resolve(process.argv[2]);
const source=JSON.parse(await readFile(resolve(dir,'scene-source.json'),'utf8'));
const prepared=JSON.parse(await readFile(resolve(dir,'scene-prepared.json'),'utf8'));
const report=JSON.parse(await readFile(resolve(dir,'scene-bake-report.json'),'utf8'));
const bytes=await readFile(resolve(dir,'scene.pzcloth'));
const key=await clothSceneKey(source);
const decoded=decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),key,source);
assert.equal(decoded.bake.tracks.length,source.items.length);
assert.equal(report.initialDelta,0);assert.equal(report.heldDelta,0);
assert(prepared.report.items.some(i=>!i.collisionReady),'Fixture must exercise unresolved contacts');
assert(decoded.warnings.length>0,'Residual contacts must not be silently hidden');
await mkdir('outputs/cloth-cache',{recursive:true});
await writeFile(resolve('outputs/cloth-cache','isotropic-damped-v2-best-effort-'+key+'.pzcloth'),bytes);
const response=await fetch('http://localhost:3000/__blender/jobs',{method:'POST',headers:{'content-type':'application/json','x-cloth-client':'1'},body:JSON.stringify({snapshot:source})});
const started=await response.json();assert(response.ok,JSON.stringify(started));
let status;
for(let attempt=0;attempt<30;attempt++){
 status=await (await fetch('http://localhost:3000/__blender/jobs/'+started.id)).json();
 if(status.state!=='running')break;
 await new Promise(resolve=>setTimeout(resolve,500));
}
assert.equal(status.state,'ready',JSON.stringify(status));
const downloaded=await fetch('http://localhost:3000/__blender/jobs/'+started.id+'/cache');
assert(downloaded.ok);
const loaded=decodeBlenderCache(await downloaded.arrayBuffer(),key,source);
assert.equal(loaded.bake.tracks.length,source.items.length);
console.log('PASS completed bake registered:',key,decoded.bake.tracks.length,'garments',decoded.bake.frameCount,'frames');
console.log('PASS application ready/cache endpoints:',started.id);
