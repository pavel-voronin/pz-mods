import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import * as THREE from 'three';
import { rigAssetPath, rigAssetSource } from '../app/pz-model-assets.ts';
import { createRigModel, skinRigModel, PzRagdollPose, rigJointPositions } from '../app/pz-rig.ts';
import { applyClothMotion } from '../app/cloth-motion.ts';

const read = (relative) => JSON.parse(fs.readFileSync(new URL(relative, import.meta.url), 'utf8'));
const loadRig = (name, sex, set) => read(`../public${rigAssetPath(name, sex, set)}`);
const manifest = read('../app/pz-tomb-models.json');
const catalog = read('../app/pz-catalog.json');
const poses = fs.readdirSync(new URL('../public/pz/rigs/poses/', import.meta.url)).filter((name) => name.endsWith('.json'));

test('Tomb uses exact replacements, vanilla and non-replaced ClothingItems retain their own models', () => {
  for (const sex of ['m', 'f']) {
    assert.equal(Object.keys(manifest.models[sex]).length, 5);
    for (const [name, entry] of Object.entries(manifest.models[sex])) {
      assert.equal(rigAssetPath(name, sex, 'tomb'), entry.url);
      assert.equal(rigAssetSource(name, sex, 'tomb'), 'Tomb');
      assert.equal(rigAssetPath(name, sex, 'vanilla'), `/pz/rigs/${sex}/${name}.json`);
      assert.match(entry.sha256, /^[a-f0-9]{64}$/);
      const raw = loadRig(name, sex, 'tomb');
      assert.equal(raw.meshes.reduce((sum, mesh) => sum + mesh.positions.length / 3, 0), entry.vertices);
    }
    for (const category of Object.values(catalog.garments)) {
      for (const variant of category.variants[sex]) {
        const name = variant.model ?? category.model;
        if (!manifest.models[sex][name]) assert.equal(rigAssetPath(name, sex, 'tomb'), rigAssetPath(name, sex, 'vanilla'));
        assert.ok(loadRig(name, sex, 'tomb').meshes.length);
      }
    }
    assert.ok(manifest.models[sex].body.vertices > loadRig('body', sex, 'vanilla').meshes.reduce((sum, mesh) => sum + mesh.positions.length / 3, 0));
  }
});

test('all mod vertices have finite, normalized weights and valid joint indices', () => {
  for (const sex of ['m', 'f']) {
    for (const name of Object.keys(manifest.models[sex])) {
      for (const mesh of loadRig(name, sex, 'tomb').meshes) {
        assert.ok(mesh.positions.every(Number.isFinite));
        assert.ok(mesh.uvs.every(Number.isFinite));
        for (let vertex = 0; vertex < mesh.positions.length / 3; vertex += 1) {
          let weight = 0;
          for (let slot = 0; slot < 4; slot += 1) {
            const i = vertex * 4 + slot;
            assert.ok(mesh.joints[i] >= 0 && mesh.joints[i] < mesh.boneNames.length);
            assert.ok(Number.isFinite(mesh.weights[i]) && mesh.weights[i] >= 0);
            weight += mesh.weights[i];
          }
          assert.ok(Math.abs(weight - 1) < 1e-6);
        }
      }
    }
  }
});

test('Tomb body and clothing share all 16 poses, ragdoll edits and Reset without sequencer rotation', () => {
  assert.equal(poses.length, 16);
  for (const sex of ['m', 'f']) {
    const hoodie = catalog.garments.hoodie.variants[sex].find((item) => item.label === 'Hoodie CamoTree UP').model;
    const names = [...Object.keys(manifest.models[sex]), hoodie];
    const models = new Map(names.map((name) => [name, createRigModel(loadRig(name, sex, 'tomb'))]));
    for (const poseFile of poses) {
      const pose = new PzRagdollPose(read(`../public/pz/rigs/poses/${poseFile}`));
      for (const state of ['base', 'edit', 'reset']) {
        if (state === 'edit') {
          pose.dragHandle('leftHand', pose.getHandlePosition('leftHand').add(new THREE.Vector3(0.07, 0.09, -0.04)));
          pose.dragHandle('rightFoot', pose.getHandlePosition('rightFoot').add(new THREE.Vector3(-0.06, 0.05, 0.03)));
        }
        if (state === 'reset') pose.reset();
        const bodyJoints = rigJointPositions(models.get('body'), pose);
        for (const [name, model] of models) {
          skinRigModel(model, pose);
          for (const [bone, position] of rigJointPositions(model, pose)) {
            if (bodyJoints.has(bone)) assert.ok(position.distanceTo(bodyJoints.get(bone)) < 1e-8, `${sex}/${name} ${poseFile} ${state} ${bone}`);
          }
          for (const part of model.parts) {
            const vertices = part.geometry.getAttribute('position');
            const center = part.geometry.boundingBox.getCenter(new THREE.Vector3());
            const group = new THREE.Group();
            const visual = new THREE.Mesh(part.geometry);
            visual.position.copy(center).negate();
            group.add(visual);
            for (const amount of [1, 0.4, 0]) applyClothMotion(group, {
              amount, seed: 9.341, level: 1, index: 2,
              dressedPosition: center, target: new THREE.Vector3(0.1, 0, -0.8),
            });
            group.updateMatrixWorld(true);
            for (let i = 0; i < vertices.count; i += 1) {
              const expected = new THREE.Vector3().fromBufferAttribute(vertices, i);
              assert.ok(expected.toArray().every(Number.isFinite));
              assert.ok(expected.clone().applyMatrix4(visual.matrixWorld).distanceTo(expected) < 1e-10);
            }
            visual.material.dispose();
          }
        }
      }
    }
    models.forEach((model) => model.parts.forEach((part) => part.geometry.dispose()));
  }
});
