import * as THREE from 'three';
import type { RigModel } from './pz-rig.ts';
type BackAnchor = {partIndex:number;ids:[number,number,number];barycentric:THREE.Vector3;up:THREE.Vector3;back:THREE.Vector3;points:THREE.Vector3[]};

/** Locate the anatomical back BEFORE posing. A world-down ray is not a back
 * locator: after ragdoll edits it can hit a hip, arm, or empty space. */
export function findBackAnchor(model: RigModel) {
  const binds = new Map<string, THREE.Vector3>();
  for (const part of model.parts) part.boneNames.forEach((name,i) =>
    binds.set(name,new THREE.Vector3().setFromMatrixPosition(part.offsets[i].clone().invert())));
  const chest=binds.get('Bip01_Spine1')!, neck=binds.get('Bip01_Neck')!;
  const up=neck.clone().sub(chest).normalize();
  const back=binds.get('Bip01_DressBack')!.clone().sub(binds.get('Bip01_DressFront')!);
  back.addScaledVector(up,-back.dot(up)).normalize();
  const target=chest.clone().lerp(neck,.3);
  const ray=new THREE.Ray(target.clone().addScaledVector(back,1),back.clone().negate());
  let result: BackAnchor | null=null;
  let nearest=Infinity;
  model.parts.forEach((part,partIndex)=>{
    const index=part.geometry.index;
    for(let i=0;i<(index?.count ?? part.positions.length/3);i+=3){
      const ids=[0,1,2].map(j=>index ? index.getX(i+j) : i+j) as [number,number,number];
      const torsoWeight=ids.reduce((sum,id)=>sum+[0,1,2,3].reduce((w,k)=>
        w+(/^Bip01_(Spine\d*|Neck|BackPack)$/.test(part.boneNames[part.joints[id*4+k]]) ? part.weights[id*4+k] : 0),0),0)/3;
      if(torsoWeight<.7)continue;
      const points=ids.map(id=>new THREE.Vector3().fromArray(part.positions,id*3));
      const hit=ray.intersectTriangle(points[0],points[1],points[2],false,new THREE.Vector3());
      if(!hit || hit.clone().sub(target).dot(back)<=0)continue;
      const distance=hit.distanceToSquared(ray.origin);
      if(distance>=nearest)continue;
      nearest=distance;
      result={partIndex,ids,points,up,back,barycentric:new THREE.Triangle(...points as [THREE.Vector3,THREE.Vector3,THREE.Vector3]).getBarycoord(hit,new THREE.Vector3())!};
    }
  });
  if(!result)throw new Error('Не найдена поверхность спины для крепления топора');
  return result as BackAnchor;
}

export function mountAxeOnBack(model: RigModel, root: THREE.Group, space: THREE.Object3D,
  position: THREE.Vector3, rotation: THREE.Quaternion) {
  const anchor=findBackAnchor(model);
  const mesh=root.children[anchor.partIndex] as THREE.Mesh;
  const restFrame=surfaceFrame(anchor.points,anchor.barycentric)!;
  const currentFrame=surfaceFrame(surfaceTriangle(mesh,space,anchor.ids),anchor.barycentric)!;
  const deformation=currentFrame.clone().multiply(restFrame.clone().invert());
  const normal=new THREE.Triangle(...anchor.points as [THREE.Vector3,THREE.Vector3,THREE.Vector3]).getNormal(new THREE.Vector3());
  if(normal.dot(anchor.back)<0)normal.negate();
  normal.transformDirection(deformation);
  const up=anchor.up.clone().transformDirection(deformation);
  // The handle points outward and toward the feet, in the BODY frame.
  const y=normal.clone().addScaledVector(up,-.7).normalize().negate();
  const x=new THREE.Vector3().crossVectors(up,normal).normalize();
  const z=new THREE.Vector3().crossVectors(x,y).normalize();
  x.crossVectors(y,z).normalize();
  rotation.setFromRotationMatrix(new THREE.Matrix4().makeBasis(x,y,z));
  const surface=new THREE.Vector3().setFromMatrixPosition(currentFrame);
  position.copy(surface).addScaledVector(normal,-.006)
    .sub(new THREE.Vector3(0,.23,-.035).applyQuaternion(rotation));
  return captureSurfaceAttachment(mesh,space,anchor.ids,space.localToWorld(surface.clone()),position,rotation)!;
}

/** Preserve the already verified attachment transform in bone-local space. */
export function captureRigAttachment(bone: THREE.Matrix4, position: THREE.Vector3, rotation: THREE.Quaternion) {
  return bone.clone().invert().multiply(new THREE.Matrix4().compose(position,rotation,new THREE.Vector3(1,1,1)));
}

export function updateRigAttachment(bone: THREE.Matrix4, local: THREE.Matrix4, position: THREE.Vector3, rotation: THREE.Quaternion) {
  bone.clone().multiply(local).decompose(position,rotation,new THREE.Vector3());
}

type SurfaceAttachment = {
  mesh: THREE.Mesh;
  space: THREE.Object3D;
  ids: [number, number, number];
  barycentric: THREE.Vector3;
  local: THREE.Matrix4;
};

function surfaceTriangle(mesh: THREE.Mesh, space: THREE.Object3D, ids: [number, number, number]) {
  space.updateWorldMatrix(true, false);
  mesh.updateWorldMatrix(true, false);
  const transform = space.matrixWorld.clone().invert().multiply(mesh.matrixWorld);
  const positions = mesh.geometry.getAttribute('position');
  return ids.map(id => new THREE.Vector3().fromBufferAttribute(positions, id).applyMatrix4(transform));
}

function surfaceFrame(points: THREE.Vector3[], barycentric: THREE.Vector3) {
  const [a,b,c] = points;
  const x = b.clone().sub(a), z = x.clone().cross(c.clone().sub(a));
  if(x.lengthSq()<1e-16 || z.lengthSq()<1e-16) return null;
  x.normalize();z.normalize();
  const y = z.clone().cross(x).normalize();
  const origin = a.clone().multiplyScalar(barycentric.x).addScaledVector(b,barycentric.y).addScaledVector(c,barycentric.z);
  return new THREE.Matrix4().makeBasis(x,y,z).setPosition(origin);
}

/** A fixed triangle/barycentric anchor follows the actual blended skin, not
 * one bone. Rebuild an orthonormal frame so skin stretch never scales the axe. */
export function captureSurfaceAttachment(mesh: THREE.Mesh, space: THREE.Object3D,
  ids: [number, number, number], worldPoint: THREE.Vector3,
  position: THREE.Vector3, rotation: THREE.Quaternion): SurfaceAttachment | null {
  const points = surfaceTriangle(mesh,space,ids);
  const point = space.worldToLocal(worldPoint.clone());
  const barycentric = new THREE.Triangle(...points as [THREE.Vector3,THREE.Vector3,THREE.Vector3]).getBarycoord(point,new THREE.Vector3());
  if(!barycentric) return null;
  const frame = surfaceFrame(points,barycentric);
  if(!frame) return null;
  return {mesh,space,ids,barycentric,local:captureRigAttachment(frame,position,rotation)};
}

export function updateSurfaceAttachment(attachment: SurfaceAttachment,
  position: THREE.Vector3, rotation: THREE.Quaternion) {
  const frame = surfaceFrame(surfaceTriangle(attachment.mesh,attachment.space,attachment.ids),attachment.barycentric);
  if(!frame) return false;
  updateRigAttachment(frame,attachment.local,position,rotation);
  return true;
}
