-- Optional local experiment. Inert unless an external debug scenario requests mcp.session.
if not getDebug() or not ModStudioScenario or not ModStudioScenario.requested() then return end
require "ModStudio/ScenarioAPI"
local API=ModStudio.Scenarios
local active
local function json(v)
    if v==nil then return "null" end
    if type(v)=="boolean" then return tostring(v) end
    if type(v)=="number" then if v~=v or math.abs(v)==math.huge then return "null" end;return tostring(v) end
    if type(v)=="string" then return '"'..string.gsub(v,'[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"' end
    local parts={}
    for k,item in pairs(v) do parts[#parts+1]=json(tostring(k))..":"..json(item) end
    return "{"..table.concat(parts,",").."}"
end
local function write(name,v)
    local w=getFileWriter(active.prefix..name,true,false);assert(w,"Cannot open MCP mailbox")
    w:write(json(v));w:close()
end
local function clear(c)
    for _,owner in ipairs({"pz3d","native"}) do local p=API.providers[owner];if p and p.boundary then p.boundary(c) end end
end
local function observe(c)
    local p=c.player;local sq=p:getSquare();local r=sq and sq:getRoom();local v=p:getVehicle()
    return {x=p:getX(),y=p:getY(),z=p:getZ(),room=r and r:getName() or false,
        health=p:getBodyDamage():getOverallBodyHealth(),dead=p:isDead(),running=p:isRunning(),
        vehicle=v and {script=v:getScriptName(),x=v:getX(),y=v:getY(),speedKmh=v:getCurrentSpeedKmHour()} or false,
        camera=PZ3D.scenarioView(),output=c.output,diagnostics=PZ3D.scenarioPath()}
end
local function survey(c,radius)
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
local allowed={move="pz3d.move",look="pz3d.look",camera="pz3d.camera",wait="native.wait",vehicle="native.vehicle",drive="native.drive",capture="pz3d.capture"}
local function reply(c,status,err,extra)
    local a=active
    write("reply.json",{id=a.id,status=status,error=err or false,state=observe(c),data=extra or false})
end
local function complete(c,status,err,extra)
    clear(active.child);reply(c,status,err,extra);active.handler=nil;active.step=nil
end
local function accept(c,line)
    if #line>4096 then return end
    local f={};for v in string.gmatch(line,"[^\t]+") do f[#f+1]=v end
    local id=tonumber(f[1]);if not id or id<=active.id or f[#f]~="END" then return end
    active.id=id
    if f[2]=="stop" or f[2]=="close" then
        clear(active.child);active.handler=nil
        reply(c,"complete");active.done=f[2]=="close";return
    end
    assert(not active.handler,"Action already running; stop it first")
    if f[2]=="observe" then reply(c,"complete");return end
    if f[2]=="survey" then local radius=tonumber(f[3]);assert(radius and radius>=1 and radius<=8 and radius==math.floor(radius),"Invalid radius");reply(c,"complete",nil,survey(c,radius));return end
    local name=allowed[f[2]];assert(name,"Unknown MCP action")
    local s={command=name,timeout=25};for i=3,#f-1,2 do
        local value=f[i+1];assert(value,"Missing value")
        if value=="true" then value=true elseif value=="false" then value=false else value=tonumber(value) or value end
        s[f[i]]=value
    end
    assert(type(s.timeout)=="number" and s.timeout>=.1 and s.timeout<=45,"Invalid timeout")
    local h=API.commands[name];assert(h,"Command unavailable: "..name);if h.validate then h.validate(s) end
    active.step=s;active.handler=h;active.started=c.clock();active.deadline=active.started+s.timeout
    active.child.stepIndex=active.id+100
    active.child.phase=function(phase,timeout)
        active.deadline=c.clock()+math.min(timeout or 25,45)
        local provider=API.providers.pz3d;if provider.phase then provider.phase(active.child,phase) end
    end
    h.start(active.child,s);c.nativeDriving=active.child.nativeDriving;reply(c,"running")
end
API.register("mcp",{
    finish=function(c,status,reason)
        if active then clear(active.child or c);write("status.json",{status="closed",reason=reason,output=c.output});active=nil end
        return true
    end
},{session={
    validate=function(s) assert(type(s.session)=="string" and string.match(s.session,"^[a-f0-9-]+$") and #s.session==36,"Invalid MCP session") end,
    start=function(c,s)
        assert(getCore():isNoSave(),"MCP experiment requires NoSave")
        active={prefix="pz3d-mcp/"..s.session.."/",id=0,nextPoll=0,nextState=0,done=false}
        active.child=setmetatable({},{__index=c})
        c.event("mcp-session",s.session)
    end,
    tick=function(c,s)
        local a=active;local now=c.clock()
        if now>=a.nextPoll then
            a.nextPoll=now+.25
            local r=getFileReader(a.prefix.."request.txt",false)
            if r then local line=r:readLine();r:close();if line then
                local ok,err=pcall(accept,c,line);if not ok then complete(c,"failed",tostring(err)) end
            end end
        end
        if a.handler and now>a.deadline then complete(c,"failed","MCP action timed out") end
        if a.handler then
            local ok,done=pcall(function()
                return not a.handler.tick or a.handler.tick(a.child,a.step,now-a.started)
            end)
            if not ok then complete(c,"failed",tostring(done)) elseif done then complete(c,"complete") end
        end
        if now>=a.nextState then a.nextState=now+.5;write("status.json",{status=a.done and "closing" or "ready",id=a.id,busy=a.handler~=nil,state=observe(c)}) end
        return a.done
    end
}})
