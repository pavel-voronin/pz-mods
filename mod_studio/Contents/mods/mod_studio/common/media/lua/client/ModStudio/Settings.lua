ModStudio = ModStudio or {}
if ModStudio.Settings then return end
local settings = {noSave=true}
ModStudio.Settings = settings
local path = "ModStudio/settings.ini"
local reader = getFileReader(path, false)
if reader then
    local line = reader:readLine()
    while line do
        if line == "noSave=true" then settings.noSave = true end
        if line == "noSave=false" then settings.noSave = false end
        line = reader:readLine()
    end
    reader:close()
end
function settings.setNoSave(value)
    local writer = getFileWriter(path, true, false)
    assert(writer, "Cannot save Mod Studio settings")
    writer:write("noSave=" .. tostring(value) .. "\n")
    writer:close()
    settings.noSave = value
end
