package me.pavel.modstudio.startup;
import java.nio.file.*;
import java.util.*;

/** Execute production premain against native-signature fixtures without starting the game. */
public final class ModStudioEarlyAgentTest {
    public static void main(String[] arguments)throws Exception {
        if(!StartupScanner.enabled || !StartupWatch.enabled || !StartupWatch.deferUntilStartupComplete)throw new AssertionError("Production defaults not active");
        if(!"ab".equals(zombie.scripting.ScriptParser.stripComments("a/* comment */b")))throw new AssertionError("Comment advice changed results");
        if(!List.of("a { b {} }","c {}","tail").equals(zombie.scripting.ScriptParser.parseTokens("a { b {} } c {} tail")))throw new AssertionError("Token advice changed order");
        Path root=Files.createTempDirectory("modstudio-early");
        var owner=zombie.DebugFileWatcher.instance;owner.watcher=root.getFileSystem().newWatchService();
        try {
            Files.createDirectories(root.resolve("media/maps/Test"));Files.createDirectories(root.resolve("media/lua"));
            Files.writeString(root.resolve("media/maps/Test/map.bin"),"map");Files.writeString(root.resolve("media/lua/a # café.lua"),"lua");
            var filesystem=new zombie.ZomboidFileSystem();filesystem.init(root.toFile());
            if(filesystem.nativeScans!=0 || filesystem.directoryEntries!=1)throw new AssertionError("Production scan not applied");
            if(!filesystem.indexed.keySet().equals(Set.of("media/maps/test/","media/maps/test/map.bin","media/lua/a # café.lua")))throw new AssertionError("Native indexing differs");
            filesystem.getAllModFolders(List.of(root.toString()));
            if(owner.nativeRegistrations!=0 || !owner.watchkeyMapping.isEmpty())throw new AssertionError("Watcher deferral not applied");
            zombie.GameWindow.init();
            if(StartupWatch.deferUntilStartupComplete || owner.watchkeyMapping.size()!=5)throw new AssertionError("Game startup did not publish every native watcher: "+owner.watchkeyMapping.size());
            Files.writeString(root.resolve("event.obj"),"event");
            long deadline=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(2);
            while(owner.events==0 && System.nanoTime()<deadline){Thread.sleep(10);owner.update();}
            if(owner.events==0)throw new AssertionError("Native watcher event lost");
            new zombie.gameStates.MainScreenState().enter();
            if(StartupScanner.enabled || StartupWatch.enabled || StartupTrace.active)throw new AssertionError("Early scope survives menu entry");
            System.out.println("Production early agent PASS: real premain, exact indexing, deferred native watchers/events and menu retirement; no game launch");
        }finally {
            owner.watcher.close();try(var paths=Files.walk(root)){for(Path path:paths.sorted(Comparator.reverseOrder()).toList())Files.delete(path);}
        }
    }
}
