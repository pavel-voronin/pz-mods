import {spawn, type ChildProcess} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import type {IncomingMessage,ServerResponse} from 'node:http';
import type {Plugin} from 'vite';
import {clothSceneKey,decodeBlenderCache} from '../app/blender-cache.ts';

/** Local dev only. No client-supplied commands/paths, no public or cross-origin access. */
export function localBlenderBake():Plugin {
  type Job={id:string;state:'running'|'ready'|'error'|'cancelled';message:string;code?:string;dir:string;child?:ChildProcess};
  const jobs=new Map<string,Job>();let active:Job|undefined;
  const root=process.cwd();
  const cancel=(job:Job)=>{job.state='cancelled';job.message='Расчёт отменён';job.child?.kill();if(active===job)active=undefined;};
  const run=(job:Job,script:string,args:string[])=>new Promise<void>((done,fail)=>{
    if(job.state!=='running'){fail(Error('Cancelled'));return;}
    const child=spawn(process.env.BLENDER_EXE??'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe',
      ['--background','--factory-startup','--threads','8','--python-exit-code','1','--python',resolve(root,'scripts',script),'--',...args],{windowsHide:true});
    job.child=child;let tail='';
    const log=(chunk:Buffer)=>{tail=(tail+chunk.toString()).slice(-6000);const matches=[...tail.matchAll(/SIM (\d+) (\d+) ([\d.]+)/g)];const p=matches.at(-1);if(p)job.message=`Blender · ${Math.round(Number(p[1])/Number(p[2])*100)}% · ${p[3]} с`;};
    child.stdout.on('data',log);child.stderr.on('data',log);
    child.on('error',fail);child.on('exit',code=>{
      job.child=undefined;
      const readable=[...tail.matchAll(/(?:RuntimeError|AssertionError): ([^\r\n]+)/g)].at(-1)?.[1];
      code===0?done():fail(Error(readable??(tail.slice(-1800)||'Blender не запущен')));
    });
  });
  async function bake(job:Job,source:any){
    try {
      await mkdir(job.dir,{recursive:true});source.sceneKey=await clothSceneKey(source);
      await writeFile(resolve(job.dir,'scene-source.json'),JSON.stringify(source));
      const cacheDir=resolve(root,'outputs','cloth-cache');
      const cachedPath=resolve(cacheDir,'isotropic-damped-v2-best-effort-'+source.sceneKey+'.pzcloth');
      try {
        const cached=await readFile(cachedPath).catch(()=>readFile(resolve(cacheDir,'isotropic-damped-v2-'+source.sceneKey+'.pzcloth')));
        decodeBlenderCache(cached.buffer.slice(cached.byteOffset,cached.byteOffset+cached.byteLength),source.sceneKey,source);
        if(job.state!=='running')return;
        await writeFile(resolve(job.dir,'scene.pzcloth'),cached);
        job.state='ready';job.message='Готовый расчёт новой ткани восстановлен';return;
      }catch{/* Missing or invalid cache must run a fresh simulation. */}
      await run(job,'prepare-cloth-scene.py',[resolve(job.dir,'scene-source.json'),'--posed-shell','--repair-layers','--allow-initial-intersections']);
      if(job.state!=='running')return;
      job.message='Blender · равномерная физическая сетка';
      await run(job,'remesh-cloth-scene.py',[resolve(job.dir,'scene-prepared.json'),'--allow-initial-intersections']);
      if(job.state!=='running')return;
      job.message='Blender · совместный расчёт одежды';
      await run(job,'blender-scene-bake.py',[resolve(job.dir,'scene-prepared.json'),'--surface-fabric','--drag-aware-launch','--damped-fabric','--allow-initial-intersections']);
      if(job.state!=='running')return;
      const bytes=await readFile(resolve(job.dir,'scene.pzcloth'));
      decodeBlenderCache(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),source.sceneKey,source);
      await mkdir(cacheDir,{recursive:true});await writeFile(cachedPath,bytes);
      job.state='ready';job.message='Кэш Blender готов';
    }catch(error){if(job.state!=='cancelled'){job.state='error';job.message=error instanceof Error?error.message:String(error);}}
    finally{if(active===job)active=undefined;}
  }
  const json=(res:ServerResponse,status:number,value:unknown)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(value));};
  async function handle(req:IncomingMessage,res:ServerResponse,next:()=>void){
    const url=new URL(req.url??'/','http://localhost');if(!url.pathname.startsWith('/__blender/')){next();return;}
    const ip=req.socket.remoteAddress;
    if(!['127.0.0.1','::1','::ffff:127.0.0.1'].includes(ip??'')){json(res,403,{error:'Local access only'});return;}
    const host=req.headers.host??'';
    if(!/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host) || (req.headers.origin && req.headers.origin!==`http://${host}`) || req.headers['sec-fetch-site']==='cross-site'){
      json(res,403,{error:'Same-origin access only'});return;
    }
    try{
      if(req.method==='POST' && url.pathname==='/__blender/jobs'){
        if(req.headers['x-cloth-client']!=='1' || !req.headers['content-type']?.startsWith('application/json')){json(res,403,{error:'Invalid request'});return;}
        if(active){json(res,409,{error:'Blender уже считает другую сцену'});return;}
        const chunks:Buffer[]=[];let size=0;
        for await(const chunk of req){size+=chunk.length;if(size>64*1024*1024){json(res,413,{error:'Снимок больше 64 МБ'});return;}chunks.push(chunk);}
        const body=JSON.parse(Buffer.concat(chunks).toString()),source=body.snapshot;
        if(source?.format!=='pz-cloth-scene-v1'||source.fps!==60||!Number.isFinite(source.duration)||source.duration<=0||source.duration>30||!Array.isArray(source.items)||source.items.length<1||source.items.length>30){json(res,400,{error:'Неверный снимок сцены'});return;}
        // Recheck after reading the request body; simultaneous POSTs must not start two solvers.
        if(active){json(res,409,{error:'Blender уже считает другую сцену'});return;}
        const id=randomUUID(),job:Job={id,state:'running',message:'Подготовка физических сеток',dir:resolve(root,'outputs','blender-jobs',id)};
        jobs.set(id,job);active=job;void bake(job,source);
        json(res,202,{id});return;
      }
      const match=url.pathname.match(/^\/__blender\/jobs\/([\da-f-]{36})(\/cache)?$/);
      const job=match?jobs.get(match[1]):undefined;
      if(!job){json(res,404,{error:'Расчёт не найден'});return;}
      if(req.method==='DELETE' && !match![2]){if(req.headers['x-cloth-client']!=='1'){json(res,403,{});return;}if(job.state==='running')cancel(job);json(res,200,{state:job.state});return;}
      if(req.method==='GET' && match![2]){
        if(job.state!=='ready'){json(res,409,{error:job.message});return;}
        const bytes=await readFile(resolve(job.dir,'scene.pzcloth'));
        res.writeHead(200,{'Content-Type':'application/octet-stream','Cache-Control':'no-store'});res.end(bytes);return;
      }
      if(req.method==='GET'){json(res,200,{id:job.id,state:job.state,message:job.message,code:job.code});return;}
      json(res,405,{error:'Method not allowed'});
    }catch(error){if(!res.headersSent)json(res,400,{error:String(error)});else res.end();}
  }
  return {name:'local-blender-bake',configureServer(server){server.middlewares.use((req,res,next)=>void handle(req,res,next));server.httpServer?.once('close',()=>{if(active)cancel(active);});}};
}
