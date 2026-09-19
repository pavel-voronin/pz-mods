import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {clothReleaseVelocities} from '../app/cloth-release.ts';
import {bakeCloth,sampleCloth} from '../app/cloth-physics.ts';

const item=(z,layerId=0)=>({layerId,releaseTime:0,flightTime:.55,target:[1,0,0],seed:0,spin:0,
 surfaces:[{positions:new Float32Array([-.01,1,z-.01,.01,1,z-.01,0,1,z+.02]),
 uvs:new Float32Array([0,0,1,0,.5,1]),indices:new Uint32Array([0,1,2])}]});

test('one layer shares a throw vector, with a small outward spread instead of convergence',()=>{
 const items=[item(-.3),item(.3)],before=structuredClone(items),velocities=clothReleaseVelocities(items);
 assert.deepEqual(items,before);
 assert.equal(velocities[0].x,velocities[1].x);assert.equal(velocities[0].y,velocities[1].y);
 assert.ok(velocities[0].z<0 && velocities[1].z>0,'garments must spread, not aim at one point');
 const relative=new THREE.Vector3(0,0,.6).addScaledVector(velocities[1].clone().sub(velocities[0]),.55);
 assert.ok(relative.z>.6 && relative.z<.66);
 const moved=clothReleaseVelocities(items.map(i=>({...i,target:[2,0,0]})));
 assert.ok(Math.abs((moved[0].x-velocities[0].x)-1/.55)<1e-9);
 assert.equal(moved[0].x-velocities[0].x,moved[1].x-velocities[1].x);
});

test('other layers cannot alter a layer throw; singleton layers still aim at the marker',()=>{
 const items=[item(-.3),item(.3)],expected=clothReleaseVelocities(items);
 const actual=clothReleaseVelocities([...items,item(5,1)]);
 assert.deepEqual(actual.slice(0,2),expected);
 assert.ok(actual[2].z<0);
});

for(const quality of ['quick','precise'])test(quality+' solver retains garment ordering and spacing in flight',()=>{
 const bake=bakeCloth({items:[item(-.3),item(.3)],floor:-10,duration:.2,capsules:[]},undefined,quality);
 const center=(track,time)=>{
  const output=new Float32Array(track.positions.length);sampleCloth(track,bake,time,output);
  const result=new THREE.Vector3();
  for(let i=0;i<output.length;i+=3)result.add(new THREE.Vector3().fromArray(output,i));
  return result.multiplyScalar(3/output.length);
 };
 const initial=center(bake.tracks[1],0).sub(center(bake.tracks[0],0));
 const final=center(bake.tracks[1],.2).sub(center(bake.tracks[0],.2));
 assert.ok(final.z>initial.z && final.z-initial.z<.03,'layer collapsed or spread too far');
 assert.ok(Math.abs(final.x)<1e-5 && Math.abs(final.y)<1e-5);
});
