-- Enabled exclusively by the external Mod Studio -Mcp launch flag.
if not getDebug() or not ModStudioScenario or not ModStudioScenario.requested()
    or not ModStudioScenario.mcpSession or ModStudioScenario.mcpSession()=="" then return end
require "ModStudio/ScenarioAPI"
local API=ModStudio.Scenarios
local active
local function json(v)
    if v==nil then return "null" end
    if type(v)=="boolean" then return tostring(v) end
    if type(v)=="number" then assert(v==v and math.abs(v)~=math.huge,"Non-finite JSON number");return tostring(v) end
    if type(v)=="string" then return '"'..string.gsub(v,'[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"' end
    local parts={}
    if #v>0 then for i=1,#v do parts[#parts+1]=json(v[i]) end;return "["..table.concat(parts,",").."]" end
    for k,item in pairs(v) do parts[#parts+1]=json(tostring(k))..":"..json(item) end
    return "{"..table.concat(parts,",").."}"
end
local function write(name,v) ModStudioScenario.mcpWrite(name,json(v)) end
local function observe(c)
    local p=c.player;local sq=p:getSquare();local r=sq and sq:getRoom();local v=p:getVehicle()
    return {x=p:getX(),y=p:getY(),z=p:getZ(),room=r and r:getName() or false,
        health=p:getBodyDamage():getOverallBodyHealth(),dead=p:isDead(),running=p:isRunning(),
        vehicle=v and {script=v:getScriptName(),x=v:getX(),y=v:getY(),speedKmh=v:getCurrentSpeedKmHour()} or false,
        camera=PZ3D and PZ3D.scenarioView and PZ3D.scenarioView() or false,output=c.output,
        diagnostics=PZ3D and PZ3D.scenarioPath and PZ3D.scenarioPath() or false,
        hour=getGameTime():getTimeOfDay(),fog=getClimateManager():getFogIntensity(),
        rain=getClimateManager():getPrecipitationIntensity(),cloud=getClimateManager():getCloudIntensity()}
end
local function survey(c,radius)
    assert(type(radius)=="number" and radius>=1 and radius<=8 and radius==math.floor(radius),"Invalid survey radius")
    local result={};local p=c.player;local cell=getCell();local x,y,z=math.floor(p:getX()),math.floor(p:getY()),math.floor(p:getZ())
    for dy=-radius,radius do for dx=-radius,radius do
        local sq=cell:getGridSquare(x+dx,y+dy,z)
        if sq then
            local room=sq:getRoom();local objects={};local list=sq:getObjects()
            for i=0,list:size()-1 do
                local o=list:get(i)
                if instanceof(o,"IsoDoor") or instanceof(o,"IsoWindow") then
                    objects[tostring(i)]={kind=instanceof(o,"IsoDoor") and "door" or "window",open=o:IsOpen()}
                end
            end
            result[dx..","..dy]={x=x+dx,y=y+dy,z=z,room=room and room:getName() or false,
                floor=sq:TreatAsSolidFloor(),solid=sq:isSolid(),solidTrans=sq:isSolidTrans(),objects=objects}
        end
    end end
    return result
end
local function reply(c,status,err,data)
    local record={id=active.id,status=status,error=err or false,completed=active.completed or 0,state=observe(c),data=data or false}
    write("reply.json",record)
    if status~="running" then write("history.jsonl",{kind="reply",reply=record}) end
end
local function clear(c)
    c.boundary();active.handler=nil;active.steps=nil;active.pending=nil;active.started=nil
end
local function complete(c,status,err,data)
    clear(c);reply(c,status,err,data)
    c.livePhase("ACTION")
end
local function validateSteps(steps)
    assert(type(steps)=="table" and #steps>=1 and #steps<=64,"Expected 1..64 steps")
    for _,s in ipairs(steps) do
        assert(type(s)=="table" and type(s.command)=="string" and s.command:match("^[a-z][a-z0-9_]*%.[a-z][a-zA-Z0-9_]*$"),"Expected owner.command")
        assert(not s.command:match("^mcp%."),"Nested MCP sessions are forbidden")
        local h=API.commands[s.command];assert(h,"Unregistered command: "..s.command)
        local timeout=s.timeout or math.max(30,(s.seconds or 0)+5)
        assert(type(timeout)=="number" and timeout==timeout and timeout>=.1 and timeout<=900,"Invalid command timeout")
        if h.validate then h.validate(s) end
    end
end
local function accept(c,r)
    assert(type(r.id)=="number" and r.id>0 and r.id==math.floor(r.id) and r.id<=9007199254740991,"Invalid request id")
    if r.id<=active.id then return end
    -- Read-only queries do not interrupt an action; stop/close explicitly do.
    if active.steps and r.action~="stop" and r.action~="close" then return end
    if active.steps then complete(c,"cancelled","Interrupted by "..r.action) end
    if (r.action=="stop" or r.action=="close") and type(r.interrupted)=="number" and r.interrupted>active.id and r.interrupted<r.id then
        write("history.jsonl",{kind="reply",reply={id=r.interrupted,status="cancelled",completed=0,error="Cancelled before acceptance",state=observe(c)}})
    end
    active.id=r.id;active.completed=0
    write("history.jsonl",{kind="request",request=r});c.event("mcp-request",json(r))
    if r.action=="close" or r.action=="stop" then clear(c);reply(c,"complete");active.done=r.action=="close";return end
    if r.action=="observe" then reply(c,"complete");return end
    if r.action=="survey" then reply(c,"complete",nil,survey(c,r.radius));return end
    if r.action=="commands" then
        local names={};for name in pairs(API.commands) do if not name:match("^mcp%.") then names[#names+1]=name end end
        table.sort(names);reply(c,"complete",nil,names);return
    end
    assert(r.action=="execute","Unknown MCP action")
    validateSteps(r.steps);active.steps=r.steps;active.index=1;active.pending=true;reply(c,"running")
end
local function run(c)
    local a=active
    if not a.steps then return end
    local s=a.steps[a.index]
    if a.pending then
        if not a.started then
            a.started=c.clock();a.since=a.started;a.deadline=a.started+(s.timeout or math.max(30,(s.seconds or 0)+5))
            c.stepIndex=c.stepIndex+1;c.livePhase("PREPARE")
        end
        if c.clock()>a.deadline then complete(c,"failed","MCP command timed out during preparation");return end
        if not c.ensureProvider(s.command:match("^([^.]+)")) then return end
        a.handler=API.commands[s.command];a.pending=nil;a.since=c.clock();c.livePhase("ACTION")
        c.event("mcp-command",json({id=a.id,index=a.index,step=s}));a.handler.start(c,s)
        return
    end
    if c.clock()>a.deadline then complete(c,"failed","MCP command timed out");return end
    if not a.handler.tick or a.handler.tick(c,s,c.clock()-a.since) then
        c.boundary();a.completed=a.index
        write("history.jsonl",{kind="step",id=a.id,index=a.index,step=s})
        a.index=a.index+1;a.handler=nil;a.started=nil
        if a.index>#a.steps then complete(c,"complete") else a.pending=true end
    end
end
API.register("mcp",{
    finish=function(c,status,reason)
        if active then
            if active.steps then complete(c,"cancelled",reason) end
            c.phase=active.originalPhase
            write("status.json",{session=c.mcpSession,status="closed",outcome=status,reason=reason,output=c.output})
            active=nil
        end
        return true
    end
},{session={
    start=function(c,s)
        assert(getCore():isNoSave() and s.session==ModStudioScenario.mcpSession(),"MCP requires an explicitly enabled NoSave scenario")
        active={id=0,nextPoll=0,nextState=0,done=false,originalPhase=c.phase}
        c.phase=function(name,timeout)
            assert(not ({LOADING=true,PREPARE=true,FINISH=true,CLOSED=true})[name],"Invalid command phase")
            active.since=c.clock();c.livePhase(name)
            -- Phase transitions cannot extend the original command deadline.
            if timeout then active.deadline=math.min(active.deadline,c.clock()+timeout) end
        end
        c.event("mcp-session",s.session)
    end,
    tick=function(c,s)
        local a=active;local now=c.clock()
        if now>=a.nextPoll then
            a.nextPoll=now+.25
            local ok,r=pcall(ModStudioScenario.mcpRead)
            if ok and r then
                local accepted,err=pcall(function() accept(c,r) end)
                if not accepted then complete(c,"failed",tostring(err)) end
            elseif not ok then c.event("mcp-read-error",tostring(r)) end
        end
        if a.steps then local ok,err=pcall(function() run(c) end);if not ok then complete(c,"failed",tostring(err)) end end
        if now>=a.nextState then
            a.nextState=now+.5
            write("status.json",{session=s.session,status=a.done and "closing" or "ready",id=a.id,busy=a.steps~=nil,completed=a.completed or 0,state=observe(c)})
        end
        return a.done
    end
}})
