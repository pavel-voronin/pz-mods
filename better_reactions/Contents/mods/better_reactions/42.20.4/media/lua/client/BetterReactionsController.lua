if isServer() then return end
require "BetterReactionsShared"

local BR = BetterReactions
local tasks = {}
local received = 0
local clock = 0
local sequence = 0
local shoutNumber = 0
local capturePlayer
local captureSource
local readyStates = {
    idle = true, sitting = true, eatbody = true, thump = true,
    pathfind = true, walktoward = true, turnalerted = true,
}

local function hasLivingTarget(zombie)
    local target = zombie:getTarget()
    return target and instanceof(target, "IsoGameCharacter") and target:isAlive()
end

local function exclusion(zombie)
    if not zombie or not zombie:isAlive() then return "dead" end
    if not zombie:getCurrentSquare() then return "unloaded" end
    if zombie:isUseless() then return "useless" end
    if zombie:isReanimatedForGrappleOnly() then return "corpse" end
    if zombie:isFakeDead() then return "fake-dead" end
    if hasLivingTarget(zombie) then return "chasing" end
end

local function log(message)
    if BR.DIAGNOSTICS then print("[Better Reactions] " .. message) end
end

local function describe(zombie)
    local path = zombie:getPathFindBehavior2()
    return string.format("z%d pos=%.1f,%.1f,%.1f state=%s moving=%s pathfind=%s soundGoal=%s goal=%.1f,%.1f,%.1f alpha=%.2f culled=%s",
        zombie:getID(), zombie:getX(), zombie:getY(), zombie:getZ(),
        tostring(zombie:getActionStateName()), tostring(zombie:getVariableBoolean("bMoving")),
        tostring(zombie:getVariableBoolean("bPathfind")), tostring(path:isGoalSound()),
        path:getTargetX(), path:getTargetY(), path:getTargetZ(), zombie:getAlpha(0),
        tostring(zombie:isSceneCulled()))
end

local function trace(zombie, task, reason)
    if not BR.DIAGNOSTICS then return end
    if (task.traces or 0) >= 12 and reason:sub(1, 4) ~= "end-" then return end
    if reason == task.lastReason and clock < (task.nextTrace or 0) then return end
    task.traces = (task.traces or 0) + 1
    task.lastReason, task.nextTrace = reason, clock + 5
    log(string.format("shout=%d %s age=%.2fs %s", task.shout,
        reason, clock - task.created, describe(zombie)))
end

local function canHear(zombie, sound, soundSquare)
    local radius = sound.radius * getWorldSoundManager():getHearingMultiplier(zombie)
    local dx = zombie:getX() - sound.x
    local dy = zombie:getY() - sound.y
    local dz = (zombie:getZ() - sound.z) * 3
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if radius <= 0 then return false, radius, distance end
    local attenuation = distance * distance / (radius * radius)
    if attenuation >= 1 then return false, radius, distance end
    -- Same room penalties as WorldSoundManager.getSoundAttract.
    local square = zombie:getCurrentSquare()
    if soundSquare and square then
        local fromRoom, toRoom = soundSquare:getRoom(), square:getRoom()
        if fromRoom ~= toRoom then
            attenuation = attenuation * 1.2
            if not fromRoom or not toRoom then attenuation = attenuation * 1.4 end
        end
    end
    return attenuation < 1, radius, distance
end

function BR.acceptShout(sound)
    local cell = getCell()
    if not cell or sound.radius <= 0 then return end
    local square = cell:getGridSquare(sound.x, sound.y, sound.z)
    local zombies = cell:getZombieList()
    shoutNumber = shoutNumber + 1
    local heardCount, queuedCount, candidates = 0, 0, {}
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        local heard, radius, distance = canHear(zombie, sound, square)
        local excluded = exclusion(zombie)
        if heard then heardCount = heardCount + 1 end
        if BR.DIAGNOSTICS and distance <= math.max(radius, sound.radius) + 2 then
            candidates[#candidates + 1] = {zombie = zombie, distance = distance,
                radius = radius, heard = heard, excluded = excluded}
        end
        if heard and not excluded then
            queuedCount = queuedCount + 1
            local dx, dy = zombie:getX() - sound.x, zombie:getY() - sound.y
            local expires = clock + math.min(180, 30 + math.sqrt(dx * dx + dy * dy) * 3)
            local task = tasks[zombie]
            if task and task.x == sound.x and task.y == sound.y and task.z == sound.z then
                task.expires = expires
                task.progressAt = clock
                task.shout = shoutNumber
            else
                tasks[zombie] = {
                    x = sound.x, y = sound.y, z = sound.z, expires = expires,
                    progressAt = clock, px = zombie:getX(), py = zombie:getY(),
                    pz = zombie:getZ(), issued = false, nextIssue = clock,
                    created = clock, shout = shoutNumber,
                }
            end
        end
    end
    if BR.DIAGNOSTICS then
        log(string.format("shout=%d at=%d,%d,%d radius=%d loaded=%d heard=%d queued=%d",
            shoutNumber, sound.x, sound.y, sound.z, sound.radius, zombies:size(), heardCount, queuedCount))
        table.sort(candidates, function(a, b) return a.distance < b.distance end)
        for i = 1, math.min(#candidates, 20) do
            local candidate = candidates[i]
            log(string.format("shout=%d heard=%s distance=%.1f effectiveRadius=%.1f excluded=%s %s",
                shoutNumber, tostring(candidate.heard), candidate.distance, candidate.radius,
                candidate.excluded or "no", describe(candidate.zombie)))
        end
    end
end

function BR.onWorldSound(x, y, z, radius, volume, source)
    if not capturePlayer or source ~= captureSource
        or capturePlayer:isDead() or radius <= 0 or volume <= 0 then return end
    local sound = {x = x, y = y, z = z, radius = radius}
    if isClient() then
        sequence = sequence + 1
        sound.sequence = sequence
        sendClientCommand(capturePlayer, BR.MODULE, "shout", sound)
    else
        BR.acceptShout(sound)
    end
end

-- Callout emits OnWorldSound before returning.
local function capture(player, source, callback, ...)
    local previousPlayer, previousSource = capturePlayer, captureSource
    capturePlayer, captureSource = player, source
    local ok, result = pcall(callback, ...)
    capturePlayer, captureSource = previousPlayer, previousSource
    if not ok then error(result) end
    return result
end

function BR.capture(player, callback, ...)
    return capture(player, player, callback, ...)
end

function BR.captureHorn(player, callback, ...)
    if isClient() then return callback(...) end
    return capture(player, player:getVehicle(), callback, ...)
end

local function sameGoal(path, task)
    return path:isGoalSound()
        and math.floor(path:getTargetX()) == task.x
        and math.floor(path:getTargetY()) == task.y
        and math.floor(path:getTargetZ()) == task.z
end

local function updateTask(zombie, task)
    local excluded = exclusion(zombie)
    if excluded then return false, excluded end
    if clock >= task.expires then return false, "expired" end
    if isClient() and zombie:isRemoteZombie() then
        task.issued = false
        task.progressAt = clock
        return true, "waiting-owner"
    end
    local state = zombie:getActionStateName()
    if state == "sitting" then
        if not task.wakeRequested then
            -- Sitting zombies need 'alerted' to start getting up.
            zombie:pathToSound(task.x, task.y, task.z)
            zombie:setLastHeardSound(task.x, task.y, task.z)
            zombie:setTurnAlertedValues(task.x, task.y)
            task.wakeRequested = true
        end
        task.progressAt = clock
        return true, "waking-sitting"
    end
    if not readyStates[state] or zombie:isGettingUp()
        or (zombie:isOnFloor() and not zombie:isCrawling()) then
        task.progressAt = clock
        return true, "waiting-" .. tostring(state)
    end
    local x, y, z = zombie:getX(), zombie:getY(), zombie:getZ()
    local dx, dy = x - task.x - 0.5, y - task.y - 0.5
    if math.floor(z) == task.z and dx * dx + dy * dy <= 0.64 then return false, "arrived" end
    if task.issued and state == "thump" then
        task.progressAt = clock
        return true, "thumping"
    end
    local mx, my = x - task.px, y - task.py
    if mx * mx + my * my > 0.04 or math.abs(z - task.pz) > 0.1 then
        task.px, task.py, task.pz, task.progressAt = x, y, z, clock
    elseif task.issued and clock - task.progressAt > 10 then
        return false, "stalled"
    end
    local path = zombie:getPathFindBehavior2()
    if task.issued and sameGoal(path, task) then
        local stopped = not zombie:getVariableBoolean("bMoving")
            and not zombie:getVariableBoolean("bPathfind")
        if not stopped or state == "turnalerted" or state == "pathfind"
            or clock < task.nextIssue then return true, "following" end
    end
    if clock < task.nextIssue then return true, "waiting-reissue" end
    local first = not task.issued
    if first then
        zombie:setTarget(nil)
        zombie:setThumpTarget(nil)
        zombie:setEatBodyTarget(nil, false)
    end
    zombie:pathToSound(task.x, task.y, task.z)
    zombie:setLastHeardSound(task.x, task.y, task.z)
    if first then
        zombie:faceLocation(task.x, task.y)
    end
    task.issued = true
    task.nextIssue = clock + 0.25
    return true, first and "issued" or "restored"
end

function BR.onTick()
    -- Fast-forward must not shorten the time allowed for pathfinding.
    clock = clock + getGameTime():getRealworldSecondsSinceLastUpdate()
    for zombie, task in pairs(tasks) do
        local keep, reason = updateTask(zombie, task)
        trace(zombie, task, keep and reason or "end-" .. reason)
        if not keep then tasks[zombie] = nil end
    end
end

function BR.forgetZombie(zombie)
    if tasks[zombie] then trace(zombie, tasks[zombie], "end-dead-or-reused") end
    tasks[zombie] = nil
end

function BR.reset()
    tasks, received = {}, 0
    clock, sequence, shoutNumber, capturePlayer = 0, 0, 0, nil
    captureSource = nil
end

function BR.onServerCommand(module, command, args)
    if module ~= BR.MODULE or command ~= "shout" or type(args) ~= "table" then return end
    for _, key in ipairs({"x", "y", "z", "radius", "sequence", "source"}) do
        if not BR.isFinite(args[key]) then return end
    end
    if args.sequence <= received then return end
    received = args.sequence
    BR.acceptShout(args)
end

Events.OnWorldSound.Add(BR.onWorldSound)
Events.OnTick.Add(BR.onTick)
Events.OnZombieDead.Add(BR.forgetZombie)
Events.OnZombieCreate.Add(BR.forgetZombie)
Events.OnGameStart.Add(BR.reset)
Events.OnServerCommand.Add(BR.onServerCommand)
