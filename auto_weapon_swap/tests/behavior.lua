-- Run with Lua 5.1 from the package root: lua tests/behavior.lua
-- Uses engine stubs, does not test a live game
local root = "Contents/mods/auto_weapon_swap/common/media/lua/client/"
local function list(values)
    values = values or {}
    values.size = function(self) return #self end
    values.get = function(self, i) return self[i + 1] end
    return values
end
local now, nextID = 0, 0
local paused = false
function isGamePaused() return paused end
function isClient() return false end
local players, pages, loot, queues = {}, {}, {}, {}
local loaded = {}
function require(name)
    if name:match("^AutoWeaponSwap/") and not loaded[name] then
        loaded[name] = true
        local base = name == "AutoWeaponSwap/ContainerAddress" and root:gsub("client/$", "shared/") or root
        dofile(base .. name .. ".lua")
    end
end
function instanceof(object, class) return object and object.class == class end
function getTimestampMs() return now end
function getRandomUUID() nextID = nextID + 1; return "test-uuid-" .. nextID end
function getSpecificPlayer(id) return players[id] end
function getPlayerInventory(id) return pages[id] end
function getPlayerLoot(id) return loot[id] end
function getText(key) return key end
Events = {}
LuaEventManager = {}
function LuaEventManager.AddEvent(key)
    if Events[key] then return Events[key] end
    local event = {handlers = {}}
    event.Add = function(fn) event.handlers[#event.handlers + 1] = fn end
    Events[key] = event
    return event
end
-- Events registered by the game
for _, key in ipairs({"OnPlayerUpdate", "OnPlayerAttackFinished", "OnFillInventoryObjectContextMenu",
    "OnFillWorldObjectContextMenu", "OnKeyPressed", "OnGameStart", "OnTickEvenPaused", "OnServerCommand", "OnClientCommand", "OnObjectAboutToBeRemoved"}) do
    LuaEventManager.AddEvent(key)
end

local function container(kind)
    local c = {kind = kind or "crate", items = list(), data = {}}
    function c:getType() return self.kind end
    function c:getContainingItem() return self.bag end
    function c:getVehiclePart() return self.part end
    function c:getParent() return self.owner end
    function c:getItems() return self.items end
    function c:contains(item) for _, v in ipairs(self.items) do if v == item then return true end end; return false end
    function c:isRemoveItemAllowed(item) return not item.noRemove end
    function c:hasRoomFor() return not self.full end
    function c:getCustomName() return nil end
    function c:add(item) self.items[#self.items + 1] = item; item.container = self end
    return c
end
local function owner()
    local o = {data = {}}
    function o:getModData() return self.data end
    function o:getContainerIndex(c) return c.index or 0 end
    function o:transmitModData() self.transmitted = true end
    return o
end
local function weapon(kind)
    nextID = nextID + 1
    local w = {class = "HandWeapon", id = nextID, kind = kind or "Axe", condition = 10}
    function w:getID() return self.id end
    function w:getType() return self.kind end
    function w:getFullType() return "Base." .. self.kind end
    function w:getName() return self.kind end
    function w:getCondition() return self.condition end
    function w:getConditionMax() return 10 end
    function w:isBroken() return self.broken == true end
    function w:isRanged() return self.ranged == true end
    function w:isAimedFirearm() return self.firearm == true end
    function w:isJammed() return self.jammed == true end
    function w:haveChamber() return self.chamber == true end
    function w:isRoundChambered() return self.loaded == true end
    function w:getCurrentAmmoCount() return self.ammo or 0 end
    function w:getIsCraftingConsumed() return self.consumed == true end
    function w:getContainer() return self.container end
    function w:getWorldItem() return self.world end
    function w:isTwoHandWeapon() return self.twoHand == true end
    function w:isRequiresEquippedBothHands() return self.requiresTwoHand == true end
    return w
end
local function bag(player, nested)
    local b = weapon("Bag")
    b.class = "InventoryContainer"
    b.inventory = container("bag")
    b.inventory.bag = b
    function b:getInventory() return self.inventory end
    if nested then nested:add(b) else player.inventory:add(b); b.equipped = true end
    return b
end

ISTimedActionQueue = {}
function ISTimedActionQueue.getTimedActionQueue(player) return queues[player] end
function ISTimedActionQueue.add(action)
    local q = queues[action.character].queue
    q[#q + 1] = action
end
ISInventoryTransferUtil = {}
function ISInventoryTransferUtil.newInventoryTransferAction(player, item, source, dest)
    return {Type = "ISInventoryTransferAction", character = player, item = item,
        isValid = function() return source:contains(item) and not dest.full end}
end
ISEquipWeaponAction = {}
function ISEquipWeaponAction:new(player, item, time, primary, twoHands)
    return {Type = "ISEquipWeaponAction", character = player, item = item, twoHands = twoHands,
        isValid = function() return player.inventory:contains(item) end}
end
ISInventoryPaneContextMenu = {}
function ISInventoryPaneContextMenu.getContainers(player)
    local result = list({player.inventory})
    for _, c in ipairs(player.visible) do
        if not c.locked and not c.outOfRange then result[#result + 1] = c end
    end
    return result
end
ISInventoryPane = {getActualItems = function(items) return items end}
ISInventoryPage = {onBackpackRightMouseDown = function(button) button.originalCalled = true end}
local function menu()
    local m = {options = {}}
    function m:addOption(name, target, callback, arg)
        local opt = {name = name, target = target, callback = callback, arg = arg}
        self.options[#self.options + 1] = opt
        return opt
    end
    function m:setOptionChecked(option, checked) option.checked = checked end
    function m:addSubMenu(option, sub) option.sub = sub end
    return m
end
ISContextMenu = {getNew = function() return menu() end}
ISWorldObjectContextMenu = {}
local playerMenus = {}
function getPlayerContextMenu(id) return playerMenus[id] end

local function player()
    local p = {inventory = container("inventory"), visible = {}, data = {}, id = #players + 1}
    function p:getModData() return self.data end
    function p:getInventory() return self.inventory end
    function p:getPlayerNum() return self.id end
    function p:isEquipped(item) return item.equipped == true end
    function p:getPrimaryHandItem() return self.primary end
    function p:getSecondaryHandItem() return self.secondary end
    function p:isLocalPlayer() return not self.remote end
    function p:isDead() return self.dead == true end
    function p:isAttacking() return self.attacking == true end
    players[p.id] = p
    pages[p.id] = {refreshBackpacks = function() end, inventoryPane = {inventory = p.inventory}}
    loot[p.id] = {refreshBackpacks = function() end}
    queues[p] = {queue = {}, indexOf = function(self, action)
        for i, a in ipairs(self.queue) do if a == action then return i end end
        return -1
    end}
    return p
end
require "AutoWeaponSwap/Core"
assert(Events.OnFillInventoryContextMenuNoItems == nil)
dofile(root .. "AutoWeaponSwap/Menu.lua")
local AWS = AutoWeaponSwap
local count = 0
local function check(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end
local function setup()
    local p = player()
    local old, replacement = weapon(), weapon()
    p.inventory:add(old); p.primary = old
    local b = bag(p)
    b.inventory:add(replacement)
    p.visible = {b.inventory}
    AWS.toggleContainer(p, b.inventory)
    AWS.onPlayerUpdate(p)
    return p, old, replacement, b.inventory
end
local function breakWeapon(p, old)
    old.condition = 0
    p.primary = nil
    AWS.onPlayerUpdate(p)
end

check("empty-container event is registered before subscription and menu works", function()
    local p = player(); local m = menu()
    local event = assert(Events.OnFillInventoryContextMenuNoItems)
    assert(#event.handlers == 1)
    assert(LuaEventManager.AddEvent("OnFillInventoryContextMenuNoItems") == event)
    event.handlers[1](p.id, m, false)
    assert(#m.options == 1)
    local option = m.options[1]; option.callback(option.target, option.arg)
    assert(AWS.enabled(p, p.inventory))
end)

check("opt-in defaults and per-player persistence", function()
    local p = player(); local b = bag(p)
    assert(not AWS.enabled(p, b.inventory))
    AWS.toggleContainer(p, b.inventory)
    local q = player(); assert(not AWS.enabled(q, b.inventory))
    q.data = p.data; assert(AWS.enabled(q, b.inventory))
    AWS.toggleContainer(q, b.inventory); assert(not AWS.enabled(p, b.inventory))
end)
check("break queues vanilla transfer then equip, leaving old item untouched", function()
    local p, old, replacement = setup(); breakWeapon(p, old)
    local actions = queues[p].queue
    assert(#actions == 2 and actions[1].Type == "ISInventoryTransferAction" and actions[2].Type == "ISEquipWeaponAction")
    assert(actions[1].item == replacement and p.inventory:contains(old))
    for i = 1, 20 do AWS.onPlayerUpdate(p) end
    assert(#actions == 2)
end)
check("manual unequip, drop and healthy switch do not trigger", function()
    for _, mode in ipairs({"unequip", "drop", "switch"}) do
        local p, old = setup()
        p.primary = nil
        if mode == "drop" then old.container = nil; old.world = {} end
        if mode == "switch" then p.primary = weapon("Hammer"); old.condition = 0 end
        AWS.onPlayerUpdate(p); assert(#queues[p].queue == 0)
    end
end)
check("disappearance and positive-condition broken flag trigger", function()
    local p, old = setup(); old.container = nil; p.primary = nil
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 2)
    p, old = setup(); old.broken = true
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 2)
end)
check("broken replacement object triggers, healthy replacement is respected", function()
    local p, old = setup(); old.condition = 0
    p.primary = weapon("Handle"); p.primary.class = "InventoryItem"; p.primary.broken = true
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 2)
    p, old = setup(); old.condition = 0; p.primary = weapon("Branch")
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 0)
end)
check("usable break results stay unless their resulting type is excluded", function()
    for _, kind in ipairs({"Branch_Broken", "SteelBarHalf", "SteelBarQuarter", "SteelRodHalf"}) do
        for _, excluded in ipairs({false, true}) do
            local p, old, spare = setup()
            old.condition = 0
            local fragment = weapon(kind); p.inventory:add(fragment); p.primary = fragment
            AWS.settings(p).types[fragment:getFullType()] = excluded or nil
            AWS.onPlayerUpdate(p)
            assert(#queues[p].queue == (excluded and 2 or 0))
            assert(p.primary == fragment and p.inventory:contains(fragment))
            if excluded then
                assert(queues[p].queue[1].item == spare and queues[p].queue[1]:isValid())
                p.inventory:add(spare); assert(queues[p].queue[2]:isValid())
            end
        end
    end
end)
check("break result arriving during attack is evaluated after transformation", function()
    for _, excluded in ipairs({false, true}) do
        local p, old = setup(); p.attacking = true; old.condition = 0
        AWS.onPlayerUpdate(p); assert(#queues[p].queue == 0)
        local fragment = weapon("SteelBarHalf"); p.inventory:add(fragment); p.primary = fragment
        AWS.settings(p).types[fragment:getFullType()] = excluded or nil
        AWS.onPlayerUpdate(p); assert(#queues[p].queue == 0)
        p.attacking = false; AWS.onAttackFinished(p, old); AWS.onPlayerUpdate(p)
        assert(#queues[p].queue == (excluded and 2 or 0))
    end
end)
check("excluded break result remains if there is no allowed spare", function()
    local p, old, spare = setup(); old.condition = 0
    local fragment = weapon("Branch_Broken"); p.inventory:add(fragment); p.primary = fragment
    AWS.settings(p).types[fragment:getFullType()] = true
    AWS.settings(p).types[spare:getFullType()] = true
    AWS.onAttackFinished(p, old); AWS.onPlayerUpdate(p)
    assert(#queues[p].queue == 0 and p.primary == fragment)
end)
check("manual excluded weapon is preserved; removing result exclusion cancels swap", function()
    local p, old = setup()
    local manual = weapon("Branch_Broken"); p.inventory:add(manual); p.primary = manual
    AWS.settings(p).types[manual:getFullType()] = true
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 0)
    p, old = setup(); old.condition = 0
    local fragment = weapon("Branch_Broken"); p.inventory:add(fragment); p.primary = fragment
    AWS.settings(p).types[fragment:getFullType()] = true
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 2)
    AWS.settings(p).types[fragment:getFullType()] = nil
    assert(not queues[p].queue[1]:isValid())
end)
check("transformed non-weapon triggers but a later manual item switch cancels", function()
    local p, old = setup(); old.condition = 0
    p.primary = weapon("Scrap"); p.primary.class = "InventoryItem"
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 2)
    assert(queues[p].queue[1]:isValid())
    p.primary = weapon("Torch"); p.primary.class = "InventoryItem"
    assert(not queues[p].queue[1]:isValid())
end)
check("nested and unequipped bags are excluded, ground bags accepted", function()
    local p, old, replacement, source = setup()
    source.bag.equipped = false
    assert(AWS.choose(p, old) == nil)
    local outer = container("bag"); outer:add(source.bag)
    assert(AWS.choose(p, old) == nil)
    source.bag.world = {getSquare = function() return {} end}
    assert(AWS.choose(p, old) == replacement)
end)
check("locked, unreachable and unmarked world containers excluded", function()
    local p = player(); local c = container(); c.owner = owner(); c:add(weapon())
    p.visible = {c}; local old = weapon()
    assert(AWS.choose(p, old) == nil)
    AWS.toggleContainer(p, c); assert(c.owner.transmitted and AWS.choose(p, old))
    c.locked = true; assert(AWS.choose(p, old) == nil)
    c.locked = false; c.outOfRange = true; assert(AWS.choose(p, old) == nil)
end)
check("world preferences belong to object, not reused location; compartments independent", function()
    local p = player(); local a, b = container(), container()
    a.owner = owner(); b.owner = a.owner; b.index = 1
    AWS.toggleContainer(p, a); assert(not AWS.enabled(p, b))
    a.owner = owner(); assert(not AWS.enabled(p, a))
end)
check("same type preference and type exclusions", function()
    local p, old, replacement, source = setup(); replacement.condition = 1
    local hammer = weapon("Hammer"); source:add(hammer)
    assert(AWS.choose(p, old) == replacement)
    AWS.settings(p).types[replacement:getFullType()] = true
    assert(AWS.choose(p, old) == hammer)
    AWS.settings(p).types[hammer:getFullType()] = true
    assert(AWS.choose(p, old) == nil)
end)
check("broken, consumed, empty, jammed and capacity-blocked weapons skipped", function()
    local p, old, w = setup()
    w.broken = true; assert(not AWS.choose(p, old)); w.broken = false
    w.consumed = true; assert(not AWS.choose(p, old)); w.consumed = false
    w.firearm = true; w.chamber = true; w.ammo = 10
    assert(not AWS.choose(p, old)); w.loaded = true; assert(AWS.choose(p, old))
    w.jammed = true; assert(not AWS.choose(p, old)); w.jammed = false
    p.inventory.full = true; assert(not AWS.choose(p, old))
end)
check("moving away, removing backpack, disabling source invalidate transfer", function()
    for _, mode in ipairs({"away", "remove", "disable"}) do
        local p, old, _, source = setup(); breakWeapon(p, old)
        local action = queues[p].queue[1]; assert(action:isValid())
        if mode == "away" then p.visible = {} end
        if mode == "remove" then source.bag.equipped = false end
        if mode == "disable" then AWS.toggleContainer(p, source) end
        now = now + 101; assert(not action:isValid())
    end
end)
check("manual/other-mod switch, repair and exclusion cancel pending actions", function()
    for _, mode in ipairs({"switch", "repair", "exclude"}) do
        local p, old, w = setup(); breakWeapon(p, old)
        if mode == "switch" then p.primary = weapon("Hammer") end
        if mode == "repair" then old.condition = 10 end
        if mode == "exclude" then AWS.settings(p).types[w:getFullType()] = true end
        assert(not queues[p].queue[1]:isValid())
    end
end)
check("transfer failure prevents equipping nonexistent item", function()
    local p, old, w = setup(); breakWeapon(p, old)
    assert(not queues[p].queue[2]:isValid())
    p.inventory:add(w); assert(queues[p].queue[2]:isValid())
end)
check("cancellation does not enqueue an endless replacement loop", function()
    local p, old = setup(); breakWeapon(p, old); queues[p].queue = {}
    for i = 1, 20 do AWS.onPlayerUpdate(p) end
    assert(#queues[p].queue == 0)
end)
check("attack and existing actions deferred without clearing user queue", function()
    local p, old = setup(); p.attacking = true; breakWeapon(p, old)
    assert(#queues[p].queue == 0); p.attacking = false
    queues[p].queue = {{Type = "OtherModAction"}}
    AWS.onPlayerUpdate(p); assert(#queues[p].queue == 1)
    queues[p].queue = {}; AWS.onPlayerUpdate(p); assert(#queues[p].queue == 2)
end)
check("remote/dead players ignored and long attacks preserve requests", function()
    local p, old = setup(); p.remote = true; breakWeapon(p, old); assert(#queues[p].queue == 0)
    p, old = setup(); p.dead = true; breakWeapon(p, old); assert(#queues[p].queue == 0)
    p, old = setup(); p.attacking = true; breakWeapon(p, old)
    now = now + 300000; p.attacking = false; AWS.onPlayerUpdate(p); assert(#queues[p].queue == 2)
end)
check("long queue waits and pauses preserve one replacement without interrupting actions", function()
    local p, old = setup()
    local existing = {Type = "OtherModAction"}; queues[p].queue = {existing}
    breakWeapon(p, old)
    now = now + 300000; AWS.onPlayerUpdate(p)
    assert(#queues[p].queue == 1 and queues[p].queue[1] == existing)
    paused = true; queues[p].queue = {}
    now = now + 3600000
    for i = 1, 5 do AWS.onPlayerUpdate(p) end
    assert(#queues[p].queue == 0)
    paused = false; AWS.onPlayerUpdate(p)
    assert(#queues[p].queue == 2)
    for i = 1, 5 do AWS.onPlayerUpdate(p) end
    assert(#queues[p].queue == 2)
end)
check("manual weapon selection including excluded types permanently cancels queued request", function()
    for _, excluded in ipairs({false, true}) do
        local p, old = setup(); queues[p].queue = {{Type = "ManualEquip"}}
        breakWeapon(p, old)
        local manual = weapon("Hammer"); p.inventory:add(manual); p.primary = manual
        AWS.settings(p).types[manual:getFullType()] = excluded or nil
        now = now + 300000; AWS.onPlayerUpdate(p)
        queues[p].queue = {}; AWS.onPlayerUpdate(p)
        assert(#queues[p].queue == 0 and p.primary == manual)
        p.primary = nil; AWS.onPlayerUpdate(p); assert(#queues[p].queue == 0)
    end
end)
check("repair or death while waiting cancels request", function()
    for _, mode in ipairs({"repair", "death"}) do
        local p, old = setup(); queues[p].queue = {{Type = "OtherAction"}}
        breakWeapon(p, old)
        if mode == "repair" then old.condition = 10 else p.dead = true end
        AWS.onPlayerUpdate(p); queues[p].queue = {}; p.dead = false
        AWS.onPlayerUpdate(p); assert(#queues[p].queue == 0)
    end
end)
check("long OnBreak processing preserves allowed fragments and replaces excluded ones", function()
    for _, excluded in ipairs({false, true}) do
        local p, old = setup(); p.attacking = true; breakWeapon(p, old)
        local fragment = weapon("Branch_Broken"); p.inventory:add(fragment); p.primary = fragment
        AWS.settings(p).types[fragment:getFullType()] = excluded or nil
        now = now + 300000; AWS.onPlayerUpdate(p)
        assert(#queues[p].queue == 0)
        p.attacking = false; queues[p].queue = {{Type = "OtherAction"}}
        AWS.onPlayerUpdate(p); now = now + 300000; queues[p].queue = {}
        AWS.onPlayerUpdate(p)
        assert(#queues[p].queue == (excluded and 2 or 0) and p.primary == fragment)
    end
end)
check("idle search rechecks source and exclusions once and never resumes later", function()
    for _, change in ipairs({"away", "disable", "exclude", "broken", "empty"}) do
        local p, old, spare, source = setup(); queues[p].queue = {{Type = "OtherAction"}}
        breakWeapon(p, old)
        if change == "away" then p.visible = {} end
        if change == "disable" then AWS.toggleContainer(p, source) end
        if change == "exclude" then AWS.setTypeExcluded(p, spare:getFullType(), true) end
        if change == "broken" then spare.condition = 0 end
        if change == "empty" then source.items = list() end
        local choose, attempts = AWS.choose, 0
        AWS.choose = function(...) attempts = attempts + 1; return choose(...) end
        now = now + 300000; queues[p].queue = {}; AWS.onPlayerUpdate(p)
        assert(attempts == 1 and #queues[p].queue == 0)
        p.visible = {source}
        if not AWS.enabled(p, source) then AWS.toggleContainer(p, source) end
        AWS.setTypeExcluded(p, spare:getFullType(), false); spare.condition = 10
        if change == "empty" then source:add(spare) end
        for i = 1, 10 do AWS.onPlayerUpdate(p) end
        assert(attempts == 1 and #queues[p].queue == 0 and p.inventory:contains(old))
        AWS.choose = choose
    end
end)
check("two-handed choice preserves held bag unless weapon requires both hands", function()
    local p, old, w = setup(); p.secondary = weapon("Bag"); w.twoHand = true
    breakWeapon(p, old); assert(not queues[p].queue[2].twoHands)
    p, old, w = setup(); w.requiresTwoHand = true
    breakWeapon(p, old); assert(queues[p].queue[2].twoHands)
end)
check("container tab chains vanilla menu without duplicate options", function()
    local p, _, _, c = setup(); local m = menu(); playerMenus[p.id] = m
    AWS.containerOption(p, m, c)
    local button = {inventory = c, parent = {parent = {player = p.id}}}
    ISInventoryPage.onBackpackRightMouseDown(button, 0, 0)
    assert(button.originalCalled and #m.options == 1 and m.options[1].checked)
    local option = m.options[1]; option.callback(option.target, option.arg)
    assert(not AWS.enabled(p, c))
end)
check("weapon menu only toggles type exclusions", function()
    local p, _, w = setup(); local m = menu()
    Events.OnFillInventoryObjectContextMenu.handlers[1](p.id, m, {w})
    assert(#m.options == 1)
    for _, o in ipairs(m.options) do o.callback(o.target, o.arg) end
    assert(AWS.settings(p).items == nil and AWS.settings(p).types[w:getFullType()])
end)
print(tostring(count) .. " regression scenarios passed")

AWS_test = { player = player, weapon = weapon, menu = menu }
