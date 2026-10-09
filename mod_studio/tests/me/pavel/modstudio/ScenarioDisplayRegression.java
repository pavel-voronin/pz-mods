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
        System.out.println("PASS: display mismatch and missing Java results fail Lua; only exact verified display proceeds.");
    }
}
