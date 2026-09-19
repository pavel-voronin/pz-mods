import * as THREE from 'three';
import {decodeBlenderCache} from '../app/blender-cache.ts';
import {sampleCloth} from '../app/cloth-physics.ts';
import {clothNormals} from '../app/cloth-normals.ts';
const source=await (await fetch('/cloth-rest-review/source.json')).json();
const views=[];let running=true,tail=true,t=4.5,previous=performance.now();
for(const name of ['before','after']){
 const bytes=await (await fetch('/cloth-rest-review/'+name+'.pzcloth')).arrayBuffer();
 const {bake}=decodeBlenderCache(bytes,source.sceneKey,source);
 const scene=new THREE.Scene();scene.background=new THREE.Color('#55594e');
 const camera=new THREE.OrthographicCamera(-.48,.48,.48,-.48,.01,20);
 camera.position.set(.5,1.2,.6);camera.lookAt(-.4,0,-.4);
 const renderer=new THREE.WebGLRenderer({antialias:true});renderer.setPixelRatio(devicePixelRatio);renderer.setSize((innerWidth-24)/2,(innerWidth-24)/2);document.getElementById(name).append(renderer.domElement);
 scene.add(new THREE.HemisphereLight(0xffffff,0x555555,1.2));const light=new THREE.DirectionalLight(0xffffff,1.2);light.position.set(2,4,1);scene.add(light);
 const bounds=new THREE.Box3();for(const track of bake.tracks){const offset=(bake.frameCount-1)*track.particleCount*3;for(let i=0;i<track.particleCount;i++)bounds.expandByPoint(new THREE.Vector3(...track.frames.slice(offset+i*3,offset+i*3+3)));}
 const target=bounds.getCenter(new THREE.Vector3());camera.position.copy(target).add(new THREE.Vector3(.9,1.2,1));camera.lookAt(target);
 const floor=new THREE.Mesh(new THREE.PlaneGeometry(6,6),new THREE.MeshStandardMaterial({color:0x8a897b,roughness:1}));floor.rotation.x=-Math.PI/2;floor.position.y=source.floor-.001;scene.add(floor);
 const meshes=bake.tracks.map((track,i)=>{
  const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.BufferAttribute(track.positions.slice(),3));g.setAttribute('uv',new THREE.BufferAttribute(track.uvs,2));g.setIndex(new THREE.BufferAttribute(track.indices,1));g.computeVertexNormals();
  const texture=new THREE.TextureLoader().load(source.garments[i].texture);texture.colorSpace=THREE.SRGBColorSpace;
  const mesh=new THREE.Mesh(g,new THREE.MeshStandardMaterial({map:texture,roughness:1,side:THREE.DoubleSide}));mesh.frustumCulled=false;scene.add(mesh);return {mesh,scratch:new Float32Array(track.particleCount*3)};
 });views.push({bake,scene,camera,renderer,meshes});
}
document.getElementById('play').onclick=()=>{running=!running;document.getElementById('play').textContent=running?'Пауза':'Играть';};
document.getElementById('full').onclick=()=>{tail=!tail;t=tail?4.5:0;document.getElementById('full').textContent=tail?'Вся секвенция':'Только конец';};
document.getElementById('time').oninput=e=>{t=Number(e.target.value);running=false;document.getElementById('play').textContent='Играть';};
function draw(now){if(running){t+=(now-previous)/1000;if(t>source.duration)t=tail?4.5:0;}previous=now;
 for(const v of views){v.meshes.forEach(({mesh,scratch},i)=>{const p=mesh.geometry.attributes.position,n=mesh.geometry.attributes.normal;sampleCloth(v.bake.tracks[i],v.bake,t,p.array);clothNormals(v.bake.tracks[i],p.array,n.array,scratch);p.needsUpdate=n.needsUpdate=true;});v.renderer.render(v.scene,v.camera);}
 document.getElementById('time').value=t;document.getElementById('status').textContent=t.toFixed(2)+' с';requestAnimationFrame(draw);
}requestAnimationFrame(draw);
