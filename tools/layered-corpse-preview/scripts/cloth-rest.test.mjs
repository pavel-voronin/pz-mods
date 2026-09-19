import {test} from 'node:test';
import assert from 'node:assert/strict';
import {finalizeClothRest} from './finalize-cloth-rest.ts';
import {decodeBlenderCache} from '../app/blender-cache.ts';
function fixture({speed=.002,lift=0,lateImpact=false,release=0}={}){
 const frameCount=181,source={sceneKey:'test-rest',fps:60,duration:3,floor:0,items:[{releaseTime:release},{releaseTime:release}]};
 const tracks=[0,1].map(()=>({positions:[0,.002+lift,0],uvs:[0,0],indices:[0,0,0],particleForVertex:[0],particleCount:1,releaseTime:release}));
 const header=Buffer.from(JSON.stringify({sceneKey:source.sceneKey,fps:60,frameCount,tracks,warnings:[]}));
 const prefix=Buffer.alloc(12+Math.ceil(header.length/4)*4);prefix.write('PZCLOTH1');prefix.writeUInt32LE(header.length,8);header.copy(prefix,12);
 const arrays=tracks.map((_,i)=>Float32Array.from({length:frameCount*3},(_,k)=>{
  const f=Math.floor(k/3),j=k%3;if(j===1)return .002+lift;
  if(j===2)return 0;return f/60*speed*(i+1)+(lateImpact&&f>120?(f-120)*.003:0);
 }));
 return {source,raw:Buffer.concat([prefix,...arrays.map(a=>Buffer.from(a.buffer))])};
}
test('whole pile sleeps together; every earlier coordinate is bit-identical',()=>{
 const {raw,source}=fixture(),r=finalizeClothRest(raw,source);assert.notEqual(r.rest.frame,null);
 const decode=b=>decodeBlenderCache(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),source.sceneKey,source).bake;
 const before=decode(raw),after=decode(r.bytes),f=r.rest.frame;
 for(let i=0;i<2;i++){
  const a=before.tracks[i].frames,b=after.tracks[i].frames;
  assert.deepEqual(b.slice(0,(f+1)*3),a.slice(0,(f+1)*3));
  for(let k=f+1;k<181;k++)assert.deepEqual(b.slice(k*3,k*3+3),a.slice(f*3,f*3+3));
 }
 assert.deepEqual(finalizeClothRest(r.bytes,source).bytes,r.bytes);
});
test('does not sleep a moving pile',()=>assert.equal(finalizeClothRest(...args({speed:.1})).rest.frame,null));
test('does not sleep suspended clothing',()=>assert.equal(finalizeClothRest(...args({lift:1})).rest.frame,null));
test('future impact is not discarded',()=>assert.equal(finalizeClothRest(...args({lateImpact:true})).rest.frame,null));
test('never sleeps before last garment release',()=>assert.equal(finalizeClothRest(...args({release:2.7})).rest.frame,null));
function args(options){const {raw,source}=fixture(options);return [raw,source];}
