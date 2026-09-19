import assert from 'node:assert/strict';
import test from 'node:test';
import {clothNormals} from '../app/cloth-normals.ts';
const track={particleForVertex:new Uint32Array([0,1,2,0,3,4])};
function normals(angle){
 const p=new Float32Array([0,0,0,1,0,0,0,1,0,0,0,0,0,Math.cos(angle),Math.sin(angle),-1,0,0]);
 const n=new Float32Array(p.length);clothNormals(track,p,n,new Float32Array(15));return n;
}
test('sub-degree fold movement cannot switch lighting abruptly at 90 degrees',()=>{
 const a=normals(Math.PI/2-.0001),b=normals(Math.PI/2+.0001);
 assert.ok(Math.hypot(...a.slice(0,3).map((v,i)=>v-b[i]))<.001);
});
test('normal changes continuously through the entire crease transition',()=>{
 let previous=normals(1);
 for(let angle=1.001;angle<1.8;angle+=.001){
  const n=normals(angle);
  assert.ok(Math.hypot(...n.slice(0,3).map((v,i)=>v-previous[i]))<.015);
  assert.ok(n[2]>.7,'Fold normals may not flip');previous=n;
 }
});
test('flat UV seams remain smooth and opposite faces do not cancel',()=>{
 const flat=normals(0),fold=normals(Math.PI);
 assert.deepEqual([...flat.slice(0,3)],[...flat.slice(9,12)]);
 assert.ok(fold[2]>.999 && fold[11]<-.999);
});
