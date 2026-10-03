local BR = BetterReactions
local p = fresh()
local z = makeZombie()
zombies = {z}
shout()
check(z.calls == 0, "route must wait for OnTick")
step()
check(z.calls == 1 and z.turns == 1, "first response routes and turns")
check(#diagnosticLines == 0, "release build does not log shout or zombie diagnostics")
for i = 1, 30 do z.x = z.x - 0.1; step() end
check(z.calls == 1, "normal progress must not restart pathfinding")
shout(); step()
check(z.calls == 1, "repeated shout from the same tile keeps the current route")
z.path.x = 50
step(0.3)
check(z.calls == 2 and z.path.x == 0.5 and z.turns == 1, "restore a route overwritten by native hearing")
z.moving = false
step(0.3)
check(z.calls == 3, "recover an otherwise matching route stopped by stale native sound state")
z.target = makePlayer(2)
step()
z.target, z.path.x = nil, 80
step()
check(z.calls == 3, "detecting a person hands control back permanently")

fresh(); z = makeZombie(); zombies = {z}
shout(); step(); step(9.8)
shout(); step(0.3)
check(z.calls == 1, "repeat near the stall deadline keeps the current route")
z.path.x = 80; step(0.3)
check(z.calls == 2 and z.path.x == 0.5, "repeat renews support past the old stall deadline")
step(9.5); z.path.x = 80; step()
check(z.calls == 2, "renewed support still expires after ten seconds without movement")

p = fresh(); z = makeZombie(); z.state = "getup"; zombies = {z}
shout(); step(3)
check(z.calls == 0, "getting up defers the command")
p.x = 4; shout(); step()
z.state = "idle"; step()
check(z.calls == 1 and z.path.x == 4.5, "latest shout replaces pending shout")

fresh(); z = makeZombie(); z.state, z.onFloor, z.culled = "sitting", true, true; zombies = {z}
shout(); step()
check(z.wakes == 1 and z.calls == 1, "sitting zombie on the floor receives a native wake-up stimulus")
step(2)
check(z.wakes == 1 and z.calls == 1, "wake stimulus is not restarted each tick")
z.state, z.gettingUp = "getup-fromSitting", true
players[0].x = 4; shout(); step()
check(z.calls == 1, "new shout is queued while the sitting zombie gets up")
z.state, z.gettingUp, z.onFloor = "idle", false, false
step()
check(z.calls == 2 and z.path.x == 4.5, "after standing up, investigate the latest shout")

fresh(); z = makeZombie(); z.state, z.onFloor = "onground", true; zombies = {z}
shout(); step()
check(z.calls == 0 and z.wakes == nil, "a knocked-down zombie is not treated as an idle sitter")

fresh(); z = makeZombie(); z.state = "climbfence"; zombies = {z}
shout(); step(5); z.state = "idle"; step()
check(z.calls == 1, "deliver once after climbing")
z.state = "thump"; step(15)
check(z.calls == 1, "do not interrupt a door attack along the route")
z.state = "walktoward"; z.x = 8; step()
check(z.calls == 1, "continue after door attack")

fresh(); z = makeZombie(); z.target = makePlayer(2); zombies = {z}
shout(); z.target = nil; step()
check(z.calls == 0, "existing chase discards rather than queues a shout")

fresh(); z = makeZombie(); z.target = makePlayer(2); z.target.dead = true; zombies = {z}
shout(); step()
check(z.calls == 1 and z.target == nil, "stale dead target is cleared before investigating")

fresh(); z = makeZombie(); zombies = {z}
Events.OnWorldSound.fire(0, 0, 0, 100, 100, players[0]); step()
check(z.calls == 0, "an arbitrary player sound is not a shout")
players[0].sneaking = true; shout(); step()
check(z.calls == 0, "whisper does not reach a zombie ten tiles away")
local close, poor = makeZombie(5), makeZombie(5)
poor.hearing = 0.45
zombies = {close, poor}; shout(); step()
check(close.calls == 1 and poor.calls == 0, "whisper reacts immediately within individual hearing range")

fresh(); local normal, poor, pinpoint = makeZombie(20), makeZombie(20), makeZombie(60)
poor.hearing, pinpoint.hearing = 0.45, 3
zombies = {normal, poor, pinpoint}; shout(); step()
check(normal.calls == 1 and poor.calls == 0 and pinpoint.calls == 1, "individual native hearing multipliers")

fresh(); local indoor, outdoor = makeZombie(25), makeZombie(25)
indoor.square = square({}); zombies = {indoor, outdoor}; shout(); step()
check(indoor.calls == 0 and outdoor.calls == 1, "native room attenuation")

fresh(); z = makeZombie(1); z.z = 10; zombies = {z}; shout(); step()
check(z.calls == 0, "vertical distance is multiplied by three")

fresh(); z = makeZombie(); zombies = {z}; shout(); step()
z.state, z.moving, z.pathfinding = "pathfind", false, false
step(0.3)
check(z.calls == 1, "temporary cleared flags must not restart an asynchronous search")
z.moving = true; z.path.x = 60; step(0.3)
check(z.calls == 2, "task survives cleared flags while pathfinding is in progress")

fresh(); z = makeZombie(); zombies = {z}; shout(); step()
z.state, z.moving, z.pathfinding = "pathfind", false, false
step(11); z.state = "idle"; z.path.x = 60; step()
check(z.calls == 1, "failed native path expires without repeated requests")

BR.DIAGNOSTICS = true
fresh(); z = makeZombie(); z.culled = true; zombies = {z}; shout(); step()
z.state, z.moving, z.pathfinding = "pathfind", false, true
dt, realDt = 4, 1 / 60
for i = 1, 240 do Events.OnTick.fire() end
z.x, z.state, z.moving, z.path.x = 9, "walktoward", true, 60
Events.OnTick.fire()
check(z.calls == 2, "offscreen task survives fast-forward while native path search runs in real time")
check(z.turns == 1, "offscreen facing does not require turn animation events")
local diagnosticFound = false
for _, line in ipairs(diagnosticLines) do
    if line:find("heard=true", 1, true) and line:find("culled=true", 1, true) then
        diagnosticFound = true
    end
end
check(diagnosticFound, "diagnostics report heard but invisible zombies")
BR.DIAGNOSTICS = false

fresh(); z = makeZombie(); zombies = {z}; shout(); step()
step(11); z.path.x = 90; step()
check(z.calls == 1, "stalled task expires without a pathfinding loop")

fresh(); z = makeZombie(); zombies = {z}; shout(); step()
z.x, z.y = 0.5, 0.5; step(); z.x, z.path.x = 20, 80; step()
check(z.calls == 1, "arrival releases the task")

fresh(); z = makeZombie(); zombies = {z}; shout()
Events.OnZombieDead.fire(z); step()
check(z.calls == 0, "death clears pending tasks")
shout(); Events.OnZombieCreate.fire(z); step()
check(z.calls == 0, "pooled zombie does not inherit a task")
shout(); z.square = nil; step(); z.square = square(); step()
check(z.calls == 0, "unloaded zombie releases task")

fresh(); z = makeZombie(); z.crawling, z.onFloor = true, true; zombies = {z}
shout(); step()
check(z.calls == 1, "crawlers can investigate")

fresh(); z = makeZombie(); z.state = "eatbody"; z.eating = {}; zombies = {z}
shout(); step()
check(z.calls == 1 and z.eating == nil, "eating can be interrupted by the shout")

fresh(); z = makeZombie(); zombies = {z}; Events.OnGameStart.fire()
Events.OnKeyPressed.fire(16); step()
check(z.calls == 1 and players[0].callouts == 1, "Q wrapper preserves the original action exactly once")
radialOpen = true; Events.OnKeyPressed.fire(16); step()
check(z.calls == 1, "opening the emote menu is not a shout")
ISEmoteRadialMenu.emote({character = players[0]}, "wavehi"); step()
check(z.calls == 1, "ordinary emote is not a shout")
players[0].x = 2
ISEmoteRadialMenu.emote({character = players[0]}, "shout"); step()
check(z.calls == 2, "radial shout is captured")
players[0].x = 4
ISDPadWheels.onShout(players[0]); step()
check(z.calls == 3, "controller shout is captured")
local vehicle = makeVehicle(players[0]); vehicle.x = 6
Events.OnKeyPressed.fire(99); step()
check(z.calls == 4 and z.path.x == 6.5 and vehicle.starts == 1, "manual horn captures the vehicle as sound source")
Events.OnWorldSound.fire(0, 0, 0, 150, 150, vehicle); step()
check(z.calls == 4 and z.path.x == 6.5, "vehicle alarm outside a manual horn action stays vanilla")

local ok = pcall(function() BR.capture(players[0], function() error("expected") end) end)
Events.OnWorldSound.fire(0, 0, 0, 30, 30, players[0]); step()
check(not ok and z.calls == 4, "capture context is restored after an input-handler error")

fresh(); client = true; z = makeZombie(); z.remote = true; zombies = {z}
shout(); step()
check(z.calls == 0 and #clientMessages == 1, "remote zombies are not mutated")
z.remote = false; step()
check(z.calls == 0, "local ownership still waits for the server to accept the shout")
BR.onServerCommand(BR.MODULE, "shout", {x=0,y=0,z=0,radius=30,source=1,sequence=9}); step()
check(z.calls == 1, "server confirmation applies the local player's shout")
BR.onServerCommand(BR.MODULE, "shout", {x=3,y=0,z=0,radius=30,source=2,sequence=10}); step()
check(z.calls == 2 and z.path.x == 3.5, "another player's shout reaches local owner")
BR.onServerCommand(BR.MODULE, "shout", {x=9,y=0,z=0,radius=30,source=2,sequence=10}); step()
check(z.calls == 2, "duplicate network message is ignored")
BR.onServerCommand(BR.MODULE, "shout", {x=9,y=0,z=0,radius=30,source=3,sequence=9}); step()
check(z.calls == 2 and z.path.x == 3.5, "older server messages cannot replace a newer shout from another player")
step(9.8)
BR.onServerCommand(BR.MODULE, "shout", {x=3,y=0,z=0,radius=30,source=2,sequence=10})
step(0.3); z.path.x = 80; step(0.3)
check(z.calls == 2, "duplicate confirmation does not renew the stall timer")

local function clientGoal(id, firstSource, remote)
    fresh(); client = true
    players[0] = makePlayer(id)
    players[0].x = id == 1 and 0 or 3
    local zombie = makeZombie()
    zombie.remote = remote
    zombies = {zombie}
    shout(); step()
    local sources = {firstSource, 3 - firstSource}
    for order, source in ipairs(sources) do
        BR.onServerCommand(BR.MODULE, "shout", {
            x = source == 1 and 0 or 3, y = 0, z = 0,
            radius = 30, source = source, sequence = order,
        })
        step()
    end
    zombie.remote = false; step()
    return zombie.path.x
end
for firstSource = 1, 2 do
    local goalA = clientGoal(1, firstSource, false)
    local goalB = clientGoal(2, firstSource, true)
    local expected = firstSource == 1 and 3.5 or 0.5
    check(goalA == expected and goalB == expected,
        "both clients preserve server order, including own shouts and ownership transfer")
end
local function shoutItem(multiplier, megaphone)
    return {
        hasTag = function(_, tag) return megaphone and tag == ItemTag.MEGAPHONE end,
        getShoutType = function() return "Whistle" end,
        getShoutMultiplier = function() return multiplier end,
    }
end
for _, slot in ipairs({"primary", "secondary", "worn"}) do
    local player = fresh()
    local item = shoutItem(2)
    if slot == "worn" then player.worn = {{getItem = function() return item end}}
    else player[slot] = item end
    local near, far = makeZombie(50), makeZombie(65)
    zombies = {near, far}; shout(); step()
    check(near.calls == 1 and far.calls == 0, "native shout item multiplier in " .. slot)
end
local player = fresh()
player.primary, player.secondary = shoutItem(2), shoutItem(5)
check(BR.shoutRadius(player) == 60, "primary shout item wins; multipliers are not stacked")
player.primary, player.sneaking = shoutItem(5, true), true
z = makeZombie(16); zombies = {z}; shout(); step()
check(BR.shoutRadius(player) == 18 and z.calls == 1,
    "megaphone whisper uses native eighteen tiles, without the item's shout multiplier")
player = fresh(); local vehicle = makeVehicle(player); zombies = {makeZombie()}
local ok = pcall(function() BR.captureHorn(player, function() error("expected") end) end)
vehicle:onHornStart(); step()
check(not ok and zombies[1].calls == 0, "horn capture context restores after callback error")
player = fresh(); vehicle = makeVehicle(player)
local normal, poor = makeZombie(100), makeZombie(100)
poor.hearing = 0.45; zombies = {normal, poor}
ISVehicleMenu.onHornStart(player); step()
check(normal.calls == 1 and poor.calls == 0, "manual horn still respects individual native hearing")
print("Better Reactions behavior checks: " .. checks)
server = true
