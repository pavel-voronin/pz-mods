-- Bounded native-cell evidence and vanilla removal in an owned acceptance world.
local Objects={}
local function integer(s,key,min,max,optional)
    local v=s[key];assert(optional and v==nil or type(v)=="number" and v==v and v%1==0 and v>=min and v<=max,"Invalid "..key)
end
Objects.cell={
    validate=function(s)
        integer(s,"x",0,100000);integer(s,"y",0,100000);integer(s,"z",-32,31,true)
        assert(s.action=="inspect" or s.action=="remove" or s.action=="expect" or s.action=="renderOffset","Invalid cell action")
        integer(s,"radius",0,4,true)
        assert(s.radius==nil or s.action=="inspect","Radius applies only to inspect")
        assert(s.sprite==nil or type(s.sprite)=="string" and #s.sprite>0 and #s.sprite<=256 and string.match(s.sprite,"^[A-Za-z0-9_]+$"),"Invalid sprite")
        if s.action~="inspect" then assert(s.sprite,"Mutation/expect requires exact sprite") end
        if s.action=="expect" then integer(s,"count",0,1024) else assert(s.count==nil,"Count applies only to expect") end
        if s.action=="renderOffset" then assert(type(s.renderYOffset)=="number" and s.renderYOffset==s.renderYOffset and s.renderYOffset>=-96 and s.renderYOffset<=96,"Invalid renderYOffset") else assert(s.renderYOffset==nil,"renderYOffset applies only to renderOffset") end
    end,
    start=function(c,s)
        assert(ModStudioScenario.disposable(),"Cell acceptance requires an owned disposable world")
        local r=s.radius or 0
        for y=s.y-r,s.y+r do for x=s.x-r,s.x+r do
            local square=getCell():getGridSquare(x,y,s.z or 0)
            assert(square,"Cell is not loaded: "..x..","..y)
            local list=square:getObjects();local matches={};local names={}
            for i=0,list:size()-1 do
                local object=list:get(i);local sprite=object:getSprite();local name=sprite and sprite:getName() or ""
                if not s.sprite or name==s.sprite then matches[#matches+1]=object;names[#names+1]=name end
            end
            if s.action=="remove" then
                assert(#matches==1,"Removal requires one exact native object, found "..#matches)
                square:transmitRemoveItemFromSquare(matches[1])
                local remaining=0;for i=0,list:size()-1 do if list:get(i)==matches[1] then remaining=remaining+1 end end
                assert(remaining==0,"Native removal did not remove object")
            elseif s.action=="renderOffset" then
                assert(#matches==1,"Render offset requires one exact native object, found "..#matches)
                local previous=matches[1]:getRenderYOffset()
                matches[1]:setRenderYOffset(s.renderYOffset)
                assert(math.abs(matches[1]:getRenderYOffset()-s.renderYOffset)<.0001,"Native render offset mismatch")
                c.event("native-cell-transform","x="..x.." y="..y.." z="..(s.z or 0).." sprite="..s.sprite.." previousRenderYOffset="..previous.." renderYOffset="..matches[1]:getRenderYOffset())
            elseif s.action=="expect" then assert(#matches==s.count,"Native saved cell count "..#matches..", expected "..s.count) end
            c.event("native-cell",s.action.." x="..x.." y="..y.." z="..(s.z or 0).." count="..#matches.." sprites="..table.concat(names,","))
            if s.action=="inspect" then
                local floor=square:getFloor();local sprite=floor and floor:getSprite();local types={}
                for i=1,#matches do types[i]=tostring(matches[i]:getType()) end
                c.event("native-cell-state","x="..x.." y="..y.." z="..(s.z or 0).." floor="..(sprite and sprite:getName() or "none").." room="..tostring(square:getRoom()~=nil).." outside="..tostring(square:isOutside()).." covered="..(square.haveRoof==nil and "unavailable" or tostring(square.haveRoof)).." stairs="..tostring(square:HasStairs()).." types="..table.concat(types,","))
            end
        end end
    end
}
ModStudioScenarioObjects=Objects
return Objects
