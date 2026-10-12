package me.pavel.modstudio;
import java.nio.file.*;
import java.util.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

public final class ScenarioDisplayRegression {
    private static void run(KahluaThread vm,KahluaTable env,String code)throws Exception{
        var result=vm.pcall(LuaCompiler.loadstring(code,"display-regression",env),new Object[0]);
        if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(Arrays.toString(result));
    }
    public static void main(String[] args)throws Exception{
        Path root=Path.of(args[0]),lua=root.resolve("Contents/mods/mod_studio/common/media/lua/client/ModStudio");
        var platform=J2SEPlatform.getInstance();var env=platform.newEnvironment();var vm=new KahluaThread(platform,env);vm.debugOwnerThread=Thread.currentThread();
        run(vm,env,Files.readString(root.resolve("tests/fixtures/scenario-runtime.lua")));
        for(String name:List.of("ScenarioAPI","ScenarioAnimals","ScenarioLights","ScenarioObjects","ScenarioMultiplayer","ScenarioRoute","Scenarios"))run(vm,env,Files.readString(lua.resolve(name+".lua")));
        run(vm,env,"""
            local cmd=ModStudio.Scenarios.commands['native.expectDisplay']
            assert(not pcall(cmd.validate,{width=1920,height=0/0}))
            assert(not pcall(cmd.validate,{width=1920.5,height=1200}))
            local s={width=1920,height=1200};cmd.validate(s)
            local verified=0;local c={event=function() verified=verified+1 end}
            ModStudioScenario.expectDisplay=function() return 'Display mismatch: 1920x1164' end
            assert(not pcall(cmd.start,c,s) and verified==0)
            ModStudioScenario.expectDisplay=function() return nil end
            assert(not pcall(cmd.start,c,s) and verified==0)
            ModStudioScenario.expectDisplay=function(w,h) assert(w==1920 and h==1200);return '' end
            assert(pcall(cmd.start,c,s) and verified==1)
            """);
        run(vm,env,"""
            local cmd=ModStudio.Scenarios.commands['native.driveReview']
            local s={x=10,y=20,kmh=40,interval=2,prefix='drive'};cmd.validate(s)
            assert(not pcall(cmd.validate,{x=10,y=20,kmh=40,interval=.1,prefix='drive'}))
            assert(not pcall(cmd.validate,{x=10,y=20,kmh=40,interval=2,prefix='../drive'}))
            local t=0;local captures={};local ready=false;local finished=false;local phase
            ModStudioScenario.screenshot=function(name) captures[#captures+1]=name;ready=false end
            ModStudioScenario.screenshotReady=function() return ready end
            ModStudioDriving.poll=function() return finished end
            local c={nativeDriving=true,player=player,clock=function() return t end,event=function() end,phase=function(name) phase=name end}
            cmd.start(c,s);assert(phase=='REVIEW' and not cmd.tick(c,s) and #captures==0)
            t=2;assert(not cmd.tick(c,s) and captures[1]=='drive-1')
            t=4;assert(not cmd.tick(c,s) and #captures==1)
            ready=true;assert(not cmd.tick(c,s) and captures[2]=='drive-2')
            ready=true;finished=true;assert(cmd.tick(c,s) and c.drivingReview==nil)
            finished=false;t=0;cmd.start(c,s)
            for i=1,50 do ready=true;t=i*2;cmd.tick(c,s) end
            assert(c.drivingReview.count==32)
            """);
        run(vm,env,"""
            for _,name in ipairs({'mappedLight','isolateLight','lightProbe','referenceHud'}) do
                local cmd=ModStudio.Scenarios.commands['native.'..name]
                local s={x=8249,y=11632,z=0,tile='lighting_indoor_01_45',on=true,name='white-lamp',visible=false}
                cmd.validate(s)
                ModStudioScenario[name]=function() return nil end
                assert(not pcall(cmd.start,{},s))
                ModStudioScenario[name]=function() return false end
                assert(not pcall(cmd.start,{},s))
                ModStudioScenario[name]=function() return true end
                assert(pcall(cmd.start,{},s))
            end
            """);
        System.out.println("PASS: light probes, mapped switches and isolation require explicit Java success; missing/failed results stop Lua.");
        System.out.println("PASS: display mismatch and missing Java results fail Lua; only exact verified display proceeds.");
        System.out.println("PASS: native driving image review is bounded, awaits capture completion and stays outside measurement phases.");
        run(vm,env,"""
            local captured={}
            ModStudioScenario.event=function(kind,detail) captured[kind]=detail end
            tm.isEndlessDay=function() return false end;tm.isEndlessNight=function() return false end
            local climate=getClimateManager()
            climate.getSeason=function() return {getDawn=function() return 5 end,getDusk=function() return 21 end} end
            getClimateManager=function() return climate end
            local p={getX=function() return 10 end,getY=function() return 20 end,getZ=function() return 0 end,
                getSquare=function() return {getRoom=function() return nil end} end}
            tm.hour=22;ModStudio.Scenarios.commands['native.inspect'].start({player=p},{})
            assert(captured['native-climate']:find('hour=22') and captured['native-climate']:find('dusk=21'))
            assert(captured['native-climate']:find('endlessDay=false') and captured['native-climate']:find('daylight=0.5'))
            """);
        System.out.println("PASS: native inspection records actual clock, seasonal daylight and endless-day/night state.");
    }
}
