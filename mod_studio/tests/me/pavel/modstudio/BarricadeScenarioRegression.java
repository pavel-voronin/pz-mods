package me.pavel.modstudio;
import java.nio.file.*;
import java.util.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
public final class BarricadeScenarioRegression {
    private static void run(KahluaThread thread,KahluaTable env,String code)throws Exception {
        var result=thread.pcall(LuaCompiler.loadstring(code,"barricade-scenario-test",env),new Object[0]);
        if(!Boolean.TRUE.equals(result[0]))throw new AssertionError(Arrays.toString(result));
    }
    public static void main(String[] args)throws Exception {
        var platform=J2SEPlatform.getInstance();var env=platform.newEnvironment();var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
        run(thread,env,"""
            getDebug=function() return true end;require=function() end
            ModStudio={Network={commands={}}}
            """);
        run(thread,env,Files.readString(Path.of(args[0],"Contents/mods/mod_studio/common/media/lua/client/ModStudio/ScenarioBarricade.lua")));
        run(thread,env,"""
            local cmd=ModStudio.Network.commands.barricade
            cmd.validate({x=10,y=20,action='build'})
            for _,s in ipairs({{x=0/0,y=20,action='build'},{x=10,y=20,action='bad'},{x=10,y=20,action='build',seconds=0},{x=10,y=20,action='build',opposite=1}}) do assert(not pcall(cmd.validate,s)) end
            isClient=function() return false end
            assert(not pcall(cmd.start,{definition={multiplayer=true}},{action='observe'}))
            isClient=function() return true end
            local cleared,dragged,notified=0,0,0
            local queue={queue={}}
            ISTimedActionQueue={clear=function() cleared=cleared+1 end,getTimedActionQueue=function() return queue end}
            local w={getBarricadeOnSameSquare=function() return nil end,getBarricadeOnOppositeSquare=function() return nil end}
            local square={getObjects=function() return {size=function() return 1 end,get=function() return w end} end}
            getCell=function() return {getGridSquare=function() return square end,setDrag=function(_,value,index) assert(value==nil and index==0);dragged=dragged+1 end} end
            instanceof=function(o,name) return o==w and name=='IsoWindow' end
            local nativeCount=0
            local player={getPlayerNum=function() return 0 end,getCharacterActions=function() return {size=function() return nativeCount end} end,
                getPrimaryHandItem=function() return nil end,getSecondaryHandItem=function() return nil end,
                getVariableBoolean=function() return false end,getActionStateName=function() return 'idle' end,
                getInventory=function() return {getCountTypeRecurse=function() return 0 end} end,
                getX=function() return 10.5 end,getY=function() return 20.5 end}
            local outcomes={}
            local c={player=player,definition={multiplayer=true},nativeAction=function() notified=notified+1 end,event=function(kind,text) if kind=='network-barricade-outcome' then outcomes[#outcomes+1]=text end end}
            cmd.start(c,{action='clear'});cmd.start(c,{action='clear'})
            assert(cleared==2 and dragged==2 and notified==2,'repeatable clear delegates to native cancellation')
            local s={x=10,y=20,action='observe',seconds=2}
            cmd.start(c,s);assert(not cmd.tick(c,s,0));assert(cmd.tick(c,s,2))
            s.action='build';cmd.start(c,s);c.barricadeIssued=true;c.barricadeBefore=0
            queue.queue={{Type='ISBuildAction',action={getJobDelta=function() return 1 end},maxTime=100}};nativeCount=1
            assert(not cmd.tick(c,s,0));assert(cmd.tick(c,s,2))
            assert(outcomes[1]=='unfinished after=2','observed stall is recorded without claiming successful construction')
            queue.queue={};nativeCount=0
            cmd.start(c,s);c.barricadeIssued=true;c.barricadeBefore=0;c.barricadeBeforeItems=1;c.barricadeBeforeNails=1;c.barricadeSawBuild=true
            w.getBarricadeOnSameSquare=function() return {getNumPlanks=function() return 1 end} end
            assert(not cmd.tick(c,s,0));assert(cmd.tick(c,s,2));assert(outcomes[2]=='completed elapsed=0')
            cmd.start(c,s);c.barricadeIssued=true;c.barricadeBefore=0;c.barricadeBeforeItems=2;c.barricadeBeforeNails=2
            assert(not pcall(cmd.tick,c,s,0),'successful state cannot hide incorrect material consumption')
            """);
        System.out.println("BarricadeScenarioRegression passed: validation, MP ownership, native cancellation, observed stall, completion and material accounting.");
    }
}
