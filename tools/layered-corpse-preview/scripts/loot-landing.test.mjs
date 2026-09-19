import test from 'node:test';
import assert from 'node:assert/strict';
import {bakeLoot} from '../app/loot-physics.ts';
test('final resting centres stay inside the chosen disk, including a weapon',()=>{
 for(const radius of [.04,.08,.16]){
  const inputs=Array.from({length:5},(_,index)=>({center:[0,.35,0],halfExtents:index===4?[.025,.18,.015]:[.02,.008,.015],quaternion:[0,0,0,1],target:[.6,0,.3],landingArea:{center:[.6,0,.3],radius},releaseTime:.1+Math.floor(index/2)*.7,flightTime:.5,mass:index===4?.9:.05,index}));
  inputs[4].target=[-.4,0,.3];inputs[4].landingArea.center=[-.4,0,.3];
  const bake=bakeLoot(inputs,0,5);
  bake.frames.forEach((track,index)=>{const end=track.subarray(-7),center=inputs[index].landingArea.center;assert.ok(Math.hypot(end[0]-center[0],end[2]-center[2])<=radius,JSON.stringify({radius,end:[...end]}));assert.deepEqual(track.subarray(-14,-7),end,'not settled');});
 }
});
