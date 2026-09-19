// Upgrade an unedited stock-pose regression snapshot; reject any ragdoll mismatch.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import * as THREE from 'three';
import {createRigModel,PzRagdollPose,skinRigModel,clothPreparationBind} from '../app/pz-rig.ts';
import {rigAssetPath} from '../app/pz-model-assets.ts';
const [input,out]=process.argv.slice(2),s=JSON.parse(await readFile(input,'utf8'));
if(process.argv.includes('--without-jacket')){
 const keep=s.garments.map((g,i)=>g.model!=='suitjacket'?i:-1).filter(i=>i>=0);
 for(const key of ['items','garments','velocities'])s[key]=keep.map(i=>s[key][i]);
 const {clothSceneKey}=await import('../app/blender-cache.ts');s.sceneKey=await clothSceneKey(s);
 s.diagnosticOnly='Subset without suitjacket; not the full failing scene';
}
const sex=s.selection.body.startsWith('m')?'m':'f';
const load=async name=>createRigModel(JSON.parse(await readFile(resolve('public','.'+rigAssetPath(name,sex,s.modelSet)),'utf8')));
const body=await load('body'),pose=new PzRagdollPose(JSON.parse(await readFile('public/pz/rigs/poses/'+s.selection.pose+'.json','utf8'))),globals=pose.boneGlobals();
const bind=clothPreparationBind(body);
const rig=model=>model.parts.map(p=>({boneNames:p.boneNames,positions:Array.from(p.positions),joints:Array.from(p.joints),weights:Array.from(p.weights),
 offsets:p.offsets.map(m=>m.toArray()),startGlobals:p.boneNames.map(n=>(bind.get(n)??new THREE.Matrix4()).toArray()),endGlobals:p.boneNames.map(n=>(globals.get(n)??new THREE.Matrix4()).toArray()),
 startMatrices:p.boneNames.map((n,i)=>(bind.get(n)??new THREE.Matrix4()).clone().multiply(p.offsets[i]).toArray()),
 skinMatrices:p.boneNames.map((n,i)=>(globals.get(n)??new THREE.Matrix4()).clone().multiply(p.offsets[i]).toArray())}));
for(let i=0;i<s.garments.length;i++){
 const m=await load(s.garments[i].model);skinRigModel(m,pose);let error=0;
 for(let j=0;j<m.parts.length;j++){const actual=m.parts[j].geometry.attributes.position.array,want=s.items[i].surfaces[j].positions;for(let k=0;k<want.length;k++)error=Math.max(error,Math.abs(actual[k]-want[k]));}
 if(error>1e-6)throw Error('Snapshot has custom pose; cannot reconstruct: '+error);
 s.garments[i].preparationRig=rig(m);
}
s.bodyPreparationRig=rig(body);
s.preparationCapsules=s.capsules.map(c=>{
 const initial=p=>{const point=new THREE.Vector3().fromArray(p),[name,m]=[...globals].filter(([n])=>bind.has(n)).sort((a,b)=>new THREE.Vector3().setFromMatrixPosition(a[1]).distanceToSquared(point)-new THREE.Vector3().setFromMatrixPosition(b[1]).distanceToSquared(point))[0];point.applyMatrix4(m.clone().invert());return {bone:name,local:point.toArray(),start:point.clone().applyMatrix4(bind.get(name)).toArray()};};
 const a=initial(c.a),b=initial(c.b);return {...c,startA:a.start,startB:b.start,attachmentA:a,attachmentB:b};
});
await mkdir(out,{recursive:true});await writeFile(resolve(out,'scene-source.json'),JSON.stringify(s));console.log('Verified exact stock pose and exported common bind-frame rig:',out);
