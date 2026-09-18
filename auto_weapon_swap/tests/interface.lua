-- Load after behavior.lua with GAME_LUA_ROOT set to the game Lua directory
local AWS = AutoWeaponSwap
local player = AWS_test.player
local p = player()
function getSoundManager() return {playUISound = function() end} end
local scriptItems = { ["Base.Axe"] = "Axe", ["Base.Branch_Broken"] = "Broken branch" }
function getScriptManager()
    return {FindItem = function(_, fullType)
        if scriptItems[fullType] then return {getDisplayName = function() return scriptItems[fullType] end} end
    end}
end
function getItemTex(fullType) return scriptItems[fullType] and ("texture:" .. fullType) or nil end
local core = {paused = false, text = false}
function core:getScreenWidth() return 1280 end
function core:getScreenHeight() return 720 end
function core:isDoingTextEntry() return self.text end
function getCore() return core end
function isGamePaused() return core.paused end
UIFont = {Small = 1}
function getTextManager()
    return {getFontHeight = function() return 16 end, MeasureStringX = function(_, _, text) return #text * 8 end}
end
local Base = {}
function Base:derive(name) local c = {Type = name}; setmetatable(c, {__index = self}); return c end
function Base:new(x, y, width, height)
    return setmetatable({x = x, y = y, width = width, height = height, visible = true,
        children = {}, items = {}, selected = 0, vscroll = {getWidth = function() return 16 end}}, {__index = self})
end
function Base:initialise() end
function Base:instantiate() end
function Base:addToUIManager() self.inUI = true; if self.createChildren and not self.created then self:createChildren(); self.created = true end end
function Base:removeFromUIManager() self.inUI = false end
function Base:addChild(child) self.children[#self.children + 1] = child end
function Base:setVisible(value) self.visible = value end
function Base:isVisible() return self.visible end
function Base:bringToTop() end
function Base:setResizable(value) self.resizable = value end
function Base:onResize() end
function Base:setWidth(value) self.width = value; self:onResize() end
function Base:setHeight(value) self.height = value; self:onResize() end
function Base:setX(value) self.x = value end
function Base:setY(value) self.y = value end
function Base:getY() return self.y end
function Base:titleBarHeight() return 24 end
function Base:resizeWidgetHeight() return 16 end
function Base:createChildren() end
function Base:prerender() end
function Base:drawText() end
function Base:drawRect() end
function Base:isVScrollBarVisible() return #self.items * self.itemheight > self.height end
function Base:getYScroll() return self.scroll or 0 end
function Base:setYScroll(value) self.scroll = value end
function Base:rowAt(x, y) local i = math.floor(y / self.itemheight) + 1; return self.items[i] and i or -1 end
function Base:topOfItem(i) return (i - 1) * self.itemheight end
function Base:onMouseDown() end
function Base:onMouseUp() end
function Base:onMouseUpOutside() end
function Base:clear() self.items = {} end
function Base:addItem(name, item) self.items[#self.items + 1] = {text = name, item = item, index = #self.items + 1} end
ISCollapsableWindow = Base:derive("Window")
ISScrollingListBox = Base:derive("List")
ISButton = Base:derive("Button")

local root = "Contents/mods/auto_weapon_swap/common/media/lua/client/AutoWeaponSwap/"
dofile(root .. "Window.lua")
local count = 0
local function check(name, fn) fn(); count = count + 1; print("PASS " .. name) end

AWS.setTypeExcluded(p, "Base.Axe", true)
check("rows contain localized names and textures, retaining missing-mod entries", function()
    AWS.setTypeExcluded(p, "Base.Branch_Broken", true)
    AWS.setTypeExcluded(p, "Missing.Weapon", true)
    local rows = AWS.exclusionRows(p)
    assert(#rows == 3 and rows[1].name == "Axe" and rows[1].texture == "texture:Base.Axe")
    assert(rows[3].name == "Missing.Weapon" and rows[3].texture == nil)
end)
check("row crosses remove their item; releasing outside cancels", function()
    AWS.toggleExclusions(p)
    local w = AWS.exclusionsWindow
    assert(w.inUI and #w.list.items == 3 and not w.search and not w.removeButton)
    local list = w.list
    local x = list.width - (list:isVScrollBarVisible() and 16 or 0) - 2 - list.deleteSize / 2
    local y = list.itemheight * 2.5
    list:onMouseDown(x, y); list:onMouseUpOutside(x, y)
    list:onMouseUp(x, y); assert(#list.items == 3)
    list:onMouseDown(x, y); list:onMouseUp(x, y)
    assert(#list.items == 2 and not AWS.settings(p).types['Missing.Weapon'])
    list:onMouseDown(12, list.itemheight / 2); list:onMouseUp(12, list.itemheight / 2)
    assert(#list.items == 2)
    AWS.setTypeExcluded(p, "Base.Axe", false); w:prerender()
    assert(#list.items == 1)
    AWS.toggleExclusions(p); assert(not w.inUI and not w:isVisible())
    AWS.toggleExclusions(p); assert(AWS.exclusionsWindow.inUI)
end)
check("scrolling targets correct row and preserves offset after deletion", function()
    for i = 1, 40 do AWS.setTypeExcluded(p, "Test.Weapon" .. i, true) end
    local w = AWS.exclusionsWindow; w:refresh(); local list = w.list
    list:setYScroll(-400)
    local x = list.width - (list:isVScrollBarVisible() and 16 or 0) - 2 - list.deleteSize / 2
    local y = list.itemheight * 12.5
    local key = list.items[13].item.fullType
    list:onMouseDown(x, y); list:onMouseUp(x, y)
    assert(not AWS.settings(p).types[key] and list:getYScroll() == -400)
    local countBefore = #list.items
    list:onMouseDown(x, 10); list:onMouseUp(x, 10)
    assert(#list.items == countBefore) -- offscreen content cannot be clicked
    list:onMouseDown(list.width - 2, y); list:onMouseUp(list.width - 2, y)
    assert(#list.items == countBefore) -- scrollbar is not a delete target
end)
check("close-button width follows translated label; names fit before delete control", function()
    local original = getText
    function getText(key) if key == "UI_AWS_Close" then return string.rep("Wide", 9) end; return original(key) end
    local w = AWS.ExclusionsWindow:new(p); w:initialise(); w:addToUIManager()
    assert(w.bottomClose.width == #getText("UI_AWS_Close") * 8 + 32)
    assert(w.bottomClose.x >= 12 and w.bottomClose.x + w.bottomClose.width <= w.width - 12)
    scriptItems['Test.Long'] = string.rep("Long weapon name ", 30)
    AWS.setTypeExcluded(p, "Test.Long", true); w:refresh()
    for _, row in ipairs(w.list.items) do
        if row.item.fullType == 'Test.Long' then
            assert(row.item.label:sub(-3) == '...' and #row.item.label < #row.item.name)
        end
    end
    w:close(); getText = original
end)
check("window closes on player death", function()
    p.dead = true; AWS.exclusionsWindow:prerender()
    assert(not AWS.exclusionsWindow.inUI); p.dead = false
end)

check("native resize enforces minimum dimensions and retains footer spacing", function()
    local file = assert(io.open(GAME_LUA_ROOT .. "/client/ISUI/ISResizeWidget.lua", "r"))
    local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
    ISResizeWidget = {}
    assert(loadstring(assert(source:match("(function ISResizeWidget:resize%([^\n]*.-)\nfunction ISResizeWidget:onMouseMove"))))()
    local w = AWS.ExclusionsWindow:new(p); w:initialise(); w:addToUIManager()
    local width, height = w.width, w.height
    assert(w.resizable and w.minimumWidth == width and w.minimumHeight == height)
    local function label()
        for _, row in ipairs(w.list.items) do if row.item.fullType == 'Test.Long' then return row.item.label end end
    end
    local initialLabel = label()
    local widget = {target = w}
    ISResizeWidget.resize(widget, 200, 80)
    assert(w.width == width + 200 and w.height == height + 80)
    assert(w.list.width == w.width - 24)
    assert(w.list.height == w.height - w.list.y - w.buttonH - w:resizeWidgetHeight() - 24)
    assert(w.bottomClose.x == (w.width - w.closeWidth) / 2)
    assert(w.bottomClose.y == w.height - w.buttonH - w:resizeWidgetHeight() - 12)
    assert(#label() > #initialLabel and label():sub(-3) == '...')
    ISResizeWidget.resize(widget, -360, -160)
    assert(w.width == width and w.height == height)
    assert(label() == initialLabel)
    assert(w.height - w:resizeWidgetHeight() - (w.bottomClose.y + w.buttonH) == 12)
    local list = w.list
    local x = list.width - (list:isVScrollBarVisible() and 16 or 0) - 2 - list.deleteSize / 2
    local key = list.items[1].item.fullType
    list:setYScroll(0)
    list:onMouseDown(x, list.itemheight / 2); list:onMouseUp(x, list.itemheight / 2)
    assert(not AWS.settings(p).types[key])
    w:close()
end)
print(tostring(count) .. " interface scenarios passed")
