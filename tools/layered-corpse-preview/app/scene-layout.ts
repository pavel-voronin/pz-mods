export type DropPointKind = 'weapon' | 'clothing' | 'valuables';
export type DropPointPositions = Record<DropPointKind, { x: number; z: number; radius: number }>;
export const DROP_LAYOUT_KEY='layered-corpse:drop-layout:v1';
export const clampDropRadius=(radius:number)=>Math.max(.04,Math.min(1.5,radius));
export function decodeDropLayout(raw:string|null):DropPointPositions {
  const result=defaultDropPoints();
  try {
    const data=JSON.parse(raw??'null');
    if(data?.version!==1)return result;
    for(const kind of ['weapon','clothing','valuables'] as const) {
      const p=data.points?.[kind];
      if(p && Number.isFinite(p.x)&&Number.isFinite(p.z)&&Math.abs(p.x)<=20&&Math.abs(p.z)<=20)
        result[kind]={x:p.x,z:p.z,radius:Number.isFinite(p.radius)?clampDropRadius(p.radius):result[kind].radius};
    }
  }catch{}
  return result;
}
/** Deterministic uniform disk sample: seeking never rerolls a trajectory. */
export function dropDiskSample(index:number,radius:number) {
  const random=(n:number)=>{const v=Math.sin(n*127.1+311.7)*43758.5453;return v-Math.floor(v);};
  const angle=random(index+17)*Math.PI*2, r=Math.sqrt(random(index+83))*radius;
  return {x:Math.cos(angle)*r,z:Math.sin(angle)*r};
}

/** Deterministic fan inside one layer; different garments are not a jumpsuit.
 * The centre remains the global clothing pile, not a new per-step target.
 */
export function garmentReleaseFan(index:number,count:number,layer:number) {
  const angle=.65+layer*.73, side=count>1 ? index/(count-1)-.5 : 0;
  const spread=side*Math.min(.08,(count-1)*.035);
  return {
    x:Math.cos(angle)*spread,z:Math.sin(angle)*spread,
    delay:0,
    flight:.55,
    spin:side*.12,
  };
}

// Camera starts at +X,+Z. Screen-right is +X,-Z; foreground is +X,+Z.
export function defaultDropPoints(): DropPointPositions {
  return {
    weapon: { x: -0.12, z: 1.05, radius:.08 },
    valuables: { x: 1.05, z: -0.12, radius:.12 },
    clothing: { x: -0.72, z: -0.72, radius:.16 },
  };
}

export function randomDropPoints(): DropPointPositions {
  const points = defaultDropPoints();
  for (const point of Object.values(points)) {
    point.x += (Math.random() - 0.5) * 0.14;
    point.z += (Math.random() - 0.5) * 0.14;
  }
  return points;
}
