require=function() end
getDebug=function() return true end
isClient=function() return false end
isServer=function() return false end
Events={}
for _,name in ipairs({"OnTick","OnTickEvenPaused","OnMainMenuEnter","OnFETick"}) do
    local e={handlers={}}
    e.Add=function(f) e.handlers[#e.handlers+1]=f end
    e.fire=function() for _,f in ipairs(e.handlers) do f() end end
    Events[name]=e
end
UIManager={isShowLuaDebuggerOnError=function() return true end,setShowLuaDebuggerOnError=function() end}
core={isNoSave=function() return true end,setNoSave=function() end,quitToDesktop=function() quit=true end}
getCore=function() return core end
world={getWorld=function() return "test" end,getMap=function() return "fixture" end}
getWorld=function() return world end
getActivatedMods=function() return {size=function() return 0 end} end
ISTimedActionQueue={clear=function() end}
tm={hour=9,getTimeOfDay=function(self) return self.hour end,setTimeOfDay=function(self,v) self.hour=v end}
getGameTime=function() return tm end
local floor={}
local square={getFloor=function() return floor end,getX=function() return math.floor(player.x) end,getY=function() return math.floor(player.y) end}
inventory={items={},AddItem=function(self,name)
    local item={name=name,on=false,charge=.2,getFullType=function(s) return s.name end,
        setUsedDelta=function(s,v) s.charge=v end,setActivated=function(s,v) s.on=v end,isActivated=function(s) return s.on end}
    self.items[#self.items+1]=item;return item
end,Remove=function(self,item) for i,v in ipairs(self.items) do if v==item then table.remove(self.items,i);return end end end}
player={x=1,y=2,z=0,god=true,invisible=false,ghost=true,running=false,sprinting=false,sneaking=true,primary={original=true},secondary={original=true}}
local methods={GodMod="god",Invisible="invisible",GhostMode="ghost",Running="running",Sprinting="sprinting",Sneaking="sneaking"}
for suffix,key in pairs(methods) do
    player["is"..suffix]=function(self) return self[key] end
    player["set"..suffix]=function(self,v) self[key]=v end
end
function player:getPrimaryHandItem() return self.primary end
function player:getSecondaryHandItem() return self.secondary end
function player:setPrimaryHandItem(v) self.primary=v end
function player:setSecondaryHandItem(v) self.secondary=v end
function player:getInventory() return inventory end
function player:getVehicle() return nil end
function player:getSquare() return square end
function player:isDead() return false end
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:setMoving(v) self.moving=v end
function player:teleportTo(x,y,z) self.x=math.floor(x);self.y=math.floor(y);self.z=z;teleports=teleports+1 end
getPlayer=function() return player end
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
journal={};quit=false;diag=false;diagClosed=true;ownedControl=false;beam=0;camera=1
PZ3D={scenarioControlStart=function() ownedControl=true;return true end,scenarioControlEnd=function() ownedControl=false end,
 scenarioView=function() return {yaw=0,pitch=0} end,cameraMode=function(v) if v then camera=v end;return camera end,
 scenarioTakeControls=ignore,scenarioHeartbeat=ignore,scenarioInterruption=function() return interruption end,scenarioAdoptNativePosition=function() adopted=(adopted or 0)+1 end,
 scenarioClearMotion=function() motion=0 end,scenarioLook=ignore,scenarioMotion=function(f) motion=f end,
 scenarioDiagnosticsStart=function() diag=true;diagClosed=false;return true end,scenarioReady=function() return diag end,
 scenarioEnd=function() diag=false;diagClosed=true end,scenarioFinished=function() return diagClosed end,
 scenarioStatus=function() return "complete" end,scenarioPath=function() return "test/pz3d" end,scenarioPhase=ignore,scenarioSettled=function() return true end,
 scenarioCapture=ignore,scenarioCaptured=function() return true end,scenarioRenderState=function() return "coneHand="..beam end}
function advance(seconds) now=now+seconds;Events.OnTick.fire() end
function pump(count,seconds) for i=1,count do advance(seconds or .1) end end
