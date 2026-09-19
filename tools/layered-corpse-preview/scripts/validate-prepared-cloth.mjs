import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const file=path.resolve(process.argv[2]);
const prepared=JSON.parse(fs.readFileSync(file));
const bytes=fs.readFileSync(path.join(path.dirname(file),prepared.sourceFile));
const source=JSON.parse(bytes);
assert.equal(prepared.sourceSha256,createHash('sha256').update(bytes).digest('hex'));
for(const key of ['camera','floor','duration','fps'])assert.deepEqual(prepared[key],source[key]);
assert.equal(prepared.items.length,source.items.length);
let boundVertices=0,maxInitialDelta=0;
for(const [index,item] of prepared.items.entries()) {
  for(const key of ['releaseTime','target','spin','seed','layerId'])assert.deepEqual(item[key],source.items[index][key]??(key==='spin'?0:undefined));
  assert.deepEqual(item.velocity,source.velocities[index]);
  assert.ok(item.positions.flat().every(Number.isFinite));
  for(const face of item.faces)assert.ok(face.length===3&&face.every(i=>Number.isInteger(i)&&i>=0&&i<item.positions.length));
  for(const [si,surface] of item.renderSurfaces.entries()) {
    for(const key of ['positions','indices','uvs'])assert.deepEqual(surface[key],source.items[index].surfaces[si][key]);
    for(const binding of surface.bindings) {
      assert.ok(Math.abs(binding.weights.reduce((a,b)=>a+b,0)-1)<1e-5);
      for(let axis=0;axis<3;axis++) {
        const anchor=binding.ids.reduce((sum,id,i)=>sum+item.positions[id][axis]*binding.weights[i],0);
        maxInitialDelta=Math.max(maxInitialDelta,Math.abs(anchor-binding.startAnchor[axis]));
      }
      boundVertices++;
    }
  }
}
assert.ok(maxInitialDelta<1e-6,`Start position mismatch: ${maxInitialDelta}`);
console.log(JSON.stringify({passed:true,sourceSha256:prepared.sourceSha256,items:prepared.items.length,boundVertices,maxInitialDelta,
  collisionReady:prepared.report.items.map(r=>({index:r.index,ready:r.collisionReady,intersections:r.proxyPosedIntersections}))},null,2));
