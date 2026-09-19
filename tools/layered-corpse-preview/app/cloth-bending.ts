import * as THREE from 'three';

export type ClothBend = {
  a: number; b: number; c: number; d: number;
  compliance: number; lambda: number;
};

// No memory of the dressed body: gentle bends are entirely free. Only sharp
// folds receive a weak, symmetric smoothing force, not a shell-restoring force.
export const CLOTH_BEND_COMPLIANCE = 720000;
export const CLOTH_FREE_BEND_ANGLE = Math.PI / 3;
const edge = new THREE.Vector3(), u = new THREE.Vector3(), v = new THREE.Vector3();
const n1 = new THREE.Vector3(), n2 = new THREE.Vector3(), cross = new THREE.Vector3();
const gradients = Array.from({length:4}, () => new THREE.Vector3());

/** Signed dihedral angle and its four position derivatives. Normals are
 * oriented as faces (a,b,c) and (b,a,d); zero is a flat, unfolded patch.
 * Degenerate triangles have no defined bending axis and are skipped.
 */
export function clothHinge(a: THREE.Vector3, b: THREE.Vector3, c: THREE.Vector3, d: THREE.Vector3,
  output?: THREE.Vector3[]): number | null {
  edge.subVectors(b,a); u.subVectors(c,a); v.subVectors(d,a);
  const lengthSq = edge.lengthSq(), length = Math.sqrt(lengthSq);
  n1.crossVectors(edge,u); n2.crossVectors(v,edge);
  const area1 = n1.lengthSq(), area2 = n2.lengthSq();
  if (lengthSq < 1e-16 || area1 < 1e-20 || area2 < 1e-20) return null;
  const angle = Math.atan2(cross.crossVectors(n1,n2).dot(edge)/length, n1.dot(n2));
  if (output) {
    output[2].copy(n1).multiplyScalar(-length/area1);
    output[3].copy(n2).multiplyScalar(-length/area2);
    const t1 = u.dot(edge)/lengthSq, t2 = v.dot(edge)/lengthSq;
    output[0].copy(output[2]).multiplyScalar(t1-1).addScaledVector(output[3],t2-1);
    output[1].copy(output[2]).multiplyScalar(-t1).addScaledVector(output[3],-t2);
  }
  return angle;
}

export function makeClothBend(p: THREE.Vector3[], a: number, b: number, c: number, d: number): ClothBend | null {
  if (c === d) return null;
  if (clothHinge(p[a],p[b],p[c],p[d]) === null) return null;
  // Edge/dual-area weighting keeps the material response comparable when
  // triangle aspect ratios differ. It is fixed in material/rest coordinates.
  const geometryWeight = 3 * p[a].distanceToSquared(p[b]) / (n1.length()+n2.length());
  return {a,b,c,d,compliance:CLOTH_BEND_COMPLIANCE/geometryWeight,lambda:0};
}

export function solveClothBends(p: THREE.Vector3[], inverseMass: number[], bends: ClothBend[], dt: number) {
  for (const bend of bends) {
    const {a,b,c,d} = bend;
    const angle = clothHinge(p[a],p[b],p[c],p[d],gradients);
    if (angle === null) continue;
    const error = Math.sign(angle)*Math.max(0,Math.abs(angle)-CLOTH_FREE_BEND_ANGLE);
    if(error===0){bend.lambda=0;continue;}
    const alpha = bend.compliance / (dt*dt);
    const denominator = inverseMass[a]*gradients[0].lengthSq()+inverseMass[b]*gradients[1].lengthSq()
      +inverseMass[c]*gradients[2].lengthSq()+inverseMass[d]*gradients[3].lengthSq();
    if (denominator < 1e-12) continue;
    const dlambda = (-error-alpha*bend.lambda)/(denominator+alpha);
    bend.lambda += dlambda;
    p[a].addScaledVector(gradients[0],inverseMass[a]*dlambda);
    p[b].addScaledVector(gradients[1],inverseMass[b]*dlambda);
    p[c].addScaledVector(gradients[2],inverseMass[c]*dlambda);
    p[d].addScaledVector(gradients[3],inverseMass[d]*dlambda);
  }
}
