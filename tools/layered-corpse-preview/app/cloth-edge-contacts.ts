import * as THREE from 'three';

export type EdgeCloth = {
  p:THREE.Vector3[]; old:THREE.Vector3[]; rest:THREE.Vector3[];
  inverseMass:number[]; edges:number[][]; neighbours:Set<number>[];
  active:boolean; sleeping:boolean; contact:boolean[];
};
const d1=new THREE.Vector3(), d2=new THREE.Vector3(), r=new THREE.Vector3();
const currentA=new THREE.Vector3(),currentB=new THREE.Vector3(),oldA=new THREE.Vector3(),oldB=new THREE.Vector3();
const normal=new THREE.Vector3(),oldNormal=new THREE.Vector3(),relative=new THREE.Vector3();
const restA=new THREE.Vector3(),restB=new THREE.Vector3();

/** Closest interior points detect contacts missed by vertex/triangle tests. */
export function closestSegments(a:THREE.Vector3,b:THREE.Vector3,c:THREE.Vector3,d:THREE.Vector3,outA:THREE.Vector3,outB:THREE.Vector3) {
  d1.subVectors(b,a);d2.subVectors(d,c);r.subVectors(a,c);
  const aa=d1.lengthSq(),ee=d2.lengthSq(),ff=d2.dot(r),cc=d1.dot(r),bb=d1.dot(d2);
  let s=0,t=0;
  if(aa<1e-16) t=THREE.MathUtils.clamp(ff/Math.max(ee,1e-16),0,1);
  else if(ee<1e-16) s=THREE.MathUtils.clamp(-cc/aa,0,1);
  else {
    const denominator=aa*ee-bb*bb;
    if(denominator>1e-20) s=THREE.MathUtils.clamp((bb*ff-cc*ee)/denominator,0,1);
    t=(bb*s+ff)/ee;
    if(t<0){t=0;s=THREE.MathUtils.clamp(-cc/aa,0,1);}
    else if(t>1){t=1;s=THREE.MathUtils.clamp((bb-cc)/aa,0,1);}
  }
  outA.copy(a).lerp(b,s);outB.copy(c).lerp(d,t);
  return [s,t] as const;
}

type Edge={cloth:EdgeCloth;a:number;b:number;id:number};
export function clothEdgeContacts(cloths:EdgeCloth[],thickness:number) {
  const edges:Edge[]=[];
  for(const cloth of cloths) if(cloth.active) for(const [a,b] of cloth.edges) edges.push({cloth,a,b,id:edges.length});
  const grid=new Map<string,Edge[]>(),seen=new Set<number>(),cell=.025;
  for(const edge of edges) {
    const {cloth,a,b}=edge;
    const p=cloth.p[a],q=cloth.p[b],op=cloth.old[a],oq=cloth.old[b];
    const minX=Math.floor((Math.min(p.x,q.x,op.x,oq.x)-thickness)/cell),maxX=Math.floor((Math.max(p.x,q.x,op.x,oq.x)+thickness)/cell);
    const minY=Math.floor((Math.min(p.y,q.y,op.y,oq.y)-thickness)/cell),maxY=Math.floor((Math.max(p.y,q.y,op.y,oq.y)+thickness)/cell);
    const minZ=Math.floor((Math.min(p.z,q.z,op.z,oq.z)-thickness)/cell),maxZ=Math.floor((Math.max(p.z,q.z,op.z,oq.z)+thickness)/cell);
    for(let x=minX;x<=maxX;x++)for(let y=minY;y<=maxY;y++)for(let z=minZ;z<=maxZ;z++) {
      const key=x+','+y+','+z,bucket=grid.get(key);
      if(!bucket){grid.set(key,[edge]);continue;}
      for(const other of bucket) {
        const pair=other.id*edges.length+edge.id;
        if(seen.has(pair))continue;seen.add(pair);
        const oc=other.cloth,c=other.a,d=other.b;
        if(cloth.sleeping && oc.sleeping)continue;
        if(cloth===oc && (a===c||a===d||b===c||b===d
          ||cloth.neighbours[a].has(c)||cloth.neighbours[a].has(d)||cloth.neighbours[b].has(c)||cloth.neighbours[b].has(d)))continue;
        const [s,t]=closestSegments(p,q,oc.p[c],oc.p[d],currentA,currentB);
        if(s<1e-4||s>1-1e-4||t<1e-4||t>1-1e-4)continue;
        const distance=currentA.distanceTo(currentB);
        if(distance>.012)continue;
        if(cloth===oc) {
          closestSegments(cloth.rest[a],cloth.rest[b],cloth.rest[c],cloth.rest[d],restA,restB);
          if(restA.distanceToSquared(restB)<(thickness*1.5)**2)continue;
        }
        normal.subVectors(q,p).cross(relative.subVectors(oc.p[d],oc.p[c])).normalize();
        oldNormal.subVectors(oq,op).cross(relative.subVectors(oc.old[d],oc.old[c])).normalize();
        oldA.copy(op).lerp(oq,s);oldB.copy(oc.old[c]).lerp(oc.old[d],t);
        const signed=relative.subVectors(currentA,currentB).dot(normal);
        const oldSigned=relative.subVectors(oldA,oldB).dot(oldNormal);
        const crossed=signed*oldSigned<0 && oldA.distanceTo(oldB)<.012 && normal.dot(oldNormal)>.5;
        if(distance>=thickness && !crossed)continue;
        if(crossed) {if(oldSigned<0)normal.negate();}
        else if(distance>1e-9) normal.subVectors(currentA,currentB).divideScalar(distance);
        else if(oldA.distanceToSquared(oldB)>1e-18)normal.subVectors(oldA,oldB).normalize();
        if(normal.lengthSq()<.5)continue;
        const wa=cloth.sleeping?0:cloth.inverseMass[a],wb=cloth.sleeping?0:cloth.inverseMass[b];
        const wc=oc.sleeping?0:oc.inverseMass[c],wd=oc.sleeping?0:oc.inverseMass[d];
        const denominator=wa*(1-s)**2+wb*s*s+wc*(1-t)**2+wd*t*t;
        if(denominator<1e-12)continue;
        const correction=(thickness-relative.subVectors(currentA,currentB).dot(normal))/denominator;
        if(correction<=0)continue;
        p.addScaledVector(normal,correction*wa*(1-s));q.addScaledVector(normal,correction*wb*s);
        oc.p[c].addScaledVector(normal,-correction*wc*(1-t));oc.p[d].addScaledVector(normal,-correction*wd*t);
        if(cloth!==oc){cloth.contact[a]=cloth.contact[b]=true;oc.contact[c]=oc.contact[d]=true;}
      }
      bucket.push(edge);
    }
  }
}
