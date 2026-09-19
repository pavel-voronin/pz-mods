import * as THREE from 'three';

export type JointTuple = [number, number, number];
export type JointMap = Record<string, JointTuple>;
export type HandleKey = 'head' | 'leftHand' | 'rightHand' | 'leftFoot' | 'rightFoot';

type Chain = { root: string; middle: string; end: string };
type Segment = { start: string; end: string };
type GeometryRagdollData = {
  basePositions: Float32Array;
  baseNormals: Float32Array;
  segmentIndices: Uint8Array;
  segmentWeights: Float32Array;
};

const chains: Record<HandleKey, Chain> = {
  head: { root: 'Bip01_Spine1', middle: 'Bip01_Neck', end: 'Bip01_Head' },
  leftHand: { root: 'Bip01_L_UpperArm', middle: 'Bip01_L_Forearm', end: 'Bip01_L_Hand' },
  rightHand: { root: 'Bip01_R_UpperArm', middle: 'Bip01_R_Forearm', end: 'Bip01_R_Hand' },
  leftFoot: { root: 'Bip01_L_Thigh', middle: 'Bip01_L_Calf', end: 'Bip01_L_Foot' },
  rightFoot: { root: 'Bip01_R_Thigh', middle: 'Bip01_R_Calf', end: 'Bip01_R_Foot' },
};

const segments: Segment[] = [
  { start: 'pelvis', end: 'Bip01_Spine1' },
  { start: 'Bip01_Spine1', end: 'Bip01_Neck' },
  { start: 'Bip01_Neck', end: 'Bip01_Head' },
  { start: 'Bip01_L_UpperArm', end: 'Bip01_L_Forearm' },
  { start: 'Bip01_L_Forearm', end: 'Bip01_L_Hand' },
  { start: 'Bip01_R_UpperArm', end: 'Bip01_R_Forearm' },
  { start: 'Bip01_R_Forearm', end: 'Bip01_R_Hand' },
  { start: 'Bip01_L_Thigh', end: 'Bip01_L_Calf' },
  { start: 'Bip01_L_Calf', end: 'Bip01_L_Foot' },
  { start: 'Bip01_R_Thigh', end: 'Bip01_R_Calf' },
  { start: 'Bip01_R_Calf', end: 'Bip01_R_Foot' },
];

function tupleToVector(tuple: JointTuple) {
  return new THREE.Vector3(tuple[0], tuple[1], tuple[2]);
}

function vectorToTuple(vector: THREE.Vector3): JointTuple {
  return [vector.x, vector.y, vector.z];
}

function cloneJoints(joints: JointMap): JointMap {
  return Object.fromEntries(Object.entries(joints).map(([name, tuple]) => [name, [...tuple] as JointTuple]));
}

function addSyntheticJoints(joints: JointMap) {
  const leftHip = tupleToVector(joints.Bip01_L_Thigh);
  const rightHip = tupleToVector(joints.Bip01_R_Thigh);
  joints.pelvis = vectorToTuple(leftHip.add(rightHip).multiplyScalar(0.5));
}

export class RagdollState {
  readonly base: JointMap;
  current: JointMap;

  constructor(joints: JointMap) {
    this.base = cloneJoints(joints);
    addSyntheticJoints(this.base);
    this.current = cloneJoints(this.base);
  }

  reset() {
    this.current = cloneJoints(this.base);
  }

  getHandlePosition(handle: HandleKey) {
    return tupleToVector(this.current[chains[handle].end]);
  }

  dragHandle(handle: HandleKey, target: THREE.Vector3) {
    const chain = chains[handle];
    const root = tupleToVector(this.current[chain.root]);
    const baseRoot = tupleToVector(this.base[chain.root]);
    const baseMiddle = tupleToVector(this.base[chain.middle]);
    const baseEnd = tupleToVector(this.base[chain.end]);
    const firstLength = baseRoot.distanceTo(baseMiddle);
    const secondLength = baseMiddle.distanceTo(baseEnd);
    const towardTarget = target.clone().sub(root);
    const rawDistance = towardTarget.length();
    if (rawDistance < 1e-5) return;

    const minimum = Math.abs(firstLength - secondLength) + 1e-4;
    const maximum = firstLength + secondLength - 1e-4;
    const distance = THREE.MathUtils.clamp(rawDistance, minimum, maximum);
    const direction = towardTarget.normalize();
    const solvedEnd = root.clone().addScaledVector(direction, distance);

    const originalBend = baseMiddle.clone().sub(baseRoot);
    const perpendicular = originalBend.addScaledVector(direction, -originalBend.dot(direction));
    if (perpendicular.lengthSq() < 1e-8) {
      perpendicular.copy(new THREE.Vector3(0, 1, 0).cross(direction));
      if (perpendicular.lengthSq() < 1e-8) perpendicular.copy(new THREE.Vector3(1, 0, 0));
    }
    perpendicular.normalize();

    const along = (firstLength ** 2 - secondLength ** 2 + distance ** 2) / (2 * distance);
    const away = Math.sqrt(Math.max(0, firstLength ** 2 - along ** 2));
    const solvedMiddle = root.clone().addScaledVector(direction, along).addScaledVector(perpendicular, away);

    this.current[chain.middle] = vectorToTuple(solvedMiddle);
    this.current[chain.end] = vectorToTuple(solvedEnd);
  }

  segmentTransforms() {
    return segments.map((segment) => {
      const baseStart = tupleToVector(this.base[segment.start]);
      const baseEnd = tupleToVector(this.base[segment.end]);
      const currentStart = tupleToVector(this.current[segment.start]);
      const currentEnd = tupleToVector(this.current[segment.end]);
      const baseDirection = baseEnd.clone().sub(baseStart).normalize();
      const currentDirection = currentEnd.clone().sub(currentStart).normalize();
      const rotation = new THREE.Quaternion().setFromUnitVectors(baseDirection, currentDirection);
      return new THREE.Matrix4()
        .makeTranslation(currentStart.x, currentStart.y, currentStart.z)
        .multiply(new THREE.Matrix4().makeRotationFromQuaternion(rotation))
        .multiply(new THREE.Matrix4().makeTranslation(-baseStart.x, -baseStart.y, -baseStart.z));
    });
  }
}

function distanceToSegment(point: THREE.Vector3, start: THREE.Vector3, end: THREE.Vector3) {
  const segment = end.clone().sub(start);
  const lengthSquared = segment.lengthSq();
  if (lengthSquared === 0) return point.distanceTo(start);
  const amount = THREE.MathUtils.clamp(point.clone().sub(start).dot(segment) / lengthSquared, 0, 1);
  return point.distanceTo(start.addScaledVector(segment, amount));
}

export function prepareRagdollGeometry(geometry: THREE.BufferGeometry, state: RagdollState) {
  if (geometry.userData.ragdoll) return;
  const position = geometry.getAttribute('position') as THREE.BufferAttribute;
  const normal = geometry.getAttribute('normal') as THREE.BufferAttribute;
  const basePositions = new Float32Array(position.array as ArrayLike<number>);
  const baseNormals = normal
    ? new Float32Array(normal.array as ArrayLike<number>)
    : new Float32Array(basePositions.length);
  const segmentIndices = new Uint8Array(position.count * 3);
  const segmentWeights = new Float32Array(position.count * 3);
  const starts = segments.map((segment) => tupleToVector(state.base[segment.start]));
  const ends = segments.map((segment) => tupleToVector(state.base[segment.end]));
  const point = new THREE.Vector3();

  for (let vertexIndex = 0; vertexIndex < position.count; vertexIndex += 1) {
    point.fromArray(basePositions, vertexIndex * 3);
    const nearest = segments
      .map((_, segmentIndex) => ({ segmentIndex, distance: distanceToSegment(point, starts[segmentIndex].clone(), ends[segmentIndex]) }))
      .sort((a, b) => a.distance - b.distance)
      .slice(0, 3);
    const scores = nearest.map(({ distance }) => 1 / Math.max(0.0001, distance) ** 3);
    const scoreTotal = scores.reduce((sum, score) => sum + score, 0);
    nearest.forEach(({ segmentIndex }, influenceIndex) => {
      const offset = vertexIndex * 3 + influenceIndex;
      segmentIndices[offset] = segmentIndex;
      segmentWeights[offset] = scores[influenceIndex] / scoreTotal;
    });
  }

  const data: GeometryRagdollData = { basePositions, baseNormals, segmentIndices, segmentWeights };
  geometry.userData.ragdoll = data;
}

export function deformRagdollGeometry(geometry: THREE.BufferGeometry, state: RagdollState) {
  const data = geometry.userData.ragdoll as GeometryRagdollData | undefined;
  if (!data) return;
  const position = geometry.getAttribute('position') as THREE.BufferAttribute;
  const normal = geometry.getAttribute('normal') as THREE.BufferAttribute;
  const transforms = state.segmentTransforms();
  const normalTransforms = transforms.map((matrix) => new THREE.Matrix3().getNormalMatrix(matrix));
  const basePoint = new THREE.Vector3();
  const transformedPoint = new THREE.Vector3();
  const outputPoint = new THREE.Vector3();
  const baseNormal = new THREE.Vector3();
  const transformedNormal = new THREE.Vector3();
  const outputNormal = new THREE.Vector3();

  for (let vertexIndex = 0; vertexIndex < position.count; vertexIndex += 1) {
    basePoint.fromArray(data.basePositions, vertexIndex * 3);
    baseNormal.fromArray(data.baseNormals, vertexIndex * 3);
    outputPoint.set(0, 0, 0);
    outputNormal.set(0, 0, 0);
    for (let influenceIndex = 0; influenceIndex < 3; influenceIndex += 1) {
      const offset = vertexIndex * 3 + influenceIndex;
      const weight = data.segmentWeights[offset];
      const segmentIndex = data.segmentIndices[offset];
      transformedPoint.copy(basePoint).applyMatrix4(transforms[segmentIndex]);
      transformedNormal.copy(baseNormal).applyMatrix3(normalTransforms[segmentIndex]);
      outputPoint.addScaledVector(transformedPoint, weight);
      outputNormal.addScaledVector(transformedNormal, weight);
    }
    position.setXYZ(vertexIndex, outputPoint.x, outputPoint.y, outputPoint.z);
    if (normal) {
      outputNormal.normalize();
      normal.setXYZ(vertexIndex, outputNormal.x, outputNormal.y, outputNormal.z);
    }
  }

  position.needsUpdate = true;
  if (normal) normal.needsUpdate = true;
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
}

export const ragdollHandles: HandleKey[] = ['head', 'leftHand', 'rightHand', 'leftFoot', 'rightFoot'];
