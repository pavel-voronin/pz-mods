-- Bounded native-cell evidence and vanilla removal in an owned acceptance world.
local Objects={}
local function matches(object,s)
    if s.kind=="tree" then return instanceof(object,"IsoTree") end
    local sprite=object:getSprite();return sprite and sprite:getName()==s.sprite
end
local function integer(s,key,min,max,optional)
    local v=s[key];assert(optional and v==nil or type(v)=="number" and v==v and v%1==0 and v>=min and v<=max,"Invalid "..key)
end
Objects.cell={
    validate=function(s)
        integer(s,"x",0,100000);integer(s,"y",0,100000);integer(s,"z",-32,31,true)
        assert(s.action=="inspect" or s.action=="remove" or s.action=="expect" or s.action=="renderOffset" or s.action=="overlay" or s.action=="expectOverlay","Invalid cell action")
        integer(s,"radius",0,4,true)
        assert(s.radius==nil or s.action=="inspect","Radius applies only to inspect")
        assert(s.sprite==nil or type(s.sprite)=="string" and #s.sprite>0 and #s.sprite<=256 and string.match(s.sprite,"^[A-Za-z0-9_]+$"),"Invalid sprite")
        assert(s.kind==nil or s.kind=="tree" and s.sprite==nil and s.action~="renderOffset" and s.action~="overlay" and s.action~="expectOverlay","Invalid native cell kind")
        if s.action~="inspect" then assert(s.sprite or s.kind=="tree","Mutation/expect requires exact sprite or native tree") end
        if s.action=="expect" then integer(s,"count",0,1024) else assert(s.count==nil,"Count applies only to expect") end
        if s.action=="renderOffset" then assert(type(s.renderYOffset)=="number" and s.renderYOffset==s.renderYOffset and s.renderYOffset>=-96 and s.renderYOffset<=96,"Invalid renderYOffset") else assert(s.renderYOffset==nil,"renderYOffset applies only to renderOffset") end
        if s.action=="overlay" or s.action=="expectOverlay" then
            assert(s.sprite and type(s.overlaySprite)=="string" and #s.overlaySprite<=256 and (s.overlaySprite=="" or string.match(s.overlaySprite,"^[A-Za-z0-9_]+$")),"Exact root and overlay sprite required")
        else assert(s.overlaySprite==nil,"overlaySprite applies only to overlay actions") end
    end,
    start=function(c,s)
        assert(ModStudioScenario.disposable(),"Cell acceptance requires an owned disposable world")
        c.nativeCellRemoval=nil
        local r=s.radius or 0
        for y=s.y-r,s.y+r do for x=s.x-r,s.x+r do
            local square=getCell():getGridSquare(x,y,s.z or 0)
            if not square and s.action=="expect" and s.count==0 and ModStudioScenario.loadedEmptyCell(x,y,s.z or 0) then
                c.event("native-cell","expect x="..x.." y="..y.." z="..(s.z or 0).." count=0 sprites= authority=loaded-empty-cell")
                return
            end
            assert(square,"Cell is not loaded: "..x..","..y)
            local list=square:getObjects();local matches={};local names={}
            for i=0,list:size()-1 do
                local object=list:get(i);local sprite=object:getSprite();local name=sprite and sprite:getName() or ""
                if not s.sprite and not s.kind or Objects.matches(object,s) then matches[#matches+1]=object;names[#names+1]=name end
            end
            if s.action=="remove" then
                assert(#matches==1,"Removal requires one exact native object, found "..#matches)
                if isClient() then
                    -- The vanilla debug destruction menu uses its authoritative MP packet.
                    c.nativeCellRemoval={square=square,object=matches[1],sprite=s.sprite,kind=s.kind}
                    sledgeDestroy(matches[1])
                    c.event("native-cell-remove-request","x="..x.." y="..y.." z="..(s.z or 0).." sprite="..names[1].." kind="..tostring(s.kind))
                    return
                end
                square:transmitRemoveItemFromSquare(matches[1])
                local remaining=0;for i=0,list:size()-1 do if list:get(i)==matches[1] then remaining=remaining+1 end end
                assert(remaining==0,"Native removal did not remove object")
            elseif s.action=="renderOffset" then
                assert(#matches==1,"Render offset requires one exact native object, found "..#matches)
                local previous=matches[1]:getRenderYOffset()
                matches[1]:setRenderYOffset(s.renderYOffset)
                assert(math.abs(matches[1]:getRenderYOffset()-s.renderYOffset)<.0001,"Native render offset mismatch")
                c.event("native-cell-transform","x="..x.." y="..y.." z="..(s.z or 0).." sprite="..s.sprite.." previousRenderYOffset="..previous.." renderYOffset="..matches[1]:getRenderYOffset())
            elseif s.action=="overlay" or s.action=="expectOverlay" then
                assert(#matches==1,"Overlay requires one exact native object, found "..#matches)
                if s.action=="overlay" then matches[1]:setOverlaySprite(s.overlaySprite,false) end
                local overlay=matches[1]:getOverlaySprite();local actual=overlay and overlay:getName() or ""
                assert(actual==s.overlaySprite,"Native overlay mismatch: "..actual..", expected "..s.overlaySprite)
                c.event("native-cell-overlay",s.action.." x="..x.." y="..y.." z="..(s.z or 0).." sprite="..s.sprite.." overlay="..actual)
            elseif s.action=="expect" then assert(#matches==s.count,"Native saved cell count "..#matches..", expected "..s.count) end
            c.event("native-cell",s.action.." x="..x.." y="..y.." z="..(s.z or 0).." count="..#matches.." sprites="..table.concat(names,","))
            if s.action=="inspect" then
                local floor=square:getFloor();local sprite=floor and floor:getSprite();local types={}
                for i=1,#matches do types[i]=tostring(matches[i]:getType()) end
                c.event("native-cell-state","x="..x.." y="..y.." z="..(s.z or 0).." floor="..(sprite and sprite:getName() or "none").." room="..tostring(square:getRoom()~=nil).." outside="..tostring(square:isOutside()).." covered="..(square.haveRoof==nil and "unavailable" or tostring(square.haveRoof)).." stairs="..tostring(square:HasStairs()).." types="..table.concat(types,","))
            end
        end end
    end,
    tick=function(c,s,t)
        local pending=c.nativeCellRemoval;if not pending then return true end
        local objects=pending.square:getObjects()
        for i=0,objects:size()-1 do if Objects.matches(objects:get(i),pending) then return false end end
        c.nativeCellRemoval=nil;c.event("native-cell","remove x="..s.x.." y="..s.y.." z="..(s.z or 0).." count=0 selector="..tostring(s.sprite or s.kind));return true
    end
}
Objects.matches=matches
-- Native four-part fixture. Sprite selection requires actual paired metadata;
-- ToggleDoorActual retains native obstruction, relocation and replacement.
Objects.pairedDoor={
    validate=function(s)
        assert(s.action=="spawn" or s.action=="adopt" or s.action=="open" or s.action=="close" or s.action=="inspect","Invalid paired door action")
        if s.action=="spawn" or s.action=="adopt" then
            integer(s,"x",4,99996);integer(s,"y",4,99996);integer(s,"z",-32,31,true)
            assert(type(s.north)=="boolean","Paired door orientation required")
        end
    end,
    start=function(c,s)
        assert(ModStudioScenario.disposable() and not isClient(),"Paired door fixture requires an owned single-player world")
        if s.action=="adopt" then
            assert(not c.pairedDoor,"Paired door already installed")
            c.pairedDoor={x=s.x,y=s.y,z=s.z or 0,north=s.north}
        end
        if s.action=="spawn" then
            assert(not c.pairedDoor,"Paired door already installed")
            local names
            for _,prefix in ipairs({"fixtures_doors_fences_01_","walls_logs_"}) do
                for begin=0,255 do
                    local selected={}
                    for index=begin,math.min(255,begin+15) do
                        local name=prefix..index;local sprite=getSprite(name)
                        if sprite then
                            local p=sprite:getProperties();local part=tonumber(p:get("DoubleDoor"))
                            if part and part>=1 and part<=4 and not p:has(IsoFlagType.open) and tostring(sprite:getType())==(s.north and "doorN" or "doorW") and not selected[part] then selected[part]=name end
                        end
                    end
                    if selected[1] and selected[2] and selected[3] and selected[4] then names=selected;break end
                end
                if names then break end
            end
            assert(names,"No complete native paired sprite family")
            local cell=getCell();local z=s.z or 0
            for dy=-4,4 do for dx=-4,4 do assert(cell:getGridSquare(s.x+dx,s.y+dy,z),"Paired fixture neighbourhood not loaded") end end
            local fixture={x=s.x,y=s.y,z=z,north=s.north,names=names}
            for part=1,4 do
                local square=cell:getGridSquare(s.x+(s.north and part-1 or 0),s.y-(s.north and 0 or part-1),z)
                local list=square:getObjects();for i=0,list:size()-1 do local object=list:get(i);assert(not instanceof(object,"IsoDoor") and not instanceof(object,"IsoThumpable"),"Paired fixture cell already has a native boundary object") end
            end
            c.pairedDoor=fixture
            for part=1,4 do
                local square=cell:getGridSquare(s.x+(s.north and part-1 or 0),s.y-(s.north and 0 or part-1),z)
                local door=IsoDoor.new(cell,square,getSprite(names[part]),s.north);square:AddSpecialObject(door)
                if part==1 then fixture.master=door end
            end
            c.event("native-paired-door","spawn north="..tostring(s.north).." x="..s.x.." y="..s.y.." sprites="..table.concat(names,","))
        else
            local fixture=assert(c.pairedDoor,"Paired fixture not installed")
            local anchor=assert(getCell():getGridSquare(fixture.x,fixture.y,fixture.z),"Paired master cell not loaded")
            local objects=anchor:getObjects();local master
            for i=0,objects:size()-1 do local object=objects:get(i);if instanceof(object,"IsoDoor") and object:getNorth()==fixture.north and IsoDoor.getDoubleDoorIndex(object)==1 then assert(not master,"Ambiguous paired master");master=object end end
            fixture.master=assert(master,"Native paired master missing")
            if s.action=="open" or s.action=="close" then
                local wanted=s.action=="open"
                if fixture.master:IsOpen()~=wanted then fixture.master:ToggleDoorActual(c.player) end
                assert(fixture.master:IsOpen()==wanted,"Native paired door rejected toggle")
            end
            local open=fixture.master:IsOpen();local positions={}
            for part=1,4 do
                local object=IsoDoor.getDoubleDoorObject(fixture.master,part)
                assert(object and object:IsOpen()==open,"Native paired part state mismatch")
                local square=object:getSquare();positions[#positions+1]=part..":"..square:getX()..","..square:getY()..":"..object:getSprite():getName()
            end
            c.event("native-paired-door",s.action.." open="..tostring(open).." parts="..table.concat(positions,"|"))
        end
    end
}

-- Existing ordinary map door only: no synthetic paired fixture or door creation.
Objects.doorSheet={
    validate=function(s)
        assert(s.action=="inspect" or s.action=="open" or s.action=="close" or s.action=="sheetAdd" or s.action=="sheetOpen" or s.action=="sheetClose" or s.action=="sheetRemove","Invalid door sheet action")
        integer(s,"x",0,99999);integer(s,"y",0,99999);integer(s,"z",-32,31,true)
        if s.action=="sheetAdd" then assert(type(s.inside)=="boolean","Native sheet side required") else assert(s.inside==nil,"Sheet side applies only to sheetAdd") end
    end,
    start=function(c,s)
        assert(ModStudioScenario.disposable() and not isClient(),"Door sheet check requires an owned single-player world")
        local square=assert(getCell():getGridSquare(s.x,s.y,s.z or 0),"Ordinary door cell not loaded")
        local objects=square:getObjects();local door
        for i=0,objects:size()-1 do local object=objects:get(i)
            if instanceof(object,"IsoDoor") then
                local p=object:getSprite():getProperties()
                assert(not p:has("DoubleDoor") and not p:has("GarageDoor"),"Door sheet check requires an ordinary map door")
                assert(not door,"Ambiguous ordinary map door");door=object
            end
        end
        assert(door,"Ordinary map door missing")
        if s.action=="open" or s.action=="close" then local wanted=s.action=="open";if door:IsOpen()~=wanted then door:ToggleDoorActual(c.player) end;assert(door:IsOpen()==wanted,"Native ordinary door rejected toggle") end
            if s.action=="sheetAdd" then
                assert(not door:HasCurtains(),"Native sheet already installed")
                assert(c.player:getInventory():AddItem("Base.Sheet"),"Native sheet item unavailable")
                door:addSheet(s.inside,c.player);assert(door:HasCurtains(),"Native sheet installation rejected")
            elseif s.action=="sheetRemove" then
                door:removeSheet(c.player);assert(not door:HasCurtains(),"Native sheet removal rejected")
            elseif s.action=="sheetOpen" or s.action=="sheetClose" then
                assert(door:HasCurtains(),"Native sheet missing");local wanted=s.action=="sheetOpen"
                if door:isCurtainOpen()~=wanted then door:toggleCurtain() end
                assert(door:isCurtainOpen()==wanted,"Native sheet toggle rejected")
            end
            if string.sub(s.action,1,5)=="sheet" then
                local square=door:getSheetSquare()
                c.event("native-door-sheet",s.action.." present="..tostring(door:HasCurtains()~=nil).." open="..tostring(door:isCurtainOpen()).." square="..(square and square:getX()..","..square:getY() or "none"))
            end

        c.event("native-ordinary-door",s.action.." x="..s.x.." y="..s.y.." sprite="..door:getSprite():getName().." open="..tostring(door:IsOpen()))
    end
}
-- Native construction/destruction on an existing ordinary opening.
Objects.barricade={
    validate=function(s)
        integer(s,"x",0,99999);integer(s,"y",0,99999);integer(s,"z",-32,31,true)
        assert(type(s.opposite)=="boolean","Native barricade side required")
        assert(s.action=="planks" or s.action=="inspect" or s.action=="destroy","Invalid barricade action")
        if s.action=="destroy" then assert(s.count==nil,"Destruction has no plank count") else integer(s,"count",0,4) end
    end,
    start=function(c,s)
        assert(ModStudioScenario.disposable() and not isClient(),"Barricade check requires an owned single-player world")
        local square=assert(getCell():getGridSquare(s.x,s.y,s.z or 0),"Opening cell not loaded")
        local objects=square:getObjects();local opening
        for i=0,objects:size()-1 do local object=objects:get(i)
            if instanceof(object,"IsoDoor") or instanceof(object,"IsoWindow") then
                local p=object:getSprite():getProperties()
                assert(not p:has("DoubleDoor") and not p:has("GarageDoor"),"Ordinary opening required")
                assert(not opening,"Ambiguous native opening");opening=object
            end
        end
        assert(opening,"Native opening missing")
        local side=s.opposite and opening:getOppositeSquare() or opening:getSquare()
        assert(side,"Barricade side not loaded")
        local dir=opening:getNorth() and (s.opposite and IsoDirections.S or IsoDirections.N) or (s.opposite and IsoDirections.E or IsoDirections.W)
        local barricade=IsoBarricade.GetBarricadeOnSquare(side,dir)
        if s.action=="planks" then
            if not barricade and s.count>0 then barricade=assert(IsoBarricade.AddBarricadeToObject(opening,s.opposite),"Native barricade installation rejected") end
            if barricade then
                assert(not barricade:isMetal() and not barricade:isMetalBar(),"Wooden barricade required")
                while barricade:getNumPlanks()<s.count do local before=barricade:getNumPlanks();barricade:addPlank(c.player);assert(barricade:getNumPlanks()==before+1,"Native plank installation rejected") end
                while barricade:getNumPlanks()>s.count do local before=barricade:getNumPlanks();barricade:removePlank(c.player);assert(barricade:getNumPlanks()==before-1,"Native plank removal rejected") end
            end
        elseif s.action=="destroy" then
            assert(barricade,"Native barricade missing")
            local strikes=0
            while not barricade:isDestroyed() and strikes<200 do barricade:WeaponHit(c.player,nil);strikes=strikes+1 end
            assert(barricade:isDestroyed(),"Native barricade destruction rejected")
        end
        barricade=IsoBarricade.GetBarricadeOnSquare(side,dir)
        local count=barricade and barricade:getNumPlanks() or 0
        assert(count==(s.action=="destroy" and 0 or s.count),"Native barricade count mismatch")
        if count==0 then assert(not barricade,"Native empty barricade membership survived") end
        c.event("native-barricade",s.action.." count="..count.." opening="..s.x..","..s.y.." square="..side:getX()..","..side:getY().." direction="..tostring(dir).." sprite="..(barricade and barricade:getSprite():getName() or "none"))
    end
}
ModStudioScenarioObjects=Objects
return Objects
