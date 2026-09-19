import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';
import { snapshotGifCamera, fitGifViewport, GIF_FRAME_ASPECT } from '../app/gif-camera.ts';

test('visible GIF frame fits available space without covering toolbar or timeline', () => {
  for(const [width,height] of [[1200,700],[600,900],[260,250],[1800,500]]) {
    const frame=fitGifViewport(width,height);
    assert(frame.width<=width && frame.height<=height);
    assert(Math.abs(frame.width/frame.height-GIF_FRAME_ASPECT)<1e-12);
    const camera=new THREE.OrthographicCamera(-frame.width/frame.height,frame.width/frame.height,1,-1);
    const gif=snapshotGifCamera(camera,1_000_000);
    assert(Math.abs(gif.width/gif.height-frame.width/frame.height)<.005);
  }
});

for (const aspect of [16/9, 4/3, 1, 9/16, 2.4]) {
  test(`GIF preserves framing and isolates camera at aspect ${aspect}`, () => {
    const live = new THREE.OrthographicCamera(-1.22*aspect,1.22*aspect,1.22,-1.22,.01,100);
    live.position.set(4,6,-3);live.lookAt(.3,.1,-.4);live.zoom=2.17;
    live.updateProjectionMatrix();live.updateMatrixWorld(true);
    const before = JSON.stringify(live.toJSON());
    const exported = snapshotGifCamera(live,1_000_000);
    assert.equal(JSON.stringify(live.toJSON()),before);
    assert.notEqual(exported.camera,live);
    assert.deepEqual(exported.camera.projectionMatrix.elements,live.projectionMatrix.elements);
    for(const p of [new THREE.Vector3(),new THREE.Vector3(.2,.3,-.5)]) {
      assert(p.clone().project(live).distanceTo(p.clone().project(exported.camera))<1e-12);
    }
    assert(Math.abs(exported.width/exported.height-aspect)<.005);
    assert(exported.width%2===0 && exported.height%2===0);
    const projection=exported.camera.projectionMatrix.clone();
    const position=exported.camera.position.clone();
    live.zoom=.7;live.right=4;live.position.set(9,9,9);live.updateProjectionMatrix();
    assert.deepEqual(exported.camera.projectionMatrix.elements,projection.elements);
    assert(exported.camera.position.equals(position));
  });
}
