-- Native animal fixtures owned only by the disposable external scenario.
local Animals={}
function Animals.clear(c)
    for _,body in ipairs(c.nativeAnimalBodies or {}) do
        body:removeFromWorld()
        body:removeFromSquare()
    end
    c.nativeAnimalBodies=nil
    c.nativeAnimalDeaths=nil
    for _,animal in ipairs(c.nativeAnimals or {}) do
        animal:removeFromWorld()
        animal:removeFromSquare()
    end
    c.nativeAnimals=nil
end
Animals.command={
    validate=function(s)
        assert(s.all==true and s.type==nil or s.all==nil and type(s.type)=="string" and #s.type>0,"Choose all=true or an animal type")
        if s.type then
            for _,key in ipairs({"dx","dy"}) do assert(type(s[key])=="number" and s[key]%1==0 and math.abs(s[key])<=12,"Invalid animal offset") end
            assert(s.dx*s.dx+s.dy*s.dy>=4,"Animal must spawn at least two tiles away")
        end
    end,
    start=function(c,s)
        assert(getCore():isNoSave(),"Animals require a disposable NoSave world")
        Animals.clear(c)
        c.nativeAnimals={}
        local defs=getAllAnimalsDefinitions()
        assert(defs:size()>0 and defs:size()<=128,"Invalid animal definition count")
        for i=0,defs:size()-1 do
            local def=defs:get(i)
            if s.all or def:getAnimalType()==s.type then
            local breeds=def:getBreeds()
            assert(breeds:size()>0,"Animal has no breeds: "..def:getAnimalType())
            local x=math.floor(c.player:getX())-6+(i%7)*2
            local y=math.floor(c.player:getY())-4-math.floor(i/7)*3
            if s.type then x=math.floor(c.player:getX())+s.dx;y=math.floor(c.player:getY())+s.dy end
            local square=getCell():getGridSquare(x,y,math.floor(c.player:getZ()))
            assert(square and square:getFloor() and square:isFree(false),"Animal fixture needs clear ground at "..x..","..y)
            local animal=addAnimal(getCell(),x,y,square:getZ(),def:getAnimalType(),breeds:get(0),false)
            assert(animal,"Animal creation failed: "..def:getAnimalType())
            table.insert(c.nativeAnimals,animal)
            animal:addToWorld()
            c.event("native-animal",def:getAnimalType().." breed="..breeds:get(0):getName().." x="..x.." y="..y)
            end
        end
        assert(#c.nativeAnimals>0,"Unknown native animal type")
    end
}
Animals.kill={
    start=function(c)
        assert(getCore():isNoSave(),"Animal death requires a disposable NoSave world")
        assert(c.nativeAnimals and #c.nativeAnimals>0,"Spawn native.animals first")
        assert(not c.nativeAnimalDeaths,"Fixture animals already killed")
        c.nativeAnimalDeaths={};c.nativeAnimalBodies={}
        for _,animal in ipairs(c.nativeAnimals) do
            assert(not animal:isDead(),"Fixture animal already dead")
            local death={x=animal:getX(),y=animal:getY(),z=animal:getZ(),inventory=animal:getInventory(),type=animal:getAnimalType()}
            table.insert(c.nativeAnimalDeaths,death)
            animal:setHealth(0)
            animal:killed(c.player)
            c.event("native-animal-killed",death.type.." x="..death.x.." y="..death.y)
        end
    end,
    tick=function(c)
        local ready=true
        for _,death in ipairs(c.nativeAnimalDeaths) do
            if not death.body then
                for x=math.floor(death.x)-2,math.floor(death.x)+2 do
                    for y=math.floor(death.y)-2,math.floor(death.y)+2 do
                        local sq=getCell():getGridSquare(x,y,math.floor(death.z))
                        if sq then
                            local objects=sq:getStaticMovingObjects()
                            for i=0,objects:size()-1 do
                                local body=objects:get(i)
                                if instanceof(body,"IsoDeadBody") and body:getContainer()==death.inventory then
                                    death.body=body;table.insert(c.nativeAnimalBodies,body)
                                    c.event("native-animal-corpse",death.type.." x="..body:getX().." y="..body:getY())
                                end
                            end
                        end
                    end
                end
            end
            if not death.body then ready=false end
        end
        return ready
    end
}
ModStudioScenarioAnimals=Animals
return Animals
