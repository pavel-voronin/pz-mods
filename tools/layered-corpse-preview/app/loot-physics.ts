import * as CANNON from 'cannon-es';
import {boxVertices,lootBottom,stableLootSupport,type LootHull} from './loot-collider.ts';

export type LootBodyInput = {
  center: [number, number, number]; halfExtents: [number, number, number];
  quaternion: [number, number, number, number]; target: [number, number, number];
  releaseTime: number; mass: number; index: number;
  flightTime?: number; angularVelocity?: [number, number, number];
  hull?:LootHull;
  landingArea?:{center:[number,number,number];radius:number};
};
export type LootBake = { fps: number; frameCount: number; frames: Float32Array[]; releaseTimes: number[]; landingError?:number };

class LootSolver extends CANNON.GSSolver {
  solve(dt:number,world:CANNON.World){
    const patches=new Map<string,CANNON.FrictionEquation[]>();
    for(const equation of this.equations){
      if(!(equation instanceof CANNON.FrictionEquation))continue;
      if(![equation.bi,equation.bj].some(b=>b.shapes[0] instanceof CANNON.ConvexPolyhedron))continue;
      const key=[equation.bi.id,equation.bj.id].sort((a,b)=>a-b).join(',');
      const patch=patches.get(key)??[];patch.push(equation);patches.set(key,patch);
    }
    // Narrowphase supplies mu*m*g (force), while GS clamps lambda (impulse).
    // Convert F to F*dt and distribute one friction budget over the patch;
    // otherwise a sub-millisecond step makes small props effectively glued.
    for(const patch of patches.values())for(const eq of patch){
      const count=Math.max(1,patch.length/2);eq.minForce*=dt/count;eq.maxForce*=dt/count;
    }
    return super.solve(dt,world);
  }
}



/** One fixed-step world per bake: contacts and sleep are never restarted per GIF frame. */
export function bakeLoot(inputs: LootBodyInput[], floor: number, duration: number): LootBake {
  let aimed=inputs.map(input=>({...input,target:[...input.target] as [number,number,number]}));
  let best:LootBake|undefined,bestError=Infinity;
  // Shooting method: correct the launch, never teleport a landed body or erect
  // an invisible wall at the marker. Every candidate runs the same contacts.
  for(let attempt=0;attempt<4;attempt++){
    const bake=simulateLoot(aimed,floor,duration);
    let error=0;
    aimed=aimed.map((input,index)=>{
      const area=input.landingArea;if(!area)return input;
      const end=bake.frames[index].subarray(-7);
      const outside=Math.max(0,Math.hypot(end[0]-area.center[0],end[2]-area.center[2])-area.radius*.9);
      error=Math.max(error,outside);
      if(!outside)return input;
      return {...input,target:[input.target[0]+(inputs[index].target[0]-end[0])*.6,input.target[1],input.target[2]+(inputs[index].target[2]-end[2])*.6] as [number,number,number]};
    });
    if(error<bestError){bestError=error;best=bake;}
    if(error<=.0001)break;
  }
  best!.landingError=bestError;
  return best!;
}

function simulateLoot(inputs: LootBodyInput[], floor: number, duration: number): LootBake {
  const floorFriction = 0.6;
  const fps = 60, substeps = inputs.some(input=>input.hull) ? 8 : 4;
  const baseDt = 1 / (fps * substeps), frameCount = Math.ceil(duration * fps) + 1;
  const world = new CANNON.World({ gravity: new CANNON.Vec3(0, -9.81, 0) });
  world.allowSleep = true;
  const solver = new LootSolver();
  solver.iterations = 32;
  solver.tolerance = 1e-8;
  world.solver = solver;
  const groundMaterial = new CANNON.Material('floor'), propMaterial = new CANNON.Material('props');
  const ground = new CANNON.Body({ mass: 0, material: groundMaterial, shape: new CANNON.Plane() });
  ground.position.y = floor;
  ground.quaternion.setFromEuler(-Math.PI / 2, 0, 0);
  world.addBody(ground);
  for (const other of [groundMaterial, propMaterial]) world.addContactMaterial(new CANNON.ContactMaterial(other, propMaterial, {
    friction: other === groundMaterial ? floorFriction : 0.45, restitution: 0,
    contactEquationStiffness: 1e8, contactEquationRelaxation: 4,
    frictionEquationStiffness: 1e8, frictionEquationRelaxation: 4,
  }));
  const states = inputs.map((input) => {
    const half = new CANNON.Vec3(...input.halfExtents.map((n) => Math.max(0.00015, n)) as [number, number, number]);
    const vertices=input.hull?.vertices??boxVertices([half.x,half.y,half.z]);
    const shape=input.hull?new CANNON.ConvexPolyhedron({vertices:vertices.map(p=>new CANNON.Vec3(...p)),faces:input.hull.faces}):new CANNON.Box(half);
    if(shape instanceof CANNON.ConvexPolyhedron){
      // Triangulated planar faces share SAT axes. Test each axis once without
      // simplifying the collider or changing its supporting vertices.
      const axes=new Map<string,CANNON.Vec3>();
      for(const normal of shape.faceNormals){
        const n=normal.clone();if(n.x<0||(n.x===0&&n.y<0)||(n.x===0&&n.y===0&&n.z<0))n.negate(n);
        const key=[n.x,n.y,n.z].map(v=>Math.round(v*1e10)).join(',');axes.set(key,n);
      }
      shape.uniqueAxes=[...axes.values()];
    }
    const body = new CANNON.Body({ mass: input.mass, material: propMaterial, shape,
      position: new CANNON.Vec3(...input.center), quaternion: new CANNON.Quaternion(...input.quaternion) });
    // Detailed hulls require support-aware sleeping: low angular speed alone
    // can freeze them while tipping. Planar/legacy box fallbacks keep their
    // existing box-material settling behaviour.
    body.allowSleep = !input.hull;
    // Cannon also uses this threshold to wake a neighbour. Keep wake-up above
    // numerical contact jitter; the stricter manual rest test is below.
    body.sleepSpeedLimit=.06;body.sleepTimeLimit=input.hull?.4:.18;
    body.linearDamping = 0.03; body.angularDamping = 0.35;
    const flight = input.flightTime ?? 0.5;
    const bottom = lootBottom(vertices,body.quaternion);
    return { body, vertices, precise:!!input.hull, active: false, quiet: 0,
      supportAge:Infinity,motionQuiet:0,restPosition:body.position.clone(),restRotation:body.quaternion.clone(),radius: half.length(), flight, bottom,
      frames: new Float32Array(frameCount * 7) };
  });
  // Discrete convex contacts must see thin cards before they cross one another.
  for(const state of states)state.body.addEventListener('wakeup',()=>{
    state.quiet=0;state.motionQuiet=0;state.supportAge=Infinity;
    state.restPosition.copy(state.body.position);state.restRotation.copy(state.body.quaternion);
  });
  // Bound relative surface travel by a fraction of the thinnest collider.
  const minThickness=Math.min(...inputs.map(input=>Math.max(.0003,2*Math.min(...input.halfExtents))));
  for (let frame = 0; frame < frameCount; frame++) {
    let elapsed=0;
    while(frame>0 && elapsed<1/fps-1e-12) {
      // Refine only near a moving pair, not the entire world because a card
      // exists in a future pocket. Sleeping pairs need no SAT or microsteps.
      let nearThinPair=false;
      if(minThickness<.003)for(let a=0;a<states.length;a++){
        const sa=states[a];if(!sa.active)continue;
        for(let b=a+1;b<states.length;b++){
          const sb=states[b];if(!sb.active||(sa.body.sleepState===CANNON.Body.SLEEPING&&sb.body.sleepState===CANNON.Body.SLEEPING))continue;
          const reach=sa.radius+sb.radius+(sa.body.velocity.length()+sb.body.velocity.length())*baseDt;
          if(sa.body.position.distanceSquared(sb.body.position)<reach*reach)nearThinPair=true;
        }
      }
      const dt=Math.min(nearThinPair?1/1920:baseDt,1/fps-elapsed);
      elapsed+=dt;
      const time = (frame-1)/fps+elapsed;
      states.forEach((state, index) => {
        if (state.active || time+1e-12 < inputs[index].releaseTime) return;
        // Several pockets may share a source point. Start their physical boxes
        // without overlap; otherwise the contact solver injects a huge separating
        // impulse before the throw even begins. Never reposition active bodies.
        const origin = new CANNON.Vec3(...inputs[index].center);
        for(let attempt=0;attempt<200;attempt++) {
          if(attempt) {
            const angle=attempt*2.399963, radius=.018*Math.sqrt(attempt);
            state.body.position.set(origin.x+Math.cos(angle)*radius,origin.y+.008*Math.floor(attempt/30),origin.z+Math.sin(angle)*radius);
          }
          state.body.updateAABB();
          if(!states.some(other=>other.active && (other.body.updateAABB(),state.body.aabb.overlaps(other.body.aabb))))break;
        }
        const dx=inputs[index].target[0]-state.body.position.x, dz=inputs[index].target[2]-state.body.position.z;
        // A slower ballistic toss reaches the marker. Contact friction and
        // rolling resistance dissipate the remaining motion after landing.
        state.body.velocity.set(dx/state.flight,
          (floor-state.bottom-state.body.position.y+.5*9.81*state.flight*state.flight)/state.flight,
          dz/state.flight);
        state.active = true;
        state.body.angularVelocity.set(...(inputs[index].angularVelocity ?? [.35, .4, .25]));
        world.addBody(state.body);
      });
      world.step(dt);
      states.forEach((state) => {
        if (!state.active || state.body.sleepState === CANNON.Body.SLEEPING) return;
        const body = state.body;
        const supported = world.contacts.some((c) => (c.bi === body && c.ni.y < -0.35) || (c.bj === body && c.ni.y > 0.35));
        // Dissipate rolling/tumbling only on support, never in free flight.
        body.linearDamping = supported && !state.precise ? 0.65 : 0.03;
        body.angularDamping = supported ? (state.precise?0.5:0.8) : 0.35;
        // Measure motion of the surface as well as the centre. Sleep requires
        // real support; objects can never be frozen in mid-air by this test.
        const speed = body.velocity.length() + body.angularVelocity.length() * state.radius;
        const contacts=world.contacts.filter(c=>(c.bi===body&&c.ni.y<-.35)||(c.bj===body&&c.ni.y>.35));
        const support=contacts.map(c=>(c.bi===body?c.ri:c.rj));
        const bottom=lootBottom(state.vertices,body.quaternion);
        if(body.position.y+bottom<=floor+.0003)for(const vertex of state.vertices) {
          const p=body.quaternion.vmult(new CANNON.Vec3(...vertex));
          if(p.y-bottom<.0003)support.push(p);
        }
        // The centre must lie inside the horizontal contact footprint, not
        // outside a lone edge/point that gravity still needs to tip over.
        const restingOnPile=contacts.some(c=>(c.bi===body?c.bj:c.bi)!==ground);
        const stable=restingOnPile || stableLootSupport(support,.0015);
        body.allowSleep=!state.precise;
        state.quiet = supported && (!state.precise||stable) && speed < (state.precise?0.02:0.055) ? state.quiet + dt : 0;
        const rotationDot=Math.min(1,Math.abs(body.quaternion.x*state.restRotation.x+body.quaternion.y*state.restRotation.y+body.quaternion.z*state.restRotation.z+body.quaternion.w*state.restRotation.w));
        const surfaceDrift=body.position.distanceTo(state.restPosition)+2*state.radius*Math.sqrt(1-rotationDot*rotationDot);
        // Contact solvers may report noisy velocity while the actual supported
        // surface stays within 0.5 mm. Require a whole quiet window, never
        // just the first low-speed instant after impact.
        state.supportAge=supported&&stable?0:state.supportAge+dt;
        // A contact can disappear for one microstep at a numerically separated
        // face. A 25 ms grace period avoids restarting the quiet window forever;
        // the displacement bound still rejects a falling or sliding object.
        if(state.supportAge<.025&&surfaceDrift<.0005)state.motionQuiet+=dt;
        else {state.motionQuiet=0;state.restPosition.copy(body.position);state.restRotation.copy(body.quaternion);}
        if (state.quiet >= (state.precise?0.4:0.2) || state.motionQuiet>=.5) {body.allowSleep=true;body.sleep();}
      });
    }
    states.forEach((state) => {
      const { position: p, quaternion: q } = state.body;
      const y=state.active?Math.max(p.y,floor-lootBottom(state.vertices,q)+1e-7):p.y;
      state.frames.set([p.x, y, p.z, q.x, q.y, q.z, q.w], frame * 7);
    });
  }
  return { fps, frameCount, frames: states.map((state) => state.frames), releaseTimes: inputs.map((input) => input.releaseTime) };
}
