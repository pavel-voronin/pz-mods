-- Native animal fixtures owned only by the disposable external scenario.
local Animals={}
function Animals.clear(c)
    for _,animal in ipairs(c.nativeAnimals or {}) do
        animal:removeFromWorld()
        animal:removeFromSquare()
    end
    c.nativeAnimals=nil
end
Animals.command={
    validate=function(s)
        assert(s.all==true,"native.animals requires all=true")
    end,
    start=function(c,s)
        assert(getCore():isNoSave(),"Animals require a disposable NoSave world")
        Animals.clear(c)
        c.nativeAnimals={}
        local defs=getAllAnimalsDefinitions()
        assert(defs:size()>0 and defs:size()<=128,"Invalid animal definition count")
        for i=0,defs:size()-1 do
            local def=defs:get(i)
            local breeds=def:getBreeds()
            assert(breeds:size()>0,"Animal has no breeds: "..def:getAnimalType())
            local x=math.floor(c.player:getX())-6+(i%7)*2
            local y=math.floor(c.player:getY())-4-math.floor(i/7)*3
            local square=getCell():getGridSquare(x,y,math.floor(c.player:getZ()))
            assert(square and square:getFloor() and square:isFree(false),"Animal fixture needs clear ground at "..x..","..y)
            local animal=addAnimal(getCell(),x,y,square:getZ(),def:getAnimalType(),breeds:get(0),false)
            assert(animal,"Animal creation failed: "..def:getAnimalType())
            table.insert(c.nativeAnimals,animal)
            animal:addToWorld()
            c.event("native-animal",def:getAnimalType().." breed="..breeds:get(0):getName().." x="..x.." y="..y)
        end
    end
}
ModStudioScenarioAnimals=Animals
return Animals
