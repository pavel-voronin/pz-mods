package me.pavel.modstudio;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import org.luaj.kahluafork.compiler.LexState;
import se.krka.kahlua.vm.Prototype;

/** Independent compiler preparation; closures and all Lua execution stay on the caller. */
public final class LuaPreparation implements AutoCloseable {
    private record Prepared(String text, String name, Prototype prototype) {}
    private final ExecutorService workers;
    private final Map<String,Future<Prepared>> pending=new LinkedHashMap<>();
    private final Set<String> consumed=new HashSet<>();
    private final Iterator<Map.Entry<Path,String>> remaining;
    private final int window;
    private boolean closed;
    private int observedLoaded;

    public LuaPreparation(Collection<Path> paths, int count, int window) {
        this(defaultNames(paths),count,window);
    }
    private static Map<Path,String> defaultNames(Collection<Path> paths){
        Map<Path,String> names=new LinkedHashMap<>();for(Path path:paths)names.put(path,path.getFileName().toString());return names;
    }
    public LuaPreparation(Map<Path,String> sources, int count, int window) {
        if(count<1 || count>8 || window<count || window>128) throw new IllegalArgumentException("Invalid preparation bounds");
        this.window=window;
        this.remaining=new LinkedHashMap<>(sources).entrySet().iterator();
        workers=Executors.newFixedThreadPool(count,r->{Thread t=new Thread(r,"ModStudio-LuaPrepare");t.setDaemon(true);return t;});
        fill();
    }
    private static String key(Path path){return path.toAbsolutePath().toString().replace('\\','/');}
    private void fill() {
        while(!closed && pending.size()<window && remaining.hasNext()) {
            Map.Entry<Path,String> source=remaining.next();Path path=source.getKey();String name=source.getValue();
            String sourceKey=key(path);if(consumed.contains(sourceKey))continue;
            pending.put(sourceKey,workers.submit(()->{
                String text;
                try(Reader input=new InputStreamReader(Files.newInputStream(path),StandardCharsets.UTF_8)) {
                    StringWriter out=new StringWriter();input.transferTo(out);text=out.toString();
                }
                try(Reader input=new StringReader(text)) {
                    // FuncState's only mutable static compiler inputs are debug file names.
                    // Rebind every prototype to caller metadata after preparation, before publication.
                    return new Prepared(text,name,LexState.compile(input.read(),input,name,null));
                }
            }));
        }
    }
    /** Native loaded is append-only during a directory scope. Reclaim slots for
     * files executed by require before their position in the directory list. */
    public void skipLoaded(List<String> loaded){
        if(closed)return;
        if(loaded.size()<observedLoaded)observedLoaded=0;
        while(observedLoaded<loaded.size()){
            String path=loaded.get(observedLoaded++);if(path==null)continue;
            String sourceKey=path.replace('\\','/');consumed.add(sourceKey);
            Future<Prepared> job=pending.remove(sourceKey);if(job!=null)job.cancel(true);
        }
        fill();
    }
    /** Never waits on an unfinished compile; native compilation is the fallback. */
    public Prototype take(String path, String name, int first, Reader reader, String file, String fullFile) throws IOException {
        if(closed || !(reader instanceof BufferedReader input)) return null;
        String sourceKey=path.replace('\\','/');consumed.add(sourceKey);
        Future<Prepared> job=pending.remove(sourceKey);
        fill();
        if(job==null) return null;
        if(!job.isDone()){job.cancel(true);return null;}
        Prepared prepared;
        try{prepared=job.get();}
        catch(InterruptedException error){Thread.currentThread().interrupt();return null;}
        catch(ExecutionException|CancellationException error){return null;}
        String text=prepared.text;
        if(!Objects.equals(name,prepared.name) || first!=(text.isEmpty()?-1:text.charAt(0))) return null;
        // Validate the actual reader, not just timestamp/size: same-size rewrites and
        // filesystem overrides must fall through to the original compiler.
        input.mark(text.length()+1);
        boolean accepted=false;
        try {
            char[] buffer=new char[8192];int offset=text.isEmpty()?0:1;
            while(offset<text.length()) {
                int count=input.read(buffer,0,Math.min(buffer.length,text.length()-offset));
                if(count<0)return null;
                if(count==0)continue;
                for(int i=0;i<count;i++)if(buffer[i]!=text.charAt(offset+i))return null;
                offset+=count;
            }
            if(input.read()!=-1)return null;
            metadata(prepared.prototype,file,fullFile);
            accepted=true;
            return prepared.prototype;
        } finally {if(!accepted)input.reset();}
    }
    private static void metadata(Prototype p,String file,String fullFile) {
        if(p.code!=null && p.code.length>0){p.file=file;p.filename=fullFile;}
        for(Prototype child:p.prototypes)metadata(child,file,fullFile);
    }
    @Override public void close(){closed=true;for(Future<?> job:pending.values())job.cancel(true);pending.clear();consumed.clear();workers.shutdownNow();}
}
