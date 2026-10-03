if not getDebug() then return end
require "ModStudio/ScenarioAPI"
require "DebugUIs/DebugScenarios"
require "TimedActions/ISTimedActionQueue"
require "ModStudio/ScenarioAnimals"
require "ModStudio/ScenarioLights"
local ScenarioLights=ModStudioScenarioLights
local ScenarioAnimals=ModStudioScenarioAnimals
local API=ModStudio.Scenarios
if API.installed then return end
API.installed=true
local ctx, cfg, state, since, deadline, step, handler
local providers, opened={},{}
local claimed=false
local outcome,reason,finishAt,previousDebugger
local function now() return ModStudioScenario.clock() end
local function event(kind,detail) ModStudioScenario.event(kind,tostring(detail)) end
local function phase(name,timeout)
    state=name;since=now();deadline=since+(timeout or 30)
    event("phase",name.." repeat="..ctx.repeatIndex.." step="..ctx.stepIndex)
    for _,p in ipairs(opened) do if p.phase then p.phase(ctx,name) end end
end
local function stop(status,why)
    if state=="FINISH" or state=="CLOSED" then return end
    outcome=status;reason=tostring(why);finishAt=now();state="FINISH"
    event("finish-request",status..": "..reason)
end
local function number(s,k,min,max,optional)
    local v=s[k];assert(optional and v==nil or type(v)=="number" and v==v and v>=min and v<=max,"Invalid "..k)
end
local function coordinates(s) number(s,"x",0,100000);number(s,"y",0,100000);number(s,"z",-32,31,true) end
API.register("native",{
    update=function(c) if c.nativeHuman then ModStudioScenario.updateHuman() end end,
    boundary=function(c) if c.nativeDriving then ModStudioDriving.stop() end end,
    finish=function(c) ScenarioLights.clear(c);ScenarioAnimals.clear(c);if c.nativeHuman then ModStudioScenario.clearHuman();c.nativeHuman=nil end;if c.nativeDriving then ModStudioDriving.close();c.nativeDriving=nil end;return true end
}, {
    lightFixture=ScenarioLights.fixture,
    lightYard=ScenarioLights.yard,
    equip=ScenarioLights.equip,
    weaponLight=ScenarioLights.weaponLight,
    animals=ScenarioAnimals.command,
    killAnimals=ScenarioAnimals.kill,
    human={validate=function(s)
            assert(ModStudioScenario.spawnHuman,"Native human API unavailable")
            number(s,"dx",-8,8);number(s,"dy",-8,8)
            assert(s.dx*s.dx+s.dy*s.dy>=1,"Human must spawn at least one tile away")
        end,start=function(c,s) c.nativeHuman=true;ModStudioScenario.spawnHuman(s.dx,s.dy) end,
        tick=function() return ModStudioScenario.humanReady() end},
    humanLight={validate=function(s)
            assert(type(s.on)=="boolean","humanLight requires on");number(s,"heading",-180,180)
        end,start=function(c,s) assert(c.nativeHuman,"Spawn a human first");ModStudioScenario.humanLight(s.on,s.heading) end},
    clearHuman={start=function(c) ModStudioScenario.clearHuman();c.nativeHuman=nil end},
    vehicle={validate=function(s)
            assert(ModStudioDriving,"Native driving API unavailable")
            assert(type(s.script)=="string" and #s.script>0 and #s.script<=128,"Invalid vehicle script")
            number(s,"heading",-180,180)
        end,start=function(c,s) c.nativeDriving=true;ModStudioDriving.spawn(s.script,s.heading) end},
    drive={validate=function(s)
            assert(ModStudioDriving,"Native driving API unavailable")
            number(s,"x",0,100000);number(s,"y",0,100000);number(s,"kmh",5,100)
        end,start=function(c,s)
            assert(c.nativeDriving,"Create a native scenario vehicle first")
            ModStudioDriving.drive(s.x,s.y,s.kmh);c.phase("MEASURE",s.timeout or 30)
        end,tick=function() return ModStudioDriving.poll() end},
    playerFlags={validate=function(s)
            assert(type(s.invisible)=="boolean","Invalid invisible")
            assert(s.ghost==nil,"Use invisible: GhostMode is the same native flag")
        end,start=function(c,s)
            if s.invisible~=nil then c.player:setInvisible(s.invisible);assert(c.player:isInvisible()==s.invisible,"Invisible flag was not applied") end
            event("native-player-flags","invisible="..tostring(c.player:isInvisible()).." ghost="..tostring(c.player:isGhostMode()))
        end},
    wait={validate=function(s) number(s,"seconds",0,600) end,start=function() end,tick=function(c,s,t) return t>=s.seconds end},
    screenshot={validate=function(s) assert(type(s.name)=="string" and #s.name<=60 and s.name:match("^[a-z0-9_-]+$"),"Invalid screenshot name") end,
        start=function(c,s) ModStudioScenario.screenshot(s.name) end,tick=function() return ModStudioScenario.screenshotReady() end},
    clearVehicles={validate=function(s)
            for _,k in ipairs({"x0","y0","x1","y1"}) do number(s,k,0,100000) end
            assert(s.x1>s.x0 and s.y1>s.y0 and s.x1-s.x0<=128 and s.y1-s.y0<=128,"Vehicle clearing requires a bounded rectangle")
        end,start=function(c,s)
            assert(getCore():isNoSave(),"Vehicle clearing is only allowed in the disposable NoSave scenario world")
            local removed=ModStudioScenario.clearVehicles(s.x0,s.y0,s.x1,s.y1)
            event("native-clear-vehicles","removed="..removed.." bounds="..s.x0..","..s.y0..","..s.x1..","..s.y1)
        end},
    teleport={validate=coordinates,start=function(c,s)
            c.player:teleportTo(s.x,s.y,s.z or 0)
            for _,p in ipairs(opened) do if p.nativeAction then p.nativeAction(c,"teleport",s) end end
        end,
        -- PZ's float overload floors x/y to native tile coordinates.
        tick=function(c,s) local p=c.player;local square=p:getSquare();return math.floor(p:getX())==math.floor(s.x) and math.floor(p:getY())==math.floor(s.y) and math.abs(p:getZ()-(s.z or 0))<.1 and square and square:getX()==math.floor(s.x) and square:getY()==math.floor(s.y) and square:getFloor() end},
    time={validate=function(s) number(s,"hour",0,23.999) end,start=function(c,s) c.fixedTime=s.freeze and s.hour or nil;getGameTime():setTimeOfDay(s.hour) end},
    weather={validate=function(s)
            number(s,"fog",0,1);number(s,"rain",0,1);number(s,"cloud",0,1)
            number(s,"wind",0,1,true);number(s,"windAngle",-1,1,true)
        end,start=function(c,s)
            assert(getCore():isNoSave(),"Weather control requires the disposable NoSave world")
            local climate=getClimateManager()
            c.weatherSaved=c.weatherSaved or {}
            for key,id in pairs({fog=5,rain=3,cloud=8,wind=6,windAngle=7}) do
                if s[key]~=nil then
                local value=climate:getClimateFloat(id)
                if not c.weatherSaved[id] then c.weatherSaved[id]={enabled=value:isEnableAdmin(),value=value:getAdminValue()} end
                value:setAdminValue(s[key]);value:setEnableAdmin(true)
                end
            end
        end,tick=function(c,s)
            local climate=getClimateManager()
            if math.abs(climate:getFogIntensity()-s.fog)>.001 or math.abs(climate:getPrecipitationIntensity()-s.rain)>.001 or math.abs(climate:getCloudIntensity()-s.cloud)>.001 then return false end
            if s.wind and math.abs(climate:getWindIntensity()-s.wind)>.001 or s.windAngle and math.abs(climate:getWindAngleIntensity()-s.windAngle)>.001 then return false end
            local color=climate:getColorNewFog():getExterior()
            event("native-weather","fog="..s.fog.." rain="..s.rain.." cloud="..s.cloud.." hour="..getGameTime():getTimeOfDay().." ambient="..climate:getAmbient().." daylight="..climate:getDayLightStrength().." tint="..color:getRedFloat()..","..color:getGreenFloat()..","..color:getBlueFloat())
            return true
        end},
    give={validate=function(s) assert(type(s.type)=="string" and type(s.id)=="string","give requires type and id");number(s,"charge",0,1,true) end,
        start=function(c,s)
            assert(not c.items[s.id],"Duplicate item id: "..s.id)
            local item=c.player:getInventory():AddItem(s.type);assert(item,"Unknown item: "..s.type);c.items[s.id]=item
            if s.charge then item:setUsedDelta(s.charge) end
            if s.equip=="primary" then c.player:setPrimaryHandItem(item) elseif s.equip=="secondary" then c.player:setSecondaryHandItem(item) end
            event("item",s.id.."="..item:getFullType())
        end},
    torch={validate=function(s) assert(type(s.id)=="string" and type(s.on)=="boolean","torch requires id and on") end,
        start=function(c,s) local item=c.items[s.id];assert(item,"Unknown item id: "..s.id);item:setActivated(s.on);assert(item:isActivated()==s.on,"Native activation failed");event("native-light",s.id.."="..tostring(s.on)) end},
    inspect={start=function(c)
        local p=c.player;local room=p:getSquare():getRoom()
        event("native-position","x="..p:getX().." y="..p:getY().." z="..p:getZ().." room="..tostring(room and room:getName()))
    end}
})
local function advance()
    for _,p in ipairs(opened) do if p.boundary then p.boundary(ctx) end end
    ctx.stepIndex=ctx.stepIndex+1
    if ctx.stepIndex>#cfg.steps then
        ctx.repeatIndex=ctx.repeatIndex+1;ctx.stepIndex=1
        if ctx.repeatIndex>(cfg.repeats or 1) then
            if cfg.manual then
                for i=#opened,1,-1 do local p=opened[i];if p.handoff then p.handoff(ctx) end end
                ModStudioScenario.handoff();state="MANUAL";return
            end
            stop("complete","Scenario finished");return
        end
    end
    step=cfg.steps[ctx.stepIndex];handler=API.commands[step.command]
    phase("ACTION",step.timeout or math.max(30,(step.seconds or 0)+5))
    event("command",step.command.." "..(step.name or ""));handler.start(ctx,step)
end
local function restoreNative()
    if ctx.weatherSaved then
        for id,saved in pairs(ctx.weatherSaved) do
            local value=getClimateManager():getClimateFloat(id)
            value:setAdminValue(saved.value);value:setEnableAdmin(saved.enabled)
        end
        ctx.weatherSaved=nil
    end
    if not ctx.saved or not ctx.player then return end
    local p,s=ctx.player,ctx.saved
    p:setPrimaryHandItem(s.primary);p:setSecondaryHandItem(s.secondary)
    for _,item in pairs(ctx.items) do item:setActivated(false);p:getInventory():Remove(item) end
    p:setGodMod(s.god);p:setInvisible(s.invisible);p:setGhostMode(s.ghost)
    p:setRunning(s.running);p:setSprinting(s.sprinting);p:setSneaking(s.sneaking);p:setMoving(false)
    getGameTime():setTimeOfDay(s.hour)
    event("restore","native loadout, flags and time restored; fresh simulation is discarded")
end
local function finish()
    local complete=true
    for i=#opened,1,-1 do
        local p=opened[i]
        if not p.closed then
            local ok,done=pcall(function() return not p.finish or p.finish(ctx,outcome,reason) end)
            if not ok then outcome="failed";reason=reason.."; provider cleanup: "..tostring(done);p.closed=true
            elseif done then p.closed=true else complete=false end
        end
    end
    if not complete and now()-finishAt<15 then return end
    if not complete then outcome="failed";reason=reason.."; provider flush timeout" end
    local ok,err=pcall(restoreNative);if not ok then outcome="failed";reason=reason.."; native cleanup: "..tostring(err) end
    if previousDebugger~=nil then UIManager.setShowLuaDebuggerOnError(previousDebugger) end
    event("scenario-seconds",ctx.startedAt and now()-ctx.startedAt or 0)
    ModStudioScenario.finish(outcome,reason);state="CLOSED";finishAt=now()
end
local function tick()
    if not claimed then return end
    if state=="MANUAL" then if ctx.fixedTime then getGameTime():setTimeOfDay(ctx.fixedTime) end;return end
    if state=="CLOSED" then
        if ModStudioScenario.closed() or now()-finishAt>10 then getCore():quitToDesktop() end
        return
    end
    if state=="FINISH" then finish();return end
    assert(ModStudioScenario.error()=="",ModStudioScenario.error())
    assert(now()<=deadline,"Timeout: "..state.." step "..ctx.stepIndex)
    if state=="LOADING" then
        local p=getPlayer();if not p or not p:getSquare() or not p:getSquare():getFloor() then return end
        ctx.player=p;ctx.items={}
        ctx.saved={primary=p:getPrimaryHandItem(),secondary=p:getSecondaryHandItem(),god=p:isGodMod(),invisible=p:isInvisible(),ghost=p:isGhostMode(),running=p:isRunning(),sprinting=p:isSprinting(),sneaking=p:isSneaking(),hour=getGameTime():getTimeOfDay()}
        p:setGodMod(true);p:setInvisible(false);p:setGhostMode(false);p:setRunning(false);p:setSprinting(false);p:setSneaking(false)
        ISTimedActionQueue.clear(p);phase("PREPARE",120)
    end
    if state=="PREPARE" then
        for _,p in ipairs(providers) do
            if not p.opened then p.opened=true;opened[#opened+1]=p end
            if not p.ready then p.ready=not p.begin or p.begin(ctx);if not p.ready then return end end
        end
        ctx.startedAt=now();event("scenario-start","World and providers ready");advance();return
    end
    assert(getPlayer()==ctx.player and not ctx.player:isDead(),"Player unavailable")
    if ctx.fixedTime then getGameTime():setTimeOfDay(ctx.fixedTime) end
    for _,p in ipairs(opened) do if p.update then p.update(ctx) end end
    if not handler.tick or handler.tick(ctx,step,now()-since) then advance() end
end
local function start()
    if claimed or not ModStudioScenario or not ModStudioScenario.requested() then return end
    ctx=ModStudioScenario.context()
    if not ctx then print("[Mod Studio] "..ModStudioScenario.error());getCore():quitToDesktop();return end
    if not ModStudioScenario.claim() then return end
    claimed=true;cfg=ctx.definition;ctx.stepIndex=0;ctx.repeatIndex=1
    ctx.event=event;ctx.phase=phase;ctx.clock=now
    previousDebugger=UIManager.isShowLuaDebuggerOnError();UIManager.setShowLuaDebuggerOnError(false)
    phase("LOADING",240)
    local owners={}
    for _,s in ipairs(cfg.steps) do
        local h=API.commands[s.command];assert(h,"Unregistered command: "..s.command)
        if h.validate then h.validate(s) end
        local owner=string.match(s.command,"^([^.]+)");owners[owner]=true
    end
    local names={};for owner in pairs(owners) do names[#names+1]=owner end;table.sort(names)
    for _,owner in ipairs(names) do providers[#providers+1]=API.providers[owner] end
    ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))
    local scenario={name="Mod Studio scenario",world=cfg.map or "Muldraugh, KY",startLoc=cfg.spawn,
        setSandbox=function()
            SandboxVars.Zombies=6;SandboxVars.StartMonth=7;SandboxVars.StartDay=9;SandboxVars.StartTime=2
            SandboxVars.WaterShutModifier=365;SandboxVars.ElecShutModifier=365;SandboxVars.StarterKit=false
            if cfg.sandbox then for k,v in pairs(cfg.sandbox) do SandboxVars[k]=v end end
        end,
        onStart=function() getCore():setNoSave(true);ModStudioScenario.worldReady();event("world-ready","native fresh world; NoSave=true") end}
    if not DebugScenarios.instance then doDebugScenarios() end
    getWorld():setGameMode("Sandbox")
    getCore():setNoSave(false) -- Native createWorld requires the empty bootstrap directory.
    DebugScenarios.instance:launchScenario(scenario)
    getCore():setNoSave(true)
end
Events.OnMainMenuEnter.Add(function()
    if claimed then stop("aborted","Returned to menu");return end
    local ok,err=pcall(start);if not ok then stop("failed",err) end
end)
local function update()
    local ok,err=pcall(tick);if not ok then
        if state=="FINISH" then ModStudioScenario.finish("failed",tostring(err));state="CLOSED";finishAt=now()
        else stop("failed",err) end
    end
end
Events.OnTick.Add(update)
Events.OnTickEvenPaused.Add(update)
Events.OnFETick.Add(update) -- Startup failures must also flush and close from the menu.
