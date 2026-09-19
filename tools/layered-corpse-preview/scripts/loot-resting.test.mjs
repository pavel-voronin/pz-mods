import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';
import {FBXLoader} from 'three/examples/jsm/loaders/FBXLoader.js';
import {makeLootHull} from '../app/loot-collider.ts';
import {bakeLoot} from '../app/loot-physics.ts';
import catalog from '../app/pz-pocket-loot.json' with {type:'json'};
import {gameRoot} from './import-pocket-loot.mjs';

class Textures extends THREE.Loader {load(){return new THREE.Texture();}}
const manager=new THREE.LoadingManager();manager.addHandler(/.*/,new Textures(manager));
function item(id,index,releaseTime){
 const d=catalog.items[id],b=fs.readFileSync(path.join(gameRoot,d.modelFile));
 const model=new FBXLoader(manager).parse(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),'');
 model.updateMatrixWorld(true);
 const bounds=new THREE.Box3().setFromObject(model),center=bounds.getCenter(new THREE.Vector3()),points=[];
 model.traverse(mesh=>{if(!mesh.isMesh)return;const p=mesh.geometry.getAttribute('position');for(let i=0;i<p.count;i++)points.push(new THREE.Vector3().fromBufferAttribute(p,i).applyMatrix4(mesh.matrixWorld).sub(center).multiplyScalar(d.scale));});
 return {center:[0,.35+index*.04,0],halfExtents:bounds.getSize(new THREE.Vector3()).multiplyScalar(d.scale*.5).toArray(),hull:makeLootHull(points),quaternion:[0,0,0,1],target:[.5,0,.3],releaseTime,mass:d.mass,index};
}
test('current scene: flyer must not restart sliding at Done',()=>{
 const inputs=['Base.IDcard','Base.BusinessCard','Base.Flier_Nolans','Base.KeyRing_Nolans'].map((id,i)=>item(id,i,i%2?1.17:2.27));
 const centers=[[.0096114877,.062701257,.035596926],[-.011236936974785897,.070701257,.043702811563875184],[-.0013394090957733447,.062701257,.023642873027602672],[.004912760595006546,.070701257,.04512012998356786]];
 const targets=[[.6937080329726074,-.040671464055776596,.04214637891326867],[.5627801837179933,-.040671464055776596,-.03639451786340702],[.5499564096541059,-.040671464055776596,.0068079578145146535],[.5183123152920541,-.040671464055776596,-.174172225135218]];
 inputs.forEach((p,i)=>{p.center=centers[i];p.target=targets[i];p.landingArea={center:[.5385260208132102,-.040671464055776596,-.027700045495506954],radius:.24354685341585314};});
 inputs.push({center:[.014220800792625141,.36019398698015315,.14336946717661517],halfExtents:[.01266249967738986,.13686500675976276,.0446619987487793],quaternion:[.10552215377578283,.24228253541169706,.9578358164621901,.1127599077651697],target:[.522389930548918,-.040671464055776596,.4894132653543907],landingArea:{center:[.5369887087062282,-.040671464055776596,.487764380792484],radius:.04210526315789476},releaseTime:.56,flightTime:.5,mass:.9,index:4});
 const bake=bakeLoot(inputs,-.0438293587926187,4.7),track=bake.frames[2];
 bake.frames.forEach((data,i)=>{
  const end=data.slice(-7),area=inputs[i].landingArea;
  assert(Math.hypot(end[0]-area.center[0],end[2]-area.center[2])<=area.radius,'current scene prop escaped its marker');
 });
 for(const i of [0,1,3]){
   const data=bake.frames[i],a=new THREE.Vector3().fromArray(data,Math.round((inputs[i].releaseTime+.5)*60)*7),b=new THREE.Vector3().fromArray(data,Math.round((inputs[i].releaseTime+.7)*60)*7);
   console.log('landing glide',i,a.distanceTo(b));
   assert(Math.hypot(a.x-b.x,a.z-b.z)>.001,'prop glued at first contact');
 }
 const p=new THREE.Vector3().fromArray(track,Math.round(3.3*60)*7);
 const end=new THREE.Vector3().fromArray(track,track.length-7);
 assert(p.distanceTo(end)<.003,'late flyer drift '+p.distanceTo(end));
 assert.deepEqual(track.slice(-7),track.slice(-14,-7),'flyer never sleeps');
});
for(const delayed of [false,true]) test(`flyer pile settles without spontaneous relaunch (delayed=${delayed})`,()=>{
 const inputs=['Base.Flier_Nolans','Base.IDcard','Base.KeyRing_Nolans','Base.Receipt'].map((id,i)=>item(id,i,delayed?.2+i*1.5:.2));
 const bake=bakeLoot(inputs,0,10);
 for(let i=0;i<inputs.length;i++){
  const track=bake.frames[i];let maxLateStep=0;
  for(let f=8*60;f<bake.frameCount;f++){
   const p=new THREE.Vector3().fromArray(track,f*7),prev=new THREE.Vector3().fromArray(track,(f-1)*7);
   const q=new THREE.Quaternion().fromArray(track,f*7+3).normalize(),pq=new THREE.Quaternion().fromArray(track,(f-1)*7+3).normalize();
   maxLateStep=Math.max(maxLateStep,p.distanceTo(prev)+q.angleTo(pq)*Math.max(...inputs[i].halfExtents));
  }
  console.log({delayed,item:i,maxLateStep});
  assert(maxLateStep<1e-5,'resting prop resumes moving: '+maxLateStep);
 }
});
