if not isServer() then return end
require "AutoWeaponSwap/ContainerAddress"

AutoWeaponSwapServer = {}
local Server = AutoWeaponSwapServer
local Address = AutoWeaponSwapAddress

function Server.onObject(object)
    if not object or object:getContainerCount() == 0 then return end
    local data = object:getModData()
    if data.AutoWeaponSwapID then return end
    data.AutoWeaponSwapID = getRandomUUID()
    object:transmitModData()
end

function Server.onSquare(square)
    if not square then return end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do Server.onObject(objects:get(i)) end
    local bodies = square:getStaticMovingObjects()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if instanceof(body, "IsoDeadBody") then Server.onObject(body) end
    end
end

function Server.onVehicle(vehicle)
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part:getItemContainer() and not part:getModData().AutoWeaponSwapID then
            part:getModData().AutoWeaponSwapID = getRandomUUID()
            vehicle:transmitPartModData(part)
        end
    end
end

local nextScan = 0
function Server.onTick()
    local now = getTimestampMs()
    if now < nextScan then return end
    nextScan = now + 500
    -- Corpse creation has no server event
    local players = getOnlinePlayers()
    local visited = {}
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        local x, y, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
        for dx = -3, 3 do
            for dy = -3, 3 do
                local square = getCell():getGridSquare(x + dx, y + dy, z)
                if square and not visited[square] then
                    visited[square] = true
                    Server.onSquare(square)
                end
            end
        end
    end
    -- Also covers containers installed after a vehicle spawned
    local vehicles = getCell():getVehicles()
    for i = 0, vehicles:size() - 1 do Server.onVehicle(vehicles:get(i)) end
end

function Server.onCommand(module, command, player, args)
    if module ~= "AutoWeaponSwap" or command ~= "containerID" then return end
    if not player or player:isDead() or type(args) ~= "table"
        or type(args.request) ~= "string" or #args.request > 100 then return end
    local container, owner, part = Address.resolve(args)
    local id
    if container and type(args.id) == "string" and args.id ~= ""
        and owner:getModData().AutoWeaponSwapID == args.id then
        local location = part and part:getVehicle() or owner:getSquare()
        local distance = part and 10 or 3
        if math.abs(player:getX() - location:getX()) <= distance
            and math.abs(player:getY() - location:getY()) <= distance
            and math.floor(player:getZ()) == math.floor(location:getZ()) then
            id = args.id
        end
    end
    sendServerCommand(player, "AutoWeaponSwap", "containerID", {request = args.request, id = id})
end

Events.LoadGridsquare.Add(Server.onSquare)
Events.OnObjectAdded.Add(Server.onObject)
Events.OnSpawnVehicleEnd.Add(Server.onVehicle)
Events.OnTick.Add(Server.onTick)
Events.OnClientCommand.Add(Server.onCommand)
