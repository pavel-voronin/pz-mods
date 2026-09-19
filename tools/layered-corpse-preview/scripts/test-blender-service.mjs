import assert from 'node:assert/strict';
const base='http://localhost:3000/__blender';
assert.equal((await fetch(base+'/jobs/00000000-0000-0000-0000-000000000000')).status,404);
assert.equal((await fetch(base+'/jobs',{method:'POST',headers:{Origin:'https://example.com','Content-Type':'application/json','x-cloth-client':'1'},body:'{}'})).status,403);
assert.equal((await fetch(base+'/jobs',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,403);
assert.equal((await fetch(base+'/jobs/00000000-0000-0000-0000-000000000000/cache%2f..%2fpackage.json')).status,404);
console.log('PASS local Blender service: unknown job, cross-origin, missing client header, path isolation');
