-- Explicit collision-free lane fixture in an owned disposable world.
local Route={}
function Route.clear(c) c.nativeRoute=nil end
function Route.update(c)
    local r=c.nativeRoute
    if not r then return end
    local now=c.clock()
    if now<r.next then return end
    assert(getCore():isNoSave(),"Route lane requires disposable NoSave world")
    r.next=now+0.25
    local list=getCell():getZombieList()
    local removed=0
    for i=list:size()-1,0,-1 do
        local z=list:get(i)
        if z:getZ()==r.z and z:getX()>=r.x0 and z:getX()<=r.x1 and z:getY()>=r.y0 and z:getY()<=r.y1 then
            z:removeFromWorld();z:removeFromSquare();removed=removed+1
        end
    end
    if removed>0 then
        r.removed=r.removed+removed
        c.event("native-route-lane","removed="..removed.." total="..r.removed)
    end
end
Route.command={validate=function(s)
    for _,k in ipairs({"x0","y0","x1","y1"}) do
        local v=s[k];assert(type(v)=="number" and v==v and v>=0 and v<=100000,"Invalid lane "..k)
    end
    local w,h=s.x1-s.x0,s.y1-s.y0
    assert(w>0 and h>0 and math.min(w,h)<=12 and math.max(w,h)<=1000,"Lane requires width <=12 and length <=1000")
end,start=function(c,s)
    assert(getCore():isNoSave(),"Route lane requires disposable NoSave world")
    c.nativeRoute={x0=s.x0,y0=s.y0,x1=s.x1,y1=s.y1,z=c.player:getZ(),next=0,removed=0}
    c.event("native-route-lane","bounds="..s.x0..","..s.y0..","..s.x1..","..s.y1)
    Route.update(c)
end}
ModStudioScenarioRoute=Route
return Route
