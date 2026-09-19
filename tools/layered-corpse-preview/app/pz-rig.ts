import * as THREE from 'three';
import { RagdollConstraints } from './ragdoll-constraints.ts';
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js';

export type HandleKey =
  | 'pelvis' | 'waist' | 'chest' | 'neck' | 'head'
  | 'leftShoulder' | 'leftElbow' | 'leftHand'
  | 'rightShoulder' | 'rightElbow' | 'rightHand'
  | 'leftHip' | 'leftKnee' | 'leftFoot'
  | 'rightHip' | 'rightKnee' | 'rightFoot';
export type PoseJson = Record<string, number[]>;
export type PzPoseState = {
  rootTranslation: [number, number, number];
  joints: Record<string, [number, number, number]>;
};

type RigMeshJson = {
  positions: number[];
  normals: number[];
  uvs: number[];
  indices: number[];
  boneNames: string[];
  offsets: number[][];
  joints: number[];
  weights: number[];
};

export type RigJson = { meshes: RigMeshJson[] };

const fbxRigCache = new Map<string, Promise<RigJson>>();
const fbxObjectCache = new Map<string, Promise<THREE.Group>>();
const pzXObjectCache = new Map<string, Promise<THREE.Group>>();

function matrixToRowMajor(matrix: THREE.Matrix4) {
  const elements = matrix.elements;
  return [
    elements[0], elements[4], elements[8], elements[12],
    elements[1], elements[5], elements[9], elements[13],
    elements[2], elements[6], elements[10], elements[14],
    elements[3], elements[7], elements[11], elements[15],
  ];
}

async function parseRigFromFbx(path: string): Promise<RigJson> {
  const source = await new FBXLoader().loadAsync(path);
  source.updateMatrixWorld(true);
  const meshes: RigMeshJson[] = [];

  source.traverse((object) => {
    const mesh = object as THREE.SkinnedMesh;
    if (!mesh.isSkinnedMesh || !mesh.skeleton) return;
    const geometry = mesh.geometry.clone();
    if (!geometry.getAttribute('normal')) geometry.computeVertexNormals();
    const positions = geometry.getAttribute('position');
    const normals = geometry.getAttribute('normal');
    const uvs = geometry.getAttribute('uv');
    const joints = geometry.getAttribute('skinIndex');
    const weights = geometry.getAttribute('skinWeight');
    if (!positions || !normals || !joints || !weights) {
      geometry.dispose();
      throw new Error(`В ${path} отсутствуют данные скелета`);
    }
    const indices = geometry.index
      ? Array.from(geometry.index.array)
      : Array.from({ length: positions.count }, (_, index) => index);
    meshes.push({
      positions: Array.from(positions.array),
      normals: Array.from(normals.array),
      uvs: uvs ? Array.from(uvs.array) : Array.from({ length: positions.count * 2 }, () => 0),
      indices,
      boneNames: mesh.skeleton.bones.map((bone) => bone.name),
      offsets: mesh.skeleton.boneInverses.map(matrixToRowMajor),
      joints: Array.from(joints.array),
      weights: Array.from(weights.array),
    });
    geometry.dispose();
  });

  if (!meshes.length) throw new Error(`В ${path} не найдена skinned-модель`);
  return { meshes };
}

export function loadRigFromFbx(path: string): Promise<RigJson> {
  const cached = fbxRigCache.get(path);
  if (cached) return cached;
  const pending = parseRigFromFbx(path).catch((error) => {
    fbxRigCache.delete(path);
    throw error;
  });
  fbxRigCache.set(path, pending);
  return pending;
}

export function loadObjectFromFbx(path: string): Promise<THREE.Group> {
  const cached = fbxObjectCache.get(path);
  if (cached) return cached;
  const manager = new THREE.LoadingManager();
  manager.setURLModifier((url) => /\.(png|jpe?g)$/i.test(url)
    ? 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8WQAAAABJRU5ErkJggg=='
    : url);
  const pending = new FBXLoader(manager).loadAsync(path).then((source) => {
    source.updateMatrixWorld(true);
    source.traverse((object) => {
      const mesh = object as THREE.Mesh;
      if (!mesh.isMesh) return;
      if (!mesh.geometry.getAttribute('normal')) mesh.geometry.computeVertexNormals();
    });
    return source;
  }).catch((error) => {
    fbxObjectCache.delete(path);
    throw error;
  });
  fbxObjectCache.set(path, pending);
  return pending;
}

function numbersIn(line: string) {
  return [...line.matchAll(/[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi)].map((match) => Number(match[0]));
}

async function parseObjectFromPzX(path: string) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Не удалось загрузить ${path}`);
  const lines = (await response.text()).split(/\r?\n/);
  let cursor = lines.findIndex((line) => /^\s*Mesh(?:\s+\w+)?\s*\{/.test(line));
  if (cursor < 0) throw new Error(`В ${path} не найдена Mesh`);

  const vertexCount = numbersIn(lines[++cursor])[0];
  const positions: number[] = [];
  for (let index = 0; index < vertexCount; index += 1) {
    positions.push(...numbersIn(lines[++cursor]).slice(0, 3));
  }

  const faceCount = numbersIn(lines[++cursor])[0];
  const indices: number[] = [];
  for (let index = 0; index < faceCount; index += 1) {
    const face = numbersIn(lines[++cursor]);
    const size = face[0];
    for (let corner = 2; corner < size; corner += 1) {
      indices.push(face[1], face[corner], face[corner + 1]);
    }
  }

  cursor = lines.findIndex((line, index) => index > cursor && /^\s*MeshTextureCoords(?:\s+\w+)?\s*\{/.test(line));
  const uvs: number[] = [];
  if (cursor >= 0) {
    const uvCount = numbersIn(lines[++cursor])[0];
    for (let index = 0; index < uvCount; index += 1) {
      uvs.push(...numbersIn(lines[++cursor]).slice(0, 2));
    }
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  if (uvs.length === vertexCount * 2) geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  const group = new THREE.Group();
  group.add(new THREE.Mesh(geometry));
  return group;
}

export function loadObjectFromPzX(path: string): Promise<THREE.Group> {
  const cached = pzXObjectCache.get(path);
  if (cached) return cached;
  const pending = parseObjectFromPzX(path).catch((error) => {
    pzXObjectCache.delete(path);
    throw error;
  });
  pzXObjectCache.set(path, pending);
  return pending;
}

export function cloneObjectWithMaterial(source: THREE.Group, material: THREE.Material) {
  const clone = source.clone(true);
  clone.traverse((object) => {
    const mesh = object as THREE.Mesh;
    if (!mesh.isMesh) return;
    mesh.material = material;
    mesh.castShadow = true;
    mesh.receiveShadow = true;
  });
  return clone;
}

type RigPart = {
  geometry: THREE.BufferGeometry;
  positions: Float32Array;
  normals: Float32Array;
  boneNames: string[];
  offsets: THREE.Matrix4[];
  joints: Uint16Array;
  weights: Float32Array;
};

export type RigModel = { parts: RigPart[] };

export type RigSkeletonComparison = {
  commonBones: number;
  missingBones: string[];
  maxJointDelta: number;
  maxRotationDelta: number;
};

type Chain = { root: string; middle: string; end: string };
type Segment = { start: string; end: string };

const chains: Record<'head' | 'leftHand' | 'rightHand' | 'leftFoot' | 'rightFoot', Chain> = {
  head: { root: 'Bip01_Spine1', middle: 'Bip01_Neck', end: 'Bip01_Head' },
  leftHand: { root: 'Bip01_L_UpperArm', middle: 'Bip01_L_Forearm', end: 'Bip01_L_Hand' },
  rightHand: { root: 'Bip01_R_UpperArm', middle: 'Bip01_R_Forearm', end: 'Bip01_R_Hand' },
  leftFoot: { root: 'Bip01_L_Thigh', middle: 'Bip01_L_Calf', end: 'Bip01_L_Foot' },
  rightFoot: { root: 'Bip01_R_Thigh', middle: 'Bip01_R_Calf', end: 'Bip01_R_Foot' },
};

const handleBones: Record<HandleKey, string> = {
  pelvis: 'Bip01_Pelvis',
  waist: 'Bip01_Spine',
  chest: 'Bip01_Spine1',
  neck: 'Bip01_Neck',
  head: 'Bip01_Head',
  leftShoulder: 'Bip01_L_UpperArm',
  leftElbow: 'Bip01_L_Forearm',
  leftHand: 'Bip01_L_Hand',
  rightShoulder: 'Bip01_R_UpperArm',
  rightElbow: 'Bip01_R_Forearm',
  rightHand: 'Bip01_R_Hand',
  leftHip: 'Bip01_L_Thigh',
  leftKnee: 'Bip01_L_Calf',
  leftFoot: 'Bip01_L_Foot',
  rightHip: 'Bip01_R_Thigh',
  rightKnee: 'Bip01_R_Calf',
  rightFoot: 'Bip01_R_Foot',
};

export const ragdollParents: Partial<Record<HandleKey, HandleKey>> = {
  waist: 'pelvis',
  chest: 'waist',
  neck: 'chest',
  head: 'neck',
  leftShoulder: 'chest',
  leftElbow: 'leftShoulder',
  leftHand: 'leftElbow',
  rightShoulder: 'chest',
  rightElbow: 'rightShoulder',
  rightHand: 'rightElbow',
  leftHip: 'pelvis',
  leftKnee: 'leftHip',
  leftFoot: 'leftKnee',
  rightHip: 'pelvis',
  rightKnee: 'rightHip',
  rightFoot: 'rightKnee',
};

const floorClearance: Record<HandleKey, number> = {
  pelvis: 0.05,
  waist: 0.05,
  chest: 0.05,
  neck: 0.04,
  head: 0.052,
  leftShoulder: 0.032,
  leftElbow: 0.027,
  leftHand: 0.018,
  rightShoulder: 0.032,
  rightElbow: 0.027,
  rightHand: 0.018,
  leftHip: 0.038,
  leftKnee: 0.028,
  leftFoot: 0.018,
  rightHip: 0.038,
  rightKnee: 0.028,
  rightFoot: 0.018,
};

const segments: Record<string, Segment> = {
  pelvis: { start: 'Bip01_Pelvis', end: 'Bip01_Spine' },
  spine: { start: 'Bip01_Spine', end: 'Bip01_Spine1' },
  neck: { start: 'Bip01_Spine1', end: 'Bip01_Neck' },
  head: { start: 'Bip01_Neck', end: 'Bip01_Head' },
  leftClavicle: { start: 'Bip01_Spine1', end: 'Bip01_L_UpperArm' },
  rightClavicle: { start: 'Bip01_Spine1', end: 'Bip01_R_UpperArm' },
  leftUpperArm: { start: 'Bip01_L_UpperArm', end: 'Bip01_L_Forearm' },
  leftForearm: { start: 'Bip01_L_Forearm', end: 'Bip01_L_Hand' },
  rightUpperArm: { start: 'Bip01_R_UpperArm', end: 'Bip01_R_Forearm' },
  rightForearm: { start: 'Bip01_R_Forearm', end: 'Bip01_R_Hand' },
  leftThigh: { start: 'Bip01_L_Thigh', end: 'Bip01_L_Calf' },
  leftCalf: { start: 'Bip01_L_Calf', end: 'Bip01_L_Foot' },
  rightThigh: { start: 'Bip01_R_Thigh', end: 'Bip01_R_Calf' },
  rightCalf: { start: 'Bip01_R_Calf', end: 'Bip01_R_Foot' },
};

export const rigDiagnosticSegments: ReadonlyArray<readonly [string, string]> = [
  ['Bip01_Pelvis', 'Bip01_Spine'],
  ['Bip01_Spine', 'Bip01_Spine1'],
  ['Bip01_Spine1', 'Bip01_Neck'],
  ['Bip01_Neck', 'Bip01_Head'],
  ['Bip01_Spine1', 'Bip01_L_UpperArm'],
  ['Bip01_L_UpperArm', 'Bip01_L_Forearm'],
  ['Bip01_L_Forearm', 'Bip01_L_Hand'],
  ['Bip01_Spine1', 'Bip01_R_UpperArm'],
  ['Bip01_R_UpperArm', 'Bip01_R_Forearm'],
  ['Bip01_R_Forearm', 'Bip01_R_Hand'],
  ['Bip01_Pelvis', 'Bip01_L_Thigh'],
  ['Bip01_L_Thigh', 'Bip01_L_Calf'],
  ['Bip01_L_Calf', 'Bip01_L_Foot'],
  ['Bip01_Pelvis', 'Bip01_R_Thigh'],
  ['Bip01_R_Thigh', 'Bip01_R_Calf'],
  ['Bip01_R_Calf', 'Bip01_R_Foot'],
];

export const ragdollHandles: HandleKey[] = [
  'pelvis', 'waist', 'chest', 'neck', 'head',
  'leftShoulder', 'leftElbow', 'leftHand',
  'rightShoulder', 'rightElbow', 'rightHand',
  'leftHip', 'leftKnee', 'leftFoot',
  'rightHip', 'rightKnee', 'rightFoot',
];

function matrixFromRowMajor(values: number[]) {
  return new THREE.Matrix4().set(
    values[0], values[1], values[2], values[3],
    values[4], values[5], values[6], values[7],
    values[8], values[9], values[10], values[11],
    values[12], values[13], values[14], values[15],
  );
}

function jointPosition(globals: Map<string, THREE.Matrix4>, name: string) {
  const matrix = globals.get(name);
  if (!matrix) throw new Error(`В позе отсутствует кость ${name}`);
  return new THREE.Vector3().setFromMatrixPosition(matrix);
}

function segmentDelta(
  base: Map<string, THREE.Vector3>,
  current: Map<string, THREE.Vector3>,
  segment: Segment,
) {
  const baseStart = base.get(segment.start)!;
  const baseEnd = base.get(segment.end)!;
  const currentStart = current.get(segment.start)!;
  const currentEnd = current.get(segment.end)!;
  const baseDirection = baseEnd.clone().sub(baseStart).normalize();
  const currentDirection = currentEnd.clone().sub(currentStart).normalize();
  const rotation = new THREE.Quaternion().setFromUnitVectors(baseDirection, currentDirection);
  return new THREE.Matrix4()
    .makeTranslation(currentStart.x, currentStart.y, currentStart.z)
    .multiply(new THREE.Matrix4().makeRotationFromQuaternion(rotation))
    .multiply(new THREE.Matrix4().makeTranslation(-baseStart.x, -baseStart.y, -baseStart.z));
}

function segmentForBone(name: string) {
  if (name === 'Bip01_Pelvis') return 'pelvis';
  if (name === 'Bip01_Spine') return 'spine';
  if (name === 'Bip01_Spine1') return 'neck';
  if (name === 'Bip01_L_Clavicle') return 'leftClavicle';
  if (name === 'Bip01_R_Clavicle') return 'rightClavicle';
  if (name === 'Bip01_Neck') return 'neck';
  if (name === 'Bip01_Head') return 'head';
  if (name === 'Bip01_L_UpperArm') return 'leftUpperArm';
  if (/^Bip01_L_(Forearm|Hand|Finger)/.test(name)) return 'leftForearm';
  if (name === 'Bip01_R_UpperArm') return 'rightUpperArm';
  if (/^Bip01_R_(Forearm|Hand|Finger)/.test(name)) return 'rightForearm';
  if (name === 'Bip01_L_Thigh') return 'leftThigh';
  if (/^Bip01_L_(Calf|Foot|Toe)/.test(name)) return 'leftCalf';
  if (name === 'Bip01_R_Thigh') return 'rightThigh';
  if (/^Bip01_R_(Calf|Foot|Toe)/.test(name)) return 'rightCalf';
  return null;
}

export class PzRagdollPose {
  private surfaceClearance = { ...floorClearance };
  readonly constraints: RagdollConstraints;
  readonly globals: Map<string, THREE.Matrix4>;
  readonly baseJoints = new Map<string, THREE.Vector3>();
  readonly currentJoints = new Map<string, THREE.Vector3>();
  readonly rootTranslation = new THREE.Vector3();

  constructor(pose: PoseJson) {
    this.globals = new Map(Object.entries(pose).map(([name, values]) => [name, matrixFromRowMajor(values)]));
    const names = new Set([
      ...Object.values(chains).flatMap((chain) => [chain.root, chain.middle, chain.end]),
      ...Object.values(handleBones),
    ]);
    names.forEach((name) => {
      const position = jointPosition(this.globals, name);
      this.baseJoints.set(name, position);
      this.currentJoints.set(name, position.clone());
    });
    this.constraints = new RagdollConstraints(new Map(ragdollHandles.map(key=>[key,this.getHandlePosition(key)])),ragdollParents);
  }

  reset() {
    this.surfaceClearance = { ...floorClearance };
    this.rootTranslation.set(0, 0, 0);
    this.currentJoints.clear();
    this.baseJoints.forEach((position, name) => this.currentJoints.set(name, position.clone()));
  }

  captureState(): PzPoseState {
    return {
      rootTranslation: this.rootTranslation.toArray() as [number, number, number],
      joints: Object.fromEntries(
        [...this.currentJoints.entries()].map(([name, position]) => [name, position.toArray() as [number, number, number]]),
      ),
    };
  }

  restoreState(state: PzPoseState) {
    this.rootTranslation.fromArray(state.rootTranslation);
    Object.entries(state.joints).forEach(([name, values]) => {
      if (this.currentJoints.has(name)) this.currentJoints.set(name, new THREE.Vector3().fromArray(values));
    });
  }

  getHandlePosition(handle: HandleKey) {
    return this.currentJoints.get(handleBones[handle])!.clone().add(this.rootTranslation);
  }

  getRotationPivot(handle: HandleKey) {
    const parent = ragdollParents[handle];
    return parent ? this.getHandlePosition(parent) : this.getHandlePosition('pelvis');
  }

  getRestLength(parent: HandleKey, child: HandleKey) {
    return this.baseJoints.get(handleBones[parent])!.distanceTo(this.baseJoints.get(handleBones[child])!);
  }

  setHandlePositions(positions: ReadonlyMap<HandleKey, THREE.Vector3>) {
    const pelvisTarget = positions.get('pelvis');
    if (pelvisTarget) this.rootTranslation.copy(pelvisTarget).sub(this.baseJoints.get(handleBones.pelvis)!);
    ragdollHandles.forEach((handle) => {
      if (handle === 'pelvis') return;
      const target = positions.get(handle);
      if (target) this.currentJoints.set(handleBones[handle], target.clone().sub(this.rootTranslation));
    });
  }

  clampHandleTarget(handle: HandleKey, target: THREE.Vector3, floorY: number) {
    const result = target.clone();
    result.y = Math.max(result.y, floorY + this.surfaceClearance[handle]);
    return result;
  }

  /** Current skinned toe/foot support, not an ankle-centred fixed sphere.
   * Includes footwear when provided. Does not alter or hide any mesh vertex. */
  updateFootSupports(models: Iterable<RigModel>) {
    const min = { leftFoot: Infinity, rightFoot: Infinity };
    for (const model of models) for (const part of model.parts) {
      const position = part.geometry.getAttribute('position');
      for (let i=0;i<position.count;i++) {
        let left=0,right=0;
        for(let j=0;j<4;j++) {
          const bone=part.boneNames[part.joints[i*4+j]]??'', weight=part.weights[i*4+j];
          if(/^Bip01_L_(Foot|Toe)/.test(bone))left+=weight;
          if(/^Bip01_R_(Foot|Toe)/.test(bone))right+=weight;
        }
        if(left>.25)min.leftFoot=Math.min(min.leftFoot,position.getY(i));
        if(right>.25)min.rightFoot=Math.min(min.rightFoot,position.getY(i));
      }
    }
    for(const key of ['leftFoot','rightFoot'] as const) {
      this.surfaceClearance[key]=Number.isFinite(min[key])
        ? Math.max(floorClearance[key],this.getHandlePosition(key).y-min[key]+.002)
        : floorClearance[key];
    }
  }

  enforceFloor(floorY: number) {
    ragdollHandles.forEach((handle) => {
      const position = this.getHandlePosition(handle);
      const minimum = floorY + floorClearance[handle];
      if (position.y < minimum) {
        position.y = minimum;
        this.pinHandle(handle, position);
      }
    });
  }

  lowestFloorGap(floorY: number) {
    return Math.min(...ragdollHandles.map((handle) => this.getHandlePosition(handle).y - floorY - floorClearance[handle]));
  }

  pinHandle(handle: HandleKey, target: THREE.Vector3) {
    if (handle === 'pelvis') {
      this.rootTranslation.copy(target).sub(this.baseJoints.get(handleBones.pelvis)!);
      return;
    }
    this.currentJoints.set(handleBones[handle], target.clone().sub(this.rootTranslation));
  }

  projectHandles(positions: Map<HandleKey, THREE.Vector3>, locked: ReadonlySet<HandleKey> = new Set(), floorY = -Infinity) {
    this.constraints.solve(positions,locked,(key,p)=>this.clampHandleTarget(key,p,floorY));
  }

  dragHandle(handle: HandleKey, target: THREE.Vector3, locked: ReadonlySet<HandleKey> = new Set(), floorY = -Infinity) {
    const positions = new Map(ragdollHandles.map(key=>[key,this.getHandlePosition(key)]));
    const start = positions.get(handle)!.clone(), end = this.clampHandleTarget(handle,target,floorY);
    const steps = Math.max(1,Math.ceil(start.distanceTo(end)/.02));
    // Small steps let contacts respond along the drag rather than teleporting
    // a hand/foot through the torso on a sparse pointer event.
    for(let step=1;step<=steps;step++){
      const previous = new Map([...positions].map(([key,p])=>[key,p.clone()]));
      const grab = start.clone().lerp(end,step/steps);
      if(handle === 'pelvis' && locked.size===0){
        const delta=grab.clone().sub(positions.get('pelvis')!);
        positions.forEach(p=>p.add(delta));
      }
      this.constraints.solve(positions,locked,(key,p)=>this.clampHandleTarget(key,p,floorY),{key:handle,target:grab});
      // An explicit pin can make a cursor target unreachable. Stop at the
      // last valid pose instead of stretching bones between two fixed points.
      if ([...locked].some(key=>key!==handle) && Object.entries(ragdollParents).some(([child,parent])=>
        Math.abs(positions.get(parent)!.distanceTo(positions.get(child as HandleKey)!)-this.getRestLength(parent,child as HandleKey))>.0015)) {
        previous.forEach((p,key)=>positions.get(key)!.copy(p));
        break;
      }
    }
    this.setHandlePositions(positions);
  }

  rotateHandle(handle: HandleKey, axis: THREE.Vector3, angle: number) {
    const parent = ragdollParents[handle];
    const pivot = parent ? this.getHandlePosition(parent) : this.getHandlePosition('pelvis');
    const rotation = new THREE.Quaternion().setFromAxisAngle(axis.clone().normalize(), angle);
    const descendants = new Set<HandleKey>();
    const visit = (candidate: HandleKey) => {
      if (candidate === handle || ragdollParents[candidate] && descendants.has(ragdollParents[candidate]!)) {
        descendants.add(candidate);
      }
    };
    ragdollHandles.forEach(visit);
    // A second pass reaches hands/feet after their intermediate joints.
    ragdollHandles.forEach(visit);
    if (handle === 'pelvis') ragdollHandles.forEach((candidate) => descendants.add(candidate));

    descendants.forEach((candidate) => {
      if (candidate === 'pelvis') return;
      const bone = handleBones[candidate];
      const position = this.currentJoints.get(bone);
      if (!position) return;
      const worldPosition = position.clone().add(this.rootTranslation);
      worldPosition.sub(pivot).applyQuaternion(rotation).add(pivot).sub(this.rootTranslation);
      this.currentJoints.set(bone, worldPosition);
    });
  }

  boneGlobals() {
    const deltas = new Map(
      Object.entries(segments).map(([name, segment]) => [name, segmentDelta(this.baseJoints, this.currentJoints, segment)]),
    );
    const result = new Map<string, THREE.Matrix4>();
    const rootTransform = new THREE.Matrix4().makeTranslation(
      this.rootTranslation.x,
      this.rootTranslation.y,
      this.rootTranslation.z,
    );
    this.globals.forEach((global, boneName) => {
      const segmentName = segmentForBone(boneName);
      const transformed = segmentName ? deltas.get(segmentName)!.clone().multiply(global) : global.clone();
      result.set(boneName, rootTransform.clone().multiply(transformed));
    });
    return result;
  }
}

export function createRigModel(json: RigJson): RigModel {
  return {
    parts: json.meshes.map((mesh) => {
      const geometry = new THREE.BufferGeometry();
      const positions = new Float32Array(mesh.positions);
      const normals = new Float32Array(mesh.normals);
      geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions), 3));
      geometry.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(normals), 3));
      geometry.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(mesh.uvs), 2));
      geometry.setIndex(mesh.indices);
      return {
        geometry,
        positions,
        normals,
        boneNames: mesh.boneNames,
        offsets: mesh.offsets.map(matrixFromRowMajor),
        joints: new Uint16Array(mesh.joints),
        weights: new Float32Array(mesh.weights),
      };
    }),
  };
}

function rigBindGlobals(model: RigModel) {
  const result = new Map<string, THREE.Matrix4>();
  model.parts.forEach((part) => {
    part.boneNames.forEach((name, index) => {
      if (!result.has(name)) result.set(name, part.offsets[index].clone().invert());
    });
  });
  return result;
}

/**
 * Returns the effective joint positions produced by this rig's own inverse-bind
 * matrices and the shared pose. This deliberately does not assume that two
 * meshes with the same bone names also have the same bind skeleton.
 */
export function rigJointPositions(model: RigModel, pose: PzRagdollPose) {
  const bindGlobals = rigBindGlobals(model);
  const poseGlobals = pose.boneGlobals();
  const result = new Map<string, THREE.Vector3>();
  bindGlobals.forEach((bindGlobal, name) => {
    const poseGlobal = poseGlobals.get(name);
    if (!poseGlobal) return;
    const offset = bindGlobal.clone().invert();
    const skinMatrix = poseGlobal.clone().multiply(offset);
    const bindJoint = new THREE.Vector3().setFromMatrixPosition(bindGlobal);
    result.set(name, bindJoint.applyMatrix4(skinMatrix));
  });
  return result;
}

export function compareRigSkeletons(reference: RigModel, candidate: RigModel): RigSkeletonComparison {
  const referenceBind = rigBindGlobals(reference);
  const candidateBind = rigBindGlobals(candidate);
  const referencePosition = new THREE.Vector3();
  const candidatePosition = new THREE.Vector3();
  const referenceRotation = new THREE.Quaternion();
  const candidateRotation = new THREE.Quaternion();
  const scale = new THREE.Vector3();
  let commonBones = 0;
  let maxJointDelta = 0;
  let maxRotationDelta = 0;

  candidateBind.forEach((candidateMatrix, name) => {
    const referenceMatrix = referenceBind.get(name);
    if (!referenceMatrix) return;
    commonBones += 1;
    referenceMatrix.decompose(referencePosition, referenceRotation, scale);
    candidateMatrix.decompose(candidatePosition, candidateRotation, scale);
    referenceRotation.normalize();
    candidateRotation.normalize();
    maxJointDelta = Math.max(maxJointDelta, referencePosition.distanceTo(candidatePosition));
    maxRotationDelta = Math.max(maxRotationDelta, referenceRotation.angleTo(candidateRotation));
  });

  return {
    commonBones,
    missingBones: [...referenceBind.keys()].filter((name) => !candidateBind.has(name)),
    maxJointDelta,
    maxRotationDelta,
  };
}

export function cloneRigWithMaterial(model: RigModel, material: THREE.Material) {
  const group = new THREE.Group();
  model.parts.forEach((part) => {
    const mesh = new THREE.Mesh(part.geometry, material);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
  });
  return group;
}

export function skinRigModel(model: RigModel, pose: PzRagdollPose) {
  const globals = pose.boneGlobals();
  const identity = new THREE.Matrix4();
  const basePoint = new THREE.Vector3();
  const transformedPoint = new THREE.Vector3();
  const outputPoint = new THREE.Vector3();
  const baseNormal = new THREE.Vector3();
  const transformedNormal = new THREE.Vector3();
  const outputNormal = new THREE.Vector3();

  model.parts.forEach((part) => {
    const skinMatrices = part.boneNames.map((name, index) =>
      (globals.get(name) ?? identity).clone().multiply(part.offsets[index]));
    const normalMatrices = skinMatrices.map((matrix) => new THREE.Matrix3().getNormalMatrix(matrix));
    const position = part.geometry.getAttribute('position') as THREE.BufferAttribute;
    const normal = part.geometry.getAttribute('normal') as THREE.BufferAttribute;
    const vertexCount = part.positions.length / 3;

    for (let vertexIndex = 0; vertexIndex < vertexCount; vertexIndex += 1) {
      basePoint.fromArray(part.positions, vertexIndex * 3);
      baseNormal.fromArray(part.normals, vertexIndex * 3);
      outputPoint.set(0, 0, 0);
      outputNormal.set(0, 0, 0);
      for (let slot = 0; slot < 4; slot += 1) {
        const influenceIndex = vertexIndex * 4 + slot;
        const weight = part.weights[influenceIndex];
        if (weight === 0) continue;
        const boneIndex = part.joints[influenceIndex];
        transformedPoint.copy(basePoint).applyMatrix4(skinMatrices[boneIndex]);
        transformedNormal.copy(baseNormal).applyMatrix3(normalMatrices[boneIndex]);
        outputPoint.addScaledVector(transformedPoint, weight);
        outputNormal.addScaledVector(transformedNormal, weight);
      }
      position.setXYZ(vertexIndex, outputPoint.x, outputPoint.y, outputPoint.z);
      outputNormal.normalize();
      normal.setXYZ(vertexIndex, outputNormal.x, outputNormal.y, outputNormal.z);
    }

    position.needsUpdate = true;
    normal.needsUpdate = true;
    part.geometry.computeBoundingBox();
    part.geometry.computeBoundingSphere();
  });
}

export function disposeRigModel(model: RigModel) {
  model.parts.forEach((part) => part.geometry.dispose());
}
