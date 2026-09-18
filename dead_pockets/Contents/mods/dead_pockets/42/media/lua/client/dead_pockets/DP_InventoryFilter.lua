if isServer() then return end

require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"

local DP = require("dead_pockets/DP_Layers")

local function cloneVisibleEntry(entry, cache)
    if not entry or not entry.items or #entry.items == 0 then
        return entry, false
    end

    local items = entry.items
    local firstActualIndex = entry.cleanUILargeStackOptimized and 1 or
        ((#items > 1 and items[1] == items[2]) and 2 or 1)
    local visible = {}
    local changed = false

    for index = firstActualIndex, #items do
        local item = items[index]
        if item and instanceof(item, "InventoryItem") and DP.isItemConcealed(item, cache) then
            changed = true
        elseif item then
            visible[#visible + 1] = item
        end
    end

    if not changed then return entry, false end
    if #visible == 0 then return nil, true end

    local copy = {}
    for key, value in pairs(entry) do
        if key ~= "items" then copy[key] = value end
    end

    copy.items = { visible[1] }
    copy.weight = 0
    for index = 1, #visible do
        local item = visible[index]
        copy.items[#copy.items + 1] = item
        copy.weight = copy.weight + item:getUnequippedWeight()
    end
    copy.count = #copy.items

    -- CleanUI caches the representative item and supports stacks without a
    -- physical header. A filtered stack uses the ordinary duplicated header.
    if entry.cleanUIDisplayItem or entry.firstItem or entry.realCount then
        copy.firstItem = visible[1]
        copy.realCount = #visible
        copy.cleanUIDisplayItem = visible[1]
        copy.cleanUILargeStackOptimized = false
        copy.cleanUIFirstActualIndex = 2
        copy.cleanUIStackCountSuffix = " (" .. tostring(#visible) .. ")"
        copy.cleanUIWeightText = nil
        copy.cleanUIWeightKnown = true
        copy.cleanUITooltipWeightKnown = false
        copy.cleanUITooltipWeight = nil
    end

    return copy, true
end

local function buildFilteredList(itemslist)
    local cache = {}
    local filtered = {}
    local changed = false

    for index = 1, #itemslist do
        local entry, entryChanged = cloneVisibleEntry(itemslist[index], cache)
        if entry then filtered[#filtered + 1] = entry end
        if entryChanged then changed = true end
    end

    local revisions = {}
    for body in pairs(cache) do
        revisions[body] = DP.getPocketRevision(body)
    end
    return changed and filtered or itemslist, revisions
end

local function visibleItems(items)
    local visible = {}
    local cache = {}
    for index = 1, #items do
        local item = items[index]
        if item and not DP.isItemConcealed(item, cache) then
            visible[#visible + 1] = item
        end
    end
    return visible
end

local function installPane(paneClass)
    if not paneClass or rawget(paneClass, "_deadPocketsInstalled") then return end
    paneClass._deadPocketsInstalled = true

    -- Vanilla and both CleanUI panes finish building/sorting their rows before
    -- restoring selection. Filter at that boundary so every later consumer,
    -- including the first rendered frame, sees the same rows and row numbers.
    local originalRestoreSelection = paneClass.restoreSelection
    function paneClass:restoreSelection(selected)
        self.itemslist, self.deadPocketsRevisions = buildFilteredList(self.itemslist or {})
        self.deadPocketsFilteredFor = self.inventory

        self.itemindex = {}
        for _, entry in ipairs(self.itemslist) do
            if entry.name and entry.type ~= "separator" then
                self.itemindex[entry.name] = entry
            end
        end
        originalRestoreSelection(self, selected)
        -- Keep a selected stack represented by its row, so another refresh
        -- saves it as a group again rather than losing a collapsed selection.
        local row = 1
        for _, entry in ipairs(self.itemslist) do
            local item = entry.cleanUIDisplayItem or entry.firstItem or entry.items[1]
            if item and selected[item] == "group" and self.selected[row] then
                self.selected[row] = entry
            end
            row = row + 1
            if not self.collapsed[entry.name] then
                local startIndex = entry.cleanUILargeStackOptimized and 1 or 2
                row = row + math.max(0, #entry.items - startIndex + 1)
            end
        end
    end

    local originalRenderDetails = paneClass.renderdetails
    function paneClass:renderdetails(doDragged)
        local refresh = self.deadPocketsFilteredFor ~= self.inventory
        for body, revision in pairs(self.deadPocketsRevisions or {}) do
            if DP.getPocketRevision(body) ~= revision then
                refresh = true
                break
            end
        end
        if refresh then self:refreshContainer() end
        return originalRenderDetails(self, doDragged)
    end

    -- Loot All and aggregate-inventory mods often pass the physical container
    -- contents instead of the rows currently displayed. Filter that list at the
    -- common transfer entry point so a single click cannot strip hidden layers.
    local originalTransferItemsByWeight = paneClass.transferItemsByWeight
    function paneClass:transferItemsByWeight(items, destination)
        return originalTransferItemsByWeight(self, visibleItems(items), destination)
    end
end

local cleanUIToggleRegistered = false
local function install()
    installPane(ISInventoryPane)
    installPane(_G.CleanUI_Clean_ISInventoryPane)
    installPane(_G.CleanUI_Vanilla_ISInventoryPane)

    if not ISInventoryPaneContextMenu._deadPocketsDropInstalled then
        ISInventoryPaneContextMenu._deadPocketsDropInstalled = true
        local originalOnDropItems = ISInventoryPaneContextMenu.onDropItems
        function ISInventoryPaneContextMenu.onDropItems(items, player)
            return originalOnDropItems(visibleItems(ISInventoryPane.getActualItems(items or {})), player)
        end
    end

    -- CleanUI can create its alternate class lazily on the first live toggle.
    -- Existing windows inherit from these classes, so patching also covers the
    -- windows that its earlier callback has just constructed.
    if not cleanUIToggleRegistered and type(CleanUI_RegisterInventoryUiToggleCallback) == "function" then
        cleanUIToggleRegistered = true
        CleanUI_RegisterInventoryUiToggleCallback(install)
    end
end

Events.OnGameStart.Add(install)
