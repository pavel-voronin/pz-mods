if not getDebug() then return end
require "ModStudio/ScenarioAPI"
ModStudio.Network={}
local N=ModStudio.Network
function N.bootstrap(c)
    if not isClient() or getPlayer() then return end
    if ConnectToServer and ConnectToServer.instance and ConnectToServer.instance.failMessage then error("Native connection failed: "..ConnectToServer.instance.failMessage) end
    local screen=MainScreen.instance
    if not screen then return end
    if MapSpawnSelect and MapSpawnSelect.instance and MapSpawnSelect.instance:isVisible() then MapSpawnSelect.instance:clickNext();c.event("network-create","native spawn region") end
    if screen.charCreationProfession and screen.charCreationProfession:isVisible() then screen.charCreationProfession:onOptionMouseDown({internal="NEXT"},0,0);c.event("network-create","native profession") end
    if screen.charCreationMain and screen.charCreationMain:isVisible() then
        screen.charCreationMain:onOptionMouseDown({internal="NEXT"},0,0)
        c.event("network-create","native character; loading queue")
    end
end
local function number(s,key,min,max,optional)
    local v=s[key];assert(optional and v==nil or type(v)=="number" and v==v and v>=min and v<=max,"Invalid network "..key)
end
local function coordinates(s)
    number(s,"x",0,100000);number(s,"y",0,100000);number(s,"z",-32,31,true)
    assert(s.x%1==0 and s.y%1==0 and (s.z==nil or s.z%1==0),"Network object coordinates must be integers")
end
local function inventoryItem(c,id)
    local items=c.player:getInventory():getItems()
    for i=0,items:size()-1 do local item=items:get(i);if item:getID()==id then return item end end
end
function N.give(c,s)
    assert(string.match(s.type,"^[A-Za-z0-9_]+%.[A-Za-z0-9_]+$"),"Invalid native item type")
    local user=c.player:getUsername();assert(string.match(user,"^[A-Za-z0-9_]+$"),"Invalid native username")
    c.networkGivenBefore={}
    local items=c.player:getInventory():getItems()
    for i=0,items:size()-1 do c.networkGivenBefore[items:get(i):getID()]=true end
    SendCommandToServer('/additem "'..user..'" "'..s.type..'"')
    c.event("network-give","native admin request "..s.type)
end
function N.given(c,s)
    local items=c.player:getInventory():getItems()
    for i=0,items:size()-1 do local item=items:get(i)
        if item:getFullType()==s.type and not c.networkGivenBefore[item:getID()] then
            c.event("network-issued",s.type.." id="..item:getID());return item
        end
    end
end
local function peer(c)
    local all=getOnlinePlayers()
    for i=0,all:size()-1 do local p=all:get(i);if p:getUsername()==c.definition.multiplayer.peer and p~=c.player then return p end end
end
local function position(p) return string.format("%s id=%s x=%.3f y=%.3f z=%.3f running=%s moving=%s",p:getUsername(),tostring(p:getOnlineID()),p:getX(),p:getY(),p:getZ(),tostring(p:isRunning()),tostring(p:isMoving())) end
local function window(s)
    local square=getCell():getGridSquare(s.x,s.y,s.z or 0);if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do local o=objects:get(i);if instanceof(o,"IsoWindow") then return o end end
    error("No native window at requested square")
end
local function nearbyItem(c,s)
    local p=c.player
    for x=math.floor(p:getX())-3,math.floor(p:getX())+3 do for y=math.floor(p:getY())-3,math.floor(p:getY())+3 do
        local sq=getCell():getGridSquare(x,y,math.floor(p:getZ()))
        if sq then local items=sq:getWorldObjects();for i=0,items:size()-1 do local w=items:get(i);local item=w:getItem();if item and item:getFullType()==s.type then return w end end end
    end end
end
local function door(s)
    local square=getCell():getGridSquare(s.x,s.y,s.z or 0);if not square then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do local object=objects:get(i);if instanceof(object,"IsoDoor") or instanceof(object,"IsoThumpable") and object:isDoor() then return object end end
    error("No native door at requested square")
end
N.commands={
    door={validate=function(s) coordinates(s);assert(type(s.open)=="boolean" and (s.change==nil or type(s.change)=="boolean"),"Invalid door check") end,
        start=function(c,s) c.networkAttempted=false end,
        tick=function(c,s,t)
            local object=door(s);if not object then return false end
            if s.change and not c.networkAttempted then
                assert(math.abs(c.player:getX()-s.x)<3 and math.abs(c.player:getY()-s.y)<3,"Door is not adjacent")
                assert(object:IsOpen()~=s.open,"Door fixture already has target state")
                c.networkAttempted=true;c.nativeAction("timedAction",s)
                ISWorldObjectContextMenu.onOpenCloseDoor({},object,c.player:getPlayerNum())
                c.event("network-door-request","x="..s.x.." y="..s.y.." open="..tostring(s.open))
            end
            if object:IsOpen()~=s.open then return false end
            c.event("network-door","x="..s.x.." y="..s.y.." open="..tostring(object:IsOpen()).." changed="..tostring(s.change==true));return true
        end},
    cell={validate=function(s) coordinates(s);assert(s.kind==nil or s.kind=="tree" and s.sprite==nil,"Invalid network cell kind");assert(s.kind=="tree" or type(s.sprite)=="string" and #s.sprite>0 and #s.sprite<=256 and string.match(s.sprite,"^[A-Za-z0-9_]+$"),"Invalid network sprite");number(s,"count",0,1024);assert(s.count%1==0,"Invalid network cell count") end,
        start=function(c,s) end,
        tick=function(c,s,t)
            local square=getCell():getGridSquare(s.x,s.y,s.z or 0);if not square then
                if s.count==0 and ModStudioScenario.loadedEmptyCell(s.x,s.y,s.z or 0) then c.event("network-cell","x="..s.x.." y="..s.y.." z="..(s.z or 0).." selector="..tostring(s.sprite or s.kind).." count=0 authority=loaded-empty-cell");return true end
                return false
            end
            local objects=square:getObjects();local count=0
            for i=0,objects:size()-1 do if ModStudioScenarioObjects.matches(objects:get(i),s) then count=count+1 end end
            if count~=s.count then return false end
            c.event("network-cell","x="..s.x.." y="..s.y.." z="..(s.z or 0).." selector="..tostring(s.sprite or s.kind).." count="..count);return true
        end},
    window={validate=function(s) coordinates(s);assert(type(s.open)=="boolean" and (s.change==nil or type(s.change)=="boolean"),"Invalid window check") end,
        start=function(c,s) c.networkAttempted=false;c.networkPoll=0 end,
        tick=function(c,s,t)
            local w=window(s);if not w then return false end
            if s.change and not c.networkAttempted then
                assert(math.abs(c.player:getX()-s.x)<3 and math.abs(c.player:getY()-s.y)<3,"Window is not adjacent")
                assert(w:IsOpen()~=s.open,"Window fixture already has target state")
                c.networkAttempted=true;c.nativeAction("timedAction",s)
                ISWorldObjectContextMenu.onOpenCloseWindow({},w,c.player:getPlayerNum())
                c.event("network-window-request","locked="..tostring(w:isLocked()).." blocked="..tostring(c.player:isBlockMovement()))
            end
            if w:IsOpen()~=s.open then if s.change and t>=c.networkPoll then local q=ISTimedActionQueue.getTimedActionQueue(c.player);local a=q and q.queue[1];c.event("network-window-wait","queue="..tostring(q and #q.queue or 0).." action="..tostring(a and a.Type).." x="..c.player:getX().." y="..c.player:getY().." locked="..tostring(w:isLocked()).." blocked="..tostring(c.player:isBlockMovement()));c.networkPoll=t+1 end;return false end
            c.event("network-window","x="..s.x.." y="..s.y.." open="..tostring(w:IsOpen()).." changed="..tostring(s.change==true));return true
        end},
    climb={validate=function(s) coordinates(s) end,
        start=function(c,s) c.networkAttempted=false;c.networkSawClimb=false;c.networkClimbOrigin={x=c.player:getX(),y=c.player:getY()} end,
        tick=function(c,s,t)
            local w=window(s);if not w then return false end
            if not c.networkAttempted then
                assert(w:IsOpen(),"Climb requires an open native window")
                c.networkAttempted=true;c.nativeAction("timedAction",s)
                ISWorldObjectContextMenu.onClimbThroughWindow({},w,c.player:getPlayerNum())
            end
            local p=c.player;local sq=p:getSquare();local o=c.networkClimbOrigin
            local climbing=p:isCurrentState(ClimbThroughWindowState.instance())
            c.networkSawClimb=c.networkSawClimb or climbing
            local north=w:getNorth();local plane=north and s.y or s.x
            local before=(north and o.y or o.x)-plane;local after=(north and p:getY() or p:getX())-plane
            if not sq or not c.networkSawClimb or climbing or before*after>=0 then return false end
            c.event("network-climb",position(p));return true
        end},
    drop={validate=function(s) assert(type(s.id)=="string","Drop requires issued item id") end,
        start=function(c,s) local item=c.items[s.id];assert(item,"Missing issued item");ISInventoryPaneContextMenu.dropItem(item,c.player:getPlayerNum()) end,
        tick=function(c,s,t)
            local item=c.items[s.id];local w=nearbyItem(c,{type=item:getFullType()});if not w or w:getItem():getID()~=item:getID() or inventoryItem(c,item:getID()) then return false end
            c.event("network-drop",item:getFullType().." id="..item:getID());return true
        end},
    item={validate=function(s) assert(type(s.type)=="string" and #s.type>0 and #s.type<=128 and (s.present==nil or type(s.present)=="boolean") and (s.pickup==nil or type(s.pickup)=="boolean"),"Invalid network item") end,
        start=function(c,s) c.networkAttempted=false;c.networkPoll=0 end,
        tick=function(c,s,t)
            local w=nearbyItem(c,s)
            if s.pickup and not c.networkAttempted then
                if not w then return false end;c.networkAttempted=true;c.networkItem=w:getItem()
                ISTimedActionQueue.add(ISGrabItemAction:new(c.player,w,50))
            end
            if s.pickup then
                if not c.networkItem or not inventoryItem(c,c.networkItem:getID()) then return false end
                c.event("network-pickup",c.networkItem:getFullType().." id="..c.networkItem:getID());return true
            end
            if (w~=nil)~=(s.present~=false) then return false end
            c.event("network-item",s.type.." present="..tostring(w~=nil)..(w and " id="..w:getItem():getID() or ""));return true
        end},
    peer={validate=function(s)
        assert(s.checkpoint==nil or type(s.checkpoint)=="string" and string.match(s.checkpoint,"^[a-z0-9_-]+$") and #s.checkpoint<=60,"Invalid peer checkpoint")
        for _,key in ipairs({"x","y","tolerance"}) do local v=s[key];assert(v==nil or type(v)=="number" and v==v and v>=0 and v<=100000,"Invalid peer coordinate") end
    end,start=function(c,s) c.peerLast=nil end,tick=function(c,s,t)
        local p=peer(c);if not p or not p:getSquare() then return false end
        local expected=s
        if s.checkpoint then expected=ModStudioScenario.checkpoint(s.checkpoint,c.definition.multiplayer.peer) end
        if s.checkpoint and not expected then return false end
        if expected.onlineID then assert(p:getOnlineID()==expected.onlineID,"Checkpoint player identity changed") end
        if expected.z and math.abs(p:getZ()-expected.z)>.1 then return false end
        if expected.x and math.abs(p:getX()-expected.x)>(s.tolerance or .8) then return false end
        if expected.y and math.abs(p:getY()-expected.y)>(s.tolerance or .8) then return false end
        assert(p:getOnlineID()~=c.player:getOnlineID(),"Peer is local player")
        c.event("network-peer",position(p));return true
    end},
    barrier={validate=function(s) assert(type(s.name)=="string" and string.match(s.name,"^[a-z0-9_-]+$") and #s.name<=60,"Invalid barrier") end,
        start=function(c,s) ModStudioScenario.signal(s.name);c.networkPoll=0 end,
        tick=function(c,s,t) if t<c.networkPoll then return false end;c.networkPoll=t+.25;return ModStudioScenario.signaled(s.name,c.definition.multiplayer.peer) end},
    focus={start=function(c) ModStudioScenario.focus() end,tick=function(c,s,t) return t>1 end},
    observe={validate=function(s) number(s,"seconds",.1,600);number(s,"distance",0,100000,true);assert(s.run==nil or type(s.run)=="boolean","Invalid running observation") end,
        start=function(c,s) c.networkRange=nil;c.networkPoll=0 end,
        tick=function(c,s,t)
            local p=peer(c);if not p then return false end
            if not c.networkRange then c.networkRange={x=p:getX(),y=p:getY(),distance=0,running=false} end
            local r=c.networkRange;r.distance=math.max(r.distance,math.sqrt((p:getX()-r.x)^2+(p:getY()-r.y)^2));r.running=r.running or p:isRunning()
            if t>=c.networkPoll then c.event("network-sample",position(p));c.networkPoll=t+1 end
            if t<s.seconds then return false end
            assert(r.distance>=(s.distance or 0),"Peer movement was not replicated: "..r.distance)
            if s.run then assert(r.running,"Peer running flag was not replicated") end
            c.event("network-observed","distance="..r.distance.." running="..tostring(r.running));return true
        end},
}
