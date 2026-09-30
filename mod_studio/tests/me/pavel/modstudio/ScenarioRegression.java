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
        // Preset shortcuts share the native loading gate without forcing NoSave.
        var gatePlatform=J2SEPlatform.getInstance();
        var gateEnv=gatePlatform.newEnvironment();
        var studio=gatePlatform.newTable();var launch=gatePlatform.newTable();
        studio.rawset("Launch",launch);gateEnv.rawset("ModStudio",studio);
        var previousEnv=zombie.Lua.LuaManager.env;
        var core=zombie.core.Core.getInstance();boolean previousNoSave=core.isNoSave();
        var state=new zombie.gameStates.GameLoadingState();
        var forceDone=state.getClass().getDeclaredField("forceDone");forceDone.setAccessible(true);
        try {
            zombie.Lua.LuaManager.env=gateEnv;
            for(boolean noSave:new boolean[]{false,true}) {
                core.setNoSave(noSave);
                for(boolean enabled:new boolean[]{false,true,false}) {
                    forceDone.setBoolean(state,false);launch.rawset("autoContinueLoading",enabled);
                    ScenarioHost.autoContinue(state);
                    if(forceDone.getBoolean(state)!=enabled || core.isNoSave()!=noSave)
                        throw new AssertionError("Shortcut loading gate or save mode isolation");
                }
            }
        } finally {zombie.Lua.LuaManager.env=previousEnv;core.setNoSave(previousNoSave);}
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
            "local a=testVehicle(2,3);local b=testVehicle(3,4);local outside=testVehicle(20,20);scenario={steps={{command='native.clearVehicles',x0=1,y0=1,x1=4,y1=5}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='complete' and a.removed and b.removed and not outside.removed and #vehicles==1)",
            "scenario={steps={{command='native.clearVehicles',x0=1,y0=1,x1=300,y1=5}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='failed')",
            "core.isNoSave=function() return false end;local a=testVehicle(2,3);scenario={steps={{command='native.clearVehicles',x0=1,y0=1,x1=4,y1=5}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='failed' and not a.removed)",
            "player:setInvisible(false);scenario={steps={{command='native.playerFlags',invisible=true},{command='native.wait',seconds=1}}};Events.OnMainMenuEnter.fire();pump(3);assert(player.invisible and player.ghost);pump(20);assert(quit and ended=='complete' and not player.invisible and not player.ghost)",
            "scenario={steps={{command='native.playerFlags',invisible='yes'}}};Events.OnMainMenuEnter.fire();pump(5);assert(quit and ended=='failed' and player.invisible and player.ghost)",
            "player:setInvisible(false);scenario={steps={{command='native.playerFlags',invisible=true},{command='native.wait',seconds=10,timeout=1}}};Events.OnMainMenuEnter.fire();pump(3);assert(player.invisible);advance(2);pump(5);assert(quit and ended=='failed' and not player.invisible and not player.ghost)",
            "scenario={steps={{command='pz3d.visualConditions',action='install'},{command='pz3d.visualConditions',action='b'}}};Events.OnMainMenuEnter.fire();pump(12);assert(quit and ended=='complete' and visualAction==nil and visualClears>0)",
            "scenario={steps={{command='pz3d.diagnostics',enabled=true},{command='pz3d.interaction',action='select',kind='door',radius=2},{command='pz3d.interaction',action='toggle'}}};Events.OnMainMenuEnter.fire();pump(45);assert(quit and ended=='complete' and interactionAction==nil and interactionClears>0)",
            "scenario={steps={{command='pz3d.interaction',action='select',kind='door',radius=9}}};Events.OnMainMenuEnter.fire();pump(6);assert(quit and ended=='failed' and interactionAction==nil)",
            "interactionReady=false;scenario={steps={{command='pz3d.diagnostics',enabled=true},{command='pz3d.interaction',action='toggle',timeout=1}}};Events.OnMainMenuEnter.fire();pump(4);advance(2);pump(45);assert(quit and ended=='failed' and interactionAction==nil and interactionClears>0)",
            "scenario={steps={{command='pz3d.visualConditions',action='unknown'}}};Events.OnMainMenuEnter.fire();pump(5);assert(quit and ended=='failed' and visualAction==nil)",
            "visualReady=false;scenario={steps={{command='pz3d.visualConditions',action='install',timeout=1}}};Events.OnMainMenuEnter.fire();pump(3);assert(visualAction=='install' and not quit);advance(2);pump(5);assert(quit and ended=='failed' and visualAction==nil and visualClears>0)",
            "scenario={steps={{command='pz3d.lighting',mode='hybrid',torch=false}}};Events.OnMainMenuEnter.fire();pump(8);assert(quit and ended=='complete' and lightingMode=='current' and lightingResets>0)",
            "lightingReady=false;scenario={steps={{command='pz3d.lighting',mode='native',timeout=1}}};Events.OnMainMenuEnter.fire();pump(3);assert(lightingMode=='native' and not quit);advance(2);pump(5);assert(quit and ended=='failed' and lightingMode=='current' and lightingResets>0)",
            "scenario={steps={{command='native.give',id='torch',type='Base.HandTorch',equip='secondary',charge=1},{command='native.torch',id='torch',on=true},{command='native.teleport',x=3,y=4,z=1},{command='native.wait',seconds=.2}}}; local old=player.secondary;Events.OnMainMenuEnter.fire();pump(20);assert(quit and ended=='complete' and player.secondary==old and player.ghost and player.sneaking and #inventory.items==0 and teleports==1)",
            "scenario={steps={{command='pz3d.look',yaw=0},{command='native.teleport',x=3.5,y=4.5,z=0}}};Events.OnMainMenuEnter.fire();pump(10);assert(quit and ended=='complete' and adopted==1 and player.x==3 and player.y==4)",
            "scenario={steps={{command='missing.command'}}};Events.OnMainMenuEnter.fire();pump(5);assert(quit and ended=='failed' and string.find(reason,'Unregistered'))",
            "scenario={steps={{command='pz3d.chunkMode',mode='isometry'},{command='native.time',hour=12,freeze=true},{command='pz3d.chunkArm',name='cold',x=80,y=80},{command='native.teleport',x=80,y=80},{command='pz3d.chunkAwait',timeout=10}}};Events.OnMainMenuEnter.fire();pump(8);assert(chunkActive and not ownedControl and camera==0 and not quit);chunkReady=true;pump(8);assert(quit and ended=='complete' and chunkFlushes==1 and chunkResult=='complete' and chunkReset)",
            "scenario={steps={{command='pz3d.chunkMode',mode='isometry'},{command='native.time',hour=12,freeze=true},{command='pz3d.chunkArm',name='cold',x=80,y=80},{command='pz3d.chunkAwait',timeout=.2}}};Events.OnMainMenuEnter.fire();pump(15);assert(quit and ended=='failed' and chunkFlushes==1 and chunkResult=='failed' and chunkReset)",
            "scenario={steps={{command='pz3d.chunkMode',mode='isometry'},{command='pz3d.chunkArm',name='cold',x=80,y=80}}};Events.OnMainMenuEnter.fire();pump(10);assert(quit and ended=='failed' and not chunkActive and chunkReset)",
            "PZ3D.scenarioChunkFinish=function() error('writer failed') end;scenario={steps={{command='pz3d.chunkMode',mode='isometry'},{command='native.wait',seconds=.1}}};Events.OnMainMenuEnter.fire();pump(10);assert(quit and ended=='failed' and chunkReset and not ownedControl and camera==1)",
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
