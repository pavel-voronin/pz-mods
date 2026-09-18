-- Separate Lua environments model the server and two clients
local root = "Contents/mods/auto_weapon_swap/common/media/lua/"
local serial, now = 0, 1000
local outgoing, replies, clients = {}, {}, {}
local function list(values)
    values = values or {}
    function values:size() return #self end
    function values:get(i) return self[i+1] end
    return values
end
local function world(kind, id)
    local c = {}
    local owner = {data = {AutoWeaponSwapID = id, OtherMod = "keep"}, index = 0}
    local square = {getX=function() return 10 end,getY=function() return 20 end,getZ=function() return 0 end}
    function square:getObjects() return list(kind == "corpse" and {} or {owner}) end
    function square:getStaticMovingObjects() return list(kind == "corpse" and {owner} or {}) end
    function owner:getSquare() if not self.removed then return square end end
    function owner:getModData() return self.data end
    function owner:getObjectIndex() return self.removed and -1 or self.index end
    function owner:getStaticMovingObjectIndex() return self.removed and -1 or 0 end
    function owner:getObjectName() return "container" end
    function owner:getSprite() return {getName=function() return "crate_sprite" end} end
    function owner:getContainerIndex(value) return value == c and 0 or -1 end
    function owner:getContainerCount() return 1 end
    function owner:getContainerByIndex(index) if index == 0 then return c end end
    function owner:transmitModData() self.transmissions=(self.transmissions or 0)+1 end
    function c:getType() return kind == "vehicle" and "trunk" or "crate" end
    function c:getContainingItem() return nil end
    function c:getParent() return owner end
    function c:getVehiclePart() return self.part end
    if kind == "corpse" then owner.class="IsoDeadBody" end
    local vehicle
    if kind == "vehicle" then
        vehicle={getId=function() return 7 end,getX=function() return 10 end,
            getY=function() return 20 end,getZ=function() return 0 end}
        function vehicle:getPartById(id) if id == "TruckBed" then return owner end end
        function vehicle:getPartCount() return 1 end
        function vehicle:getPartByIndex(i) if i==0 then return owner end end
        function vehicle:transmitPartModData(part) assert(part==owner);owner:transmitModData() end
        function owner:getVehicle() return vehicle end
        function owner:getId() return "TruckBed" end
        function owner:getItemContainer() return c end
        c.part=owner
    end
    return {container=c,owner=owner,square=square,vehicle=vehicle}
end
local function environment(server,worldObject)
    local env=setmetatable({world=worldObject,AutoWeaponSwap={},Events={}}, {__index=_G})
    env._G=env
    for _,key in ipairs({"OnPlayerUpdate","OnPlayerAttackFinished","OnServerCommand","OnGameStart",
        "OnTickEvenPaused","OnObjectAboutToBeRemoved","LoadGridsquare","OnObjectAdded",
        "OnSpawnVehicleEnd","OnTick","OnClientCommand"}) do
        local e={handlers={}}
        e.Add=function(fn) e.handlers[#e.handlers+1]=fn end
        env.Events[key]=e
    end
    function env.isClient() return not server end
    function env.isServer() return server end
    function env.instanceof(obj,class) return obj and obj.class==class end
    function env.getTimestampMs() return now end
    function env.getRandomUUID() serial=serial+1;return "uuid-"..serial end
    function env.getCell() return {
        getGridSquare=function(_,x,y,z) if x==10 and y==20 and z==0 then return env.world.square end end,
        getVehicles=function() return list(env.world.vehicle and {env.world.vehicle} or {}) end}
    end
    function env.getVehicleById(id) if id==7 then return env.world.vehicle end end
    function env.getOnlinePlayers() return list(env.online or {}) end
    local loaded={}
    function env.require(name)
        if loaded[name] or not name:match('^AutoWeaponSwap/') then return end
        loaded[name]=true
        local side=name=='AutoWeaponSwap/ContainerAddress' and 'shared/' or 'client/'
        setfenv(assert(loadfile(root..side..name..'.lua')),env)()
    end
    function env.sendClientCommand(player,module,command,args)
        outgoing[#outgoing+1]={player=player,module=module,command=command,args=args,client=env}
    end
    function env.sendServerCommand(player,module,command,args)
        replies[#replies+1]={module=module,command=command,args=args,client=clients[player]}
    end
    if server then
        setfenv(assert(loadfile(root..'server/AutoWeaponSwap/ContainerServer.lua')),env)()
    else
        local p={data={},inventory={}}
        function p:getModData() return self.data end
        function p:getInventory() return self.inventory end
        function p:getPlayerNum() return 0 end
        function p:isDead() return self.dead end
        function p:getX() return self.x or 10 end
        function p:getY() return 20 end
        function p:getZ() return 0 end
        env.player=p;clients[p]=env
        function env.getSpecificPlayer() return env.player end
        env.require('AutoWeaponSwap/Core')
        env.AutoWeaponSwap.accessible=function(_,c) return c==env.world.container end
    end
    return env
end
local function fixture(kind,id)
    outgoing,replies,clients={},{},{}
    local s=environment(true,world(kind,id))
    local a,b=environment(false,world(kind,id)),environment(false,world(kind,id))
    s.online={a.player,b.player}
    return s,a,b
end
local function provision(s)
    if s.world.vehicle then s.AutoWeaponSwapServer.onVehicle(s.world.vehicle)
    else s.AutoWeaponSwapServer.onSquare(s.world.square) end
end
local function sync(s,c)
    c.world.owner.data.AutoWeaponSwapID=s.world.owner.data.AutoWeaponSwapID
    c.AutoWeaponSwap.updateContainerRequests()
end
local function toggle(c) c.AutoWeaponSwap.toggleContainer(c.player,c.world.container) end
local function enabled(c) return c.AutoWeaponSwap.enabled(c.player,c.world.container) end
local function checked(c) return c.AutoWeaponSwap.containerChecked(c.player,c.world.container) end
local function process(s,i)
    local msg=outgoing[i]
    s.AutoWeaponSwapServer.onCommand(msg.module,msg.command,msg.player,msg.args)
end
local function deliver(i)
    local msg=replies[i]
    msg.client.AutoWeaponSwap.onContainerID(msg.module,msg.command,msg.args)
end
local count=0
local function check(name,fn) fn();count=count+1;print('PASS '..name) end
check('loaded containers get one ID before either client enables them',function()
    local s,a,b=fixture();provision(s)
    local id=s.world.owner.data.AutoWeaponSwapID
    assert(id and #outgoing==0)
    provision(s);assert(s.world.owner.data.AutoWeaponSwapID==id and s.world.owner.transmissions==1)
    sync(s,a);sync(s,b);toggle(a);toggle(b)
    assert(not enabled(a) and checked(a) and not enabled(b))
    process(s,1);process(s,2);deliver(2);deliver(1)
    assert(enabled(a) and enabled(b))
    toggle(a);assert(not enabled(a) and enabled(b))
    assert(not a.world.owner.transmissions and a.world.owner.data.OtherMod=='keep')
end)
check('an identical replacement cannot accept a request for the old ID',function()
    for _,kind in ipairs({'object','vehicle','corpse'}) do
        local s,a=fixture(kind,'old-container');toggle(a)
        s.world=world(kind);provision(s)
        local freshID=s.world.owner.data.AutoWeaponSwapID
        process(s,1);deliver(1)
        assert(not enabled(a) and not checked(a))
        assert(a.world.owner.data.AutoWeaponSwapID=='old-container')
        assert(not a.AutoWeaponSwap.settings(a.player).containers['object:'..freshID..':0'])
    end
end)
check('a valid old acknowledgement cannot enable a later replacement',function()
    local s,a=fixture(nil,'old-container');toggle(a);process(s,1)
    s.world=world();provision(s)
    deliver(1)
    assert(enabled(a))
    a.world=world();sync(s,a)
    assert(not enabled(a))
end)
check('replacement on the client before acknowledgement cancels the request',function()
    local s,a=fixture(nil,'old-container');toggle(a);process(s,1)
    local old=a.world.owner
    s.world=world();provision(s);a.world=world();sync(s,a);deliver(1)
    assert(not enabled(a) and old.data.AutoWeaponSwapID=='old-container')
end)
check('missing IDs wait for object sync without requesting or assigning one',function()
    local s,a=fixture();toggle(a)
    assert(checked(a) and not enabled(a) and #outgoing==0)
    a.AutoWeaponSwap.updateContainerRequests();assert(#outgoing==0)
    provision(s);sync(s,a);assert(#outgoing==1 and not enabled(a))
    process(s,1);deliver(1);assert(enabled(a))
end)
check('removal or disabling while waiting cancels the intended enable',function()
    local s,a=fixture();toggle(a);toggle(a);provision(s);sync(s,a)
    assert(not checked(a) and #outgoing==0)
    s,a=fixture();toggle(a)
    a.AutoWeaponSwap.onContainerRemoved(a.world.owner)
    provision(s);sync(s,a);assert(not checked(a) and #outgoing==0)
    s,a=fixture();toggle(a);a.world=world();provision(s);sync(s,a)
    assert(not checked(a) and #outgoing==0)
end)
check('late and duplicate replies respect the latest toggle',function()
    local s,a=fixture(nil,'existing');toggle(a);toggle(a);toggle(a)
    assert(#outgoing==2)
    process(s,1);deliver(1);assert(not enabled(a) and checked(a))
    process(s,2);deliver(2);assert(enabled(a))
    toggle(a);deliver(2);assert(not enabled(a))
end)
check('acknowledgement waits for matching local modData and never writes it',function()
    local s,a=fixture(nil,'existing');toggle(a);process(s,1)
    a.world.owner.data.AutoWeaponSwapID=nil
    deliver(1);assert(not enabled(a) and a.world.owner.data.AutoWeaponSwapID==nil)
    sync(s,a);assert(enabled(a))
    s,a=fixture(nil,'existing');toggle(a);process(s,1)
    a.world.owner.data.AutoWeaponSwapID='different';deliver(1)
    assert(not enabled(a) and a.world.owner.data.AutoWeaponSwapID=='different')
end)
check('existing IDs and saved personal choices survive provisioning and reload',function()
    local s,a,b=fixture(nil,'saved-container')
    a.AutoWeaponSwap.settings(a.player).containers['object:saved-container:0']=true
    provision(s);assert(s.world.owner.data.AutoWeaponSwapID=='saved-container' and not s.world.owner.transmissions)
    local restored=environment(false,world(nil,'saved-container'));restored.player.data=a.player.data
    assert(enabled(restored) and not enabled(b))
end)
check('server lifecycle covers crates, corpse scans and loaded vehicle parts',function()
    local s,a=fixture();s.Events.OnObjectAdded.handlers[1](s.world.owner)
    assert(s.world.owner.data.AutoWeaponSwapID)
    s,a=fixture('vehicle');s.Events.OnSpawnVehicleEnd.handlers[1](s.world.vehicle)
    assert(s.world.owner.data.AutoWeaponSwapID)
    s,a=fixture('corpse');s.Events.OnTick.handlers[1]()
    assert(s.world.owner.data.AutoWeaponSwapID)
    s,a=fixture('vehicle');s.Events.OnTick.handlers[1]()
    assert(s.world.owner.data.AutoWeaponSwapID)
end)
check('expired, dead-player and invalid-address requests do not enable containers',function()
    local s,a=fixture(nil,'existing');toggle(a);process(s,1);now=now+16000;deliver(1);assert(not enabled(a))
    s,a=fixture(nil,'existing');toggle(a);process(s,1);a.player.dead=true;deliver(1);assert(not enabled(a))
    s,a=fixture(nil,'existing');toggle(a);outgoing[1].args.index=-1;process(s,1);deliver(1);assert(not enabled(a))
    s,a=fixture(nil,'existing');toggle(a);a.player.x=500;process(s,1);deliver(1);assert(not enabled(a))
    s,a=fixture();provision(s)
    s.AutoWeaponSwapServer.onCommand('AutoWeaponSwap','containerID',a.player,{request='no-id'})
    assert(not replies[1].args.id)
end)
check('vehicle and corpse permissions require their synced IDs',function()
    for _,kind in ipairs({'vehicle','corpse'}) do
        local s,a,b=fixture(kind);provision(s);sync(s,a);sync(s,b)
        toggle(a);toggle(b);process(s,1);process(s,2);deliver(1);deliver(2)
        assert(enabled(a) and enabled(b))
        toggle(a);assert(not enabled(a) and enabled(b))
    end
end)
check('single-player uses UUIDs immediately and bags retain item IDs',function()
    local s,a=fixture()
    a.isClient=function() return false end
    toggle(a)
    assert(enabled(a) and a.world.owner.data.AutoWeaponSwapID:match('^uuid%-') and #outgoing==0)
    local id=a.world.owner.data.AutoWeaponSwapID
    toggle(a);toggle(a);assert(a.world.owner.data.AutoWeaponSwapID==id)
    s,a=fixture()
    a.world.container.getContainingItem=function() return {getID=function() return 42 end} end
    toggle(a)
    assert(a.AutoWeaponSwap.containerKey(a.player,a.world.container,false)=='item:42')
    assert(enabled(a) and #outgoing==0 and not a.world.owner.data.AutoWeaponSwapID)
end)
print(count..' isolated client/server scenarios passed (no live server)')
