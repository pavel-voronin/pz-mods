if not getDebug() then return end
require "ModStudio/ScenarioMultiplayer"
require "TimedActions/ISTimedActionQueue"
local B={}
local function opening(s)
    local square=getCell():getGridSquare(s.x,s.y,s.z or 0)
    if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do local object=objects:get(i);if instanceof(object,"IsoWindow") then return object,square end end
    error("Native barricade window missing")
end
local function planks(window)
    local same=window:getBarricadeOnSameSquare();local opposite=window:getBarricadeOnOppositeSquare()
    return same and same:getNumPlanks() or 0,opposite and opposite:getNumPlanks() or 0
end
local function sample(c,s,t)
    local window=opening(s);if not window then return end
    local same,opposite=planks(window)
    local player=c.player;local queue=ISTimedActionQueue.getTimedActionQueue(player)
    local action=queue.queue[1];local native=action and action.action
    local id=action and action.transactionId
    local primary=player:getPrimaryHandItem();local secondary=player:getSecondaryHandItem()
    local detail=string.format("elapsed=%.3f same=%d opposite=%d queue=%d native=%d type=%s transaction=%s progress=%s maxTime=%s performing=%s state=%s primary=%s secondary=%s planks=%d nails=%d x=%.3f y=%.3f",
        t,same,opposite,#queue.queue,player:getCharacterActions():size(),tostring(action and action.Type),tostring(id),tostring(native and native:getJobDelta()),tostring(action and action.maxTime),tostring(player:getVariableBoolean("IsPerformingAnAction")),tostring(player:getActionStateName()),tostring(primary and primary:getFullType()),tostring(secondary and secondary:getFullType()),player:getInventory():getCountTypeRecurse("Base.Plank"),player:getInventory():getCountTypeRecurse("Base.Nails"),player:getX(),player:getY())
    if id and id~=0 then detail=detail.." done="..tostring(isActionDone(player,id)).." rejected="..tostring(isActionRejected(player,id)).." duration="..tostring(getActionDuration(player,id)) end
    c.event("network-barricade-sample",detail)
    return same+opposite,#queue.queue,player:getCharacterActions():size(),action
end
B.command={
    validate=function(s)
        for _,key in ipairs({"x","y"}) do local v=s[key];assert(type(v)=="number" and v>=0 and v<=100000 and v%1==0,"Invalid barricade coordinate") end
        assert(s.z==nil or type(s.z)=="number" and s.z>=-32 and s.z<=31 and s.z%1==0,"Invalid barricade floor")
        assert(s.action=="build" or s.action=="observe" or s.action=="clear","Invalid network barricade action")
        assert(s.seconds==nil or type(s.seconds)=="number" and s.seconds>=1 and s.seconds<=120,"Invalid barricade observation duration")
        assert(s.opposite==nil or type(s.opposite)=="boolean","Invalid barricade side")
    end,
    start=function(c,s)
        assert(isClient() and c.definition.multiplayer,"Barricade probe requires an owned multiplayer scenario")
        c.barricadePoll=0;c.barricadeCompletedAt=nil;c.barricadeSawBuild=false;c.barricadeIssued=false
        if s.action=="clear" then
            ISTimedActionQueue.clear(c.player)
            getCell():setDrag(nil,c.player:getPlayerNum())
            c.nativeAction("timedAction",s)
        end
    end,
    tick=function(c,s,t)
        local window,square=opening(s);if not window then return false end
        if s.action=="build" and not c.barricadeIssued then
            assert(not c.player:isBuildCheat() and not c.player:isTimedActionInstant() and not ISBuildMenu.cheat,"Native barricade probe forbids construction cheats")
            assert(#ISTimedActionQueue.getTimedActionQueue(c.player).queue==0,"Native action queue must be empty")
            local same,opposite=planks(window);c.barricadeBefore=same+opposite
            c.barricadeBeforeItems=c.player:getInventory():getCountTypeRecurse("Base.Plank")
            c.barricadeBeforeNails=c.player:getInventory():getCountTypeRecurse("Base.Nails")
            local north=window:getNorth()
            ISWorldObjectContextMenu.onBarricade(north and "carpentry_01_9" or "carpentry_01_8",c.player)
            local cursor=assert(getCell():getDrag(c.player:getPlayerNum()),"Native barricade cursor missing")
            cursor.nSprite=north and (s.opposite and 4 or 2) or (s.opposite and 3 or 1)
            cursor:getSprite()
            local target=s.opposite and window:getOppositeSquare() or square
            assert(target and cursor:isValid(target)==true,"Native barricade recipe or target rejected")
            c.nativeAction("timedAction",s)
            cursor.square=target;cursor.canBeBuild=true;cursor.build=true
            DoTileBuilding(cursor,false,target:getX(),target:getY(),target:getZ(),target)
            c.barricadeIssued=true
            c.event("network-barricade-request","cursor="..tostring(cursor.Type).." script="..cursor.objectInfo:getScript():getName().." face="..cursor:getFace():getFaceName().." before="..c.barricadeBefore)
        end
        local count,queue,native,action
        if t>=c.barricadePoll then count,queue,native,action=sample(c,s,t);c.barricadePoll=t+.5 end
        if s.action=="build" and count then
            c.barricadeSawBuild=c.barricadeSawBuild or action and action.Type=="ISBuildAction"
            if count==c.barricadeBefore+1 and queue==0 and native==0 then
                assert(c.player:getInventory():getCountTypeRecurse("Base.Plank")==c.barricadeBeforeItems-1,"Native barricade plank consumption mismatch")
                assert(c.player:getInventory():getCountTypeRecurse("Base.Nails")==c.barricadeBeforeNails-1,"Native barricade nail consumption mismatch")
                c.barricadeCompletedAt=c.barricadeCompletedAt or t
            end
        end
        if t<(s.seconds or 35) then return false end
        if s.action=="build" then
            assert(c.barricadeSawBuild,"Native ISBuildAction was never observed")
            c.event("network-barricade-outcome",c.barricadeCompletedAt and "completed elapsed="..c.barricadeCompletedAt or "unfinished after="..t)
        end
        return true
    end
}
ModStudio.Network.commands.barricade=B.command
return B
