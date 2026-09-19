import type { ClothTrack } from './cloth-physics';

type Fans = {faces:number[][];normals:Float32Array};
const fanCache=new WeakMap<Uint32Array,Fans>();
/** UV seams share light; opposite sides of a tight fold must not average to zero. */
export function clothNormals(track: Pick<ClothTrack, 'particleForVertex'>, positions: Float32Array, output: Float32Array, scratch: Float32Array) {
  let fans=fanCache.get(track.particleForVertex);
  if(!fans) {
    const faces=Array.from({length:scratch.length/3},()=>[] as number[]);
    for(let vertex=0;vertex<track.particleForVertex.length;vertex++)faces[track.particleForVertex[vertex]].push(Math.floor(vertex/3));
    fans={faces,normals:new Float32Array(positions.length/3)};
    fanCache.set(track.particleForVertex,fans);
  }
  const faceNormals=fans.normals;
  faceNormals.fill(0);
  for(let i=0;i<positions.length;i+=9) {
    const ax=positions[i+3]-positions[i],ay=positions[i+4]-positions[i+1],az=positions[i+5]-positions[i+2];
    const bx=positions[i+6]-positions[i],by=positions[i+7]-positions[i+1],bz=positions[i+8]-positions[i+2];
    const nx=ay*bz-az*by,ny=az*bx-ax*bz,nz=ax*by-ay*bx;
    const length=Math.hypot(nx,ny,nz);
    if(length>1e-12) {
      faceNormals[i/3]=nx/length;faceNormals[i/3+1]=ny/length;faceNormals[i/3+2]=nz/length;
    }
  }
  const creaseCos=-1e-6; // At most 90 degrees: averaging cannot invert a face normal.
  for(let vertex=0;vertex<track.particleForVertex.length;vertex++) {
    const own=Math.floor(vertex/3)*3;
    let nx=0,ny=0,nz=0;
    for(const face of fans.faces[track.particleForVertex[vertex]]) {
      const at=face*3;
      const dot=faceNormals[own]*faceNormals[at]+faceNormals[own+1]*faceNormals[at+1]+faceNormals[own+2]*faceNormals[at+2];
      if(dot<creaseCos)continue;
      nx+=faceNormals[at];ny+=faceNormals[at+1];nz+=faceNormals[at+2];
    }
    const length=Math.hypot(nx,ny,nz)||1;
    output[vertex*3]=nx/length;output[vertex*3+1]=ny/length;output[vertex*3+2]=nz/length;
  }
}
