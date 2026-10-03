BetterReactions = BetterReactions or {}
local BR = BetterReactions
BR.VERSION = "1.0.5"
BR.MODULE = "BetterReactions"
BR.DIAGNOSTICS = false

function BR.isFinite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

function BR.shoutRadius(player)
    local primary = player:getPrimaryHandItem()
    local radius = primary and primary:hasTag(ItemTag.MEGAPHONE) and 90 or 30
    if player:isSneaking() then return radius / 5 end
    local item
    if primary and primary:getShoutType() then
        item = primary
    else
        local secondary = player:getSecondaryHandItem()
        if secondary and secondary:getShoutType() then item = secondary end
    end
    if not item then
        local worn = player:getWornItems()
        if worn then
            for i = 0, worn:size() - 1 do
                local candidate = worn:get(i):getItem()
                if candidate and candidate:getShoutType() then
                    item = candidate
                    break
                end
            end
        end
    end
    if item then radius = math.floor(radius * item:getShoutMultiplier()) end
    return radius
end
