import * as THREE from 'three';
import { clothReleaseVelocities } from './cloth-release.ts';
import { clothEdgeContacts } from './cloth-edge-contacts.ts';
import { makeClothBend, solveClothBends, type ClothBend } from './cloth-bending.ts';

export type ClothSurface = {
  positions: Float32Array;
  normals?: Float32Array;
  uvs: Float32Array;
  indices: Uint32Array;
};
export type ClothInput = {
  fabricStiffness?: number;
  layerId?: number;
  surfaces: ClothSurface[];
  releaseTime: number;
  target: [number, number, number];
  seed: number;
  flightTime?: number;
  spin?: number;
};
export type Capsule = { a: [number, number, number]; b: [number, number, number]; radius: number };
export type ClothBakeInput = { items: ClothInput[]; floor: number; duration: number; capsules: Capsule[] };
export type ClothTrack = {
  positions: Float32Array;
  uvs: Float32Array;
  indices: Uint32Array;
  particleForVertex: Uint32Array;
  particleCount: number;
  releaseTime: number;
  frames: Float32Array;
};
export type ClothBake = { fps: number; frameCount: number; tracks: ClothTrack[] };

type Constraint = { a: number; b: number; rest: number; compliance: number; lambda: number };
type Cloth = {
  track: ClothTrack; p: THREE.Vector3[]; old: THREE.Vector3[]; rest: THREE.Vector3[];
  v: THREE.Vector3[]; inverseMass: number[]; triangles: number[][];
  constraints: Constraint[]; bends: ClothBend[]; neighbours: Set<number>[]; edges:number[][]; target: THREE.Vector3;
  active: boolean; sleeping: boolean; quietTime: number; contact: boolean[];
};

const FPS = 60;
const SUBSTEPS = 8;
const DT = 1 / (FPS * SUBSTEPS);
export const CLOTH_MAX_EDGE = 0.025;
export const CLOTH_THICKNESS = 0.0015;
const THICKNESS = CLOTH_THICKNESS;
const GRAVITY = 9.81;
const point = (array: ArrayLike<number>, i: number) => new THREE.Vector3(array[i * 3], array[i * 3 + 1], array[i * 3 + 2]);

function prepare(input: ClothInput, frameCount: number, maxEdge = CLOTH_MAX_EDGE): Cloth {
  const positions: number[] = [], uvs: number[] = [], renderIndices: number[] = [];
  const particles: THREE.Vector3[] = [], particleForVertex: number[] = [];
  const triangles: number[][] = [];
  const welded = new Map<string, number>();
  const addParticle = (p: THREE.Vector3) => {
    const key = `${Math.round(p.x * 1e6)},${Math.round(p.y * 1e6)},${Math.round(p.z * 1e6)}`;
    let id = welded.get(key);
    if (id === undefined) { id = particles.length; particles.push(p.clone()); welded.set(key, id); }
    return id;
  };
  const emit = (p: THREE.Vector3[], uv: THREE.Vector2[], depth: number) => {
    const lengths = [0, 1, 2].map((i) => p[i].distanceToSquared(p[(i + 1) % 3]));
    const longest = lengths.indexOf(Math.max(...lengths));
    if (depth < 16 && lengths[longest] > maxEdge ** 2) {
      const a = longest, b = (a + 1) % 3, c = (a + 2) % 3;
      const midpoint = p[a].clone().add(p[b]).multiplyScalar(0.5);
      const midpointUv = uv[a].clone().add(uv[b]).multiplyScalar(0.5);
      emit([p[a], midpoint, p[c]], [uv[a], midpointUv, uv[c]], depth + 1);
      emit([midpoint, p[b], p[c]], [midpointUv, uv[b], uv[c]], depth + 1);
      return;
    }
    const ids = p.map(addParticle);
    if (new Set(ids).size < 3) return;
    triangles.push(ids);
    for (let i = 0; i < 3; i++) {
      renderIndices.push(particleForVertex.length);
      positions.push(p[i].x, p[i].y, p[i].z);
      uvs.push(uv[i].x, uv[i].y);
      particleForVertex.push(ids[i]);
    }
  };
  for (const surface of input.surfaces) {
    // Longest-edge refinement leaves already-small source triangles alone.
    // Shared source edges bisect at the same positions; UV seams remain welded.
    for (let i = 0; i < surface.indices.length; i += 3) {
      const ids = [...surface.indices.slice(i, i + 3)];
      emit(ids.map((id) => point(surface.positions, id)), ids.map((id) => new THREE.Vector2(surface.uvs[id * 2], surface.uvs[id * 2 + 1])), 0);
    }
  }
  const masses = particles.map(() => 0);
  const edges = new Map<string, { a: number; b: number; faces: Array<{u:number; v:number; opposite:number}> }>();
  const constraints: Constraint[] = [];
  const bends: ClothBend[] = [];
  const neighbours = particles.map(() => new Set<number>());
  for (const [a, b, c] of triangles) {
    const area = particles[b].clone().sub(particles[a]).cross(particles[c].clone().sub(particles[a])).length() * 0.5;
    for (const id of [a, b, c]) masses[id] += area * 0.28 / 3;
    for (const [u, v, opposite] of [[a, b, c], [b, c, a], [c, a, b]]) {
      neighbours[u].add(v); neighbours[v].add(u);
      const key = u < v ? `${u}:${v}` : `${v}:${u}`;
      const existing = edges.get(key);
      if (existing) {
        existing.faces.push({u,v,opposite});
      } else {
        edges.set(key, { a: u, b: v, faces:[{u,v,opposite}] });
        constraints.push({ a: u, b: v, rest: particles[u].distanceTo(particles[v]), compliance: 1e-9, lambda: 0 });
      }
    }
  }
  for (const {a,b,faces} of edges.values()) {
    // Only an oriented, manifold pair defines an interior bending hinge.
    if (faces.length !== 2 || faces[1].u !== b || faces[1].v !== a) continue;
    const bend = makeClothBend(particles,a,b,faces[0].opposite,faces[1].opposite);
    if (bend) bends.push(bend);
  }
  const track: ClothTrack = {
    positions: new Float32Array(positions), uvs: new Float32Array(uvs), indices: new Uint32Array(renderIndices),
    particleForVertex: new Uint32Array(particleForVertex), particleCount: particles.length,
    releaseTime: input.releaseTime, frames: new Float32Array(frameCount * particles.length * 3),
  };
  return {
    track, p: particles, old: particles.map((p) => p.clone()), rest: particles.map((p) => p.clone()),
    v: particles.map(() => new THREE.Vector3()), inverseMass: masses.map((m) => 1 / Math.max(m, 0.00002)),
    triangles, constraints, bends, neighbours, edges:[...edges.values()].map(({a,b})=>[a,b]), target: new THREE.Vector3(...input.target),
    active: false, sleeping: false, quietTime: 0, contact: particles.map(() => false),
  };
}

const delta = new THREE.Vector3();
function stretch(cloth: Cloth, dt = DT) {
  for (const constraint of cloth.constraints) {
    const { a, b, rest, compliance } = constraint;
    delta.subVectors(cloth.p[a], cloth.p[b]);
    const length = delta.length();
    if (length < 1e-10) continue;
    const alpha = compliance / (dt * dt);
    const lambda = (-(length - rest) - alpha * constraint.lambda) / (cloth.inverseMass[a] + cloth.inverseMass[b] + alpha);
    constraint.lambda += lambda;
    delta.multiplyScalar(lambda / length);
    cloth.p[a].addScaledVector(delta, cloth.inverseMass[a]);
    cloth.p[b].addScaledVector(delta, -cloth.inverseMass[b]);
  }
}

const closest = new THREE.Vector3(), normal = new THREE.Vector3(), ab = new THREE.Vector3();
const bary = new THREE.Vector3(), previous = new THREE.Vector3();
const triangle = new THREE.Triangle();
type Face = { cloth: Cloth; ids: number[]; minX: number; maxX: number; minY: number; maxY: number; minZ: number; maxZ: number };
const oldTriangle = new THREE.Triangle();
type ContactCache={grid?:Map<string,Face[]>;positions?:Float64Array[]};
export function clothContacts(cloths: Cloth[],cache?:ContactCache) {
  const padding=cache ? .003 : 0;
  let valid=!!cache?.grid;
  if(valid)cloths.forEach((cloth,index)=>{if(cloth.active)for(let i=0;i<cloth.p.length;i++){const p=cloth.p[i],before=cache!.positions![index];if(Math.abs(p.x-before[i*3])>padding||Math.abs(p.y-before[i*3+1])>padding||Math.abs(p.z-before[i*3+2])>padding){valid=false;break;}}});
  const grid = valid?cache!.grid!:new Map<string, Face[]>();
  const cell = 0.028;
  if(!valid){
  for (const cloth of cloths) {
    if (!cloth.active) continue;
    for (const ids of cloth.triangles) {
      const [a, b, c] = ids;
      const pa = cloth.p[a], pb = cloth.p[b], pc = cloth.p[c];
      const oa = cloth.old[a], ob = cloth.old[b], oc = cloth.old[c];
      const face: Face = { cloth, ids,
        minX: Math.min(pa.x,pb.x,pc.x,oa.x,ob.x,oc.x) - THICKNESS,
        maxX: Math.max(pa.x,pb.x,pc.x,oa.x,ob.x,oc.x) + THICKNESS,
        minY: Math.min(pa.y,pb.y,pc.y,oa.y,ob.y,oc.y) - THICKNESS,
        maxY: Math.max(pa.y,pb.y,pc.y,oa.y,ob.y,oc.y) + THICKNESS,
        minZ: Math.min(pa.z,pb.z,pc.z,oa.z,ob.z,oc.z) - THICKNESS,
        maxZ: Math.max(pa.z,pb.z,pc.z,oa.z,ob.z,oc.z) + THICKNESS,
      };
      face.minX-=padding;face.maxX+=padding;face.minY-=padding;face.maxY+=padding;face.minZ-=padding;face.maxZ+=padding;
      const minX = Math.floor(face.minX / cell), maxX = Math.floor(face.maxX / cell);
      const minY = Math.floor(face.minY / cell), maxY = Math.floor(face.maxY / cell);
      const minZ = Math.floor(face.minZ / cell), maxZ = Math.floor(face.maxZ / cell);
      if (maxX - minX > 80 || maxY - minY > 80 || maxZ - minZ > 80) throw new Error('Cloth solver diverged');
      for (let x = minX; x <= maxX; x++) for (let y = minY; y <= maxY; y++) for (let z = minZ; z <= maxZ; z++) {
        const key = `${x},${y},${z}`;
        const bucket = grid.get(key);
        if (bucket) bucket.push(face); else grid.set(key, [face]);
      }
    }
  }
  if(cache){cache.grid=grid;cache.positions=cloths.map(cloth=>Float64Array.from(cloth.p.flatMap(p=>[p.x,p.y,p.z])));}
  }
  for (const cloth of cloths) {
    if (!cloth.active || cloth.sleeping) continue;
    for (let i = 0; i < cloth.p.length; i++) {
      const p = cloth.p[i];
      const old = cloth.old[i];
      const minX = Math.min(p.x,old.x), maxX = Math.max(p.x,old.x);
      const minY = Math.min(p.y,old.y), maxY = Math.max(p.y,old.y);
      const minZ = Math.min(p.z,old.z), maxZ = Math.max(p.z,old.z);
      const x0 = Math.floor(minX/cell), x1 = Math.floor(maxX/cell);
      const y0 = Math.floor(minY/cell), y1 = Math.floor(maxY/cell);
      const z0 = Math.floor(minZ/cell), z1 = Math.floor(maxZ/cell);
      // Broad phase must cover the vertex's travelled segment too. Looking
      // only at its new position discards exactly the fast crossings that
      // the continuous narrow-phase test below is meant to resolve.
      let bucket: Iterable<Face> | undefined;
      if (x0===x1 && y0===y1 && z0===z1) bucket=grid.get(`${x0},${y0},${z0}`);
      else {
        const swept = new Set<Face>();
        for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++)for(let z=z0;z<=z1;z++) {
          const faces=grid.get(`${x},${y},${z}`);
          if(faces)for(const face of faces)swept.add(face);
        }
        bucket=swept;
      }
      if (!bucket) continue;
      for (const face of bucket) {
        if (maxX < face.minX || minX > face.maxX || maxY < face.minY || minY > face.maxY || maxZ < face.minZ || minZ > face.maxZ) continue;
        const other = face.cloth;
        const [a, b, c] = face.ids;
        if (other === cloth && (a === i || b === i || c === i || cloth.neighbours[i].has(a) || cloth.neighbours[i].has(b) || cloth.neighbours[i].has(c))) continue;
        triangle.set(other.p[a], other.p[b], other.p[c]);
        triangle.closestPointToPoint(p, closest);
        const distance = p.distanceTo(closest);
        if (distance > 0.025) continue;
        if (other === cloth) {
          // Source skins contain touching seams and very small triangles.
          // Rest-neighbour surfaces must not repel one another as if they
          // were newly colliding folds; that would stretch the textile.
          oldTriangle.set(cloth.rest[a], cloth.rest[b], cloth.rest[c]);
          oldTriangle.closestPointToPoint(cloth.rest[i], previous);
          if (previous.distanceToSquared(cloth.rest[i]) < (THICKNESS * 1.5) ** 2) {
            cloth.neighbours[i].add(a); cloth.neighbours[i].add(b); cloth.neighbours[i].add(c);
            continue;
          }
        }
        triangle.getNormal(normal);
        if (normal.lengthSq() < 0.5) continue;
        const signed = delta.subVectors(p, other.p[a]).dot(normal);
        // Keep the previous side on a face crossing. Fixed 480 Hz substeps
        // and this swept plane test stop cloth from tunnelling through a layer.
        oldTriangle.set(other.old[a], other.old[b], other.old[c]);
        oldTriangle.getNormal(ab);
        const oldSigned = previous.subVectors(cloth.old[i], other.old[a]).dot(ab);
        const crossed = signed * oldSigned < 0 && Math.abs(signed) < 0.025 && Math.abs(oldSigned) < 0.025 && triangle.containsPoint(closest) && distance < Math.abs(signed) + 1e-6;
        if (distance >= THICKNESS && !crossed) continue;
        if (!crossed && distance > 1e-7) normal.subVectors(p, closest).divideScalar(distance);
        else if (oldSigned < 0) normal.negate();
        triangle.getBarycoord(closest, bary);
        const weights = [Math.max(0, bary.x), Math.max(0, bary.y), Math.max(0, bary.z)];
        const wi = cloth.inverseMass[i];
        const inv = face.ids.map((id) => other.sleeping ? 0 : other.inverseMass[id]);
        const denominator = wi + weights.reduce((sum, w, j) => sum + w * w * inv[j], 0);
        const correction = (THICKNESS - delta.subVectors(p, closest).dot(normal)) / denominator;
        if (correction <= 0) continue;
        p.addScaledVector(normal, correction * wi);
        face.ids.forEach((id, j) => other.p[id].addScaledVector(normal, -correction * weights[j] * inv[j]));
        if (other !== cloth) {
          cloth.contact[i] = true;
          face.ids.forEach((id) => { other.contact[id] = true; });
        }
        // Coulomb tangential contact, not air damping: sliding can reach rest.
        delta.subVectors(p, cloth.old[i]);
        face.ids.forEach((id, j) => delta.addScaledVector(previous.subVectors(other.p[id], other.old[id]), -weights[j]));
        delta.addScaledVector(normal, -delta.dot(normal));
        const slip = delta.length();
        if (slip > 1e-9) {
          delta.multiplyScalar(Math.min(slip, correction * denominator * 0.65) / (slip * denominator));
          p.addScaledVector(delta, -wi);
          face.ids.forEach((id, j) => other.p[id].addScaledVector(delta, weights[j] * inv[j]));
        }
      }
    }
  }
}

function environmentContacts(cloth: Cloth, floor: number, capsules: Capsule[], dt = DT) {
  for (let i = 0; i < cloth.p.length; i++) {
    const p = cloth.p[i];
    for (const capsule of capsules) {
      const r = capsule.radius + THICKNESS;
      if (p.x < Math.min(capsule.a[0], capsule.b[0]) - r || p.x > Math.max(capsule.a[0], capsule.b[0]) + r
        || p.y < Math.min(capsule.a[1], capsule.b[1]) - r || p.y > Math.max(capsule.a[1], capsule.b[1]) + r
        || p.z < Math.min(capsule.a[2], capsule.b[2]) - r || p.z > Math.max(capsule.a[2], capsule.b[2]) + r) continue;
      closest.set(...capsule.a);
      ab.set(...capsule.b).sub(closest);
      delta.copy(p).sub(closest);
      const t = THREE.MathUtils.clamp(delta.dot(ab) / Math.max(1e-12, ab.lengthSq()), 0, 1);
      closest.set(...capsule.a).addScaledVector(ab, t);
      normal.subVectors(p, closest);
      const distance = normal.length();
      if (distance < capsule.radius + THICKNESS && distance > 1e-8) {
        p.copy(closest).addScaledVector(normal, (capsule.radius + THICKNESS) / distance);
        cloth.contact[i] = true;
      }
    }
    if (p.y < floor + THICKNESS / 2) {
      const correction = floor + THICKNESS / 2 - p.y;
      p.y = floor + THICKNESS / 2;
      delta.subVectors(p, cloth.old[i]); delta.y = 0;
      const slip = delta.length();
      if (slip > 1e-10) p.addScaledVector(delta, -Math.min(1, (correction + GRAVITY * dt * dt) * 0.85 / slip));
      cloth.contact[i] = true;
    }
  }
}

/** Approximate particle contacts; final quality uses swept faces and edges. */
function quickParticleContacts(cloths: Cloth[]) {
  const gap = .008, grid = new Map<string, Array<{cloth: Cloth; i: number}>>();
  for (const cloth of cloths) if (cloth.active) for (let i=0;i<cloth.p.length;i++) {
    const p=cloth.p[i], x=Math.floor(p.x/gap), y=Math.floor(p.y/gap), z=Math.floor(p.z/gap);
    for(let dx=-1;dx<=1;dx++)for(let dy=-1;dy<=1;dy++)for(let dz=-1;dz<=1;dz++) {
      for(const other of grid.get(`${x+dx},${y+dy},${z+dz}`)??[]) {
        if(other.cloth===cloth && cloth.neighbours[i].has(other.i))continue;
        const q=other.cloth.p[other.i]; delta.subVectors(p,q);const d=delta.length();
        if(d>=gap || d<1e-9)continue;
        const wa=cloth.sleeping?0:cloth.inverseMass[i], wb=other.cloth.sleeping?0:other.cloth.inverseMass[other.i];
        if(wa+wb===0)continue;
        delta.multiplyScalar((gap-d)/(d*(wa+wb)));
        p.addScaledVector(delta,wa);q.addScaledVector(delta,-wb);
        cloth.contact[i]=true;other.cloth.contact[other.i]=true;
      }
    }
    const key=`${x},${y},${z}`, bucket=grid.get(key);
    if(bucket)bucket.push({cloth,i});else grid.set(key,[{cloth,i}]);
  }
}

/** Offline XPBD membrane/bending simulation, cached at fixed times for GIF and seeking. */
export function bakeCloth(input: ClothBakeInput, onProgress: (progress: number) => void = () => {}, quality: 'precise' | 'quick' = 'precise'): ClothBake {
  const quick = quality === 'quick';
  const FPS = quick ? 30 : 60;
  const frameCount = Math.ceil(input.duration * FPS) + 1;
  const cloths = input.items.map((item) => prepare(item, frameCount, quick ? Infinity : CLOTH_MAX_EDGE));
  const iterationPositions=cloths.map(cloth=>new Float64Array(cloth.p.length*3));
  const releaseVelocities = clothReleaseVelocities(input.items);
  const finalRelease = Math.max(0, ...input.items.map((item) => item.releaseTime));
  for (let frame = 0; frame < frameCount; frame++) {
    // Swept face/edge contacts remain enabled; spend 480 Hz only on fast
    // motion. Quiet cloth does not need eight identical tiny steps per frame.
    let maxVelocity=0;
    if(!quick)cloths.forEach((cloth,index)=>{
      if(cloth.active&&!cloth.sleeping)for(const v of cloth.v)maxVelocity=Math.max(maxVelocity,v.length());
      else if(!cloth.active&&input.items[index].releaseTime<=frame/FPS)maxVelocity=Math.max(maxVelocity,releaseVelocities[index].length());
    });
    const SUBSTEPS=quick?2:Math.max(2,Math.min(8,Math.ceil(maxVelocity/(FPS*.012))));
    const DT=1/(FPS*SUBSTEPS);
    for (let substep = 0; substep < (frame === 0 ? 0 : SUBSTEPS); substep++) {
      const time = ((frame - 1) * SUBSTEPS + substep + 1) * DT;
      for (let index = 0; index < cloths.length; index++) {
        const cloth = cloths[index];
        if (!cloth.active && time >= cloth.track.releaseTime && cloth.p.length) {
          cloth.active = true;
          const center = cloth.p.reduce((sum, p) => sum.add(p), new THREE.Vector3()).divideScalar(cloth.p.length);
          // A short upward/outward impulse frees the garment; afterwards no
          // target interpolation or resizing is applied, only forces/contact.
          const velocity = releaseVelocities[index];
          const spin = new THREE.Vector3(0.2 + (input.items[index].spin ?? 0), Math.sin(input.items[index].seed) * 0.65, 0.25);
          cloth.v.forEach((v, i) => v.copy(velocity).add(spin.clone().cross(cloth.p[i].clone().sub(center))));
          cloths.forEach((item) => { item.sleeping = false; item.quietTime = 0; });
        }
        if (!cloth.active || cloth.sleeping) continue;
        cloth.constraints.forEach((c) => { c.lambda = 0; });
        cloth.bends.forEach((bend) => { bend.lambda = 0; });
        cloth.p.forEach((p, i) => {
          cloth.old[i].copy(p); cloth.contact[i] = false;
          cloth.v[i].y -= GRAVITY * DT;
          cloth.v[i].multiplyScalar(Math.exp(-0.06 * DT));
          p.addScaledVector(cloth.v[i], DT);
        });
      }
      // No contact grids or solver iterations for inactive/settled cloth.
      if(!cloths.some(cloth=>cloth.active&&!cloth.sleeping))continue;
      const contactCache:ContactCache={};
      for (let iteration = 0; iteration < (quick ? 6 : 32); iteration++) {
        const checkConvergence=!quick&&iteration>=4&&iteration%4===0;
        if(checkConvergence)cloths.forEach((cloth,index)=>{if(cloth.active&&!cloth.sleeping)cloth.p.forEach((p,i)=>p.toArray(iterationPositions[index],i*3));});
        if (!quick && iteration % 4 === 0) clothContacts(cloths,contactCache);
        if (!quick && iteration === 0) clothEdgeContacts(cloths, THICKNESS);
        if (quick && iteration === 0) quickParticleContacts(cloths);
        for (const cloth of cloths) if (cloth.active && !cloth.sleeping) {
          solveClothBends(cloth.p,cloth.inverseMass,cloth.bends,DT);
          stretch(cloth, DT);
        }
        for (const cloth of cloths) if (cloth.active && !cloth.sleeping) {
          // The removal impulse releases the closed garment from its wearer.
          // Corpse contacts arm after this short extraction interval; cloth–
          // cloth contacts and gravity remain active throughout the release.
          // Otherwise a closed trouser tube is topologically trapped on a leg.
          environmentContacts(cloth, input.floor, time - cloth.track.releaseTime < 0.18 ? [] : input.capsules, DT);
        }
        if(checkConvergence){
          let movement=0;
          cloths.forEach((cloth,index)=>{if(cloth.active&&!cloth.sleeping)cloth.p.forEach((p,i)=>{const old=iterationPositions[index];movement=Math.max(movement,Math.abs(p.x-old[i*3]),Math.abs(p.y-old[i*3+1]),Math.abs(p.z-old[i*3+2]));});});
          if(movement<.00001)break;
        }
      }
      for (const cloth of cloths) {
        if (!cloth.active || cloth.sleeping) continue;
        let maxSpeed = 0;
        cloth.v.forEach((v, i) => {
          v.subVectors(cloth.p[i], cloth.old[i]).divideScalar(DT);
          // Internal cloth contacts conserve the centre-of-mass momentum.
          // Friction is applied to relative tangential motion at the contact,
          // never as global damping of an airborne garment.
          maxSpeed = Math.max(maxSpeed, v.length());
          if (!Number.isFinite(v.lengthSq()) || v.lengthSq() > 1e5) throw new Error('Non-finite cloth state');
        });
        const supported = cloth.contact.some(Boolean);
        cloth.quietTime = supported && maxSpeed < 0.045 ? cloth.quietTime + DT : 0;
        if (cloth.quietTime > 0.25 && time > finalRelease + 0.8) {
          cloth.sleeping = true;
          cloth.v.forEach((v) => v.set(0, 0, 0));
          cloth.old.forEach((p, i) => p.copy(cloth.p[i]));
        }
      }
    }
    for (const cloth of cloths) {
      const offset = frame * cloth.p.length * 3;
      cloth.p.forEach((p, i) => p.toArray(cloth.track.frames, offset + i * 3));
    }
    if (frame % 6 === 0) onProgress(frame / Math.max(1, frameCount - 1));
  }
  onProgress(1);
  return { fps: FPS, frameCount, tracks: cloths.map((cloth) => cloth.track) };
}

export function sampleCloth(track: ClothTrack, bake: Pick<ClothBake, 'fps' | 'frameCount'>, time: number, output: Float32Array) {
  const frame = THREE.MathUtils.clamp(time * bake.fps, 0, bake.frameCount - 1);
  const lower = Math.floor(frame), upper = Math.min(lower + 1, bake.frameCount - 1), blend = frame - lower;
  for (let i = 0; i < track.particleForVertex.length; i++) {
    const particle = track.particleForVertex[i];
    for (let axis = 0; axis < 3; axis++) {
      const a = track.frames[(lower * track.particleCount + particle) * 3 + axis];
      const b = track.frames[(upper * track.particleCount + particle) * 3 + axis];
      output[i * 3 + axis] = a + (b - a) * blend;
    }
  }
}
