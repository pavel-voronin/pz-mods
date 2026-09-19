DeadPockets = DeadPockets or {}

local DP = DeadPockets

local CARRIER_ID_KEY = "DeadPocketsPocketCarrierId"
local CORPSE_POCKETS_KEY = "DeadPocketsCarriers"
local CORPSE_REVISION_KEY = "DeadPocketsRevision"

local LOWER_LOCATIONS = {
    legs1 = true, shortsshort = true, shortpants = true, pantsskinny = true,
    pants = true,
}

local SKIRT_LOCATIONS = {
    skirt = true, longskirt = true,
}

local SHIRT_LOCATIONS = {
    torso1 = true, shortsleeveshirt = true, shirt = true,
}

local OUTER_LOCATIONS = {
    vesttexture = true,
    jacket = true, jacketdown = true, jacketbulky = true, jackethat = true,
    jackethatbulky = true, jacketsuit = true, fulltop = true,
    bathrobe = true, torsoextravest = true,
    torsoextravestbullet = true,
}

local APRON_LOCATIONS = {
    torsoextra = true,
}

local DRESS_LOCATIONS = {
    dress = true, longdress = true,
}

local BRA_LOCATIONS = {
    underweartop = true,
}

local UNDERWEAR_LOCATIONS = {
    underwearbottom = true, underwear = true,
    underwearextra1 = true, underwearextra2 = true,
}

local function normalize(value)
    local key = string.lower(tostring(value or ""))
    key = string.gsub(key, "^.*:", "")
    return string.gsub(key, "[^%w]", "")
end

local function typeKey(item)
    local key = string.lower(tostring(item and item:getFullType() or ""))
    key = string.gsub(key, "^.*[%.:]", "")
    return string.gsub(key, "[^%w]", "")
end

local function inSet(value, values)
    return values[value] == true
end

local function hasPrefix(value, prefixes)
    for index = 1, #prefixes do
        if string.sub(value, 1, #prefixes[index]) == prefixes[index] then
            return true
        end
    end
    return false
end

local function itemId(item)
    return item and tostring(item:getID()) or nil
end

local function carrierKind(location, item)
    local name = typeKey(item)
    -- Coverage is not a pocket type: long johns, wedding dresses and mascot
    -- suits can occupy the same full-body slots as real work clothes.
    if string.find(name, "longjohn", 1, true) then return nil end
    if item:hasTag(ItemTag.LONG_JOHNS) then
        return nil
    end
    if string.find(name, "coverall", 1, true) or
            string.find(name, "boilersuit", 1, true) or
            string.find(name, "overall", 1, true) or
            string.find(name, "dungarees", 1, true) or
            string.find(name, "workrobe", 1, true) then
        return "workwear"
    end
    local key = normalize(location)
    if BRA_LOCATIONS[key] then return "bra" end
    if UNDERWEAR_LOCATIONS[key] then return "underwear" end
    if SKIRT_LOCATIONS[key] then return "skirt" end
    if LOWER_LOCATIONS[key] then return "lower" end
    if SHIRT_LOCATIONS[key] then return "shirt" end
    if APRON_LOCATIONS[key] then return "apron" end
    if OUTER_LOCATIONS[key] then return "outer" end
    if DRESS_LOCATIONS[key] then return "dress" end

    -- Body-location names are moddable. Fall back to names only when the item
    -- is clothing, so unrelated equipment never becomes a virtual pocket.
    if string.find(name, "bra") or string.find(name, "brassiere") then
        return "bra"
    end
    if string.find(name, "underwear") or string.find(name, "boxer") or
            string.find(name, "brief") or string.find(name, "panties") then
        return "underwear"
    end
    if string.find(name, "sweater") then return nil end
    if string.find(name, "tshirt") or string.find(name, "bandeau") or
            string.find(name, "jersey") then return nil end
    if string.find(name, "apron") then return "apron" end
    if string.find(name, "jacket") or string.find(name, "coat") or
            string.find(name, "hoodie") or string.find(name, "vest") then
        return "outer"
    end
    if string.find(name, "pants") or string.find(name, "trouser") or
            string.find(name, "jeans") or string.find(name, "shorts") then
        return "lower"
    end
    if string.find(name, "skirt") then return "skirt" end
    if string.find(name, "dress") then return "dress" end
    if string.find(name, "shirt") then return "shirt" end
    return nil
end

local function collectProtectedItems(body)
    local protected = {}
    local wornItems = body:getWornItems()
    if wornItems then
        for index = 0, wornItems:size() - 1 do
            local worn = wornItems:get(index)
            local item = worn and worn:getItem() or nil
            if item then protected[item] = true end
        end
    end

    local attachedItems = body:getAttachedItems()
    if attachedItems then
        for index = 0, attachedItems:size() - 1 do
            local attached = attachedItems:get(index)
            local item = attached and attached:getItem() or nil
            if item then protected[item] = true end
        end
    end

    local primary = body:getPrimaryHandItem()
    local secondary = body:getSecondaryHandItem()
    if primary then protected[primary] = true end
    if secondary then protected[secondary] = true end
    return protected
end

local function collectCarriers(body)
    local carriers = {}
    local wornItems = body:getWornItems()
    if not wornItems then return carriers end

    for index = 0, wornItems:size() - 1 do
        local worn = wornItems:get(index)
        local item = worn and worn:getItem() or nil
        local location = worn and worn:getLocation() or nil
        if item and instanceof(item, "Clothing") then
            local kind = carrierKind(location, item)
            if kind then
                carriers[#carriers + 1] = {
                    item = item,
                    id = itemId(item),
                    kind = kind,
                }
            end
        end
    end
    return carriers
end

local PERSONAL_TYPES = {
    creditcard = true, idcard = true, idcardfemale = true, idcardmale = true,
    letterhandwritten = true, locket = true, money = true, moneybundle = true,
    passport = true, photo = true, photohass = true, postcard = true,
    receipt = true, scratchticket = true, scratchticketwinner = true,
    walletfemale = true, walletmale = true,
}

local SMOKING_TYPES = {
    cigar = true, cigarettepack = true, cigaretterolled = true,
    cigaretterollingpapers = true, cigarillo = true, lighter = true,
    lighterdisposable = true, matches = true, smokingpipe = true,
    tobaccochewing = true, tobaccoloose = true,
}

local PAPER_TYPES = {
    bluepen = true, diary1 = true, diary2 = true, graphpaper = true,
    magazine = true, marchridgemap = true, muldraughmap = true,
    newspaperrecent = true, note = true, notebook = true, notepad = true,
    paperwork = true, pen = true, penfancy = true, pencil = true,
    redpen = true, riversidemap = true, rosewoodmap = true,
    westpointmap = true,
}

local function itemCategory(item)
    local key = typeKey(item)
    if inSet(key, PERSONAL_TYPES) then return "personal" end
    if inSet(key, SMOKING_TYPES) then return "smoking" end
    if inSet(key, PAPER_TYPES) or
            hasPrefix(key, { "louisvillemap", "magazine", "paperback" }) then
        return "paper"
    end
    -- Pens are HandWeapon instances in Project Zomboid, so exact semantic
    -- exceptions must be checked first. Everything else uses the runtime class.
    if instanceof(item, "HandWeapon") then return "weapon" end
    return "general"
end

local WEIGHTS = {
    personal      = { lower = 60, skirt = 60, outer = 28, shirt = 12, apron = 28, dress = 50, workwear = 70 },
    smoking       = { lower = 38, skirt = 38, outer = 50, shirt = 12, apron = 50, dress = 42, workwear = 65 },
    paper         = { lower = 28, skirt = 28, outer = 40, shirt = 32, apron = 40, dress = 38, workwear = 60 },
    weaponPocket  = { lower = 38, skirt = 38, outer = 62, shirt = 0,  apron = 62, dress = 0,  workwear = 75 },
    weaponCompact = { lower = 0,  skirt = 0,  outer = 62, shirt = 0,  apron = 0,  dress = 0,  workwear = 75 },
    general       = { lower = 42, skirt = 42, outer = 43, shirt = 15, apron = 43, dress = 45, workwear = 70 },
}

local function stableRoll(item, salt, limit)
    local source = itemId(item) .. ":" .. salt
    local hash = 17
    for index = 1, #source do
        hash = (hash * 131 + string.byte(source, index)) % 2147483647
    end
    return hash % limit
end

local function itemWeight(item)
    -- Pocket fit uses the whole unequipped item, including fluids/ammunition
    -- and bag contents. A worn bag's encumbrance reduction does not make it fit.
    return item:getUnequippedWeight()
end

local function weaponSize(item)
    local key = typeKey(item)
    local weight = itemWeight(item)
    if weight > 1.5 then return "large" end

    local largeTypes = {
        baseballbat = true, crowbar = true, katana = true, machete = true,
        pickaxe = true, plank = true, shovel = true, sledgehammer = true,
        woodaxe = true,
    }
    if inSet(key, largeTypes) or
            hasPrefix(key, { "rifle", "shotgun", "spear", "sword" }) then
        return "large"
    end

    if item:isTwoHandWeapon() then return "large" end

    local pocketTypes = {
        glassshiv = true, handiknife = true, icepick = true,
        knifebutterfly = true, knifepocket = true, knifeshiv = true,
        screwdriver = true, smallknife = true, steakknife = true,
        switchknife = true,
    }
    if inSet(key, pocketTypes) then
        return weight <= 0.5 and "pocket" or "compact"
    end

    local compactTypes = {
        ballpeenhammer = true, crudehammer = true, crudeknife = true,
        fightingknife = true, hammer = true, huntingknife = true,
        kitchenknife = true, knifefillet = true, pipewrench = true,
        wrench = true,
    }
    if inSet(key, compactTypes) or hasPrefix(key, { "pistol", "revolver" }) then
        return "compact"
    end

    if weight <= 0.5 then return "pocket" end
    return "compact"
end

local function carrierHasPockets(carrier)
    if carrier.kind == "skirt" or carrier.kind == "dress" then
        return stableRoll(carrier.item, "clothing-pockets", 100) < 10
    end
    if carrier.kind == "apron" then
        return stableRoll(carrier.item, "clothing-pockets", 100) < 15
    end
    return true
end

local ALWAYS_VISIBLE_TYPES = {
    garbagebag = true,
    toiletpaper = true,
}

local OUTER_ONLY_TYPES = {
    firstaidkit = true,
    seedbag = true,
}

local SMALL_CONTAINER_TYPES = {
    dicebag = true, walletfemale = true, walletmale = true,
}

local function itemFit(item)
    local key = typeKey(item)
    local weight = itemWeight(item)
    if weight > 1.0 then return "visible" end

    if inSet(key, ALWAYS_VISIBLE_TYPES) then return "visible" end

    if instanceof(item, "InventoryContainer") and
            not inSet(key, OUTER_ONLY_TYPES) and
            not inSet(key, SMALL_CONTAINER_TYPES) and
            not hasPrefix(key, { "keyring" }) then
        return "visible"
    end

    if inSet(key, OUTER_ONLY_TYPES) then return "outer" end
    if weight > 0.5 then return "outer" end
    return "normal"
end

local function underwearEligibility(item)
    local key = typeKey(item)

    -- A wallet is deliberately never an underwear stash, regardless of sex.
    if key == "walletfemale" or key == "walletmale" then return nil end

    -- Flat cards and identification are plausible in a bra, but not in
    -- bottom underwear. Passport is included as a compact ID document.
    if key == "creditcard" or key == "idcard" or key == "idcardfemale" or
            key == "idcardmale" or key == "passport" then
        return { bra = true }
    end

    -- Only small, personal objects can use either kind of underwear.
    if key == "money" or key == "moneybundle" or key == "coin" or
            key == "note" or key == "letterhandwritten" or key == "photo" or
            key == "photohass" or key == "locket" or key == "postcard" or
            hasPrefix(key, { "doodle" }) then
        return { bra = true, underwear = true }
    end

    return nil
end

local function chooseCarrier(item, carriers)
    local category = itemCategory(item)
    local weapon = category == "weapon"

    if weapon then
        local size = weaponSize(item)
        if size == "large" then return nil end
        category = size == "pocket" and "weaponPocket" or "weaponCompact"
    end

    local fit = weapon and "normal" or itemFit(item)
    if fit == "visible" then return nil end

    -- A tiny, deterministic chance for a personal keepsake to have been hidden
    -- in underwear. It is an override, not a fallback for every naked zombie.
    local underwearKinds = underwearEligibility(item)
    if underwearKinds and stableRoll(item, "underwear", 100) < 3 then
        local underwear = {}
        for index = 1, #carriers do
            if underwearKinds[carriers[index].kind] then
                underwear[#underwear + 1] = carriers[index]
            end
        end
        if #underwear > 0 then
            return underwear[stableRoll(item, "underwear-index", #underwear) + 1]
        end
    end

    local weights = WEIGHTS[category]
    local weighted = {}
    local total = 0
    for index = 1, #carriers do
        local carrier = carriers[index]
        local weight = weights[carrier.kind] or 0
        if fit == "outer" and carrier.kind ~= "outer" and
                carrier.kind ~= "workwear" then
            weight = 0
        end
        if weight > 0 and carrierHasPockets(carrier) then
            total = total + weight
            weighted[#weighted + 1] = { carrier = carrier, ceiling = total }
        end
    end
    if total == 0 then return nil end

    local roll = stableRoll(item, category, total)
    for index = 1, #weighted do
        if roll < weighted[index].ceiling then return weighted[index].carrier end
    end
end

local function getPocketCarrierId(item)
    local modData = item and item:getModData() or nil
    return modData and modData[CARRIER_ID_KEY] or nil
end

function DP.getPocketRevision(body)
    return body:getModData()[CORPSE_REVISION_KEY] or 0
end

function DP.publishPocketAssignments(body)
    local carriers = {}
    local items = body:getContainer():getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local carrierId = getPocketCarrierId(item)
        local id = itemId(item)
        if id and carrierId then carriers[id] = tostring(carrierId) end
    end
    -- The container-add packet ignores item IDs already present on a client.
    -- Corpse modData has its own native, reliable ObjectModData packet and is
    -- also included when a corpse is saved or loaded by a later observer.
    local modData = body:getModData()
    modData[CORPSE_POCKETS_KEY] = carriers
    modData[CORPSE_REVISION_KEY] = DP.getPocketRevision(body) + 1
    body:transmitModData()
end

function DP.assignGeneratedCorpseLoot(container)
    if not container then return 0 end
    if isClient() then return 0 end
    local body = container:getParent()
    if not DP.isAffectedCorpse(body) then return 0 end

    local protected = collectProtectedItems(body)
    local carriers = collectCarriers(body)
    if #carriers == 0 then return 0 end

    local assigned = 0
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item and not protected[item] then
            local modData = item:getModData()
            if modData[CARRIER_ID_KEY] == nil then
                local carrier = chooseCarrier(item, carriers)
                if carrier then
                    modData[CARRIER_ID_KEY] = carrier.id
                    assigned = assigned + 1
                end
            end
        end
    end
    return assigned
end

local function isHolsterItem(item)
    return item and string.find(normalize(item:getFullType()), "holster") ~= nil
end

local function hasConcealingGarment(body, needsLower)
    local wornItems = body:getWornItems()
    if not wornItems then return false end
    for index = 0, wornItems:size() - 1 do
        local worn = wornItems:get(index)
        local item = worn and worn:getItem() or nil
        if item and not isHolsterItem(item) then
            local kind = carrierKind(worn:getLocation(), item)
            if needsLower and (kind == "lower" or kind == "skirt" or
                    kind == "dress" or kind == "workwear") then return true end
            if not needsLower and (kind == "outer" or kind == "workwear") then return true end
        end
    end
    return false
end

function DP.isHolsterItem(item)
    return isHolsterItem(item)
end

function DP.isHolsterConcealed(body, location, item)
    if not body then return false end
    local key = normalize(location) .. normalize(item and item:getFullType() or "")
    if not string.find(key, "holster") then return false end
    return hasConcealingGarment(body, string.find(key, "ankle") ~= nil)
end

function DP.addHiddenPocketItems(body, hidden)
    local pocketMap = body:getModData()[CORPSE_POCKETS_KEY]
    local wornIds = {}
    local wornItems = body:getWornItems()
    if wornItems then
        for index = 0, wornItems:size() - 1 do
            local worn = wornItems:get(index)
            local wornItem = worn and worn:getItem() or nil
            local id = itemId(wornItem)
            if id and wornItem then
                wornIds[id] = true
            end
        end
    end

    local container = body:getContainer()
    local items = container and container:getItems() or nil
    if items then
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local id = itemId(item)
            local carrierId = pocketMap and id and pocketMap[id] or getPocketCarrierId(item)
            carrierId = carrierId and tostring(carrierId) or nil
            if carrierId and wornIds[carrierId] then
                hidden[item] = true
            end
        end
    end

    -- Holstered weapons follow the holster's visibility. Other attached and
    -- embedded weapons remain exposed.
    local attachedItems = body:getAttachedItems()
    if attachedItems then
        for index = 0, attachedItems:size() - 1 do
            local attached = attachedItems:get(index)
            local item = attached and attached:getItem() or nil
            local location = attached and attached:getLocation() or nil
            if item and DP.isHolsterConcealed(body, location, item) then
                hidden[item] = true
            end
        end
    end
end

return DP
