if isClient() then
    return
end

local DP = require("dead_pockets/DP_Layers")

local function onFillContainer(roomType, containerType, container)
    -- Nested zombie bags emit their own event, sometimes with a distribution
    -- table rather than an ItemContainer. Only the final root-corpse event has
    -- roomType "Zombie" and contains all generated loose loot.
    if roomType ~= "Zombie" then return end

    DP.assignGeneratedCorpseLoot(container)
    if isServer() and container and DP.isAffectedCorpse(container:getParent()) then
        DP.publishPocketAssignments(container:getParent())
    end
end

Events.OnFillContainer.Add(onFillContainer)
