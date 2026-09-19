import * as THREE from 'three';

// Explicit asset recipe, not automatic physical separation. In Lipstick.fbx
// islands 0/1/2 are the case, collar and lipstick; island 3 is the loose cap.
const recipes:Record<string,number[][]>={
  '/pz-game/pocket/models/Lipstick.fbx':[[0,1,2],[3]],
};

export function prepareLootParts(root:THREE.Object3D,model:string):Array<{group:THREE.Group;area:number}> {
  const recipe=recipes[model];
  const whole=()=>{
    const group=new THREE.Group(),clone=root.clone(true);
    clone.traverse(object=>{const mesh=object as THREE.Mesh;if(mesh.isMesh)mesh.geometry=mesh.geometry.clone();});
    group.add(clone);return [{group,area:1}];
  };
  if(!recipe)return whole();
  const islands=splitLootComponents(root);
  if(islands.length!==recipe.flat().length){
    islands.forEach(part=>part.group.traverse(object=>{const mesh=object as THREE.Mesh;if(mesh.isMesh)mesh.geometry.dispose();}));
    console.warn('Loot part recipe does not match asset; keeping whole:',model);
    return whole();
  }
  return recipe.map(ids=>{
    const group=new THREE.Group();let area=0;
    for(const id of ids){group.add(islands[id].group);area+=islands[id].area;}
    return {group,area};
  });
}

/** Connected by even one coincident vertex, including across mesh/UV seams.
 * Coordinates are compared after node transforms (1e-7 numerical tolerance).
 * No proximity, overlap, naming or size heuristics join separate bodies.
 * Output owns its geometry but shares source materials.
 */
export function splitLootComponents(root:THREE.Object3D):Array<{group:THREE.Group;area:number}> {
  root.updateWorldMatrix(true,true);
  const meshes:THREE.Mesh[]=[],geometries:THREE.BufferGeometry[]=[];
  root.traverse(object=>{const mesh=object as THREE.Mesh;if(mesh.isMesh){meshes.push(mesh);geometries.push(mesh.geometry.clone().applyMatrix4(mesh.matrixWorld));}});
  const parent:number[]=[],weld=new Map<string,number>();
  const find=(id:number):number=>{while(parent[id]!==id){parent[id]=parent[parent[id]];id=parent[id];}return id;};
  const join=(a:number,b:number)=>{parent[find(b)]=find(a);};
  const triangles:Array<{mesh:number;ids:number[];node:number;material:number;area:number}>=[];
  const a=new THREE.Vector3(),b=new THREE.Vector3(),c=new THREE.Vector3();
  geometries.forEach((geometry,mesh)=>{
    const position=geometry.getAttribute('position'),index=geometry.index;
    const count=index?.count??position.count;
    for(let at=0;at+2<count;at+=3){
      const ids=[0,1,2].map(j=>index?index.getX(at+j):at+j);
      const nodes=ids.map(id=>{
        const key=[position.getX(id),position.getY(id),position.getZ(id)].map(n=>Math.round(n*1e7)).join(',');
        let node=weld.get(key);if(node===undefined){node=parent.length;parent.push(node);weld.set(key,node);}return node;
      });
      join(nodes[0],nodes[1]);join(nodes[0],nodes[2]);
      a.fromBufferAttribute(position,ids[0]);b.fromBufferAttribute(position,ids[1]);c.fromBufferAttribute(position,ids[2]);
      const area=b.sub(a).cross(c.sub(a)).length()*.5;
      const material=geometry.groups.find(g=>at>=g.start&&at<g.start+g.count)?.materialIndex??0;
      triangles.push({mesh,ids,node:nodes[0],material,area});
    }
  });
  const components=new Map<number,typeof triangles>();
  for(const triangle of triangles){const id=find(triangle.node),list=components.get(id);if(list)list.push(triangle);else components.set(id,[triangle]);}
  const result=[...components.values()].map(faces=>{
    const group=new THREE.Group();let area=0;
    const batches=new Map<string,typeof triangles>();
    for(const face of faces){area+=face.area;const key=`${face.mesh}:${face.material}`,list=batches.get(key);if(list)list.push(face);else batches.set(key,[face]);}
    for(const batch of batches.values()) {
      const first=batch[0],source=geometries[first.mesh],geometry=new THREE.BufferGeometry();
      for(const [name,attribute] of Object.entries(source.attributes)) {
        const array=new Float32Array(batch.length*3*attribute.itemSize);let at=0;
        for(const face of batch)for(const id of face.ids)for(let axis=0;axis<attribute.itemSize;axis++)array[at++]=attribute.getComponent(id,axis);
        geometry.setAttribute(name,new THREE.BufferAttribute(array,attribute.itemSize));
      }
      const material=meshes[first.mesh].material;
      const mesh=new THREE.Mesh(geometry,Array.isArray(material)?material[first.material]:material);
      mesh.castShadow=true;mesh.receiveShadow=true;group.add(mesh);
    }
    return {group,area};
  });
  geometries.forEach(g=>g.dispose());
  return result;
}
