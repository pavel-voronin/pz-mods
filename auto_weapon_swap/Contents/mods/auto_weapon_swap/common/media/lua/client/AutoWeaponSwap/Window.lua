require "AutoWeaponSwap/Core"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"

local AWS = AutoWeaponSwap
AWS.ExclusionsWindow = ISCollapsableWindow:derive("AWSExclusionsWindow")
local Window = AWS.ExclusionsWindow

function AWS.exclusionRows(player)
    local rows = {}
    for fullType, excluded in pairs(AWS.settings(player).types) do
        if excluded then
            local script = getScriptManager():FindItem(fullType)
            rows[#rows + 1] = { fullType = fullType,
                name = script and script:getDisplayName() or fullType,
                texture = script and getItemTex(fullType) or nil }
        end
    end
    table.sort(rows, function(a, b)
        if a.name == b.name then return a.fullType < b.fullType end
        return a.name < b.name
    end)
    return rows
end

local function deleteX(list)
    local scrollbarWidth = list:isVScrollBarVisible() and list.vscroll:getWidth() or 0
    return list.width - scrollbarWidth - list.deleteSize - 2
end

-- Kahlua indexes Java characters, not UTF-8 bytes
local function fitName(name, width)
    local manager = getTextManager()
    if manager:MeasureStringX(UIFont.Small, name) <= width then return name end
    for length = #name - 1, 0, -1 do
        local shortened = name:sub(1, length) .. "..."
        if manager:MeasureStringX(UIFont.Small, shortened) <= width then return shortened end
    end
    return "..."
end

function Window:new(player)
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local buttonH = fontH + 12
    local closeWidth = math.max(80,
        getTextManager():MeasureStringX(UIFont.Small, getText("UI_AWS_Close")) + 32)
    local width = math.min(getCore():getScreenWidth() - 24, math.max(440, closeWidth + 24,
        getTextManager():MeasureStringX(UIFont.Small, getText("UI_AWS_Title")) + 100))
    local height = math.min(getCore():getScreenHeight() - 24, math.max(360, fontH * 18))
    local o = ISCollapsableWindow.new(self, (getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2, width, height)
    o.player = player
    o.fontH = fontH
    o.buttonH = buttonH
    o.closeWidth = closeWidth
    o.title = getText("UI_AWS_Title")
    o.resizable = true
    o.minimumWidth = width
    o.minimumHeight = height
    return o
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(true)
    local y = self:titleBarHeight() + 12
    local bottomInset = self:resizeWidgetHeight() + 12
    self.list = ISScrollingListBox:new(12, y, self.width - 24,
        math.max(0, self.height - y - self.buttonH - bottomInset - 12))
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = math.max(40, self.fontH + 20)
    self.list.iconSize = self.list.itemheight - 12
    self.list.deleteSize = self.buttonH
    self.list.deleteTexture = self.closeButtonTexture
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = Window.drawRow
    self.list.onMouseDown = Window.listMouseDown
    self.list.onMouseUp = Window.listMouseUp
    self.list.onMouseUpOutside = Window.listMouseUpOutside
    self.list.awsWindow = self
    self:addChild(self.list)
    self.bottomClose = ISButton:new((self.width - self.closeWidth) / 2,
        self.height - self.buttonH - bottomInset, self.closeWidth, self.buttonH,
        getText("UI_AWS_Close"), self, Window.close)
    self.bottomClose:initialise()
    self:addChild(self.bottomClose)
    self:refresh()
end

function Window:onResize()
    ISCollapsableWindow.onResize(self)
    if not self.list or not self.bottomClose then return end
    local bottomInset = self:resizeWidgetHeight() + 12
    self.list:setWidth(math.max(0, self.width - 24))
    self.list:setHeight(math.max(0, self.height - self.list.y - self.buttonH - bottomInset - 12))
    self.bottomClose:setX((self.width - self.closeWidth) / 2)
    self.bottomClose:setY(self.height - self.buttonH - bottomInset)
    self:refresh()
end

function Window.drawRow(list, y, row, alt)
    if alt then list:drawRect(0, y, list.width, list.itemheight, 0.06, 1, 1, 1) end
    local iconY = y + (list.itemheight - list.iconSize) / 2
    if row.item.texture then
        list:drawTextureScaledAspect(row.item.texture, 8, iconY, list.iconSize, list.iconSize, 1, 1, 1, 1)
    else
        list:drawTextCentre("?", 8 + list.iconSize / 2, iconY, 0.65, 0.65, 0.65, 1, UIFont.Small)
    end
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    list:drawText(row.item.label, list.iconSize + 18, y + (list.itemheight - fontH) / 2,
        1, 1, 1, 1, UIFont.Small)
    local x = deleteX(list)
    local buttonY = y + (list.itemheight - list.deleteSize) / 2
    local hover = list:isMouseOver() and list:getMouseX() >= x
        and list:getMouseX() < x + list.deleteSize
        and list:getMouseY() >= buttonY and list:getMouseY() < buttonY + list.deleteSize
    list:drawRect(x, buttonY, list.deleteSize, list.deleteSize, hover and 0.55 or 0.12, 0.65, 0.2, 0.2)
    if list.deleteTexture then
        list:drawTextureScaledAspect(list.deleteTexture, x + 6, buttonY + 6,
            list.deleteSize - 12, list.deleteSize - 12, 1, 1, 1, 1)
    else
        list:drawTextCentre("x", x + list.deleteSize / 2, y + (list.itemheight - fontH) / 2, 1, 1, 1, 1, UIFont.Small)
    end
    return y + list.itemheight
end

local function deleteRowAt(list, x, y)
    -- Mouse coordinates already include the scroll offset
    if y + list:getYScroll() < 0 or y + list:getYScroll() >= list.height then return nil end
    local left = deleteX(list)
    if x < left or x >= left + list.deleteSize then return nil end
    local index = list:rowAt(x, y)
    local row = list.items[index]
    if not row then return nil end
    local top = list:topOfItem(index) + (list.itemheight - list.deleteSize) / 2
    if y < top or y >= top + list.deleteSize then return nil end
    return row
end

function Window.listMouseDown(list, x, y)
    local row = deleteRowAt(list, x, y)
    list.pressedType = row and row.item.fullType or nil
    if row then return true end
    return ISScrollingListBox.onMouseDown(list, x, y)
end

function Window.listMouseUp(list, x, y)
    local row = deleteRowAt(list, x, y)
    local pressed = list.pressedType
    list.pressedType = nil
    ISScrollingListBox.onMouseUp(list, x, y)
    if row and row.item.fullType == pressed then
        getSoundManager():playUISound("UIActivateButton")
        AWS.setTypeExcluded(list.awsWindow.player, pressed, false)
        list.awsWindow:refresh()
        return true
    end
end

function Window.listMouseUpOutside(list, x, y)
    list.pressedType = nil
    ISScrollingListBox.onMouseUpOutside(list, x, y)
end

function Window:refresh()
    if not self.list then return end
    local scroll = self.list:getYScroll()
    self.list:clear()
    self.list.pressedType = nil
    for _, row in ipairs(AWS.exclusionRows(self.player)) do
        self.list:addItem(row.name, row)
    end
    local labelWidth = deleteX(self.list) - self.list.iconSize - 30
    for _, row in ipairs(self.list.items) do
        row.item.label = fitName(row.item.name, labelWidth)
    end
    self.list:setYScroll(math.max(math.min(0, self.list.height - #self.list.items * self.list.itemheight), math.min(0, scroll)))
    self.revision = AWS.exclusionsRevision or 0
end

function Window:prerender()
    if self.player:isDead() or self.player ~= getSpecificPlayer(self.player:getPlayerNum()) then
        self:close()
        return
    end
    if self.revision ~= (AWS.exclusionsRevision or 0) then self:refresh() end
    ISCollapsableWindow.prerender(self)
    if #self.list.items == 0 then
        self:drawTextCentre(getText("UI_AWS_Empty"), self.width / 2, self.list.y + 16,
            0.85, 0.85, 0.85, 1, UIFont.Small)
    end
end

function Window:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

function AWS.toggleExclusions(player)
    local window = AWS.exclusionsWindow
    if window and window.player == player and window:isVisible() then
        window:close()
        return
    end
    if window then window:close() end
    window = Window:new(player)
    AWS.exclusionsWindow = window
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
end
