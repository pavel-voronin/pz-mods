import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import * as THREE from 'three';
import {findBackAnchor,mountAxeOnBack,updateSurfaceAttachment} from '../app/rig-attachment.ts';
import {createRigModel,cloneRigWithMaterial,skinRigModel,PzRagdollPose} from '../app/pz-rig.ts';

for(const source of ['pz/tomb','pz']) for(const sex of ['m','f']) test(`axe blade stays on actual ${source}/${sex} back through all poses, edits and reset`,()=>{
  const model=createRigModel(JSON.parse(fs.readFileSync(new URL(`../public/${source}/rigs/${sex}/body.json`,import.meta.url),'utf8')));
  const anchor=findBackAnchor(model);
  const bindPoint=anchor.points.reduce((p,v,i)=>p.addScaledVector(v,anchor.barycentric.getComponent(i)),new THREE.Vector3());
  assert(bindPoint.z<-.03,'Attachment must be on posterior torso, not chest or waist');
  assert(bindPoint.y>.65 && bindPoint.y<.8,'Attachment must be on upper back');
  for(const file of fs.readdirSync(new URL('../public/pz/rigs/poses/',import.meta.url)).filter(f=>f.endsWith('.json'))){
    const pose=new PzRagdollPose(JSON.parse(fs.readFileSync(new URL('../public/pz/rigs/poses/'+file,import.meta.url),'utf8')));
    skinRigModel(model,pose);
    const space=new THREE.Group(),root=cloneRigWithMaterial(model,new THREE.MeshBasicMaterial());space.add(root);
    const mesh=root.children[anchor.partIndex],geometry=mesh.geometry,positions=geometry.getAttribute('position');
    const ids=anchor.ids;
    const vertices=ix=>ix.map(i=>new THREE.Vector3().fromBufferAttribute(positions,i));
    const triangle=()=>new THREE.Triangle(...vertices(ids));
    const blade=new THREE.Vector3(0,.23,-.035),q=new THREE.Quaternion(),position=new THREE.Vector3();
    const attachment=mountAxeOnBack(model,root,space,position,q);assert(attachment);
    const sign=Math.sign(new THREE.Triangle(...anchor.points).getNormal(new THREE.Vector3()).dot(anchor.back));
    const expectedTip=()=>vertices(ids).reduce((p,v,i)=>p.addScaledVector(v,anchor.barycentric.getComponent(i)),new THREE.Vector3())
      .addScaledVector(triangle().getNormal(new THREE.Vector3()),-.006*sign);
    assert(blade.clone().applyQuaternion(q).add(position).distanceTo(expectedTip())<1e-7,file+' initial mount');
    const initial=position.clone(),initialQ=q.clone();
    // Scene centering, rotation and display scale are not skinning transforms.
    space.position.set(2,-1,3);space.scale.setScalar(1.9);space.rotation.y=.7;
    for(const handle of ['head','chest','pelvis','leftHand','rightHand']){
      pose.dragHandle(handle,pose.getHandlePosition(handle).add(new THREE.Vector3(.05,-.04,.08)));
      skinRigModel(model,pose);assert(updateSurfaceAttachment(attachment,position,q));
      const tip=blade.clone().applyQuaternion(q).add(position);
      const expected=expectedTip();
      assert(tip.distanceTo(expected)<1e-7,`${file}/${handle}: blade left skin`);
      assert(Math.abs(q.length()-1)<1e-10,'Axe must remain rigid');
    }
    pose.reset();skinRigModel(model,pose);updateSurfaceAttachment(attachment,position,q);
    assert(position.distanceTo(initial)<1e-7,file+' reset position');
    assert(Math.abs(q.dot(initialQ))>1-1e-10,file+' reset rotation');
    root.children.forEach(m=>m.material.dispose());
  }
});
