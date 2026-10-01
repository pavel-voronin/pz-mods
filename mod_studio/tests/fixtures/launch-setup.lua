require=function() end
getDebug=function() return DEBUG end
UIFont={Large=1}
UIManager={isModalVisible=function() return false end}
Events={}
for _,name in ipairs({'OnGameBoot','OnMainMenuEnter','OnNewGame','OnGameStart'}) do
    local event={handlers={}}
    event.Add=function(fn) table.insert(event.handlers,fn) end
    event.fire=function(...) for _,fn in ipairs(event.handlers) do fn(...) end end
    Events[name]=event
end
core={noSave=false}
function core:isNoSave() return self.noSave end
function core:setNoSave(v) self.noSave=v end
function core:getScreenWidth() return 1920 end
function core:getScreenHeight() return 1080 end
function core:setSelectedMap(v) self.selectedMap=v end
function core:getGameMode() return world.mode end
getCore=function() return core end
local random=0
ZombRand=function(n) random=random+1;return random%n end
getFileSeparator=function() return '/' end
checkSaveFolderExists=function(name) return name=='Sandbox/ModStudio-1-2' end
world={mode='Apocalypse',map='DEFAULT',name='old',traits={}}
for _,pair in ipairs({{'GameMode','mode'},{'Map','map'},{'World','name'},{'Preset','preset'}}) do
    local suffix,key=pair[1],pair[2]
    world['set'..suffix]=function(self,value) self[key]=value end
    world['get'..suffix]=function(self) return self[key] end
end
function world:setLuaPlayerDesc(desc) self.desc=desc end
function world:getLuaTraits() return {clear=function() world.traits={} end} end
function world:addLuaTrait(trait) table.insert(self.traits,trait) end
function world:setLuaPosX(v) self.x=v end
function world:setLuaPosY(v) self.y=v end
function world:setLuaPosZ(v) self.z=v end
getWorld=function() return world end
CharacterProfession={UNEMPLOYED={getName=function() return 'unemployed' end}}
function freshDesc()
    return {getCharacterProfession=function(self) return self.profession end,
        setProfessionSkills=function(self,p) self.skills=p end,
        setCharacterProfession=function(self,p) self.profession=p end}
end
SurvivorFactory={CreateSurvivor=freshDesc}
MapGroups={new=function() return {
    createGroups=function() end,getNumberOfGroups=function() return 2 end,
    setWorld=function(self,n) world.map=n==0 and 'Other world' or 'Kentucky' end}
end}
SpawnRegionMgr={getSpawnRegions=function() return world.map=='Kentucky' and regions or {} end}
regions={{name='Rosewood, KY',points={unemployed={{posX=8123,posY=11742,posZ=0}}}}}
setSpawnRegion=function(name) spawnName=name end
SandboxOptions={new=function()
    return {loadPresetFile=function(self,name)
        if name~='New Rising' then return false end
        self.zombies=5;self.vehicles=true;return true
    end}
end}
options={zombies=4}
function options:newCopy() return {zombies=self.zombies,vehicles=self.vehicles} end
function options:copyValuesFrom(other) self.zombies=other.zombies;self.vehicles=other.vehicles end
function options:toLua() SandboxVars={Zombies=self.zombies} end
getSandboxOptions=function() return options end
local mods={copyFrom=function(self,source) modsCopied=source end}
ActiveMods={getById=function() return mods end}
local Widget={}
Widget.__index=Widget
function Widget:new(x,y,w,h)
    return setmetatable({x=x,y=y,width=w,height=h,visible=true,children={}},self)
end
function Widget:getX() return self.x end
function Widget:getY() return self.y end
function Widget:getWidth() return self.width end
function Widget:getHeight() return self.height end
function Widget:setX(x) self.x=x end
function Widget:setY(y) self.y=y end
function Widget:setVisible(v) self.visible=v end
function Widget:getIsVisible() return self.visible end
function Widget:addChild(child) table.insert(self.children,child);child.parent=self end
function Widget:initialise() end
function Widget:setTooltip(t) self.tooltip=t end
function Widget:setNameWithoutMoving(t) self.name=t;self.width=#t*12 end
function Widget:setColor(r,g,b) self.r=r;self.g=g;self.b=b end
function Widget:isMouseOver() return false end
ISLabel=setmetatable({}, {__index=Widget});ISLabel.__index=ISLabel
function ISLabel:new(x,y,h,text)
    local label=Widget.new(self,x,y,#text*12,h);label.name=text;return label
end
function ISLabel:prerender() end
ISModalDialog={new=function(self,x,y,w,h,message)
    errorMessage=message
    return {initialise=function() end,addToUIManager=function() end,setAlwaysOnTop=function() end}
end}
MainScreen=setmetatable({}, {__index=Widget});MainScreen.__index=MainScreen
function MainScreen:instantiate()
    self.bottomPanel=Widget:new(100,300,350,500);self.bottomPanel.parent=self
    self.bottomPanel.setVisible=MainScreen.setBottomPanelVisible
    self.survivalOption=Widget:new(0,100,350,32)
end
function MainScreen:prerender() end
function MainScreen:setBottomPanelVisible(v) self.visible=v end
function MainScreen:setDefaultSandboxVars() options.zombies=4;options.vehicles=false end
NewGameScreen={clickPlay=function(self)
    nativeNewSaveMode=core.noSave
    MainScreen.instance.bottomPanel:setVisible(false)
end}
CharacterCreationMain={}
CharacterCreationProfession={}
MapSpawnSelect={}
JoypadState={getMainMenuJoypad=function() end}
CoopCharacterCreation={getJoypad=function() end}
isClient=function() return false end
isDemo=function() return false end
GameWindow={doRenderEvent=function() end}
LoadingQueueState={new=function() return 'loading' end}
forceChangeState=function(state) loadingState=state;CharacterCreationProfession.initWorld() end
createWorld=function(name) createdName=name;createdSaveMode=core.noSave;createdCount=(createdCount or 0)+1 end
function makeScreen()
    local screen=MainScreen:new(0,0,1920,1080)
    screen.inGame=false;screen.delay=0;screen.desc=freshDesc()
    screen:instantiate()
    screen.mapSpawnSelect={generateNewSeed=function() seedGenerated=true end,saveGenParams=function() seedSaved=true end}
    MapSpawnSelect.instance=screen.mapSpawnSelect
    screen.sandOptions={settingsToUI=function(self,value) self.value=value end,
        setSandboxVars=function(self) options:copyValuesFrom(self.value);options:toLua() end}
    screen.charCreationMain=setmetatable({setVisible=function() end,
        createAvatar=function() avatarCreated=true end,
        onRandomCharacter=function() randomized=true end,
        initPlayer=function() playerInitialized=true end,disableBtn=function() end}, {__index=CharacterCreationMain})
    screen.charCreationProfession={listboxTraitSelected={items={{item={getType=function() return 'stale' end}}}},
        getSelectedProf=function() return 'unemployed-definition' end,
        resetBuild=function(self) self.listboxTraitSelected.items={};buildReset=true end,
        onOptionMouseDown=function(self) screen.charCreationMain:setVisible(true) end,
        setVisible=function() end}
    CharacterCreationProfession.instance=screen.charCreationProfession
    MainScreen.instance=screen
    return screen
end

function MainScreen:removeChild(child)
    for i,v in ipairs(self.children) do if v==child then table.remove(self.children,i);return end end
end
settingsFile=nil
getFileReader=function(path)
    assert(path=='ModStudio/settings.ini')
    if not settingsFile then return nil end
    local read=false
    return {readLine=function() if not read then read=true;return settingsFile:gsub("\n","") end end,close=function() end}
end
getFileWriter=function(path)
    assert(path=='ModStudio/settings.ini')
    if failWrite then return nil end
    return {write=function(self,text) settingsFile=text end,close=function() end}
end
-- The game exposes instanceItem globally, not InventoryItemFactory.
instanceItem=function(id)
    if id=='Missing.Item' then return nil end
    return {type=id, getMaxAmmo=function() return 4 end,
        setCurrentAmmoCount=function(self,n) self.ammo=n end,
        getBodyLocation=function() return 'LeftWrist' end}
end
player={items={'vanilla-starter'}, worn={}}
function player:getInventory() return {AddItem=function(self,item) table.insert(player.items,item);return item end} end
function player:setWornItem(location,item) self.worn[location]=item end
getPlayer=function() return player end
