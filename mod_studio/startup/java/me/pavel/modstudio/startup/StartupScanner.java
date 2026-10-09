package me.pavel.modstudio.startup;

import java.io.File;
import java.net.URI;
import java.util.*;
import java.util.concurrent.*;

/** Native File.list traversal and merge order; workers never touch game state. */
public final class StartupScanner {
    public static volatile boolean enabled;
    public static final Runnable POLL=()->zombie.core.Core.getInstance().DoFrameReady();
    private static final ThreadLocal<Integer> indexDepth=ThreadLocal.withInitial(()->0);
    private static final ThreadLocal<Map<String,URI>> indexUris=ThreadLocal.withInitial(HashMap::new);
    private static final ThreadLocal<Set<String>> indexDirectories=ThreadLocal.withInitial(HashSet::new);
    private static final ThreadLocal<int[]> directoryHits=ThreadLocal.withInitial(()->new int[1]);
    public static void enterIndex(){if(indexDepth.get()==0){indexUris.get().clear();indexDirectories.get().clear();directoryHits.get()[0]=0;}indexDepth.set(indexDepth.get()+1);}
    public static void exitIndex(){int depth=indexDepth.get()-1;indexDepth.set(depth);if(depth==0){StartupTrace.note("index-directory-cache", "hits="+directoryHits.get()[0]);indexUris.get().clear();indexDirectories.get().clear();}}
    /** Only substituted inside native filesystem initialization, within its scan scope. */
    public static boolean isDirectory(File file){
        if(enabled && indexDepth.get()>0){
            String path=path(file);
            if(indexUris.get().containsKey(path)){directoryHits.get()[0]++;return indexDirectories.get().contains(path);}
        }
        return file.isDirectory();
    }
    public static String relative(URI root,String path){
        if(!enabled || indexDepth.get()==0)return null;
        URI uri=indexUris.get().get(path);if(uri==null)return null;
        URI relative=root.relativize(uri);if(relative.equals(uri))return path;
        String result=relative.getPath();
        return path.endsWith("/")&&!result.endsWith("/")?result+"/":result;
    }
    static URI uri(String path,boolean directory)throws Exception{
        // On case-sensitive systems the lowercased File.toURI target can differ
        // from the original file. Retain native existence/URI semantics there.
        if(File.separatorChar!='\\')return new File(new File(path).getAbsolutePath().toLowerCase(Locale.ENGLISH)).toURI();
        String p=new File(path).getAbsolutePath().toLowerCase(Locale.ENGLISH).replace(File.separatorChar,'/');
        if(!p.startsWith("/"))p="/"+p;
        if(directory&&!p.endsWith("/"))p+="/";
        if(p.startsWith("//"))p="//"+p;
        return new URI("file",null,p,null);
    }
    static final class Listing extends ArrayList<String>{
        final Set<String> directories=new HashSet<>();
        @Override public boolean addAll(Collection<? extends String> items){if(items instanceof Listing listing)directories.addAll(listing.directories);return super.addAll(items);}
    }
    static final int workerCount=Math.max(1,Math.min(8,Integer.getInteger("modstudio.startup.workers",Math.min(8,Runtime.getRuntime().availableProcessors()))));
    private static final ExecutorService workers=Executors.newFixedThreadPool(workerCount,r->{Thread t=new Thread(r,"modstudio-startup-scan");t.setDaemon(true);return t;});
    public static boolean replace(File root,List<String> output,Runnable poll){
        try{
            List<String> result=parallel(root,poll);
            if(indexDepth.get()>0){
                Map<String,URI> prepared=new HashMap<>();
                for(String path:result)prepared.put(path,uri(path,result instanceof Listing listing && listing.directories.contains(path)));
                indexUris.get().putAll(prepared);
                if(result instanceof Listing listing)indexDirectories.get().addAll(listing.directories);
            }
            output.addAll(result);
            StartupTrace.note("scan-result",root+": entries="+result.size());
            return true;
        }catch(Exception e){
            if(e instanceof InterruptedException)Thread.currentThread().interrupt();
            StartupTrace.note("scan-fallback",root+": "+e);
            return false;
        }
    }
    static List<String> parallel(File root,Runnable poll)throws Exception{
        if(!root.isDirectory()){poll.run();return List.of(path(root));}
        String[] names=root.list();if(names==null)throw new IllegalStateException("Cannot enumerate "+root);
        // Thin roots can contain one huge branch and empty siblings. Reach the
        // independent branches instead of assigning that whole tree to one worker.
        if(names.length<Math.max(4,workerCount)){
            List<String> result=new Listing();addDirectory(root,result);
            for(String name:names)result.addAll(parallel(new File(root,name),poll));
            poll.run();return result;
        }
        List<Future<List<String>>> tasks=new ArrayList<>();
        try{
            for(String name:names){File child=new File(root.getAbsolutePath()+File.separator+name);tasks.add(workers.submit(()->serial(child)));}
            List<String> result=new Listing();addDirectory(root,result);
            poll.run();
            for(var task:tasks){
                while(true){
                    try{result.addAll(task.get(10,TimeUnit.MILLISECONDS));break;}
                    catch(TimeoutException waiting){poll.run();}
                }
            }
            poll.run();return result;
        }finally{for(var task:tasks)if(!task.isDone())task.cancel(true);}
    }
    static List<String> serial(File root)throws InterruptedException{
        List<String> output=new Listing();
        Deque<File> pending=new ArrayDeque<>();pending.push(root);
        while(!pending.isEmpty()){
            if(Thread.currentThread().isInterrupted())throw new InterruptedException("Scan interrupted");
            File file=pending.pop();
            if(!file.isDirectory()){output.add(path(file));continue;}
            addDirectory(file,output);
            // NIO providers need not enumerate in File.list order. Native precedence
            // follows this exact order, including case-colliding resource names.
            String[] names=file.list();
            if(names==null)throw new IllegalStateException("Cannot enumerate "+file);
            for(int i=names.length-1;i>=0;i--)pending.push(new File(file.getAbsolutePath()+File.separator+names[i]));
        }
        return output;
    }
    private static String path(File file){return file.getAbsolutePath().replace("\\","/").replace("./","");}
    private static void addDirectory(File root,List<String> output){String p=path(root);if(p.contains("media/maps/")){output.add(p);if(output instanceof Listing listing)listing.directories.add(p);}}
}
