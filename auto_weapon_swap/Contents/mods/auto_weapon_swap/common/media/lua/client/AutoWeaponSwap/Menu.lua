require "AutoWeaponSwap/Core"
require "ISUI/ISInventoryPage"

local AWS = AutoWeaponSwap

function AWS.containerOption(player, context, container)
    if not container or container:getType() == "floor" then return end
    for _, option in ipairs(context.options) do
        if option.awsContainer == container then return end
    end
    local option = context:addOption(getText("ContextMenu_AWS_UseContainer"), player, AWS.toggleContainer, container)
    option.awsContainer = container
    context:setOptionChecked(option, AWS.containerChecked(player, container))
end

local function setSelectedTypes(player, selection)
    for _, fullType in ipairs(selection.types) do
        AWS.setTypeExcluded(player, fullType, selection.exclude)
    end
end

local function inventoryMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    local actual = ISInventoryPane.getActualItems(items)
    local types, seen = {}, {}
    local allExcluded = true
    local data = AWS.settings(player)
    for _, item in ipairs(actual) do
        if instanceof(item, "InventoryContainer") then
            AWS.containerOption(player, context, item:getInventory())
        end
        if AWS.isWeapon(item) then
            local fullType = item:getFullType()
            if not seen[fullType] then
                seen[fullType] = true
                types[#types + 1] = fullType
                if data.types[fullType] ~= true then allExcluded = false end
            end
        end
    end
    if #types > 0 then
        local label = allExcluded and "ContextMenu_AWS_AllowType" or "ContextMenu_AWS_ExcludeType"
        if #types > 1 then label = label .. "s" end
        -- Keep the action shown when the menu opened
        local selection = {types = types, exclude = not allExcluded}
        local option = context:addOption(getText(label), player, setSelectedTypes, selection)
        context:setOptionChecked(option, allExcluded)
    end
end

local function emptyMenu(playerNum, context, isLoot)
    local page = isLoot and getPlayerLoot(playerNum) or getPlayerInventory(playerNum)
    if page then AWS.containerOption(getSpecificPlayer(playerNum), context, page.inventoryPane.inventory) end
end

local function worldMenu(playerNum, context, objects, test)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    local accessible = AWS.containers(player, true)
    local seen = {}
    for _, object in ipairs(objects) do
        for _, container in ipairs(accessible) do
            local bag = container:getContainingItem()
            if not seen[container] and (container:getParent() == object
                or (bag and bag:getWorldItem() == object)) then
                if test then ISWorldObjectContextMenu.Test = true; return true end
                seen[container] = true
                local label = bag and bag:getName() or container:getCustomName()
                    or getText("IGUI_ContainerTitle_" .. container:getType())
                local option = context:addOption(label, nil, nil)
                local sub = ISContextMenu:getNew(context)
                context:addSubMenu(option, sub)
                AWS.containerOption(player, sub, container)
            end
        end
    end
end

-- Container tabs have no menu event, extend the existing handler
local original = ISInventoryPage.onBackpackRightMouseDown
function ISInventoryPage:onBackpackRightMouseDown(x, y)
    local result = original(self, x, y)
    local page = self.parent.parent
    AWS.containerOption(getSpecificPlayer(page.player), getPlayerContextMenu(page.player), self.inventory)
    return result
end

Events.OnFillInventoryObjectContextMenu.Add(inventoryMenu)
-- The game fires this event without registering it
LuaEventManager.AddEvent("OnFillInventoryContextMenuNoItems")
Events.OnFillInventoryContextMenuNoItems.Add(emptyMenu)
Events.OnFillWorldObjectContextMenu.Add(worldMenu)
