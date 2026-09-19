import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';
import { clothHinge, makeClothBend, solveClothBends } from '../app/cloth-bending.ts';
import { bakeCloth } from '../app/cloth-physics.ts';

const patch = (angle, size=.025) => [
  new THREE.Vector3(0,0,0),new THREE.Vector3(size,0,0),
  new THREE.Vector3(0,size,0),new THREE.Vector3(0,-size*Math.cos(angle),-size*Math.sin(angle)),
];
const readAngle = p => clothHinge(...p);
const derivatives = () => Array.from({length:4},()=>new THREE.Vector3());
const mass = [20000,20000,20000,20000],dt=1/480;
const wrap = n=>Math.atan2(Math.sin(n),Math.cos(n));

test('signed hinge gradients match finite differences, including a flat cloth patch',()=>{
  for(const angle of [0,.4,-.8,2.8,-2.8]) {
    const p=patch(angle),g=derivatives();
    // Non-isosceles hinges exercise the derivatives along both edge endpoints.
    p[2].x=.006;p[3].x=.012;
    clothHinge(...p,g);
    for(let i=0;i<4;i++)for(const axis of ['x','y','z']){
      const before=p[i][axis],eps=1e-7;
      p[i][axis]=before+eps;const high=readAngle(p);
      p[i][axis]=before-eps;const low=readAngle(p);p[i][axis]=before;
      const finite=wrap(high-low)/(2*eps);
      assert.ok(Math.abs(finite-g[i][axis])<1e-5,JSON.stringify({angle,i,axis,finite,gradient:g[i][axis]}));
    }
  }
});

test('flattened and gently folded cloth never restores its original body curvature',()=>{
  for(const original of [-2,-.4,.4,2])for(const angle of [-.8,0,.8]){
    const bend=makeClothBend(patch(original),0,1,2,3),p=patch(angle),before=p.map(v=>v.toArray());
    for(let iteration=0;iteration<32;iteration++)solveClothBends(p,mass,[bend],dt);
    assert.deepEqual(p.map(v=>v.toArray()),before);
  }
});

test('only sharp folds have weak symmetric resistance in both quality timesteps',()=>{
 for(const step of [1/60,1/480]){
  const correction=(angle)=>{
    const bend=makeClothBend(patch(.4),0,1,2,3),p=patch(angle);
    solveClothBends(p,mass,[bend],step);
    assert.ok(Math.abs(readAngle(p))<Math.abs(angle));
    return Math.abs(wrap(readAngle(p)-angle));
  };
  assert.ok(Math.abs(correction(2)-correction(-2))<1e-10);
  assert.ok(correction(2)<.15,'excessive fold stiffness');
 }
});

test('bending is local and conserves translation/rotation, including unequal vertex masses',()=>{
  const p=patch(-2),rest=patch(.4),weights=[10000,20000,30000,40000];
  const before=p.map(p=>p.clone()),bend=makeClothBend(rest,0,1,2,3);
  const q=new THREE.Quaternion().setFromEuler(new THREE.Euler(.5,-.7,1.2)),t=new THREE.Vector3(2,4,-3);
  const transformed=p.map(p=>p.clone().applyQuaternion(q).add(t));
  const rotatedBend=makeClothBend(rest.map(p=>p.clone().applyQuaternion(q).add(t)),0,1,2,3);
  solveClothBends(p,weights,[bend],dt);solveClothBends(transformed,weights,[rotatedBend],dt);
  const total=new THREE.Vector3(),torque=new THREE.Vector3();
  for(let i=0;i<4;i++){
    assert.ok(transformed[i].distanceTo(p[i].clone().applyQuaternion(q).add(t))<1e-12);
    const impulse=p[i].clone().sub(before[i]).divideScalar(weights[i]);
    total.add(impulse);torque.add(before[i].clone().cross(impulse));
  }
  assert.ok(total.length()<1e-15);assert.ok(torque.length()<1e-15);
  assert.equal(clothHinge(...Array.from({length:4},()=>new THREE.Vector3())),null);
});

test('curved airborne cloth retains dimensions and does not gain lift from bending',()=>{
  const p=patch(.5),surface={
    positions:Float32Array.from(p.flatMap(p=>p.clone().add(new THREE.Vector3(0,1,0)).toArray())),
    uvs:new Float32Array(8),indices:new Uint32Array([0,1,2,1,0,3]),
  };
  const original=surface.positions.slice();
  const bake=bakeCloth({floor:-10,duration:.2,capsules:[],items:[{surfaces:[surface],releaseTime:.01,target:[0,-10,0],seed:0}]});
  assert.deepEqual(surface.positions,original);
  const track=bake.tracks[0],at=(frame,id)=>new THREE.Vector3().fromArray(track.frames,(frame*track.particleCount+id)*3);
  const meanY=frame=>Array.from({length:track.particleCount},(_,id)=>at(frame,id).y).reduce((a,b)=>a+b)/track.particleCount;
  const acceleration=(meanY(8)-2*meanY(7)+meanY(6))*bake.fps*bake.fps;
  assert.ok(acceleration < -9.5 && acceleration > -10.1,'bending caused buoyancy: '+acceleration);
  for(let i=0;i<track.indices.length;i+=3)for(let j=0;j<3;j++){
    const a=track.particleForVertex[i+j],b=track.particleForVertex[i+(j+1)%3];
    assert.ok(Math.abs(at(bake.frameCount-1,a).distanceTo(at(bake.frameCount-1,b))/at(0,a).distanceTo(at(0,b))-1)<.01);
  }
});

for(const quality of ['quick','precise'])test(quality+': unsupported sleeve collapses under gravity without preserving the body silhouette',()=>{
  const positions=[],indices=[],sides=12,rows=4;
  for(let row=0;row<rows;row++)for(let i=0;i<sides;i++){
    const angle=2*Math.PI*i/sides;
    positions.push(.04*Math.cos(angle),.25+.04*Math.sin(angle),.12*row/(rows-1)-.06);
  }
  for(let row=0;row<rows-1;row++)for(let i=0;i<sides;i++){
    const a=row*sides+i,b=row*sides+(i+1)%sides,c=b+sides,d=a+sides;
    indices.push(a,b,c,a,c,d);
  }
  const surface={positions:new Float32Array(positions),uvs:new Float32Array(positions.length/3*2),indices:new Uint32Array(indices)};
  const bake=bakeCloth({floor:0,duration:2,capsules:[],items:[{surfaces:[surface],releaseTime:0,target:[0,0,0],seed:0}]},undefined,quality);
  const track=bake.tracks[0],end=track.frames.subarray(-track.particleCount*3);
  const ys=Array.from({length:track.particleCount},(_,i)=>end[i*3+1]),loft=Math.max(...ys)-Math.min(...ys);
  console.log('Open sleeve final loft:',loft);
  assert.ok(loft<.045,'sleeve did not collapse enough under its own weight');
  assert.ok(Math.min(...ys)>=.00074,'sleeve passes through the floor');
});
