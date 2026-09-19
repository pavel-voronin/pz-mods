import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import { bakeQuickPreview } from '../app/cloth-rigid-preview.ts';
import { sampleCloth } from '../app/cloth-physics.ts';
import { garmentReleaseFan } from '../app/scene-layout.ts';
import { createRigModel, skinRigModel, PzRagdollPose } from '../app/pz-rig.ts';
import { rigAssetPath } from '../app/pz-model-assets.ts';
const read=path=>JSON.parse(fs.readFileSync(new URL(path,import.meta.url)));

test('same-layer garments release together into a compact fan with equal flight time',()=>{
 for(let count=1;count<12;count++) {
  const fans=Array.from({length:count},(_,i)=>garmentReleaseFan(i,count,2));
  assert.ok(fans.every(f=>f.delay===0 && f.flight===.55 && Math.hypot(f.x,f.z)<=.041));
 }
});

test('real Tomb and vanilla previews deform cloth, preserve worn vertices and seek deterministically',()=>{
 const times=[];
 for(const modelSet of ['tomb','vanilla']) {
  const pose=new PzRagdollPose(read('../public/pz/rigs/poses/front.json'));
  const items=['trousers','jumper'].map((name,index)=>{
   const rig=createRigModel(read('../public'+rigAssetPath(name,'m',modelSet)));skinRigModel(rig,pose);
   return {surfaces:rig.parts.map(({geometry:g})=>({positions:g.getAttribute('position').array,uvs:g.getAttribute('uv').array,
    indices:g.index?.array??Uint32Array.from({length:g.getAttribute('position').count},(_,i)=>i)})),releaseTime:.3,target:[-.5,-.05,-.5],flightTime:.55,seed:index};
  });
  const input={items,floor:-.05,duration:3,capsules:[],loot:[]},before=structuredClone(input);
  const started=performance.now(), bake=bakeQuickPreview(input);times.push(performance.now()-started);
  assert.deepEqual(input,before);
  bake.tracks.forEach((track,i)=>{
   assert.equal(track.indices.length,items[i].surfaces.reduce((sum,s)=>sum+s.indices.length,0));
   assert.ok(track.frames.every(Number.isFinite));
   const out=new Float32Array(track.positions.length);
   sampleCloth(track,bake,0,out);assert.deepEqual(out,track.positions);
   sampleCloth(track,bake,1.237,out);const expected=out.slice();
   for(const t of [3,0,.5,1.237])sampleCloth(track,bake,t,out);
   assert.deepEqual(out,expected);
   sampleCloth(track,bake,3,out);
   assert.ok(out.filter((_,i)=>i%3===1).every(y=>y>=input.floor-1e-6));
   // A rigid transform preserves all pairwise distances; cloth must not.
   let changed=0;
   for(let j=3;j<out.length;j+=3) {
    const distance=(a)=>Math.hypot(a[j]-a[0],a[j+1]-a[1],a[j+2]-a[2]);
    changed=Math.max(changed,Math.abs(distance(out)-distance(track.positions)));
   }
   assert.ok(changed>.01,'preview still rigid');
  });
 }
 console.log('Quick cloth timings ms:',times.map(Math.round));
 assert.ok(Math.max(...times)<5000,'interactive preview too expensive');
});

test('expensive worker remains explicit and export locks its selected quality',()=>{
 const source=fs.readFileSync(new URL('../app/page.tsx',import.meta.url),'utf8');
 const begin=source.indexOf('const calculateCloth ='),end=source.indexOf('const cancelCloth =',begin);
 assert.equal([...source.matchAll(/new ClothWorker\(/g)].length,1);
 assert.ok(source.slice(begin,end).includes('new ClothWorker('));
 assert.ok(source.includes('version !== bakeVersion'));
 assert.ok(source.includes('exportUsesPrecise = usePreciseCloth'));
 assert.ok(source.includes('new QuickWorker()'));
 assert.ok(!source.includes('bakeQuickPreview(makePhysicsInput())'),'preview must not block the main thread');
 assert.ok(source.includes('reuseLoot:quickPreview.loot'),'precise cloth must reuse the same rigid trajectories');
 assert.ok(!source.includes('simulateRigidBody('),'axe must use cached frames, not restart integration each frame');
});
