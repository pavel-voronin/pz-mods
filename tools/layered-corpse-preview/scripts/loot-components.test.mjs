import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';
import {FBXLoader} from 'three/examples/jsm/loaders/FBXLoader.js';
import {splitLootComponents,prepareLootParts} from '../app/loot-components.ts';
import {makeLootHull,lootBottom} from '../app/loot-collider.ts';
import {bakeLoot} from '../app/loot-physics.ts';
import catalog from '../app/pz-pocket-loot.json' with {type:'json'};
import {gameRoot} from './import-pocket-loot.mjs';

test('UV seams stay connected, but disjoint meshes split',()=>{
 const root=new THREE.Group();
 root.add(new THREE.Mesh(new THREE.BoxGeometry()));
 assert.equal(splitLootComponents(root).length,1);
 const second=new THREE.Mesh(new THREE.BoxGeometry());second.position.x=2;root.add(second);
 assert.equal(splitLootComponents(root).length,2);
 assert.equal(prepareLootParts(root,'unconfigured-model.fbx').length,1);
 second.position.set(1,1,1); // Exactly one shared corner, across transformed meshes.
 assert.equal(splitLootComponents(root).length,1);
});

test('disconnected triangles inside one mesh split without losing scale or UVs',()=>{
 const geometry=new THREE.BufferGeometry();
 geometry.setAttribute('position',new THREE.Float32BufferAttribute([0,0,0,1,0,0,0,1,0,3,0,0,4,0,0,3,1,0],3));
 geometry.setAttribute('uv',new THREE.Float32BufferAttribute([0,0,1,0,0,1,0,0,1,0,0,1],2));
 const root=new THREE.Group();root.scale.setScalar(.7);root.add(new THREE.Mesh(geometry));
 const parts=splitLootComponents(root);assert.equal(parts.length,2);
 assert.ok(Math.abs(parts.reduce((sum,p)=>sum+p.area,0)-.49)<1e-6);
 assert.ok(Math.abs(new THREE.Box3().setFromObject(parts[1].group).min.x-2.1)<1e-6);
 for(const part of parts)assert.equal(part.group.children[0].geometry.getAttribute('uv').count,3);
});

test('actual lipstick components have independent rigid tracks and floor support',()=>{
 class Textures extends THREE.Loader {load(){return new THREE.Texture();}}
 const manager=new THREE.LoadingManager();manager.addHandler(/.*/,new Textures(manager));
 const definition=catalog.items['Base.Lipstick'],buffer=fs.readFileSync(path.join(gameRoot,definition.modelFile));
 const model=new FBXLoader(manager).parse(buffer.buffer.slice(buffer.byteOffset,buffer.byteOffset+buffer.byteLength),'');
 const root=new THREE.Group();root.scale.setScalar(definition.scale);root.add(model);
 const parts=prepareLootParts(root,definition.model);assert.equal(parts.length,2);
 const originalBounds=new THREE.Box3().setFromObject(root),combinedBounds=new THREE.Box3();
 parts.forEach(part=>combinedBounds.union(new THREE.Box3().setFromObject(part.group)));
 assert.ok(originalBounds.min.distanceTo(combinedBounds.min)<1e-7);
 assert.ok(originalBounds.max.distanceTo(combinedBounds.max)<1e-7);
 assert.equal(parts[0].group.children.length,3,'case, collar and lipstick remain one body');
 assert.equal(parts[1].group.children.length,1,'cap is the second body');
 const total=parts.reduce((sum,p)=>sum+p.area,0);
 const inputs=parts.map(({group,area},index)=>{
  const bounds=new THREE.Box3().setFromObject(group),center=bounds.getCenter(new THREE.Vector3()),points=[];
  group.traverse(mesh=>{if(!mesh.isMesh)return;const p=mesh.geometry.getAttribute('position');for(let i=0;i<p.count;i++)points.push(new THREE.Vector3().fromBufferAttribute(p,i).sub(center));});
  const hull=makeLootHull(points);assert.ok(hull);
  return {center:center.add(new THREE.Vector3(0,.35,0)).toArray(),halfExtents:bounds.getSize(new THREE.Vector3()).multiplyScalar(.5).toArray(),hull,quaternion:[0,0,0,1],target:[.5,0,.3],releaseTime:.2,mass:definition.mass*area/total,index};
 });
 assert.ok(Math.abs(inputs.reduce((sum,p)=>sum+p.mass,0)-definition.mass)<1e-10);
 const bake=bakeLoot(inputs,0,5);assert.equal(bake.frames.length,parts.length);
 for(let index=0;index<parts.length;index++){
  const frames=bake.frames[index];assert.ok(frames.every(Number.isFinite));
  for(let i=Math.ceil(.2*bake.fps)*7;i<frames.length;i+=7)assert.ok(frames[i+1]+lootBottom(inputs[index].hull.vertices,new THREE.Quaternion().fromArray(frames,i+3))>=-1e-7);
 }
 assert.notDeepEqual(bake.frames[0],bake.frames[1]);
 console.log('Lipstick independent components:',parts.length);
});
