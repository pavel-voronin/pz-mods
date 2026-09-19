import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';
import { bakeCloth, sampleCloth, CLOTH_THICKNESS } from '../app/cloth-physics.ts';
import { clothSurface } from '../app/cloth-surface.ts';
import { bakeLoot } from '../app/loot-physics.ts';
import { defaultDropPoints, randomDropPoints } from '../app/scene-layout.ts';
import { clothNormals } from '../app/cloth-normals.ts';

const square = (y) => ({
  positions: new Float32Array([-.15,y,-.15, .15,y,-.15, .15,y,.15, -.15,y,.15]),
  uvs: new Float32Array([0,0,1,0,1,1,0,1]),
  indices: new Uint32Array([0,1,2,0,2,3]),
});
const vertex = (track, frame, id) => new THREE.Vector3().fromArray(track.frames, (frame * track.particleCount + id) * 3);
const last = (track, bake) => track.frames.subarray((bake.frameCount - 1) * track.particleCount * 3);

test('default and randomized drop zones retain foreground left/right and rear centre', () => {
  for (const points of [defaultDropPoints(), ...Array.from({ length: 100 }, randomDropPoints)]) {
    assert.ok(points.weapon.x + points.weapon.z > .7);
    assert.ok(points.weapon.x - points.weapon.z < -.8);
    assert.ok(points.valuables.x + points.valuables.z > .7);
    assert.ok(points.valuables.x - points.valuables.z > .8);
    assert.ok(points.clothing.x + points.clothing.z < -1.2);
    assert.ok(Math.abs(points.clothing.x - points.clothing.z) < .15);
  }
});

test('cloth keeps dimensions, collides with another layer, and can be scrubbed reversibly', () => {
  const input = { floor: 0, duration: 4, capsules: [], items: [
    { surfaces: [square(.3)], releaseTime: .1, target: [0,0,0], seed: 0 },
    { surfaces: [square(.45)], releaseTime: 1.2, target: [0,0,0], seed: 1 },
  ] };
  const bake = bakeCloth(input);
  for (const track of bake.tracks) {
    let worst = 0, sum = 0, count = 0;
    for (let i = 0; i < track.indices.length; i += 3) {
      for (let k = 0; k < 3; k++) {
        const a = track.particleForVertex[i + k], b = track.particleForVertex[i + (k + 1) % 3];
        const rest = vertex(track, 0, a).distanceTo(vertex(track, 0, b));
        const end = vertex(track, bake.frameCount - 1, a).distanceTo(vertex(track, bake.frameCount - 1, b));
        const strain = Math.abs(end / rest - 1);
        worst = Math.max(worst, strain); sum += strain; count++;
      }
    }
    assert.ok(worst < .06, 'worst edge strain ' + worst);
    assert.ok(sum / count < .01, 'mean edge strain ' + sum / count);
    for (let i = 1; i < last(track, bake).length; i += 3) assert.ok(last(track, bake)[i] >= CLOTH_THICKNESS * .499);
    const output = new Float32Array(track.positions.length);
    sampleCloth(track, bake, .05, output);
    assert.deepEqual(output, track.positions, 'attached geometry must be byte-identical');
    sampleCloth(track, bake, 2.375, output);
    const direct = output.slice();
    for (const time of [4, .6, 3.9, .01, 2.375]) sampleCloth(track, bake, time, output);
    assert.deepEqual(output, direct);
  }
  const lower = bake.tracks[0], upper = bake.tracks[1];
  let supported = 0;
  for (let i = 0; i < upper.particleCount; i++) {
    const p = vertex(upper, bake.frameCount - 1, i);
    for (let face = 0; face < lower.indices.length; face += 3) {
      const ids = [0,1,2].map((j) => lower.particleForVertex[face + j]);
      const t = new THREE.Triangle(...ids.map((id) => vertex(lower, bake.frameCount - 1, id)));
      const closest = t.closestPointToPoint(p, new THREE.Vector3());
      assert.ok(closest.distanceTo(p) > CLOTH_THICKNESS * .85, 'separate cloth layers must not occupy same surface');
      if (closest.distanceTo(p) < CLOTH_THICKNESS * 1.7) supported++;
    }
  }
  assert.ok(supported > 10, 'upper cloth should rest on lower cloth');
});

test('invisible body-atlas regions do not become phantom cloth colliders', () => {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array([0,0,0,1,0,0,0,1,0,2,0,0,3,0,0,2,1,0]), 3));
  geometry.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([.1,.1,.2,.1,.1,.2,.8,.8,.9,.8,.8,.9]), 2));
  const image = { width: 10, height: 10, data: new Uint8ClampedArray(400) };
  for (let y = 0; y < 5; y++) for (let x = 0; x < 5; x++) image.data[(y * 10 + x) * 4 + 3] = 255;
  const before = geometry.getAttribute('position').array.slice();
  assert.deepEqual([...clothSurface(geometry, image).indices], [0,1,2]);
  assert.deepEqual(geometry.getAttribute('position').array, before, 'worn mesh stays untouched');
});

test('airborne cloth accelerates under Earth gravity instead of being damped by its own contacts', () => {
  const surface = {
    positions: new Float32Array([0,1,0, .02,1,0, 0,1,.02]),
    uvs: new Float32Array([0,0,1,0,0,1]), indices: new Uint32Array([0,1,2]),
  };
  const bake = bakeCloth({floor:-10,duration:.2,capsules:[],items:[{surfaces:[surface],releaseTime:0,target:[0,-10,0],seed:0}]});
  const track = bake.tracks[0];
  const y = (frame) => Array.from({length:track.particleCount},(_,i)=>vertex(track,frame,i).y).reduce((a,b)=>a+b)/track.particleCount;
  const acceleration = (y(8)-2*y(7)+y(6))*bake.fps*bake.fps;
  assert.ok(acceleration < -9.6 && acceleration > -10.1, 'wrong acceleration: ' + acceleration);
});

test('cloth lighting stays continuous across duplicate UV-seam vertices', () => {
  const positions = new Float32Array([0,0,0, 1,0,0, 0,1,0, 0,0,0, 0,1,0, 0,0,1]);
  const track = {particleForVertex:new Uint32Array([0,1,2,0,2,3])};
  const normals = new Float32Array(positions.length);
  clothNormals(track,positions,normals,new Float32Array(12));
  assert.deepEqual(normals.subarray(0,3),normals.subarray(9,12));
  assert.deepEqual(normals.subarray(6,9),normals.subarray(12,15));
  for(let i=0;i<normals.length;i+=3) assert.ok(Math.abs(Math.hypot(...normals.subarray(i,i+3))-1)<1e-6);
});

test('seven colliding loot bodies settle and stop drifting without freezing above their support', () => {
  const inputs = Array.from({ length: 7 }, (_, index) => ({
    center: [0,.4,0], halfExtents: [.025,.009,.037], quaternion: [0,0,0,1],
    target: [.6,0,.4], releaseTime: .6 + index * .08, mass: .02, index,
  }));
  const bake = bakeLoot(inputs, 0, 4);
  bake.frames.forEach((track, index) => {
    const final = track.subarray(-7);
    for (let frame = bake.frameCount - 31; frame < bake.frameCount; frame++) {
      assert.deepEqual(track.subarray(frame * 7, frame * 7 + 7), final, 'loot ' + index + ' drifts at rest');
    }
    const q = new THREE.Quaternion(...final.subarray(3));
    const bottom = Math.min(...[-1,1].flatMap((x) => [-1,1].flatMap((y) => [-1,1].map((z) =>
      new THREE.Vector3(x * .025, y * .009, z * .037).applyQuaternion(q).y + final[1]))));
    assert.ok(bottom > -.0003, 'box passes through floor');
    assert.ok(bottom < .05, 'unsupported box suspended above pile');
  });
  const single = bakeLoot([inputs[0]], 0, 3).frames[0].subarray(-7);
  const q = new THREE.Quaternion(...single.subarray(3));
  const bottom = Math.min(...[-1,1].flatMap((x) => [-1,1].flatMap((y) => [-1,1].map((z) =>
    new THREE.Vector3(x * .025, y * .009, z * .037).applyQuaternion(q).y + single[1]))));
  assert.ok(Math.abs(bottom) < .0003, 'isolated object must touch floor');
});
