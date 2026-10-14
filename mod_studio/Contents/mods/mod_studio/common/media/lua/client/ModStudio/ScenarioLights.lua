if not getDebug() then return end
-- Native fixtures in the disposable scenario world. No renderer-specific state.
ModStudioScenarioLights={}
local M=ModStudioScenarioLights
local function disposable() assert(getCore():isNoSave(),"Light fixtures require the disposable NoSave world") end
local gallery
local function galleryClose()
    if gallery then Events.OnTick.Remove(gallery.update);Events.OnMainMenuEnter.Remove(galleryClose);gallery=nil end
end
function M.clear(c)
    galleryClose()
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
    validate=function(s) assert(s.slot=="primary" or s.slot=="secondary" or s.slot=="both" or s.slot=="none","Invalid equip slot");assert(s.slot=="none" or type(s.id)=="string","equip requires id") end,
    start=function(c,s)
        local item=s.id and c.items[s.id];assert(s.slot=="none" or item,"Unknown item id")
        c.player:setPrimaryHandItem(nil);c.player:setSecondaryHandItem(nil)
        if s.slot=="both" then c.player:setPrimaryHandItem(item);c.player:setSecondaryHandItem(item)
        elseif s.slot=="primary" then c.player:setPrimaryHandItem(item) elseif s.slot=="secondary" then c.player:setSecondaryHandItem(item) end
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

-- Native authored street lamp, prepared only in a throwaway world.
M.yard={
    validate=function(s)
        assert(s.radius==nil or type(s.radius)=="number" and s.radius%1==0 and s.radius>=24 and s.radius<=32,"Invalid yard radius")
    end,
    start=function(c,s) disposable();assert(c.definition.manual,"Light yard requires explicit manual setup");c.lightYardPending=true end,
    tick=function(c,s)
        if not c.lightYardPending then return true end
        local cell=getCell();local x,y=math.floor(c.player:getX()),math.floor(c.player:getY());local r=s.radius or 28
        -- Wait for every square before making any changes.
        for xx=x-r,x+r do for yy=y-r,y+r do local sq=cell:getGridSquare(xx,yy,0);if not sq or not sq:getFloor() then return false end end end
        assert(ModStudioScenario.lightYardSources()==0,"Choose an outdoor yard without loaded native sources")
        for xx=x-r,x+r do for yy=y-r,y+r do
            for z=0,3 do
                local sq=cell:getGridSquare(xx,yy,z)
                if sq then
                    local objs=sq:getObjects()
                    for i=objs:size()-1,0,-1 do sq:transmitRemoveItemFromSquare(objs:get(i)) end
                    if z==0 then sq:addFloor("blends_street_01_0") end
                    sq:RecalcAllWithNeighbours(true)
                end
            end
        end end
        local base=cell:getGridSquare(x+2,y,0)
        base:AddTileObject(IsoObject.new(cell,base,"lighting_outdoor_01_16"))
        local top=cell:createNewGridSquare(x+2,y,1,true)
        local lamp=IsoLightSwitch.new(cell,top,getSprite("lighting_outdoor_01_11"),top:getRoomID())
        lamp:addLightSourceFromSprite();top:AddSpecialObject(lamp);lamp:setActivated(true)
        c.yardLamp=lamp;c.lightYardPending=false
        c.event("native-light-yard","lamp="..(x+2)..","..y..",1 clearRadius="..r.." sources="..lamp:getLights():size())
        assert(lamp:getLights():size()==1,"Expected exactly one authored lamp source")
        return true
    end
}

-- A native streamed fixture gallery: stations are re-created when their chunks
-- return. The manual world's fixture lifecycle continues after input handoff.
function M.galleryLayout(x,y)
    local result={}
    for _,id in ipairs({0,1,2,3,5,6,7,8,9,10,11,18,19}) do
        result[#result+1]={tile="lighting_outdoor_01_"..id,base=id>=5 and (id<=7 and "lighting_outdoor_01_4" or "lighting_outdoor_01_16") or nil}
    end
    -- Match native map assemblies: two shaft sections, then the crossarm.
    -- X-facing arms use 88/89/93; Y-facing arms use 94/95/92.
    for id=136,141 do
        local axisX=id==137 or id==138 or id==141
        result[#result+1]={tile="appliances_com_01_"..id,base="appliances_com_01_"..(axisX and 88 or 94),middle="appliances_com_01_"..(axisX and 89 or 95),crossarm="appliances_com_01_"..(axisX and 93 or 92)}
    end
    for i,station in ipairs(result) do
        local row=math.floor((i-1)/5);local column=(i-1)%5
        if row%2==1 then column=4-column end
        station.x=x+column*50;station.y=y+row*50;station.z=station.base and 1 or 0
    end
    return result
end
function M.galleryParts(station)
    if not station.base then return {} end
    return {{tile=station.base,z=0},{tile=station.middle,z=1},{tile=station.crossarm,z=2}}
end
local function galleryClean(g,square)
    if square:getModData().modStudioLampGallery==g.id then return end
    assert(not square:getRoom(),"Lamp gallery requires outdoor squares")
    square:getModData().modStudioLampGallery=g.id
    local objects=square:getObjects()
    for i=objects:size()-1,0,-1 do square:transmitRemoveItemFromSquare(objects:get(i)) end
    if square:getZ()==0 then square:addFloor("blends_street_01_0") end
    square:RecalcAllWithNeighbours(true)
end
local function galleryUpdate()
    local g=gallery;if not g or not getCore():isNoSave() then return end
    local now=ModStudioScenario.clock();if now<(g.next or 0) then return end;g.next=now+.5
    local player=getPlayer();if not player then return end
    local cell=getCell();local px,py=math.floor(player:getX()),math.floor(player:getY())
    -- Clear only the loaded calibration plot. Ordinary native movement is retained.
    if px>=g.x-22 and px<=g.x+222 and py>=g.y-22 and py<=g.y+172 then
        for x=px-4,px+4 do for y=py-4,py+4 do for z=0,3 do
            local square=cell:getGridSquare(x,y,z);if square then galleryClean(g,square) end
        end end end
    end
    for i,station in ipairs(g.stations) do
        if math.abs(station.x-px)<=35 and math.abs(station.y-py)<=35 then
            local top=cell:getGridSquare(station.x,station.y,station.z);local found
            if top then local objects=top:getObjects();for j=0,objects:size()-1 do
                local object=objects:get(j);local sprite=object:getSprite()
                if instanceof(object,"IsoLightSwitch") and sprite and sprite:getName()==station.tile then found=object;break end
            end end
            if not found then
                local ready=true
                for x=station.x-22,station.x+22 do for y=station.y-22,station.y+22 do
                    local square=cell:getGridSquare(x,y,0);if not square or not square:getFloor() then ready=false end
                end end
                if ready then
                    for x=station.x-22,station.x+22 do for y=station.y-22,station.y+22 do for z=0,3 do
                        local square=cell:getGridSquare(x,y,z);if square then galleryClean(g,square) end
                    end end end
                    top=cell:getGridSquare(station.x,station.y,station.z) or cell:createNewGridSquare(station.x,station.y,station.z,true)
                    galleryClean(g,top)
                    for _,part in ipairs(M.galleryParts(station)) do
                        local square=cell:getGridSquare(station.x,station.y,part.z) or cell:createNewGridSquare(station.x,station.y,part.z,true)
                        galleryClean(g,square)
                        local exists=false;local objects=square:getObjects()
                        for j=0,objects:size()-1 do local sprite=objects:get(j):getSprite();if sprite and sprite:getName()==part.tile then exists=true end end
                        if not exists then square:AddTileObject(IsoObject.new(cell,square,part.tile)) end
                    end
                    local lamp=IsoLightSwitch.new(cell,top,assert(getSprite(station.tile)),top:getRoomID())
                    lamp:addLightSourceFromSprite();top:AddSpecialObject(lamp);lamp:setActivated(true)
                    assert(lamp:getLights():size()==1,"Gallery lamp must have exactly one native source")
                    g.created[i]=true
                    if g.workbench then g.workbench.lamp=lamp end
                    print("[mod_studio] Lamp gallery station "..i.." "..station.tile.." at "..station.x..","..station.y..","..station.z)
                end
            end
        end
    end
    local w=g.workbench
    if w and w.pendingSelect and w.lamp and w.lamp:getLights():size()>0 and cell:getLamppostPositions():contains(w.lamp:getLights():get(0)) then
        if PZ3D and PZ3D.emitterDebugSelect then PZ3D.emitterDebugSelect(0) end
        w.pendingSelect=false
    end
end
M.gallery={
    validate=function(s) assert(s.x==nil or type(s.x)=="number" and s.x%1==0 and s.x>=32 and s.x<=99700,"Invalid gallery x");assert(s.y==nil or type(s.y)=="number" and s.y%1==0 and s.y>=32 and s.y<=99700,"Invalid gallery y") end,
    start=function(c,s)
        disposable();assert(c.definition.manual,"Lamp gallery requires explicit manual setup");galleryClose()
        local x,y=s.x or math.floor(c.player:getX())+2,s.y or math.floor(c.player:getY())
        assert(ModStudioScenario.lightYardSources()==0,"Gallery location has unrelated native sources")
        gallery={id=c.output,x=x,y=y,stations=M.galleryLayout(x,y),created={},update=galleryUpdate}
        for i,station in ipairs(gallery.stations) do
            local props=assert(getSprite(station.tile)):getProperties()
            assert(props:has("streetlight") and props:has("LightRadius"),"Gallery sprite is not a native street lamp")
            c.event("native-gallery-station",i.." "..station.tile.." x="..station.x.." y="..station.y.." z="..station.z)
        end
        Events.OnTick.Add(galleryUpdate);Events.OnMainMenuEnter.Add(galleryClose)
    end,
    tick=function() galleryUpdate();return gallery and gallery.created[1]==true end
}

-- One native fixture at a fixed location, switched from the emitter editor.
function M.workbenchState()
    return gallery and gallery.workbench and {index=gallery.workbench.index,count=19} or nil
end
function M.workbenchChoose(delta)
    local g=gallery;assert(g and g.workbench,"Lamp workbench is not active");disposable()
    local w=g.workbench;w.index=((w.index-1+delta)%19)+1
    -- This isolated square belongs entirely to the disposable fixture.
    for z=0,3 do local square=getCell():getGridSquare(g.x,g.y,z)
        if square then local objects=square:getObjects()
            for i=objects:size()-1,0,-1 do local object=objects:get(i);if object~=square:getFloor() then square:transmitRemoveItemFromSquare(object) end end
        end
    end
    local station=M.galleryLayout(g.x,g.y)[w.index];station.x=g.x;station.y=g.y
    g.stations={station};g.created={};g.next=0;w.lamp=nil;w.pendingSelect=true
    galleryUpdate()
    if PZ3D and PZ3D.emitterDebugSelect then PZ3D.emitterDebugSelect(0) end
end
M.workbench={
    validate=M.gallery.validate,
    start=function(c,s)
        M.gallery.start(c,s)
        gallery.stations={gallery.stations[1]};gallery.workbench={index=1}
        c.event("native-lamp-workbench","One fixture; 19 selectable native street lamp variants")
    end,
    tick=M.gallery.tick
}
M.workbenchSelect={
    validate=function(s) assert(type(s.index)=="number" and s.index%1==0 and s.index>=1 and s.index<=19,"Invalid workbench lamp index") end,
    start=function(c,s) M.workbenchChoose(s.index-assert(M.workbenchState(),"Workbench unavailable").index);c.event("native-workbench-selected",tostring(s.index)) end,
    tick=function() return gallery and gallery.workbench and gallery.workbench.lamp and not gallery.workbench.pendingSelect end
}
