import fs from 'node:fs';
import path from 'node:path';
import * as THREE from 'three';

const root = process.cwd();

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function matrix(values) {
  return new THREE.Matrix4().set(
    values[0], values[1], values[2], values[3],
    values[4], values[5], values[6], values[7],
    values[8], values[9], values[10], values[11],
    values[12], values[13], values[14], values[15],
  );
}

function bones(file) {
  const json = readJson(file);
  const result = new Map();
  for (const mesh of json.meshes) {
    mesh.boneNames.forEach((name, index) => {
      if (!result.has(name)) result.set(name, matrix(mesh.offsets[index]).invert());
    });
  }
  return result;
}

function compare(reference, candidate) {
  let maxPosition = 0;
  let maxRotation = 0;
  let common = 0;
  for (const [name, candidateMatrix] of candidate) {
    const referenceMatrix = reference.get(name);
    if (!referenceMatrix) continue;
    common += 1;
    const rp = new THREE.Vector3();
    const rq = new THREE.Quaternion();
    const cp = new THREE.Vector3();
    const cq = new THREE.Quaternion();
    referenceMatrix.decompose(rp, rq, new THREE.Vector3());
    candidateMatrix.decompose(cp, cq, new THREE.Vector3());
    maxPosition = Math.max(maxPosition, rp.distanceTo(cp));
    maxRotation = Math.max(maxRotation, THREE.MathUtils.radToDeg(rq.normalize().angleTo(cq.normalize())));
  }
  return { common, maxPosition, maxRotation };
}

for (const sex of ['m', 'f']) {
  const directory = path.join(root, 'public', 'pz', 'rigs', sex);
  const reference = bones(path.join(directory, 'body.json'));
  const rows = fs.readdirSync(directory)
    .filter((name) => name.endsWith('.json') && name !== 'body.json')
    .map((name) => ({ name, ...compare(reference, bones(path.join(directory, name))) }))
    .sort((left, right) => right.maxPosition - left.maxPosition || right.maxRotation - left.maxRotation);
  console.log(`\n${sex}: ${rows.length} rigs`);
  for (const row of rows.filter((candidate) => candidate.maxPosition > 0.003 || candidate.maxRotation > 0.5)) {
    console.log(`${row.name.padEnd(42)} bones=${String(row.common).padStart(2)} Δ=${(row.maxPosition * 1000).toFixed(2).padStart(8)} mm  rot=${row.maxRotation.toFixed(3)}°`);
  }
  console.log(`outliers: ${rows.filter((candidate) => candidate.maxPosition > 0.003 || candidate.maxRotation > 0.5).length}`);
}
