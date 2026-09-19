import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import * as THREE from 'three';
import { applyClothMotion } from '../app/cloth-motion.ts';
import { createRigModel, skinRigModel, PzRagdollPose } from '../app/pz-rig.ts';

const read = (name) => JSON.parse(fs.readFileSync(new URL(name, import.meta.url), 'utf8'));
const catalog = read('../app/pz-catalog.json');
const front = read('../public/pz/rigs/poses/front.json');
const motion = {
  amount: 0, seed: 4 * 1.731 + 2.417, level: 1, index: 2,
  dressedPosition: new THREE.Vector3(0.2, 0.08, -0.17),
  target: new THREE.Vector3(-0.1, 0, -0.78),
};

test('all seeds leave attached clothing in the exact body coordinate system', () => {
  for (let id = 1; id <= 120; id += 1) {
    const group = new THREE.Group();
    const parameters = { ...motion, seed: id * 1.731 + 2.417 };
    for (const amount of [1, 0.5, 0, 0.1, 0]) {
      applyClothMotion(group, { ...parameters, amount });
    }
    assert.ok(group.position.equals(parameters.dressedPosition), `position changed for id ${id}`);
    assert.ok(group.quaternion.angleTo(new THREE.Quaternion()) < 1e-10, `attached clothing rotated for id ${id}: ${group.rotation.z}`);
  }
});

test('scrubbing forward and backward gives the same absolute transform', () => {
  for (const amount of [0, 0.1, 0.3, 0.55, 0.9, 1]) {
    const direct = new THREE.Group();
    const scrubbed = new THREE.Group();
    applyClothMotion(direct, { ...motion, amount });
    for (const previous of [1, 0.2, 0.8, 0.01, amount]) {
      applyClothMotion(scrubbed, { ...motion, amount: previous });
    }
    direct.updateMatrix();
    scrubbed.updateMatrix();
    assert.deepEqual(scrubbed.matrix.elements, direct.matrix.elements);
  }
});

test('LongShorts and Hoodie rendered vertices preserve the skinned pose through edit and Reset', () => {
  for (const sex of ['m', 'f']) {
    for (const [category, label] of [['shorts', 'LongShorts SportBlue'], ['hoodie', 'Hoodie CamoTree UP']]) {
      const variant = catalog.garments[category].variants[sex].find((item) => item.label === label);
      assert.ok(variant, `${sex} ${label}`);
      const model = createRigModel(read(`../public/pz/rigs/${sex}/${variant.model}.json`));
      const pose = new PzRagdollPose(front);
      skinRigModel(model, pose);
      const source = model.parts[0].geometry;
      source.computeBoundingBox();
      const center = source.boundingBox.getCenter(new THREE.Vector3());
      const instance = new THREE.Group();
      const visual = new THREE.Mesh(source.clone());
      visual.position.copy(center).negate();
      instance.add(visual);
      for (const state of ['base', 'edit', 'reset']) {
        if (state === 'edit') pose.dragHandle('leftHand', pose.getHandlePosition('leftHand').add(new THREE.Vector3(0.07, 0.09, -0.04)));
        if (state === 'reset') pose.reset();
        skinRigModel(model, pose);
        visual.geometry.getAttribute('position').copy(source.getAttribute('position'));
        applyClothMotion(instance, { ...motion, dressedPosition: center, amount: 0 });
        instance.updateMatrixWorld(true);
        const vertices = visual.geometry.getAttribute('position');
        const expected = source.getAttribute('position');
        let maxError = 0;
        for (let vertex = 0; vertex < vertices.count; vertex += 1) {
          const actual = new THREE.Vector3().fromBufferAttribute(vertices, vertex).applyMatrix4(visual.matrixWorld);
          maxError = Math.max(maxError, actual.distanceTo(new THREE.Vector3().fromBufferAttribute(expected, vertex)));
        }
        assert.ok(maxError < 1e-10, `${sex} ${label} ${state}: transformed away from its pose by ${maxError * 1000} mm`);
      }
      visual.geometry.dispose();
      model.parts.forEach((part) => part.geometry.dispose());
    }
  }
});
