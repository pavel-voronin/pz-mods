import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js';
import catalog from '../app/pz-pocket-loot.json' with {type:'json'};
import { importPocketLoot, gameRoot } from './import-pocket-loot.mjs';
import { normalizePocketId, generatePocketLoot } from '../app/pocket-loot.ts';
import { bakeLoot } from '../app/loot-physics.ts';

test('catalog is reproducible from installed zombie pocket tables and excludes notebooks / long weapons',()=>{
  assert.deepEqual(importPocketLoot(),catalog);
  assert.ok(Object.keys(catalog.items).length>200);
  for(const item of Object.values(catalog.items)){
    assert.ok(item.mass<=1.5 && item.mass>0);
    assert.ok(!/Notebook|Notepad|Diary|Journal/.test(item.id));
    assert.ok(!/^Base\.(Shotgun|ShotgunSawnoff|AssaultRifle\d*|DoubleBarrelShotgun)$/.test(item.id));
    assert.ok(item.pools.length>0);
    assert.ok(item.pools.every(id=>/^(inventorymale|inventoryfemale|Outfit_\w+)$/.test(id)));
    assert.ok(fs.existsSync(path.join(gameRoot,item.modelFile)));
    assert.ok(fs.existsSync(path.join(gameRoot,item.textureFile)));
  }
  for(const id of ['Base.KnifePocket','Base.KnifeButterfly','Base.SwitchKnife','Base.Handiknife','Base.Pistol','Base.Revolver_Short'])assert.ok(catalog.items[id],id);
  assert.equal(normalizePocketId('notebook','m'),undefined);
  assert.equal(normalizePocketId('Base.Notebook','f'),undefined);
  assert.equal(normalizePocketId('wallet','f'),'Base.Wallet_Female');
});

test('generated contents use one real pocket recipe, are distinct, and contain no notebook',()=>{
  let state=17;const random=()=>((state=Math.imul(state,1664525)+1013904223>>>0)/2**32);
  for(let i=0;i<200;i++){
    const result=generatePocketLoot(i%2?'m':'f',5,random);
    const recipe=catalog.pools.find(p=>p.id===result.recipe);
    assert.equal(result.items.length,new Set(result.items).size);
    assert.ok(result.items.every(id=>recipe.entries.some(e=>e.id===id)));
  }
});

test('mixed pocket weights settle on real contact without residual drift',()=>{
  const ids=['Base.SwitchKnife','Base.Pistol','Base.KnifeButterfly','Base.CigarettePack','Base.MoneyBundle'];
  const inputs=ids.map((id,index)=>({center:[0,.4,0],halfExtents:index===1?[.07,.018,.045]:[.035,.008,.016],
    quaternion:[0,0,0,1],target:[.5,0,.3],releaseTime:.2+index*.08,mass:catalog.items[id].mass,index}));
  const bake=bakeLoot(inputs,0,4);
  bake.frames.forEach((frames,index)=>{
    const last=frames.subarray(-7);
    assert.ok([...last].every(Number.isFinite));
    for(let frame=bake.frameCount-15;frame<bake.frameCount;frame++)assert.deepEqual(frames.subarray(frame*7,frame*7+7),last,ids[index]+' drifts');
    const q=new THREE.Quaternion(...last.subarray(3)),half=inputs[index].halfExtents;
    const bottom=Math.min(...[-1,1].flatMap(x=>[-1,1].flatMap(y=>[-1,1].map(z=>new THREE.Vector3(x*half[0],y*half[1],z*half[2]).applyQuaternion(q).y+last[1]))));
    assert.ok(bottom>=-.0004 && bottom<.1,ids[index]+' invalid support');
  });
});

test('every selectable game mesh loads with UVs and a finite physical size at its source scale',()=>{
  class GeometryTextures extends THREE.Loader {load(){return new THREE.Texture();}}
  const manager=new THREE.LoadingManager();manager.addHandler(/.*/,new GeometryTextures(manager));
  const loader=new FBXLoader(manager),cache=new Map(),sizes=[];
  for(const item of Object.values(catalog.items)){
    let bounds=cache.get(item.modelFile);
    if(!bounds){
      const buffer=fs.readFileSync(path.join(gameRoot,item.modelFile));
      if(item.modelFile.endsWith('.fbx')){
        const model=loader.parse(buffer.buffer.slice(buffer.byteOffset,buffer.byteOffset+buffer.byteLength),'');model.updateMatrixWorld(true);
        let count=0;model.traverse(mesh=>{if(mesh.isMesh){assert.ok(mesh.geometry.getAttribute('uv'),item.id+' missing UVs');count++;}});
        assert.ok(count,item.id);bounds=new THREE.Box3().setFromObject(model);
      }else{
        const lines=buffer.toString().split(/\r?\n/),numbers=line=>[...line.matchAll(/[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi)].map(m=>Number(m[0]));
        let at=lines.findIndex(line=>/^\s*Mesh(?:\s+\w+)?\s*\{/.test(line));assert.ok(at>=0,item.id);
        const count=numbers(lines[++at])[0];bounds=new THREE.Box3();
        for(let i=0;i<count;i++)bounds.expandByPoint(new THREE.Vector3(...numbers(lines[++at]).slice(0,3)));
        assert.ok(lines.some(line=>/^\s*MeshTextureCoords/.test(line)),item.id+' missing UVs');
      }
      cache.set(item.modelFile,bounds);
    }
    const size=bounds.getSize(new THREE.Vector3()).multiplyScalar(item.scale),longest=Math.max(...size.toArray());
    assert.ok(size.toArray().every(Number.isFinite) && longest>.001 && longest<1,item.id+' implausible size '+size.toArray());
    sizes.push({id:item.id,size:longest});
  }
  console.log('Largest source-scaled pocket props:',sizes.sort((a,b)=>b.size-a.size).slice(0,10));
  console.log('Unique geometry files:',cache.size);
});
