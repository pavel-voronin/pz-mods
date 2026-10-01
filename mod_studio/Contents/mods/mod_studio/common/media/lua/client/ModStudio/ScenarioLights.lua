if not getDebug() then return end
-- Native fixtures in the disposable scenario world. No renderer-specific state.
ModStudioScenarioLights={}
local M=ModStudioScenarioLights
local function disposable() assert(getCore():isNoSave(),"Light fixtures require the disposable NoSave world") end
function M.clear(c)
    if c.lightFixtures then
        for _,fixture in pairs(c.lightFixtures) do
            if fixture.campfire then SCampfireSystem.instance:removeCampfire(fixture.campfire)
            elseif fixture.object and fixture.object:getSquare() then fixture.object:getSquare():transmitRemoveItemFromSquare(fixture.object) end
        end
        c.lightFixtures=nil
    end
end
M.fixture={
    validate=function(s)
        assert(type(s.id)=="string" and #s.id>0,"lightFixture requires id")
        assert(s.kind=="campfire" or s.kind=="fireplace" or s.kind=="constructed","Invalid light fixture kind")
        assert(type(s.on)=="boolean","lightFixture requires on")
        assert(s.tile==nil or s.kind=="fireplace" and type(s.tile)=="string" and s.tile:match("^[a-z0-9_]+$"),"tile requires a fireplace sprite name")
        for _,key in ipairs({"dx","dy"}) do assert(type(s[key])=="number" and s[key]%1==0 and math.abs(s[key])<=12,"Invalid "..key) end
        assert(s.dx*s.dx+s.dy*s.dy>=4,"Light fixture must be at least two tiles away")
    end,
    start=function(c,s)
        disposable();c.lightFixtures=c.lightFixtures or {}
        local fixture=c.lightFixtures[s.id]
        if not fixture then
            local sq=getCell():getGridSquare(math.floor(c.player:getX())+s.dx,math.floor(c.player:getY())+s.dy,math.floor(c.player:getZ()))
            assert(sq and sq:getFloor() and sq:isFree(false),"Light fixture requires clear loaded ground")
            fixture={kind=s.kind,square=sq};c.lightFixtures[s.id]=fixture
            if s.kind=="campfire" then
                assert(SCampfireSystem and SCampfireSystem.instance,"Native camping system unavailable")
                fixture.campfire=assert(SCampfireSystem.instance:addCampfire(sq),"Campfire creation failed")
                fixture.campfire:setFuel(120)
            elseif s.kind=="fireplace" then
                local sprite=assert(getSprite(s.tile or "fixtures_fireplaces_01_0"),"Fireplace sprite missing")
                fixture.object=IsoFireplace.new(getCell(),sq,sprite)
                sq:AddTileObject(fixture.object);fixture.object:setFuelAmount(120)
            else
                fixture.object=IsoThumpable.new(getCell(),sq,"carpentry_02_59",false,nil)
                local battery=c.player:getInventory():AddItem("Base.Torch")
                assert(battery,"Native torch missing");battery:setUsedDelta(1)
                fixture.object:createLightSource(10,0,4,0,0,"Base.Battery",battery,c.player)
                sq:AddSpecialObject(fixture.object)
                c.player:getInventory():Remove(battery)
            end
        end
        assert(fixture.kind==s.kind,"Fixture kind cannot change")
        if fixture.campfire then
            if s.on then fixture.campfire:lightFire() else fixture.campfire:putOut() end
            fixture.campfire:syncIsoFire();fixture.campfire:saveData()
            assert(fixture.campfire.isLit==s.on,"Campfire state failed")
        elseif s.kind=="fireplace" then fixture.object:setLit(s.on);assert(fixture.object:isLit()==s.on,"Fireplace state failed")
        else fixture.object:toggleLightSource(s.on);assert(fixture.object:isLightSourceOn()==s.on,"Constructed light state failed") end
        c.event("native-light-fixture",s.id.." kind="..s.kind.." on="..tostring(s.on).." x="..fixture.square:getX().." y="..fixture.square:getY())
    end,
    tick=function(c,s)
        if s.kind~="constructed" then return true end
        local source=c.lightFixtures[s.id].object:getLightSource()
        if not source then return false end
        assert(source:isActive()==s.on,"Constructed native source activation mismatch")
        c.event("native-light-source",s.id.." x="..source:getX().." y="..source:getY().." on="..tostring(s.on))
        return true
    end
}
M.equip={
    validate=function(s) assert(s.slot=="primary" or s.slot=="secondary" or s.slot=="none","Invalid equip slot");assert(s.slot=="none" or type(s.id)=="string","equip requires id") end,
    start=function(c,s)
        local item=s.id and c.items[s.id];assert(s.slot=="none" or item,"Unknown item id")
        c.player:setPrimaryHandItem(nil);c.player:setSecondaryHandItem(nil)
        if s.slot=="primary" then c.player:setPrimaryHandItem(item) elseif s.slot=="secondary" then c.player:setSecondaryHandItem(item) end
        c.player:resetEquippedHandsModels()
        c.event("native-equip",s.slot.." "..tostring(s.id))
    end
}
M.weaponLight={
    validate=function(s) assert(type(s.id)=="string" and type(s.on)=="boolean","weaponLight requires id and on") end,
    start=function(c,s)
        disposable();local weapon=assert(c.items[s.id],"Unknown weapon id")
        assert(instanceof(weapon,"HandWeapon"),"weaponLight requires HandWeapon")
        local part=weapon:getActiveLight()
        if not part then part=instanceItem("Base.GunLight");assert(part,"GunLight unavailable");weapon:attachWeaponPart(part) end
        assert(weapon:getActiveLight(),"Native weapon did not accept light")
        weapon:getActiveLight():setCurrentUses(weapon:getActiveLight():getMaxUses());weapon:setActivated(s.on)
        assert(weapon:isEmittingLight()==s.on,"Native weapon light state mismatch")
        c.player:resetEquippedHandsModels();c.event("native-weapon-light",s.id.."="..tostring(s.on))
    end
}
