AuthenticZBalloonLift = AuthenticZBalloonLift or {}

local AZBL = AuthenticZBalloonLift

AZBL.DEFAULT_LIFT_PER_FACTOR = 1.0
AZBL.BALLOON_LOCATIONS = {
    "Schoolbag Balloon Right",
    "Dufflebag Balloon Left",
}

local BASE_KEY = "AZBL_BaseWeightReduction"
local APPLIED_KEY = "AZBL_AppliedWeightReduction"
local stateByPlayer = {}

-- Public type-level compatibility registry. Other mods may populate this table
-- even before this file loads, or call registerBalloonFactor after it loads.
AZBL.BalloonFactors = AZBL.BalloonFactors or {}

-- Built-in compatibility factors.
local BUILT_IN_BALLOON_FACTORS = {
    ["AuthenticZClothing.AuthenticBalloonGroup_Red"] = 3,
    ["AuthenticZClothing.AuthenticBalloonGroup_Blue"] = 3,
    ["AuthenticZClothing.AuthenticBalloonGroup_Green"] = 3,
    ["AuthenticZClothing.AuthenticBalloon_Group_Yellow"] = 3,
    ["AuthenticZClothing.AuthenticBalloonGroup_Pink"] = 3,
    ["AuthenticZClothing.AuthenticBalloonGroup_Purple"] = 3,
    ["AuthenticZClothing.AuthenticBalloonGroup_White"] = 3,
    ["AuthenticZClothing.AuthenticBalloonGroup_Teal"] = 3,

    ["AuthenticZBackpacksPlus.AuthenticBalloonGroup_Red"] = 3,
    ["AuthenticZBackpacksPlus.AuthenticBalloonGroup_Blue"] = 3,
    ["AuthenticZBackpacksPlus.AuthenticBalloonGroup_Green"] = 3,
    ["AuthenticZBackpacksPlus.AuthenticBalloon_Group_Yellow"] = 3,
    ["AuthenticZBackpacksPlus.AuthenticBalloonGroup_Pink"] = 3,
    ["AuthenticZBackpacksPlus.AuthenticBalloonGroup_Purple"] = 3,
    ["AuthenticZBackpacksPlus.AuthenticBalloonGroup_White"] = 3,
    ["AuthenticZBackpacksPlus.AuthenticBalloonGroup_Teal"] = 3,

    ["Balloon.Balloon_KL"] = 1.0,
    ["Balloon.Balloon_YSQQ"] = 2.0,
    ["Balloon.Balloon_QQS"] = 3.2,
    ["Balloon.Balloon_GGGG"] = 2.3,
    ["Balloon.Balloon_GGGG1"] = 1.5,
    ["Balloon.Balloon_MEIYA"] = 1.3,
    ["Balloon.Balloon_DUODUO"] = 1.4,
    ["Balloon.Balloon_HAIBAO"] = 1.6,
    ["Balloon.Balloon_AIYIN2"] = 1.0,
    ["Balloon.Balloon_AIYIN1"] = 1.9,
    ["Balloon.Balloon_DORO"] = 0.7,
    ["Balloon.Balloon_FBQB"] = 1.2,
    ["Balloon.Balloon_SLBZ"] = 0.9,
    ["Balloon.Balloon_CJL"] = 1.7,
    ["Balloon.Balloon_BANMA"] = 2.0,
    ["Balloon.Balloon_NIU"] = 2.1,
    ["Balloon.Balloon_NIU1"] = 3.8,
    ["Balloon.Balloon_DORO1"] = 4.0,
    ["Balloon.Balloon_JI"] = 3.4,
    ["Balloon.Balloon_BAOZHI"] = 1.2,
    ["Balloon.Balloon_WSDE"] = 0.7,
}

for fullType, factor in pairs(BUILT_IN_BALLOON_FACTORS) do
    if AZBL.BalloonFactors[fullType] == nil then
        AZBL.BalloonFactors[fullType] = factor
    end
end

local function readFactor(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return math.max(0, value)
end

function AZBL.registerBalloonFactor(fullType, factor)
    factor = readFactor(factor)
    if type(fullType) ~= "string" or fullType == "" or factor == nil then return false end
    AZBL.BalloonFactors[fullType] = factor
    return true
end

local function getBalloonFactor(item)
    if not item then return 0 end

    -- Instance-level metadata has the highest priority. This lets an item vary
    -- by size or condition without requiring a separate item type.
    local data = item:getModData()
    local factor = data and readFactor(data.BalloonFactor)
    if factor ~= nil then return factor end

    local fullType = item:getFullType()
    factor = readFactor(AZBL.BalloonFactors[fullType])
    if factor ~= nil then return factor end

    return 1
end

local function isContainer(item)
    return item and instanceof(item, "InventoryContainer") and item:getItemContainer()
end

local function getLiftPerFactor()
    local options = SandboxVars and SandboxVars.AuthenticZBalloonLift
    local value = options and readFactor(options.LiftPerFactor)
    if value == nil then return AZBL.DEFAULT_LIFT_PER_FACTOR end
    return value
end

local function getBalloonUnits(playerObj)
    local units = 0
    for _, location in ipairs(AZBL.BALLOON_LOCATIONS) do
        units = units + getBalloonFactor(playerObj:getAttachedItem(location))
    end
    return units
end

local function invalidateWeight(containerItem)
    local inner = containerItem and containerItem:getItemContainer()
    local outer = containerItem and containerItem:getContainer()
    if inner then inner:setDrawDirty(true) end
    if outer then outer:setDrawDirty(true) end
    if ISInventoryPage then ISInventoryPage.renderDirty = true end
end

local function setReduction(containerItem, reduction)
    local container = containerItem:getItemContainer()
    if containerItem:getWeightReduction() == reduction and container:getWeightReduction() == reduction then
        return false
    end
    containerItem:setWeightReduction(reduction)
    container:setWeightReduction(reduction)
    if isClient and isClient() and containerItem.syncItemFields then
        containerItem:syncItemFields()
    end
    invalidateWeight(containerItem)
    return true
end

local function restoreContainer(containerItem)
    if not isContainer(containerItem) then return end
    local data = containerItem:getModData()
    local base = tonumber(data[BASE_KEY])
    if base == nil then return end
    setReduction(containerItem, base)
    data[BASE_KEY] = nil
    data[APPLIED_KEY] = nil
end

local function applyLift(containerItem, balloonUnits)
    local lift = getLiftPerFactor()
    if balloonUnits <= 0 or lift <= 0 then
        restoreContainer(containerItem)
        return false
    end

    local container = containerItem:getItemContainer()
    local data = containerItem:getModData()
    local base = tonumber(data[BASE_KEY])
    local applied = tonumber(data[APPLIED_KEY])
    if applied ~= nil then
        local current = containerItem:getWeightReduction()
        local containerCurrent = container:getWeightReduction()
        if current ~= applied then
            base = current
        elseif containerCurrent ~= applied then
            base = containerCurrent
        end
    end
    if base == nil then
        base = containerItem:getWeightReduction()
    end
    data[BASE_KEY] = base

    local contentsWeight = container:getContentsWeight()
    local desired = base
    if contentsWeight > 0 then
        local effectiveBase = contentsWeight * (1 - base / 100)
        local effectiveTarget = math.max(0, effectiveBase - balloonUnits * lift)
        desired = math.min(100, math.max(0,
            math.floor(100 * (1 - effectiveTarget / contentsWeight) + 0.5)))
    end

    setReduction(containerItem, desired)
    data[APPLIED_KEY] = desired
    return true
end

local function reconcile(playerObj)
    if not playerObj then return end
    if isClient and isClient() and not playerObj:isLocalPlayer() then return end

    local state = stateByPlayer[playerObj]
    if not state then
        state = { ticks = 0, backpack = nil }
        stateByPlayer[playerObj] = state
    end

    state.ticks = state.ticks + 1
    if state.ticks < 20 then return end
    state.ticks = 0

    local backpack = playerObj:getWornItem(ItemBodyLocation.BACK)
    if not isContainer(backpack) then backpack = nil end

    if state.backpack and state.backpack ~= backpack then
        restoreContainer(state.backpack)
    end

    if backpack and applyLift(backpack, getBalloonUnits(playerObj)) then
        state.backpack = backpack
    else
        state.backpack = nil
    end
end

Events.OnPlayerUpdate.Add(reconcile)

return AZBL
