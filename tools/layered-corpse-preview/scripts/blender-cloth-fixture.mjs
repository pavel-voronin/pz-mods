import fs from 'node:fs';
import path from 'node:path';
import {createRigModel,skinRigModel,PzRagdollPose} from '../app/pz-rig.ts';
import {rigAssetPath} from '../app/pz-model-assets.ts';
import {clothReleaseVelocities} from '../app/cloth-release.ts';
const read=p=>JSON.parse(fs.readFileSync(new URL(p,import.meta.url)));
const pose=new PzRagdollPose(read('../public/pz/rigs/poses/front.json'));
const name=process.argv[2]??'jumper',modelSet='tomb';
const rig=createRigModel(read('../public'+rigAssetPath(name,'m',modelSet)));
const rest=process.argv.includes('--rest');
if(!rest)skinRigModel(rig,pose);
const surfaces=rig.parts.map(({geometry:g})=>({positions:Array.from(g.getAttribute('position').array),uvs:Array.from(g.getAttribute('uv').array),indices:Array.from(g.index?.array??Uint32Array.from({length:g.getAttribute('position').count},(_,i)=>i))}));
const item={surfaces,releaseTime:.3,target:[-.5,-.05,-.5],flightTime:.55,seed:0};
const result={name,modelSet,pose:rest?'bind':'front',floor:-.05,fps:60,duration:2.5,item,velocity:clothReleaseVelocities([item])[0].toArray()};
result.restSurfaces=rig.parts.map(part=>({positions:Array.from(part.positions)}));
if(process.argv.includes('--scene')) {
  const body=createRigModel(read('../public'+rigAssetPath('body','m',modelSet)));skinRigModel(body,pose);
  result.body=body.parts.map(({geometry:g})=>({positions:Array.from(g.getAttribute('position').array),indices:Array.from(g.index.array)}));
}
const catalog=read('../app/pz-catalog.json');
const variant=catalog.garments[name].variants.m.find(v=>v.value==='jumper-roundneck')??catalog.garments[name].variants.m.find(v=>(v.model??catalog.garments[name].model)===name);
result.texture=path.resolve('public'+variant.texture);
const out=path.resolve(process.argv[3]??'outputs/blender-trial');fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,name+'-input.json'),JSON.stringify(result));
console.log(path.join(out,name+'-input.json'));
