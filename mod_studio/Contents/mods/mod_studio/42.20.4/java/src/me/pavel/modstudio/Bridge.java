package me.pavel.modstudio;

import java.util.ArrayList;
import java.util.List;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Exposer;
import zombie.core.znet.SteamWorkshopItem;

/** Editor reads and selection are exposed. Publishing still uses the game's confirmation. */
@Exposer.LuaClass(name="ModStudioJava")
public final class Bridge {
    private static SteamReader reader;
    static SteamWriter writer;
    static UploadRequest activeUpload;
    interface Confirmation { boolean submit(SteamWorkshopItem item); }
    static Confirmation confirmation=SteamWorkshopItem::submitUpdate;

    public static boolean isUploading() { return activeUpload!=null && activeUpload.getState().equals("saving"); }
    static UploadRequest send(SteamWorkshopItem item,List<SteamWriter.Change> changes,String note,boolean dependencies) {
        if(!Guard.ready() || isUploading()) throw new IllegalStateException("unavailable_or_busy");
        String id=item.getID();
        if(id==null || !id.matches("[1-9][0-9]{0,19}")) throw new IllegalArgumentException("invalid_id");
        Long.parseUnsignedLong(id);
        if(changes.isEmpty()) throw new IllegalArgumentException("no_changes");
        if(writer==null) writer=SteamWriter.open(Path.of("steam_api64.dll"));
        UploadRequest request=new UploadRequest(writer,id,changes,note,dependencies);
        return confirm(item,request);
    }
    static UploadRequest confirm(SteamWorkshopItem item,UploadRequest request) {
        if(!Guard.ready() || isUploading()) throw new IllegalStateException("unavailable_or_busy");
        Guard.editorItem=item;Guard.editorRequest=request;
        try {
            confirmation.submit(item); // Original game dialog; the patched submit consumes this request once.
            if(request.state.equals("prepared")) request.state="cancelled";
        } catch(Throwable e) {request.fail(e);}
        finally {Guard.editorItem=null;Guard.editorRequest=null;}
        activeUpload=request;
        return request;
    }
    public static PublicationRequest newPublication(SteamWorkshopItem item,String title,String description,String preview,String tags,int visibility,String descriptors,String note) throws Exception {
        if(!Guard.ready() || isUploading() || item.getID()!=null) throw new IllegalStateException("unavailable_or_existing");
        if(writer==null) writer=SteamWriter.open(Path.of("steam_api64.dll"));
        return new PublicationRequest(writer,item,title,description,preview,tags,visibility,descriptors,note);
    }
    public static PublicationRequest publishNew(PublicationRequest request) {
        if(!request.getState().equals("prepared") && !request.canRetry()) throw new IllegalStateException("cannot_retry");
        boolean retry=request.canRetry();
        request.state="prepared";confirm(request.item,request);
        if(retry && request.state.equals("cancelled")) request.state="error"; // Keep the unfinished plan after cancelling its retry.
        return request;
    }
    static void add(List<SteamWriter.Change> changes,String key,Object value) {
        if(value!=null) changes.add(new SteamWriter.Change(key,value));
    }
    public static UploadRequest saveText(SteamWorkshopItem item,String language,String title,String description,String metadata) {
        if(!SteamReader.LANGUAGES.contains(language)) throw new IllegalArgumentException("invalid_language");
        if(title==null && description==null) throw new IllegalArgumentException("no_changes");
        List<SteamWriter.Change> changes=new ArrayList<>();
        add(changes,"SetItemUpdateLanguage",language);
        add(changes,"SetItemTitle",SteamWriter.checkedText(title,129));
        add(changes,"SetItemDescription",SteamWriter.checkedText(description,8000));
        add(changes,"SetItemMetadata",SteamWriter.marker(metadata));
        return send(item,changes,null,false);
    }
    public static UploadRequest saveSettings(SteamWorkshopItem item,String tags,int visibility,String descriptorsBefore,String descriptorsAfter,String metadata) {
        List<SteamWriter.Change> changes=new ArrayList<>();
        List<String> tagList=SteamWriter.lines(tags);
        if(tagList!=null) for(String tag:tagList) {
            SteamWriter.checkedText(tag,256);
            if(tag.indexOf(',')>=0 || tag.chars().anyMatch(c->c<32 || c==127)) throw new IllegalArgumentException("invalid_tag");
        }
        add(changes,"SetItemTags",tagList);
        if(visibility>=0) {
            if(visibility>3) throw new IllegalArgumentException("invalid_visibility");
            add(changes,"SetItemVisibility",visibility);
        }
        List<String> before=SteamWriter.lines(descriptorsBefore),after=SteamWriter.lines(descriptorsAfter);
        if(before==null || after==null) throw new IllegalArgumentException("missing_descriptors");
        for(String id:before) if(!List.of("1","2","3","4","5").contains(id)) throw new IllegalArgumentException("invalid_descriptor");
        for(String id:after) if(!List.of("1","2","3","4","5").contains(id)) throw new IllegalArgumentException("invalid_descriptor");
        for(String id:after) if(!before.contains(id)) add(changes,"AddContentDescriptor",Integer.parseInt(id));
        for(String id:before) if(!after.contains(id)) add(changes,"RemoveContentDescriptor",Integer.parseInt(id));
        if(changes.isEmpty()) throw new IllegalArgumentException("no_changes");
        add(changes,"SetItemMetadata",SteamWriter.marker(metadata));
        return send(item,changes,null,false);
    }
    public static UploadRequest savePreview(SteamWorkshopItem item,String path,String metadata) throws Exception {
        Path selected=LocalFiles.assetPath(item,path);LocalFiles.checkPreview(selected);
        List<SteamWriter.Change> changes=new ArrayList<>();
        add(changes,"SetItemPreview",selected.toString());
        add(changes,"SetItemMetadata",SteamWriter.marker(metadata));
        return send(item,changes,null,false);
    }
    public static UploadRequest saveDependencies(SteamWorkshopItem item,String before,String after) {
        List<String> previous=SteamWriter.lines(before),next=SteamWriter.lines(after);
        if(previous==null || next==null) throw new IllegalArgumentException("missing_dependencies");
        for(List<String> ids:List.of(previous,next)) for(String id:ids) {
            if(!id.matches("[1-9][0-9]{0,19}") || id.equals(item.getID())) throw new IllegalArgumentException("invalid_dependency");
            Long.parseUnsignedLong(id);
        }
        List<SteamWriter.Change> changes=new ArrayList<>();
        for(String id:next) if(!previous.contains(id)) add(changes,"AddDependency",id);
        for(String id:previous) if(!next.contains(id)) add(changes,"RemoveDependency",id);
        return send(item,changes,null,true);
    }
    public static UploadRequest publishFiles(SteamWorkshopItem item,String note,String metadata) {
        validateFiles(item);
        if(note!=null && note.indexOf('\0')>=0) throw new IllegalArgumentException("invalid_note");
        List<SteamWriter.Change> changes=new ArrayList<>();
        add(changes,"SetItemContent",item.getContentFolder());
        add(changes,"SetItemMetadata",SteamWriter.marker(metadata));
        return send(item,changes,note,false);
    }
    static void validateFiles(SteamWorkshopItem item) {
        boolean old=Guard.omitPreview.get();Guard.omitPreview.set(true);
        try {
            String error=LocalFiles.validateContents(item);
            if(error!=null) throw new IllegalArgumentException(error);
        } finally {Guard.omitPreview.set(old);}
    }
    public static FileScan scanFiles(SteamWorkshopItem item) {
        return FileScan.start(Path.of(item.getContentFolder()),item.getID(),ManifestSource.LIVE);
    }
    public static ArrayList<String> loadEnglish(SteamWorkshopItem item) throws Exception {return LocalFiles.loadEnglish(item);}
    public static String loadReleaseNotes(SteamWorkshopItem item) throws Exception {return LocalFiles.loadReleaseNotes(item);}
    public static void saveEnglish(SteamWorkshopItem item,String title,String description) throws Exception {LocalFiles.saveEnglish(item,title,description);}
    public static void saveId(SteamWorkshopItem item) throws Exception {LocalFiles.saveId(item);}
    public static ArrayList<String> importDependencies(SteamWorkshopItem item) throws Exception {return LocalFiles.dependencies(item);}
    public static ArrayList<PackageEntry> listAssets(SteamWorkshopItem item,String folder) throws Exception {return LocalFiles.listAssets(item,folder);}
    public static PreviewAnimation previewAnimation(SteamWorkshopItem item,String file) throws Exception {return PreviewAnimation.open(LocalFiles.assetPath(item,file));}
    public static PreviewInfo previewInfo(SteamWorkshopItem item,String file) throws Exception {return LocalFiles.inspectPreview(LocalFiles.assetPath(item,file),LocalFiles.PREVIEW_UPLOAD_BYTES);}
    public static PreviewDownload downloadPreview(ReadRequest snapshot) {return PreviewDownload.start(snapshot);}
    public static String saveWorkshopPreview(SteamWorkshopItem item,PreviewDownload download) throws Exception {return LocalFiles.savePreviewCopy(item,download);}
    /** Call poll from the UI tick and cancel when its editor closes. No writes are performed. */
    public static ReadRequest readWorkshop(String itemId, String language) {
        if (!Guard.ready()) throw new IllegalStateException("Mod Studio is unavailable");
        if (reader == null) reader = SteamReader.open(java.nio.file.Path.of("steam_api64.dll"));
        return reader.begin(itemId, language);
    }
    public static boolean isReady() { return Guard.ready() && LuaBindings.ensure(); }
    public static void begin(SteamWorkshopItem item) { Guard.selections.put(item, new Selection(item.getID())); }
    public static void configure(SteamWorkshopItem item, int keepMask) {
        Selection s = Guard.selection(item);
        if (s != null) s.configure(keepMask);
    }
    public static String validate(SteamWorkshopItem item, boolean finalCheck) { return Guard.validate(item, finalCheck); }
    public static boolean arm(SteamWorkshopItem item) {
        if (Guard.validate(item, true) != null) return false;
        Guard.selection(item).armed = true;
        return true;
    }
    public static ArrayList<String> drain(SteamWorkshopItem item) { return Guard.drain(item); }
    public static void clear(SteamWorkshopItem item) { Guard.selections.remove(item); }
}
