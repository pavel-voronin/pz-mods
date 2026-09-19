import * as THREE from 'three';
import { ConvexGeometry } from 'three/examples/jsm/geometries/ConvexGeometry.js';
export type LootHull = {vertices:[number,number,number][];faces:number[][]};
export function makeLootHull(points:THREE.Vector3[]):LootHull|undefined {
  const size=new THREE.Box3().setFromPoints(points).getSize(new THREE.Vector3());
  if(points.length<4 || Math.min(size.x,size.y,size.z)<1e-6)return;
  const geometry=new ConvexGeometry(points),position=geometry.getAttribute('position');
  const vertices:LootHull['vertices']=[],faces:number[][]=[],ids=new Map<string,number>();
  for(let i=0;i<position.count;i+=3){
    const face:number[]=[];
    for(let j=0;j<3;j++) {
      const p:[number,number,number]=[position.getX(i+j),position.getY(i+j),position.getZ(i+j)];
      const key=p.map(n=>Math.round(n*1e8)).join(',');
      let id=ids.get(key);if(id===undefined){id=vertices.length;vertices.push(p);ids.set(key,id);}face.push(id);
    }
    if(new Set(face).size===3)faces.push(face);
  }
  geometry.dispose();
  // Cannon clips against whole convex faces. Treating the two triangles of a
  // flat card as separate faces makes its contact footprint depend on a hidden
  // diagonal and float noise, producing rocking/sliding on another flat card.
  const planes:{normal:THREE.Vector3;distance:number;ids:Set<number>;faces:number[][]}[]=[];
  for(const face of faces){
    const a=new THREE.Vector3(...vertices[face[0]]),b=new THREE.Vector3(...vertices[face[1]]),c=new THREE.Vector3(...vertices[face[2]]);
    const normal=b.sub(a).cross(c.sub(a)).normalize(),distance=normal.dot(a);
    let plane=planes.find(p=>p.normal.dot(normal)>1-1e-8&&Math.abs(p.distance-distance)<1e-7);
    if(!plane){plane={normal,distance,ids:new Set(),faces:[]};planes.push(plane);}
    face.forEach(id=>plane.ids.add(id));plane.faces.push(face);
  }
  const polygons=planes.map(plane=>{
    const edges=new Map<string,[number,number]>();
    for(const face of plane.faces)for(let i=0;i<3;i++){
      const a=face[i],b=face[(i+1)%3],key=[Math.min(a,b),Math.max(a,b)].join(',');
      if(edges.has(key))edges.delete(key);else edges.set(key,[a,b]);
    }
    const boundary=[...edges.values()],polygon=[boundary[0][0]];
    let next=boundary[0][1];
    while(next!==polygon[0]&&polygon.length<=boundary.length){
      polygon.push(next);const edge=boundary.find(e=>e[0]===next);
      if(!edge)break;next=edge[1];
    }
    return next===polygon[0]&&polygon.length===boundary.length?[polygon]:plane.faces;
  }).flat();
  return vertices.length>=4?{vertices,faces:polygons}:undefined;
}
export function boxVertices(half:readonly number[]):LootHull['vertices'] {
  return [-1,1].flatMap(x=>[-1,1].flatMap(y=>[-1,1].map(z=>[x*half[0],y*half[1],z*half[2]] as [number,number,number])));
}
export function stableLootSupport(points:readonly {x:number;z:number}[],tolerance=.0005) {
  const p=[...points].sort((a,b)=>a.x-b.x||a.z-b.z);
  const cross=(a:typeof p[number],b:typeof p[number],c:typeof p[number])=>(b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x);
  const chain=(source:typeof p)=>{const out:typeof p=[];for(const v of source){while(out.length>1&&cross(out[out.length-2],out[out.length-1],v)<=0)out.pop();out.push(v);}return out;};
  if(!p.length)return false;
  const a=chain(p),b=chain([...p].reverse());const hull=[...a.slice(0,-1),...b.slice(0,-1)];
  if(hull.length<2)return Math.hypot(p[0].x,p[0].z)<=tolerance;
  if(hull.length===2){const [a,b]=hull,dx=b.x-a.x,dz=b.z-a.z,t=Math.max(0,Math.min(1,-(a.x*dx+a.z*dz)/(dx*dx+dz*dz||1)));return Math.hypot(a.x+t*dx,a.z+t*dz)<=tolerance;}
  return hull.every((a,i)=>{const b=hull[(i+1)%hull.length];return cross(a,b,{x:0,z:0})>=-tolerance*Math.hypot(b.x-a.x,b.z-a.z);});
}
/** Exact support of the convex collider, also used between cached GIF frames. */
export function lootBottom(vertices:readonly (readonly number[])[],q:{x:number;y:number;z:number;w:number}) {
  const ax=2*(q.x*q.y+q.w*q.z),ay=1-2*(q.x*q.x+q.z*q.z),az=2*(q.y*q.z-q.w*q.x);
  let min=Infinity;for(const p of vertices)min=Math.min(min,ax*p[0]+ay*p[1]+az*p[2]);return min;
}
