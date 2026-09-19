import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';
import {FBXLoader} from 'three/examples/jsm/loaders/FBXLoader.js';
import {makeLootHull,boxVertices,lootBottom,stableLootSupport} from '../app/loot-collider.ts';
import {bakeLoot} from '../app/loot-physics.ts';
import catalog from '../app/pz-pocket-loot.json' with {type:'json'};
import {gameRoot} from './import-pocket-loot.mjs';

test('contact footprint rejects a false edge prop and accepts a supporting face',()=>{
 assert.equal(stableLootSupport([{x:.02,z:-.01},{x:.02,z:.01}]),false);
 assert.equal(stableLootSupport([{x:-.02,z:-.01},{x:.02,z:-.01},{x:.02,z:.01},{x:-.02,z:.01}]),true);
});
for(const itemId of ['Base.Lipstick','Base.IDcard','Base.Wallet_Male'])test(itemId+' actual hull rests on its visible surface and never crosses the floor',()=>{
 class Textures extends THREE.Loader {load(){return new THREE.Texture();}}
 const manager=new THREE.LoadingManager();manager.addHandler(/.*/,new Textures(manager));
 const definition=catalog.items[itemId],buffer=fs.readFileSync(path.join(gameRoot,definition.modelFile));
 const model=new FBXLoader(manager).parse(buffer.buffer.slice(buffer.byteOffset,buffer.byteOffset+buffer.byteLength),'');model.updateMatrixWorld(true);
 const bounds=new THREE.Box3().setFromObject(model),center=bounds.getCenter(new THREE.Vector3()),points=[];
 model.traverse(mesh=>{if(!mesh.isMesh)return;const p=mesh.geometry.getAttribute('position');for(let i=0;i<p.count;i++)points.push(new THREE.Vector3().fromBufferAttribute(p,i).applyMatrix4(mesh.matrixWorld).sub(center).multiplyScalar(definition.scale));});
 const hull=makeLootHull(points);assert.ok(hull);
 const half=bounds.getSize(new THREE.Vector3()).multiplyScalar(definition.scale*.5).toArray();
 const bake=bakeLoot([{center:[0,.35,0],halfExtents:half,quaternion:[0,0,0,1],hull,target:[.5,0,.3],releaseTime:.2,mass:definition.mass,index:0}],0,5);
 const frames=bake.frames[0],last=frames.subarray(-7),q=new THREE.Quaternion(...last.slice(3));
 assert.ok(Math.abs(last[1]+lootBottom(hull.vertices,q))<.0002);
 const renderedMin=Math.min(...points.map(p=>p.clone().applyQuaternion(q).y+last[1]));
 assert.ok(renderedMin>=-1e-6&&renderedMin<.0002,'lipstick supported by empty space: '+renderedMin);
 for(let i=Math.ceil(.2*bake.fps)*7;i<frames.length;i+=7)assert.ok(frames[i+1]+lootBottom(hull.vertices,new THREE.Quaternion().fromArray(frames,i+3))>=-1e-7,itemId+' crossed floor');
 console.log(itemId+' visible floor gap',renderedMin);
});
test('thin card never crosses floor in cached or interpolated frames',()=>{
 const half=[.025,.00015,.016],vertices=boxVertices(half);
 const bake=bakeLoot([{center:[0,.4,0],halfExtents:half,quaternion:[0,0,0,1],target:[.4,0,.2],releaseTime:.1,mass:.01,index:0,angularVelocity:[7,4,3]}],0,3);
 const frames=bake.frames[0];
 for(let time=.101;time<3;time+=.0013){
  const f=time*bake.fps,lo=Math.floor(f),hi=Math.min(lo+1,bake.frameCount-1),mix=f-lo;
  const q=new THREE.Quaternion().fromArray(frames,lo*7+3).slerp(new THREE.Quaternion().fromArray(frames,hi*7+3),mix);
  const p=new THREE.Vector3().fromArray(frames,lo*7).lerp(new THREE.Vector3().fromArray(frames,hi*7),mix);
  p.y=Math.max(p.y,-lootBottom(vertices,q));
  assert.ok(p.y+lootBottom(vertices,q)>=-1e-10);
 }
 for(let i=7;i<frames.length;i+=7)assert.ok(frames[i+1]+lootBottom(vertices,new THREE.Quaternion().fromArray(frames,i+3))>=-1e-7);
});
