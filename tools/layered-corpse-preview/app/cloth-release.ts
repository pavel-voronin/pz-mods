import * as THREE from 'three';
import type { ClothInput } from './cloth-physics.ts';

/** Area-based source centroid: independent of the simulation mesh refinement. */
function sourceCenter(item: ClothInput) {
  const center=new THREE.Vector3(),a=new THREE.Vector3(),b=new THREE.Vector3(),c=new THREE.Vector3();
  let area=0;
  for(const surface of item.surfaces)for(let i=0;i<surface.indices.length;i+=3) {
    a.fromArray(surface.positions,surface.indices[i]*3);
    b.fromArray(surface.positions,surface.indices[i+1]*3);
    c.fromArray(surface.positions,surface.indices[i+2]*3);
    const weight=b.clone().sub(a).cross(c.clone().sub(a)).length();
    center.addScaledVector(a.clone().add(b).add(c),weight/3);area+=weight;
  }
  return area>1e-12?center.divideScalar(area):center;
}

/** The marker aims the layer as a whole; it never attracts individual garments.
 * A small outward velocity difference expands their existing relative layout.
 * These impulses are shared by quick and precise simulation.
 */
export function clothReleaseVelocities(items: ClothInput[]) {
  const centers=items.map(sourceCenter);
  return items.map((item,index)=>{
    const peers=items.map((other,i)=>({other,i})).filter(({other,i})=>
      item.layerId===undefined?i===index:other.layerId===item.layerId);
    const center=new THREE.Vector3(),target=new THREE.Vector3();
    for(const {other,i} of peers){center.add(centers[i]);target.add(new THREE.Vector3(...other.target));}
    center.divideScalar(peers.length);target.divideScalar(peers.length);
    const flight=item.flightTime??.58;
    const velocity=target.sub(center).divideScalar(flight);
    velocity.y=Math.max(1.9,velocity.y+9.81*flight*.5);
    if(peers.length>1) {
      const spread=centers[index].clone().sub(center);spread.y=0;
      spread.multiplyScalar(.08).clampLength(0,.035).divideScalar(flight);
      velocity.add(spread);
    }
    return velocity;
  });
}
