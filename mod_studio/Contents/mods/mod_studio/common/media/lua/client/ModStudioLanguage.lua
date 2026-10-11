require "ISUI/ISComboBox"
require "OptionScreens/MainScreen"

local function scaled(value)
    return math.ceil(value * math.max(1, getTextManager():getFontHeight(UIFont.Small) / 19))
end

local function changeLanguage(screen, box)
    if screen.inGame or not screen.bottomPanel:isVisible() or box.disabled then return end
    local language = box:getOptionData(box.selected)
    if not language or language == Translator.getLanguage() then return end
    getCore():setOptionLanguageName(language:name())
    Translator.setLanguage(language)
    getCore():saveOptions()
    box:setEnabled(false)
    getCore():DelayResetLua("default", "optionsChangedAccepted")
end

local function install(screen)
    if not screen or screen.inGame or not screen.bottomPanel or screen.modStudioLanguage then return end
    local box = ISComboBox:new(0, 0, 160, scaled(34), screen, changeLanguage)
    box:initialise()
    box:setAnchorLeft(false)
    box:setAnchorRight(true)
    box:setAnchorTop(false)
    box:setAnchorBottom(true)
    box.openUpwards = true
    local languages = Translator.getAvailableLanguage()
    for i = 0, languages:size() - 1 do
        local language = languages:get(i)
        box:addOptionWithData(language:text(), language)
    end
    box:selectData(Translator.getLanguage())
    box.language = Translator.getLanguage()
    box:setWidthToOptions(160)
    box:setToolTipMap({defaultTooltip = getText("UI_optionscreen_language")})
    box:setVisible(false)
    screen:addChild(box)
    screen.modStudioLanguage = box
end

local function update(screen)
    install(screen)
    local box = screen.modStudioLanguage
    if not box then return end
    local visible = not screen.inGame and screen.bottomPanel:isVisible()
    box:setVisible(visible)
    if not visible then
        if box.expanded then box.expanded = false; box:hidePopup() end
        return
    end
    if box.language ~= Translator.getLanguage() then
        box.language = Translator.getLanguage()
        box:selectData(box.language)
    end
    local top, right = screen.height - 20, screen.width - 20
    for _, name in ipairs({"reportBug", "termsOfService", "resetLua", "modListDetail"}) do
        local button = screen[name]
        if button and button:isVisible() then
            top = math.min(top, button:getY())
            right = math.min(right, button:getRight())
        end
    end
    box:setX(math.max(0, right - box:getWidth()))
    box:setY(math.max(0, top - box:getHeight() - scaled(8)))
end

local nativeUpdate = MainScreen.update
function MainScreen:update(...)
    nativeUpdate(self, ...)
    update(self)
end
Events.OnGameBoot.Add(function() install(MainScreen.instance) end)
install(MainScreen.instance)
