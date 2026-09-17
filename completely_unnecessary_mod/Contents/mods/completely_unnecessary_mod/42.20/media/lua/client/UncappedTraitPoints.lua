require "OptionScreens/ServerSettingsScreen"
require "OptionScreens/CharacterCreationProfession"

-- Replace the returned UI entry: vanilla's Java option is capped at 100.
local originalGetSandboxSettingsTable = ServerSettingsScreen.getSandboxSettingsTable
function ServerSettingsScreen.getSandboxSettingsTable(...)
    local pages = originalGetSandboxSettingsTable(...)
    local option = getSandboxOptions():getOptionByName("UncappedTraitPoints.Points")
    if not option then
        error("Integer.MAX_VALUE Trait Points: sandbox option was not loaded")
    end
    for _, page in ipairs(pages) do
        for _, setting in ipairs(page.settings) do
            if setting.name == "CharacterFreePoints" then
                setting.name = option:getName()
                setting.translatedName = option:getTranslatedName()
                setting.tooltip = getText("Sandbox_CharacterFreePoints_tooltip")
                setting.type = "entry"
                setting.text = option:getValueAsString()
                setting.onlyNumbers = true
            end
        end
    end
    return pages
end

local originalPointToSpend = CharacterCreationProfession.PointToSpend
function CharacterCreationProfession:PointToSpend()
    local points = originalPointToSpend(self)
    local settings = SandboxVars and SandboxVars.UncappedTraitPoints
    if not settings or type(settings.Points) ~= "number" then
        return points
    end
    -- Replace the bonus, preserving profession costs and trait penalties.
    return points - (SandboxVars.CharacterFreePoints or 0) + settings.Points
end
