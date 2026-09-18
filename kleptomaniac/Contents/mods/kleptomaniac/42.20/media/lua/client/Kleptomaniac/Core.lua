require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferAction"
require "Moveables/ISMoveablesAction"
require "Moveables/ISMoveableSpriteProps"

Kleptomaniac = Kleptomaniac or {}
local K = Kleptomaniac
local active = {}
local receipts = {}
local revision = 0
local nextTick = 0
local RECEIPT_CHECK_MS = 10000

function K.enabled()
    local options = SandboxVars.Kleptomaniac
    return not options or ((tonumber(options.MaxWeight) or 2) > 0
        and (tonumber(options.IntervalMinutes) or 40) > 0)
end

function K.hasTrait(player)
    return player:hasTrait(KleptomaniacTrait)
end

function K.gameMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

function K.settings()
    local options = SandboxVars.Kleptomaniac or {}
    return math.max(0, math.min(10080, tonumber(options.IntervalMinutes) or 40)),
        math.max(0, math.min(50, tonumber(options.MaxWeight) or 2)),
        math.max(1, math.min(10080, tonumber(options.RetryMinutes) or 10))
end

function K.state(player)
    local data = player:getModData()
    if not data.Kleptomaniac then
        data.Kleptomaniac = { lastSuccess = K.gameMinutes(), pending = false }
    end
    return data.Kleptomaniac
end

function K.updateUrge(player)
    if not K.enabled() then return false end
    local state = K.state(player)
    local now = K.gameMinutes()
    local interval = K.settings()
    if not state.lastSuccess or state.lastSuccess > now then state.lastSuccess = now end
    if now - state.lastSuccess + 0.000001 >= interval then state.pending = true end
    return state.pending
end

function K.satisfy(player)
    if not K.enabled() then return end
    local state = K.state(player)
    state.pending = false
    state.lastSuccess = K.gameMinutes()
    state.inFlight = nil
    state.retryStarted = nil
    receipts[player] = nil
end

function K.cancel(player)
    if not K.enabled() then return end
    local state = K.state(player)
    state.pending = true
    state.retryStarted = state.retryStarted or K.gameMinutes()
    if not isClient() then state.inFlight = nil end
end

function K.retryReady(player)
    local state = K.state(player)
    if not state.retryStarted then return true end
    local _, _, delay = K.settings()
    local now = K.gameMinutes()
    if state.retryStarted > now then state.retryStarted = now end
    return now - state.retryStarted + 0.000001 >= delay
end

function K.allowedWeight(item, limit)
    limit = limit or select(2, K.settings())
    -- Includes bag contents and fluids.
    return limit > 0 and item and item:getUnequippedWeight() <= limit + 0.000001
end

function K.wornBags(player)
    local result = {}
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        if instanceof(item, "InventoryContainer") then
            result[#result + 1] = item:getInventory()
        end
    end
    return result
end

function K.destination(player, item, bags)
    for _, bag in ipairs(bags or K.wornBags(player)) do
        if bag:hasRoomFor(player, item) and not bag:isInside(item) then return bag end
    end
    local inventory = player:getInventory()
    if inventory:hasRoomFor(player, item) then return inventory end
end

function K.reachable(player, square)
    local current = player:getSquare()
    if not current or not square or current:getZ() ~= square:getZ() then return false end
    if math.abs(current:getX() - square:getX()) > 1
        or math.abs(current:getY() - square:getY()) > 1 then return false end
    if current ~= square and not current:canReachTo(square) then return false end
    return not isClient() or SafeHouse.isSafehouseAllowLoot(square, player)
end

local function unlocked(player, object)
    return not instanceof(object, "IsoThumpable") or not object:isLockedToCharacter(player)
end

function K.surroundings(player)
    local sources, squares, seen, vehicles = {}, {}, {}, {}
    local current = player:getSquare()
    if not current then return sources, squares end
    local cell = getCell()
    local x, y, z = current:getX(), current:getY(), current:getZ()
    local function add(container, square, object, part)
        if not container or seen[container] or container:getType() == "floor"
            or container:isInCharacterInventory(player) or not unlocked(player, object) then return end
        seen[container] = true
        if not container:isExplored() then
            if isClient() then
                container:requestServerItemsForContainer()
            else
                ItemPicker.fillContainer(container, player)
            end
            container:setExplored(true)
        end
        sources[#sources + 1] = { container = container, square = square, object = object, part = part }
    end
    for dy = -1, 1 do
        for dx = -1, 1 do
            local square = cell:getGridSquare(x + dx, y + dy, z)
            if K.reachable(player, square) then
                squares[#squares + 1] = square
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    for j = 0, object:getContainerCount() - 1 do
                        add(object:getContainerByIndex(j), square, object)
                    end
                end
                local bodies = square:getDeadBodys()
                for i = 0, bodies:size() - 1 do
                    local body = bodies:get(i)
                    add(body:getContainer(), square, body)
                end
                local worldItems = square:getWorldObjects()
                for i = 0, worldItems:size() - 1 do
                    local object = worldItems:get(i)
                    local item = object:getItem()
                    if instanceof(item, "InventoryContainer") then add(item:getInventory(), square, object) end
                end
                local vehicle = square:getVehicleContainer()
                if vehicle and not vehicles[vehicle] then
                    vehicles[vehicle] = true
                    for i = 0, vehicle:getPartCount() - 1 do
                        local part = vehicle:getPartByIndex(i)
                        if vehicle:canAccessContainer(i, player) then
                            add(part:getItemContainer(), square, vehicle, part)
                        end
                    end
                end
            end
        end
    end
    return sources, squares
end

function K.sourceValid(player, source)
    if not K.reachable(player, source.square) or not unlocked(player, source.object)
        or not source.container:isExistYet() or source.container:isInCharacterInventory(player) then return false end
    if source.part then
        return source.object:canAccessContainer(source.part:getIndex(), player)
    end
    -- isExistYet() can return true for removed objects when world sync is off
    if instanceof(source.object, "IsoDeadBody") then return source.object:getStaticMovingObjectIndex() ~= -1 end
    if instanceof(source.object, "IsoWorldInventoryObject") then return source.object:getWorldObjectIndex() ~= -1 end
    if source.object then return source.object:getObjectIndex() ~= -1 end
    return true
end

function K.moveableCandidate(player, square, object, sprite, limit, cached)
    if not unlocked(player, object) or instanceof(object, "IsoWorldInventoryObject") then return end
    limit = limit or select(2, K.settings())
    if limit <= 0 then return end
    local props = cached and cached.props
    if not props then
        sprite = sprite or object:getSprite()
        if not sprite or not sprite:getProperties():has("IsMoveAble") then return end
        props = ISMoveableSpriteProps.new(sprite)
    end
    if not props or not props.isMoveable or props.pickUpTool or props.isMultiSprite
        or props.weight > limit + 0.000001
        or props.type == "FloorTile" or props.type == "Window" or props.type == "WindowObject"
        or props.type == "Vegitation" or props.isoType == "IsoBrokenGlass" then return end
    local found, attached = props:findOnSquare(square, props.spriteName)
    if found ~= object or not props:canPickUpMoveable(player, square, not attached and object or nil) then return end
    local item = cached and cached.prototype or props:instanceItem()
    if not K.allowedWeight(item, limit) or not player:getInventory():hasRoomFor(player, item) then return end
    return cached or { object = object, square = square, sprite = props.spriteName, prototype = item, props = props }
end

function K.chooseCandidate(player, sources, squares, limit)
    limit = limit or select(2, K.settings())
    if limit <= 0 then return end
    local inventory = player:getInventory()
    local bags = K.wornBags(player)
    -- Worn bags still use the character's carry limit
    local maxWeight = math.min(limit, inventory:getFreeCapacity(player)) + 0.000001
    local function eligible(source, item)
        return item:getUnequippedWeight() <= maxWeight and source.container:isRemoveItemAllowed(item)
            and (inventory:hasRoomFor(player, item) or K.destination(player, item, bags))
    end
    local selected, total = nil, 0
    local function consider(candidate, weight)
        if candidate and weight > 0 then
            total = total + weight
            if ZombRand(total) < weight then selected = candidate end
        end
    end
    for _, source in ipairs(sources) do
        local items, weight = source.container:getItems(), 0
        for i = 0, items:size() - 1 do
            if eligible(source, items:get(i)) then
                weight = weight + 1
                if weight == 4 then break end
            end
        end
        consider(source, weight)
    end
    for _, square in ipairs(squares) do
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            consider(K.moveableCandidate(player, square, object, nil, limit), 1)
            local children = object:getChildSprites()
            if children then
                for j = 0, children:size() - 1 do
                    consider(K.moveableCandidate(player, square, object, children:get(j):getParentSprite(), limit), 1)
                end
            end
        end
    end
    if selected and selected.container then
        -- The cap affects container odds, not which items can be picked
        local source, winner, count = selected, nil, 0
        local items = source.container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if eligible(source, item) then
                count = count + 1
                if ZombRand(count) == 0 then winner = item end
            end
        end
        if winner then
            return { item = winner, source = source, destination = K.destination(player, winner, bags) }
        end
        return
    end
    return selected
end

local function owns(player, item)
    return item and item:getContainer() and item:getContainer():isInCharacterInventory(player)
end

local function destinationStillWorn(player, destination)
    if destination == player:getInventory() then return true end
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        if instanceof(item, "InventoryContainer") and item:getInventory() == destination then return true end
    end
    return false
end

local function confirmReceipt(player, entry)
    if entry.received then return true end
    local item
    if entry.pickup then
        item = K.receivedPickup(player, entry.pickup)
    else
        item = entry.action.item
        -- Server packets recreate items, so match by ID
        if not owns(player, item) then item = player:getInventory():getItemWithIDRecursiv(entry.itemID) end
    end
    if owns(player, item) then
        K.satisfy(player)
        entry.received = item
        return true
    end
    return false
end

local function watchCancellation(player, action)
    for _, method in ipairs({ "stop", "forceCancel" }) do
        local original = action[method]
        action[method] = function(self)
            local entry = active[player]
            if K.enabled() and entry and entry.action == self and not confirmReceipt(player, entry) then
                K.cancel(player)
            end
            return original(self)
        end
    end
end

function K.startTransfer(player, candidate, packing)
    if not K.enabled() then return end
    local item, source, destination = candidate.item, candidate.source, candidate.destination
    local action = ISInventoryTransferAction:new(player, item, source.container, destination)
    local valid = action.isValid
    action.isValid = function(self)
        if not K.enabled() then return false end
        if owns(player, self.item) and not packing then return valid(self) end
        if not K.hasTrait(player) or not K.allowedWeight(self.item) or not destinationStillWorn(player, destination)
            or not destination:hasRoomFor(player, self.item) then return false end
        if not packing and (not K.sourceValid(player, source) or not source.container:isRemoveItemAllowed(self.item)) then return false end
        return valid(self)
    end
    if not packing then
        active[player] = { action = action, itemID = item:getID() }
        action:setOnComplete(function()
            local entry = active[player]
            if K.enabled() and entry and entry.action == action then
                confirmReceipt(player, entry)
            end
        end)
        K.state(player).retryStarted = nil
        K.state(player).inFlight = { itemID = item:getID() }
        watchCancellation(player, action)
    end
    ISTimedActionQueue.add(action)
end

function K.startPickup(player, candidate)
    if not K.enabled() then return end
    local before = {}
    local fullType = candidate.prototype:getFullType()
    local items = player:getInventory():getAllTypeRecurse(fullType)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        before[tostring(item:getID())] = true
    end
    local action = ISMoveablesAction:new(player, candidate.square, "pickup", candidate.sprite, candidate.object)
    local valid = action.isValid
    action.isValid = function(self)
        if not K.enabled() then return false end
        if not K.hasTrait(player) or not K.reachable(player, candidate.square) then return false end
        if not K.moveableCandidate(player, candidate.square, candidate.object, nil, nil, candidate) then return false end
        return valid(self)
    end
    local flight = { sprite = candidate.sprite, fullType = fullType, before = before }
    K.state(player).retryStarted = nil
    K.state(player).inFlight = flight
    active[player] = { action = action, pickup = flight }
    local perform = action.perform
    action.perform = function(self)
        local entry = active[player]
        -- The next queued action may consume or move the item
        if K.enabled() and entry and entry.action == self then confirmReceipt(player, entry) end
        return perform(self)
    end
    watchCancellation(player, action)
    ISTimedActionQueue.add(action)
end

function K.receivedPickup(player, flight)
    return player:getInventory():getFirstTypeEvalRecurse(flight.fullType, function(item)
        return not flight.before[tostring(item:getID())]
            and (not instanceof(item, "Moveable") or item:getWorldSprite() == flight.sprite)
    end)
end

local function packPickup(player, item)
    if item:getContainer() ~= player:getInventory() or not K.canStart(player) then return end
    local destination = K.destination(player, item)
    if destination and destination ~= player:getInventory() then
        K.startTransfer(player, {
            item = item, destination = destination, source = { container = player:getInventory() }
        }, true)
    end
end

function K.checkActive(player, realNow)
    local entry = active[player]
    if not entry then return false end
    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    if queue:indexOf(entry.action) ~= -1 then return true end
    confirmReceipt(player, entry)
    -- Completion can arrive before the item packet
    if not entry.received and isClient() then
        entry.finishedAt = entry.finishedAt or realNow
        if realNow - entry.finishedAt < 3000 then return true end
    end
    active[player] = nil
    if entry.pickup and entry.received and #queue.queue == 0 then packPickup(player, entry.received) end
    if not entry.received then
        -- Keep tracking the item while a server reply may still arrive
        K.cancel(player)
    end
    return true
end

function K.recover(player, realNow)
    if not K.enabled() then return end
    local flight = K.state(player).inFlight
    if not flight then return end
    if realNow then
        local last = receipts[player]
        if last and last.flight == flight and last.revision == revision and realNow < last.nextCheck then return end
        receipts[player] = { flight = flight, revision = revision, nextCheck = realNow + RECEIPT_CHECK_MS }
    end
    local item
    if flight.itemID then
        item = player:getInventory():getItemWithIDRecursiv(flight.itemID)
    elseif flight.before then
        item = K.receivedPickup(player, flight)
    end
    if owns(player, item) then
        K.satisfy(player)
    else
        K.cancel(player)
    end
end

function K.canStart(player)
    return K.enabled() and K.hasTrait(player) and not player:isDead() and not player:isAsleep() and not player:isMoving()
        and not player:isAiming() and not player:getVehicle() and not player:isDraggingCorpse()
        and not player:isSitOnGround() and not player:isSittingOnFurniture()
        and not ISTimedActionQueue.isPlayerDoingAction(player)
        and #ISTimedActionQueue.getTimedActionQueue(player).queue == 0
end

function K.tickPlayer(player, realNow)
    if not K.enabled() then return end
    if not player or not player:isLocalPlayer() or player:isDead() then return end
    if K.checkActive(player, realNow) then return end
    if not K.hasTrait(player) then return end
    K.recover(player, realNow)
    if not K.updateUrge(player) or not K.retryReady(player) or not K.canStart(player) then return end
    -- Check for a late delivery before starting another theft
    if K.state(player).inFlight then
        K.recover(player)
        if not K.state(player).pending or not K.retryReady(player) then return end
    end
    local _, limit = K.settings()
    K.state(player).retryStarted = nil
    local sources, squares = K.surroundings(player)
    local candidate = K.chooseCandidate(player, sources, squares, limit)
    if candidate and candidate.item then
        K.startTransfer(player, candidate)
    elseif candidate then
        K.startPickup(player, candidate)
    else
        K.cancel(player)
    end
end

local function onTick()
    if not K.enabled() then return end
    if isGamePaused() then return end
    local realNow = getTimestampMs()
    if realNow < nextTick then return end
    nextTick = realNow + 750
    for i = 0, getNumActivePlayers() - 1 do K.tickPlayer(getSpecificPlayer(i), realNow) end
end

Events.OnTick.Add(onTick)
Events.OnCreatePlayer.Add(function(_, player)
    if K.enabled() and K.hasTrait(player) then K.recover(player) end
end)
-- Recheck pending deliveries when container contents change
Events.OnContainerUpdate.Add(function()
    if K.enabled() then revision = revision + 1 end
end)
Events.OnPlayerDeath.Add(function(player)
    active[player], receipts[player] = nil, nil
end)
