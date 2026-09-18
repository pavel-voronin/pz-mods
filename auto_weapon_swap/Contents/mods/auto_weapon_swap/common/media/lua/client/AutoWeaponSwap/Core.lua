require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISEquipWeaponAction"

AutoWeaponSwap = AutoWeaponSwap or {}
local AWS = AutoWeaponSwap
require "AutoWeaponSwap/ContainerNetwork"
local states = setmetatable({}, { __mode = "k" })

function AWS.settings(player)
    local data = player:getModData()
    data.AutoWeaponSwap = data.AutoWeaponSwap or { containers = {}, types = {} }
    return data.AutoWeaponSwap
end

-- Object indices can change, so keep the ID on the object
function AWS.containerKey(player, container, create)
    if not container or container:getType() == "floor" then return nil end
    if container == player:getInventory() then return "inventory" end
    local bag = container:getContainingItem()
    if bag then return "item:" .. tostring(bag:getID()) end
    local part = container:getVehiclePart()
    local owner = part or container:getParent()
    if not owner then return nil end
    local data = owner:getModData()
    if not data.AutoWeaponSwapID and create and not isClient() then
        data.AutoWeaponSwapID = getRandomUUID()
        if part then
            part:getVehicle():transmitPartModData(part)
        else
            owner:transmitModData()
        end
    end
    if not data.AutoWeaponSwapID then return nil end
    local index = part and 0 or owner:getContainerIndex(container)
    return "object:" .. data.AutoWeaponSwapID .. ":" .. tostring(index)
end

function AWS.enabled(player, container)
    local key = AWS.containerKey(player, container, false)
    return key ~= nil and AWS.settings(player).containers[key] == true
end

function AWS.toggleContainer(player, container)
    if isClient() and container and container ~= player:getInventory()
        and not container:getContainingItem() then
        AWS.toggleWorldContainer(player, container)
        return
    end
    local key = AWS.containerKey(player, container, true)
    if key then
        local choices = AWS.settings(player).containers
        choices[key] = not choices[key] or nil
    end
end

function AWS.isWeapon(item)
    return item ~= nil and instanceof(item, "HandWeapon") and item:getType() ~= "BareHands"
end

function AWS.intact(item)
    return AWS.isWeapon(item) and not item:isBroken() and item:getCondition() > 0
end

function AWS.excluded(player, item)
    local data = AWS.settings(player)
    return data.types[item:getFullType()] == true
end

function AWS.setTypeExcluded(player, fullType, excluded)
    AWS.settings(player).types[fullType] = excluded and true or nil
    AWS.exclusionsRevision = (AWS.exclusionsRevision or 0) + 1
end

function AWS.candidate(player, item)
    if not AWS.intact(item) or AWS.excluded(player, item) then return false end
    if item:getIsCraftingConsumed() then return false end
    if item:isAimedFirearm() then
        if item:isJammed() then return false end
        if item:haveChamber() then
            if not item:isRoundChambered() then return false end
        elseif item:getCurrentAmmoCount() <= 0 then
            return false
        end
    end
    return true
end

-- Use visible containers, but skip nested bags
function AWS.containers(player, refresh)
    local result = {}
    local inventory = getPlayerInventory(player:getPlayerNum())
    local loot = getPlayerLoot(player:getPlayerNum())
    if not inventory or not loot then return result end
    if refresh then
        inventory:refreshBackpacks()
        loot:refreshBackpacks()
    end
    local list = ISInventoryPaneContextMenu.getContainers(player)
    if not list then return result end
    for i = 0, list:size() - 1 do
        local container = list:get(i)
        local bag = container:getContainingItem()
        local allowed = container:getType() ~= "floor"
        if bag then
            allowed = (bag:getContainer() == player:getInventory() and player:isEquipped(bag))
                or (bag:getWorldItem() ~= nil and bag:getWorldItem():getSquare() ~= nil)
        end
        if allowed then result[#result + 1] = container end
    end
    return result
end

function AWS.accessible(player, source, refresh)
    for _, container in ipairs(AWS.containers(player, refresh)) do
        if container == source then return true end
    end
    return false
end

function AWS.choose(player, old)
    local best, source, bestScore
    for _, container in ipairs(AWS.containers(player, true)) do
        if AWS.enabled(player, container) then
            local items = container:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item ~= old and AWS.candidate(player, item) and container:isRemoveItemAllowed(item)
                    and (container == player:getInventory() or player:getInventory():hasRoomFor(player, item)) then
                    local score = item:getCondition() / math.max(1, item:getConditionMax())
                    if item:isRanged() == old:isRanged() then score = score + 2 end
                    if item:getFullType() == old:getFullType() then score = score + 4 end
                    if not bestScore or score > bestScore then
                        best, source, bestScore = item, container, score
                    end
                end
            end
        end
    end
    return best, source
end

local function stateFor(player)
    if not states[player] then states[player] = {} end
    return states[player]
end

local function freeHandsForReplacement(player, old, expected)
    local current = player:getPrimaryHandItem()
    return current == nil or current == old
        or (current == expected and (not AWS.intact(current) or AWS.excluded(player, current)))
end

local function removed(item)
    if item:getWorldItem() then return false end -- Dropping a weapon is not losing it
    local container = item:getContainer()
    return container == nil or not container:contains(item)
end

local function request(player, old)
    local state = stateFor(player)
    local current = player:getPrimaryHandItem()
    if state.pending or state.active
        or (current ~= old and AWS.intact(current) and not AWS.excluded(player, current)) then return end
    -- Wait for OnBreak before checking the weapon left in hand
    state.pending = { old = old, hand = current, settling = player:isAttacking() }
end

function AWS.onAttackFinished(player, weapon)
    if not player or not player:isLocalPlayer() or not AWS.isWeapon(weapon) then return end
    if not AWS.intact(weapon) or removed(weapon) then request(player, weapon) end
end

function AWS.equip(player, old, item, source, expected)
    local state = stateFor(player)
    local token = {}
    state.active = token
    local function commonGuard()
        return not player:isDead() and state.active == token
            and freeHandsForReplacement(player, old, expected)
            and (not AWS.intact(old) or removed(old))
            and AWS.enabled(player, source) and AWS.candidate(player, item)
    end
    if source ~= player:getInventory() then
        local transfer = ISInventoryTransferUtil.newInventoryTransferAction(player, item, source, player:getInventory())
        local valid = transfer.isValid
        local nextAccessCheck, access = 0, false
        transfer.isValid = function(action)
            if not commonGuard() then return false end
            local now = getTimestampMs()
            if now >= nextAccessCheck then
                access = AWS.accessible(player, source, true)
                nextAccessCheck = now + 100
            end
            return access and valid(action)
        end
        ISTimedActionQueue.add(transfer)
    end
    local secondary = player:getSecondaryHandItem()
    local twoHands = item:isRequiresEquippedBothHands()
        or (item:isTwoHandWeapon() and (secondary == nil or secondary == old))
    local equip = ISEquipWeaponAction:new(player, item, 50, true, twoHands)
    local valid = equip.isValid
    equip.isValid = function(action)
        return commonGuard() and valid(action)
    end
    token.action = equip
    ISTimedActionQueue.add(equip)
end

function AWS.onPlayerUpdate(player)
    if not player or not player:isLocalPlayer() then return end
    if player:isDead() then states[player] = nil; return end
    if isGamePaused() then return end
    local state = stateFor(player)
    local current = player:getPrimaryHandItem()
    local previous = state.weapon
    if previous and (not AWS.intact(previous) or (current ~= previous and removed(previous))) then
        request(player, previous)
    end
    state.weapon = AWS.intact(current) and current or nil

    local queue = ISTimedActionQueue.getTimedActionQueue(player)
    if state.active then
        if queue:indexOf(state.active.action) == -1 then state.active = nil end
        return
    end
    local pending = state.pending
    if not pending then return end
    if pending.settling then
        if player:isAttacking() then return end
        pending.hand = current
        pending.settling = false
    end
    if not freeHandsForReplacement(player, pending.old, pending.hand)
        or (AWS.intact(pending.old) and not removed(pending.old)) then
        state.pending = nil
        return
    end
    if #queue.queue > 0 or player:isAttacking() then return end
    -- Search once, finding no replacement ends this request
    state.pending = nil
    local item, source = AWS.choose(player, pending.old)
    if item then AWS.equip(player, pending.old, item, source, pending.hand) end
end

Events.OnPlayerUpdate.Add(AWS.onPlayerUpdate)
Events.OnPlayerAttackFinished.Add(AWS.onAttackFinished)
