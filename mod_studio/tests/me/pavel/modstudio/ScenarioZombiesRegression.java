package me.pavel.modstudio;

import java.nio.file.*;
import java.util.Arrays;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

public final class ScenarioZombiesRegression {
    public static void main(String[] args)throws Exception {
        var platform=J2SEPlatform.getInstance();var env=platform.newEnvironment();
        var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
        String fixture="""
            local disposable=true
            getCore=function() return {isNoSave=function() return disposable end} end
            getCell=function() return {getGridSquare=function() return {getFloor=function() return {} end,isFree=function() return true end} end} end
            local calls,removed=0,0
            local failAt=0
            addZombiesInOutfit=function(x,y,z,count,outfit,female,crawler,fall,fake,knock,invulnerable,sitting,health,record,height,ragdoll,fire)
                calls=calls+1;if calls==failAt then error('spawn failure') end
                assert(count==1 and invulnerable and not sitting and health==1)
                local zombie={removeFromWorld=function() removed=removed+1 end,removeFromSquare=function() end}
                return {size=function() return 1 end,get=function() return zombie end}
            end
            local c={player={getX=function() return 10 end,getY=function() return 20 end,getZ=function() return 0 end},event=function() end}
            local command=ModStudioScenarioZombies.command
            for _,s in ipairs({{count=13,dx=2,dy=0},{count=1,dx=1,dy=0},{count=1,dx=0/0,dy=2},{count=1,dx=2,dy=0,crawler=1}}) do assert(not pcall(command.validate,s)) end
            local step={count=2,dx=2,dy=0,crawler=true,onFire=true};command.validate(step);command.start(c,step)
            assert(calls==2 and #c.nativeZombies==2)
            ModStudioScenarioZombies.clear(c);assert(removed==2 and c.nativeZombies==nil)
            failAt=calls+2;assert(not pcall(command.start,c,step));assert(#c.nativeZombies==1)
            ModStudioScenarioZombies.clear(c);assert(removed==3)
            disposable=false;assert(not pcall(command.start,c,step));assert(calls==4 and c.nativeZombies==nil)
            """;
        String source=Files.readString(Path.of(args[0]).resolve("Contents/mods/mod_studio/common/media/lua/client/ModStudio/ScenarioZombies.lua"));
        var result=thread.pcall(LuaCompiler.loadstring(source+"\n"+fixture,"zombie-fixture-test",env),new Object[0]);
        if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(Arrays.toString(result));
        System.out.println("PASS bounded native zombies, NoSave guard, owned cleanup and partial spawn failure");
    }
}
