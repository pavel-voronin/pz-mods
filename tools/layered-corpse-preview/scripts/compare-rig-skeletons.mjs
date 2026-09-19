import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';

const root = process.cwd();
const sex = process.argv[2] ?? 'm';
const poseName = process.argv[3] ?? 'front';
const modelNames = process.argv.slice(4);
const rigs = modelNames.length ? modelNames : ['body', 'garment-bob-jacketleather', 'suittrousers'];
const trackedBones = [
  'Bip01_Pelvis',
  'Bip01_Spine',
  'Bip01_Spine1',
  'Bip01_L_UpperArm',
  'Bip01_L_Forearm',
  'Bip01_L_Hand',
  'Bip01_R_UpperArm',
  'Bip01_R_Forearm',
  'Bip01_R_Hand',
  'Bip01_L_Thigh',
  'Bip01_L_Calf',
  'Bip01_L_Foot',
  'Bip01_R_Thigh',
  'Bip01_R_Calf',
  'Bip01_R_Foot',
];

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function matrixFromRowMajor(values) {
  return new THREE.Matrix4().set(
    values[0], values[1], values[2], values[3],
    values[4], values[5], values[6], values[7],
    values[8], values[9], values[10], values[11],
    values[12], values[13], values[14], values[15],
  );
}

function position(matrix) {
  return new THREE.Vector3().setFromMatrixPosition(matrix);
}

function rotation(matrix) {
  return new THREE.Quaternion().setFromRotationMatrix(matrix).normalize();
}

function degreesBetween(left, right) {
  return THREE.MathUtils.radToDeg(left.angleTo(right));
}

function skinMatrix(pose, offset, order = 'pose-offset') {
  return order === 'offset-pose'
    ? offset.clone().multiply(pose)
    : pose.clone().multiply(offset);
}

const poseFile = process.env.POSE_FILE || path.join(root, 'public', 'pz', 'rigs', 'poses', `${poseName}.json`);
const pose = readJson(poseFile);
const poseGlobals = new Map(Object.entries(pose).map(([name, values]) => [name, matrixFromRowMajor(values)]));
const loaded = new Map(rigs.map((name) => {
  const json = readJson(path.join(root, 'public', 'pz', 'rigs', sex, `${name}.json`));
  const mesh = json.meshes[0];
  const bones = new Map(mesh.boneNames.map((bone, index) => [bone, {
    offset: matrixFromRowMajor(mesh.offsets[index]),
  }]));
  bones.forEach((bone) => { bone.bind = bone.offset.clone().invert(); });
  return [name, { json, mesh, bones }];
}));

const body = loaded.get('body');
if (!body) throw new Error('The comparison requires body.json');

const diagnosticSegments = [
  ['Bip01_Pelvis', 'Bip01_Spine'], ['Bip01_Spine', 'Bip01_Spine1'],
  ['Bip01_Spine1', 'Bip01_Neck'], ['Bip01_Neck', 'Bip01_Head'],
  ['Bip01_Spine1', 'Bip01_L_UpperArm'], ['Bip01_L_UpperArm', 'Bip01_L_Forearm'],
  ['Bip01_L_Forearm', 'Bip01_L_Hand'], ['Bip01_Spine1', 'Bip01_R_UpperArm'],
  ['Bip01_R_UpperArm', 'Bip01_R_Forearm'], ['Bip01_R_Forearm', 'Bip01_R_Hand'],
  ['Bip01_Pelvis', 'Bip01_L_Thigh'], ['Bip01_L_Thigh', 'Bip01_L_Calf'],
  ['Bip01_L_Calf', 'Bip01_L_Foot'], ['Bip01_Pelvis', 'Bip01_R_Thigh'],
  ['Bip01_R_Thigh', 'Bip01_R_Calf'], ['Bip01_R_Calf', 'Bip01_R_Foot'],
];

console.log('\nBody segment length preservation (bind -> pose):');
for (const [start, end] of diagnosticSegments) {
  const bindStart = body.bones.get(start)?.bind;
  const bindEnd = body.bones.get(end)?.bind;
  const poseStart = poseGlobals.get(start);
  const poseEnd = poseGlobals.get(end);
  if (!bindStart || !bindEnd || !poseStart || !poseEnd) continue;
  const bindLength = position(bindStart).distanceTo(position(bindEnd));
  const poseLength = position(poseStart).distanceTo(position(poseEnd));
  console.log(`${start} -> ${end}: ${bindLength.toFixed(6)} -> ${poseLength.toFixed(6)} m, error ${((poseLength - bindLength) * 1000).toFixed(3)} mm`);
}

function skinnedVertices(model, order = 'pose-offset') {
  const result = [];
  for (let vertex = 0; vertex < model.mesh.positions.length / 3; vertex += 1) {
    const source = new THREE.Vector3().fromArray(model.mesh.positions, vertex * 3);
    const output = new THREE.Vector3();
    const influences = [];
    for (let slot = 0; slot < 4; slot += 1) {
      const influence = vertex * 4 + slot;
      const weight = model.mesh.weights[influence];
      if (!weight) continue;
      const boneIndex = model.mesh.joints[influence];
      const boneName = model.mesh.boneNames[boneIndex];
      const bone = model.bones.get(boneName);
      const poseGlobal = poseGlobals.get(boneName);
      if (!bone || !poseGlobal) continue;
      output.addScaledVector(source.clone().applyMatrix4(skinMatrix(poseGlobal, bone.offset, order)), weight);
      influences.push({ boneName, weight });
    }
    result.push({ position: output, influences });
  }
  return result;
}

function influenced(vertices, pattern, threshold = 0.15) {
  return vertices.filter((vertex) => vertex.influences.some(({ boneName, weight }) => (
    pattern.test(boneName) && weight >= threshold
  )));
}

function nearestDistance(left, right) {
  let nearest = Infinity;
  for (const a of left) {
    for (const b of right) nearest = Math.min(nearest, a.position.distanceToSquared(b.position));
  }
  return Math.sqrt(nearest);
}

function readObjPositions(file) {
  return fs.readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .filter((line) => line.startsWith('v '))
    .map((line) => new THREE.Vector3(...line.trim().split(/\s+/).slice(1).map(Number)));
}

function compareBaked(modelName, vertices) {
  const bakedName = modelName === 'body' ? 'body'
    : modelName === 'trousers' ? 'trousers'
      : modelName === 'jacket' ? 'jacket'
        : null;
  if (!bakedName) return;
  const file = path.join(root, 'public', 'pz', 'poses', sex, poseName, `${bakedName}.obj`);
  if (!fs.existsSync(file)) return;
  const baked = readObjPositions(file);
  if (baked.length !== vertices.length) {
    console.log(`baked vertex count differs: ${baked.length} vs ${vertices.length}`);
    return;
  }
  const distances = vertices.map((vertex, index) => vertex.position.distanceTo(baked[index]));
  const rms = Math.sqrt(distances.reduce((sum, value) => sum + value * value, 0) / distances.length);
  console.log(`baked parity: max=${Math.max(...distances).toFixed(9)} m rms=${rms.toFixed(9)} m`);
}

for (const [modelName, model] of loaded) {
  console.log(`\n${modelName}`);
  console.log('bone'.padEnd(24), 'bind Δm'.padStart(11), 'bind Δ°'.padStart(11), 'skin Δm'.padStart(11), 'skin Δ°'.padStart(11));
  for (const boneName of trackedBones) {
    const bodyBone = body.bones.get(boneName);
    const modelBone = model.bones.get(boneName);
    const poseGlobal = poseGlobals.get(boneName);
    if (!bodyBone || !modelBone || !poseGlobal) continue;
    const bindDistance = position(bodyBone.bind).distanceTo(position(modelBone.bind));
    const bindAngle = degreesBetween(rotation(bodyBone.bind), rotation(modelBone.bind));
    const bodySkin = skinMatrix(poseGlobal, bodyBone.offset);
    const modelSkin = skinMatrix(poseGlobal, modelBone.offset);
    const skinDistance = position(bodySkin).distanceTo(position(modelSkin));
    const skinAngle = degreesBetween(rotation(bodySkin), rotation(modelSkin));
    console.log(
      boneName.padEnd(24),
      bindDistance.toFixed(6).padStart(11),
      bindAngle.toFixed(3).padStart(11),
      skinDistance.toFixed(6).padStart(11),
      skinAngle.toFixed(3).padStart(11),
    );
  }
}

const bodyVertices = skinnedVertices(body);
compareBaked('body', bodyVertices);
for (const [modelName, model] of loaded) {
  if (modelName === 'body') continue;
  const modelVertices = skinnedVertices(model);
  compareBaked(modelName, modelVertices);
  console.log(`\n${modelName} surface continuity`);
  for (const side of ['L', 'R']) {
    const sleeve = influenced(modelVertices, new RegExp(`^Bip01_${side}_(UpperArm|Forearm|Hand)`));
    const hand = influenced(bodyVertices, new RegExp(`^Bip01_${side}_(Hand|Finger)`), 0.1);
    if (sleeve.length && hand.length) {
      console.log(`${side} sleeve -> body hand nearest: ${nearestDistance(sleeve, hand).toFixed(6)} m`);
    }
    const trouserLeg = influenced(modelVertices, new RegExp(`^Bip01_${side}_(Thigh|Calf|Foot)`));
    const foot = influenced(bodyVertices, new RegExp(`^Bip01_${side}_(Foot|Toe)`), 0.1);
    if (trouserLeg.length && foot.length) {
      console.log(`${side} trouser -> body foot nearest: ${nearestDistance(trouserLeg, foot).toFixed(6)} m`);
    }
  }
}

console.log('\nAlternative offset × pose order');
const alternativeBodyVertices = skinnedVertices(body, 'offset-pose');
for (const [modelName, model] of loaded) {
  if (modelName === 'body') continue;
  const modelVertices = skinnedVertices(model, 'offset-pose');
  console.log(`\n${modelName} surface continuity`);
  for (const side of ['L', 'R']) {
    const sleeve = influenced(modelVertices, new RegExp(`^Bip01_${side}_(UpperArm|Forearm|Hand)`));
    const hand = influenced(alternativeBodyVertices, new RegExp(`^Bip01_${side}_(Hand|Finger)`), 0.1);
    if (sleeve.length && hand.length) console.log(`${side} sleeve -> body hand nearest: ${nearestDistance(sleeve, hand).toFixed(6)} m`);
    const trouserLeg = influenced(modelVertices, new RegExp(`^Bip01_${side}_(Thigh|Calf|Foot)`));
    const foot = influenced(alternativeBodyVertices, new RegExp(`^Bip01_${side}_(Foot|Toe)`), 0.1);
    if (trouserLeg.length && foot.length) console.log(`${side} trouser -> body foot nearest: ${nearestDistance(trouserLeg, foot).toFixed(6)} m`);
  }
}
