ISBaseObject = {derive = function() return {} end}
Vector3f = {new = function() return {} end}
KeybindId = {EMOTE = "Emote", SHOUT = "Shout", VEHICLE_HORN = "VehicleHorn",
    START_VEHICLE_ENGINE = "StartVehicleEngine", VEHICLE_HEATER = "VehicleHeater",
    VEHICLE_MECHANICS = "VehicleMechanics", VEHICLE_SWITCH_SEAT = "VehicleSwitchSeat"}
UIManager = {getSpeedControls = function() return nil end}
ISTimedActionQueue = {queues = {}}
local core = {
    isKey = function(_, name, key)
        return (name == "Shout" or name == "Emote" or name == "VehicleHorn") and key == 16
    end,
    getGameMode = function() return "Sandbox" end,
    getOptionRadialMenuKeyToggle = function() return false end,
}
function getCore() return core end
local radial = {
    isReallyVisible = function() return radialOpen end,
    removeFromUIManager = function() radialOpen = false end,
}
function getPlayerRadialMenu() return radial end
