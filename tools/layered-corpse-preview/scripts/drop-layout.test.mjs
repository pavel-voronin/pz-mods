import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {defaultDropPoints,decodeDropLayout,dropDiskSample,clampDropRadius} from '../app/scene-layout.ts';
test('all three centers and radii survive storage roundtrip',()=>{
 const points=defaultDropPoints();points.valuables={x:.7,z:.8,radius:.43};points.weapon.radius=.21;
 assert.deepEqual(decodeDropLayout(JSON.stringify({version:1,points})),points);
});
test('invalid storage is safe and resize stays bounded',()=>{
 assert.deepEqual(decodeDropLayout('bad'),defaultDropPoints());
 assert.deepEqual(decodeDropLayout('{"version":2}'),defaultDropPoints());
 assert.equal(clampDropRadius(.001),.04);assert.equal(clampDropRadius(999),1.5);
 const points=defaultDropPoints();points.valuables.radius=-4;
 assert.equal(decodeDropLayout(JSON.stringify({version:1,points})).valuables.radius,.04);
});
test('random targets cover the disk and never change while scrubbing',()=>{
 let r2=0;
 for(let i=0;i<2000;i++) {
  const point=dropDiskSample(i,.5),radius=Math.hypot(point.x,point.z);
  assert.ok(radius<=.5);r2+=radius*radius;
  assert.deepEqual(point,dropDiskSample(i,.5));
  const doubled=dropDiskSample(i,1);assert.equal(doubled.x,point.x*2);assert.equal(doubled.z,point.z*2);
 }
 assert.ok(Math.abs(r2/2000-.125)<.012);
});
test('new zombies preserve layout and ring resizing does not move the center',()=>{
 const source=fs.readFileSync(new URL('../app/page.tsx',import.meta.url),'utf8');
 const random=source.slice(source.indexOf('const randomize ='),source.indexOf('return (',source.indexOf('const randomize =')));
 assert.ok(!random.includes('dropPointPositionsRef.current ='));
 assert.ok(!source.includes('randomizedDropPoints'));
 const resize=source.slice(source.indexOf('if(drag.resize)'),source.indexOf('} else {',source.indexOf('if(drag.resize)')));
 assert.ok(resize.includes('.radius=radius'));assert.ok(!resize.includes('marker.position.copy'));
 assert.ok(source.includes('saveDropLayout();'));
});

test('drop editing renders only and commits one calculation on release',()=>{
 const source=fs.readFileSync(new URL('../app/page.tsx',import.meta.url),'utf8');
 const change=source.slice(source.indexOf('const onDropTransformChange ='),source.indexOf("dropTransformControls.addEventListener('change'"));
 assert.ok(change.includes('render();'));
 assert.ok(!change.includes('scheduleQuickPreview('));assert.ok(!change.includes('applySequence('));assert.ok(!change.includes('saveDropLayout('));
 const resize=source.slice(source.indexOf('if(drag.resize)'),source.indexOf('const finishPointer ='));
 assert.ok(!resize.includes('scheduleQuickPreview('));assert.ok(!resize.includes('applySequence('));
 const finish=source.slice(source.indexOf('const finishDropEdit ='),source.indexOf('const onDropTransformChange ='));
 assert.equal([...finish.matchAll(/scheduleQuickPreview\(0\)/g)].length,1);
 assert.ok(finish.includes('if (!dropEditActive) return;'));
 assert.ok(source.includes('if (dropEditActive) { dropEditDirty = true; return; }'));
 assert.ok(source.includes("addEventListener('mouseUp', finishDropEdit)"));
 assert.ok(source.includes('if (dropWasEdited) finishDropEdit();'));
});
