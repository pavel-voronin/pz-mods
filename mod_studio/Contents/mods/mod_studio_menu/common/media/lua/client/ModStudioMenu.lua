-- An external request is required; this helper does nothing in ordinary sessions.
local reader = getFileReader("ModStudio/menu-request.txt", false)
if not reader then return end
local token = reader:readLine()
local seconds = tonumber(reader:readLine())
reader:close()
if not token or not string.match(token, "^[a-f0-9]+$") or #token ~= 32
    or not seconds or seconds < 1 or seconds > 600 then return end
local entered, captured, finished
local function result(status)
    local writer = getFileWriter("ModStudio/menu-" .. token .. ".json", true, false)
    assert(writer, "Cannot write menu result")
    writer:write('{"schema":1,"status":"' .. status .. '","reason":"Main-menu check","token":"' .. token .. '"}')
    writer:close()
end
Events.OnMainMenuEnter.Add(function()
    if entered then return end
    entered = getTimestampMs()
    result("running")
    print("[Mod Studio] Main menu ready: " .. token)
end)
Events.OnFETick.Add(function()
    if not entered or finished then return end
    local ok, err = pcall(function()
        local elapsed = (getTimestampMs() - entered) / 1000
        if elapsed >= seconds and not captured then
            getCore():TakeFullScreenshot("modstudio-menu-" .. token .. ".png")
            captured = getTimestampMs()
        end
        -- Leave the render thread time to flush its screenshot before shutdown.
        if captured and getTimestampMs() - captured >= 1000 then
            finished = true
            result("complete")
            getCore():quitToDesktop()
        end
    end)
    if not ok then
        finished = true
        print("[Mod Studio] Menu check failed: " .. tostring(err))
        result("failed")
        getCore():quitToDesktop()
    end
end)
