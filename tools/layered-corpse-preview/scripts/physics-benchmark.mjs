import fs from 'node:fs';
import path from 'node:path';
import * as T from 'three';
import {FBXLoader} from 'three/examples/jsm/loaders/FBXLoader.js';
import {makeLootHull} from '../app/loot-collider.ts';
import {bakeLoot} from '../app/loot-physics.ts';
import {bakeCloth} from '../app/cloth-physics.ts';
import {createRigModel,skinRigModel,PzRagdollPose} from '../app/pz-rig.ts';
import {rigAssetPath} from '../app/pz-model-assets.ts';
import catalog from '../app/pz-pocket-loot.json' with {type:'json'};
import {gameRoot} from './import-pocket-loot.mjs';
import {dropDiskSample} from '../app/scene-layout.ts';
class Textures extends T.Loader{load(){return new T.Texture();}}
const manager=new T.LoadingManager();manager.addHandler(/.*/,new Textures(manager));
const loot=['Base.Receipt','Base.IDcard','Base.Wallet_Male','Base.Lipstick','Base.IDcard','Base.Receipt'].map((id,index)=>{
 const d=catalog.items[id],b=fs.readFileSync(path.join(gameRoot,d.modelFile));
 const model=new FBXLoader(manager).parse(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),'');model.updateMatrixWorld(true);
 const bounds=new T.Box3().setFromObject(model),center=bounds.getCenter(new T.Vector3()),points=[];
 model.traverse(mesh=>{if(!mesh.isMesh)return;const p=mesh.geometry.getAttribute('position');for(let i=0;i<p.count;i++)points.push(new T.Vector3().fromBufferAttribute(p,i).applyMatrix4(mesh.matrixWorld).sub(center).multiplyScalar(d.scale));});
 return {center:[0,.35,0],halfExtents:bounds.getSize(new T.Vector3()).multiplyScalar(d.scale*.5).toArray(),hull:makeLootHull(points),quaternion:[0,0,0,1],target:[.5,0,.3],releaseTime:.2+Math.floor(index/2)*2,mass:d.mass,index};
});
if(process.argv.includes('--landing'))loot.forEach(item=>{item.landingArea={center:[.5,0,.3],radius:.1};const offset=dropDiskSample(item.index,.045);item.target=[.5+offset.x,0,.3+offset.z];});
let start=performance.now();const lootBake=bakeLoot(loot,0,10);console.log('loot6 duration10:',Math.round(performance.now()-start),'ms','landing error',lootBake.landingError);
const read=p=>JSON.parse(fs.readFileSync(new URL(p,import.meta.url)));
const pose=new PzRagdollPose(read('../public/pz/rigs/poses/front.json'));
const items=['trousers','jumper'].map((name,index)=>{
 const rig=createRigModel(read('../public'+rigAssetPath(name,'m','tomb')));skinRigModel(rig,pose);
 return {surfaces:rig.parts.map(({geometry:g})=>({positions:g.getAttribute('position').array,uvs:g.getAttribute('uv').array,indices:g.index?.array??Uint32Array.from({length:g.getAttribute('position').count},(_,i)=>i)})),releaseTime:.3,target:[-.5,-.05,-.5],seed:index};
});
for(const quality of ['quick','precise']){const duration=Number(process.argv[2]??3);start=performance.now();bakeCloth({items,floor:-.05,duration,capsules:[]},undefined,quality);console.log(quality+' cloth2 duration'+duration+':',Math.round(performance.now()-start),'ms');}
