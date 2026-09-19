import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import { inflateSync } from 'node:zlib';
import * as THREE from 'three';
import { createRigModel, skinRigModel, PzRagdollPose } from '../app/pz-rig.ts';
import { rigAssetPath } from '../app/pz-model-assets.ts';
import { clothSurface } from '../app/cloth-surface.ts';
import { bakeCloth, CLOTH_THICKNESS } from '../app/cloth-physics.ts';

const read = (path) => JSON.parse(fs.readFileSync(new URL(path, import.meta.url)));
const catalog = read('../app/pz-catalog.json');

// The checked-in test textures are non-interlaced, 8-bit RGBA PNGs.
function rgbaPng(path) {
  const bytes = fs.readFileSync(new URL('../public' + path, import.meta.url));
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  assert.equal(bytes[24], 8); assert.equal(bytes[25], 6); assert.equal(bytes[28], 0);
  const parts = [];
  for (let offset = 8; offset < bytes.length;) {
    const length = bytes.readUInt32BE(offset);
    if (bytes.toString('ascii', offset + 4, offset + 8) === 'IDAT') parts.push(bytes.subarray(offset + 8, offset + 8 + length));
    offset += length + 12;
  }
  const filtered = inflateSync(Buffer.concat(parts)), data = new Uint8ClampedArray(width * height * 4);
  const stride = width * 4;
  for (let y = 0; y < height; y++) {
    const filter = filtered[y * (stride + 1)];
    for (let x = 0; x < stride; x++) {
      const a = x >= 4 ? data[y * stride + x - 4] : 0;
      const b = y ? data[(y - 1) * stride + x] : 0;
      const c = y && x >= 4 ? data[(y - 1) * stride + x - 4] : 0;
      const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
      const paeth = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      const predictor = [0, a, b, Math.floor((a + b) / 2), paeth][filter];
      data[y * stride + x] = (filtered[y * (stride + 1) + 1 + x] + predictor) & 255;
    }
  }
  return { data, width, height };
}

for (const [set, sex, poseName, garments] of [
  ['tomb', 'm', 'front', [['trousers','trousers-camo-dcu'], ['shirt','tshirt-white'], ['underpants','male-boxers-white']]],
  ['vanilla', 'm', 'back', [['hoodie','hoodie-camotree-down'], ['shorts','longshorts-camogreen']]],
]) test(set + ' real garments leave the corpse, retain their dimensions and form a grounded pile', () => {
  const pose = new PzRagdollPose(read('../public/pz/rigs/poses/' + poseName + '.json'));
  const load = (name) => {
    const rig = createRigModel(read('../public' + rigAssetPath(name, sex, set)));
    skinRigModel(rig, pose);
    return rig;
  };
  const body = load('body');
  const bounds = new THREE.Box3();
  body.parts.forEach(({ geometry }) => bounds.union(geometry.boundingBox));
  const center = bounds.getCenter(new THREE.Vector3()), floor = bounds.min.y - .006 / 1.9;
  const target = [center.x - .72 / 1.9, floor, center.z - .72 / 1.9];
  const links = [['pelvis','waist',.055],['waist','chest',.06],['neck','head',.04],
    ['leftShoulder','leftElbow',.021],['leftElbow','leftHand',.015],['rightShoulder','rightElbow',.021],['rightElbow','rightHand',.015],
    ['leftHip','leftKnee',.033],['leftKnee','leftFoot',.024],['rightHip','rightKnee',.033],['rightKnee','rightFoot',.024]];
  const capsules = links.map(([a,b,radius]) => ({a:pose.getHandlePosition(a).toArray(), b:pose.getHandlePosition(b).toArray(), radius}));
  const originals = [];
  const items = garments.map(([category,value], index) => {
    const variant = catalog.garments[category].variants[sex].find((item) => item.value === value);
    const rig = load(variant.model ?? catalog.garments[category].model);
    const surfaces = rig.parts.map(({geometry}) => clothSurface(geometry, rgbaPng(variant.texture)));
    originals.push(surfaces.map((surface) => surface.positions.slice()));
    return {surfaces,releaseTime:.3 + index * .8,target,seed:index * 1.731};
  });
  const started = performance.now();
  const bake = bakeCloth({items,floor,duration:4.6,capsules});
  bake.tracks.forEach((track, index) => {
    items[index].surfaces.forEach((surface, part) => assert.deepEqual(surface.positions, originals[index][part], 'source pose mutated'));
    const p = (frame, id) => new THREE.Vector3().fromArray(track.frames, (frame * track.particleCount + id) * 3);
    const centre = (frame) => {
      const sum = new THREE.Vector3();
      for (let i = 0; i < track.particleCount; i++) sum.add(p(frame, i));
      return sum.divideScalar(track.particleCount);
    };
    const final = centre(bake.frameCount - 1);
    assert.ok(final.distanceTo(centre(0)) > .22, 'garment remains trapped on body: ' + garments[index]);
    assert.ok(Math.hypot(final.x - target[0], final.z - target[2]) < .25,
      'garment missed pile: '+garments[index].join('/')+' '+JSON.stringify({centre:final.toArray(),target}));
    const strains = [];
    for (let i = 0; i < track.indices.length; i += 3) for (let j = 0; j < 3; j++) {
      const a = track.particleForVertex[i+j], b = track.particleForVertex[i+(j+1)%3];
      strains.push(Math.abs(p(bake.frameCount-1,a).distanceTo(p(bake.frameCount-1,b)) / p(0,a).distanceTo(p(0,b)) - 1));
    }
    strains.sort((a,b) => a-b);
    const mean = strains.reduce((a,b) => a+b,0) / strains.length;
    console.log(garments[index].join('/'), {particles:track.particleCount, meanStrain:mean, p95: strains[Math.floor(strains.length*.95)], centre:final.toArray()});
    assert.ok(mean < .02, 'cloth has changed size: mean strain ' + mean);
    assert.ok(strains[Math.floor(strains.length*.95)] < .08, 'cloth is over-stretched');
    for (let i=0; i<track.particleCount; i++) {
      const end=p(bake.frameCount-1,i);
      assert.ok(end.toArray().every(Number.isFinite));
      assert.ok(end.y >= floor + CLOTH_THICKNESS*.49, 'cloth passes below ground');
    }
  });
  console.log(set + ' cloth bake: ' + ((performance.now()-started)/1000).toFixed(2) + ' s');
});
