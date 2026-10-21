-- Bounded native zombie fixtures owned by the disposable external scenario.
local Zombies={}
function Zombies.clear(c)
    for _,zombie in ipairs(c.nativeZombies or {}) do
        zombie:removeFromWorld()
        zombie:removeFromSquare()
    end
    c.nativeZombies=nil;c.nativeZombieExpected=nil
end
Zombies.command={
    validate=function(s)
        assert(type(s.count)=="number" and s.count%1==0 and s.count>=1 and s.count<=12,"Zombie count must be 1..12")
        for _,key in ipairs({"dx","dy"}) do
            assert(type(s[key])=="number" and s[key]%1==0 and math.abs(s[key])<=12,"Invalid zombie offset")
        end
        assert(s.dx*s.dx+s.dy*s.dy>=4,"Zombies must spawn at least two tiles away")
        for _,key in ipairs({"crawler","onFire"}) do assert(s[key]==nil or type(s[key])=="boolean","Invalid zombie "..key) end
    end,
    start=function(c,s)
        assert(getCore():isNoSave(),"Zombies require a disposable NoSave world")
        Zombies.clear(c)
        c.nativeZombies={}
        c.nativeZombieExpected={crawler=s.crawler==true,onFire=s.onFire==true}
        for i=1,s.count do
            local x=math.floor(c.player:getX())+s.dx+(i-1)%3
            local y=math.floor(c.player:getY())+s.dy+math.floor((i-1)/3)
            local z=math.floor(c.player:getZ())
            local square=getCell():getGridSquare(x,y,z)
            assert(square and square:getFloor() and square:isFree(false),"Zombie fixture needs clear ground at "..x..","..y)
            -- Native god mode extinguishes burning characters; fire fixtures use normal health.
            local result=addZombiesInOutfit(x,y,z,1,nil,50,s.crawler==true,false,false,false,s.onFire~=true,false,1,false,0,false,s.onFire==true)
            assert(result and result:size()==1,"Native zombie creation failed")
            local zombie=result:get(0)
            table.insert(c.nativeZombies,zombie)
            c.event("native-zombie","x="..x.." y="..y.." crawler="..tostring(s.crawler==true).." fire="..tostring(s.onFire==true))
        end
    end,
    tick=function(c)
        local expected=assert(c.nativeZombieExpected,"Zombie fixture not started")
        for _,zombie in ipairs(c.nativeZombies) do
            if zombie:isCrawling()~=expected.crawler or zombie:isOnFire()~=expected.onFire then return false end
        end
        c.event("native-zombies-ready","count="..#c.nativeZombies.." crawler="..tostring(expected.crawler).." fire="..tostring(expected.onFire))
        return true
    end
}
ModStudioScenarioZombies=Zombies
