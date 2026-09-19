import {readdir,readFile,writeFile} from 'node:fs/promises';
import {resolve,relative} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(process.argv[2]);
if(!root.includes('checkpoints'))throw Error('Expected an explicit checkpoint directory');
const entries=[];
async function walk(dir){
 for(const entry of await readdir(dir,{withFileTypes:true})){
  const path=resolve(dir,entry.name);
  if(entry.isDirectory())await walk(path);
  else if(entry.isFile()&&entry.name!=='manifest.json')entries.push({path:relative(root,path).replaceAll('\\','/'),sha256:createHash('sha256').update(await readFile(path)).digest('hex')});
 }
}
await walk(root);entries.sort((a,b)=>a.path.localeCompare(b.path));
await writeFile(resolve(root,'manifest.json'),JSON.stringify(entries,null,2));
for(const e of entries)if(createHash('sha256').update(await readFile(resolve(root,e.path))).digest('hex')!==e.sha256)throw Error('Verification failed: '+e.path);
console.log('Checkpoint verified:',entries.length,'files');
