local screen=makeScreen()
screen:prerender()
local labels=screen.modStudioLaunchLabels
assert(#labels==2 and labels[2].name=='Rising+Vehicles')
assert(labels[1].name=='No Saves' and labels[1].r==0.5 and not core.noSave)
assert(labels[1].x==474 and labels[1].y==400 and labels[2].x>labels[1].x+labels[1].width)
labels[1].onMouseDown();screen:prerender()
assert(labels[1].name=='Saves On' and labels[1].r==1)
assert(settingsFile=='noSave=false\n','toggle persists')
NewGameScreen:clickPlay();assert(nativeNewSaveMode==false)
screen:prerender();assert(not labels[1].visible)
screen.bottomPanel:setVisible(true)
labels[1].onMouseDown();screen:prerender()
NewGameScreen:clickPlay();assert(nativeNewSaveMode==true)
screen.bottomPanel:setVisible(true);assert(not core.noSave,'cancel restores save mode')

ModStudio.Launch.presets[1].sandboxPreset='Missing'
labels[2].onMouseDown()
assert(errorMessage:find('Missing') and not createdName and not core.noSave)
assert(screen.bottomPanel.visible and world.mode=='Apocalypse')
ModStudio.Launch.presets[1].sandboxPreset='New Rising'
ModStudio.Launch.presets[1].spawnRegion='Nowhere'
labels[2].onMouseDown()
assert(errorMessage:find('Nowhere') and not createdName and not core.noSave)
assert(world.mode=='Apocalypse' and options.zombies==4)
ModStudio.Launch.presets[1].spawnRegion='Rosewood, KY'
errorMessage=nil
labels[2].onMouseDown()
assert(not errorMessage,errorMessage)
assert(loadingState=='loading' and createdName~='ModStudio-1-2' and createdSaveMode==true)
assert(world.mode=='Sandbox' and world.preset=='New Rising' and options.zombies==5 and options.vehicles)
assert(world.map=='Kentucky','skip unrelated map groups and select the requested spawn region')
assert(world.x==8123 and world.y==11742 and #world.traits==0,'native spawn/traits')
assert(seedGenerated and seedSaved and avatarCreated and randomized and buildReset and playerInitialized)
assert(core.noSave and spawnName=='Rosewood, KY' and core.selectedMap=='Rosewood, KY')
Events.OnNewGame.fire(player)
assert(#player.items==4 and player.items[1]=='vanilla-starter','inventory adds to vanilla items')
assert(player.items[2].ammo==4 and player.items[3].ammo==4,'counts and full ammo')
assert(player.worn.LeftWrist==player.items[4],'native worn body location')
Events.OnNewGame.fire(player)
assert(#player.items==4,'loadout consumed once')
local count=createdCount
labels[2].onMouseDown();assert(createdCount==count,'double click cannot launch twice')
screen.inGame=true;screen.bottomPanel:setVisible(true);screen:prerender()
assert(core.noSave and not labels[1].visible,'pause menu must not re-enable saving')
screen.inGame=false
Events.OnMainMenuEnter.fire();screen:prerender()
assert(not core.noSave and labels[1].visible,'return-to-menu resets engine switch')
labels[1].onMouseDown();screen:prerender()
labels[2].onMouseDown()
assert(createdSaveMode==false and createdCount==count+1,'same shortcut with saving')

Events.OnMainMenuEnter.fire()
ModStudio.Launch.register('other-mod','second',{name='Second',sandboxPreset='New Rising',spawnRegion='Rosewood, KY'})
local second=makeScreen();second:prerender()
assert(#second.modStudioLaunchLabels==3,'one button per configured preset')
second.bottomPanel.x=200;second:prerender()
assert(second.modStudioLaunchLabels[1].x==574,'layout tracks menu movement')
second.inGame=true;second:prerender()
assert(not second.modStudioLaunchLabels[1].visible)

second.inGame=false
ModStudio.Launch.register('other-mod','second',{name='Updated',sandboxPreset='New Rising',spawnRegion='Rosewood, KY'})
second:prerender()
assert(#second.modStudioLaunchLabels==3 and second.modStudioLaunchLabels[3].name=='Updated','replace without duplicate; live menu refresh')
local previous=ModStudio.Settings.noSave
failWrite=true
second.modStudioLaunchLabels[1].onMouseDown()
assert(ModStudio.Settings.noSave==previous and errorMessage:find('Cannot save'),'failed persistence leaves setting unchanged')
failWrite=false
assert(not pcall(ModStudio.Launch.register,'other','bad',{name='Bad',sandboxPreset='New Rising',spawnRegion='Rosewood, KY',inventory={{type='Base.Any',count=-1}}}))
ModStudio.Launch.register('other','invalid-item',{name='Invalid',sandboxPreset='New Rising',spawnRegion='Rosewood, KY',inventory={{type='Missing.Item'}}})
second:prerender()
local before=createdCount
second.modStudioLaunchLabels[4].onMouseDown()
assert(createdCount==before and errorMessage:find('Missing.Item'),'invalid inventory rejected before world creation')
Events.OnNewGame.fire(player)
assert(#player.items==4,'failed/cancelled launch never leaks items')
ModStudio.Settings.setNoSave(false)
ModStudio.Settings=nil
