-- Optional API: require "ModStudio/LaunchAPI" when Mod Studio is enabled.
-- register(ownerModId, presetId, {name, sandboxPreset, spawnRegion, inventory}).
-- inventory: {{type="Base.Item", count=1, fullAmmo=false, worn=false}, ...}.
-- fullAmmo fills native ammo capacity; worn equips at the native body location.
-- Registering the same owner/id replaces it; definitions are copied on registration.
ModStudio = ModStudio or {}
ModStudio.Launch = ModStudio.Launch or {presets={}, keys={}, revision=0}
local API = ModStudio.Launch
function API.register(owner, id, preset)
    assert(type(owner)=="string" and owner~="", "Missing preset owner")
    assert(type(id)=="string" and id~="", "Missing preset ID")
    assert(type(preset)=="table", "Missing preset")
    local copy = {}
    for _, key in ipairs({"name", "sandboxPreset", "spawnRegion"}) do
        assert(type(preset[key])=="string" and preset[key]~="", "Missing " .. key)
        copy[key] = preset[key]
    end
    copy.inventory = {}
    assert(preset.inventory==nil or type(preset.inventory)=="table", "Invalid inventory")
    for _, entry in ipairs(preset.inventory or {}) do
        assert(type(entry)=="table" and type(entry.type)=="string" and entry.type~="", "Invalid inventory item")
        local count = entry.count or 1
        assert(type(count)=="number" and count>=1 and count<=1000 and count==math.floor(count), "Invalid inventory count")
        assert(entry.fullAmmo==nil or type(entry.fullAmmo)=="boolean", "Invalid fullAmmo")
        assert(entry.worn==nil or type(entry.worn)=="boolean", "Invalid worn")
        copy.inventory[#copy.inventory+1] = {type=entry.type, count=count, fullAmmo=entry.fullAmmo, worn=entry.worn}
    end
    API.keys[owner] = API.keys[owner] or {}
    local index = API.keys[owner][id] or (#API.presets+1)
    API.keys[owner][id] = index
    API.presets[index] = copy
    API.revision = API.revision+1
end
