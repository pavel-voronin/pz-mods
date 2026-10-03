if isServer() then return end
require "BetterReactionsController"
require "ISUI/ISEmoteRadialMenu"
require "ISUI/ISDPadWheels"
require "Vehicles/ISUI/ISVehicleMenu"

local BR = BetterReactions

local keyReleased = ISEmoteRadialMenu.onKeyReleased
ISEmoteRadialMenu.onKeyReleased = function(key)
    return BR.capture(getSpecificPlayer(0), keyReleased, key)
end
-- Vanilla hooks this callback on OnGameStart.
Events.OnKeyPressed.Remove(keyReleased)

local emote = ISEmoteRadialMenu.emote
ISEmoteRadialMenu.emote = function(self, name)
    if name ~= "shout" then return emote(self, name) end
    return BR.capture(self.character, emote, self, name)
end

local dpadShout = ISDPadWheels.onShout
ISDPadWheels.onShout = function(player)
    return BR.capture(player, dpadShout, player)
end

local vehicleKey = ISVehicleMenu.onKeyPressed
ISVehicleMenu.onKeyPressed = function(key)
    return BR.capture(getSpecificPlayer(0), vehicleKey, key)
end
Events.OnKeyPressed.Remove(vehicleKey)
Events.OnKeyPressed.Add(ISVehicleMenu.onKeyPressed)

local hornStart = ISVehicleMenu.onHornStart
ISVehicleMenu.onHornStart = function(player)
    return BR.captureHorn(player, hornStart, player)
end

print("[Better Reactions] " .. BR.VERSION .. " loaded")
