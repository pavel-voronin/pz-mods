package me.pavel.modstudio;

import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;

/** External debug sessions only. No UI, network listener or dependency on a tested mod. */
@Exposer.LuaClass(name="ModStudioScenario")
public final class ScenarioHost {
    private static Map<String,Object> definition;
    private static String json;
    private static volatile String error="";
    private static Path output;
    private static boolean claimed,loading;
    private static volatile boolean closed,finishing;
    private static final ArrayBlockingQueue<Map<String,Object>> events=new ArrayBlockingQueue<>(4096);
    private static volatile String status="running",reason="";
    public static double clock(){return System.nanoTime()*1e-9;}
    public static String error(){return error;}
    public static boolean closed(){return closed;}
    public static boolean requested(){return !System.getProperty("modstudio.scenario","").isEmpty();}
    public static KahluaTable context() {
        if(!requested()||!zombie.core.Core.debug||zombie.network.GameClient.client||zombie.network.GameServer.server)return null;
        try {
            if(definition==null){
                Path path=Path.of(System.getProperty("modstudio.scenario"));
                if(Files.size(path)>262144)throw new IllegalArgumentException("Scenario exceeds 256 KiB");
                json=Files.readString(path);definition=ScenarioJson.parse(json);validate(definition);
                output=Path.of(System.getProperty("modstudio.scenario.output"));
            }
            return (KahluaTable)lua(Map.of("definition",definition,"json",json,"output",output.toString()));
        }catch(Exception e){error="Invalid scenario: "+e;return null;}
    }
    static void validate(Map<String,Object> root)throws Exception {
        if(number(root,"schema",0,1,1)!=1)throw new IllegalArgumentException("Expected schema 1");
        if(!ScenarioJson.string(root,"id").matches("[a-z0-9_-]{1,80}"))throw new IllegalArgumentException("Invalid id");
        var spawn=ScenarioJson.object(root.get("spawn"));number(spawn,"x",-1,0,100000);number(spawn,"y",-1,0,100000);number(spawn,"z",0,-32,31);
        double repeats=number(root,"repeats",1,1,20);if(repeats!=Math.rint(repeats))throw new IllegalArgumentException("Nonintegral repeats");
        if(!(root.get("steps") instanceof List<?> steps)||steps.isEmpty()||steps.size()>512)throw new IllegalArgumentException("Expected 1..512 steps");
        double budget=0;
        for(Object value:steps){var step=ScenarioJson.object(value);
            if(!ScenarioJson.string(step,"command").matches("[a-z][a-z0-9_]*\\.[a-z][a-zA-Z0-9_]*"))throw new IllegalArgumentException("Expected owner.command");
            double seconds=number(step,"seconds",0,0,600);budget+=number(step,"timeout",Math.max(30,seconds+5),.1,900);
        }
        if(budget*repeats>7200)throw new IllegalArgumentException("Scenario timeout budget exceeds two hours");
    }
    private static double number(Map<String,Object> m,String key,double fallback,double min,double max){
        Object v=m.get(key);double n=v==null?fallback:v instanceof Number x?x.doubleValue():Double.NaN;
        if(!Double.isFinite(n)||n<min||n>max)throw new IllegalArgumentException("Invalid "+key);return n;
    }
    private static Object lua(Object value){
        if(value instanceof Map<?,?> m){var t=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();m.forEach((k,v)->t.rawset(k,lua(v)));return t;}
        if(value instanceof List<?> a){var t=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();for(int i=0;i<a.size();i++)t.rawset((double)i+1,lua(a.get(i)));return t;}
        return value instanceof Number n?n.doubleValue():value;
    }
    public static synchronized boolean claim(){
        if(claimed||context()==null)return false;claimed=loading=true;
        Thread writer=new Thread(ScenarioHost::write,"ModStudio-scenario-artifacts");writer.setDaemon(true);writer.start();return true;
    }
    public static void worldReady(){loading=false;}
    public static void event(String kind,String detail){
        if(!claimed||finishing)return;
        if(!events.offer(Map.of("monotonic_ns",System.nanoTime(),"kind",kind,"detail",detail)))error="Scenario event queue overflow";
    }
    public static void finish(String result,String detail){if(finishing)return;status=result;reason=detail;finishing=true;loading=false;}
    private static void write(){
        try {
            Files.createDirectories(output);
            result("running","");
            try(var writer=Files.newBufferedWriter(output.resolve("events.jsonl"))){
                while(!finishing||!events.isEmpty()){
                    var event=events.poll(100,TimeUnit.MILLISECONDS);if(event!=null){writer.write(ScenarioJson.write(event));writer.flush();}
                }
            }
            result(error.isEmpty()?status:"failed",error.isEmpty()?reason:error);
        }catch(Exception e){error="Scenario artifact writer: "+e;try{result("failed",error);}catch(Exception ignored){}}
        finally{closed=true;}
    }
    private static void result(String state,String detail)throws Exception {
        var result=new LinkedHashMap<String,Object>();result.put("schema",1);result.put("scenario",definition.get("id"));result.put("status",state);result.put("reason",detail);
        result.put("utc",java.time.Instant.now().toString());result.put("output",output.toString());
        Path temp=output.resolve("scenario-result.tmp");Files.writeString(temp,ScenarioJson.write(result));
        Files.move(temp,output.resolve("scenario-result.json"),StandardCopyOption.REPLACE_EXISTING);
    }
    public static void autoContinue(zombie.gameStates.GameLoadingState state){
        if(!loading)return;zombie.core.Core.getInstance().setNoSave(true);
        try{var field=zombie.gameStates.GameLoadingState.class.getDeclaredField("forceDone");field.setAccessible(true);field.setBoolean(state,true);}
        catch(Exception e){error="Native loading gate: "+e;}
    }
    @Patch(className="zombie.gameStates.GameLoadingState",methodName="update",warmUp=true,strictMatch=true)
    public static class LoadingGate {
        @Patch.OnEnter public static void enter(@Patch.This zombie.gameStates.GameLoadingState state){ScenarioHost.autoContinue(state);}
    }
}
