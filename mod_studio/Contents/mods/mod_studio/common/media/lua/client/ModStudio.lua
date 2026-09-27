require "OptionScreens/WorkshopSubmitScreen"
require "ISUI/ISTabPanel"
require "ISUI/ISModalDialog"
require "ISUI/ISTickBox"
require "ISUI/ISContextMenu"

ModStudio = ModStudio or {}
local MS = ModStudio
if MS.installed then return end
MS.installed = true
-- Steam identifiers differ from the game's translation-folder names.
MS.languages = {
    {"EN","english"},{"RU","russian"},{"DE","german"},{"FR","french"},
    {"ES","spanish"},{"ES-419","latam"},{"PT","portuguese"},{"PT-BR","brazilian"},
    {"IT","italian"},{"PL","polish"},{"UK","ukrainian"},{"TR","turkish"},
    {"JA","japanese"},{"KO","koreana"},{"ZH-CN","schinese"},{"ZH-TW","tchinese"},
    {"AR","arabic"},{"BG","bulgarian"},{"CS","czech"},{"DA","danish"},
    {"NL","dutch"},{"FI","finnish"},{"EL","greek"},{"HU","hungarian"},
    {"ID","indonesian"},{"NO","norwegian"},{"RO","romanian"},{"SV","swedish"},
    {"TH","thai"},{"VI","vietnamese"},{"MS","malay"}
}
local function text(key,...) return getText("UI_MS_"..key,...) end
local function previewError(reason)
    local keys={preview_size="PreviewSizeError",preview_format="PreviewFormatError",preview_dimensions="PreviewDimensionsError",preview_frames="PreviewFramesError",preview_missing="PreviewMissing",preview_download_size="PreviewDownloadSize"}
    for code,key in pairs(keys) do if tostring(reason):find(code,1,true) then return text(key) end end
    return text("Error",tostring(reason))
end
local function ready() return ModStudioJava and ModStudioJava.isReady() end
local function values(list)
    local result={}
    if list then for i=0,list:size()-1 do result[#result+1]=tostring(list:get(i)) end end
    return result
end
local function javaList(list)
    local result=ArrayList.new()
    for _,value in ipairs(list) do result:add(value) end
    return result
end
local function joined(list)
    local copy={}
    for _,v in ipairs(list) do copy[#copy+1]=v end
    table.sort(copy)
    return table.concat(copy,"\n")
end
local function contains(list,value)
    for _,v in ipairs(list) do if v==value then return true end end
    return false
end
local function label(p,caption,x,y)
    local c=ISLabel:new(x,y,getTextManager():getFontHeight(UIFont.Small),caption,1,1,1,1,UIFont.Small,true)
    p:addChild(c);return c
end
local function fontHeight() return getTextManager():getFontHeight(UIFont.Small) end
local function measure(value,font) return getTextManager():MeasureStringX(font or UIFont.Small,value) end
local function fit(value,width,font)
    value=tostring(value or "")
    if measure(value,font)<=width then return value end
    -- Kahlua strings use Java characters, so trimming does not split UTF-8 bytes.
    while #value>0 and measure(value.."...",font)>width do value=value:sub(1,-2) end
    return value.."..."
end
local function wrap(value,width)
    local lines={}
    while measure(value)>width do
        local count=1
        while count<#value and measure(value:sub(1,count+1))<=width do count=count+1 end
        local prefix=value:sub(1,count)
        local space=prefix:match("^.*()%s")
        if space and space>1 then count=space end
        lines[#lines+1]=value:sub(1,count):gsub("%s+$","")
        value=value:sub(count+1):gsub("^%s+","")
    end
    lines[#lines+1]=value;return lines
end
local function resize(c,x,y,w,h)
    c:setX(x);c:setY(y);c:setWidth(w);c:setHeight(h)
end
local function cleanRow(list,y,row)
    if list.selected==row.index then list:drawSelection(0,y,list.width,row.height) end
    local inset=10
    list:drawText(fit(row.text,list.width-inset-22),inset,y+(row.height-list.fontHgt)/2,0.9,0.9,0.9,1,UIFont.Small)
    row.tooltip=row.text
    return y+row.height
end
local function listbox(p,x,y,w,h)
    local c=ISScrollingListBox:new(x,y,w,h);c:initialise();c:setFont(UIFont.Small,6)
    c.drawBorder=true;c.doDrawItem=cleanRow;p:addChild(c);return c
end
local function isFolder(node) return node.directory or node.file and node.file:isDirectory() end
local function nodeName(node) return node.file and node.file:getName() or node.name end
local function treeX(list,depth) return 8+math.min(depth*list.indent,list.width*0.5) end
local function tree(p,x,y,w,h,target,activate)
    local c=listbox(p,x,y,w,h);c:setFont(UIFont.Small,1);c.indent=22;c.selected=-1;c.drawBorder=false
    c.expandedIcon=getTexture("media/ui/inventoryPanes/Button_TreeExpanded.png")
    c.collapsedIcon=getTexture("media/ui/inventoryPanes/Button_TreeCollapsed.png")
    -- Scrolling is native; files are not selectable list rows.
    c.onMouseDown=function(list,mx,my)
        if list:isMouseOverScrollBar() then return false end
        local row=list.items[list:rowAt(mx,my)];if not row then return true end
        local node=row.item;local left=treeX(list,node.depth)
        local right=math.min(list.width-22,left+40+measure(nodeName(node)))
        if mx>=left and mx<=right and (isFolder(node) or node.file and node.file:isSelectable()) then activate(target,node) end
        return true
    end
    -- The game replaces the second press with this event. Treat it as another click.
    c.onMouseDoubleClick=c.onMouseDown
    return c
end
local function treeRows(list,nodes)
    local scroll=list:getYScroll();list:clear();list:setScrollHeight(0)
    local function add(children,guides)
        for i,node in ipairs(children) do
            node.last=i==#children;node.guides=guides;list:addItem(nodeName(node),node)
            if node.expanded and node.children then
                local nextGuides={};for j,v in ipairs(guides) do nextGuides[j]=v end
                nextGuides[#nextGuides+1]=not node.last;add(node.children,nextGuides)
            end
        end
    end
    add(nodes,{});list.selected=-1;list:setScrollHeight(#list.items*list.itemheight)
    list.smoothScrollTargetY=nil;list:setYScroll(math.max(math.min(0,list.height-list:getScrollHeight()),math.min(0,scroll)))
end
local function treeGlyphs(list,y,row)
    local node=row.item;local x=treeX(list,node.depth);local mid=y+math.floor(row.height/2)
    for ancestor,continues in ipairs(node.guides or {}) do
        if continues and ancestor>1 then list:drawRect(treeX(list,ancestor-2)+7,y,1,row.height,0.22,0.65,0.65,0.65) end
    end
    if node.depth>0 then
        local branch=treeX(list,node.depth-1)+7
        list:drawRect(branch,y,1,node.last and row.height/2 or row.height,0.22,0.65,0.65,0.65)
        list:drawRect(branch,mid,x-branch+7,1,0.22,0.65,0.65,0.65)
    end
    if isFolder(node) then
        list:drawTextureScaledAspect(node.expanded and list.expandedIcon or list.collapsedIcon,x,mid-7,14,14,1,1,1,1)
        list:drawRect(x+21,mid-6,6,3,1,0.64,0.53,0.34)
        list:drawRect(x+20,mid-3,15,10,1,0.64,0.53,0.34)
        list:drawRectBorder(x+20,mid-3,15,10,0.7,0.85,0.73,0.49)
    else
        local shade=node.file and not node.file:isSelectable() and 0.3 or 0.65
        list:drawRectBorder(x+22,mid-7,10,14,1,shade,shade,shade)
        list:drawRect(x+24,mid-3,6,1,1,shade,shade,shade)
        list:drawRect(x+24,mid,6,1,1,shade,shade,shade)
    end
    return x+40
end
local function entry(p,x,y,w,h,multiline)
    local c=ISTextEntryBox:new("",x,y,w,h)
    c:initialise();c:instantiate()
    c:setFont(UIFont.Small)
    if multiline then c:setMultipleLine(true);c:addScrollBars() end
    p:addChild(c);return c
end
local function readout(p,x,y,w,h)
    local c=entry(p,x,y,w,h,true);c:setEditable(false)
    c.backgroundColor={r=0,g=0,b=0,a=0};c.borderColor={r=0,g=0,b=0,a=0};return c
end
local function button(p,caption,x,y,target,callback)
    local c=ISButton:new(x,y,10,math.max(26,getTextManager():getFontHeight(UIFont.Small)+8),caption,target,callback)
    c:initialise();c.borderColor={r=1,g=1,b=1,a=0.25};p:addChild(c);return c
end
local function panel(w,h)
    local p=ISPanelJoypad:new(0,0,w,h);p:initialise();p.background=false;return p
end
local function editable(c,enabled)
    c:setEditable(enabled);local shade=enabled and 1 or 0.45;c:setTextRGBA(shade,shade,shade,1)
end
local Editor=ISPanelJoypad:derive("ModStudioEditor")
MS.Editor=Editor
-- Workshop also opens from the main menu, before a player context menu exists.
local Menu=ISContextMenu:derive("ModStudioMenu")
function Menu:topmostMenuWithMouse(x,y)
    if self:isVisible() and x>=self:getX() and x<self:getRight() and y>=self:getY() and y<self:getBottom() then return self end
end
function Menu:hideSelf()
    ISContextMenu.hideSelf(self);self:removeFromUIManager()
    if self.owner and self.owner.popup==self then self.owner.popup=nil end
end
function Menu:onMouseDown(x,y)
    self.mousePressed=true
end
function Menu:onMouseUp(x,y)
    if not self.mousePressed then return end
    self.mousePressed=false;ISContextMenu.onMouseUp(self,x,y)
end
function Editor:closeMenu()
    if self.popup then self.popup:hideAndChildren();self.popup=nil end
end
function Editor:openMenu()
    self:closeMenu()
    local menu=Menu:new(getMouseX(),getMouseY(),1,1)
    menu:initialise();menu:instantiate();menu.parent=nil;menu.owner=self;menu.origin=self;menu.instanceMap={}
    menu:setFont(UIFont.Small);menu:addToUIManager();menu:setVisible(true);menu:bringToTop();menu:setForceCursorVisible(true)
    self.popup=menu;return menu
end
function Editor:new(x,y,w,h,tags)
    local o=ISPanelJoypad.new(self,x,y,w,h)
    o.background=true;o.backgroundColor={r=0.035,g=0.035,b=0.035,a=0.97};o.tags=tags;o.requests={};o.languages={};o.actions={}
    return o
end
function Editor:action(p,caption,x,y,callback,enabled)
    local c=button(p,caption,x,y,self,callback)
    self.actions[#self.actions+1]={control=c,enabled=enabled or function() return true end}
    return c
end
function Editor:create()
    local fh=fontHeight();local bh=math.max(26,fh+8)
    self.margin=math.max(24,(self.width-1360)/2)
    local navWidth=140
    for _,key in ipairs({"Files","Texts","Preview","Settings","Dependencies"}) do navWidth=math.max(navWidth,measure(text(key))+32) end
    self.mainX=self.margin+navWidth+24;self.mainWidth=self.width-self.mainX-self.margin
    self.headerY=24+getTextManager():getFontHeight(UIFont.Large)+fh+14
    self.toolbarY=self.headerY+fh+12
    -- Reserve wrapped toolbar rows using the same font metrics as ISButton.
    local toolbarRows=1
    for _,titles in ipairs({{"Load","SavePreviewFile","Refresh"},{"Load","ImportDependencies"},{"Load","LocalActions"}}) do
        local rows=1;local used=0
        for _,key in ipairs(titles) do
            local width=measure(text(key))+20
            if used>0 and used+width>self.mainWidth then rows=rows+1;used=0 end
            used=used+width+12
        end
        toolbarRows=math.max(toolbarRows,rows)
    end
    local bodyY=self.toolbarY+(bh+8)*toolbarRows+6
    self.footerY=self.height-24-bh-(fh*2+18)
    local w=self.mainWidth;local h=self.footerY-bodyY-12
    self.navigation=listbox(self,self.margin,self.headerY,navWidth,self.footerY-self.headerY)
    self.navigation.drawBorder=false
    self.navigation:setFont(UIFont.Small,10)
    self.navigation:setOnMouseDownFunction(self,function(editor,key) editor:selectSection(key) end)
    self.sections={}
    for _,key in ipairs({"Files","Texts","Preview","Settings","Dependencies"}) do
        local p=panel(w,h);p:setX(self.mainX);p:setY(bodyY);self:addChild(p);self.sections[key]=p
        self.navigation:addItem(text(key),key)
    end
    self.loadButton=button(self,text("Load"),self.mainX,self.toolbarY,self,function(editor) editor:loadCurrent() end)
    self.localButton=button(self,text("LocalActions"),self.mainX+self.loadButton.width+12,self.toolbarY,self,function(editor) editor:localAction() end)
    self.refreshButton=button(self,text("Refresh"),self.mainX,self.toolbarY,self,function(editor)
        if editor.activeSection=="Files" then editor:scanFiles() else editor:refreshAssets() end
    end)
    local texts=self.sections.Texts
    local hintLines=wrap(text("TranslationFallback"),w-8)
    local hintH=#hintLines*fh+8
    self.languageHint=readout(self,self.mainX,bodyY,w,hintH)
    self.languageHint:setText(table.concat(hintLines,"\n"))
    self.languageHint:setTextRGBA(0.7,0.73,0.76,1)
    texts:setY(bodyY+hintH+8);texts:setHeight(h-hintH-8)
    self.languageTabs=ISTabPanel:new(0,0,w,texts.height);self.languageTabs:initialise();texts:addChild(self.languageTabs)
    self.plusPanel=panel(w,texts.height-self.languageTabs.tabHeight)
    self.languageTabs.target=self
    self.languageTabs.onActivateView=function(editor,tabs)
        if editor:busy() and tabs.activeView.name~=(editor.activeLanguage or "EN") then
            tabs:activateView(editor.activeLanguage or "EN");return
        end
        if tabs.activeView.view==editor.plusPanel then
            tabs:activateView(editor.activeLanguage or "EN")
        else
            editor.activeLanguage=tabs.activeView.name;editor:openLanguage(editor.languages[editor.activeLanguage])
        end
    end
    local function overPlus(tabs,x,y)
        if y<0 or y>=tabs.tabHeight or tabs:getScrollButtonAtX(x) then return false end
        local view=tabs.viewList[tabs:getTabIndexAtX(x)]
        return view and view.view==self.plusPanel
    end
    self.languageTabs.onMouseDown=function(tabs,x,y)
        tabs.plusPressed=overPlus(tabs,x,y)
        if tabs.plusPressed then return true end
        return ISTabPanel.onMouseDown(tabs,x,y)
    end
    self.languageTabs.onMouseDoubleClick=self.languageTabs.onMouseDown
    self.languageTabs.onMouseUp=function(tabs,x,y)
        local open=tabs.plusPressed and overPlus(tabs,x,y);tabs.plusPressed=false
        ISTabPanel.onMouseUp(tabs,x,y)
        if open then self:languageMenu() end
        return true
    end
    self.languageTabs.onMouseUpOutside=function(tabs,x,y)
        tabs.plusPressed=false;ISTabPanel.onMouseUpOutside(tabs,x,y)
    end
    local drawTabText=self.languageTabs.drawTextCentre
    self.languageTabs.drawTextCentre=function(tabs,caption,x,y,r,g,b,a,font)
        local d=self.languages[caption]
        if d and self:languageDirty(d) then r,g,b=0.93,0.74,0.4 end
        return drawTabText(tabs,caption,x,y,r,g,b,a,font)
    end
    local preview=self.sections.Preview
    local imageWidth=math.min(300,math.floor(w*0.43));self.previewX=w-imageWidth
    label(preview,text("PackageFiles"),0,0)
    self.assetTree=tree(preview,0,fh+8,w-imageWidth-16,h-fh-8,self,function(editor,node) editor:selectAsset(node) end)
    self.assetTree.doDrawItem=function(list,y,row)
        local node=row.item;local file=node.file;local shade=(file:isDirectory() or file:isSelectable()) and 0.9 or 0.35
        local x=treeGlyphs(list,y,row)
        list:drawText(fit(file:getName(),list.width-x-22),x,y+(row.height-list.fontHgt)/2,shade,shade,shade,1,UIFont.Small)
        row.tooltip=file:getPath();return y+row.height
    end
    self.previewFilename=label(preview,"",self.previewX,0)
    self.previewSize=math.min(imageWidth,math.max(72,h-fh*5-28));self.previewY=fh+8
    self.previewDetails=readout(preview,self.previewX,self.previewY+self.previewSize+8,imageWidth,h-self.previewY-self.previewSize-8)
    preview.render=function(p)
        p:drawRectBorder(self.previewX,self.previewY,imageWidth,self.previewSize,0.35,0.65,0.65,0.65)
        if self.previewTexture then self:drawPreview(p) end
    end
    local settings=self.sections.Settings
    local x=math.floor(w*0.43)+16
    label(settings,getText("UI_WorkshopSubmit_ItemTags"),0,0)
    resize(self.tags,0,fh+8,x-32,h-fh-8);self.tags:setFont(UIFont.Small,3);settings:addChild(self.tags)
    -- Keep native tag state/input; centre both the tick and label in compact rows.
    self.tags.doDrawItem=function(list,y,row,alt)
        local boxY=y+math.floor((row.height-list.boxSize)/2)
        if list.enabled and row.index==list.selected and list.joyfocus then
            list:drawRect(0,y,list.width,row.height,0.2,1,1,1)
        elseif list.enabled and row.index==list.mouseoverselected then
            list:drawRect(0,y,list.width,row.height,0.1,1,1,1)
        end
        local border=list.borderColor
        list:drawRectBorder(list.leftMargin,boxY,list.boxSize,list.boxSize,border.a,border.r,border.g,border.b)
        if list:isChecked(row.text) then
            list:drawTextureScaled(list.tickTexture,list.leftMargin+2,boxY+2,list.boxSize-4,list.boxSize-4,1,1,1,1)
        end
        local x=list.leftMargin+list.boxSize+list.textGap
        list:drawText(fit(row.text,list.width-x-22),x,y+(row.height-list.fontHgt)/2,1,1,1,1,list.font)
        row.tooltip=row.text;return y+row.height
    end
    label(settings,getText("UI_WorkshopSubmit_ItemVisibility"),x,0)
    self.visibility=ISComboBox:new(x,fh+8,w-x,bh);self.visibility:initialise()
    for _,key in ipairs({"Public","FriendsOnly","Private","Unlisted"}) do self.visibility:addOption(getText("UI_WorkshopSubmit_Visibility"..key)) end
    settings:addChild(self.visibility)
    local descY=self.visibility:getBottom()+18
    label(settings,text("Descriptors"),x,descY)
    self.descriptors=ISTickBox:new(x,descY+fh+8,w-x,24,"Descriptors",self,nil);self.descriptors:initialise();self.descriptors.autoWidth=false
    local full={}
    for i=1,5 do full[#full+1]=text("Descriptor"..i);self.descriptors:addOption(fit(full[#full],w-x-32)) end
    self.descriptors.tooltip=table.concat(full," <LINE> ");settings:addChild(self.descriptors)
    local deps=self.sections.Dependencies
    label(deps,text("DependenciesHint"),0,0)
    self.dependencies=listbox(deps,0,fh+8,w,h-fh-bh-20)
    self:action(deps,text("Remove"),0,h-bh,function(editor)
        local selected=editor.dependencies.items[editor.dependencies.selected]
        if selected then editor.dependencies:removeItemByIndex(editor.dependencies.selected) end
    end,function(editor) return deps.loaded and not deps.loading and editor.dependencies.items[editor.dependencies.selected]~=nil end)
    local files=self.sections.Files
    self.filesInfo=readout(files,0,0,w,fh*2+8)
    local notesH=math.max(fh*2+8,math.floor(h*0.2))
    local notesY=h-notesH-fh-6
    self.fileList=tree(files,0,fh*2+16,w,notesY-fh*2-28,self,function(editor,node)
        if node.directory then node.expanded=not node.expanded;editor:drawFileTree() end
    end)
    self.fileList.doDrawItem=function(list,y,row) return self:drawFileRow(list,y,row) end
    self.fileNotesY=notesY
    self.showAllFiles=false
    self.fileFilter=button(self,text("ShowAllFiles"),self.mainX,self.toolbarY,self,function(editor)
        editor.showAllFiles=not editor.showAllFiles
        editor:buildFileTree(editor.fileEntries or {})
    end)
    label(files,text("ChangeNotes"),0,notesY)
    self.changeNote=entry(files,0,notesY+fh+6,w,notesH,true)
    self.statusBox=readout(self,self.mainX,self.footerY,w,fh*2+8)
    local bottom=self.height-24-bh
    self.publishButton=button(self,text("PublishNew"),self.mainX,bottom,self,function(editor) editor:saveCurrent() end)
    self.backButton=button(self,getText("UI_btn_back"),self.margin,bottom,self,self.onButtonBack)
    self.overlayButton=button(self,text("OpenWorkshop"),self.mainX,bottom,self,function(editor)
        if editor:existing() then activateSteamOverlayToWorkshopItem(editor.item:getID()) end
    end)
    self.linkButton=button(self,text("Link"),self.mainX,bottom,self,function(editor)
        editor:confirmDiscard(editor:hasDrafts(),function()
            editor:setVisible(false);editor.parent.page4:setFields();editor.parent.page4:setVisible(true,editor.joyfocus)
        end)
    end)
end
function Editor:selectSection(key)
    if self:busy() and key~=self.activeSection then
        for i,row in ipairs(self.navigation.items) do if row.item==self.activeSection then self.navigation.selected=i end end
        return
    end
    self:closeMenu();self.activeSection=key
    for name,p in pairs(self.sections) do p:setVisible(name==key) end
    for i,row in ipairs(self.navigation.items) do if row.item==key then self.navigation.selected=i end end
    if key=="Texts" then self:openLanguage(self.languages[self.activeLanguage or "EN"]) end
    if self.item then self:updateChrome() end
end
function Editor:currentState()
    if self.activeSection=="Texts" then
        local d=self.languages[self.activeLanguage or "EN"]
        if d then return d.panel,self:languageDirty(d) end
    end
    local key=self.activeSection;local p=self.sections[key]
    local dirty=key=="Preview" and self.previewDirty or key=="Settings" and p.loaded and self:settingsDirty() or key=="Dependencies" and p.loaded and self:dependenciesDirty()
    return p,dirty
end
function Editor:sourceCaption()
    local p,dirty=self:currentState();local source=p and p.source
    if self.activeSection=="Files" then source="Local" end
    local color={0.65,0.7,0.75}
    if source=="Workshop" then color={0.5,0.78,0.93}
    elseif source then color={0.87,0.73,0.48} end
    local caption=text("Source"..(source or "None"))
    if dirty then caption=caption.."  /  "..text("Unsaved");color={0.93,0.74,0.4} end
    if p and p.loading then caption=caption.."  /  "..text("Loading") end
    return caption,color
end
function Editor:loadCurrent()
    if self.activeSection=="Texts" then self:loadLanguage(self.languages[self.activeLanguage or "EN"])
    elseif self.activeSection=="Preview" then self:loadPreview()
    elseif self.activeSection=="Settings" then self:loadSettings()
    elseif self.activeSection=="Dependencies" then self:loadDependencies() end
end
function Editor:localAction()
    if self.activeSection=="Texts" then
        local d=self.languages.EN;local menu=self:openMenu()
        menu:addOption(text("LoadFile"),self,function(editor) editor:loadEnglish(d) end)
        menu:addOption(text("SaveFile"),self,function(editor) editor:saveEnglish(d) end)
    elseif self.activeSection=="Preview" then self:savePreviewFile()
    elseif self.activeSection=="Dependencies" then self:importDependencies() end
end
function Editor:saveCurrent()
    if not self:existing() or self.publication then self:createPublication();return end
    if self.activeSection=="Files" then self:publishFiles()
    elseif self.activeSection=="Texts" then self:saveLanguage(self.languages[self.activeLanguage or "EN"])
    elseif self.activeSection=="Preview" then self:savePreview()
    elseif self.activeSection=="Settings" then self:saveSettings()
    elseif self.activeSection=="Dependencies" then self:saveDependencies() end
end
function Editor:updateChrome()
    local p,dirty=self:currentState();if not p then return end
    local ok=ready() and not self:busy() and not self.publication
    local key=self.activeSection;local newItem=not self:existing() or self.publication~=nil
    self.languageHint:setVisible(key=="Texts")
    self.loadButton:setVisible(key~="Files");self.loadButton:setEnable(ok and self:existing() and not p.loading)
    local localVisible=key=="Texts" and (self.activeLanguage or "EN")=="EN" or key=="Preview" or key=="Dependencies"
    self.localButton:setVisible(localVisible)
    self.localButton:setTitle(text(key=="Preview" and "SavePreviewFile" or key=="Dependencies" and "ImportDependencies" or "LocalActions"))
    self.localButton:setWidth(measure(self.localButton.title)+20)
    self.localButton:setX(self.loadButton:getRight()+12)
    self.localButton:setEnable(ok and not p.loading and (key=="Texts" or key=="Preview" and self.remotePreview~=nil or key=="Dependencies" and p.loaded))
    self.refreshButton:setVisible(key=="Files" or key=="Preview")
    self.refreshButton:setEnable(ok and not p.loading)
    self.fileFilter:setVisible(key=="Files")
    self.fileFilter:setTitle(text(self.showAllFiles and "ShowChangesOnly" or "ShowAllFiles"))
    self.fileFilter:setWidth(measure(self.fileFilter.title)+20)
    self.fileFilter:setEnable(self.fileScan and self.fileScan:getState()=="ready" and self.fileScan:getBasis()~="unknown")
    local cursor=self.mainX;local y=self.toolbarY
    for _,control in ipairs({self.loadButton,self.localButton,self.refreshButton,self.fileFilter}) do
        if control:isVisible() then
            if cursor>self.mainX and cursor+control.width>self.mainX+self.mainWidth then cursor=self.mainX;y=y+control.height+8 end
            control:setX(cursor);control:setY(y);cursor=control:getRight()+12
        end
    end
    local scanReady=self.fileScan and self.fileScan:getState()=="ready" and self.fileScan:getFileCount()>0
    local canSave=dirty and not p.loading
    if key=="Files" then canSave=scanReady and (self.fileScan:getBasis()~="manifest" or self.fileScan:getAdded()+self.fileScan:getModified()+self.fileScan:getRemoved()>0)
    elseif key=="Preview" then canSave=canSave and self.animation and self.animation:getState()=="ready" end
    local required=""
    local title=text(key=="Files" and "Publish" or "Save")
    if newItem then
        title=text(self.publication and "Retry" or "PublishNew")
        local missing={};local en=self.languages.EN
        if not en or not en.title:getText():match("%S") then missing[#missing+1]="EN: "..getText("UI_WorkshopSubmit_ItemTitle") end
        if not en or not en.description:getText():match("%S") then missing[#missing+1]="EN: "..getText("UI_WorkshopSubmit_ItemDescription") end
        if not self.previewPath or not self.animation or self.animation:getState()~="ready" then missing[#missing+1]=text("Preview") end
        if not scanReady then missing[#missing+1]=text("Files") end
        canSave=self.publication and self.publication:canRetry() or not self.publication and #missing==0
        if #missing>0 then required=text("Required",table.concat(missing,", ")) end
    end
    self.publishButton:setTitle(title);self.publishButton:setWidth(measure(title)+28)
    self.publishButton:setX(self.mainX+self.mainWidth-self.publishButton.width)
    self.publishButton:setEnable(ready() and not self:busy() and canSave and (newItem or not self.publication))
    self.publishButton.borderColor={r=0.5,g=0.7,b=0.8,a=0.8}
    local status=self.upload and self.upload.section or self.publication and self.sections.Files or p
    local message=status.status or ""
    if required~="" and not self:busy() and not status.failed then message=required end
    if self.statusBox:getText()~=message then self.statusBox:setText(message) end
    self.statusBox:setVisible(message~="")
    if status.failed then self.statusBox:setTextRGBA(1,0.55,0.55,1) else self.statusBox:setTextRGBA(0.75,0.78,0.8,1) end
end
function Editor:setPreviewCaption(caption)
    self.previewFilename:setName(fit(caption,self.sections.Preview.width-self.previewX));self.previewFilename.tooltip=caption
end
function Editor:buildFileTree(lines)
    self.fileEntries=lines
    local expanded={}
    local function remember(node)
        if node.directory then expanded[node.path]=node.expanded end
        for _,child in ipairs(node.children or {}) do remember(child) end
    end
    if self.fileRoot then remember(self.fileRoot) end
    local root={children={},byName={}};self.fileRoot=root
    for _,line in ipairs(lines) do
        local kind,path=line:match("^([^\t]+)\t(.*)$")
        if path and (kind~="same" or self.showAllFiles) then
            local parent=root;local parts={};for part in path:gmatch("[^/\\]+") do parts[#parts+1]=part end
            local prefix=""
            for i,name in ipairs(parts) do
                prefix=prefix=="" and name or prefix.."/"..name
                local nodeKey=name..(i<#parts and "/" or "")
                local node=parent.byName[nodeKey]
                if not node then
                    node={name=name,path=prefix,directory=i<#parts,depth=i-1,children={},byName={},expanded=expanded[prefix]~=false}
                    parent.byName[nodeKey]=node;parent.children[#parent.children+1]=node
                end
                if i==#parts then node.kind=kind end
                parent=node
            end
        end
    end
    local function sort(node)
        table.sort(node.children,function(a,b) if a.directory~=b.directory then return a.directory end;return a.name:lower()<b.name:lower() end)
        for _,child in ipairs(node.children) do sort(child) end
    end
    sort(root);self:drawFileTree()
end
function Editor:drawFileTree()
    treeRows(self.fileList,self.fileRoot and self.fileRoot.children or {})
end
function Editor:drawFileRow(list,y,row)
    local node=row.item;local x=treeGlyphs(list,y,row)
    local status="";local color={0.8,0.8,0.8}
    if node.kind=="modified" then status=text("File_modified");color={0.95,0.76,0.4}
    elseif node.kind=="added" then status=text("File_added");color={0.55,0.85,0.6}
    elseif node.kind=="removed" then status=text("File_removed");color={0.95,0.55,0.55} end
    local reserve=status~="" and measure(status)+24 or 0
    local dy=(row.height-list.fontHgt)/2
    list:drawText(fit(node.name,list.width-x-22-reserve),x,y+dy,color[1],color[2],color[3],1,UIFont.Small)
    if status~="" then list:drawText(status,list.width-22-measure(status),y+dy,color[1],color[2],color[3],1,UIFont.Small) end
    row.tooltip=node.path..(node.kind and " <LINE> "..text("File_"..node.kind) or "")
    return y+row.height
end
function Editor:languageMenu()
    if self:busy() or self.publication then return end
    local menu=self:openMenu()
    for _,language in ipairs(MS.languages) do
        if not self.languages[language[1]] then menu:addOption(language[1],self,function(s,lang)
            s:addLanguage(lang[1],lang[2]);s.languageTabs:activateView(lang[1])
        end,language) end
    end
end
function Editor:openLanguage(d)
    if not d or d.visited or self:busy() or self.publication then return end
    d.visited=true
    if self:existing() then self:loadLanguage(d) end
end
function Editor:existing() return self.item and self.item:getID()~=nil end
function Editor:busy()
    return self.upload~=nil or (ModStudioJava and ModStudioJava.isUploading())
end
function Editor:addLanguage(code,steam)
    if self.languages[code] then return self.languages[code] end
    local p=panel(self.languageTabs.width,self.languageTabs.height-self.languageTabs.tabHeight)
    local d={code=code,steam=steam,panel=p,baseTitle="",baseDescription="",observedTitle="",observedDescription=""};self.languages[code]=d
    self.languageTabs:removeView(self.plusPanel);self.languageTabs:addView(code,p);self.languageTabs:addView("+",self.plusPanel)
    local fh=fontHeight();local pad=10
    label(p,getText("UI_WorkshopSubmit_ItemTitle"),pad,12)
    d.title=entry(p,pad,12+fh+6,p.width-pad*2,fh+10,false)
    local y=d.title:getBottom()+14
    label(p,getText("UI_WorkshopSubmit_ItemDescription"),pad,y)
    d.description=entry(p,pad,y+fh+6,p.width-pad*2,p.height-y-fh-16,true)
    return d
end
function Editor:languageDirty(d) return d.force or d.title:getText()~=d.baseTitle or d.description:getText()~=d.baseDescription end
function Editor:descriptorValues()
    local result={};for i=1,5 do if self.descriptors:isSelected(i) then result[#result+1]=tostring(i) end end;return joined(result)
end
function Editor:settingsDirty()
    return joined(values(self.tags:getCheckedTags()))~=self.baseTags or self.visibility.selected-1~=self.baseVisibility or self:descriptorValues()~=self.baseDescriptors
end
function Editor:dependencyValues()
    local result={};for _,row in ipairs(self.dependencies.items) do result[#result+1]=row.item end;return result
end
function Editor:dependenciesDirty() return joined(self:dependencyValues())~=self.baseDependencies end
function Editor:hasDrafts()
    for _,draft in pairs(self.languages) do if self:languageDirty(draft) then return true end end
    return self.publication~=nil or self.previewDirty or (self.sections.Settings.loaded and self:settingsDirty()) or
        (self.sections.Dependencies.loaded and self:dependenciesDirty()) or self.changeNote:getText()~=""
end
function Editor:confirmDiscard(dirty,callback)
    if not dirty then callback();return end
    local modal=ISModalDialog:new(0,0,440,160,text("Discard"),true,self,function(_,b) if b.internal=="YES" then callback() end end)
    modal:initialise();modal:addToUIManager()
end
function Editor:attempt(section,callback)
    local ok,result=pcall(callback)
    if not ok then section.status=section==self.sections.Preview and previewError(result) or text("Error",tostring(result));section.failed=true;return nil end
    return result
end
function Editor:startRead(section,language,apply)
    if section.loading or self:busy() or not self:existing() then return end
    local request=self:attempt(section,function() return ModStudioJava.readWorkshop(self.item:getID(),language) end)
    if not request then return end
    section.loading=true;section.failed=false;section.status=text("Loading")
    self.requests[#self.requests+1]={request=request,section=section,apply=apply}
end
function Editor:loadLanguage(d)
    self:confirmDiscard(self:languageDirty(d),function()
        self:startRead(d.panel,d.steam,function(r)
            d.title:setText(r:getTitle() or "");d.description:setText(r:getDescription() or "")
            d.baseTitle=d.title:getText();d.baseDescription=d.description:getText();d.force=false
            if d.code=="EN" then self.itemTitle=d.baseTitle end
            d.panel.status=text("Loaded");d.panel.source="Workshop";self.metadata=r:getMetadata()
        end)
    end)
end
function Editor:loadEnglish(d)
    self:confirmDiscard(self:languageDirty(d),function()
        self:attempt(d.panel,function()
            local data=ModStudioJava.loadEnglish(self.item);d.title:setText(data:get(0));d.description:setText(data:get(1));d.force=true
            d.panel.status=text("LoadedFile");d.panel.source="File";d.panel.failed=false
        end)
    end)
end
function Editor:saveEnglish(d)
    self:attempt(d.panel,function()
        ModStudioJava.saveEnglish(self.item,d.title:getText(),d.description:getText());d.panel.status=text("SavedFile");d.panel.failed=false
    end)
end
function Editor:startUpload(section,operation,onSaved,onError)
    if self:busy() or section.loading then return end
    local request=self:attempt(section,operation);if not request then return end
    self.upload={request=request,section=section,onSaved=onSaved,onError=onError};section.failed=false;section.status=text("Saving")
end
function Editor:saveLanguage(d)
    local title=d.title:getText();local description=d.description:getText();local titleChange,descriptionChange=nil,nil
    if d.force or title~=d.baseTitle then titleChange=title end
    if d.force or description~=d.baseDescription then descriptionChange=description end
    if titleChange==nil and descriptionChange==nil then return end
    self:startUpload(d.panel,function() return ModStudioJava.saveText(self.item,d.steam,titleChange,descriptionChange,self.metadata) end,
        function()
            d.baseTitle=title;d.baseDescription=description;d.force=false;d.panel.source="Workshop"
            if d.code=="EN" then self.itemTitle=title end
        end)
end
function Editor:applySettings(r)
    local allowed=values(SteamWorkshopItem.getAllowedTags());local remote=values(r:getTags())
    for _,tag in ipairs(remote) do if not contains(allowed,tag) then allowed[#allowed+1]=tag end end
    self.tags:setTags(javaList(allowed));self.tags:setCheckedTags(javaList(remote));self.visibility.selected=r:getVisibility()+1
    local descriptors=values(r:getContentDescriptors())
    for i=1,5 do self.descriptors:setSelected(i,contains(descriptors,tostring(i))) end
    self.baseTags=joined(remote);self.baseVisibility=r:getVisibility();self.baseDescriptors=joined(descriptors)
    self.sections.Settings.loaded=true;self.sections.Settings.source="Workshop";self.metadata=r:getMetadata();self.previewUrl=r:getPreviewUrl()
end
function Editor:loadSettings()
    local p=self.sections.Settings
    self:confirmDiscard(p.loaded and self:settingsDirty(),function() self:startRead(p,"english",function(r) self:applySettings(r) end) end)
end
function Editor:saveSettings()
    local tags=joined(values(self.tags:getCheckedTags()));local visibility=self.visibility.selected-1
    local descriptors=self:descriptorValues();local tagChange=nil;local visibilityChange=-1
    if tags~=self.baseTags then tagChange=tags end;if visibility~=self.baseVisibility then visibilityChange=visibility end
    self:startUpload(self.sections.Settings,function()
        return ModStudioJava.saveSettings(self.item,tagChange,visibilityChange,self.baseDescriptors,descriptors,self.metadata)
    end,function() self.baseTags=tags;self.baseVisibility=visibility;self.baseDescriptors=descriptors;self.sections.Settings.source="Workshop" end)
end
function Editor:applyDependencies(r)
    self.dependencies:clear();for _,id in ipairs(values(r:getDependencies())) do self.dependencies:addItem(id,id) end
    if self.nameRequest then self.nameRequest.request:cancel();self.nameRequest=nil end
    self.nameQueue=self:dependencyValues()
    self.baseDependencies=joined(self:dependencyValues());self.sections.Dependencies.loaded=true;self.sections.Dependencies.source="Workshop"
end
function Editor:loadDependencies()
    local p=self.sections.Dependencies
    self:confirmDiscard(self:dependenciesDirty(),function() self:startRead(p,"english",function(r) self:applyDependencies(r) end) end)
end
function Editor:importDependencies()
    self:attempt(self.sections.Dependencies,function()
        local previous=self:dependencyValues()
        for _,id in ipairs(values(ModStudioJava.importDependencies(self.item))) do
            if not contains(previous,id) then
                self.dependencies:addItem(id,id);previous[#previous+1]=id
                self.nameQueue=self.nameQueue or {};self.nameQueue[#self.nameQueue+1]=id
            end
        end
        self.sections.Dependencies.status=text("Imported");self.sections.Dependencies.failed=false
    end)
end
function Editor:saveDependencies()
    local target=joined(self:dependencyValues())
    self:startUpload(self.sections.Dependencies,function() return ModStudioJava.saveDependencies(self.item,self.baseDependencies,target) end,
        function() self.baseDependencies=target;self.sections.Dependencies.source="Workshop" end,function()
            -- Earlier operations may have succeeded. A fresh snapshot is required before retrying.
            self.sections.Dependencies.loaded=false
        end)
end
function Editor:refreshAssets()
    self:attempt(self.sections.Preview,function()
        self.assetRoots=self:assetNodes("",0);self:drawAssetTree()
    end)
end
function Editor:assetNodes(path,depth)
    local entries=ModStudioJava.listAssets(self.item,path);local nodes={}
    for i=0,entries:size()-1 do nodes[#nodes+1]={file=entries:get(i),depth=depth} end
    return nodes
end
function Editor:drawAssetTree()
    treeRows(self.assetTree,self.assetRoots or {})
end
function Editor:selectAsset(node)
    if self:busy() or self.publication or self.sections.Preview.loading or not node then return end
    local file=node.file
    if file:isDirectory() then
        self:attempt(self.sections.Preview,function()
            if not node.children then node.children=self:assetNodes(file:getPath(),node.depth+1) end
            node.expanded=not node.expanded;self:drawAssetTree()
        end)
    elseif file:isSelectable() then self:choosePreview(file:getPath(),true)
    else self.sections.Preview.status=previewError(file:getReason());self.sections.Preview.failed=true end
end
function Editor:releasePreview()
    if self.animation then self.animation:close();self.animation=nil end
    if self.remotePreview then self.remotePreview:cancel();self.remotePreview=nil end
end
function Editor:previewInformation(info)
    local error=info:getUploadError()
    self.previewDetails:setText(info:getFormat().."  "..info:getWidth().." x "..info:getHeight().."\n"..text("PreviewBytes",tostring(math.floor(info:getBytes()))).."\n"..(error and previewError(error) or text("PreviewHint")))
end
function Editor:loadPreview()
    if self:busy() or self.publication or self.sections.Preview.loading then return end
    self:confirmDiscard(self.previewDirty,function()
        self:startRead(self.sections.Preview,"english",function(snapshot)
            local download=ModStudioJava.downloadPreview(snapshot)
            self.pendingPreview=download;self.sections.Preview.loading=true;self.sections.Preview.status=text("LoadingPreview")
        end)
    end)
end
function Editor:savePreviewFile()
    if not self.remotePreview or self.sections.Preview.loading or self:busy() then return end
    self:attempt(self.sections.Preview,function()
        local path=ModStudioJava.saveWorkshopPreview(self.item,self.remotePreview)
        self:refreshAssets();self.sections.Preview.status=text("PreviewFileSaved",path);self.sections.Preview.failed=false
    end)
end
function Editor:choosePreview(path,dirty)
    self:attempt(self.sections.Preview,function()
        local info=ModStudioJava.previewInfo(self.item,path)
        local animation=ModStudioJava.previewAnimation(self.item,path)
        self:releasePreview();self:previewInformation(info)
        self.animation=animation;self.previewPath=path;self.previewDirty=dirty;self.previewTexture=nil;self.previewFrame=nil
        self:setPreviewCaption(path);self.sections.Preview.source="Local";self.animationStart=getTimestampMs()
        self.sections.Preview.status=text("PreviewSelected");self.sections.Preview.failed=false
    end)
end
function Editor:drawPreview(p)
    local size=self.previewSize;p:drawTextureScaledAspect(self.previewTexture,self.previewX,self.previewY,size,size,1,1,1,1)
end
function Editor:savePreview()
    local path=self.previewPath
    self:startUpload(self.sections.Preview,function() return ModStudioJava.savePreview(self.item,path,self.metadata) end,function() self.previewDirty=false;self.sections.Preview.source="Workshop" end)
end
function Editor:scanFiles()
    if self.fileScan then self.fileScan:cancel() end
    self.fileList:clear();self.fileEntries={};self:setFilesInfo(text("Scanchecking"))
    self.sections.Files.status=nil;self.sections.Files.failed=false
    self.fileScan=self:attempt(self.sections.Files,function() return ModStudioJava.scanFiles(self.item) end)
    self.scanApplied=false
end
function Editor:setFilesInfo(message)
    if self.fileInfoMessage==message then return end
    self.fileInfoMessage=message
    local lines={}
    for line in (message.."\n"):gmatch("(.-)\n") do
        for _,part in ipairs(wrap(line,self.filesInfo.width-8)) do lines[#lines+1]=part end
    end
    local height=math.min(#lines*fontHeight()+8,math.floor(self.sections.Files.height*0.3))
    self.filesInfo:setText(table.concat(lines,"\n"));self.filesInfo:setHeight(height)
    self.fileList:setY(height+8);self.fileList:setHeight(self.fileNotesY-height-20)
end
function Editor:publishFiles()
    if self:busy() then return end
    if not self:existing() or self.publication then self:createPublication();return end
    local note=self.changeNote:getText()
    self:startUpload(self.sections.Files,function() return ModStudioJava.publishFiles(self.item,note,self.metadata) end,
        function() if self.changeNote:getText()==note then self.changeNote:setText("") end;self:scanFiles() end)
end
function Editor:createPublication()
    if self:busy() then return end
    self:attempt(self.sections.Files,function()
        if not self.publication then
            local en=self.languages.EN
            local request=ModStudioJava.newPublication(self.item,en.title:getText(),en.description:getText(),self.previewPath,
                joined(values(self.tags:getCheckedTags())),self.visibility.selected-1,self:descriptorValues(),self.changeNote:getText())
            for _,language in ipairs(MS.languages) do
                local d=self.languages[language[1]]
                if d and d.code~="EN" then
                    local title=d.title:getText();local description=d.description:getText()
                    request:addLanguage(d.steam,title~="" and title or nil,description~="" and description or nil)
                end
            end
            request:addDependencies(joined(self:dependencyValues()));self.publication=request
        end
        self:startUpload(self.sections.Files,function() return ModStudioJava.publishNew(self.publication) end,function()
            self.publication=nil;self.previewDirty=false;self.changeNote:setText("")
            for _,d in pairs(self.languages) do d.baseTitle=d.title:getText();d.baseDescription=d.description:getText();d.force=false;d.visited=true;d.panel.source="Workshop" end
            for _,key in ipairs({"Preview","Settings","Dependencies"}) do self.sections[key].source="Workshop" end
            self.baseTags=joined(values(self.tags:getCheckedTags()));self.baseVisibility=self.visibility.selected-1;self.baseDescriptors=self:descriptorValues()
            self.baseDependencies=joined(self:dependencyValues());self.metadata='{"editor":"mod_studio"}'
            self:scanFiles()
        end)
    end)
end
function Editor:cancelReads()
    self:closeMenu()
    for _,p in ipairs(self.requests) do p.request:cancel();p.section.loading=false end
    self.requests={}
    if self.nameRequest then self.nameRequest.request:cancel();self.nameRequest=nil end
    self.nameQueue={}
    self:releasePreview()
    if self.pendingPreview then self.pendingPreview:cancel();self.pendingPreview=nil end
    if self.fileScan then self.fileScan:cancel();self.fileScan=nil end
end
function Editor:setWorkshopItem(item)
    self:cancelReads();self.item=item;self.metadata=nil;self.upload=nil;self.publication=nil;self.sessionOpen=true
    self.itemTitle=item:getTitle()
    self.fileRoot=nil;self.fileEntries={};self.showAllFiles=false
    local actions={}
    for _,action in ipairs(self.actions) do
        local keep=true
        for _,draft in pairs(self.languages) do if action.control.parent==draft.panel then keep=false end end
        if keep then actions[#actions+1]=action end
    end
    for _,draft in pairs(self.languages) do self.languageTabs:removeView(draft.panel) end
    self.languageTabs:removeView(self.plusPanel);self.languageTabs.activeView=nil;self.activeLanguage="EN"
    self.languageTabs.maxLength=0;self.languageTabs.scrollX=0;self.languageTabs.targetScrollX=0
    self.actions=actions;self.languages={}
    for _,p in pairs(self.sections) do p.status=nil;p.failed=false;p.loaded=false;p.loading=false;p.source=nil;p.observedValue=nil end
    local en=self:addLanguage("EN","english")
    en.title:setText(self:existing() and "" or (item:getTitle() or ""));en.description:setText(self:existing() and "" or (item:getDescription() or ""))
    en.baseTitle=en.title:getText();en.baseDescription=en.description:getText();en.panel.status=nil;en.panel.source=self:existing() and nil or "File"
    en.observedTitle=en.baseTitle;en.observedDescription=en.baseDescription
    self.previewPath=nil;self.previewDirty=false;self.previewTexture=nil;self.previewFrame=nil;self.previewUrl=nil
    self:setPreviewCaption(text("LocalPreview"));self.previewDetails:setText(text("PreviewHint"))
    self:refreshAssets()
    if not self:existing() then for _,node in ipairs(self.assetRoots or {}) do
        if node.file:getName()=="preview.png" and node.file:isSelectable() then self:choosePreview(node.file:getPath(),false);break end
    end
    end
    self.tags:setTags(SteamWorkshopItem.getAllowedTags());self.tags:setCheckedTags(self:existing() and javaList({}) or item:getTags())
    self.visibility.selected=self:existing() and 0 or (item:getVisibilityInteger()+1)
    for i=1,5 do self.descriptors:setSelected(i,false) end
    self.dependencies:clear();self.baseDependencies="";self.baseDescriptors=""
    self.baseTags=joined(values(item:getTags()));self.baseVisibility=item:getVisibilityInteger()
    self.changeNote:setText("");self:selectSection("Files");self:scanFiles()
    local notes=self:attempt(self.sections.Files,function() return ModStudioJava.loadReleaseNotes(item) end)
    if notes then self.changeNote:setText(notes) end
    if self:existing() then self:loadSettings();self:loadDependencies();self:openLanguage(en);self:loadPreview()
    else self.sections.Settings.loaded=true;self.sections.Dependencies.loaded=true;self.sections.Settings.source="Local";self.sections.Dependencies.source="Local" end
    self:updateChrome()
end
function Editor:updateWhenVisible()
    if self.pendingPreview then
        local download=self.pendingPreview;local state=download:getState()
        if state~="loading" then
            self.pendingPreview=nil;local p=self.sections.Preview;p.loading=false
            if state=="loaded" then
                self:releasePreview();self.remotePreview=download;self.animation=download:getAnimation();self.animationStart=getTimestampMs()
                self.previewPath=nil;self.previewDirty=false;self.previewTexture=nil;self.previewFrame=nil
                self:setPreviewCaption(text("WorkshopPreview"));p.source="Workshop";self:previewInformation(download:getInfo())
                local renderError=download:getRenderError()
                p.status=renderError and previewError(renderError) or text("Loaded");p.failed=renderError~=nil
            else p.status=previewError(download:getError());p.failed=true;download:cancel() end
        end
    end
    if self.animation then
        local state=self.animation:getState()
        if state=="ready" then
            local path=self.animation:getFramePath(getTimestampMs()-self.animationStart)
            if path and path~=self.previewFrame then self.previewFrame=path;self.previewTexture=self.animation:getFrameTexture(getTimestampMs()-self.animationStart) end
        elseif state=="error" then
            self.sections.Preview.status=previewError(self.animation:getError());self.sections.Preview.failed=true
            self.animation:close();self.animation=nil
        end
    end
    if self.fileScan and not self.scanApplied then
        local scan=self.fileScan;local state=scan:getState()
        if state=="ready" then
            self.scanApplied=true
            local basis=scan:getBasis();local message=text("Compare"..basis)
            if basis=="unknown" then
                local reason=scan:getComparisonError() or ""
                message=message.."\n"..text((reason=="manifest_unavailable" or reason=="manifest_access") and "ManifestAccess" or "ManifestRetry")
                -- Keep exact diagnostics available without filling the page with protocol errors.
                self.filesInfo.tooltip=reason
            else
                self.filesInfo.tooltip=basis=="manifest" and ("Steam manifest: "..(scan:getManifestId() or "")) or nil
                if basis=="manifest" and scan:getAdded()+scan:getModified()+scan:getRemoved()==0 then message=message.."\n"..text("NoFileChanges")
                else message=message.."\n"..text("FileChanges",tostring(scan:getAdded()),tostring(scan:getModified()),tostring(scan:getRemoved())) end
            end
            self:setFilesInfo((scan.getContentLabel and scan:getContentLabel() or "Contents").."\n"..message)
            self:buildFileTree(values(scan:getEntries()))
        elseif state=="error" then self.scanApplied=true;self:setFilesInfo(text("Error",scan:getError()))
        elseif state=="loading" then self:setFilesInfo(text("Scan"..scan:getPhase())) end
    end
    for i=#self.requests,1,-1 do
        local pending=self.requests[i];pending.request:poll();local state=pending.request:getState()
        if state~="loading" then
            pending.section.completedThisTick=true
            pending.section.loading=false
            if state=="loaded" then
                pending.section.status=text("Loaded");pending.section.failed=false
                self:attempt(pending.section,function() pending.apply(pending.request) end)
            elseif state=="error" then pending.section.status=pending.section==self.sections.Preview and previewError(pending.request:getError()) or text("Error",pending.request:getError());pending.section.failed=true end
            table.remove(self.requests,i)
        end
    end
    -- Resolve display names one at a time. Failures keep usable Workshop IDs in the list.
    if self.nameRequest then
        local pending=self.nameRequest;pending.request:poll();local state=pending.request:getState()
        if state~="loading" then
            if state=="loaded" then for _,row in ipairs(self.dependencies.items) do
                if row.item==pending.id then row.text=pending.request:getTitle().." ("..pending.id..")" end
            end end
            self.nameRequest=nil
        end
    elseif self.nameQueue and #self.nameQueue>0 then
        local id=table.remove(self.nameQueue,1)
        local ok,request=pcall(function() return ModStudioJava.readWorkshop(id,"english") end)
        if ok and request then self.nameRequest={id=id,request=request} end
    end
    if self.upload then
        local upload=self.upload;local request=upload.request;request:poll();local state=request:getState()
        if state=="saved" then
            upload.section.completedThisTick=true
            upload.section.status=text(request:needsLegalAgreement() and "LegalRequired" or "Saved")
            upload.onSaved();self.upload=nil
        elseif state=="error" then
            upload.section.completedThisTick=true
            upload.section.status=text("Error",request:getError());upload.section.failed=true
            if request==self.publication then
                if request:getItemId() then upload.section.status=text("Incomplete",request:getItemId()).."\n"..upload.section.status
                elseif not request:canRetry() then upload.section.status=text("CreateUnknown").."\n"..upload.section.status end
            end
            if request:needsLegalAgreement() then upload.section.status=upload.section.status.."\n"..text("LegalRequired") end
            if upload.onError then upload.onError() end;self.upload=nil
        elseif state=="cancelled" then upload.section.completedThisTick=true;upload.section.status=text("Cancelled");self.upload=nil
            if request==self.publication then
                if request:getItemId() then upload.section.status=text("Incomplete",request:getItemId()) end
                self.publication=nil
            end
        elseif request:isSlow() then upload.section.status=text("Slow")
        else
            local stage=""
            if request==self.publication then stage="  "..request:getStage() end
            upload.section.status=text("Saving").." "..tostring(math.floor(request:getProgress()*100)).."%"..stage
        end
    end
    local ok=ready() and not self:busy() and not self.publication
    for _,action in ipairs(self.actions) do action.control:setEnable(ok and action.enabled(self)) end
    for _,d in pairs(self.languages) do
        local title=d.title:getText();local description=d.description:getText()
        if ok and not d.panel.loading and not d.panel.completedThisTick and (title~=d.observedTitle or description~=d.observedDescription) then
            d.panel.status=nil;d.panel.failed=false
        end
        d.panel.completedThisTick=false
        d.observedTitle=title;d.observedDescription=description
        editable(d.title,ok and not d.panel.loading);editable(d.description,ok and not d.panel.loading)
    end
    local settings=self.sections.Settings
    local settingsValue=joined(values(self.tags:getCheckedTags())).."|"..tostring(self.visibility.selected).."|"..self:descriptorValues()
    local deps=self.sections.Dependencies;local dependenciesValue=joined(self:dependencyValues())
    for _,state in ipairs({{settings,settingsValue,settings.loaded and self:settingsDirty()},{deps,dependenciesValue,deps.loaded and self:dependenciesDirty()}}) do
        local p=state[1]
        if ok and not p.loading and not p.completedThisTick and p.observedValue and p.observedValue~=state[2] then
            p.status=nil;p.failed=false
        end
        p.observedValue=state[2]
    end
    for _,p in pairs(self.sections) do p.completedThisTick=false end
    local canEditSettings=ok and not settings.loading and (settings.loaded or not self:existing())
    self.tags:setEnabled(canEditSettings);self.visibility:setEnabled(canEditSettings);self.descriptors.enable=canEditSettings
    editable(self.changeNote,ok)
    self:updateChrome()
    self.backButton:setEnable(not self:busy());self.linkButton:setVisible(not self:existing() and not self.publication);self.linkButton:setEnable(ok)
    self.overlayButton:setVisible(self:existing())
    self.overlayButton:setEnable(self:existing() and isSteamOverlayEnabled())
    if self.activeSection=="Texts" then self:openLanguage(self.languages[self.activeLanguage or "EN"]) end
end
function Editor:render()
    ISPanelJoypad.render(self)
    self:updateWhenVisible()
    local title=self.itemTitle
    if not title or not title:match("%S") then title=self.item and self.item:getFolderName() or "" end
    self:drawText(fit(title,self.width-self.margin*2,UIFont.Large),self.margin,18,1,1,1,1,UIFont.Large)
    local caption=not ready() and text("Unavailable") or (self:existing() and getText("UI_WorkshopSubmit_ItemID").." "..self.item:getID() or text("NewItem"))
    self:drawText(fit(caption,self.width-self.margin*2),self.margin,24+getTextManager():getFontHeight(UIFont.Large),0.7,0.7,0.7,1,UIFont.Small)
    local source,color=self:sourceCaption()
    self:drawText(fit(source,self.mainWidth),self.mainX,self.headerY,color[1],color[2],color[3],1,UIFont.Small)
    self:drawRect(self.mainX,self.footerY-8,self.mainWidth,1,0.4,0.4,0.4,0.4)
end
function Editor:aboutToShow() end
function Editor:onButtonBack()
    if self:busy() then return end
    self:confirmDiscard(self:hasDrafts(),function()
        self:cancelReads();self.sessionOpen=false;if self.item then ModStudioJava.clear(self.item) end
        self:setVisible(false);self.parent.page1:setVisible(true,self.joyfocus)
    end)
end
local function decorate(screen)
    if screen.msDecorated then return end;screen.msDecorated=true
    local original=screen.page2;original:removeChild(original.tags);screen:removeChild(original)
    local editor=Editor:new(0,0,screen.width,screen.height,original.tags)
    editor:initialise();editor:create();screen:addChild(editor);screen.page2=editor;editor:setVisible(false)
    -- Vanilla TagsList checks mouse input but not gamepad input when disabled.
    local tagJoy=editor.tags.onJoypadDown
    function editor.tags:onJoypadDown(b,joypad) if not self.enabled then return end;return tagJoy(self,b,joypad) end
    local p1=screen.page1
    p1.onButtonNext=function(p)
        local selected=p.listbox.items[p.listbox.selected];if not selected then return end;screen.item=selected.item
        if not ready() then p:setVisible(false);screen.page8:setFields("MS_Unavailable",p);screen.page8:setVisible(true,p.joyfocus);return end
        p:setVisible(false);editor:setWorkshopItem(screen.item);editor:setVisible(true,p.joyfocus)
    end
    p1.nextButton.onclick=p1.onButtonNext
    local p4=screen.page4
    p4.onButtonNext=function(p)
        screen.item:setID(p.IDEntry:getText());if not screen.item:getID() then return end
        local ok=pcall(function() ModStudioJava.saveId(screen.item) end)
        if not ok then screen.page8:setFields("IOError",p);p:setVisible(false);screen.page8:setVisible(true);return end
        p:setVisible(false);editor:setWorkshopItem(screen.item);editor:setVisible(true,p.joyfocus)
    end
    p4.nextButton.onclick=p4.onButtonNext
    p4.onButtonBack=function(p) p:setVisible(false);editor:setVisible(true,p.joyfocus) end;p4.backButton.onclick=p4.onButtonBack
end
local create=WorkshopSubmitScreen.create
function WorkshopSubmitScreen:create() create(self);decorate(self) end
local back=WorkshopSubmitScreen.onButtonBack
function WorkshopSubmitScreen:onButtonBack()
    local editor=self.page2
    if editor and self.msDecorated and editor.sessionOpen then
        if editor:busy() then return end
        editor:confirmDiscard(editor:hasDrafts(),function()
            editor:cancelReads();editor.sessionOpen=false
            if editor.item and ModStudioJava then ModStudioJava.clear(editor.item) end
            back(self)
        end)
    else back(self) end
end
if WorkshopSubmitScreen.instance and WorkshopSubmitScreen.instance.page2 then decorate(WorkshopSubmitScreen.instance) end
