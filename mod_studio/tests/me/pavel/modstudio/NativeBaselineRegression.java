package me.pavel.modstudio;

public final class NativeBaselineRegression {
    public static void main(String[] args) throws Exception {
        var h=new NativeBaseline.Histogram();
        if(h.q(.99)!=0)throw new AssertionError("Empty histogram");
        for(int i=0;i<95;i++)h.add(10_000_000);
        for(int i=0;i<4;i++)h.add(20_000_000);
        h.add(3_000_000_000L);
        if(h.n!=100||h.over16!=5||h.over33!=1||h.over100!=1||h.max!=3_000_000_000L)throw new AssertionError("Tail accounting");
        if(Math.abs(h.q(.95)-10.1)>1e-9||Math.abs(h.q(.99)-20.1)>1e-9||h.q(1)!=3000)throw new AssertionError("Nearest-rank bounds and overflow");
        boolean rejected=false;try{NativeBaseline.start("bad",0,-1,150,true,true);}catch(IllegalStateException expected){rejected=true;}
        if(!rejected)throw new AssertionError("Ordinary session mutation");
        if(args.length>0){
            var root=java.nio.file.Path.of(args[0]);var lua=root.resolve("Contents/mods/mod_studio/common/media/lua/client/ModStudio");
            var platform=se.krka.kahlua.j2se.J2SEPlatform.getInstance();var env=platform.newEnvironment();var thread=new se.krka.kahlua.vm.KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
            for(String code:java.util.List.of(java.nio.file.Files.readString(root.resolve("tests/fixtures/scenario-runtime.lua")),java.nio.file.Files.readString(lua.resolve("ScenarioAPI.lua")),java.nio.file.Files.readString(lua.resolve("ScenarioZombies.lua")),"local animals=(function()\n"+java.nio.file.Files.readString(lua.resolve("ScenarioAnimals.lua"))+"\nend)()",java.nio.file.Files.readString(lua.resolve("ScenarioLights.lua")),java.nio.file.Files.readString(lua.resolve("ScenarioObjects.lua")),java.nio.file.Files.readString(lua.resolve("ScenarioMultiplayer.lua")),"ModStudioScenarioRoute=(function()\n"+java.nio.file.Files.readString(lua.resolve("ScenarioRoute.lua"))+"\nend)()",java.nio.file.Files.readString(lua.resolve("Scenarios.lua")),
                "ModStudioNativeBaseline={open=function() return true end,start=function() return true end,poll=function() return true end};local cmd=ModStudio.Scenarios.commands['native.baseline'];local prepare=ModStudio.Scenarios.commands['native.baselinePrepare'];local c={phase=function() end};local s={name='test',dx=.7071067811865475,dy=.7071067811865475,seconds=10};cmd.validate(s);assert(not pcall(cmd.validate,{name='test',dx=1,dy=1,seconds=10}));cmd.start(c,s);assert(cmd.tick());ModStudioNativeBaseline.poll=function() end;assert(not pcall(cmd.tick));ModStudioNativeBaseline.open=function() end;assert(not pcall(cmd.start,{phase=function() end},s));assert(not pcall(prepare.tick));ModStudioNativeBaseline.open=function() return false end;assert(prepare.tick()==false);ModStudioNativeBaseline.start=function() return false end;assert(not pcall(cmd.start,c,s))")){
                var result=thread.pcall(se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(code,"native-baseline-test",env),new Object[0]);if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(java.util.Arrays.toString(result));
            }
        }
        System.out.println("PASS: bounded percentiles, exact tails, overflow and ordinary-session guard");
    }
}
