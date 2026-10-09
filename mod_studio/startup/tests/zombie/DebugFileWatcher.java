package zombie;
import java.nio.file.*;
import java.util.*;

/** Minimal signatures for proving the agent's publication-before-consumption barrier. */
public final class DebugFileWatcher {
    public static final DebugFileWatcher instance=new DebugFileWatcher();
    public final Map<WatchKey,Path> watchkeyMapping=new HashMap<>();
    public WatchService watcher;
    public int nativeRegistrations,events;
    public void registerDirRecursive(Path root){nativeRegistrations++;throw new AssertionError("Expected asynchronous interception");}
    public void update(){
        WatchKey key;
        while((key=watcher.poll())!=null){
            if(!watchkeyMapping.containsKey(key))throw new AssertionError("Update consumed an unpublished native key");
            events+=key.pollEvents().size();key.reset();
        }
    }
}
