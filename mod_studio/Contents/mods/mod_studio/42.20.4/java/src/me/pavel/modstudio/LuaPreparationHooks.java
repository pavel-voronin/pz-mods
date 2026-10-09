package me.pavel.modstudio;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import me.zed_0xff.zombie_buddy.Patch;
import org.luaj.kahluafork.compiler.FuncState;
import se.krka.kahlua.vm.Prototype;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;

/** Ordinary Mod Studio patches. No change to agents or loader sequencing. */
public final class LuaPreparationHooks {
    private static final ThreadLocal<Scope> scopes=new ThreadLocal<>();
    private static final class Scope {int depth;LuaPreparation preparation;boolean seeded;}
    public static void begin() {
        if(!StartupPreparationPolicy.enabled("lua")) return;
        Scope scope=scopes.get();if(scope==null){scope=new Scope();scopes.set(scope);}
        close(scope);scope.seeded=false;scope.depth++;
    }
    public static void end() {
        Scope scope=scopes.get();if(scope==null)return;
        close(scope);if(--scope.depth==0)scopes.remove();
    }
    private static void close(Scope scope){if(scope.preparation!=null){scope.preparation.close();scope.preparation=null;}}
    public static void prepare() {
        Scope scope=scopes.get();if(scope==null)return;
        if(scope.seeded){if(scope.preparation!=null)scope.preparation.skipLoaded(LuaManager.loaded);return;}scope.seeded=true;
        Map<Path,String> paths=new LinkedHashMap<>();
        Set<String> loaded=new HashSet<>(LuaManager.loaded);
        // Resolve overrides on the caller using the native list and native filesystem.
        for(String relative:new ArrayList<>(LuaManager.loadList)) {
            String absolute=ZomboidFileSystem.instance.getAbsolutePath(relative);
            if(absolute!=null && !loaded.contains(absolute.replace('\\','/'))){
                // RunLuaInternal resolves through getString, then splits only on '/'.
                // On Windows the native result can contain '\\', making its compiler
                // name the entire path. Preserve that exact native naming behavior.
                String resolved=ZomboidFileSystem.instance.getString(absolute.replace('\\','/'));
                paths.put(Path.of(absolute),resolved.substring(resolved.lastIndexOf('/')+1));
            }
        }
        if(!paths.isEmpty())scope.preparation=new LuaPreparation(paths,4,32);
    }
    public static Prototype take(int first,Reader reader,String name,String source)throws IOException {
        Scope scope=scopes.get();
        if(scope==null || scope.preparation==null || source!=null || FuncState.currentfullFile==null)return null;
        Prototype result=scope.preparation.take(FuncState.currentfullFile,name,first,reader,FuncState.currentFile,FuncState.currentfullFile);
        StartupPreparationPolicy.record(result==null?StartupPreparationPolicy.LUA_FALLBACK:StartupPreparationPolicy.LUA_HIT);
        return result;
    }
    @Patch(className="zombie.Lua.LuaManager",methodName="LoadDirBase",warmUp=true)
    public static final class ScopePatch {
        @Patch.OnEnter public static void enter(){LuaPreparationHooks.begin();}
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(){LuaPreparationHooks.end();}
    }
    @Patch(className="zombie.Lua.LuaManager",methodName="RunLuaInternal",warmUp=true,strictMatch=true)
    public static final class PreparePatch {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) String filename,@Patch.Argument(1) boolean rewriteEvents){LuaPreparationHooks.prepare();}
    }
    @Patch(className="org.luaj.kahluafork.compiler.LexState",methodName="compile",warmUp=true,strictMatch=true)
    public static final class CompilePatch {
        @Patch.OnEnter(skipOn=true) public static boolean enter(@Patch.Argument(0) int first,@Patch.Argument(1) Reader reader,@Patch.Argument(2) String name,@Patch.Argument(3) String source,@Patch.Local("prepared") Prototype prepared)throws IOException {
            prepared=LuaPreparationHooks.take(first,reader,name,source);return prepared!=null;
        }
        @Patch.OnExit public static void exit(@Patch.Local("prepared") Prototype prepared,@Patch.Return(readOnly=false) Prototype result){if(prepared!=null)result=prepared;}
    }
}
