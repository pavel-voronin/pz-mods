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
        var road=new ScenarioDriving.Route(10,100,10,0,40);
        var straight=road.control(10,90,0,-1,0);
        if(!straight.gas()||straight.brake()||Math.abs(straight.steering())>.001||straight.remaining()!=90)throw new AssertionError("Native driving acceleration");
        if(road.control(12,80,0,-1,40).steering()>=0||road.control(8,80,0,-1,40).steering()<=0)throw new AssertionError("Road-centre steering signs");
        if(!road.control(10,2,0,-1,20).brake()||road.control(10,2,0,-1,20).gas())throw new AssertionError("Stop at destination");
        if(!road.control(10,50,0,-1,60).brake())throw new AssertionError("Speed governor");
        for(double speed:new double[]{Double.NaN,0,101}){boolean rejected=false;try{new ScenarioDriving.Route(0,0,0,100,speed);}catch(IllegalArgumentException e){rejected=true;}if(!rejected)throw new AssertionError("Invalid speed");}
        boolean guarded=false;try{ScenarioDriving.spawn("Base.CarNormal",0);}catch(IllegalStateException e){guarded=true;}if(!guarded)throw new AssertionError("Normal world mutation");
        guarded=false;try{ScenarioHost.spawnHuman(0,-3);}catch(IllegalStateException e){guarded=true;}if(!guarded)throw new AssertionError("Human spawned outside a disposable scenario");
        ScenarioHost.clearHuman();ScenarioHost.clearHuman();
        guarded=false;try{ScenarioHost.screenshot("test");}catch(IllegalStateException e){guarded=true;}if(!guarded)throw new AssertionError("Screenshot outside disposable scenario");
        guarded=false;try{ScenarioDriving.spawnConfigured("Base.CarNormal",0,false,true);}catch(IllegalStateException e){guarded=true;}if(!guarded)throw new AssertionError("Parked car spawned outside a disposable scenario");
        ScenarioDriving.stop();ScenarioDriving.close();ScenarioDriving.close();
        var frames=new ScenarioDriving.Intervals();for(int i=0;i<99;i++)frames.add(16_000_000);frames.add(2_000_000_000L);
        if(frames.count!=100||frames.percentile(.95)!=16.1||frames.percentile(1)!=2000)throw new AssertionError("Bounded frame histogram and overflow");
        String mp="{\"schema\":1,\"id\":\"mp-test\",\"spawn\":{\"x\":10,\"y\":20},\"steps\":[{\"command\":\"native.networkPeer\"}],\"multiplayer\":{\"host\":\"127.0.0.1\",\"port\":16371,\"username\":\"TestA\",\"peer\":\"TestB\"}}";
        boolean mpRejected=false;try{ScenarioHost.validate(ScenarioJson.parse(mp));}catch(Exception e){mpRejected=true;}
        if(!mpRejected)throw new AssertionError("MP without explicit external launch accepted");
        System.setProperty("modstudio.scenario","test.json");System.setProperty("modstudio.scenario.multiplayer","true");
        ScenarioHost.validate(ScenarioJson.parse(mp));
        for(String bad:List.of(mp.replace("127.0.0.1","example.org"),mp.replace("TestA","../user"),mp.replace("16371","0"),mp.replace("16371","16371.5"),mp.replace("\"steps\"","\"manual\":true,\"steps\""))){
            mpRejected=false;try{ScenarioHost.validate(ScenarioJson.parse(bad));}catch(Exception e){mpRejected=true;}
            if(!mpRejected)throw new AssertionError("Unsafe MP context accepted");
        }
        System.clearProperty("modstudio.scenario");System.clearProperty("modstudio.scenario.multiplayer");
        boolean signalGuard=false;try{ScenarioHost.signal("ready");}catch(IllegalStateException e){signalGuard=true;}
        if(!signalGuard||ScenarioHost.resume())throw new AssertionError("MP state outside an owned client");
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
            "local handed=false;local state={};ClimbThroughWindowState={instance=function() return state end};local climbing=false;local x=10.5;local w={IsOpen=function() return true end,getNorth=function() return false end};instanceof=function(o,kind) return o==w and kind=='IsoWindow' end;getCell=function() return {getGridSquare=function() return {getObjects=function() return {size=function() return 1 end,get=function() return w end} end} end} end;ISWorldObjectContextMenu={onClimbThroughWindow=function() assert(handed,'native climb requested before motion handoff');requestedClimb=true end};local c={player={getX=function() return x end,getY=function() return 20.5 end,getPlayerNum=function() return 0 end,getSquare=function() return {} end,isCurrentState=function() return climbing end,getUsername=function() return 'TestA' end,getOnlineID=function() return 1 end,getZ=function() return 0 end,isRunning=function() return false end,isMoving=function() return false end},nativeAction=function(action) assert(action=='timedAction');handed=true end,event=function() end};local cmd=ModStudio.Network.commands.climb;local step={x=10,y=20};cmd.start(c,step);assert(not cmd.tick(c,step,0) and requestedClimb);climbing=true;x=9.9;assert(not cmd.tick(c,step,1));climbing=false;x=9.8;assert(cmd.tick(c,step,2))",
            "local handed=false;local open=false;local w={IsOpen=function() return open end,isLocked=function() return false end};instanceof=function(o,kind) return o==w and kind=='IsoWindow' end;getCell=function() return {getGridSquare=function() return {getObjects=function() return {size=function() return 1 end,get=function() return w end} end} end} end;ISWorldObjectContextMenu={onOpenCloseWindow=function() assert(handed,'native window requested before motion handoff');open=true end};local c={player={getX=function() return 10.5 end,getY=function() return 20.5 end,getPlayerNum=function() return 0 end,isBlockMovement=function() return not handed end},nativeAction=function(action) assert(action=='timedAction');handed=true end,event=function() end};local cmd=ModStudio.Network.commands.window;local step={x=10,y=20,open=true,change=true};cmd.start(c,step);assert(cmd.tick(c,step,0) and open)",
            "local calls=0;triggerEvent=function(name,forced) assert(name=='OnPZ3DUiActions' and forced);calls=calls+1 end;ModStudio.Scenarios.providers.pz3d.nativeAction({},'timedAction',{});assert(calls==1)",
            "local all={};local inv={getItems=function() return {size=function() return #all end,get=function(_,i) return all[i+1] end} end};local c={player={getUsername=function() return 'TestA' end,getInventory=function() return inv end},event=function() end};local s={type='Base.Screwdriver'};SendCommandToServer=function(v) issuedCommand=v end;ModStudio.Network.give(c,s);assert(issuedCommand=='/additem \"TestA\" \"Base.Screwdriver\"' and ModStudio.Network.given(c,s)==nil);all[1]={getFullType=function() return s.type end,getID=function() return 7 end};assert(ModStudio.Network.given(c,s)==all[1]);assert(not pcall(ModStudio.Network.give,c,{type='Base.Screwdriver;quit'}))",
            "assert(not pcall(ModStudio.Network.commands.window.validate,{x=10.5,y=20,open=true}));assert(not pcall(ModStudio.Network.commands.window.validate,{x=10,y=20,open=true,change='true'}));assert(not pcall(ModStudio.Network.commands.item.validate,{type='Base.Screwdriver',pickup='true'}));assert(not pcall(ModStudio.Network.commands.observe.validate,{seconds=1,distance=-1}));assert(pcall(ModStudio.Network.commands.window.validate,{x=10,y=20,open=true,change=true}))",
            "local provider=ModStudio.Scenarios.providers.pz3d;local t=0;local c={definition={multiplayer={},steps={{command='pz3d.move'}}},clock=function() return t end,event=function() end};local focuses=0;ModStudioScenario.focus=function() focuses=focuses+1 end;assert(not provider.begin(c) and not ownedControl);t=2;assert(not provider.begin(c) and not ownedControl);t=14;assert(not provider.begin(c) and not ownedControl);for i=1,35 do t=t+.1;provider.begin(c) end;assert(ownedControl and focuses==1)",
            "local provider=ModStudio.Scenarios.providers.pz3d;local t=0;local c={definition={multiplayer={},steps={{command='pz3d.connection'},{command='pz3d.permission'}}},clock=function() return t end,event=function() end};ModStudioScenario.focus=function() error('passive observer took foreground') end;for i=1,45 do t=t+.1;provider.begin(c) end;assert(c.mpPassive and not ownedControl);provider.update(c)",
            "local p={getSquare=function() return {} end,getUsername=function() return 'TestB' end,getOnlineID=function() return 2 end,getX=function() return 10 end,getY=function() return 20 end,getZ=function() return 0 end,isRunning=function() return false end,isMoving=function() return false end};getOnlinePlayers=function() return {size=function() return 1 end,get=function() return p end} end;local c={definition={multiplayer={peer='TestB'}},player={getOnlineID=function() return 1 end},event=function() end};local expected={x=11,y=20,z=0,onlineID=2};ModStudioScenario.checkpoint=function() return expected end;local cmd=ModStudio.Network.commands.peer;assert(not cmd.tick(c,{checkpoint='settled',tolerance=.35},0));ModStudioScenario.checkpoint=function() return nil end;assert(not cmd.tick(c,{checkpoint='settled'},0));ModStudioScenario.checkpoint=function() return expected end;expected.x=10;assert(cmd.tick(c,{checkpoint='settled',tolerance=.35},0));expected.onlineID=3;assert(not pcall(cmd.tick,c,{checkpoint='settled'},0))",

            "isClient=function() return true end;getPlayer=function() return nil end;ConnectToServer={instance={}};MainScreen={instance={}};ModStudio.Network.bootstrap({event=function() end});assert(true)",
            "isClient=function() return true end;ModStudio.Network.bootstrap({event=function() error('bootstrap ran after world ready') end});assert(true)",
            "assert(not pcall(ModStudio.Network.commands.barrier.validate,{name='../escape'}));assert(pcall(ModStudio.Network.commands.barrier.validate,{name='world-ready'}))",
            "scenario={steps={{command='native.screenshot',name='native-view'}}};Events.OnMainMenuEnter.fire();pump(15);assert(ended=='complete' and screenshotName=='native-view' and screenshotPolls>=3)",
            "scenario={steps={{command='native.screenshot',name='../bad'}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and screenshotName==nil)",
            "scenario={steps={{command='native.weather',fog=1,rain=0,cloud=.6},{command='native.wait',seconds=1}}};Events.OnMainMenuEnter.fire();pump(4);assert(weatherValues[5].enabled and weatherValues[5].value==1);pump(25);assert(ended=='complete');for _,v in pairs(weatherValues) do assert(not v.enabled and v.value==.2) end",
            "scenario={steps={{command='native.weather',fog=2,rain=0,cloud=0}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and not weatherValues[5].enabled)",
            "scenario={steps={{command='native.weather',fog=1,rain=0,cloud=.6,wind=.8,windAngle=-.5},{command='native.wait',seconds=1}}};Events.OnMainMenuEnter.fire();pump(4);assert(weatherValues[6].enabled and weatherValues[6].value==.8 and weatherValues[7].value==-.5);pump(25);assert(ended=='complete');for _,v in pairs(weatherValues) do assert(not v.enabled and v.value==.2) end",
            "scenario={steps={{command='native.weather',fog=1,rain=0,cloud=0,windAngle=2}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and not weatherValues[7].enabled)",
            "core.isNoSave=function() return false end;scenario={steps={{command='native.weather',fog=1,rain=0,cloud=0}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and not weatherValues[5].enabled)",
            "humanReady=true;scenario={steps={{command='native.human',dx=3,dy=0},{command='native.humanLight',on=true,heading=90},{command='native.wait',seconds=1},{command='native.humanLight',on=false,heading=-90}}};Events.OnMainMenuEnter.fire();pump(5);assert(humanLightOn and humanHeading==90);pump(25);assert(ended=='complete' and humanLightOn==false and humanHeading==-90 and humanCleared)",
            "scenario={steps={{command='native.humanLight',on=true,heading=181}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='failed' and not humanLightOn)",
            "scenario={steps={{command='native.humanLight',on=true,heading=0}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='failed' and not humanLightOn)",
            "animalRendered=true;scenario={steps={{command='native.animals',all=true},{command='pz3d.animalsReady'}}};Events.OnMainMenuEnter.fire();pump(20);assert(ended=='complete' and #spawnedAnimals==3);for _,a in ipairs(spawnedAnimals) do assert(a.added and a.removed and a.squareRemoved) end",
            "scenario={steps={{command='native.animals',type='cow',dx=0,dy=-4}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='complete' and #spawnedAnimals==1 and spawnedAnimals[1]:getAnimalType()=='cow' and spawnedAnimals[1].removed)",
            "scenario={steps={{command='native.animals',type='missing',dx=0,dy=-4}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and #spawnedAnimals==0)",
            "scenario={steps={{command='native.killAnimals'}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed')",
            "animalFailure=true;scenario={steps={{command='native.animals',all=true}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and #spawnedAnimals==1 and spawnedAnimals[1].removed)",
            "animalBlocked=true;scenario={steps={{command='native.animals',all=true}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and #spawnedAnimals==0)",
            "scenario={steps={{command='native.animals',all=true},{command='pz3d.animalsReady',timeout=1}}};Events.OnMainMenuEnter.fire();pump(30);assert(ended=='failed' and spawnedAnimals[1].removed)",
            "local s={id='fire',kind='fireplace',dx=3,dy=0,on=true,tile='crafted_02_42'};ModStudioScenarioLights.fixture.validate(s);s.tile='../bad';assert(not pcall(ModStudioScenarioLights.fixture.validate,s));s.tile='crafted_02_42';s.kind='campfire';assert(not pcall(ModStudioScenarioLights.fixture.validate,s))",
            "local lamps=ModStudioScenarioLights.galleryLayout(7102,7100);assert(#lamps==19);local names={};for i,a in ipairs(lamps) do assert(not names[a.tile]);names[a.tile]=true;for j,b in ipairs(lamps) do if i~=j then assert((a.x-b.x)^2+(a.y-b.y)^2>=2500) end end;if i>1 then local b=lamps[i-1];assert(math.abs(a.x-b.x)+math.abs(a.y-b.y)==50) end end;assert(lamps[1].z==0 and lamps[5].z==1 and lamps[14].crossarm and lamps[19].tile=='appliances_com_01_141');for i=14,19 do local a=lamps[i];local p=ModStudioScenarioLights.galleryParts(a);assert(a.z==1 and #p==3 and p[1].z==0 and p[2].z==1 and p[3].z==2);local x=i==15 or i==16 or i==19;assert(p[1].tile=='appliances_com_01_'..(x and 88 or 94) and p[2].tile=='appliances_com_01_'..(x and 89 or 95) and p[3].tile=='appliances_com_01_'..(x and 93 or 92)) end;assert(not pcall(ModStudioScenarioLights.gallery.validate,{x=-1}));assert(not pcall(ModStudioScenarioLights.gallery.start,{definition={manual=false}},{}))",
            "core.isNoSave=function() return false end;scenario={steps={{command='native.animals',all=true}}};Events.OnMainMenuEnter.fire();pump(10);assert(ended=='failed' and #spawnedAnimals==0)",
            "humanReady=true;scenario={steps={{command='native.human',dx=0,dy=-3},{command='native.wait',seconds=1}}};Events.OnMainMenuEnter.fire();pump(3);assert(humanSpawned and humanOffset[2]==-3);pump(20);assert(ended=='complete' and humanCleared and not humanSpawned)",
            "scenario={steps={{command='native.human',dx=0,dy=0}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='failed' and not humanSpawned)",
            "scenario={steps={{command='native.human',dx=0,dy=-3,timeout=1}}};Events.OnMainMenuEnter.fire();pump(3);advance(2);pump(8);assert(ended=='failed' and humanCleared and not humanSpawned)",
            "humanFailure=true;scenario={steps={{command='native.human',dx=0,dy=-3}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='failed' and humanCleared and not humanSpawned)",
            "humanReady=true;scenario={steps={{command='native.human',dx=0,dy=-3},{command='native.clearHuman'},{command='native.clearHuman'},{command='native.human',dx=3,dy=0}}};Events.OnMainMenuEnter.fire();pump(20);assert(ended=='complete' and humanCleared and not humanSpawned)",
            "scenario={steps={{command='pz3d.diagnostics',enabled=true},{command='pz3d.worldWarp',mode=3,lateral=200,vertical=150,scale=1000,near=160},{command='native.wait',seconds=.2}}};Events.OnMainMenuEnter.fire();pump(5);assert(PZ3D.cameraDebugState().warpMode==3);pump(40);local w=PZ3D.cameraDebugState();assert(quit and ended=='complete' and w.warpMode==0 and w.warpLateral==100 and w.warpScale==2400)",
            "scenario={steps={{command='pz3d.worldWarp',mode=3,near=159}}};Events.OnMainMenuEnter.fire();pump(5);assert(quit and ended=='failed' and PZ3D.cameraDebugState().warpMode==0)",
            "scenario={steps={{command='pz3d.diagnostics',enabled=true},{command='pz3d.worldWarp',mode=2},{command='native.wait',seconds=100}}};Events.OnMainMenuEnter.fire();pump(5);assert(PZ3D.cameraDebugState().warpMode==2);interruption='focus lost';pump(40);assert(quit and ended=='failed' and PZ3D.cameraDebugState().warpMode==0)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=-90},{command='native.drive',x=1,y=100,kmh=40},{command='native.wait',seconds=1}}};Events.OnMainMenuEnter.fire();pump(6);assert(carSpawned and driving and ended==nil);driveReady=true;pump(20);assert(ended=='complete' and carClosed and not driving)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,enter=false,headlights=true,x=10.5,y=20.5}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='complete' and carX==10.5 and carY==20.5 and carEntry==false and carHeadlights==true and carClosed)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,x=10}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='failed' and not carSpawned)",
            "ModStudioDriving.spawnConfiguredAt=nil;scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,x=10,y=20}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='failed' and not carSpawned)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,enter=false,headlights=true},{command='native.wait',seconds=.2}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='complete' and carSpawned and carEntry==false and carHeadlights==true and carClosed)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,enter=true,headlights=false}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='complete' and carEntry==true and carHeadlights==false and carClosed)",
            "configuredSpawnFailure=true;scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,enter=false,headlights=true}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='failed' and carClosed)",
            "ModStudioDriving.spawnConfigured=nil;scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,enter=false}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='failed' and not carSpawned)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,enter='no'}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='failed' and not carSpawned)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0,headlights=1}}};Events.OnMainMenuEnter.fire();pump(12);assert(ended=='failed' and not carSpawned)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=200}}};Events.OnMainMenuEnter.fire();pump(6);assert(ended=='failed' and not carSpawned)",
            "scenario={steps={{command='native.drive',x=1,y=100,kmh=40}}};Events.OnMainMenuEnter.fire();pump(6);assert(ended=='failed' and not driving)",
            "scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0},{command='native.drive',x=1,y=100,kmh=40,timeout=1}}};Events.OnMainMenuEnter.fire();pump(4);assert(driving);advance(2);pump(8);assert(ended=='failed' and carClosed and not driving)",
            "spawnFailure=true;scenario={steps={{command='native.vehicle',script='Base.CarNormal',heading=0}}};Events.OnMainMenuEnter.fire();pump(8);assert(ended=='failed' and carClosed and not driving)",
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
            "scenario={steps={{command='native.give',id='lighter',type='Base.Lighter'},{command='native.equip',id='lighter',slot='secondary'},{command='native.equip',slot='none'}}};Events.OnMainMenuEnter.fire();pump(18);assert(quit and ended=='complete' and modelResets==2 and #inventory.items==0 and player.primary.original and player.secondary.original)",
            "scenario={steps={{command='native.equip',id='unknown',slot='primary'}}};Events.OnMainMenuEnter.fire();pump(8);assert(quit and ended=='failed' and player.primary.original)",
            "scenario={steps={{command='native.lightFixture',id='fire',kind='campfire',dx=0,dy=0,on=true}}};Events.OnMainMenuEnter.fire();pump(5);assert(quit and ended=='failed')",
            "core.isNoSave=function() return false end;local c={};local ok=pcall(ModStudioScenarioLights.fixture.start,c,{id='fire',kind='campfire',dx=3,dy=0,on=true});assert(not ok and c.lightFixtures==nil)",
            "local removed=0;local c={lightFixtures={partial={},object={object={getSquare=function() return {transmitRemoveItemFromSquare=function() removed=removed+1 end} end}}}};ModStudioScenarioLights.clear(c);ModStudioScenarioLights.clear(c);assert(removed==1 and c.lightFixtures==nil)",
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
            for(String code:List.of(fixture,api,"local animals=(function()\n"+Files.readString(lua.resolve("ScenarioAnimals.lua"))+"\nend)()",Files.readString(lua.resolve("ScenarioLights.lua")),Files.readString(lua.resolve("ScenarioMultiplayer.lua")),runtime,adapter,check))run(thread,env,code);
        }
        System.out.println("PASS: bounded schema, native-only launch, item cleanup, teleport, timeout, unknown commands, independent diagnostics, PZ3D route failure, interruption and automatic exit.");
    }
}
