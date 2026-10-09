package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.Event;
import zombie.debug.DebugOptions;
import java.util.*;
import java.lang.invoke.*;
import se.krka.kahlua.profiler.*;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.Prototype;

/** Temporarily use the game's own slow-callback diagnostics for startup events. */
public final class StartupLuaDiagnostics {
    public static final class Scope implements AutoCloseable {
        private final boolean before;private boolean closed;private Sampling sampling;
        Scope(String name){
            before=DebugOptions.instance.checks.slowLuaEvents.getValue();DebugOptions.instance.checks.slowLuaEvents.setValue(true);
            if("OnMainMenuEnter".equals(name) && Boolean.getBoolean("modstudio.startup.luaSampling") && zombie.Lua.LuaManager.thread!=null){
                try{sampling=new Sampling(zombie.Lua.LuaManager.thread);}catch(RuntimeException error){System.out.println("[ModStudioStartup] Lua sampler unavailable: "+error);}
            }
        }
        @Override public void close(){
            if(closed)return;closed=true;
            try{if(sampling!=null){sampling.close();sampling.print();}}
            finally{if(DebugOptions.instance.checks.slowLuaEvents.getValue())DebugOptions.instance.checks.slowLuaEvents.setValue(before);}
        }
    }
    /** Native Kahlua sampling, bounded aggregation; no changes to Lua execution. */
    static final class Sampling implements Profiler,AutoCloseable {
        private static final VarHandle PROTOTYPE=prototypeField();
        private static VarHandle prototypeField(){
            try{return MethodHandles.privateLookupIn(LuaStacktraceElement.class,MethodHandles.lookup()).findVarHandle(LuaStacktraceElement.class,"prototype",Prototype.class);}
            catch(ReflectiveOperationException unsupported){return null;}
        }
        private final Sampler sampler;
        private final Map<String,Integer> leaf=new HashMap<>(),inclusive=new HashMap<>();
        private boolean closed;private int samples,empty,dropped;
        Sampling(KahluaThread thread){sampler=new Sampler(thread,10,this);sampler.start();}
        @Override public synchronized void getSample(Sample sample){
            if(closed)return;
            try{
                List<StacktraceElement> stack=sample.getList();
                if(stack.isEmpty()){empty++;return;}
                Set<String> unique=new HashSet<>();String first=null;
                for(StacktraceElement frame:stack){String key=label(frame);if(first==null)first=key;unique.add(key);}
                increment(leaf,first);for(String key:unique)increment(inclusive,key);samples++;
            }catch(RuntimeException staleFrame){dropped++;}
        }
        private static void increment(Map<String,Integer> map,String key){if(map.size()<512 || map.containsKey(key))map.merge(key,1,Integer::sum);}
        private static String label(StacktraceElement frame){
            if(frame instanceof LuaStacktraceElement lua && PROTOTYPE!=null){
                Prototype prototype=(Prototype)PROTOTYPE.get(lua);
                return "lua:"+prototype.filename+":"+lua.getLine()+" "+prototype.name;
            }
            return frame.type()+":"+frame.name();
        }
        synchronized int sampleCount(){return samples;}
        @Override public void close(){sampler.stop();synchronized(this){closed=true;}}
        synchronized void print(){
            System.out.println("[ModStudioStartup] Lua menu samples="+samples+" empty="+empty+" dropped="+dropped+" intervalMs=10; sample counts are not exact CPU durations");
            printRows("leaf",leaf);printRows("inclusive",inclusive);
        }
        private static void printRows(String kind,Map<String,Integer> map){
            map.entrySet().stream().sorted(Map.Entry.<String,Integer>comparingByValue().reversed().thenComparing(Map.Entry.comparingByKey())).limit(15)
                .forEach(row->System.out.println("[ModStudioStartup] Lua menu "+kind+" samples="+row.getValue()+" "+row.getKey()));
        }
    }
    public static Scope begin(String name){
        if(!zombie.core.Core.debug || !StartupPreparationPolicy.enabled("diagnostics"))return null;
        if(!"OnMainMenuEnter".equals(name) && !"OnGameBoot".equals(name) && !"OnLoadSoundBanks".equals(name))return null;
        return new Scope(name);
    }
    @Patch(className="zombie.Lua.Event",methodName="trigger",warmUp=true,strictMatch=true)
    public static final class EventPatch {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) se.krka.kahlua.vm.KahluaTable environment,@Patch.This Event event,@Patch.Local("scope") Scope scope){scope=StartupLuaDiagnostics.begin(event.name);}
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("scope") Scope scope){if(scope!=null)scope.close();}
    }
}
