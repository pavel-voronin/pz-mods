import * as THREE from 'three';
import type { HandleKey } from './pz-rig';
import { closestSegments } from './cloth-edge-contacts.ts';

type Positions = Map<HandleKey, THREE.Vector3>;
type Link = {a:HandleKey;b:HandleKey;min:number;max:number};
type Capsule = {a:HandleKey;b:HandleKey;r:number};
const core:HandleKey[]=['pelvis','waist','chest','neck','leftHip','rightHip','leftShoulder','rightShoulder'];
const chains:HandleKey[][]=[
  ['leftShoulder','leftElbow','leftHand'],['rightShoulder','rightElbow','rightHand'],
  ['leftHip','leftKnee','leftFoot'],['rightHip','rightKnee','rightFoot'],
];

/** Shared positional constraints for gravity and interactive whole-body grabs.
 * Only explicit locks and the grabbed point are anchored, never the root.
 */
export class RagdollConstraints {
  readonly links:Link[]=[];
  readonly contacts:Array<{a:Capsule;b:Capsule;gap:number;normal:THREE.Vector3}>=[];
  constructor(rest:Positions,parents:Partial<Record<HandleKey,HandleKey>>) {
    const add=(a:HandleKey,b:HandleKey,slack=0)=>{
      const length=rest.get(a)!.distanceTo(rest.get(b)!);
      this.links.push({a,b,min:length*(1-slack),max:length*(1+slack)});
    };
    for(const [child,parent] of Object.entries(parents))add(parent,child as HandleKey);
    // Cross-braces keep the torso/shoulder/pelvic frames from collapsing.
    for(const cluster of [
      ['pelvis','waist','leftHip','rightHip'],
      ['chest','neck','leftShoulder','rightShoulder'],
    ] as HandleKey[][])for(let a=0;a<cluster.length;a++)for(let b=a+1;b<cluster.length;b++)add(cluster[a],cluster[b]);
    for(const shoulder of ['leftShoulder','rightShoulder'] as const)add('waist',shoulder,.08);
    for(const hip of ['leftHip','rightHip'] as const)add('chest',hip,.08);
    for(const [a,b,c] of chains){
      const l1=rest.get(a)!.distanceTo(rest.get(b)!),l2=rest.get(b)!.distanceTo(rest.get(c)!);
      // Bound complete folding while admitting all source poses.
      const min=Math.min(rest.get(a)!.distanceTo(rest.get(c)!),Math.sqrt(l1*l1+l2*l2-2*l1*l2*Math.cos(.3)));
      this.links.push({a,b:c,min,max:l1+l2});
    }
    const capsules:Capsule[]=[
      {a:'pelvis',b:'waist',r:.043},{a:'waist',b:'chest',r:.048},{a:'neck',b:'head',r:.038},
      ...chains.flatMap(([a,b,c])=>[{a,b,r:a.includes('Hip')?.025:.018},{a:b,b:c,r:a.includes('Hip')?.021:.014}]),
    ];
    const p=new THREE.Vector3(),q=new THREE.Vector3();
    for(let i=0;i<capsules.length;i++)for(let j=i+1;j<capsules.length;j++){
      const a=capsules[i],b=capsules[j];
      if([a.a,a.b].some(id=>id===b.a||id===b.b))continue;
      if([a.a,a.b,b.a,b.b].every(id=>core.includes(id)))continue;
      closestSegments(rest.get(a.a)!,rest.get(a.b)!,rest.get(b.a)!,rest.get(b.b)!,p,q);
      const separation=p.distanceTo(q);
      // Respect touching source seams/poses; do not explode an imported rig.
      const gap=Math.min(a.r+b.r,separation*.98);
      if(gap<1e-5)continue;
      this.contacts.push({a,b,gap,normal:p.clone().sub(q).normalize()});
    }
  }

  solve(p:Positions,locked:ReadonlySet<HandleKey>,clamp:(key:HandleKey,p:THREE.Vector3)=>THREE.Vector3,
    anchor?:{key:HandleKey;target:THREE.Vector3},iterations=160) {
    const fixed=new Map<HandleKey,THREE.Vector3>();
    for(const key of locked)fixed.set(key,p.get(key)!.clone());
    if(anchor)fixed.set(anchor.key,clamp(anchor.key,anchor.target));
    const weight=(key:HandleKey)=>fixed.has(key)?0:1;
    const delta=new THREE.Vector3(),aPoint=new THREE.Vector3(),bPoint=new THREE.Vector3();
    for(let iteration=0;iteration<iterations;iteration++){
      for(const [key,point] of fixed)p.get(key)!.copy(point);
      for(let n=0;n<this.links.length;n++){
        const link=this.links[iteration%2?n:this.links.length-1-n];
        const a=p.get(link.a)!,b=p.get(link.b)!,wa=weight(link.a),wb=weight(link.b);
        delta.subVectors(b,a);const length=delta.length();
        if(length<1e-10||wa+wb===0)continue;
        const wanted=THREE.MathUtils.clamp(length,link.min,link.max);
        delta.multiplyScalar((length-wanted)/(length*(wa+wb)));
        a.addScaledVector(delta,wa);b.addScaledVector(delta,-wb);
      }
      for(const contact of this.contacts){
        const {a,b,gap}=contact;
        const [s,t]=closestSegments(p.get(a.a)!,p.get(a.b)!,p.get(b.a)!,p.get(b.b)!,aPoint,bPoint);
        delta.subVectors(aPoint,bPoint);const distance=delta.length();
        if(distance>=gap)continue;
        if(distance>1e-9)delta.divideScalar(distance);else delta.copy(contact.normal);
        const ids=[a.a,a.b,b.a,b.b],coeff=[1-s,s,-(1-t),-t];
        const denom=ids.reduce((sum,id,k)=>sum+weight(id)*coeff[k]*coeff[k],0);
        if(denom<1e-10)continue;
        ids.forEach((id,k)=>p.get(id)!.addScaledVector(delta,(gap-distance)*weight(id)*coeff[k]/denom));
      }
      for(const [key,point] of p)if(!fixed.has(key))point.copy(clamp(key,point));
    }
    for(const [key,point] of fixed)p.get(key)!.copy(point);
  }
}
