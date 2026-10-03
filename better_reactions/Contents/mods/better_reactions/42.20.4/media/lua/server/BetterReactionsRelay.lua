if not isServer() then return end
require "BetterReactionsShared"
local BR = BetterReactions
local lastShout = {}
local sequence = 0
local hornPlayers, hornSounds = {}, {}

local function relay(player, sound)
    local id = player:getOnlineID()
    local now = getTimestampMs()
    if lastShout[id] and now - lastShout[id] < 200 then return end
    lastShout[id] = now
    sequence = sequence + 1
    sendServerCommand(BR.MODULE, "shout", {
        x = math.floor(sound.x), y = math.floor(sound.y), z = math.floor(sound.z),
        radius = sound.radius, sequence = sequence, source = id,
    })
end

local function relayHorn(vehicle)
    local player, sound = hornPlayers[vehicle], hornSounds[vehicle]
    if not player or not sound then return end
    hornPlayers[vehicle], hornSounds[vehicle] = nil, nil
    relay(player, sound)
end

local function onCommand(module, command, player, args)
    if module == "vehicle" and command == "onHorn" and type(args) == "table"
        and args.state == "start" and player and not player:isDead() then
        local vehicle = player:getVehicle()
        if vehicle and vehicle:isDriver(player) and vehicle:getBatteryCharge() > 0 then
            hornPlayers[vehicle] = player
            relayHorn(vehicle)
        end
        return
    end
    if module ~= BR.MODULE or command ~= "shout" or type(args) ~= "table"
        or not player or player:isDead() then return end
    for _, key in ipairs({"x", "y", "z", "radius", "sequence"}) do
        if not BR.isFinite(args[key]) then return end
    end
    if args.sequence < 1 or args.sequence ~= math.floor(args.sequence)
        or args.radius <= 0 or args.radius > BR.shoutRadius(player)
        or math.abs(args.x - player:getX()) > 4 or math.abs(args.y - player:getY()) > 4
        or args.z ~= math.floor(player:getZ()) then return end
    relay(player, args)
end

Events.OnClientCommand.Add(onCommand)

-- The vanilla command handler may run before or after ours.
Events.OnWorldSound.Add(function(x, y, z, radius, volume, source)
    if radius ~= 150 or volume ~= 150 or not instanceof(source, "BaseVehicle") then return end
    hornSounds[source] = {x = x, y = y, z = z, radius = radius}
    relayHorn(source)
end)

Events.OnTick.Add(function()
    for vehicle in pairs(hornPlayers) do hornPlayers[vehicle] = nil end
    for vehicle in pairs(hornSounds) do hornSounds[vehicle] = nil end
end)
