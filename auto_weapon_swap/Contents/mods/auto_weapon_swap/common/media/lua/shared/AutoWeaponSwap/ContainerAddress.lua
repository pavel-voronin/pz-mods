AutoWeaponSwapAddress = {}
local Address = AutoWeaponSwapAddress

function Address.integer(value)
    return type(value) == "number" and value == value and value > -2147483648
        and value < 2147483647 and value == math.floor(value)
end

function Address.of(container)
    if not container or container:getContainingItem() or container:getType() == "floor" then return nil end
    local part = container:getVehiclePart()
    if part then
        local vehicle = part:getVehicle()
        if not vehicle or part:getItemContainer() ~= container then return nil end
        return {kind = "vehicle", vehicle = vehicle:getId(), part = part:getId(), containerType = container:getType()}
    end
    local owner = container:getParent()
    local square = owner and owner:getSquare()
    if not square then return nil end
    local corpse = instanceof(owner, "IsoDeadBody")
    local objectIndex = corpse and owner:getStaticMovingObjectIndex() or owner:getObjectIndex()
    if objectIndex < 0 then return nil end
    local index = owner:getContainerIndex(container)
    if index < 0 then return nil end
    local sprite = owner:getSprite()
    return {kind = corpse and "corpse" or "object", x = square:getX(), y = square:getY(), z = square:getZ(),
        index = objectIndex, containerIndex = index, containerType = container:getType(),
        objectName = owner:getObjectName(), sprite = sprite and sprite:getName() or ""}
end

function Address.same(a, b)
    if not a or not b then return false end
    for _, key in ipairs({"kind", "vehicle", "part", "containerType", "x", "y", "z",
        "index", "containerIndex", "objectName", "sprite"}) do
        if a[key] ~= b[key] then return false end
    end
    return true
end

function Address.resolve(args)
    if type(args) ~= "table" then return nil end
    local container, owner, part
    if args.kind == "vehicle" then
        if not Address.integer(args.vehicle) or type(args.part) ~= "string" then return nil end
        local vehicle = getVehicleById(args.vehicle)
        part = vehicle and vehicle:getPartById(args.part)
        owner = part
        container = part and part:getItemContainer()
    elseif args.kind == "object" or args.kind == "corpse" then
        for _, key in ipairs({"x", "y", "z", "index", "containerIndex"}) do
            if not Address.integer(args[key]) then return nil end
        end
        if args.index < 0 or args.containerIndex < 0 then return nil end
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        if not square then return nil end
        local objects = args.kind == "corpse" and square:getStaticMovingObjects() or square:getObjects()
        if args.index >= objects:size() then return nil end
        owner = objects:get(args.index)
        if args.containerIndex >= owner:getContainerCount() then return nil end
        container = owner:getContainerByIndex(args.containerIndex)
    end
    if not Address.same(args, Address.of(container)) then return nil end
    return container, owner, part
end
