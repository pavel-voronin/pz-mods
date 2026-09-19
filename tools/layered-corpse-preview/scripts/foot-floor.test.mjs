import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import {createRigModel,skinRigModel,PzRagdollPose,ragdollHandles} from '../app/pz-rig.ts';
import {rigAssetPath} from '../app/pz-model-assets.ts';
const read=path=>JSON.parse(fs.readFileSync(new URL(path,import.meta.url)));
test('skinned toe support keeps both feet above the floor across source poses',()=>{
 for(const name of fs.readdirSync(new URL('../public/pz/rigs/poses/',import.meta.url)).filter(n=>n.endsWith('.json'))) {
  const pose=new PzRagdollPose(read('../public/pz/rigs/poses/'+name));
  const rig=createRigModel(read('../public'+rigAssetPath('body','m','tomb')));
  const positions=new Map(ragdollHandles.map(k=>[k,pose.getHandlePosition(k)]));
  for(const p of positions.values())p.y-=.2;
  for(let pass=0;pass<3;pass++) {
   pose.setHandlePositions(positions);skinRigModel(rig,pose);pose.updateFootSupports([rig]);pose.projectHandles(positions,new Set(),-.1);
  }
  pose.setHandlePositions(positions);skinRigModel(rig,pose);
  let count=0;
  for(const part of rig.parts)for(let i=0;i<part.positions.length/3;i++) {
   let weight=0;
   for(let j=0;j<4;j++)if(/^Bip01_[LR]_(Foot|Toe)/.test(part.boneNames[part.joints[i*4+j]]??''))weight+=part.weights[i*4+j];
   if(weight>.25){count++;assert.ok(part.geometry.getAttribute('position').getY(i)>=-.1005,name+' toe through floor');}
  }
  assert.ok(count>0,'no foot samples');
 }
});
