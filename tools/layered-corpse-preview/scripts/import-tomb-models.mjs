import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { Loader, LoadingManager, Texture } from 'three';
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js';

// Import only author-provided replacements. Never overwrite the vanilla rig
// files or substitute a loosely related model for a missing replacement.
const project = fileURLToPath(new URL('..', import.meta.url));
const workshop = process.env.PZ_WORKSHOP_ROOT ?? 'C:/Program Files (x86)/Steam/steamapps/workshop/content/108600';
const roots = [
  "3429790870/mods/Tomb's Player Body/42.13/media/models_X/Skinned",
  "3431734923/mods/Tomb's Player Body - Compatability/42.0/media/models_X/Skinned",
];
const slug = (value) => value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const files = new Map();
for (const root of roots) {
  const absolute = path.join(workshop, root);
  for (const file of fs.readdirSync(absolute, { recursive: true })) {
    if (!file.toLowerCase().endsWith('.fbx')) continue;
    const key = slug(path.basename(file, path.extname(file)));
    if (files.has(key)) throw new Error(`Ambiguous model: ${key}`);
    files.set(key, path.join(absolute, file));
  }
}
const aliases = {
  trousers: 'Trousers', shorts: 'LongShorts', shortshorts: 'ShortShorts',
  suittrousers: 'SuitTrousers', dungarees: 'Dungerees', jumper: 'Jumper',
  hoodie: 'HoodieDown', jacket: 'Jacket', suitjacket: 'SuitJacket',
  longcoat: 'LongCoat', apron: 'Apron', bulletvest: 'BulletVest',
};
const rowMajor = (matrix) => matrix.clone().transpose().toArray();
// This export contains geometry only. Runtime materials use the existing PZ
// texture catalog, not the author's Blender texture paths embedded in the FBX.
class GeometryOnlyTextureLoader extends Loader {
  load() { return new Texture(); }
}
const manager = new LoadingManager();
manager.addHandler(/.*/, new GeometryOnlyTextureLoader(manager));
function importFbx(buffer) {
  const scene = new FBXLoader(manager).parse(buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength), '');
  scene.updateMatrixWorld(true);
  const meshes = [];
  scene.traverse((mesh) => {
    if (!mesh.isSkinnedMesh) return;
    const geometry = mesh.geometry;
    const attribute = (name) => Array.from(geometry.getAttribute(name).array);
    if (!geometry.getAttribute('normal')) geometry.computeVertexNormals();
    // The vanilla JSON exporter stores image-space V (1 - UV.y), and runtime
    // textures all use flipY=false. FBXLoader returns conventional UV.y.
    // Convert here once so both asset sets share the same atlas convention.
    const uvs = attribute('uv').map((value, index) => index % 2 ? 1 - value : value);
    meshes.push({
      positions: attribute('position'), normals: attribute('normal'), uvs,
      indices: geometry.index ? Array.from(geometry.index.array) : Array.from({ length: geometry.getAttribute('position').count }, (_, i) => i),
      boneNames: mesh.skeleton.bones.map((bone) => bone.name),
      offsets: mesh.skeleton.boneInverses.map(rowMajor),
      joints: attribute('skinIndex'), weights: attribute('skinWeight'),
    });
  });
  if (!meshes.length) throw new Error('No skinned meshes');
  return { meshes };
}
const catalog = JSON.parse(fs.readFileSync(path.join(project, 'app/pz-catalog.json'), 'utf8'));
const manifest = { name: "Tomb's Player Body + Compatibility Vanilla+", models: { m: {}, f: {} } };
for (const sex of ['m', 'f']) {
  const models = new Set(['body', ...Object.values(catalog.garments).flatMap((category) => category.variants[sex].map((variant) => variant.model ?? category.model))]);
  for (const name of models) {
    const sourceKey = name === 'body' ? `${sex === 'm' ? 'male' : 'female'}body`
      : aliases[name] ? slug(`${sex === 'm' ? 'Bob' : 'Kate'}_${aliases[name]}`)
        : name.replace(/^garment-/, '');
    const source = files.get(sourceKey);
    if (!source) continue;
    const buffer = fs.readFileSync(source);
    const rig = importFbx(buffer);
    const url = `/pz/tomb/rigs/${sex}/${name}.json`;
    const output = path.join(project, 'public', url);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, JSON.stringify(rig));
    manifest.models[sex][name] = {
      url, source: path.relative(workshop, source).replaceAll('\\', '/'),
      sha256: createHash('sha256').update(buffer).digest('hex'),
      vertices: rig.meshes.reduce((sum, mesh) => sum + mesh.positions.length / 3, 0),
    };
    console.log(`${sex}/${name}: ${manifest.models[sex][name].vertices} vertices`);
  }
  if (!manifest.models[sex].body) throw new Error(`Missing ${sex} body`);
}
fs.writeFileSync(path.join(project, 'app/pz-tomb-models.json'), JSON.stringify(manifest, null, 2) + '\n');
