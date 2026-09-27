-- Kahlua integration harness. Widgets are inert; native calls never reach Steam.
function require() end
UIFont={Small=1,Medium=2,Large=3}
local locale='EN';local fontSet='default'
function getText(k,...)
    local s=(MSTranslations[locale] or {})[k] or ({UI_WorkshopSubmit_ItemTitle='Title',UI_WorkshopSubmit_ItemDescription='Description',UI_WorkshopSubmit_ItemTags='Tags',UI_WorkshopSubmit_ItemVisibility='Visibility',UI_WorkshopSubmit_ItemID='Workshop ID:',UI_btn_back='Back'})[k] or k
    for i,a in ipairs({...}) do s=s:gsub('%%'..i,tostring(a)) end
    return s
end
local tm={}
function tm:getFontHeight(font) return MSMetrics[fontSet][type(font)=='string' and UIFont[font] or font].height end
function tm:getFontFromEnum(font) return {getLineHeight=function() return self:getFontHeight(font) end} end
function tm:MeasureStringX(font,s)
    local f=MSMetrics[fontSet][font];local w=0
    for i=1,#s do w=w+(f.chars[s:sub(i,i)] or f.height) end
    return w
end
function getTextManager() return tm end
function getTexture(path) return {path=path,getWidth=function() return 14 end,getWidthOrig=function() return 14 end,getHeight=function() return 14 end} end
function getTimestampMs() return 1000 end
local mouseX,mouseY=50,50
function getMouseX() return mouseX end;function getMouseY() return mouseY end
local core={screenWidth=1920,screenHeight=1200}
function core:getScreenWidth() return self.screenWidth end;function core:getScreenHeight() return self.screenHeight end
function core:getGameMode() return '' end;function core:getOptionSingleContextMenu() return false end
function core:isDisplayCursor() return true end;function core:setDisplayCursor() end
function getCore() return core end
local playerMenuLookups=0
function getPlayerContextMenu() playerMenuLookups=playerMenuLookups+1;return nil end
JoypadState={players={}}
function table.wipe(t) for k in pairs(t) do t[k]=nil end end
function isSteamOverlayEnabled() return true end
UITransition={new=function() return {setFadeIn=function() end,update=function() end,fraction=function() return 0 end} end}
ISMouseDrag={}
function getSoundManager() return {playUISound=function() end} end
function activateSteamOverlayToWorkshopItem() end
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local tabTextCapture
local Base={}
function Base:derive() local t={};setmetatable(t,{__index=self});t.__index=t;return t end
function Base:new(x,y,w,h)
    local o={x=x or 0,y=y or 0,width=w or 800,height=h or 600,children={},visible=true,text='',items={},selected=1,enabled=true}
    self.__index=self;return setmetatable(o,self)
end
function Base:initialise() end
function Base:instantiate() self.javaObject=true end
function Base:addChild(c) self.children[c]=c;c.parent=self end
function Base:removeChild(c) self.children[c]=nil;c.parent=nil end
function Base:setX(v) self.x=v end;function Base:setY(v) self.y=v end
function Base:setWidth(v) self.width=v end;function Base:setHeight(v) self.height=v end
function Base:getRight() return self.x+self.width end
function Base:getBottom() return self.y+self.height end
function Base:getWidth() return self.width end;function Base:getHeight() return self.height end
function Base:getX() return self.x end;function Base:getY() return self.y end
function Base:getYScroll() return self.yScroll or 0 end;function Base:setYScroll(v) self.yScroll=v end
function Base:getScrollHeight() return self.scrollHeight or 0 end;function Base:setScrollHeight(v) self.scrollHeight=v end
function Base:getMouseX() return mouseX-self.x end;function Base:getMouseY() return mouseY-self.y-self:getYScroll() end
function Base:isMouseOver() return false end
function Base:isMouseOverScrollBar() return self.mouseOverScrollBar or false end
function Base:addToUIManager() self.inUI=true end;function Base:removeFromUIManager() self.inUI=false end
function Base:bringToTop() end;function Base:setForceCursorVisible(v) self.forceCursorVisible=v end
function Base:noBackground() self.background=false end
function Base:setText(v) self.text=v end;function Base:getText() return self.text end
function Base:setName(v) self.name=v end
function Base:setTitle(v) self.title=v end
function Base:setOnMouseDownFunction(target,callback) self.target=target;self.onmousedown=callback end
function Base:setVisible(v) self.visible=v end
function Base:isVisible() return self.visible end
Base.getIsVisible=Base.isVisible
function Base:setEnable(v) self.enabled=v end;Base.setEnabled=Base.setEnable
function Base:setEditable(v) self.editable=v end
function Base:setFont(v) self.font=v end
function Base:setTextRGBA() end;function Base:addScrollBars() end;function Base:setMultipleLine() end
function Base:render() end;function Base:drawText() end
function Base:drawTextCentre(caption,x,y,r,g,b,a,font)
    if tabTextCapture then tabTextCapture[caption]={r=r,g=g,b=b} end
end
function Base:setStencilRect() end;function Base:clearStencilRect() end
function Base:drawTextureScaledAspect() end
function Base:drawTextureScaled() end
function Base:drawTexture() end;function Base:drawTextRight() end
function Base:drawRect() end;function Base:drawRectBorder() end;function Base:drawSelection() end
Base.drawRectBorderStatic=Base.drawRectBorder
function Base:addOption(v) self.options=self.options or {};self.options[#self.options+1]=v end
function Base:clear() self.items={};self.selected=1 end
function Base:addItem(text,item) local row={text=text,item=item,height=self.itemheight,index=#self.items+1};self.items[#self.items+1]=row;return row end
function Base:removeItemByIndex(i) table.remove(self.items,i) end
function Base:onJoypadDown() end
ISPanelJoypad=Base:derive();ISScrollingListBox=Base:derive();ISComboBox=Base:derive()
ISPanel=Base;ISUIElement=Base
ISLabel=Base:derive()
function ISLabel:new(x,y,h,text) local c=Base.new(self,x,y,80,h);c.name=text;return c end
ISTextEntryBox=Base:derive()
function ISTextEntryBox:new(text,x,y,w,h) local c=Base.new(self,x,y,w,h);c.text=text;return c end
ISButton=Base:derive()
function ISButton:new(x,y,w,h,title,target,callback) local c=Base.new(self,x,y,math.max(w,#title*7),h);c.title=title;c.target=target;c.onclick=callback;return c end
ISTickBox=Base:derive()
function ISTickBox:setSelected(i,v) self.checked=self.checked or {};self.checked[i]=v end
function ISTickBox:isSelected(i) return self.checked and self.checked[i] or false end
ISTabPanel=Base:derive()
function ISTabPanel:new(x,y,w,h) local c=Base.new(self,x,y,w,h);c.tabHeight=22;c.viewList={};return c end
function ISTabPanel:addView(name,p) self:addChild(p);p.y=self.tabHeight;self.viewList[#self.viewList+1]={name=name,view=p};p.visible=#self.viewList==1;if #self.viewList==1 then self.activeView=self.viewList[1] end end
function ISTabPanel:removeView(p) for i=#self.viewList,1,-1 do if self.viewList[i].view==p then table.remove(self.viewList,i) end end;self:removeChild(p) end
function ISTabPanel:activateView(name) for _,v in ipairs(self.viewList) do v.view.visible=v.name==name;if v.name==name then self.activeView=v end end;if self.onActivateView then self.onActivateView(self.target,self) end end
ISModalDialog=Base:derive()
local modal
function ISModalDialog:new(x,y,w,h,text,yesno,target,callback) local c=Base.new(self,x,y,w,h);c.callback=callback;c.target=target;modal=c;return c end
function ISModalDialog:addToUIManager() end
-- NATIVE_WIDGET_GEOMETRY
local function answer(value) local m=modal;modal=nil;m.callback(m.target,{internal=value}) end
local function tabColors(editor)
    tabTextCapture={};editor.languageTabs:render();local colors=tabTextCapture;tabTextCapture=nil;return colors
end
ArrayList={}
function ArrayList.new()
    local l={data={}}
    function l:add(v) self.data[#self.data+1]=v end
    function l:get(i) return self.data[i+1] end
    function l:size() return #self.data end
    function l:contains(v) for _,x in ipairs(self.data) do if x==v then return true end end;return false end
    return l
end
local function list(...) local l=ArrayList.new();for _,x in ipairs({...}) do l:add(x) end;return l end
SteamWorkshopItem={getAllowedTags=function() return list('Build 42','Interface') end}
local function makeTags()
    return MSTagsList:new(0,0,100,100)
end
local tags=makeTags()
local reads,saves={},{}
local function read(id,language)
    local r={id=id,language=language,state='loading',title='Remote '..language,description='Remote description '..language}
    function r:poll() end;function r:getState() return self.state end
    function r:cancel() self.state='cancelled' end
    function r:getTitle() return self.title end;function r:getDescription() return self.description end
    function r:getMetadata() return '' end;function r:getPreviewUrl() return '' end
    function r:getTags() return list('Build 42','Custom tag') end
    function r:getVisibility() return 2 end
    function r:getContentDescriptors() return list(2) end
    function r:getDependencies() return list('12','13') end
    function r:getError() return 'network' end
    reads[#reads+1]=r;return r
end
local function save(kind,...)
    local r={kind=kind,args={...},state='saving'}
    function r:poll() end;function r:getState() return self.state end
    function r:isSlow() return false end;function r:getProgress() return 0 end
    function r:getError() return 'network' end;function r:needsLegalAgreement() return false end
    saves[#saves+1]=r;return r
end
local writes=0
ModStudioJava={isReady=function() return true end,isUploading=function() return false end,readWorkshop=read,
    saveText=function(...) return save('text',...) end,saveSettings=function(...) return save('settings',...) end,
    saveDependencies=function(...) return save('deps',...) end,savePreview=function(...) return save('preview',...) end,
    publishFiles=function(...) return save('files',...) end,clear=function() end,
    importDependencies=function() return list('13','14') end,
    loadEnglish=function() return list('From file','File description') end,
    loadReleaseNotes=function() return 'Fixed\n- Release notes from package' end,
    saveEnglish=function() writes=writes+1 end}
local function asset(path,selectable,folder)
    return {getName=function() return path end,getPath=function() return path end,isSelectable=function() return selectable end,isDirectory=function() return folder end,getReason=function() return 'preview_format' end}
end
ModStudioJava.listAssets=function() return list(asset('preview.png',true),asset('banner.gif',true),asset('code.lua',false)) end
ModStudioJava.previewAnimation=function() return {getState=function() return 'ready' end,getFramePath=function() return 'frame.png' end,getFrameTexture=function() return nil end,close=function() end} end
local previewInfo={getFormat=function() return 'GIF' end,getWidth=function() return 512 end,getHeight=function() return 256 end,getBytes=function() return 40000 end,getUploadError=function() return nil end}
ModStudioJava.previewInfo=function() return previewInfo end
local downloads,previewCopies={},0
ModStudioJava.downloadPreview=function(snapshot)
    local d={state='loading',snapshot=snapshot}
    function d:getState() return self.state end;function d:getError() return 'network' end
    function d:getRenderError() return nil end
    function d:cancel() self.cancelled=true;self.state='cancelled' end
    function d:getInfo() return previewInfo end;function d:getAnimation() return ModStudioJava.previewAnimation() end
    downloads[#downloads+1]=d;return d
end
ModStudioJava.saveWorkshopPreview=function() previewCopies=previewCopies+1;return 'workshop-preview.gif' end
ModStudioJava.scanFiles=function(item)
    return {getState=function() return 'ready' end,getBasis=function() return item:getID() and 'unknown' or 'new' end,
        getComparisonError=function() return 'offline' end,getPhase=function() return 'checking' end,getManifestId=function() return '123' end,getUnchanged=function() return 0 end,
        getFileCount=function() return 1 end,getAdded=function() return 0 end,getModified=function() return 0 end,getRemoved=function() return 0 end,
        getEntries=function() return list('unknown\tmods/code.lua') end,cancel=function() end}
end
local function fileScanFixture(lines,basis,state)
    local counts={added=0,modified=0,removed=0,same=0,unknown=0}
    for _,line in ipairs(lines) do local kind=line:match('^([^\t]+)');counts[kind]=counts[kind]+1 end
    local scan={state=state or 'ready',phase='checking',cancelled=false}
    function scan:getState() return self.state end
    function scan:getBasis() return basis end
    function scan:getFileCount() return #lines-counts.removed end
    function scan:getAdded() return counts.added end
    function scan:getModified() return counts.modified end
    function scan:getRemoved() return counts.removed end
    function scan:getUnchanged() return counts.same end
    function scan:getManifestId() return '123' end
    function scan:getPhase() return self.phase end
    function scan:getComparisonError() return 'manifest_unavailable' end
    function scan:getError() return 'file_changed' end
    function scan:getEntries() return list(unpack(lines)) end
    function scan:cancel() self.cancelled=true end
    return scan
end
ModStudioJava.newPublication=function(...)
    local r=save('new',...);r.state='prepared';r.languages={}
    function r:addLanguage(language,title,description) self.languages[language]={title,description} end
    function r:addDependencies(ids) self.dependencies=ids end
    function r:canRetry() return self.state=='error' end
    function r:getStage() return 'initial' end
    function r:getItemId() return self.args[1]:getID() end
    return r
end
ModStudioJava.publishNew=function(r) r.state='saving';return r end
local item={id='1234567890'}
function item:getID() return self.id end
function item:setID(id) self.id=id end
function item:setTitle(v) self.title=v end;function item:setDescription(v) self.description=v end
function item:setTags(v) self.tags=v end;function item:setVisibilityInteger(v) self.visibility=v end
function item:setChangeNote(v) self.note=v end
function item:getTitle() return 'Local title' end;function item:getDescription() return 'Local description' end
function item:getFolderName() return 'fixture' end;function item:getPreviewImage() return 'C:/preview.png' end
function item:getTags() return list('Interface') end;function item:getVisibilityInteger() return 0 end
WorkshopSubmitScreen=Base:derive()
function WorkshopSubmitScreen:create()
    for i=1,10 do local p=Base:new();self:addChild(p);self['page'..i]=p;p.nextButton=Base:new();p.backButton=Base:new();p.closeButton=Base:new() end
    self.page2.tags=tags;self.page2:addChild(tags)
    self.page1.listbox={items={{item=item}},selected=1}
    self.page7.setFields=function(p) p.item=self.item;p.state=p.item:getID() and 'update' or 'create' end
    self.page7.OnSteamWorkshopItemUpdated=function(p) p.state='done' end
    self.page7.LOG=function() end
end
function WorkshopSubmitScreen:onButtonBack() self.closed=true end
ModStudioJava.begin=function(i) i.begun=true end
ModStudioJava.configure=function(i,mask) i.mask=mask end
ModStudioJava.validate=function() return nil end
ModStudioJava.arm=function(i) i.armed=true;return true end
ModStudioJava.saveId=function(i) i.idSaved=true end

-- MOD_UNDER_TEST

local screen=WorkshopSubmitScreen:new(0,0,1280,720);screen:create()
screen.page1:onButtonNext();local e=screen.page2;local en=e.languages.EN
check(e.changeNote:getText()=='Fixed\n- Release notes from package','publication opens with package release notes')
e.changeNote:setText('Manual edit');e:scanFiles()
check(e.changeNote:getText()=='Manual edit','file refresh preserves edited release notes')
e.changeNote:setText('')
local initialActionCount=#e.actions
check(e.visible and #e.navigation.items==5 and e.activeSection=='Files','native uploader opens Files first with section navigation')
check(#reads==4 and #saves==0,'opening requests all current Steam metadata, never writes')
check(en.title:getText()=='' and e.previewPath==nil,'stale local English and preview are not shown as current Steam data')
check(not e:languageDirty(en),'opening does not implicitly schedule text for upload')
check(not e.sections.Settings.loaded,'settings cannot be saved before snapshot')
for _,r in ipairs(reads) do r.state='loaded' end;e:updateWhenVisible()
check(#downloads==1 and e.sections.Preview.loading and previewCopies==0,'snapshot starts preview download without saving to package')
downloads[1].state='loaded';e:updateWhenVisible()
check(e.remotePreview==downloads[1] and not e.previewDirty and e.previewPath==nil,'Steam preview displayed without scheduling reupload')
local originalPreview=e.remotePreview
e:loadPreview();reads[#reads].state='loaded';e:updateWhenVisible();downloads[#downloads].state='error';e:updateWhenVisible()
check(e.remotePreview==originalPreview and e.sections.Preview.failed,'failed repeat download keeps previous preview')
e:savePreviewFile();check(previewCopies==1 and #saves==0 and not e.previewDirty,'explicit local preview copy does not send Steam changes')
check(e.sections.Settings.loaded and e.sections.Dependencies.loaded,'Steam settings/dependency snapshots applied')
check(tags:isChecked('Custom tag'),'remote tags outside game whitelist preserved')
check(not e:settingsDirty() and not e:dependenciesDirty(),'fresh snapshot has no changes')
check(e.itemTitle=='Remote english','header uses current Workshop title after English load')
e:selectSection('Texts');check(en.title:getText()=='Remote english' and not en.panel.loading,'English is already loaded from Steam when editor opens')
local ru=e:addLanguage('RU','russian');e.languageTabs:activateView('RU')
check(ru.panel.loading and reads[#reads].language=='russian','opening added language starts automatic load')
reads[#reads].state='loaded';e:updateWhenVisible()
check(e.languageTabs.viewList[#e.languageTabs.viewList].name=='+','plus stays last language tab')
check(e.itemTitle=='Remote english','another language does not replace canonical header title')
local oldMenuOK,oldMenuError=pcall(ISContextMenu.get,0,50,50)
check(not oldMenuOK and tostring(oldMenuError):find('hideAndChildren',1,true),'native player menu reproduces main-menu crash')
local oldLookups=playerMenuLookups
local tabs=e.languageTabs;local plusX=tabs:getTabX(#tabs.viewList)+5
tabs:onMouseDown(plusX,5)
check(not e.popup and e.activeLanguage=='RU','pressing plus does not open menu or activate a language')
tabs:onMouseUp(plusX,5);local menu=e.popup
check(menu and #menu.options>0 and e.activeLanguage=='RU','plus opens real menu and returns to previous tab')
menu:prerender();menu:render()
mouseX=menu.x+20;mouseY=menu.y+menu.itemHgt/2;menu:onMouseMove(0,0)
check(menu.mouseOver==1 and menu.options[1].name=='DE','standalone native menu hover works without player')
local readCount=#reads
menu:onMouseUp(20,menu.itemHgt/2)
check(e.popup==menu and e.activeLanguage=='RU' and #reads==readCount,'release that opened popup cannot accidentally select a language')
menu:onMouseDown(20,menu.itemHgt/2)
menu:onMouseUp(20,menu.itemHgt/2)
check(e.languages.DE and e.languages.DE.panel.loading and reads[#reads].language=='german','native menu selection adds language and starts Steam read')
check(not menu.inUI and not menu:isVisible() and e.popup==nil,'native selection closes and removes owned menu')
tabs:onMouseDown(plusX,5);tabs:onMouseUpOutside(plusX,-10)
check(not e.popup and not tabs.plusPressed,'dragging off plus cancels the click')
reads[#reads].state='loaded';e:updateWhenVisible();e.languageTabs:activateView('RU')
e:languageMenu();local oldMenu=e.popup;e:languageMenu()
check(not oldMenu.inUI and e.popup~=oldMenu,'reopening replaces previous menu')
menu=e.popup;menu:onMouseDownOutside(-1,-1)
check(not menu.inUI and not e.popup,'outside click dismisses owned menu')
e:languageMenu();e:selectSection('Settings');check(not e.popup,'changing section closes language menu')
e:selectSection('Texts');e:localAction();menu=e.popup
check(#menu.options==2 and menu.options[1].name==getText('UI_MS_LoadFile'),'local file actions also use standalone menu')
menu:prerender();menu:render();menu:onMouseDownOutside(-1,-1)
check(playerMenuLookups==oldLookups,'editor never accesses absent player context menu')
ru.title:setText('Draft RU');ru.description:setText('Russian draft')
e:updateWhenVisible()
local colors=tabColors(e)
check(colors.RU.r>colors.RU.b and colors.EN.r==colors.EN.b,'changed active language is amber, unchanged language keeps native text color')
check(e.statusBox:getText()=='' and not e.statusBox:isVisible() and e.scopeBox==nil,'editing clears bottom status without unsaved or submission instructions')
check(e.languageHint:isVisible() and e.languageHint.y>e.loadButton.y and e.languageHint:getBottom()<=e.sections.Texts.y,'fallback hint is between load controls and text tabs')
local beforeSwitch=#reads
e.languageTabs:activateView('EN');colors=tabColors(e)
check(colors.RU.r>colors.RU.b,'inactive language tab preserves its unsaved color')
e.languageTabs:activateView('RU')
check(ru.description:getText()=='Russian draft' and #reads==beforeSwitch,'language switch retains draft without repeating reads')
local count=#reads;e:loadLanguage(ru);check(modal and #reads==count,'dirty reload waits for confirmation')
answer('NO');check(ru.title:getText()=='Draft RU' and #reads==count,'declining reload preserves draft')
e:loadLanguage(ru);answer('YES');check(#reads==count+1 and ru.panel.loading,'explicit confirmed load starts request')
reads[#reads].state='error';e:updateWhenVisible();check(ru.title:getText()=='Draft RU' and ru.panel.failed,'failed read retains draft')
e:loadLanguage(ru);answer('YES');reads[#reads].state='loaded';e:updateWhenVisible()
check(ru.title:getText()=='Remote russian' and not e:languageDirty(ru),'successful load sets current-language baseline')
ru.title:setText('Edited title');e:saveLanguage(ru)
local sent=saves[#saves];check(sent.kind=='text' and sent.args[2]=='russian' and sent.args[3]=='Edited title' and sent.args[4]==nil,'title-only save omits description')
e:updateWhenVisible();check(not ru.title.editable and not e.backButton.enabled,'submission prevents concurrent edits/closing')
sent.state='error';e:updateWhenVisible();check(e:languageDirty(ru),'failed save retains unsaved draft')
colors=tabColors(e);check(colors.RU.r>colors.RU.b,'failed upload keeps language tab amber')
e:saveLanguage(ru);saves[#saves].state='saved';e:updateWhenVisible();check(not e:languageDirty(ru),'only confirmed success advances baseline')
colors=tabColors(e);check(colors.RU.r==colors.RU.b,'confirmed save restores language tab color')
check(en.title:getText()=='Remote english' and writes==0,'language save does not change English or workshop.txt')
en.title:setText('Changed EN');e:saveLanguage(en);saves[#saves].state='cancelled';e:updateWhenVisible();check(e:languageDirty(en),'cancelled save retains draft')
e:saveEnglish(en);check(writes==1 and e:languageDirty(en),'explicit file save does not claim Steam save')
e:loadEnglish(en);answer('YES');check(en.force and en.title:getText()=='From file','explicit file load can publish both local fields')
e:importDependencies();check(#e.dependencies.items==3,'import unions local known requirements with manual dependencies')
e.dependencies:removeItemByIndex(2);e:saveDependencies();sent=saves[#saves]
check(sent.args[2]=='12\n13' and sent.args[3]=='12\n14','dependency save sends exact baseline and desired list')
sent.state='error';e:updateWhenVisible();check(not e.sections.Dependencies.loaded,'partial failure requires refresh before another dependency save')
e:selectAsset(e.assetRoots[3]);check(e.previewPath==nil and e.remotePreview==originalPreview and not e.previewDirty,'disabled nonimage cannot replace Steam preview')
e:selectAsset(e.assetRoots[2]);check(originalPreview.cancelled,'choosing local image releases old download')
local beforePreviewLoad=#reads;e:loadPreview();check(modal and #reads==beforePreviewLoad,'loading over a selected local preview needs discard confirmation')
answer('NO');check(e.previewPath=='banner.gif' and e.previewDirty,'declining reload preserves local selection')
e:loadPreview();answer('YES');reads[#reads].state='loaded';e:updateWhenVisible();downloads[#downloads].state='error';e:updateWhenVisible()
check(e.previewPath=='banner.gif' and e.previewDirty,'download error also preserves an unsaved local selection')
e:savePreview();sent=saves[#saves];check(sent.kind=='preview' and sent.args[2]=='banner.gif','in-package GIF goes to preview request')
sent.state='saved';e:updateWhenVisible();check(not e.previewDirty and e.previewPath=='banner.gif','successful preview clears dirty state but keeps animation')
e.changeNote:setText('Fix');e:publishFiles();sent=saves[#saves]
check(sent.kind=='files' and sent.args[2]=='Fix','file operation has only item, change note and metadata')
sent.state='saved';e:updateWhenVisible();check(e.changeNote:getText()=='','confirmed file upload clears submitted note')
local oldRequests=#reads;e:setWorkshopItem(item)
check(e.languages.RU==nil and #e.languageTabs.viewList==2,'reopening resets languages to EN and plus; no local persistence')
check(#reads==oldRequests+4 and writes==1,'reopen refreshes all metadata without writing a language list or workshop.txt')
check(#e.actions==initialActionCount,'reopening does not accumulate stale language button callbacks')
for _,pending in ipairs(e.requests) do pending.request.state='loaded' end;e:updateWhenVisible()
local abandonedDownload=e.pendingPreview
-- First publication and retry must not lose drafts in other languages or skip initial metadata.
local fresh=setmetatable({},{__index=item});fresh.id=false
function fresh:getID() return self.id or nil end
screen.item=fresh;e:setWorkshopItem(fresh)
check(abandonedDownload.cancelled and e.pendingPreview==nil,'switching publication cancels pending preview download')
local pendingLanguage=e:addLanguage('DE','german');pendingLanguage.title:setText('Unsaved German')
e:createPublication();sent=e.publication
check(e.visible and sent.kind=='new' and sent.languages.german[1]=='Unsaved German','new publication uses same editor and captures all added language drafts')
fresh.id='222';sent.state='error';e:updateWhenVisible()
check(e.publication==sent and not pendingLanguage.title.editable,'failed initial publication keeps captured plan frozen for retry')
e:publishFiles();check(e.upload.request==sent,'failed initial publication resumes the same request')
sent.state='saved';e:updateWhenVisible()
check(e.languages.DE==pendingLanguage and pendingLanguage.title:getText()=='Unsaved German','first publication preserves language text')
check(not e.publication and not e:languageDirty(pendingLanguage),'successful first upload enters independent editing with saved baselines')
pendingLanguage.title:setText('Another change')
e:onButtonBack();check(modal~=nil,'leaving asks before dropping in-memory drafts');answer('NO')
check(e.sessionOpen,'declining close keeps editing session');e:onButtonBack();answer('YES')
check(not e.sessionOpen and #e.requests==0,'confirmed close cancels all pending reads')
print('PASS: '..checks..' editor assertions; drafts, reads, field omission, separate saves and failures')

-- The same persistent button must dispatch only its visible section.
e:setWorkshopItem(item)
for _,pending in ipairs(e.requests) do pending.request.state='loaded' end;e:updateWhenVisible()
downloads[#downloads].state='loaded';e:updateWhenVisible()
e:selectSection('Texts');en=e.languages.EN
check(e:sourceCaption()==getText('UI_MS_SourceWorkshop'),'current source is the successful remote snapshot')
en.title:setText('One text change');e:updateWhenVisible()
check(e:sourceCaption():find(getText('UI_MS_Unsaved'),1,true),'source and edit status stay independently visible')
e.publishButton.onclick(e);sent=saves[#saves]
check(sent.kind=='text' and sent.args[3]=='One text change' and sent.args[4]==nil,'persistent action sends only current language changes')
sent.state='saved';e:updateWhenVisible()
e:loadEnglish(en);check(e:sourceCaption():find(getText('UI_MS_SourceFile'),1,true),'file load is clearly identified as local')
e:saveEnglish(en);check(e:languageDirty(en),'local save never claims the Workshop draft was sent')
fresh.id=false;e:setWorkshopItem(fresh);e:updateWhenVisible()
e.previewPath=nil;e:selectSection('Settings');e:updateWhenVisible()
check(e.publishButton.parent==e and not e.publishButton.enabled and e.statusBox:getText():find(getText('UI_MS_Preview'),1,true),'new publication action is global and explains missing preview on any section')
e:choosePreview('banner.gif',true);e:selectSection('Preview');e:updateWhenVisible()
e.publishButton.onclick(e)
check(e.publication and e.upload.request==e.publication,'new publication starts from Preview using all sections')
e.upload.request.state='cancelled';e:updateWhenVisible()

-- Verify physical bounds with installed bitmap-font metrics and native widget constructors.
e:setWorkshopItem(item);e:selectSection('Files')
local delta={'same\tmods/same.lua','added\tmods/new.lua','modified\tmods/edit.lua','removed\tmods/gone.lua'}
e.fileScan=fileScanFixture(delta,'manifest');e.scanApplied=false;e:updateWhenVisible()
local function hasKind(editor,kind)
    for _,row in ipairs(editor.fileList.items) do if row.item.kind==kind then return true end end
    return false
end
check(not hasKind(e,'same') and hasKind(e,'added') and hasKind(e,'modified') and hasKind(e,'removed'),'default view includes added, changed and remote-only deleted files, hiding unchanged files')
check(e.filesInfo:getText():find('Added: 1   Changed: 1   Removed: 1',1,true) and e.publishButton.enabled,'manifest counts substitute all three parameters and allow upload')
e.fileFilter.onclick(e);e:updateWhenVisible()
check(hasKind(e,'same') and e.fileFilter.title==getText('UI_MS_ShowChangesOnly'),'show-all retains unchanged files and offers the return action')
e.fileFilter.onclick(e);check(not hasKind(e,'same'),'toggle returns to changed files without rescanning Steam')
e:buildFileTree({'removed\tmods/replaced','added\tmods/replaced/child.lua'})
check(#e.fileRoot.children[1].children==2,'file-to-directory replacement preserves both old file and new directory')
e.fileScan=fileScanFixture({'same\tmods/same.lua'},'manifest');e.scanApplied=false;e:updateWhenVisible()
check(#e.fileList.items==0 and not e.publishButton.enabled and e.filesInfo:getText():find(getText('UI_MS_NoFileChanges'),1,true),'unchanged revision has an explicit empty state and disables redundant upload')
e.fileFilter.onclick(e);e:updateWhenVisible();check(hasKind(e,'same') and not e.publishButton.enabled,'showing unchanged files does not enable upload')
e.fileScan=fileScanFixture({'unknown\tmods/same.lua'},'unknown');e.scanApplied=false;e:updateWhenVisible()
check(hasKind(e,'unknown') and not e.fileFilter.enabled and e.filesInfo:getText():find(getText('UI_MS_ManifestAccess'),1,true),'unavailable manifest never hides files or claims no changes')
e.fileScan=fileScanFixture({},'unknown','loading');e.scanApplied=false
for _,phase in ipairs({'checking','connecting','manifest','hashing'}) do
    e.fileScan.phase=phase;e:updateWhenVisible()
    check(e.filesInfo:getText()==getText('UI_MS_Scan'..phase) and not e.publishButton.enabled,'background phase is visible and upload awaits a completed scan')
end
local pendingScan=e.fileScan;e:scanFiles();check(pendingScan.cancelled,'refresh cancels the previous worker')
pendingScan=e.fileScan;e:cancelReads()
local layouts=0
local function bounds(parent,context)
    local children={}
    for _,c in pairs(parent.children or {}) do if c.visible~=false then
        local desc=c.title or c.name or c.text or 'widget'
        check(c.width>=0 and c.height>0,context..' negative/zero size: '..desc)
        check(c.x>=-1 and c.y>=-1 and c:getRight()<=parent.width+1 and c:getBottom()<=parent.height+1,context..' outside parent: '..desc..' @ '..c.x..','..c.y..' '..c.width..'x'..c.height..' parent '..parent.width..'x'..parent.height)
        for _,other in ipairs(children) do
            local overlap=math.min(c:getRight(),other:getRight())-math.max(c.x,other.x)>1 and math.min(c:getBottom(),other:getBottom())-math.max(c.y,other.y)>1
            check(not overlap,context..' overlapping: '..desc..' / '..(other.title or other.name or other.text or 'widget'))
        end
        children[#children+1]=c;bounds(c,context)
    end end
end
local function captureEditor(editor)
    MSReview={width=editor.width,height=editor.height,fontSet=fontSet,commands={}}
    local function record(owner,kind,x,y,w,h,value,font,color)
        local ox,oy=0,0;local p=owner
        while p do ox=ox+p.x;oy=oy+p.y;p=p.parent end
        MSReview.commands[#MSReview.commands+1]={kind=kind,x=x+ox,y=y+oy,w=w,h=h,value=value,font=font,color=color}
    end
    local drawText,drawRect,selection=Base.drawText,Base.drawRect,Base.drawSelection
    local drawBorder,drawTexture=Base.drawRectBorder,Base.drawTextureScaledAspect
    Base.drawText=function(owner,s,x,y,r,g,b,a,font) record(owner,'text',x,y,0,0,s,font,{r,g,b}) end
    Base.drawRect=function(owner,x,y,w,h,a,r,g,b) record(owner,'fill',x,y,w,h,'',1,{r,g,b}) end
    Base.drawSelection=function(owner,x,y,w,h) record(owner,'fill',x,y,w,h,'',1,{0.24,0.17,0.12}) end
    Base.drawRectBorder=function(owner,x,y,w,h,a,r,g,b) record(owner,'border',x,y,w,h,'',1,{r,g,b}) end
    Base.drawTextureScaledAspect=function(owner,texture,x,y,w,h) record(owner,'texture',x,y,w,h,texture.path,1,{1,1,1}) end
    editor:render()
    local function paint(p)
        for _,c in pairs(p.children or {}) do if c.visible~=false then
            if c.doDrawItem and c.items then
                if c.drawBorder then record(c,'border',0,0,c.width,c.height,'',1,{0.3,0.3,0.3}) end
                local y=0
                for i,row in ipairs(c.items) do
                    row.index=i;if y+row.height>c.height then break end
                    y=c:doDrawItem(y,row,false)
                end
            elseif c.title then
                record(c,'border',0,0,c.width,c.height,'',1,{0.5,0.5,0.5})
                c:drawText(c.title,(c.width-tm:MeasureStringX(1,c.title))/2,(c.height-tm:getFontHeight(1))/2,0.9,0.9,0.9,1,1)
            elseif c.name and not c.options then
                c:drawText(c.name,0,0,0.9,0.9,0.9,1,c.font or 1)
            elseif getmetatable(c)==ISTextEntryBox then
                if not c.borderColor or c.borderColor.a>0 then record(c,'border',0,0,c.width,c.height,'',1,{0.3,0.3,0.3}) end
                local y=4
                for line in (c.text..'\n'):gmatch('(.-)\n') do
                    if y+tm:getFontHeight(1)>c.height then break end
                    c:drawText(line,4,y,0.8,0.8,0.8,1,1);y=y+tm:getFontHeight(1)
                end
            end
            if c.viewList then
                local x=0
                for _,tab in ipairs(c.viewList) do
                    local w=tm:MeasureStringX(1,tab.name)+40
                    record(c,'border',x,0,w,c.tabHeight,'',1,{0.4,0.4,0.4});c:drawText(tab.name,x+20,3,0.9,0.9,0.9,1,1);x=x+w
                end
            end
            paint(c)
        end end
    end
    paint(editor);Base.drawText=drawText;Base.drawRect=drawRect;Base.drawSelection=selection
    Base.drawRectBorder=drawBorder;Base.drawTextureScaledAspect=drawTexture
end
local function rows(list)
    check(list.font==UIFont.Small and list.itemheight>=tm:getFontHeight(UIFont.Small)+(list.indent and 2 or 8),'list font and row spacing match')
    local original=rawget(list,'drawText')
    list.drawText=function(_,str,x,y,r,g,b,a,font)
        check(x>=0 and x+tm:MeasureStringX(font,str)<=list.width,'row text must fit inside its viewport: '..str)
        check(y>=0 and y+tm:getFontHeight(font)<=list.itemheight,'row text must fit inside its line')
    end
    for i,row in ipairs(list.items) do row.index=i;list:doDrawItem(0,row,false) end
    list.drawText=original
end
for _,lang in ipairs({'EN','RU','UA','DE','FR','IT','PL','TR','KO','ES','ES_CL','ES_MX','PT','PTBR','CN','CH'}) do
    locale=lang
    for _,variant in ipairs({{1152,648,'default'},{1728,1080,'default'},{1728,1080,'2x'}}) do
        fontSet=variant[3];tags=makeTags()
        core.screenWidth=variant[1];core.screenHeight=variant[2]
        local sc=WorkshopSubmitScreen:new(0,0,variant[1],variant[2]);sc:create();local editor=sc.page2
        editor:setWorkshopItem(item);editor:updateWhenVisible()
        editor.fileScan=fileScanFixture({'modified\tmods/very-long-mod-folder/common/media/lua/client/a-really-long-file-name-to-check-clipping.lua','same\tmods/example/mod.info','added\tmods/example/data.json','removed\tmods/example/old.lua'},'manifest')
        editor.scanApplied=false;editor:updateWhenVisible()
        for _,section in ipairs({'Files','Texts','Preview','Settings','Dependencies'}) do
            editor:selectSection(section);editor:updateWhenVisible()
            bounds(editor,lang..' '..variant[1]..' '..fontSet..' '..section)
        end
        rows(editor.navigation);rows(editor.fileList);rows(editor.assetTree)
        for line in (editor.filesInfo:getText()..'\n'):gmatch('(.-)\n') do
            check(tm:MeasureStringX(UIFont.Small,line)<=editor.filesInfo.width-8,'localized file summary wraps inside its actual width')
        end
        check(editor.tags.itemheight==tm:getFontHeight(UIFont.Small)+6,'tags use slightly denser spacing')
        local marks=editor.tags;local tick,box
        local oldTexture,oldBorder=rawget(marks,'drawTextureScaled'),rawget(marks,'drawRectBorder')
        marks.drawRectBorder=function(_,x,y,w,h) box={x=x,y=y,w=w,h=h} end
        marks.drawTextureScaled=function(_,tex,x,y,w,h) tick={x=x,y=y,w=w,h=h} end
        marks:setChecked(marks.items[1].text,true);marks:doDrawItem(0,marks.items[1],false)
        check(tick and tick.x+tick.w/2==box.x+box.w/2 and tick.y+tick.h/2==box.y+box.h/2,'native tag tick is centered in its box at every scale')
        check(tick.x>box.x and tick.y>box.y and tick.x+tick.w<box.x+box.w and tick.y+tick.h<box.y+box.h,'tag tick fits inside its border')
        marks.drawTextureScaled=oldTexture;marks.drawRectBorder=oldBorder
        for line in (editor.languageHint:getText()..'\n'):gmatch('(.-)\n') do
            check(tm:MeasureStringX(UIFont.Small,line)<=editor.languageHint.width-8,'localized fallback hint wraps within toolbar width')
        end
        check(editor.fileList.itemheight==tm:getFontHeight(UIFont.Small)+2,'tree spacing is compact at each font scale')
        local tree=editor.fileList;local rootNode=editor.fileRoot.children[1];local treeCount=#tree.items
        tree:onMouseDown(tree.width-30,tree.itemheight/2)
        check(rootNode.expanded and #tree.items==treeCount and tree.selected==-1,'blank row area neither selects nor toggles tree')
        tree.mouseOverScrollBar=true;tree:onMouseDown(10,tree.itemheight/2);tree.mouseOverScrollBar=false
        check(rootNode.expanded,'scrollbar input does not toggle folder')
        tree:onMouseDown(10,tree.itemheight/2)
        check(not rootNode.expanded and #tree.items==1 and tree.selected==-1,'graphical disclosure click collapses without row selection')
        tree:onMouseDown(10,tree.itemheight/2);check(#tree.items==treeCount,'graphical disclosure click expands folder')
        for click=1,8 do
            local wasExpanded=rootNode.expanded
            if click%2==1 then tree:onMouseDown(10,tree.itemheight/2) else tree:onMouseDoubleClick(10,tree.itemheight/2) end
            check(rootNode.expanded~=wasExpanded,'every rapid press toggles the folder, including native double-click events')
        end
        tree:onMouseDown(8+22+45,2*tree.itemheight+tree.itemheight/2)
        check(tree.selected==-1,'file clicks do not select rows')
        local selection,texture=rawget(tree,'drawSelection'),rawget(tree,'drawTextureScaledAspect');local arrows=0
        tree.drawSelection=function() error('tree must never draw a selected row') end
        tree.drawTextureScaledAspect=function(_,tex) check(tex.path:find('Button_Tree',1,true),'native graphical disclosure texture');arrows=arrows+1 end
        rows(tree);check(arrows>0,'folder renderer draws disclosure icons');tree.drawSelection=selection;tree.drawTextureScaledAspect=texture
        tree:setYScroll(-10000);rootNode.expanded=false;editor:drawFileTree()
        check(tree:getYScroll()==0,'collapsing a scrolled tree clamps scroll back to visible content')
        rootNode.expanded=true;editor:drawFileTree()
        local headings={};local oldDraw=rawget(editor,'drawText')
        editor.itemTitle=string.rep('Workshop title ',40)
        editor.drawText=function(_,caption,x,y,r,g,b,a,font)
            headings[#headings+1]={caption=caption,font=font}
            check(x+tm:MeasureStringX(font,caption)<=editor.width-editor.margin,'header text fits with its actual font')
        end
        editor:render();editor.drawText=oldDraw
        check(headings[1].font==UIFont.Large and headings[1].caption:find('Workshop title',1,true) and headings[2].caption=='Workshop ID: '..item:getID(),'mod title and Workshop ID replace app branding')
        editor.itemTitle='Example mod'
        local lookups=playerMenuLookups;editor:languageMenu();local popup=editor.popup
        popup:prerender();popup:render();popup:onMouseWheel(1)
        check(popup.height<=core.screenHeight and popup:getScrollAreaHeight()<=popup:getScrollHeight(),'native language menu fits and scrolls in each font/window size')
        editor:cancelReads();check(not popup.inUI and not editor.popup and playerMenuLookups==lookups,'session closes standalone menu without player lookup')
        local count=#editor.fileList.items;local root=editor.fileRoot.children[1]
        root.expanded=false;editor:drawFileTree();check(#editor.fileList.items<count,'folders collapse without losing file nodes')
        root.expanded=true;editor:drawFileTree();check(#editor.fileList.items==count,'folders expand with all children preserved')
        if MSCapturePreview and lang=='EN' and variant[1]==1728 and fontSet=='2x' then editor:selectSection('Files');captureEditor(editor) end
        fresh.id=false;editor:setWorkshopItem(fresh);editor:updateWhenVisible()
        for _,section in ipairs({'Files','Texts','Preview','Settings','Dependencies'}) do
            editor:selectSection(section);editor:updateWhenVisible()
            bounds(editor,lang..' '..variant[1]..' '..fontSet..' NEW '..section)
        end
        editor:cancelReads();layouts=layouts+1
    end
end
print('PASS: '..layouts..' font/locale/window layouts; native widget sizes, no overlaps or clipped row text; '..checks..' checks')
MSLayoutCount=layouts;MSUICheckCount=checks
