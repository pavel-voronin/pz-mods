package me.pavel.modstudio;

import java.lang.foreign.*;
import java.util.*;
import me.zed_0xff.zombie_buddy.Exposer;
import zombie.core.znet.SteamWorkshopItem;
import static java.lang.foreign.ValueLayout.*;

/** One editor action, several Steam updates. An allocated ID is never allocated again. */
@Exposer.LuaClass(name="ModStudioPublicationRequest")
public final class PublicationRequest extends UploadRequest {
    final SteamWorkshopItem item;
    record Step(String name,List<SteamWriter.Change> changes,String note,boolean dependency) {}
    final List<Step> steps=new ArrayList<>();
    final int visibility;
    boolean sealed,ambiguousCreate,idSaved;
    UploadRequest current;
    PublicationRequest(SteamWriter writer,SteamWorkshopItem item,String title,String description,String preview,String tags,int visibility,String descriptors,String note) throws Exception {
        super(writer,item.getID(),List.of(),null,false);this.item=item;this.visibility=visibility;
        Bridge.validateFiles(item);
        SteamWriter.checkedText(title,129);SteamWriter.checkedText(description,8000);
        if(title==null || description==null || preview==null || visibility<0 || visibility>3) throw new IllegalArgumentException("missing_required");
        if(note!=null && note.indexOf('\0')>=0) throw new IllegalArgumentException("invalid_note");
        var path=LocalFiles.assetPath(item,preview);LocalFiles.checkPreview(path);
        List<SteamWriter.Change> changes=new ArrayList<>();
        Bridge.add(changes,"SetItemUpdateLanguage","english");Bridge.add(changes,"SetItemTitle",title);Bridge.add(changes,"SetItemDescription",description);
        Bridge.add(changes,"SetItemContent",item.getContentFolder());Bridge.add(changes,"SetItemPreview",path.toString());
        Bridge.add(changes,"SetItemVisibility",2); // Stay private until every selected language/dependency is uploaded.
        var tagList=SteamWriter.lines(tags);
        if(tagList==null) throw new IllegalArgumentException("missing_tags");
        for(String tag:tagList) {SteamWriter.checkedText(tag,256);if(tag.indexOf(',')>=0 || tag.chars().anyMatch(c->c<32||c==127)) throw new IllegalArgumentException("invalid_tag");}
        Bridge.add(changes,"SetItemTags",tagList);Bridge.add(changes,"SetItemMetadata",SteamWriter.marker(""));
        var content=SteamWriter.lines(descriptors);
        if(content==null) throw new IllegalArgumentException("missing_descriptors");
        for(String id:content) {if(!List.of("1","2","3","4","5").contains(id)) throw new IllegalArgumentException("invalid_descriptor");Bridge.add(changes,"AddContentDescriptor",Integer.parseInt(id));}
        steps.add(new Step("initial",List.copyOf(changes),note,false));
        item.setTitle(title); // The original game's confirmation must show the title being published.
    }
    public void addLanguage(String language,String title,String description) {
        if(sealed || !state.equals("prepared")) throw new IllegalStateException("sealed");
        if(!SteamReader.LANGUAGES.contains(language) || language.equals("english")) throw new IllegalArgumentException("invalid_language");
        List<SteamWriter.Change> changes=new ArrayList<>();Bridge.add(changes,"SetItemUpdateLanguage",language);
        Bridge.add(changes,"SetItemTitle",SteamWriter.checkedText(title,129));Bridge.add(changes,"SetItemDescription",SteamWriter.checkedText(description,8000));
        if(changes.size()==1) return;
        steps.add(new Step(language,List.copyOf(changes),null,false));
    }
    public void addDependencies(String ids) {
        if(sealed || !state.equals("prepared")) throw new IllegalStateException("sealed");
        for(String id:SteamWriter.lines(ids)) {
            if(!id.matches("[1-9][0-9]{0,19}")) throw new IllegalArgumentException("invalid_dependency");Long.parseUnsignedLong(id);
            steps.add(new Step("dependency:"+id,List.of(new SteamWriter.Change("AddDependency",id)),null,true));
        }
    }
    @Override void start() {
        try {
            if(!sealed) {if(visibility!=2) steps.add(new Step("visibility",List.of(new SteamWriter.Change("SetItemVisibility",visibility)),null,false));sealed=true;}
            state="saving";error=null;slow=false;
            if(itemId!=null) {next();return;}
            stage="create";
            ugc=(MemorySegment)writer.calls.call("SteamAPI_SteamUGC_v021");utils=(MemorySegment)writer.calls.call("SteamAPI_SteamUtils_v010");
            if(ugc.address()==0 || utils.address()==0 || (int)writer.calls.call("SteamAPI_ISteamUtils_GetAppID",utils)!=108600) throw new IllegalStateException("steam_unavailable");
            apiCall=(long)writer.calls.call("SteamAPI_ISteamUGC_CreateItem",ugc,108600,0);
            if(apiCall==0) throw new IllegalStateException("create_failed");
            ambiguousCreate=true;started=writer.clock.getAsLong();
        } catch(Throwable e) {fail(e);}
    }
    void next() throws Exception {
        if(!idSaved) {stage="save_id";LocalFiles.saveId(item);idSaved=true;}
        if(completed==steps.size()) {state="saved";progress=1;current=null;return;}
        Step step=steps.get(completed);stage=step.name();
        List<SteamWriter.Change> changes=new ArrayList<>();
        for(var change:step.changes()) {
            if(change.operation().equals("SetItemDescription")) {
                String previous=item.getDescription();
                try {
                    item.setDescription((String)change.value());
                    changes.add(new SteamWriter.Change(change.operation(),SteamWriter.checkedText(item.getSubmitDescription(),8000)));
                } finally {item.setDescription(previous);}
            } else changes.add(change);
        }
        // Keep the original step text so retries never append the native footer twice.
        current=new UploadRequest(writer,itemId,changes,step.note(),step.dependency());current.start();
        if(current.state.equals("error")) fail(new IllegalStateException(current.error));
    }
    @Override public void poll() {
        if(!state.equals("saving")) return;
        try {
            if(itemId==null) {
                try(Arena arena=Arena.ofConfined()) {
                    MemorySegment failed=arena.allocate(JAVA_BOOLEAN);
                    boolean done=(boolean)writer.calls.call("SteamAPI_ISteamUtils_IsAPICallCompleted",utils,apiCall,failed);
                    if(failed.get(JAVA_BOOLEAN,0)) throw new IllegalStateException("create_result_unknown");
                    if(!done) {slow=writer.clock.getAsLong()-started>60_000_000_000L;return;}
                    MemorySegment data=arena.allocate(24,8);
                    if(!(boolean)writer.calls.call("SteamAPI_ISteamUtils_GetAPICallResult",utils,apiCall,data,24,3403,failed) || failed.get(JAVA_BOOLEAN,0)) throw new IllegalStateException("create_result_unknown");
                    int result=data.get(JAVA_INT,0);
                    if(result!=1) {ambiguousCreate=false;throw new IllegalStateException("steam_result_"+result);}
                    long id=data.get(JAVA_LONG,8);if(id==0) throw new IllegalStateException("create_result_unknown");
                    itemId=Long.toUnsignedString(id);item.setID(itemId);legal=data.get(JAVA_BOOLEAN,16);ambiguousCreate=false;
                    next();
                }
            } else if(current!=null) {
                current.poll();slow=current.slow;progress=(completed+current.progress)/steps.size();
                if(current.state.equals("error")) fail(new IllegalStateException(current.error));
                else if(current.state.equals("saved")) {legal|=current.legal;completed++;next();}
            }
        } catch(Throwable e) {fail(e);}
    }
    public boolean canRetry(){return state.equals("error") && !ambiguousCreate;}
    public String getItemId(){return itemId;}
}
