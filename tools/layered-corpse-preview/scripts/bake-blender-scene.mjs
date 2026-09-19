import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {clothSceneKey,decodeBlenderCache} from '../app/blender-cache.ts';
const args=process.argv.slice(2),sourcePath=args[0];
if(!sourcePath)throw Error('Usage: node scripts/bake-blender-scene.mjs SNAPSHOT.json [--out DIR] [--strict-intersections] (best-effort contacts by default)');
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const out=resolve(args.includes('--out')?args[args.indexOf('--out')+1]:resolve(root,'outputs','blender-scene-'+Date.now()));
await mkdir(out,{recursive:true});
const source=JSON.parse(await readFile(sourcePath,'utf8'));
if(source.format!=='pz-cloth-scene-v1')throw Error('Not an app scene snapshot');
source.sceneKey=await clothSceneKey(source);
await writeFile(resolve(out,'scene-source.json'),JSON.stringify(source));
const blender=process.env.BLENDER_EXE??'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe';
async function run(script,params){
  await new Promise((done,fail)=>{
    const child=spawn(blender,['--background','--factory-startup','--threads','8','--python-exit-code','1','--python',resolve(root,'scripts',script),'--',...params],{stdio:'inherit',windowsHide:true});
    const stop=()=>child.kill();process.once('SIGINT',stop);
    child.on('error',fail);child.on('exit',code=>{process.removeListener('SIGINT',stop);code===0?done():fail(Error('Blender exited '+code));});
  });
}
const contactPolicy=args.includes('--strict-intersections')?[]:['--allow-initial-intersections'];
await run('prepare-cloth-scene.py',[resolve(out,'scene-source.json'),'--posed-shell','--repair-layers',...contactPolicy]);
await run('remesh-cloth-scene.py',[resolve(out,'scene-prepared.json'),...contactPolicy]);
await run('blender-scene-bake.py',[resolve(out,'scene-prepared.json'),'--surface-fabric','--drag-aware-launch','--damped-fabric',...contactPolicy]);
const raw=await readFile(resolve(out,'scene.pzcloth'));
const decoded=decodeBlenderCache(raw.buffer.slice(raw.byteOffset,raw.byteOffset+raw.byteLength),source.sceneKey,source);
console.log('Validated app cache:',resolve(out,'scene.pzcloth'),decoded.bake.tracks.length,'garments',decoded.bake.frameCount,'frames');
