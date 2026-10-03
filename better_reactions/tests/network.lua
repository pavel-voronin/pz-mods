local BR = BetterReactions
local player = makePlayer(7)
local function request(args)
    Events.OnClientCommand.fire(BR.MODULE, "shout", player, args)
end
request({x=0,y=0,z=0,radius=30,sequence=1})
check(#serverMessages == 1 and serverMessages[1][3].source == 7, "server relays validated shout")
request({x=0,y=0,z=0,radius=30,sequence=2})
check(#serverMessages == 1, "server rate limit")
timestamp = timestamp + 300
request({x=0,y=0,z=0,radius=3000,sequence=3})
request({x=90,y=0,z=0,radius=30,sequence=3})
request({x=0/0,y=0,z=0,radius=30,sequence=3})
check(#serverMessages == 1, "reject impossible radius, location and nonfinite fields")
player.sneaking = true
request({x=0,y=0,z=0,radius=30,sequence=3})
check(#serverMessages == 1, "server rejects shout range while whispering")
request({x=0,y=0,z=0,radius=6,sequence=3})
check(#serverMessages == 2 and serverMessages[2][3].radius == 6, "server accepts native whisper range")
player.sneaking = false
timestamp = timestamp + 300
player.primary = {
    hasTag = function(_, tag) return tag == ItemTag.MEGAPHONE end,
    getShoutType = function() end,
}
request({x=0,y=0,z=0,radius=90,sequence=3})
check(#serverMessages == 3 and serverMessages[3][3].radius == 90, "megaphone range is preserved")
timestamp = timestamp + 300
player = makePlayer(7)
request({x=0,y=0,z=0,radius=30,sequence=1})
check(#serverMessages == 4 and serverMessages[4][3].sequence > serverMessages[3][3].sequence,
    "reconnecting player gets a new server sequence")

local vehicle = makeVehicle(player)
local function hornCommand()
    Events.OnClientCommand.fire("vehicle", "onHorn", player, {state = "start"})
end
timestamp = timestamp + 300
hornCommand(); vehicle:onHornStart()
check(#serverMessages == 5 and serverMessages[5][3].radius == 150,
    "server captures actual horn sound when mod handler runs first")
step(); timestamp = timestamp + 300
vehicle:onHornStart(); hornCommand()
check(#serverMessages == 6 and serverMessages[6][3].sequence > serverMessages[5][3].sequence,
    "server captures horn when vanilla handler runs first, preserving global order")
step(); timestamp = timestamp + 300
vehicle:onHornStart(); step()
check(#serverMessages == 6, "alarm or arbitrary vehicle sound without manual command is not relayed")
hornCommand(); step()
check(#serverMessages == 6, "expired sound cannot be matched to a later horn command")
vehicle.driver = makePlayer(9)
hornCommand(); vehicle:onHornStart(); step()
check(#serverMessages == 6, "passenger cannot issue driver horn command")
vehicle.driver, vehicle.battery = player, 0
hornCommand(); vehicle:onHornStart(); step()
check(#serverMessages == 6, "empty battery rejects enhanced horn response")
vehicle.battery, vehicle.noHorn = 1, true
hornCommand(); vehicle:onHornStart(); step()
check(#serverMessages == 6, "silent horn command does not fabricate a sound")
timestamp = timestamp + 300
player.vehicle = nil
player.secondary = {getShoutType = function() return "Whistle" end,
    getShoutMultiplier = function() return 2 end}
request({x=0,y=0,z=0,radius=60,sequence=2})
check(#serverMessages == 7 and serverMessages[7][3].radius == 60,
    "server preserves equipped whistle multiplier")
timestamp = timestamp + 300
player.secondary = nil
local item = {getShoutType = function() return "Whistle" end,
    getShoutMultiplier = function() return 3 end}
player.worn = {{getItem = function() return item end}}
request({x=0,y=0,z=0,radius=90,sequence=3})
check(#serverMessages == 8 and serverMessages[8][3].radius == 90,
    "server preserves worn shout item multiplier")
print("Better Reactions total checks: " .. checks)
