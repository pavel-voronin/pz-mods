-- Use the game's own save switch and character/world creation pipeline.

require "OptionScreens/MainScreen"
require "OptionScreens/NewGameScreen"
require "SpawnRegions"
require "ISUI/ISLabel"
require "ISUI/ISModalDialog"
require "ModStudio/LaunchAPI"
require "ModStudio/Settings"
local API = ModStudio.Launch
local settings = ModStudio.Settings
if API.installed then return end
API.installed = true

local pendingItems
local pendingWorld
local ownsSaveMode = false
local previousNoSave = false
local launching = false

local function applySaveMode()
    if not ownsSaveMode then previousNoSave = getCore():isNoSave() end
    ownsSaveMode = true
    getCore():setNoSave(settings.noSave)
end

local function restoreSaveMode()
    if ownsSaveMode then getCore():setNoSave(previousNoSave) end
    ownsSaveMode = false
end

local function canLaunch(screen)
    return screen and not screen.inGame and not launching
        and screen.bottomPanel and screen.bottomPanel:getIsVisible()
        and (not screen.delay or screen.delay <= 0)
        and not screen.tutorialButton and not screen.checkSavefileModal
        and not UIManager.isModalVisible()
end

local function showError(message)
    print("[Mod Studio] Preset launch: " .. tostring(message))
    local modal = ISModalDialog:new((getCore():getScreenWidth()-560)/2,
        (getCore():getScreenHeight()-180)/2, 560, 180,
        "Mod Studio: " .. tostring(message), false, nil, nil)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
end

local function prepareAndLaunch(screen, preset)
    assert(type(preset.name) == "string" and preset.name ~= "", "Missing shortcut name")
    assert(type(preset.sandboxPreset) == "string", "Missing sandboxPreset")
    assert(type(preset.spawnRegion) == "string", "Missing spawnRegion")
    -- Validate and prepare the complete loadout before changing the world.
    local items = {}
    for _, entry in ipairs(preset.inventory or {}) do
        for i = 1, entry.count or 1 do
            local item = InventoryItemFactory.CreateItem(entry.type)
            assert(item, "Unknown inventory item: " .. entry.type)
            if entry.fullAmmo then
                assert(item:getMaxAmmo() > 0, "Item has no ammo capacity: " .. entry.type)
                item:setCurrentAmmoCount(item:getMaxAmmo())
            end
            if entry.worn then assert(item:getBodyLocation(), "Item cannot be worn: " .. entry.type) end
            items[#items+1] = {item=item, worn=entry.worn}
        end
    end
    local options = SandboxOptions.new()
    assert(options:loadPresetFile(preset.sandboxPreset),
        "Sandbox preset not found or unreadable: " .. preset.sandboxPreset)

    -- Same mod set as the native New Game entry.
    ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))
    getWorld():setGameMode("Sandbox")
    getWorld():setMap("DEFAULT")
    local groups = MapGroups.new()
    groups:createGroups()
    local region
    for group = 0, groups:getNumberOfGroups()-1 do
        groups:setWorld(group)
        for _, candidate in ipairs(SpawnRegionMgr.getSpawnRegions() or {}) do
            if candidate.name == preset.spawnRegion then region = candidate; break end
        end
        if region then break end
    end
    assert(region, "Spawn region not found: " .. preset.spawnRegion)
    local points = region.points and region.points[CharacterProfession.UNEMPLOYED:getName()]
    assert(points and #points > 0, "No unemployed spawn points in " .. preset.spawnRegion)

    applySaveMode() -- Before any createWorld/database initialization.
    screen.bottomPanel:setVisible(false)
    screen.createWorld = true
    screen:setDefaultSandboxVars()
    screen.sandOptions:settingsToUI(options)
    screen.sandOptions:setSandboxVars() -- Native power/water cutoff randomization.
    getWorld():setPreset(preset.sandboxPreset)
    local worldName = "ModStudio-" .. ZombRand(1000000000) .. "-" .. ZombRand(1000000000)
    while checkSaveFolderExists("Sandbox" .. getFileSeparator() .. worldName) do
        worldName = "ModStudio-" .. ZombRand(1000000000) .. "-" .. ZombRand(1000000000)
    end
    getWorld():setWorld(worldName)
    local spawn = screen.mapSpawnSelect
    spawn.selectedRegion = region
    setSpawnRegion(region.name)
    getCore():setSelectedMap(region.name)
    spawn:generateNewSeed()
    spawn:saveGenParams()

    -- Reset a previously edited character, then let native screens populate their
    -- normal descriptor, outfit and voice. No perk/stat overrides or bonus traits.
    screen.desc = SurvivorFactory.CreateSurvivor()
    screen.charCreationMain:createAvatar()
    screen.charCreationProfession:resetBuild()
    -- onSelectProf skips an unchanged selection; this descriptor is always fresh.
    screen.desc:setProfessionSkills(screen.charCreationProfession:getSelectedProf())
    screen.desc:setCharacterProfession(CharacterProfession.UNEMPLOYED)
    screen.charCreationProfession:onOptionMouseDown({internal="NEXT"}, 0, 0)
    screen.charCreationMain:onRandomCharacter()
    pendingItems = items
    pendingWorld = worldName
    screen.charCreationMain:onOptionMouseDown({internal="NEXT"}, 0, 0)
end

local function launch(preset)
    local screen = MainScreen.instance
    if not canLaunch(screen) then return end
    launching = true
    local world = getWorld()
    local oldMode, oldMap, oldWorld = world:getGameMode(), world:getMap(), world:getWorld()
    local oldOptions = getSandboxOptions():newCopy()
    local oldCreateWorld = screen.createWorld
    local oldRegion = screen.mapSpawnSelect.selectedRegion
    local ok, err = pcall(prepareAndLaunch, screen, preset)
    if ok then return end -- Prevent double-clicks until returning to the menu.
    restoreSaveMode()
    pendingItems, pendingWorld = nil, nil
    launching = false
    world:setGameMode(oldMode)
    world:setMap(oldMap)
    world:setWorld(oldWorld)
    getSandboxOptions():copyValuesFrom(oldOptions)
    getSandboxOptions():toLua()
    screen.createWorld = oldCreateWorld
    screen.mapSpawnSelect.selectedRegion = oldRegion
    screen.charCreationMain:setVisible(false)
    screen.charCreationProfession:setVisible(false)
    screen.bottomPanel:setVisible(true)
    showError(err)
end

local function addLabel(screen, text, callback)
    local label = ISLabel:new(0, 0, screen.survivalOption:getHeight(), text,
        1, 1, 1, 1, UIFont.Large, true)
    label:initialise()
    label.onMouseDown = function()
        if canLaunch(screen) then callback() end
        return true
    end
    label.prerender = function(self)
        if self:isMouseOver() then
            self:drawRect(-6, 0, self:getWidth()+12, self:getHeight(), 0.5, 0.3, 0.3, 0.3)
        end
        ISLabel.prerender(self)
    end
    label:setVisible(false)
    screen:addChild(label) -- Native bottomPanel stretches all of its label hitboxes.
    return label
end

local function install(screen)
    if not screen or screen.inGame or not screen.survivalOption then return end
    if screen.modStudioLaunchRevision == API.revision then return end
    for _, label in ipairs(screen.modStudioLaunchLabels or {}) do screen:removeChild(label) end
    screen.modStudioLaunchRevision = API.revision
    local labels = {}
    screen.modStudioLaunchLabels = labels
    labels[1] = addLabel(screen, "No Saves", function()
        local ok, err = pcall(settings.setNoSave, not settings.noSave)
        if not ok then showError(err) end
    end)
    labels[1]:setTooltip("New games only. No Saves: progress is not saved. Saves On: normal saving.")
    for _, preset in ipairs(API.presets) do
        local entry = preset
        local label = addLabel(screen, tostring(entry.name or "?"), function() launch(entry) end)
        label:setTooltip(tostring(entry.sandboxPreset) .. " / " .. tostring(entry.spawnRegion)
            .. " / Unemployed / No selected traits / Random appearance")
        labels[#labels+1] = label
    end
end

local function layout(screen)
    local labels = screen.modStudioLaunchLabels
    if not labels then return end
    local visible = not screen.inGame and not launching
        and screen.bottomPanel:getIsVisible() and screen.survivalOption:getIsVisible()
    local x = screen.bottomPanel:getX() + screen.survivalOption:getX()
        + screen.survivalOption:getWidth() + 24
    local startX = x
    local y = screen.bottomPanel:getY() + screen.survivalOption:getY()
    labels[1]:setNameWithoutMoving(settings.noSave and "No Saves" or "Saves On")
    local color = settings.noSave and 0.5 or 1
    labels[1]:setColor(color, color, color)
    for _, label in ipairs(labels) do
        if x > startX and x + label:getWidth() > screen:getWidth()-20 then
            x = startX
            y = y + label:getHeight()
        end
        label:setX(x)
        label:setY(y)
        label:setVisible(visible)
        x = x + label:getWidth() + 24
    end
end

-- Also apply the toggle to ordinary New Game, without changing existing saves.
local nativeClickPlay = NewGameScreen.clickPlay
function NewGameScreen:clickPlay()
    if MainScreen.instance and not MainScreen.instance.inGame then applySaveMode() end
    return nativeClickPlay(self)
end

local nativeInstantiate = MainScreen.instantiate
function MainScreen:instantiate()
    nativeInstantiate(self)
    install(self)
end

local nativePrerender = MainScreen.prerender
function MainScreen:prerender()
    nativePrerender(self)
    install(self) -- Include registrations made after menu construction.
    layout(self) -- Follow native logo scaling, localization and resolution changes.
end

local nativeBottomVisible = MainScreen.setBottomPanelVisible
function MainScreen:setBottomPanelVisible(visible)
    if visible and self.parent and not self.parent.inGame then
        restoreSaveMode()
        pendingItems, pendingWorld = nil, nil
        launching = false
    end
    nativeBottomVisible(self, visible)
    if self.parent then layout(self.parent) end
end

Events.OnMainMenuEnter.Add(function()
    -- Core survives ResetLua when leaving a game, Lua locals do not. A menu entered
    -- after such a reset must not carry NoSave into Continue/Load/Multiplayer.
    getCore():setNoSave(false)
    ownsSaveMode = false
    pendingItems, pendingWorld = nil, nil
    launching = false
    install(MainScreen.instance)
end)
Events.OnGameBoot.Add(function() install(MainScreen.instance) end)
install(MainScreen.instance)

-- Add to the vanilla StarterKit and profession items, once per preset launch.
Events.OnNewGame.Add(function(player)
    if isClient() or not pendingItems or getWorld():getWorld() ~= pendingWorld then return end
    local items = pendingItems
    pendingItems, pendingWorld = nil, nil
    for _, entry in ipairs(items) do
        local item = player:getInventory():AddItem(entry.item)
        if item and entry.worn then player:setWornItem(item:getBodyLocation(), item) end
    end
end)
