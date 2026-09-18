-- Run with Lua 5.1 or the game's Kahlua runtime; MOD_FILE points to Core.lua.
local tests = 0
local function check(value, message) assert(value, message); tests = tests + 1 end
function require() end
function instanceof(object, kind) return object and object.kind == kind end
function list(values)
    values = values or {}
    function values:size() return #self end
    function values:get(i) return self[i + 1] end
    function values:isEmpty() return #self == 0 end
    return values
end
local gameMinutes = 100
function getGameTime() return { getWorldAgeHours = function() return gameMinutes / 60 end } end
function isClient() return CLIENT == true end
function ZombRand(n) return n - 1 end
function isGamePaused() return false end
SandboxVars = {}
KleptomaniacTrait = 'kleptomaniac:kleptomaniac'
Events = {}
for _, name in ipairs({'OnTick', 'OnCreatePlayer', 'OnPlayerDeath', 'OnContainerUpdate'}) do
    local event = {}
    event.Add = function(handler) event.handler = handler end
    Events[name] = event
end
SafeHouse = { isSafehouseAllowLoot = function() return not FORBIDDEN end }
local function container(capacity, owner)
    local c = { items = list(), capacity = capacity, owner = owner, exists = true }
    function c:getItems() return self.items end
    function c:isInCharacterInventory(p) return self.owner == p end
    function c:hasRoomFor(p, item)
        local weight = 0
        for _, v in ipairs(self.items) do weight = weight + v.weight end
        return not self.disallowed and weight + item.weight <= self.capacity
    end
    function c:getFreeCapacity(p)
        local weight = 0
        for _, v in ipairs(self.items) do weight = weight + v.weight end
        return math.max(0, self.capacity - weight)
    end
    function c:isInside() return false end
    function c:isExistYet() return self.exists end
    function c:isRemoveItemAllowed() return not self.removeBlocked end
    function c:getType() return self.type or 'crate' end
    function c:isExplored() return true end
    function c:getAllTypeRecurse(fullType)
        local result = list()
        local function collect(contents)
            for _, v in ipairs(contents.items) do
                if v:getFullType() == fullType then result[#result + 1] = v end
                if instanceof(v, 'InventoryContainer') then collect(v:getInventory()) end
            end
        end
        collect(self)
        return result
    end
    function c:getFirstTypeEvalRecurse(fullType, predicate)
        local items = self:getAllTypeRecurse(fullType)
        for _, v in ipairs(items) do if predicate(v) then return v end end
    end
    function c:getItemWithIDRecursiv(id)
        for _, item in ipairs(self.items) do if item.id == id then return item end end
        if self.owner then
            for _, worn in ipairs(self.owner.worn) do
                for _, item in ipairs(worn:getItem():getInventory().items) do
                    if item.id == id then return item end
                end
            end
        end
    end
    return c
end
local nextID = 0
local function item(weight, c, sprite)
    nextID = nextID + 1
    local v = { weight = weight, id = nextID, container = c, sprite = sprite,
        kind = sprite and 'Moveable' or 'InventoryItem', fullType = sprite and 'Moveables.Moveable' or 'Base.Spoon' }
    function v:getUnequippedWeight() return self.weight end
    function v:getID() return self.id end
    function v:getContainer() return self.container end
    function v:getFullType() return self.fullType end
    function v:getWorldSprite() return self.sprite end
    if c then c.items[#c.items + 1] = v end
    return v
end
local function move(v, destination)
    if v.container then
        for i, old in ipairs(v.container.items) do
            if old == v then table.remove(v.container.items, i); break end
        end
    end
    v.container = destination
    destination.items[#destination.items + 1] = v
end
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z or 0 end,
        canReachTo = function(_, other) return not other.blocked end,
        getObjects = function(self) return self.objects or list() end,
        getDeadBodys = function() return list() end,
        getWorldObjects = function() return list() end,
        getVehicleContainer = function() end }
end
local function player()
    local p = { data = {}, worn = list(), square = square(10, 10), actions = list(), klepto = true }
    p.inventory = container(20, p)
    function p:getModData() return self.data end
    function p:getInventory() return self.inventory end
    function p:getWornItems() return self.worn end
    function p:getSquare() return self.square end
    function p:isLocalPlayer() return true end
    function p:hasTrait(trait) return trait == KleptomaniacTrait and self.klepto end
    function p:isDead() return self.dead end
    function p:isAsleep() return self.asleep end
    function p:isMoving() return self.moving end
    function p:isAiming() return self.aiming end
    function p:getVehicle() return self.vehicle end
    function p:isDraggingCorpse() return self.dragging end
    function p:isSitOnGround() return self.sitting end
    function p:isSittingOnFurniture() return false end
    function p:getCharacterActions() return self.actions end
    return p
end
local function wearBag(p, capacity)
    local bag = container(capacity, p)
    local v = item(0, p.inventory)
    v.kind, v.fullType = 'InventoryContainer', 'Base.Bag'
    function v:getInventory() return bag end
    p.worn[#p.worn + 1] = { getItem = function() return v end }
    return bag
end
ISTimedActionQueue = {}
function ISTimedActionQueue.isPlayerDoingAction(p) return p.engineAction or not p.actions:isEmpty() end
function ISTimedActionQueue.getTimedActionQueue(p)
    if not p.queue then
        p.queue = { queue = {} }
        function p.queue:indexOf(a)
            for i, v in ipairs(self.queue) do if a == v then return i end end
            return -1
        end
    end
    return p.queue
end
function ISTimedActionQueue.add(action)
    local queue = ISTimedActionQueue.getTimedActionQueue(action.character).queue
    queue[#queue + 1] = action
end
ISInventoryTransferAction = {}
function ISInventoryTransferAction:new(p, v, source, destination)
    local a = { character = p, item = v, srcContainer = source, destContainer = destination }
    function a:isValid() return self.item:getContainer() == self.srcContainer end
    function a:setOnComplete(callback) self.callback = callback end
    function a:stop() self.stopped = true; p.queue.queue = {} end
    function a:forceCancel() self:stop() end
    return a
end
ISMoveablesAction = {}
function ISMoveablesAction:new(p, sq, mode, sprite, object)
    return { character = p, isValid = function() return true end, perform = function() end,
        stop = function() p.queue.queue = {} end, forceCancel = function() p.queue.queue = {} end }
end
ISMoveableSpriteProps = {}
function ISMoveableSpriteProps.new(sprite) return PROPS end
function ISMoveableSpriteProps.fromObject(object) return PROPS end
function getCell() return { getGridSquare = function() end } end

dofile(MOD_FILE)
local K = Kleptomaniac
local p = player()
check(K.allowedWeight(item(2)), 'Default weight limit includes a table lamp')
check(not K.allowedWeight(item(2.001)), 'Default weight limit is 2')
check(not K.updateUrge(p), 'No urge immediately after activation')
gameMinutes = 139.99
check(not K.updateUrge(p), 'Do not round 40 game minutes down')
gameMinutes = 140
check(K.updateUrge(p), 'Default interval is 40 game minutes')
gameMinutes = 400
check(K.updateUrge(p), 'Unfulfilled urge persists')
K.satisfy(p)
check(not K.updateUrge(p), 'No backlog after fulfilling an overdue urge')
gameMinutes = 439
check(not K.updateUrge(p), 'Next interval starts on successful theft')
SandboxVars.Kleptomaniac = { IntervalMinutes = 20, MaxWeight = 1 }
check(K.updateUrge(p), 'Live Sandbox interval change is read')
local saved = p.data
p = player(); p.data = saved
check(K.updateUrge(p), 'Pending urge survives player reload')
check(K.allowedWeight(item(1)), 'Inclusive weight limit')
check(not K.allowedWeight(item(1.01)), 'Reject weight above limit')
local bag1, bag2 = wearBag(p, 0), wearBag(p, 2)
local spoon = item(0.1)
check(K.destination(p, spoon) == bag2, 'Try another worn bag if first is full')
bag2.disallowed = true
check(K.destination(p, spoon) == p.inventory, 'Fall back to main inventory when bags reject item')
p.inventory.capacity = 0
check(K.destination(p, spoon) == nil, 'Do not steal when no destination fits')
p.inventory.capacity = 20; bag2.disallowed = nil
local sq = square(11, 10)
check(K.reachable(p, sq), 'Adjacent accessible square')
sq.blocked = true
check(not K.reachable(p, sq), 'Cannot take through a wall')
sq.blocked = nil
check(not K.reachable(p, square(12, 10)), 'No distant pickup')
check(not K.reachable(p, square(10, 10, 1)), 'No pickup on another floor')
CLIENT = true; FORBIDDEN = true
check(not K.reachable(p, sq), 'Respect server safehouse permissions')
CLIENT = false; FORBIDDEN = false
local source = { container = container(50), square = sq }
local heavy = item(2, source.container)
local light = item(0.1, source.container)
local candidate = K.chooseCandidate(p, {source}, {})
check(candidate.item == light, 'Filter weight before random selection')
source.container.removeBlocked = true
check(not K.chooseCandidate(p, {source}, {}), 'Respect source removal restriction')
source.container.removeBlocked = false
K.startTransfer(p, candidate)
local a = p.queue.queue[1]
check(a.item == light and light.container == source.container, 'Queue action without moving item instantly')
check(a:isValid(), 'Valid queued transfer')
bag2.capacity = 0
check(not a:isValid(), 'Recheck destination capacity during action')
bag2.capacity = 2
sq.blocked = true
check(not a:isValid(), 'Cancel if source becomes unreachable')
sq.blocked = nil
a:stop()
check(a.stopped and K.state(p).retryStarted == gameMinutes, 'Cancellation calls vanilla stop and records exact game time')
K.checkActive(p, 1000); K.checkActive(p, 5000)
check(K.state(p).pending, 'Cancellation preserves urge')
check(light.container == source.container, 'Cancelled action leaves original item intact')
check(not K.retryReady(p), 'Cancellation starts the default retry delay')
local cancelledAt = gameMinutes
gameMinutes = cancelledAt + 9.99
K.recover(p)
check(not K.retryReady(p), 'Wait for ten full game minutes, independent of real time')
check(K.state(p).retryStarted == cancelledAt, 'Repeated recovery does not extend cooldown')
local reloaded = player(); reloaded.data = p.data
check(not K.retryReady(reloaded), 'Cooldown survives player reload')
gameMinutes = cancelledAt + 10
check(K.retryReady(p), 'Retry allowed at exactly ten game minutes')
SandboxVars.Kleptomaniac.RetryMinutes = 20
check(not K.retryReady(p), 'Live server setting can lengthen retry delay')
SandboxVars.Kleptomaniac.RetryMinutes = 0
check(select(3, K.settings()) == 1 and K.retryReady(p), 'Legacy zero retry setting is clamped to one game minute')
SandboxVars.Kleptomaniac.RetryMinutes = nil
K.startTransfer(p, candidate)
a = p.queue.queue[1]
move(light, bag2); a.callback(); p.queue.queue = {}
K.checkActive(p, 6000)
check(not K.state(p).pending, 'Confirmed multiplayer-style receipt satisfies urge')
check(K.state(p).retryStarted == nil, 'Success clears retry state')
check(light.container == bag2, 'Same item transferred into preferred bag')
K.state(p).pending = true; K.state(p).inFlight = { itemID = light.id }
K.recover(p)
check(not K.state(p).pending, 'Reload reconciles a completed in-flight transfer')
K.state(p).pending = true; K.state(p).inFlight = { itemID = -123 }
K.recover(p)
check(K.state(p).pending, 'Reload of cancelled action preserves urge')

local sprite = { getProperties = function() return {has=function() return true end} end }
local object = { getChildSprites = function() end, getSprite = function() return sprite end }
local proto = item(0.5, nil, 'decoration_1')
PROPS = { weight = 0.5, isMoveable = true, type = 'WallObject', spriteName = 'decoration_1',
    findOnSquare = function() return object end,
    canPickUpMoveable = function() return true end,
    instanceItem = function() return proto end }
check(K.moveableCandidate(p, sq, object), 'Tool-free wall decoration is eligible')
PROPS.pickUpTool = 'Hammer'
check(not K.moveableCandidate(p, sq, object), 'Exclude furniture requiring a tool even if one is equipped')
PROPS.pickUpTool = nil; PROPS.isMultiSprite = true
check(not K.moveableCandidate(p, sq, object), 'Exclude furniture requiring multiple parts')
PROPS.isMultiSprite = false; PROPS.type = 'FloorTile'
check(not K.moveableCandidate(p, sq, object), 'Do not pull up the floor')
PROPS.type = 'WallObject'
check(not K.moveableCandidate(p, sq, {kind='IsoWorldInventoryObject'}), 'Do not pick up loose floor items')
proto.weight = 2
check(not K.moveableCandidate(p, sq, object), 'Custom 1-unit limit excludes a 2-unit table lamp')
proto.weight = 0.5
candidate = K.moveableCandidate(p, sq, object)
local existing = item(0.5, p.inventory, 'decoration_1')
K.startPickup(p, candidate)
local flight = K.state(p).inFlight
check(not K.receivedPickup(p, flight), 'Existing matching decoration is not treated as newly stolen')
local acquired = item(0.5, p.inventory, 'decoration_1')
check(K.receivedPickup(p, flight) == acquired, 'Recognize actual newly received decoration')
p.queue.queue = {}
K.checkActive(p, 7000)
check(not K.state(p).pending, 'Successful furniture pickup satisfies urge')
check(#p.queue.queue == 1 and p.queue.queue[1].item == acquired, 'Follow furniture pickup with timed packing into bag')
p.queue.queue = {}; K.checkActive(p, 8000)
for _, flag in ipairs({'moving','aiming','asleep','dragging','sitting'}) do
    p[flag] = true; check(not K.canStart(p), 'Wait while ' .. flag); p[flag] = nil
end
p.vehicle = {}; check(not K.canStart(p), 'Do not steal scenery while seated in a vehicle'); p.vehicle = nil
p.actions[1] = {}; check(not K.canStart(p), 'Do not interrupt another game action'); p.actions[1] = nil
p.engineAction = true
check(not K.canStart(p), 'Wait during native climbing and window-interaction states without a Lua action')
p.engineAction = nil
check(K.canStart(p), 'Idle survivor may start theft')
p.klepto = false
check(not K.canStart(p), 'Characters without the trait cannot steal')
local ordinary = player(); ordinary.klepto = false
K.tickPlayer(ordinary, 9000)
check(ordinary.data.Kleptomaniac == nil and ordinary.queue == nil, 'No state or queued action for ordinary characters')
p.klepto = true

CLIENT = true
local alice, bob = player(), player()
local shared = {container = container(50), square = sq}
local unique = item(0.1, shared.container)
K.state(alice).pending = true; K.state(bob).pending = true
K.startTransfer(alice, {item=unique, source=shared, destination=alice.inventory})
K.startTransfer(bob, {item=unique, source=shared, destination=bob.inventory})
move(unique, alice.inventory)
alice.queue.queue = {}; bob.queue.queue = {}
K.checkActive(alice, 10000); K.checkActive(bob, 10000); K.checkActive(bob, 14000)
check(not K.state(alice).pending and K.state(bob).pending, 'Only the server-approved recipient satisfies the urge')
check(not K.retryReady(bob), 'Rejected competing attempt enters cooldown')
check(#alice.inventory.items == 1 and #bob.inventory.items == 0, 'Mod does not fabricate or duplicate an item')

local late = player()
local delayed = item(0.1, shared.container)
K.state(late).pending = true
K.startTransfer(late, {item=delayed, source=shared, destination=late.inventory})
late.queue.queue[1]:stop()
K.checkActive(late, 15000); K.checkActive(late, 19000)
check(K.state(late).inFlight.itemID == delayed.id, 'Retain receipt identity beyond completion-packet grace period')
move(delayed, late.inventory)
K.recover(late)
check(not K.state(late).pending and not K.state(late).retryStarted, 'Late server receipt satisfies urge and removes cooldown')

local interrupted = player()
K.state(interrupted).pending = true
K.startPickup(interrupted, candidate)
interrupted.queue.queue[1]:stop()
check(not K.retryReady(interrupted) and K.state(interrupted).pending, 'Furniture cancellation uses the same persistent cooldown')
K.checkActive(interrupted, 20000); K.checkActive(interrupted, 24000)

local packing = player(); wearBag(packing, 5)
local packed = item(0.1, packing.inventory)
K.satisfy(packing)
K.startTransfer(packing, {item=packed, source={container=packing.inventory}, destination=K.wornBags(packing)[1]}, true)
packing.queue.queue[1]:stop(); K.checkActive(packing, 25000)
check(not K.state(packing).pending and not K.state(packing).retryStarted, 'Cancelling packing does not undo a completed theft')

local waiting = player()
local untouched = item(0.1, shared.container)
K.startTransfer(waiting, {item=untouched, source=shared, destination=waiting.inventory})
waiting.queue.queue[1]:forceCancel()
check(K.state(waiting).retryStarted == gameMinutes, 'Cancelling before an action starts records the delay immediately')
local confirmed = player()
local committed = item(0.1, shared.container)
K.startTransfer(confirmed, {item=committed, source=shared, destination=confirmed.inventory})
move(committed, confirmed.inventory)
confirmed.queue.queue[1]:stop()
check(not K.state(confirmed).pending and not K.state(confirmed).retryStarted, 'Cancellation arriving after receipt does not create a second urge')
CLIENT = false
local floor = container(50); floor.type = 'floor'; item(0.1, floor)
local closed = {kind='IsoThumpable', isLockedToCharacter=function() return true end,
    getContainerCount=function() return 1 end, getContainerByIndex=function() return source.container end}
local open = { getContainerCount=function() return 1 end, getContainerByIndex=function() return floor end }
p.square.objects = list({closed, open})
function getCell() return {getGridSquare=function(_, x,y,z) if x==10 and y==10 then return p.square end end} end
check(#K.surroundings(p) == 0, 'Scanner excludes locked storage and floor containers')

local originalSurroundings = K.surroundings
local scans = 0
K.surroundings = function() scans = scans + 1; return {}, {} end
local idle = player()
K.state(idle).pending = true
local failedAt = gameMinutes
for now = 0, 59250, 750 do K.tickPlayer(idle, now) end
check(scans == 1, 'Real time alone cannot trigger another search during the retry delay')
check(K.state(idle).pending and K.state(idle).retryStarted == failedAt, 'An empty search preserves the urge and starts the failure delay')
local fresh = player()
K.tickPlayer(fresh, 0)
check(scans == 1, 'No world search before the first urge')
idle.square = square(11, 10)
K.tickPlayer(idle, 60000)
Events.OnContainerUpdate.handler()
K.tickPlayer(idle, 60750)
SandboxVars.Kleptomaniac.MaxWeight = 1.5
K.tickPlayer(idle, 61500)
check(scans == 1, 'Movement, inventory changes and weight settings cannot bypass failure cooldown')
SandboxVars.Kleptomaniac.MaxWeight = 1
gameMinutes = failedAt + 9.99
K.tickPlayer(idle, 62250)
check(scans == 1, 'Empty searches wait ten full game minutes')
gameMinutes = failedAt + 10
idle.moving = true
K.tickPlayer(idle, 63000)
check(scans == 1 and K.state(idle).retryStarted == failedAt, 'Movement neither searches nor restarts an expired delay')
idle.moving = nil
K.tickPlayer(idle, 63750)
check(scans == 2 and K.state(idle).retryStarted == gameMinutes, 'The next empty attempt starts a new full delay')
gameMinutes = failedAt + 19.99
K.tickPlayer(idle, 64500)
check(scans == 2, 'An expired earlier cooldown cannot cause repeated searches')
gameMinutes = failedAt + 20
K.tickPlayer(idle, 65250)
check(scans == 3, 'A third attempt occurs only after the second delay')
SandboxVars.Kleptomaniac.RetryMinutes = 0
K.tickPlayer(idle, 66000)
gameMinutes = failedAt + 20.99
K.tickPlayer(idle, 66750)
check(scans == 3, 'Legacy zero retry setting cannot bypass the minimum one-minute delay')
gameMinutes = failedAt + 21
K.tickPlayer(idle, 67500)
check(scans == 4, 'Retry is allowed at exactly one game minute with a legacy zero setting')
SandboxVars.Kleptomaniac.RetryMinutes = 1
gameMinutes = failedAt + 22
K.tickPlayer(idle, 68250)
check(scans == 5, 'The explicit minimum setting waits one game minute between attempts')
SandboxVars.Kleptomaniac.RetryMinutes = nil
local busy = player()
K.state(busy).pending = true
busy.actions[1] = {}
K.tickPlayer(busy, 69000)
check(scans == 5 and not K.state(busy).retryStarted, 'Being busy is not a failed attempt')
busy.actions[1] = nil
K.tickPlayer(busy, 69750)
check(scans == 6, 'A pending urge searches as soon as the character is free')
K.surroundings = originalSurroundings

local bulk = {container=container(20000), square=sq}
local weightReads, wornReads = 0, 0
for i = 1, 10000 do
    local v = item(0.1, bulk.container)
    v.getUnequippedWeight = function(self) weightReads = weightReads + 1; return self.weight end
end
local shopper = player()
local shopperBag = wearBag(shopper, 10)
local bagChecks = 0
local originalBagRoom = shopperBag.hasRoomFor
shopperBag.hasRoomFor = function(self, owner, v)
    bagChecks = bagChecks + 1
    return originalBagRoom(self, owner, v)
end
shopper.getWornItems = function(self) wornReads = wornReads + 1; return self.worn end
check(K.chooseCandidate(shopper, {bulk}, {}).destination == shopperBag, 'Select an item from 10,000 candidates and prefer its worn bag')
check(weightReads == 10004 and wornReads == 1, 'Count four eligible items, then scan the winner once; collect worn bags once')
check(bagChecks == 1, 'Check bag capacity once for the winner rather than for all 10,000 items')
shopper.inventory.disallowed = true
check(K.chooseCandidate(shopper, {bulk}, {}) ~= nil, 'A bag may accept an item rejected by main-inventory filters')
shopper.inventory.disallowed = nil
weightReads, wornReads = 0, 0
local skipped = {container=container(20000), square=sq}
for i = 1, 4 do item(0.1, skipped.container) end
local skippedReads = 0
skipped.container.items.size = function() return 10000 end
skipped.container.items.get = function(self, i)
    skippedReads = skippedReads + 1
    assert(i < 4, 'Read beyond the four eligible items in an unselected container')
    return self[i+1]
end
check(K.chooseCandidate(shopper, {bulk, skipped}, {}).source == bulk and skippedReads == 4,
    'Inspect only four eligible items in an unselected 10,000-item container')
bulk.container.removeBlocked = true
weightReads, wornReads = 0, 0
check(not K.chooseCandidate(shopper, {bulk}, {}), 'All disallowed items still produce no candidate')
check(weightReads == 10000 and wornReads == 1, 'An unsuccessful scan visits each item at most once without rebuilding bags')
bulk.container.removeBlocked = false
local random = ZombRand
-- Exhaustive probability checks.
local mixed = {container=container(50), square=sq}
local firstItem = item(0.1, mixed.container)
item(20, mixed.container)
local secondItem = item(0.1, mixed.container)
local rejected = item(0.1, mixed.container)
local thirdItem = item(0.1, mixed.container)
mixed.container.isRemoveItemAllowed = function(_, v) return v ~= rejected end
local counts = {}
for a = 0, 1 do
    for b = 0, 2 do
        local draws, draw = {0, 0, a, b}, 0
        function ZombRand(n) draw = draw + 1; return draws[draw] end
        local chosen = K.chooseCandidate(shopper, {mixed}, {}).item
        counts[chosen] = (counts[chosen] or 0) + 1
    end
end
check(counts[firstItem] == 2 and counts[secondItem] == 2 and counts[thirdItem] == 2 and not counts[rejected],
    'Every eligible item has exactly the same probability regardless of gaps')
local environment = square(10, 11)
environment.objects = list({object})
local function outcomes(itemCount)
    local shelf = {container=container(50), square=sq}
    local candidates, totals, draws = {}, {}, {0}
    for i = 1, itemCount do candidates[i] = item(0.1, shelf.container) end
    local function enumerate(n)
        if n <= itemCount then
            for d = 0, n - 1 do draws[n] = d; enumerate(n + 1) end
            return
        end
        for envDraw = 0, math.min(itemCount, 4) do
            local call = 0
            function ZombRand(size)
                call = call + 1
                if call == 1 then return 0 end
                if call == 2 then return envDraw end
                return draws[call - 2]
            end
            local chosen = K.chooseCandidate(shopper, {shelf}, {environment})
            local key = chosen.item or 'environment'
            totals[key] = (totals[key] or 0) + 1
        end
    end
    enumerate(2)
    return totals, candidates
end
local probabilities, choices = outcomes(3)
check(probabilities.environment == 6 and probabilities[choices[1]] == 6
    and probabilities[choices[2]] == 6 and probabilities[choices[3]] == 6,
    'Three eligible items plus one decoration: each has exactly a one-in-four chance')
probabilities, choices = outcomes(5)
local equal = probabilities.environment == 120
for _, v in ipairs(choices) do equal = equal and probabilities[v] == 96 end
check(equal, 'Five items plus one decoration: decoration probability is 1/5, each item including the fifth is 4/25')
-- Container weights: 1, 4, 2, 0; decoration weight: 1.
local shelves = {}
for i = 1, 4 do
    shelves[i] = {container=container(50), square=sq}
    local sizes = {1, 7, 2, 1}
    for j = 1, sizes[i] do item(i == 4 and 20 or 0.1, shelves[i].container) end
end
counts = {}
for a = 0, 4 do
    for b = 0, 6 do
        for c = 0, 7 do
            local draws, draw = {0, a, b, c}, 0
            function ZombRand(n)
                draw = draw + 1
                return draw <= 4 and draws[draw] or n - 1
            end
            local chosen = K.chooseCandidate(shopper, shelves, {environment})
            local key = chosen.source or 'environment'
            counts[key] = (counts[key] or 0) + 1
        end
    end
end
check(counts[shelves[1]] == 35 and counts[shelves[2]] == 140 and counts[shelves[3]] == 70
    and not counts[shelves[4]] and counts.environment == 35,
    'Containers and decorations share one draw with exact capped weights; empty candidates have no chance')
ZombRand = random

local simple = player()
local scenery = {getSprite=function() return {getProperties=function() return {has=function() return false end} end} end}
check(not K.moveableCandidate(simple, sq, scenery), 'Non-moveable scenery is rejected by its sprite flag')
local instanceCount = 0
local originalInstance = PROPS.instanceItem
PROPS.instanceItem = function() instanceCount = instanceCount + 1; return proto end
PROPS.weight = 20
check(not K.moveableCandidate(simple, sq, object) and instanceCount == 0, 'Heavy scenery is rejected before item instantiation')
PROPS.weight = 0.5
local decoration = K.moveableCandidate(simple, sq, object)
check(decoration and instanceCount == 1, 'Instantiate one prototype for an eligible decoration')
local unrelated = item(0.1, simple.inventory)
local priorDecoration = item(0.5, simple.inventory, 'decoration_1')
K.startPickup(simple, decoration)
local pickupAction = simple.queue.queue[1]
local allValid = true
for i = 1, 100 do if not pickupAction:isValid() then allValid = false end end
check(allValid, 'Cached decoration remains valid through repeated action checks')
check(instanceCount == 1, 'One hundred action validations create no additional items')
local storedBefore = K.state(simple).inFlight.before
check(storedBefore[tostring(priorDecoration.id)] and not storedBefore[tostring(unrelated.id)], 'Receipt snapshot stores only matching item types')
simple.inventory.capacity = 0
check(not pickupAction:isValid(), 'A newly full main inventory cancels furniture pickup before overfilling')
simple.inventory.capacity = 20
local originalReceipt = K.receivedPickup
local receiptReads = 0
K.receivedPickup = function(...) receiptReads = receiptReads + 1; return originalReceipt(...) end
for i = 1, 100 do K.checkActive(simple, i * 750) end
check(receiptReads == 0, 'Do not search the inventory while the pickup action is still running')
simple.queue.queue = {}
local newDecoration = item(0.5, simple.inventory, 'decoration_1')
K.checkActive(simple, 76000)
check(receiptReads == 1 and not K.state(simple).pending, 'Check receipt after pickup leaves the action queue')
K.receivedPickup = originalReceipt
PROPS.instanceItem = originalInstance

do
    CLIENT = true
    local recipient = player()
    local original = item(0.1, shared.container)
    K.state(recipient).pending = true
    K.startTransfer(recipient, {item=original, source=shared, destination=recipient.inventory})
    local action = recipient.queue.queue[1]
    local delivered = item(0.1, recipient.inventory)
    delivered.id = original.id
    original.container = nil
    action.callback()
    check(not K.state(recipient).pending and not K.state(recipient).retryStarted,
        'Confirm the deserialized server item by ID before the next queued action')
    local confirmedAt = K.state(recipient).lastSuccess
    gameMinutes = gameMinutes + 1
    action.callback()
    check(K.state(recipient).lastSuccess == confirmedAt, 'Completion is idempotent')
    recipient.queue.queue = {}
    K.checkActive(recipient, 80000)

    local delayedPlayer = player()
    local lateOriginal = item(0.1, shared.container)
    K.startTransfer(delayedPlayer, {item=lateOriginal, source=shared, destination=delayedPlayer.inventory})
    delayedPlayer.queue.queue = {}
    K.checkActive(delayedPlayer, 80000)
    local lateCopy = item(0.1, delayedPlayer.inventory)
    lateCopy.id = lateOriginal.id
    lateOriginal.container = nil
    K.checkActive(delayedPlayer, 80750)
    check(not K.state(delayedPlayer).pending and not K.state(delayedPlayer).inFlight,
        'A packet received after queue removal satisfies the urge within the grace period')

    local cancelledPlayer = player()
    local cancelledOriginal = item(0.1, shared.container)
    K.startTransfer(cancelledPlayer, {item=cancelledOriginal, source=shared, destination=cancelledPlayer.inventory})
    local cancelledAction = cancelledPlayer.queue.queue[1]
    local copy = item(0.1, cancelledPlayer.inventory)
    copy.id = cancelledOriginal.id
    cancelledOriginal.container = nil
    cancelledAction:stop()
    check(not K.state(cancelledPlayer).pending and not K.state(cancelledPlayer).retryStarted,
        'Cancellation after receipt recognizes a replacement item object')
    K.checkActive(cancelledPlayer, 82000)
    CLIENT = false
end

do
    local collector = player()
    local bag = wearBag(collector, 10)
    local owned = item(0.5, bag, 'decoration_1')
    local decoration = K.moveableCandidate(collector, sq, object)
    K.startPickup(collector, decoration)
    local flight = K.state(collector).inFlight
    move(owned, collector.inventory)
    check(not K.receivedPickup(collector, flight),
        'Unpacking an existing decoration cannot count as a successful theft')
    local received = item(0.5, bag, 'decoration_1')
    check(K.receivedPickup(collector, flight) == received,
        'A newly received decoration remains recognizable after being packed')
    collector.queue.queue = {}
    K.checkActive(collector, 83000)
    check(not K.state(collector).pending and #collector.queue.queue == 0,
        'Already packed furniture satisfies the urge without a redundant transfer')
end

CLIENT = true
local recovering = player()
local incoming = item(0.1, shared.container)
K.state(recovering).inFlight = {itemID=incoming.id}
local recursiveReads = 0
local originalLookup = recovering.inventory.getItemWithIDRecursiv
recovering.inventory.getItemWithIDRecursiv = function(self, id)
    recursiveReads = recursiveReads + 1
    return originalLookup(self, id)
end
for now = 0, 9750, 750 do K.recover(recovering, now) end
check(recursiveReads == 1, 'Unchanged late receipt is checked once per ten seconds')
move(incoming, recovering.inventory)
Events.OnContainerUpdate.handler()
K.recover(recovering, 9750)
check(recursiveReads == 2 and not K.state(recovering).pending, 'An inventory packet triggers immediate late-receipt reconciliation')
local beforeRetry = player()
local receivedWithoutEvent = item(0.1, shared.container)
K.state(beforeRetry).inFlight = {itemID=receivedWithoutEvent.id}
K.recover(beforeRetry, 0)
move(receivedWithoutEvent, beforeRetry.inventory)
gameMinutes = gameMinutes + 10
K.surroundings = function() error('Searched after an unobserved successful theft') end
local recoveredBeforeSearch = pcall(K.tickPlayer, beforeRetry, 1000)
K.surroundings = originalSurroundings
check(recoveredBeforeSearch and not K.state(beforeRetry).pending and not K.state(beforeRetry).inFlight,
    'Reconcile a late receipt before retrying even without an inventory event or a real-time timeout')
CLIENT = false

local removed = {kind='IsoDeadBody', getStaticMovingObjectIndex=function() return -1 end}
check(not K.sourceValid(p, {container=source.container, square=sq, object=removed}), 'Reject removed corpse even if container reports itself alive')
removed = {kind='IsoWorldInventoryObject', getWorldObjectIndex=function() return -1 end}
check(not K.sourceValid(p, {container=source.container, square=sq, object=removed}), 'Reject removed ground bag')
removed = {getObjectIndex=function() return -1 end}
check(not K.sourceValid(p, {container=source.container, square=sq, object=removed}), 'Reject removed furniture container')

local disabled = player()
local running = player()
local originalItem = item(0.1, shared.container)
K.state(running).pending = true
K.startTransfer(running, {item=originalItem, source=shared, destination=running.inventory})
local runningAction = running.queue.queue[1]
local originalTime = getGameTime
local originalPause = isGamePaused
local function forbiddenWork() error('Disabled mechanic performed work') end
getGameTime = forbiddenWork
getTimestampMs = forbiddenWork
getNumActivePlayers = forbiddenWork
isGamePaused = forbiddenWork
for _, setting in ipairs({'MaxWeight', 'IntervalMinutes'}) do
    local previous = SandboxVars.Kleptomaniac[setting]
    SandboxVars.Kleptomaniac[setting] = 0
    check(not K.enabled(), 'Zero ' .. setting .. ' disables the mechanic')
    if setting == 'MaxWeight' then check(not K.allowedWeight(item(0)), 'Zero weight disables even weightless items') end
    check(pcall(Events.OnTick.handler), 'Disabled tick returns before clocks or player enumeration')
    check(pcall(Events.OnCreatePlayer.handler, 0, disabled), 'Disabled player creation does not initialize a timer')
    check(pcall(Events.OnContainerUpdate.handler), 'Disabled container event performs no timer or inventory work')
    check(pcall(K.tickPlayer, disabled, 0), 'Disabled player tick performs no work')
    check(not K.updateUrge(disabled), 'Disabled urge update does not read game time')
    K.recover(disabled)
    K.startTransfer(disabled, nil); K.startPickup(disabled, nil)
    check(disabled.data.Kleptomaniac == nil and disabled.queue == nil, 'Disabled mode creates no state and queues no actions')
    check(not runningAction:isValid(), 'Disabling also invalidates an already queued theft')
    check(pcall(function() runningAction:stop(); runningAction.callback() end), 'Callbacks while disabled do not update timers')
    check(K.state(running).pending and not K.state(running).retryStarted, 'Disabled callbacks leave saved urge and cooldown unchanged')
    SandboxVars.Kleptomaniac[setting] = previous
end
getGameTime = originalTime
isGamePaused = originalPause
SandboxVars.Kleptomaniac.MaxWeight = 2
check(K.enabled() and K.allowedWeight(item(2)), 'Live positive weight restores the mechanic')
check(not K.updateUrge(disabled), 'Re-enabled new character starts with a fresh interval')
print('PASS: ' .. tests .. ' behavior checks')
