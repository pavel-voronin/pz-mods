import * as THREE from './vendor/three.module.js';

export class GameModels {
  constructor() {
    this.renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,preserveDrawingBuffer:true});
    this.renderer.setSize(1024,1024);this.renderer.setClearColor(0,0);
    this.renderer.outputColorSpace=THREE.SRGBColorSpace;
    this.scene=new THREE.Scene();
    this.ambient=new THREE.HemisphereLight(0xfff5df,0x546653,2.0);this.scene.add(this.ambient);
    this.key=new THREE.DirectionalLight(0xffeacb,2.1);this.key.position.set(-2,3,-3);this.scene.add(this.key);
    this.fill=new THREE.DirectionalLight(0xbedcdd,.65);this.fill.position.set(3,1,2);this.scene.add(this.fill);
    this.camera=new THREE.OrthographicCamera(-1,1,1,-1,.01,20);
    this.geometry=new Map();this.textures=new Map();this.objects=new Map();
  }
  async getGeometry(url) {
    if(!this.geometry.has(url)) this.geometry.set(url,fetch(url).then(r=>{if(!r.ok)throw Error(url);return r.json()}).then(data=>data.meshes.map(m=>{
      const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(m.positions,3));g.setAttribute('uv',new THREE.Float32BufferAttribute(m.uv,2));g.setIndex(m.indices);if(m.normals)g.setAttribute('normal',new THREE.Float32BufferAttribute(m.normals,3));else g.computeVertexNormals();return g;
    })));
    return this.geometry.get(url);
  }
  async getTexture(url) {
    if(!this.textures.has(url))this.textures.set(url,new THREE.TextureLoader().loadAsync(url).then(t=>{t.colorSpace=THREE.SRGBColorSpace;t.anisotropy=this.renderer.capabilities.getMaxAnisotropy();return t}));
    return this.textures.get(url);
  }
  async getObject(asset,sex) {
    const id=asset.id+'_'+sex;
    if(!this.objects.has(id))this.objects.set(id,(async()=>{
      const geometry=await this.getGeometry(asset.models[sex]||asset.models.any);
      const map=await this.getTexture(sex==='Female'&&asset.femaleTexture?asset.femaleTexture:asset.texture);
      const group=new THREE.Group();const uniforms={opening:{value:0}};
      for(const g of geometry){
        const mat=new THREE.MeshLambertMaterial({map,side:asset.kind==='item'?THREE.DoubleSide:THREE.FrontSide,alphaTest:.04});
        if(asset.kind==='shirt'||asset.kind==='jacket'){
          mat.onBeforeCompile=shader=>{
            shader.uniforms.opening=uniforms.opening;
            shader.vertexShader='varying vec3 shirtPosition;\n'+shader.vertexShader.replace('#include <begin_vertex>','#include <begin_vertex>\nshirtPosition=position;');
            shader.fragmentShader='uniform float opening; varying vec3 shirtPosition;\n'+shader.fragmentShader.replace('#include <alphatest_fragment>',`#include <alphatest_fragment>
              float height=clamp((shirtPosition.y-0.48)/0.32,0.0,1.0);
              float gap=opening*(${asset.kind==='jacket'?'0.028+height*0.14':'0.008+height*0.075'});
              if(opening>0.001 && shirtPosition.y>0.48 && abs(shirtPosition.x)<gap) discard;`);
          };
          mat.customProgramCacheKey=()=>asset.kind+'-opening';
        }
        group.add(new THREE.Mesh(g,mat));
      }
      if(asset.kind==='item'){
        const box=new THREE.Box3().setFromObject(group),size=box.getSize(new THREE.Vector3()),center=box.getCenter(new THREE.Vector3());
        const wrapper=new THREE.Group();group.position.copy(center).negate();wrapper.add(group);wrapper.scale.setScalar(2/Math.max(size.x,size.y,size.z));
        const outer=new THREE.Group();outer.add(wrapper);return {group:outer,uniforms};
      }
      return {group,uniforms};
    })());
    return this.objects.get(id);
  }
  async render(asset,layer,state,target) {
    const {group,uniforms}=await this.getObject(asset,state.sex);
    this.scene.add(group);uniforms.opening.value=layer.opening||0;
    group.traverse(o=>{if(o.isMesh)o.material.color.set(layer.tint||'#ffffff')});
    this.key.intensity=state.light??2.1;
    if(asset.kind==='item') {
      const span=2.8;this.camera.left=-span/2;this.camera.right=span/2;this.camera.top=span/2;this.camera.bottom=-span/2;
      this.camera.position.set(0,0,4);this.camera.lookAt(0,0,0);
      this.key.position.set(-2,3,4);
      group.rotation.set(THREE.MathUtils.degToRad(layer.rx||0),THREE.MathUtils.degToRad(layer.ry||0),THREE.MathUtils.degToRad(layer.rz||0),'ZYX');
    } else {
      const span=state.span||.39;this.camera.left=-span/2;this.camera.right=span/2;this.camera.top=span/2;this.camera.bottom=-span/2;
      const yaw=THREE.MathUtils.degToRad(state.yaw),pitch=THREE.MathUtils.degToRad(state.pitch);
      const targetY=state.chestY??.66;
      this.camera.position.set(Math.sin(yaw)*3,targetY+Math.sin(pitch)*3,Math.cos(yaw)*Math.cos(pitch)*3);this.camera.lookAt(0,targetY,0);
      this.key.position.set(-2,3,3);group.rotation.set(0,0,0);
    }
    this.camera.updateProjectionMatrix();this.renderer.render(this.scene,this.camera);
    const ctx=target.getContext('2d');ctx.clearRect(0,0,1024,1024);ctx.drawImage(this.renderer.domElement,0,0);this.scene.remove(group);
  }
}
