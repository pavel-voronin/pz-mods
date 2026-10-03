local player = fresh()
function player:getVehicle() return self.vehicle end
ISVehicleMenu.getVehicleToInteractWith = function() end
local z = makeZombie()
zombies = {z}
ISEmoteRadialMenu.variants = {}
Events.OnGameStart.fire()
timestamp = 1000
Events.OnKeyStartPressed.fire(16)
timestamp = 1050
Events.OnKeyPressed.fire(16)
check(player.callouts == 1 and z.calls == 0, "real vanilla Q handler captures sound but defers route")
step()
check(z.calls == 1, "real vanilla Q routes at OnTick")

timestamp = 2000; Events.OnKeyStartPressed.fire(16)
timestamp = 2600; Events.OnKeyPressed.fire(16); step()
check(player.callouts == 1 and z.calls == 1, "holding the real key is not an extra shout")

timestamp = 3000; Events.OnKeyStartPressed.fire(16)
radialOpen = true
timestamp = 3050; Events.OnKeyPressed.fire(16); step()
check(player.callouts == 1, "closing the real radial menu does not shout")

player.x = 3
ISEmoteRadialMenu.emote({character = player}, "shout"); step()
check(player.callouts == 2 and z.calls == 2 and z.path.x == 3.5, "real radial emote uses the wrapper")

player.sneaking = true; player.x = 5
timestamp = 4000; Events.OnKeyStartPressed.fire(16)
timestamp = 4050; Events.OnKeyPressed.fire(16); step()
check(player.callouts == 3 and z.calls == 3 and z.path.x == 5.5, "real Q whisper routes within its short range")

player.sneaking = false
local vehicle = makeVehicle(player)
timestamp = 5000; Events.OnKeyStartPressed.fire(16)
timestamp = 5050; Events.OnKeyPressed.fire(16); step()
check(player.callouts == 3 and vehicle.starts == 1 and vehicle.stops == 1 and z.calls == 4,
    "real vehicle Q starts horn once and routes without a duplicate shout")

vehicle.battery = 0
timestamp = 6000; Events.OnKeyStartPressed.fire(16)
timestamp = 6050; Events.OnKeyPressed.fire(16); step()
check(vehicle.starts == 1 and z.calls == 4, "real horn handler respects battery check")

vehicle.battery, vehicle.driver = 1, makePlayer(2)
player.x = 8
timestamp = 7000; Events.OnKeyStartPressed.fire(16)
timestamp = 7050; Events.OnKeyPressed.fire(16); step()
check(player.callouts == 4 and z.calls == 5 and z.path.x == 8.5,
    "real passenger Q captures callout rather than a driver horn")

vehicle.driver = player; client = true
timestamp = 8000; Events.OnKeyStartPressed.fire(16)
check(#clientMessages == 1 and clientMessages[1][2] == "vehicle"
    and clientMessages[1][3] == "onHorn" and clientMessages[1][4].state == "start",
    "MP Q sends only the original horn command; server handles the reaction")
