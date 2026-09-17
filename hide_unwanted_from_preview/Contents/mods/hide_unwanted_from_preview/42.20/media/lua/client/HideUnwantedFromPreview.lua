require "ISUI/ISToolTipInv"

-- Load the optional library before capturing its renderer, irrespective of
-- alphabetical Lua loading order. Standalone installations need no library
local starlitUI
if getActivatedMods():contains("StarlitLibrary") then
    starlitUI = require "Starlit/client/ui/InventoryUI"
end
local originalRender = ISToolTipInv.render

local function drawItemDetails(item, tooltip)
    if not starlitUI then
        item:DoTooltipEmbedded(tooltip, nil, 0)
        return
    end
    -- Preserve Starlit 2.1's extension event, including modifications to the
    -- existing layout. This path only handles InventoryContainer, not Food
    local layout = tooltip:beginLayout()
    layout:setMinLabelWidth(80)
    layout:setMinValueWidth(80)
    item:DoTooltipEmbedded(tooltip, layout, 0)
    starlitUI.onFillItemTooltip:trigger(tooltip, layout, item)
    local padding = getTextManager():MeasureStringX(tooltip:getFont(), "0")
    local offset = tooltip:getLineSpacing() + 5
    local extra = item:getExtraItems()
    if extra then offset = offset * (1 + extra:size()) end
    local height = layout:render(padding, offset, tooltip)
    tooltip:endLayout(layout)
    tooltip:setHeight(height + math.floor(padding / 2))
end

-- Keep the real container intact, including while measuring the tooltip.
-- DoTooltipEmbedded renders the ordinary item information and dispatches the
-- container's layout overload, but does not append the vanilla icon row
local function drawFilteredTooltip(item, tooltip, icons, player)
    drawItemDetails(item, tooltip)
    tooltip:setWidth(math.max(160, tooltip:getWidth()))

    local font = tooltip:getFont()
    -- ObjectTooltip.checkFont uses the width of "0" for horizontal padding.
    -- Calculate it through the public API instead of accessing Java fields
    local padding = getTextManager():MeasureStringX(font, "0")
    local bottom = math.floor(padding / 2)
    local size = math.max(16, getTextManager():getFontHeight(font))
    if not icons then
        icons = {}
        local names = {}
        local items = item:getItemContainer():getItems()
        local nextX = padding
        -- Only collect the row that fits the measured tooltip. Never cache
        -- across frames: contents and unwanted preferences may change
        for i = items:size() - 1, 0, -1 do
            local contained = items:get(i)
            if not contained:isUnwanted(player) then
                local name = contained:getName()
                if name == nil or not names[name] then
                    icons[#icons + 1] = contained
                    if name ~= nil then names[name] = true end
                    nextX = nextX + size + 1
                    if nextX + size > tooltip:getWidth() - padding then break end
                end
            end
        end
    end
    if #icons == 0 then return icons end
    local x = padding
    local y = tooltip:getHeight() - bottom + 4
    if not tooltip:isMeasureOnly() then
        for _, icon in ipairs(icons) do
            tooltip:DrawTextureScaledAspect(icon:getTex(), x, y, size, size, 1, 1, 1, 1)
            x = x + size + 1
            if x + size > tooltip:getWidth() - padding then break end
        end
    end
    tooltip:setHeight(y + size + bottom)
    return icons
end

-- Positioning follows ISToolTipInv in 42.20.4, including controller menus and
-- screen-edge clamping. The measurement also selects the row in one pass
local function renderFiltered(self, player)
    local mx, my = getMouseX() + 24, getMouseY() + 24
    if not self.followMouse then
        mx, my = self:getX(), self:getY()
        if self.anchorBottomLeft then
            mx, my = self.anchorBottomLeft.x, self.anchorBottomLeft.y
        end
    end

    local tooltip = self.tooltip
    tooltip:setX(mx)
    tooltip:setY(my)
    tooltip:setWidth(50)
    tooltip:setMeasureOnly(true)
    local icons = drawFilteredTooltip(self.item, tooltip, nil, player)
    tooltip:setMeasureOnly(false)
    -- Reuse the measured row even when every item is wanted. Calling the
    -- original renderer here would rebuild details and trigger Starlit a
    -- third time. The same two-pass layout handles either case

    local core = getCore()
    local maxX, maxY = core:getScreenWidth(), core:getScreenHeight()
    local tw, th = tooltip:getWidth(), tooltip:getHeight()
    tooltip:setX(math.max(0, math.min(mx, maxX - tw - 1)))
    local top = my
    if not self.followMouse and self.anchorBottomLeft then top = my - th end
    tooltip:setY(math.max(0, math.min(top, maxY - th - 1)))

    if self.contextMenu and self.contextMenu.joyfocus then
        local playerNum = self.contextMenu.player
        tooltip:setX(getPlayerScreenLeft(playerNum) + 60)
        tooltip:setY(getPlayerScreenTop(playerNum) + 60)
    elseif self.contextMenu and self.contextMenu.currentOptionRect then
        if self.contextMenu.currentOptionRect.height > 32 then
            self:setY(my + self.contextMenu.currentOptionRect.height)
        end
        self:adjustPositionToAvoidOverlap(self.contextMenu.currentOptionRect)
    end

    self:setX(tooltip:getX())
    self:setY(tooltip:getY())
    self:setWidth(tw)
    self:setHeight(th)
    if self.followMouse and not self.contextMenu then
        self:adjustPositionToAvoidOverlap({x = mx - 48, y = my - 48, width = 48, height = 48})
    end

    local bg, border = self.backgroundColor, self.borderColor
    self:drawRect(0, 0, self.width, self.height, bg.a, bg.r, bg.g, bg.b)
    self:drawRectBorder(0, 0, self.width, self.height, border.a, border.r, border.g, border.b)
    drawFilteredTooltip(self.item, tooltip, icons)
end

function ISToolTipInv:render()
    if ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
    local item = self.item
    local player = self.tooltip:getCharacter()
    if not item or not instanceof(item, "InventoryContainer")
        or not player or not instanceof(player, "IsoPlayer") then
        return originalRender(self)
    end

    if item:getItemContainer():getItems():isEmpty() then return originalRender(self) end
    return renderFiltered(self, player)
end
