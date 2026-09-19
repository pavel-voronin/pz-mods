import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import * as THREE from 'three';
import { PzRagdollPose,ragdollHandles,ragdollParents } from '../app/pz-rig.ts';
import { captureRigAttachment,updateRigAttachment } from '../app/rig-attachment.ts';
import { closestSegments } from '../app/cloth-edge-contacts.ts';
const data=name=>JSON.parse(fs.readFileSync(new URL('../public/pz/rigs/poses/'+name,import.meta.url)));
const poses=fs.readdirSync(new URL('../public/pz/rigs/poses/',import.meta.url)).filter(name=>name.endsWith('.json'));
const checkLengths=pose=>{
  for(const [child,parent] of Object.entries(ragdollParents)){
    const expected=pose.getRestLength(parent,child),actual=pose.getHandlePosition(parent).distanceTo(pose.getHandlePosition(child));
    assert.ok(Math.abs(actual-expected)<.002,child+' stretched '+(actual-expected));
  }
};
test('hands, elbows, feet and head pull the free torso in all source poses',()=>{
  for(const name of poses)for(const handle of ['leftHand','rightFoot','leftElbow','head']){
    const pose=new PzRagdollPose(data(name)),before=pose.getHandlePosition('pelvis');
    const target=pose.getHandlePosition(handle).add(new THREE.Vector3(.15,.7,-.1));
    pose.dragHandle(handle,target);
    assert.ok(pose.getHandlePosition(handle).distanceTo(target)<1e-8);
    assert.ok(pose.getHandlePosition('pelvis').distanceTo(before)>.01,name+' '+handle+' fixed pelvis');
    checkLengths(pose);
  }
});
test('explicit pins remain fixed; reset restores byte-identical original pose',()=>{
  const pose=new PzRagdollPose(data('front.json')),initial=pose.captureState();
  const pinned=pose.getHandlePosition('rightFoot');
  pose.dragHandle('leftHand',pose.getHandlePosition('leftHand').add(new THREE.Vector3(.1,.15,0)),new Set(['rightFoot']));
  assert.ok(pose.getHandlePosition('rightFoot').distanceTo(pinned)<1e-10);
  checkLengths(pose);pose.reset();assert.deepEqual(pose.captureState(),initial);
});
test('a held hand stays under the cursor while the unpinned body falls and follows it',()=>{
  const pose=new PzRagdollPose(data('front.json'));
  const target=pose.getHandlePosition('leftHand').add(new THREE.Vector3(0,.7,0));
  pose.dragHandle('leftHand',target);
  const p=new Map(ragdollHandles.map(key=>[key,pose.getHandlePosition(key)]));
  const previous=new Map([...p].map(([key,p])=>[key,p.clone()]));
  const before=p.get('pelvis').clone();
  for(let frame=0;frame<45;frame++){
    for(const [key,point] of p){
      if(key==='leftHand')continue;
      const old=point.clone(),velocity=point.clone().sub(previous.get(key)).multiplyScalar(.985);
      point.add(velocity);point.y-=9.81/3600;previous.get(key).copy(old);
    }
    pose.projectHandles(p,new Set(['leftHand']),-.3);
    assert.ok(p.get('leftHand').distanceTo(target)<1e-9);
  }
  assert.ok(p.get('pelvis').y<before.y-.01,'body remains frozen while a hand is held');
  pose.setHandlePositions(p);checkLengths(pose);
});
test('an unreachable cursor target cannot stretch the skeleton against an explicit pin',()=>{
  const pose=new PzRagdollPose(data('front.json')),pin=pose.getHandlePosition('rightFoot');
  const target=pose.getHandlePosition('leftHand').add(new THREE.Vector3(0,2,0));
  pose.dragHandle('leftHand',target,new Set(['rightFoot']));
  assert.ok(pose.getHandlePosition('rightFoot').distanceTo(pin)<1e-10);
  assert.ok(pose.getHandlePosition('leftHand').distanceTo(target)>.1);
  checkLengths(pose);
});
test('the same projection used by gravity enforces floor and non-adjacent body contacts',()=>{
  const pose=new PzRagdollPose(data('front.json')),floor=-.1;
  const p=new Map(ragdollHandles.map(key=>[key,pose.getHandlePosition(key).add(new THREE.Vector3(0,-.3,0))]));
  for(let i=0;i<8;i++)pose.projectHandles(p,new Set(),floor);
  pose.setHandlePositions(p);checkLengths(pose);
  for(const [key,position] of p)assert.ok(position.y>=pose.clampHandleTarget(key,position,floor).y-1e-9);
  const a=new THREE.Vector3(),b=new THREE.Vector3();
  for(const contact of pose.constraints.contacts){
    closestSegments(p.get(contact.a.a),p.get(contact.a.b),p.get(contact.b.a),p.get(contact.b.b),a,b);
    assert.ok(a.distanceTo(b)>=contact.gap-.002,'body capsules overlap');
  }
});
test('axe preserves its exact bone-local attachment under translation, articulation and reset',()=>{
  const pose=new PzRagdollPose(data('front.json')),bone=()=>pose.boneGlobals().get('Bip01_Spine1');
  const position=new THREE.Vector3(.02,.08,-.06),q=new THREE.Quaternion().setFromEuler(new THREE.Euler(.2,1.1,-.4));
  const original=new THREE.Matrix4().compose(position,q,new THREE.Vector3(1,1,1)),local=captureRigAttachment(bone(),position,q);
  for(const handle of ['leftHand','pelvis','head']){
    pose.dragHandle(handle,pose.getHandlePosition(handle).add(new THREE.Vector3(.12,.2,.08)));
    updateRigAttachment(bone(),local,position,q);
    const relative=captureRigAttachment(bone(),position,q);
    relative.elements.forEach((value,i)=>assert.ok(Math.abs(value-local.elements[i])<1e-9));
  }
  pose.reset();updateRigAttachment(bone(),local,position,q);
  const reset=new THREE.Matrix4().compose(position,q,new THREE.Vector3(1,1,1));
  reset.elements.forEach((value,i)=>assert.ok(Math.abs(value-original.elements[i])<1e-9));
});
test('reset is always in toolbar and stops physics before resetting pose',()=>{
  const source=fs.readFileSync(new URL('../app/page.tsx',import.meta.url),'utf8');
  assert.equal([...source.matchAll(/aria-label="Сбросить позу"/g)].length,1);
  assert.ok(source.indexOf('aria-label="Сбросить позу"')<source.indexOf('{ragdollEnabled && ('));
  const reset=source.slice(source.indexOf('const resetRagdoll ='),source.indexOf('const toggleLock ='));
  assert.ok(reset.indexOf('setPhysics(false)')<reset.indexOf('pose.reset()'));
  assert.ok(reset.includes('setRagdollEnabled(false)'));
});
