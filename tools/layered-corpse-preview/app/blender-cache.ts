import type { ClothBake, ClothBakeInput } from './cloth-physics';

/** Geometry/pose/timing/material identity. Camera and unrelated loot do not invalidate cloth. */
export async function clothSceneKey(input: ClothBakeInput): Promise<string> {
  const body = { floor: input.floor, duration: input.duration, capsules: input.capsules,
    items: input.items.map(i => ({ layerId:i.layerId, releaseTime:i.releaseTime, target:i.target,
      seed:i.seed, flightTime:i.flightTime, spin:i.spin, fabricStiffness:i.fabricStiffness ?? 1,
      surfaces:i.surfaces.map(s=>({positions:Array.from(s.positions),uvs:Array.from(s.uvs),indices:Array.from(s.indices)})) })) };
  const digest = await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(body)));
  return Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
}

export function decodeBlenderCache(buffer:ArrayBuffer, expectedKey:string, input:ClothBakeInput): {bake:ClothBake; warnings:string[]} {
  const fail=(s:string):never=>{throw new Error('Кэш Blender: '+s);};
  if(buffer.byteLength<12 || buffer.byteLength>512*1024*1024)fail('неверный размер');
  if(new TextDecoder().decode(new Uint8Array(buffer,0,8))!=='PZCLOTH1')fail('неверный формат');
  const length=new DataView(buffer).getUint32(8,true), start=12+Math.ceil(length/4)*4;
  if(length>32*1024*1024 || start>buffer.byteLength)fail('повреждён заголовок');
  const h=JSON.parse(new TextDecoder().decode(new Uint8Array(buffer,12,length)));
  if(h.sceneKey!==expectedKey)fail('сцена изменилась; экспортируйте новый снимок');
  if(h.fps!==60 || h.frameCount!==Math.round(input.duration*h.fps)+1 || !Array.isArray(h.tracks) || h.tracks.length!==input.items.length)fail('не совпадает секвенция');
  let offset=start;
  const tracks=h.tracks.map((t:any,index:number)=>{
    if(!Number.isSafeInteger(t.particleCount)||t.particleCount<1||t.particleCount>200000 || t.releaseTime!==input.items[index].releaseTime)fail('неверный трек');
    const floats=t.particleCount*3*h.frameCount;
    if(offset+floats*4>buffer.byteLength)fail('обрезанные кадры');
    for(const k of ['positions','uvs','indices','particleForVertex'])if(!Array.isArray(t[k])||!t[k].every(Number.isFinite))fail('неверная геометрия');
    const n=t.particleForVertex.length;
    if(t.positions.length!==n*3||t.uvs.length!==n*2||t.indices.length%3 ||
      !t.indices.every((v:number)=>Number.isInteger(v)&&v>=0&&v<n) ||
      !t.particleForVertex.every((v:number)=>Number.isInteger(v)&&v>=0&&v<t.particleCount))fail('неверные индексы');
    const frames=new Float32Array(buffer,offset,floats);offset+=floats*4;
    if(!frames.every(Number.isFinite))fail('нечисловые координаты');
    for(let v=0;v<n;v++)for(let a=0;a<3;a++)if(Math.abs(t.positions[v*3+a]-frames[t.particleForVertex[v]*3+a])>1e-5)fail('изменено начальное положение');
    return {positions:new Float32Array(t.positions),uvs:new Float32Array(t.uvs),indices:new Uint32Array(t.indices),
      particleForVertex:new Uint32Array(t.particleForVertex),particleCount:t.particleCount,releaseTime:t.releaseTime,frames};
  });
  if(offset!==buffer.byteLength)fail('лишние данные');
  return {bake:{fps:h.fps,frameCount:h.frameCount,tracks},warnings:Array.isArray(h.warnings)?h.warnings.filter((w:unknown)=>typeof w==='string'):[]};
}
