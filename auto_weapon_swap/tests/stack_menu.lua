-- Run after behavior.lua, with GAME_LUA_ROOT set to the installed media/lua
local file = assert(io.open(GAME_LUA_ROOT .. "/client/ISUI/ISInventoryPane.lua", "r"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local oldExpand, oldInstanceof = ISInventoryPane.getActualItems, instanceof
assert(loadstring(assert(source:match("(function ISInventoryPane.getActualItems%([^\n]*.-)\nfunction ISInventoryPane.getActualUniqueItems"))))()
function instanceof(item, class)
    if class == "InventoryItem" then
        return item and (item.class == "HandWeapon" or item.class == "InventoryContainer" or item.class == "InventoryItem")
    end
    return oldInstanceof(item, class)
end
local AWS, fixtures = AutoWeaponSwap, AWS_test
local player = fixtures.player()
local a, b = fixtures.weapon("Axe"), fixtures.weapon("Axe")
local stack = {items = {a, a, b}} -- vanilla dummy first entry
local callback = Events.OnFillInventoryObjectContextMenu.handlers[1]
for _, selection in ipairs({{stack}, {a, b}, {stack, a, b}}) do
    assert(#ISInventoryPane.getActualItems(selection) == 2)
    local menu = fixtures.menu()
    callback(player:getPlayerNum(), menu, selection)
    assert(#menu.options == 1 and not menu.options[1].checked)
    local option = menu.options[1]
    option.callback(option.target, option.arg)
    assert(AWS.excluded(player, a) and AWS.excluded(player, b))
    menu = fixtures.menu(); callback(player:getPlayerNum(), menu, selection)
    assert(#menu.options == 1 and menu.options[1].checked)
    option = menu.options[1]; option.callback(option.target, option.arg)
    assert(not AWS.excluded(player, a))
end
local nonWeapon = fixtures.weapon("Axe"); nonWeapon.class = "InventoryItem"
local moddedAxe = fixtures.weapon("Axe")
function moddedAxe:getFullType() return "OtherMod.Axe" end
for _, selection in ipairs({{}, {nonWeapon}}) do
    local menu = fixtures.menu()
    callback(player:getPlayerNum(), menu, selection)
    assert(#menu.options == 0 and next(AWS.settings(player).types) == nil)
end
local hammer = fixtures.weapon("Hammer")
for _, selection in ipairs({{stack, hammer}, {stack, a, b, hammer}, {a, moddedAxe}}) do
    for _, initial in ipairs({"none", "partial", "all"}) do
        AWS.settings(player).types = {['Unrelated.Spear'] = true}
        local second = selection[#selection]
        if initial ~= "none" then AWS.setTypeExcluded(player, a:getFullType(), true) end
        if initial == "all" then AWS.setTypeExcluded(player, second:getFullType(), true) end
        local menu = fixtures.menu()
        callback(player:getPlayerNum(), menu, selection)
        assert(#menu.options == 1)
        local option = menu.options[1]
        local remove = initial == "all"
        assert(option.name == (remove and "ContextMenu_AWS_AllowTypes" or "ContextMenu_AWS_ExcludeTypes"))
        assert(option.checked == remove and #option.arg.types == 2)
        option.callback(option.target, option.arg)
        assert(AWS.excluded(player, a) == not remove)
        assert(AWS.excluded(player, second) == not remove)
        assert(AWS.settings(player).types['Unrelated.Spear'])
    end
end
AWS.settings(player).types = {}
local menu = fixtures.menu()
callback(player:getPlayerNum(), menu, {a, nonWeapon, hammer})
local option = menu.options[1]
assert(#menu.options == 1 and #option.arg.types == 2)
option.callback(option.target, option.arg)
assert(AWS.excluded(player, a) and AWS.excluded(player, hammer))
-- Changing settings must not change an open menu action
menu = fixtures.menu(); callback(player:getPlayerNum(), menu, {a, hammer})
option = menu.options[1]
AWS.setTypeExcluded(player, a:getFullType(), false)
option.callback(option.target, option.arg)
assert(not AWS.excluded(player, a) and not AWS.excluded(player, hammer))
ISInventoryPane.getActualItems, instanceof = oldExpand, oldInstanceof
print("16 stack/selection scenarios passed with vanilla getActualItems")
