import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';
import * as CANNON from 'cannon-es';
import {FBXLoader} from 'three/examples/jsm/loaders/FBXLoader.js';
import {makeLootHull,boxVertices} from '../app/loot-collider.ts';
import {bakeLoot} from '../app/loot-physics.ts';
import catalog from '../app/pz-pocket-loot.json' with {type:'json'};
import {gameRoot} from './import-pocket-loot.mjs';

test('real ID card and receipt do not penetrate each other during landing',()=>{
 class Textures extends THREE.Loader {load(){return new THREE.Texture();}}
 const manager=new THREE.LoadingManager();manager.addHandler(/.*/,new Textures(manager));
 const inputs=['Base.Receipt','Base.IDcard'].map((id,index)=>{
  const d=catalog.items[id],b=fs.readFileSync(path.join(gameRoot,d.modelFile));
  const model=new FBXLoader(manager).parse(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),'');
  model.updateMatrixWorld(true);const bounds=new THREE.Box3().setFromObject(model),center=bounds.getCenter(new THREE.Vector3()),points=[];
  model.traverse(mesh=>{if(!mesh.isMesh)return;const p=mesh.geometry.getAttribute('position');for(let i=0;i<p.count;i++)points.push(new THREE.Vector3().fromBufferAttribute(p,i).applyMatrix4(mesh.matrixWorld).sub(center).multiplyScalar(d.scale));});
  return {center:[0,.3+index*.06,0],halfExtents:bounds.getSize(new THREE.Vector3()).multiplyScalar(d.scale*.5).toArray(),hull:makeLootHull(points),quaternion:[0,0,0,1],target:[.3,0,.2],releaseTime:.1+index*.04,mass:d.mass,index};
 });
 const shapes=inputs.map(input=>input.hull?new CANNON.ConvexPolyhedron({vertices:input.hull.vertices.map(p=>new CANNON.Vec3(...p)),faces:input.hull.faces}):new CANNON.Box(new CANNON.Vec3(...input.halfExtents.map(n=>Math.max(.00015,n)))).convexPolyhedronRepresentation);
 const bake=bakeLoot(inputs,0,3);let maxOverlap=0,contacts=0;
 for(const track of bake.frames){
  assert.ok(track.every(Number.isFinite));
  for(let at=0;at<track.length;at+=7)assert.ok(Math.hypot(track[at],track[at+1],track[at+2])<1,'collision launched a prop out of the scene');
 }
 for(let frame=10;frame<bake.frameCount;frame++){
  const poses=bake.frames.map(track=>({p:new CANNON.Vec3(...track.slice(frame*7,frame*7+3)),q:new CANNON.Quaternion(...track.slice(frame*7+3,frame*7+7))}));
  const axis=new CANNON.Vec3();
  if(shapes[0].findSeparatingAxis(shapes[1],poses[0].p,poses[0].q,poses[1].p,poses[1].q,axis)){
   const depth=shapes[0].testSepAxis(axis,shapes[1],poses[0].p,poses[0].q,poses[1].p,poses[1].q);
   if(depth!==false){maxOverlap=Math.max(maxOverlap,depth);contacts++;}
  }
 }
 console.log('ID/receipt max penetration',maxOverlap,'contact frames',contacts,'half extents',inputs.map(i=>i.halfExtents));
 assert.ok(maxOverlap<.0001,'ID penetrated receipt by '+maxOverlap);
});
