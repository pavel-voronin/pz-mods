import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';
import { bakeCloth, clothContacts, CLOTH_MAX_EDGE } from '../app/cloth-physics.ts';
import { clothNormals } from '../app/cloth-normals.ts';
import { closestSegments, clothEdgeContacts } from '../app/cloth-edge-contacts.ts';
import { garmentReleaseFan } from '../app/scene-layout.ts';

test('refinement preserves a watertight surface across differently shaped source faces',()=>{
  const surface={positions:new Float32Array([0,0,0,.17,0,0,.07,.12,0,.02,.03,.09]),
    uvs:new Float32Array(8),indices:new Uint32Array([0,2,1,0,1,3,1,2,3,2,0,3])};
  const track=bakeCloth({floor:-1,duration:0,capsules:[],items:[{surfaces:[surface],releaseTime:1,target:[0,0,0],seed:0}]}).tracks[0];
  const edges=new Map();
  for(let i=0;i<track.particleForVertex.length;i+=3)for(let j=0;j<3;j++){
    const a=track.particleForVertex[i+j],b=track.particleForVertex[i+(j+1)%3];
    const key=a<b?a+':'+b:b+':'+a;edges.set(key,(edges.get(key)??0)+1);
    const p=new THREE.Vector3().fromArray(track.positions,(i+j)*3),q=new THREE.Vector3().fromArray(track.positions,(i+(j+1)%3)*3);
    assert.ok(p.distanceTo(q)<=CLOTH_MAX_EDGE+1e-7);
  }
  assert.equal([...edges.values()].filter(count=>count!==2).length,0,'refinement opened cracks / T-junctions');
});

test('edge interiors collide even when all four endpoints miss one another',()=>{
  const v=(x,y,z)=>new THREE.Vector3(x,y,z);
  const cloth=(p,old)=>({p,old,rest:old.map(p=>p.clone()),inverseMass:[1,1],edges:[[0,1]],neighbours:[new Set(),new Set()],active:true,sleeping:false,contact:[false,false]});
  const a=cloth([v(-.01,-.001,0),v(.01,-.001,0)],[v(-.01,.002,0),v(.01,.002,0)]);
  const b=cloth([v(0,0,-.01),v(0,0,.01)],[v(0,0,-.01),v(0,0,.01)]);
  const before=a.p.concat(b.p).reduce((s,p)=>s.add(p),v(0,0,0));
  clothEdgeContacts([a,b],.0015);
  const pa=v(0,0,0),pb=v(0,0,0);
  assert.deepEqual(closestSegments(...a.p,...b.p,pa,pb),[.5,.5]);
  assert.ok(pa.y-pb.y>=.0015-1e-10,'crossing must return to previous side');
  assert.ok(before.distanceTo(a.p.concat(b.p).reduce((s,p)=>s.add(p),v(0,0,0)))<1e-12,'internal contact must conserve centre of mass');
});

test('a vertex crossing an entire collision thickness is not discarded by the broad phase',()=>{
  const v=(x,y,z)=>new THREE.Vector3(x,y,z);
  const cloth=(p,old,triangles)=>({p,old,rest:old.map(p=>p.clone()),triangles,inverseMass:p.map(()=>1),
    neighbours:p.map(()=>new Set()),active:true,sleeping:false,contact:p.map(()=>false)});
  const moving=cloth([v(0,-.004,0)],[v(0,.004,0)],[]);
  const plane=cloth([v(-.02,0,-.02),v(.02,0,-.02),v(0,0,.02)],[v(-.02,0,-.02),v(.02,0,-.02),v(0,0,.02)],[[0,1,2]]);
  plane.sleeping=true;
  clothContacts([moving,plane]);
  assert.ok(moving.p[0].y>=.0015-1e-10,'vertex tunnelled through static cloth face');
});

test('opposite fold normals do not cancel, including after reverse seeking through a degenerate frame',()=>{
  const positions=new Float32Array([0,0,0,1,0,0,0,1,0, 0,0,0,0,1,0,1,0,0]);
  const track={particleForVertex:new Uint32Array([0,1,2,0,2,1])};
  const normals=new Float32Array(18),scratch=new Float32Array(9);
  clothNormals(track,positions,normals,scratch);const expected=normals.slice();
  assert.deepEqual([...normals.slice(0,3)],[0,0,1]);
  assert.deepEqual([...normals.slice(9,12)],[0,0,-1]);
  clothNormals(track,new Float32Array(18),normals,scratch);
  clothNormals(track,positions,normals,scratch);assert.deepEqual(normals,expected);
});

test('same-layer pieces receive independent modest release impulses around the shared pile',()=>{
  const a=garmentReleaseFan(0,2,1),b=garmentReleaseFan(1,2,1);
  assert.ok(Math.hypot(a.x-b.x,a.z-b.z)>.02 && Math.hypot(a.x-b.x,a.z-b.z)<.08);
  assert.ok(Math.hypot(a.x+b.x,a.z+b.z)<1e-12);
  assert.equal(a.flight,b.flight);assert.notEqual(a.spin,b.spin);assert.equal(a.delay,0);assert.equal(b.delay,0);
  assert.deepEqual(a,garmentReleaseFan(0,2,1));
  const single=garmentReleaseFan(0,1,1);assert.equal(Math.hypot(single.x,single.z),0);assert.equal(single.delay,0);
});
