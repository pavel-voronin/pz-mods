package me.pavel.modstudio.startup;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;
import java.util.concurrent.*;

/** Same native per-directory WatchKeys; only preparation moves off the loading thread. */
public final class StartupWatch {
    public static volatile boolean enabled;
    public static volatile boolean deferUntilStartupComplete;
    private static final ExecutorService workers=Executors.newFixedThreadPool(4,r->{Thread t=new Thread(r,"modstudio-startup-watch");t.setDaemon(true);return t;});
    private static final ThreadLocal<Integer> depth=ThreadLocal.withInitial(()->0);
    private static final ThreadLocal<List<Job>> jobs=ThreadLocal.withInitial(ArrayList::new);
    private static final Queue<Job> deferred=new ConcurrentLinkedQueue<>();
    private record Registered(WatchKey key,Path path){}
    private record Result(List<Registered> keys,IOException error){}
    private record Job(Object owner,Future<Result> result){}
    public static void begin(){if(enabled)depth.set(depth.get()+1);}
    public static boolean submit(Path root,Object owner,WatchService watcher){
        if(!enabled||depth.get()==0||watcher==null)return false;
        jobs.get().add(new Job(owner,workers.submit(()->register(root,watcher))));
        return true;
    }
    private static Result register(Path root,WatchService watcher){
        List<Registered> keys=new ArrayList<>();
        IOException error=null;
        try{
            Files.walkFileTree(root,new SimpleFileVisitor<>(){
                @Override public FileVisitResult preVisitDirectory(Path path,BasicFileAttributes attributes)throws IOException{
                    if(Thread.currentThread().isInterrupted())throw new IOException("Registration interrupted");
                    keys.add(new Registered(path.register(watcher,StandardWatchEventKinds.ENTRY_MODIFY,StandardWatchEventKinds.ENTRY_CREATE),path));
                    return FileVisitResult.CONTINUE;
                }
            });
        }catch(IOException e){error=e;}
        return new Result(keys,error);
    }
    public static void finish(){
        if(!enabled)return;
        int nesting=depth.get()-1;depth.set(nesting);if(nesting!=0)return;
        List<Job> pending=jobs.get();if(pending.isEmpty())return;
        if(deferUntilStartupComplete){deferred.addAll(pending);pending.clear();return;}
        publish(pending);
    }
    public static synchronized void flush(){
        List<Job> pending=new ArrayList<>();Job job;
        while((job=deferred.poll())!=null)pending.add(job);
        if(!pending.isEmpty())publish(pending);
    }
    public static void endStartup(){deferUntilStartupComplete=false;flush();}
    private static void publish(List<Job> pending){
        long start=System.nanoTime();int count=0;boolean interrupted=false;
        try{
            List<Result> completed=new ArrayList<>();ExecutionException failure=null;
            for(Job job:pending){
                // Every queued task must finish before native code consumes the watcher map.
                while(true){
                    try{completed.add(job.result.get());break;}
                    catch(InterruptedException e){interrupted=true;}
                    catch(ExecutionException e){if(failure==null)failure=e;completed.add(null);break;}
                }
            }
            if(failure!=null)throw failure;
            for(int i=0;i<pending.size();i++){
                Job job=pending.get(i);Result result=completed.get(i);
                var field=job.owner.getClass().getDeclaredField("watchkeyMapping");field.setAccessible(true);
                @SuppressWarnings("unchecked") Map<WatchKey,Path> map=(Map<WatchKey,Path>)field.get(job.owner);
                for(Registered key:result.keys){map.put(key.key,key.path);count++;}
                if(result.error!=null){
                    var watcherField=job.owner.getClass().getDeclaredField("watcher");watcherField.setAccessible(true);watcherField.set(job.owner,null);
                    StartupTrace.note("watch-error",result.error.toString());
                    zombie.core.logger.ExceptionLogger.logException(result.error);
                }
            }
        }catch(Exception e){
            // Do not allow a partially published batch to silently proceed.
            throw new IllegalStateException("Cannot publish native watcher registrations",e);
        }finally{
            pending.clear();if(interrupted)Thread.currentThread().interrupt();
            StartupTrace.span("watch-registration-barrier:keys="+count,start,null);
        }
    }
}
