function require() end
server, client, dt, realDt, timestamp = false, false, 1 / 60, 1 / 60, 1000
diagnosticLines = {}
function print(message) diagnosticLines[#diagnosticLines + 1] = tostring(message) end
function isServer() return server end
function isClient() return client end
function getTimestampMs() return timestamp end
function getGameTime() return {
    getTimeDelta = function() return dt end,
    getRealworldSecondsSinceLastUpdate = function() return realDt end,
} end
function instanceof(value, name) return value and value.kind == name end
ItemTag = {MEGAPHONE = "Megaphone"}

Events = setmetatable({}, {__index = function(self, key)
    local callbacks = {}
    local event = {
        Add = function(callback) callbacks[callback] = true end,
        Remove = function(callback) callbacks[callback] = nil end,
        fire = function(...)
            for callback in pairs(callbacks) do callback(...) end
        end,
    }
    rawset(self, key, event)
    return event
end})

function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
function square(room) return {getRoom = function() return room end} end
zombies, players, fromSquare = {}, {}, square()
local cell = {
    getZombieList = function() return list(zombies) end,
    getGridSquare = function() return fromSquare end,
}
function getCell() return cell end
function getSpecificPlayer(i) return players[i] end
function getWorldSoundManager()
    return {getHearingMultiplier = function(_, zombie) return zombie.hearing end}
end

function makePlayer(id)
    local player = {id = id or 1, x = 0, y = 0, z = 0, kind = "IsoGameCharacter"}
    function player:isAlive() return not self.dead end
    function player:isDead() return self.dead end
    function player:isSneaking() return self.sneaking end
    function player:getOnlineID() return self.id end
    function player:getX() return self.x end
    function player:getY() return self.y end
    function player:getZ() return self.z end
    function player:getPrimaryHandItem() return self.primary end
    function player:getSecondaryHandItem() return self.secondary end
    function player:getWornItems() return list(self.worn or {}) end
    function player:getVehicle() return self.vehicle end
    function player:Callout()
        self.callouts = (self.callouts or 0) + 1
        local radius = self.radius or BetterReactions.shoutRadius(self)
        Events.OnWorldSound.fire(self.x, self.y, self.z, radius, radius, self)
    end
    function player:playEmote(name) self.emote = name end
    function player:setJoypadIgnoreAimUntilCentered() end
    return player
end

function makeVehicle(player)
    local vehicle = {kind = "BaseVehicle", x = 0, y = 0, z = 0, battery = 1, driver = player}
    function vehicle:isDriver(candidate) return candidate == self.driver end
    function vehicle:getBatteryCharge() return self.battery end
    function vehicle:onHornStart()
        self.starts = (self.starts or 0) + 1
        if not self.noHorn then
            Events.OnWorldSound.fire(self.x, self.y, self.z, 150, 150, self)
        end
    end
    function vehicle:onHornStop() self.stops = (self.stops or 0) + 1 end
    player.vehicle = vehicle
    return vehicle
end

function makeZombie(x, y)
    local zombie = {
        x = x or 10, y = y or 0, z = 0, hearing = 1, state = "idle",
        square = square(), calls = 0, turns = 0, moving = false,
        path = {x = -1, y = -1, z = -1, goal = "none"},
    }
    function zombie:isAlive() return not self.dead end
    function zombie:getID() return 123 end
    function zombie:getAlpha() return self.culled and 0 or 1 end
    function zombie:isSceneCulled() return self.culled or false end
    function zombie:getCurrentSquare() return self.square end
    function zombie:isUseless() return self.useless end
    function zombie:isReanimatedForGrappleOnly() return self.grapple end
    function zombie:isFakeDead() return self.fakeDead end
    function zombie:getTarget() return self.target end
    function zombie:setTarget(target) self.target = target end
    function zombie:getX() return self.x end
    function zombie:getY() return self.y end
    function zombie:getZ() return self.z end
    function zombie:isRemoteZombie() return self.remote end
    function zombie:getActionStateName() return self.state end
    function zombie:isGettingUp() return self.gettingUp end
    function zombie:isOnFloor() return self.onFloor end
    function zombie:isCrawling() return self.crawling end
    function zombie:setThumpTarget(value) self.thump = value end
    function zombie:setEatBodyTarget(value, force)
        assert(force == false, "setEatBodyTarget requires its boolean argument")
        self.eating = value
    end
    function zombie:getVariableBoolean(name)
        if name == "bMoving" then return self.moving end
        if name == "bPathfind" then return self.pathfinding end
    end
    function zombie:getPathFindBehavior2() return self.path end
    function zombie:pathToSound(tx, ty, tz)
        self.calls = self.calls + 1
        self.path.x, self.path.y, self.path.z = tx + 0.5, ty + 0.5, tz
        self.path.goal, self.moving = "sound", true
    end
    function zombie:setLastHeardSound(x, y, z) self.lastSound = {x, y, z} end
    function zombie:setTurnAlertedValues()
        assert(self.state == "sitting", "walking zombies must not wait for turn animation")
        self.wakes = (self.wakes or 0) + 1
    end
    function zombie:faceLocation() self.turns = self.turns + 1 end
    function zombie.path:isGoalSound() return self.goal == "sound" end
    function zombie.path:getTargetX() return self.x end
    function zombie.path:getTargetY() return self.y end
    function zombie.path:getTargetZ() return self.z end
    return zombie
end

clientMessages, serverMessages = {}, {}
function sendClientCommand(player, module, command, args)
    clientMessages[#clientMessages + 1] = {player, module, command, args}
end
function sendServerCommand(module, command, args)
    serverMessages[#serverMessages + 1] = {module, command, args}
end

ISEmoteRadialMenu = {variants = {}}
function ISEmoteRadialMenu.onKeyReleased(key)
    if key == 16 and not radialOpen then players[0]:Callout() end
end
function ISEmoteRadialMenu:emote(name)
    self.character:playEmote(name)
    if name == "shout" then self.character:Callout() end
end
Events.OnGameStart.Add(function()
    Events.OnKeyPressed.Add(ISEmoteRadialMenu.onKeyReleased)
end)
ISDPadWheels = {onShout = function(player) player:Callout() end}
ISVehicleMenu = {onKeyPressed = function(key)
    if key == 99 and players[0]:getVehicle() then ISVehicleMenu.onHornStart(players[0]) end
end}
function ISVehicleMenu.onHornStart(player)
    local vehicle = player:getVehicle()
    if vehicle:getBatteryCharge() <= 0 then return end
    if isClient() then
        sendClientCommand(player, "vehicle", "onHorn", {state = "start"})
    else
        vehicle:onHornStart()
    end
end
Events.OnKeyPressed.Add(ISVehicleMenu.onKeyPressed)

function fresh()
    BetterReactions.reset()
    server, client, dt, realDt = false, false, 1 / 60, 1 / 60
    diagnosticLines = {}
    zombies, players, fromSquare = {}, {[0] = makePlayer()}, square()
    clientMessages, serverMessages, radialOpen = {}, {}, false
    return players[0]
end
function step(seconds)
    dt = seconds or 1 / 60
    realDt = dt
    Events.OnTick.fire()
end
function shout(player)
    BetterReactions.capture(player or players[0], function() (player or players[0]):Callout() end)
end
checks = 0
function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end
