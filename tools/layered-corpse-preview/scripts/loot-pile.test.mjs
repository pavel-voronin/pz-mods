import test from 'node:test';
import assert from 'node:assert/strict';
import {bakeLoot} from '../app/loot-physics.ts';
test('simultaneous overlapping pocket sources form a compact physical pile',()=>{
 for(const count of [2,5,10]) {
  const inputs=Array.from({length:count},(_,index)=>({center:[0,.35,0],
   halfExtents:index%4===0?[.055,.012,.035]:[.022,.009,.016],quaternion:[0,0,0,1],
   target:[.6+Math.cos(index*2.399963)*.02,0,.4+Math.sin(index*2.399963)*.02],
   releaseTime:.2,flightTime:.5,mass:index%4===0?.8:.025,index}));
  const bake=bakeLoot(inputs,0,4);
  let maxRadius=0;
  for(const frames of bake.frames) {
   assert.ok(frames.every(Number.isFinite));
   const final=frames.subarray(-7),radius=Math.hypot(final[0]-.6,final[2]-.4);
   maxRadius=Math.max(maxRadius,radius);
   assert.ok(radius<.19,'escaped pile: '+radius);
   assert.deepEqual(frames.subarray(-14,-7),final,'still drifting');
   for(let frame=1;frame<bake.frameCount;frame++) {
    const x=frames[frame*7],z=frames[frame*7+2];
    assert.ok(x>-.3&&x<.9&&z>-.3&&z<.7,'explosive contact');
   }
  }
  console.log(count+' props: max pile radius '+maxRadius.toFixed(3));
 }
});
