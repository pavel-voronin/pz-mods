local env = setmetatable({}, {__index = _G})
env._G = env
local function loadSource(source)
    local chunk = assert(loadstring(source))
    setfenv(chunk, env)
    chunk()
end
local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end
local source = read(GAME_LUA_ROOT .. "/client/OptionScreens/MainOptions.lua")
env.MainOptions = {KEYS_VERSION = 2, instance = {gameOptions = {}, onKeybindChanged = function() end}}
for _, bounds in ipairs({
    {"function MainOptions.loadKeys()", "function MainOptions:prerender()"},
    {"MainOptions.saveKeys = function()", "function MainOptions:apply("},
    {"function MainOptions.getKeyPrefix(bind)", "function MainOptions:onOptionMouseDown("},
    {"function MainOptions.keyPressHandler(", "function MainOptions:onKeybindChanged("}
}) do
    local first = assert(source:find(bounds[1], 1, true))
    local last = assert(source:find(bounds[2], first, true))
    loadSource(source:sub(first, last - 1))
end
local bindings, saved = {}, {}
local core = {}
function core:reinitKeyMaps() bindings = {} end
function core:isAzerty() return false end
function core:getOptionUpdateSneakButton() return false end
function core:addKeyBinding(name, key, alternate, shift, ctrl, alt)
    bindings[name] = {key = key, altCode = alternate, shift = shift, ctrl = ctrl, alt = alt}
end
function core:getKey(name) return bindings[name].key end
env.getCore = function() return core end
env.getKeyName = tostring
env.cacheFileExists = function() return true end
env.getFileReader = function(name)
    assert(name == "keysB42.ini")
    local index = 0
    return {readLine = function() index = index + 1; return saved[index] end, close = function() end}
end
env.getFileWriter = function(name)
    assert(name == "keysB42.ini")
    saved = {}
    return {write = function(_, value)
        for line in value:gmatch("[^\r\n]+") do saved[#saved + 1] = line end
    end, close = function() end}
end
env.luautils = {stringStarts = function(s, prefix) return s:sub(1, #prefix) == prefix end}
env.string = setmetatable({split = function(s, separator)
    local out = {}
    for value in (s or ""):gmatch("[^" .. separator .. "]+") do out[#out + 1] = value end
    return out
end}, {__index = string})
env.keyBinding = {
    {value = "Toggle Health Panel", key = 35}, {value = "VehicleHorn", key = 16},
    {value = "OtherModAction", key = 31}
}
env.require = function(name) assert(name == "keyBinding") end
loadSource(read("Contents/mods/auto_weapon_swap/common/media/lua/shared/AutoWeaponSwap/KeyBinding.lua"))
local options = env.MainOptions
options.loadKeys()
assert(bindings.AWSOpenExclusions.key == 0)
local function rows()
    options.keyText = {}
    local selected
    for _, bind in ipairs(options.keys) do
        local row
        if bind.value:sub(1, 1) == "[" then row = {value = bind.value}
        else
            local name = bind.value
            row = {txt = {getName = function() return name end}, btn = {setTitle = function() end},
                keyCode = bind.key, altCode = bind.altCode, shift = bind.shift, ctrl = bind.ctrl, alt = bind.alt}
            if name == "AWSOpenExclusions" then selected = row end
        end
        table.insert(options.keyText, row)
    end
    return assert(selected)
end
local count = 0
for _, assignment in ipairs({
    {44, false, false, false}, {44, true, false, false}, {44, false, true, false},
    {44, false, false, true}, {10002, false, false, false}, {10002, false, true, false}
}) do
    local row = rows()
    options.setKeybindDialog = {keybindName = "AWSOpenExclusions", destroy = function() end}
    options.keyPressHandler(unpack(assignment))
    options.saveKeys()
    options.loadKeys()
    local bind = bindings.AWSOpenExclusions
    assert(bind.key == assignment[1] and bind.shift == assignment[2])
    assert(bind.ctrl == assignment[3] and bind.alt == assignment[4])
    assert(bindings.OtherModAction.key == 31)
    row = rows()
    row.keyCode = 99
    options.loadKeys()
    assert(bindings.AWSOpenExclusions.key == assignment[1])
    count = count + 1
end
-- Simulate startup with the saved assignment and a fresh binding list
local savedKey = bindings.AWSOpenExclusions.key
env.keyBinding = {{value = "Toggle Health Panel", key = 35}, {value = "VehicleHorn", key = 16},
    {value = "OtherModAction", key = 31}}
loadSource(read("Contents/mods/auto_weapon_swap/common/media/lua/shared/AutoWeaponSwap/KeyBinding.lua"))
options.loadKeys()
assert(bindings.AWSOpenExclusions.key == savedKey and bindings.AWSOpenExclusions.ctrl)
env.ISSetKeybindDialog = {}
source = read(GAME_LUA_ROOT .. "/client/ISUI/ISSetKeybindDialog.lua")
loadSource(assert(source:match("(function ISSetKeybindDialog:onClear.-)\nfunction ISSetKeybindDialog:isKeyConsumed")))
rows()
env.ISSetKeybindDialog.onClear({keybindName = "AWSOpenExclusions", destroy = function() end})
options.saveKeys()
options.loadKeys()
assert(bindings.AWSOpenExclusions.key == 0 and bindings.OtherModAction.key == 31)
print(tostring(count + 3) .. " native Controls scenarios passed: default, assignments, persistence, cancel and clear")
