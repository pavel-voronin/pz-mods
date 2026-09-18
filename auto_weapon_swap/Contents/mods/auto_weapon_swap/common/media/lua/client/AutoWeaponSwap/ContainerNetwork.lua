require "AutoWeaponSwap/ContainerAddress"

AutoWeaponSwap = AutoWeaponSwap or {}
local AWS = AutoWeaponSwap
local Address = AutoWeaponSwapAddress
local pending = {}

local function valid(request)
    local player = request.player
    return getTimestampMs() - request.started <= 15000 and not player:isDead()
        and getSpecificPlayer(player:getPlayerNum()) == player
        and Address.resolve(request.address) == request.container
        and request.owner == (request.container:getVehiclePart() or request.container:getParent())
end

local function requestFor(player, container)
    for token, request in pairs(pending) do
        if not valid(request) then
            pending[token] = nil
        elseif request.player == player and request.container == container then
            return request, token
        end
    end
end

local function advance(token, request)
    if not valid(request) then pending[token] = nil; return end
    local id = request.owner:getModData().AutoWeaponSwapID
    if not id then return end
    if request.id and request.id ~= id then pending[token] = nil; return end
    if request.confirmed then
        local key = AWS.containerKey(request.player, request.container, false)
        if key then AWS.settings(request.player).containers[key] = true end
        pending[token] = nil
    elseif not request.sent then
        request.id = id
        request.sent = true
        local args = {}
        for key, value in pairs(request.address) do args[key] = value end
        args.request, args.id = token, id
        sendClientCommand(request.player, "AutoWeaponSwap", "containerID", args)
    end
end

function AWS.containerChecked(player, container)
    return requestFor(player, container) ~= nil or AWS.enabled(player, container)
end

function AWS.toggleWorldContainer(player, container)
    local request, token = requestFor(player, container)
    if request or AWS.enabled(player, container) then
        if token then pending[token] = nil end
        local key = AWS.containerKey(player, container, false)
        if key then AWS.settings(player).containers[key] = nil end
        return
    end
    local address = Address.of(container)
    if not address or not AWS.accessible(player, container, true) then return end
    local owner = container:getVehiclePart() or container:getParent()
    token = getRandomUUID()
    request = {player = player, container = container, owner = owner, address = address,
        id = owner:getModData().AutoWeaponSwapID, started = getTimestampMs()}
    pending[token] = request
    advance(token, request)
end

function AWS.onContainerID(module, command, args)
    if module ~= "AutoWeaponSwap" or command ~= "containerID" or type(args) ~= "table" then return end
    local request = pending[args.request]
    if not request then return end
    if not request.sent or type(args.id) ~= "string" or args.id ~= request.id then
        pending[args.request] = nil
        return
    end
    request.confirmed = true
    advance(args.request, request)
end

function AWS.updateContainerRequests()
    for token, request in pairs(pending) do advance(token, request) end
end

function AWS.onContainerRemoved(object)
    for token, request in pairs(pending) do
        if request.owner == object then pending[token] = nil end
    end
end

Events.OnServerCommand.Add(AWS.onContainerID)
Events.OnTickEvenPaused.Add(AWS.updateContainerRequests)
Events.OnObjectAboutToBeRemoved.Add(AWS.onContainerRemoved)
Events.OnGameStart.Add(function() pending = {} end)
