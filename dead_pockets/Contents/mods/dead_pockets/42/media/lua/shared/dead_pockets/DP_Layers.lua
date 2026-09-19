local DP = require("dead_pockets/DP_Pockets")

-- Body-part coverage is useful for modded clothes, but vanilla underwear has
-- no BloodClothingType at all. These coarse channels describe the actual
-- dressing layers and deliberately ignore small geometric differences between
-- garments (for example boxers and jeans both occupy the lower-body chain).
local LOCATION_CHANNELS = {
    underwearbottom = { "lower" },
    underweartop = { "upper" },
    underwear = { "upper", "lower" },
    underwearextra1 = { "lower" },
    underwearextra2 = { "lower" },
    torso1 = { "upper" },
    torso1legs1 = { "upper", "lower" },
    tanktop = { "upper" },
    tshirt = { "upper" },
    shortsleeveshirt = { "upper" },
    shirt = { "upper" },
    socks = { "feet" },
    legs1 = { "lower" },
    shoes = { "feet" },
    shortsshort = { "lower" },
    shortpants = { "lower" },
    pantsskinny = { "lower" },
    pants = { "lower" },
    skirt = { "lower" },
    dress = { "upper", "lower" },
    longskirt = { "lower" },
    longdress = { "upper", "lower" },
    vesttexture = { "upper" },
    bodycostume = { "upper", "lower" },
    sportshoulderpad = { "upper" },
    jersey = { "upper" },
    sweater = { "upper" },
    sweaterhat = { "upper" },
    pantsextra = { "upper", "lower" },
    jacket = { "upper" },
    jacketdown = { "upper" },
    jacketbulky = { "upper" },
    jackethat = { "upper" },
    jackethatbulky = { "upper" },
    jacketsuit = { "upper" },
    fullsuit = { "upper", "lower" },
    boilersuit = { "upper", "lower" },
    fullsuithead = { "upper", "lower", "feet" },
    fullsuitheadscba = { "upper", "lower", "feet" },
    fulltop = { "upper" },
    bathrobe = { "upper", "lower" },
    torsoextra = { "upper" },
    torsoextravest = { "upper" },
    torsoextravestbullet = { "upper" },
    cuirass = { "upper" },
    fullrobe = { "upper", "lower" },
}

local function getLayerChannels(location)
    if not location then return nil end

    local key = string.lower(tostring(location))
    key = string.gsub(key, "^.*:", "")
    key = string.gsub(key, "[^%w]", "")
    return LOCATION_CHANNELS[key]
end

function DP.isAffectedCorpse(body)
    if not body or not instanceof(body, "IsoDeadBody") then return false end
    if body:isAnimal() then return false end
    return true
end

local function getCoveredPartKeys(item)
    local keys = {}
    local count = 0

    if not item or not instanceof(item, "Clothing") then
        return keys, count
    end

    local parts = item:getCoveredParts()
    if not parts then return keys, count end

    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        if part then
            local key = tostring(part)
            if not keys[key] then
                keys[key] = true
                count = count + 1
            end
        end
    end

    return keys, count
end

local function isHiddenByOuterModel(group, outerLocations, location)
    if not group or not location then return false end

    for index = 1, #outerLocations do
        local outerLocation = outerLocations[index]
        if group:isHideModel(outerLocation, location) then return true end
    end

    return false
end

-- WornItems are kept in render order (inner to outer) by the game. Walking the
-- collection backwards lets every outer garment claim the body parts it covers.
-- An inner garment is concealed when all of its covered parts are already
-- claimed, or when the game's own BodyLocation rules hide its model.
function DP.collectHiddenItems(body)
    local hidden = {}
    if not DP.isAffectedCorpse(body) then return hidden end

    local wornItems = body:getWornItems()
    if not wornItems or wornItems:isEmpty() then return hidden end

    local group = wornItems:getBodyLocationGroup()
    local claimedParts = {}
    local claimedChannels = {}
    local outerLocations = {}

    for index = wornItems:size() - 1, 0, -1 do
        local wornItem = wornItems:get(index)
        local item = wornItem and wornItem:getItem() or nil
        local location = wornItem and wornItem:getLocation() or nil

        -- Holsters use several vanilla body locations (BeltExtra,
        -- ShoulderHolster and AnkleHolster), and the shoulder holster is an
        -- InventoryContainer rather than Clothing. Detect the item as well as
        -- the slot before entering the normal clothing-only layer logic.
        if item and DP.isHolsterItem(item) and
                DP.isHolsterConcealed(body, location, item) then
            hidden[item] = true
        end

        if item and instanceof(item, "Clothing") then
            local partKeys, partCount = getCoveredPartKeys(item)
            local allPartsCovered = partCount > 0
            local channels = getLayerChannels(location)
            local allChannelsCovered = channels ~= nil and #channels > 0

            if allPartsCovered then
                for key in pairs(partKeys) do
                    if not claimedParts[key] then
                        allPartsCovered = false
                        break
                    end
                end
            end

            if allChannelsCovered then
                for channelIndex = 1, #channels do
                    if not claimedChannels[channels[channelIndex]] then
                        allChannelsCovered = false
                        break
                    end
                end
            end

            if allChannelsCovered or allPartsCovered or
                    isHiddenByOuterModel(group, outerLocations, location) then
                hidden[item] = true
            end

            for key in pairs(partKeys) do
                claimedParts[key] = true
            end

            if channels then
                for channelIndex = 1, #channels do
                    claimedChannels[channels[channelIndex]] = true
                end
            end

        end

        if location then
            outerLocations[#outerLocations + 1] = location
        end
    end

    DP.addHiddenPocketItems(body, hidden)

    return hidden
end

local function getSourceCorpse(item)
    if not item then return nil end

    local container = item:getContainer()
    local parent = container and container:getParent() or nil
    if DP.isAffectedCorpse(parent) then return parent end
    return nil
end

function DP.isItemConcealed(item, cache)
    local body = getSourceCorpse(item)
    if not body then return false end

    cache = cache or {}
    local hidden = cache[body]
    if not hidden then
        hidden = DP.collectHiddenItems(body)
        cache[body] = hidden
    end

    return hidden[item] == true
end

return DP
