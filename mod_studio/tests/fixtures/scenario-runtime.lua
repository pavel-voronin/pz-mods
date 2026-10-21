require=function() end
getDebug=function() return true end
getPlayerInfoPanel=function() return nil end
isClient=function() return false end
isServer=function() return false end
Events={}
for _,name in ipairs({"OnTick","OnTickEvenPaused","OnMainMenuEnter","OnFETick","OnGameStart","OnPostUIDraw"}) do
    local e={handlers={}}
    e.Add=function(f) e.handlers[#e.handlers+1]=f end
    e.fire=function() for _,f in ipairs(e.handlers) do f() end end
    Events[name]=e
end
UIManager={isShowLuaDebuggerOnError=function() return true end,setShowLuaDebuggerOnError=function() end}
core={isNoSave=function() return true end,setNoSave=function() end,quitToDesktop=function() quit=true end}
getCore=function() return core end
core.vsync=true
core.getOptionVSync=function(self) return self.vsync end
core.setOptionVSync=function(self,value) self.vsync=value end
world={getWorld=function() return "test" end,getMap=function() return "fixture" end}
getWorld=function() return world end
getActivatedMods=function() return {size=function() return 0 end} end
ISTimedActionQueue={clear=function() end}
tm={hour=9,getTimeOfDay=function(self) return self.hour end,setTimeOfDay=function(self,v) self.hour=v end}
getGameTime=function() return tm end
weatherValues={}
for _,id in ipairs({3,5,6,7,8}) do
    weatherValues[id]={enabled=false,value=.2,
        isEnableAdmin=function(self) return self.enabled end,getAdminValue=function(self) return self.value end,
        setEnableAdmin=function(self,v) self.enabled=v end,setAdminValue=function(self,v) self.value=v end}
end
weatherSnow={enabled=false,value=false,isEnableAdmin=function(self) return self.enabled end,getAdminValue=function(self) return self.value end,setEnableAdmin=function(self,v) self.enabled=v end,setAdminValue=function(self,v) self.value=v end}
getClimateManager=function() return {
    getClimateBool=function() return weatherSnow end,
    getPrecipitationIsSnow=function() return weatherSnow.value end,
    getAmbient=function() return .5 end,getDayLightStrength=function() return .5 end,
    getClimateFloat=function(self,id) return weatherValues[id] end,
    getFogIntensity=function() return weatherValues[5].value end,
    getWindIntensity=function() return weatherValues[6].value end,
    getWindAngleIntensity=function() return weatherValues[7].value end,
    getPrecipitationIntensity=function() return weatherValues[3].value end,
    getCloudIntensity=function() return weatherValues[8].value end,
    getColorNewFog=function() return {getExterior=function() return {getRedFloat=function() return .5 end,getGreenFloat=function() return .5 end,getBlueFloat=function() return .5 end} end} end}
end
local floor={}
local square={getFloor=function() return floor end,getX=function() return math.floor(player.x) end,getY=function() return math.floor(player.y) end}
inventory={items={},AddItem=function(self,name)
    local item={name=name,on=false,charge=.2,getFullType=function(s) return s.name end,
        setUsedDelta=function(s,v) s.charge=v end,setActivated=function(s,v) s.on=v end,isActivated=function(s) return s.on end}
    self.items[#self.items+1]=item;return item
end,Remove=function(self,item) for i,v in ipairs(self.items) do if v==item then table.remove(self.items,i);return end end end}
player={x=1,y=2,z=0,god=true,invisible=true,ghost=true,running=false,sprinting=false,sneaking=true,primary={original=true},secondary={original=true}}
player.getPlayerNum=function() return 0 end
local methods={GodMod="god",Invisible="invisible",GhostMode="ghost",Running="running",Sprinting="sprinting",Sneaking="sneaking"}
for suffix,key in pairs(methods) do
    player["is"..suffix]=function(self) return self[key] end
    player["set"..suffix]=function(self,v) self[key]=v end
end
function player:setInvisible(v) self.invisible=v;self.ghost=v end
player.setGhostMode=player.setInvisible
function player:isGhostMode() return self.invisible end
function player:getPrimaryHandItem() return self.primary end
function player:getSecondaryHandItem() return self.secondary end
function player:setPrimaryHandItem(v) self.primary=v end
function player:setSecondaryHandItem(v) self.secondary=v end
function player:getInventory() return inventory end
function player:resetEquippedHandsModels() modelResets=(modelResets or 0)+1 end
function player:getVehicle() return self.vehicle end
function player:getSquare() return square end
function player:isDead() return false end
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:setMoving(v) self.moving=v end
function player:teleportTo(x,y,z) self.x=math.floor(x);self.y=math.floor(y);self.z=z;teleports=teleports+1 end
function player:setX(x) self.x=x end
function player:setY(y) self.y=y end
function player:setLastX(x) self.lastX=x end
function player:setLastY(y) self.lastY=y end
getPlayer=function() return player end
vehicles={}
function testVehicle(x,y)
    local v={x=x,y=y,getX=function(s) return s.x end,getY=function(s) return s.y end}
    function v:permanentlyRemove() self.removed=true;for i,item in ipairs(vehicles) do if item==self then table.remove(vehicles,i);break end end end
    vehicles[#vehicles+1]=v;return v
end
getCell=function() return {getVehicles=function() return {size=function() return #vehicles end,get=function(s,i) return vehicles[i+1] end} end} end
now=0;teleports=0;motion=0;interruption="";ended=nil;active=false

function world:setGameMode() end
SandboxVars={}
ActiveMods={getById=function() return {copyFrom=function() end} end}
DebugScenarios={instance={launchScenario=function(self,s) s.setSandbox();s.onStart() end}}
local function ignore() end
ModStudioScenario={clock=function() return now end,requested=function() return true end,
 context=function() return {definition=scenario,json="{}",output="test"} end,claim=function() return true end,
 event=function(k,v) journal[#journal+1]={k,v} end,error=function() return "" end,worldReady=ignore,
 finish=function(s,r) ended=s;reason=r end,closed=function() return true end}
ModStudioScenario.screenshot=function(name) screenshotName=name;screenshotPolls=0 end
ModStudioScenario.screenshotReady=function() screenshotPolls=screenshotPolls+1;return screenshotPolls>=3 end
ModStudioScenario.renderSnapshotPause=function(value) snapshotPaused=value end
ModStudioScenario.restoreReferenceLights=function() end
ModStudioScenario.renderSnapshot=function(name,x,y,z) assert(snapshotPaused);snapshotName=name;return true end
ModStudioScenario.clearVehicles=function(x0,y0,x1,y1)
    assert(core:isNoSave())
    local selected={}
    for _,v in ipairs(vehicles) do if v.x>=x0 and v.x<=x1 and v.y>=y0 and v.y<=y1 then
        assert(v~=player:getVehicle());selected[#selected+1]=v
    end end
    for _,v in ipairs(selected) do v:permanentlyRemove() end
    return #selected
end
journal={};quit=false;diag=false;diagClosed=true;ownedControl=false;beam=0;camera=1
ModStudioDriving={
 spawn=function() carSpawned=true;if spawnFailure then error('spawn failed') end end,
 spawnConfigured=function(script,heading,enter,headlights) carSpawned=true;carEntry=enter;carHeadlights=headlights;return not configuredSpawnFailure end,
 spawnConfiguredAt=function(script,heading,enter,headlights,x,y) carX=x;carY=y;return ModStudioDriving.spawnConfigured(script,heading,enter,headlights) end,
 drive=function() driving=true end,poll=function() return driveReady end,
 stop=function() driving=false end,close=function() driving=false;carClosed=true end}
PZ3DArchitectureScenario={command={start=function() end},clear=function() end}
PZ3DArchitecturePreview={command={start=function() end}}
PZ3D={ready=function() return true end,scenarioControlStart=function() ownedControl=true;return true end,scenarioControlEnd=function() ownedControl=false end,
 scenarioView=function() return {yaw=0,pitch=0} end,cameraMode=function(v) if v then camera=v end;return camera end,
 scenarioTakeControls=ignore,scenarioHeartbeat=ignore,scenarioInterruption=function() return interruption end,scenarioAdoptNativePosition=function() adopted=(adopted or 0)+1 end,
 scenarioClearMotion=function() motion=0 end,scenarioLook=ignore,scenarioMotion=function(f) motion=f end,
 scenarioDiagnosticsStart=function() diag=true;diagClosed=false;return true end,scenarioReady=function() return diag end,
 scenarioEnd=function() diag=false;diagClosed=true end,scenarioFinished=function() return diagClosed end,
 scenarioStatus=function() return "complete" end,scenarioPath=function() return "test/pz3d" end,scenarioPhase=ignore,scenarioSettled=function() return true end,
 scenarioCapture=ignore,scenarioCaptured=function() return true end,scenarioRenderState=function() return "coneHand="..beam end}
function advance(seconds) now=now+seconds;Events.OnTick.fire() end
lightingMode='current';lightingReady=true;lightingResets=0
PZ3D.lightingModeKnown=function(m) return m=='current' or m=='native' or m=='hybrid' end
PZ3D.lightingMode=function(m,a,b,c,d) lightingMode=m;return true end
PZ3D.lightingReady=function() return lightingReady end
PZ3D.lightingState=function() return {error='',cells=1,held=0} end
PZ3D.lightingReset=function() lightingMode='current';lightingResets=lightingResets+1 end
PZ3D.scenarioUi=function() end
local warp={warpMode=0,warpLateral=100,warpVertical=100,warpScale=2400,warpNear=192}
PZ3D.cameraDebugState=function() local copy={};for k,v in pairs(warp) do copy[k]=v end;return copy end
PZ3D.cameraDebugSet=function(k,v) warp[k]=v end
PZ3D.scenarioRenderState=function()
    return "coneHand="..beam.." warpMode="..warp.warpMode.." warpLateral="..warp.warpLateral.." warpVertical="..warp.warpVertical.." warpScaleM="..warp.warpScale.." warpNearM="..warp.warpNear
end
visualAction=nil;visualReady=true;visualClears=0
PZ3D.scenarioVisualConditionsKnown=function(a) return a=='install' or a=='a' or a=='b' or a=='missing' or a=='layers' or a=='unmatched' or a=='reload' or a=='unload' or a=='workload' or a=='clear' end
PZ3D.scenarioVisualConditions=function(a,output) assert(output=='test');visualAction=a end
PZ3D.scenarioVisualConditionsStatus=function() return visualReady and 'ready '..tostring(visualAction) or 'waiting' end
PZ3D.scenarioVisualConditionsClear=function() visualAction=nil;visualClears=visualClears+1 end
function pump(count,seconds) for i=1,count do advance(seconds or .1) end end
interactionAction=nil;interactionReady=true;interactionClears=0
PZ3D.scenarioInteractionKnown=function(a) return a=='select' or a=='toggle' or a=='clear' end
PZ3D.scenarioInteraction=function(a,k,r) interactionAction=a end
PZ3D.scenarioInteractionStatus=function() return interactionReady and 'ready '..tostring(interactionAction) or 'waiting render' end
PZ3D.scenarioInteractionClear=function() interactionAction=nil;interactionClears=interactionClears+1 end
chunkMode=false;chunkActive=false;chunkReady=false;chunkFlushes=0;chunkReset=false
PZ3D.scenarioChunkMode=function(iso) chunkMode=iso;if iso then camera=0 end end
PZ3D.scenarioChunkStart=function(output,name,x,y) assert(not chunkActive);chunkActive=true;chunkReady=false end
PZ3D.scenarioChunkPoll=function() return chunkActive and (chunkReady and 'ready native=1/1' or 'waiting native=0/1') or 'inactive' end
PZ3D.scenarioChunkFinish=function(status) if chunkActive then chunkActive=false;chunkFlushes=chunkFlushes+1;chunkResult=status end;return true end
PZ3D.scenarioChunkReset=function() chunkReset=true;chunkMode=false end

ModStudioScenario.spawnHuman=function(dx,dy) assert(not humanSpawned);humanSpawned=true;humanOffset={dx,dy};if humanFailure then error('human spawn failed') end end
ModStudioScenario.humanReady=function() return humanReady end
ModStudioScenario.clearHuman=function() humanSpawned=false;humanCleared=true end

ModStudioScenario.updateHuman=function() end

-- Native animal fixture contracts: all definitions, partial failure and cleanup.
spawnedAnimals={}
local function animalList(items)
    return {size=function() return #items end,get=function(self,i) return items[i+1] end}
end
getAllAnimalsDefinitions=function()
    local defs={}
    for _,name in ipairs({'rat','cow','calf'}) do
        local breed={getName=function() return 'native' end}
        defs[#defs+1]={getAnimalType=function() return name end,getBreeds=function() return animalList({breed}) end}
    end
    return animalList(defs)
end
getCell=function() return {getGridSquare=function(self,x,y,z)
    if animalBlocked then return nil end
    return {getFloor=function() return true end,isFree=function() return true end,getZ=function() return z end}
end} end
addAnimal=function(cell,x,y,z,name,breed,skeleton)
    if animalFailure and #spawnedAnimals==1 then error('animal spawn failed') end
    local a={getAnimalType=function() return name end,getAnimalSize=function() return 1 end,
        addToWorld=function(self) self.added=true end,removeFromWorld=function(self) self.removed=true end,
        removeFromSquare=function(self) self.squareRemoved=true end}
    spawnedAnimals[#spawnedAnimals+1]=a;return a
end
PZ3D.scenarioAnimalRendered=function() return animalRendered==true end

ModStudioScenario.humanLight=function(on,heading) assert(humanSpawned);humanLightOn=on;humanHeading=heading end

PZ3D.scenarioStaticHold=function(enabled) staticHeld=enabled end
PZ3D.scenarioWorldParity=function(action) return action=='compare' and 'compared=1 regions=1 differences=0 {}' or action end
PZ3D.scenarioDynamicProbe=function(enabled) dynamicProbed=enabled end
ModStudioScenario.savedWorld=function() return 'owned_test_world' end
ModStudioScenario.saveNativeWorld=function() assert(not core:isNoSave());nativeSaved=(nativeSaved or 0)+1 end
MainScreen={continueLatestSave=function(mode,name) resumedMode=mode;resumedWorld=name end}
nativeFrameRate=30
nativeUncapped=true
ModStudioScenario.frameUncapped=function() return nativeUncapped end
ModStudioScenario.setFrameUncapped=function(value) nativeUncapped=value end
ModStudioScenario.frameLimit=function() return nativeFrameRate end
ModStudioScenario.setFrameLimit=function(value) nativeFrameRate=value end
ModStudioScenario.frameSync=function() return core.vsync end
ModStudioScenario.setFrameSync=function(value) core.vsync=value end

ISExitVehicle={new=function(self,character) return {character=character,nativeExit=true} end}
ISTimedActionQueue.add=function(action) exitQueued=action;exitCount=(exitCount or 0)+1 end
