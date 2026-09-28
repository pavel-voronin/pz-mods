package me.pavel.modstudio;
import java.nio.file.*;
import java.util.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

public final class ScenarioRegression {
    static void run(KahluaThread thread,KahluaTable env,String code)throws Exception {
        var result=thread.pcall(LuaCompiler.loadstring(code,"scenario-test",env),new Object[0]);
        if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(Arrays.toString(result));
    }
    public static void main(String[] args)throws Exception {
        Path root=Path.of(args[0]),pz=Path.of(args[1]);
        String valid="{\"schema\":1,\"id\":\"test\",\"spawn\":{\"x\":1,\"y\":2},\"steps\":[{\"command\":\"native.wait\",\"seconds\":1}]}";
        ScenarioHost.validate(ScenarioJson.parse(valid));
        for(String bad:List.of(valid.replace("native.wait","wait"),valid.replace("\"schema\":1","\"schema\":1.2"),valid.replace("\"id\":\"test\"","\"id\":\"test\",\"repeats\":1.5"))) {
            boolean rejected=false;try{ScenarioHost.validate(ScenarioJson.parse(bad));}catch(Exception e){rejected=true;}if(!rejected)throw new AssertionError("Invalid scenario accepted");
        }
        String fixture=Files.readString(root.resolve("tests/fixtures/scenario-runtime.lua"));
        Path lua=root.resolve("Contents/mods/mod_studio/common/media/lua/client/ModStudio");
        String api=Files.readString(lua.resolve("ScenarioAPI.lua")),runtime=Files.readString(lua.resolve("Scenarios.lua"));
        String adapter=Files.readString(pz.resolve("Contents/mods/pz3d/common/media/lua/client/PZ3DScenarioAPI.lua"));
        for(String check:List.of(
            "scenario={steps={{command='native.give',id='torch',type='Base.HandTorch',equip='secondary',charge=1},{command='native.torch',id='torch',on=true},{command='native.teleport',x=3,y=4,z=1},{command='native.wait',seconds=.2}}}; local old=player.secondary;Events.OnMainMenuEnter.fire();pump(20);assert(quit and ended=='complete' and player.secondary==old and player.ghost and player.sneaking and #inventory.items==0 and teleports==1)",
            "scenario={steps={{command='missing.command'}}};Events.OnMainMenuEnter.fire();pump(5);assert(quit and ended=='failed' and string.find(reason,'Unregistered'))",
            "scenario={steps={{command='native.wait',seconds=10,timeout=1}}};Events.OnMainMenuEnter.fire();advance(.1);advance(2);pump(4);assert(quit and ended=='failed' and string.find(reason,'Timeout'))",
            "scenario={steps={{command='native.wait',seconds=90}}};Events.OnMainMenuEnter.fire();advance(.1);advance(65);assert(not ended);advance(26);pump(4);assert(quit and ended=='complete')",
            "scenario={steps={{command='pz3d.diagnostics',enabled=true},{command='pz3d.measure',seconds=.2},{command='pz3d.diagnostics',enabled=false},{command='pz3d.look',yaw=1}}};Events.OnMainMenuEnter.fire();pump(10);assert(diag);pump(40);assert(quit and ended=='complete' and not diag and not ownedControl)",
            "scenario={steps={{command='pz3d.move',x=20,y=2,z=0}}};Events.OnMainMenuEnter.fire();pump(3);assert(motion==1 and not diag);advance(6);pump(4);assert(quit and ended=='failed' and motion==0 and teleports==0 and not ownedControl)",
            "scenario={steps={{command='pz3d.diagnostics',enabled=true},{command='pz3d.measure',seconds=10}}};Events.OnMainMenuEnter.fire();pump(3);interruption='focus lost';pump(40);assert(quit and ended=='failed' and not diag and not ownedControl)")) {
            var platform=J2SEPlatform.getInstance();var env=platform.newEnvironment();var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
            for(String code:List.of(fixture,api,runtime,adapter,check))run(thread,env,code);
        }
        System.out.println("PASS: bounded schema, native-only launch, item cleanup, teleport, timeout, unknown commands, independent diagnostics, PZ3D route failure, interruption and automatic exit.");
    }
}
