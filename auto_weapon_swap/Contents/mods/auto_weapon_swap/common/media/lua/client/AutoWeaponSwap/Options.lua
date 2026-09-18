require "AutoWeaponSwap/KeyBinding"
require "AutoWeaponSwap/Window"

local AWS = AutoWeaponSwap
local bindingName = "AWSOpenExclusions"
local previousPress = false
local waitForRelease = false

local function physicallyDown(key)
    if key == 0 then return false end
    if key >= Mouse.BTN_OFFSET then return Mouse.isButtonDown(key - Mouse.BTN_OFFSET) end
    return GameKeyboard.isKeyDownRaw(key)
end

function AWS.onMenuInput()
    local core = getCore()
    if not physicallyDown(core:getKey(bindingName)) and not physicallyDown(core:getAltKey(bindingName)) then
        previousPress, waitForRelease = false, false
        return
    end
    local player = getSpecificPlayer(0)
    if isGamePaused() or core:isDoingTextEntry() or not player or player:isDead()
        or (MainScreen and MainScreen.instance and MainScreen.instance:isVisible())
        or (MainOptions and (MainOptions.setKeybindDialog
            or (MainOptions.instance and MainOptions.instance:isVisible()))) then
        -- A key held in a menu or text field must be released first
        waitForRelease = true
        return
    end
    if waitForRelease then return end
    local pressed = GameKeyboard.isKeyDown(bindingName)
    if pressed and not previousPress then AWS.toggleExclusions(player) end
    if pressed then previousPress = true end
end

Events.OnTickEvenPaused.Add(AWS.onMenuInput)
