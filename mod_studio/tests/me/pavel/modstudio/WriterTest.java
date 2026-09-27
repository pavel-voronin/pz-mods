package me.pavel.modstudio;

import java.lang.foreign.*;
import java.nio.file.*;
import java.util.*;
import zombie.core.znet.*;
import static java.lang.foreign.ValueLayout.*;

final class WriterTest {
    static int checks;
    static void check(boolean condition,String message) {checks++;if(!condition) throw new AssertionError(message);}
    static final class Fake implements SteamReader.Calls {
        final LinkedHashMap<String,Object> sent=new LinkedHashMap<>();
        final List<String> calls=new ArrayList<>();
        final List<String> descriptions=new ArrayList<>();
        long child,now;boolean complete=true,badIdentity,legal;int result=1;String reject;
        SteamWriter writer(){return new SteamWriter(this,()->now);}
        public Object call(String full,Object... args) {
            String name=full.replace("SteamAPI_ISteamUGC_", "").replace("SteamAPI_ISteamUtils_", "");calls.add(name);
            if(name.equals(reject)) return false;
            if(name.startsWith("SetItem")) {
                if(name.equals("SetItemDescription")) descriptions.add(((MemorySegment)args[2]).getString(0));
                if(name.equals("SetItemTags")) {
                    check(args.length==4 && args[3].equals(false),"explicit non-admin tags flag");
                    MemorySegment array=(MemorySegment)args[2];int count=array.get(JAVA_INT,8);
                    MemorySegment pointers=array.get(ADDRESS,0).reinterpret(Math.max(1,count)*8L);List<String> tags=new ArrayList<>();
                    for(int i=0;i<count;i++) tags.add(pointers.getAtIndex(ADDRESS,i).reinterpret(256).getString(0));
                    sent.put(name,tags);
                } else sent.put(name,args[2] instanceof MemorySegment m?m.getString(0):args[2]);
                return true;
            }
            return switch(name) {
                case "SteamAPI_SteamUGC_v021","SteamAPI_SteamUtils_v010" -> MemorySegment.ofAddress(1);
                case "GetAppID" -> 108600;
                case "CreateItem" -> {check(args[1].equals(108600) && args[2].equals(0),"creation app/file type");yield 99L;}
                case "StartItemUpdate" -> {check(args[2].equals(1234567890L),"publication id");yield 77L;}
                case "AddContentDescriptor","RemoveContentDescriptor" -> {sent.put(name,args[2]);yield true;}
                case "SubmitItemUpdate" -> {MemorySegment note=(MemorySegment)args[2];sent.put(name,note.address()==0?null:note.getString(0));yield 88L;}
                case "AddDependency","RemoveDependency" -> {child=(long)args[2];sent.put(name,child);yield 88L;}
                case "IsAPICallCompleted" -> complete;
                case "GetItemUpdateProgress" -> {((MemorySegment)args[2]).set(JAVA_LONG,0,40L);((MemorySegment)args[3]).set(JAVA_LONG,0,100L);yield 3;}
                case "GetAPICallResult" -> {
                    MemorySegment data=(MemorySegment)args[2];int callback=(int)args[4];
                    check((callback==3404&&(int)args[3]==16)||((callback==3403||callback==3412||callback==3413)&&(int)args[3]==24),"callback ABI");
                    data.set(JAVA_INT,0,result);data.set(JAVA_LONG,8,badIdentity?2:1234567890L);
                    if(callback==3404) data.set(JAVA_BOOLEAN,4,legal);else if(callback==3403) data.set(JAVA_BOOLEAN,16,legal);else data.set(JAVA_LONG,16,child);yield true;
                }
                default -> throw new AssertionError("Unexpected operation "+name);
            };
        }
    }
    static Fake use() {Bridge.activeUpload=null;Fake fake=new Fake();Bridge.writer=fake.writer();return fake;}
    static void run(Path library,Path folder) throws Exception {
        SteamWriter.NativeCalls bindings=new SteamWriter.NativeCalls(library);
        check(bindings.methods.size()==36,"all read/write exports resolve without invoking writes");
        SteamWorkshopItem item=new SteamWorkshopItem(folder.toString());item.setID("1234567890");
        check(LocalFiles.dependencies(item).isEmpty(),"mod without require imports no dependencies");
        var own=zombie.gameStates.ChooseGameInfo.readModInfo(folder.resolve("Contents/mods/fixture").toString());
        check(own!=null && own.getId().equals("ModStudioTest"),"game parser finds versioned local mod");
        Path dependency=folder.getParent().resolve("known-dependency");
        Path dependencyMod=dependency.resolve("Contents/mods/known/42.20.4");Files.createDirectories(dependencyMod);
        Files.writeString(dependencyMod.resolve("mod.info"),"name=Known\nid=KnownDependency\n");
        Files.writeString(dependency.resolve("workshop.txt"),"version=1\nid=1234567891\n");
        zombie.ZomboidFileSystem.instance.setModIdToDir("KnownDependency",dependencyMod.getParent().toString());
        own.setRequire(new ArrayList<>(List.of("\\KnownDependency","ModStudioTest","DoesNotExist")));
        check(LocalFiles.dependencies(item).equals(List.of("1234567891")),"import resolves staged Workshop ID, ignores own and unknown Mod IDs");
        own.setRequire(null);
        Bridge.confirmation=i->SteamWorkshop.instance.SubmitWorkshopItem(i);
        Fake f=use();UploadRequest r=Bridge.saveText(item,"russian","Знаки 😃",null,null);
        check(f.sent.keySet().equals(new LinkedHashSet<>(List.of("SetItemUpdateLanguage","SetItemTitle","SubmitItemUpdate"))),"title-only omits description, content, tags, visibility, preview");
        check(f.sent.get("SetItemTitle").equals("Знаки 😃"),"UTF-8 sent losslessly");
        r.poll();check(r.getState().equals("saved"),"successful update");
        f=use();r=Bridge.saveText(item,"german",null,"Beschreibung","");r.poll();
        check(!f.sent.containsKey("SetItemTitle") && f.sent.containsKey("SetItemDescription"),"description-only");
        check(f.sent.get("SetItemMetadata").equals("{\"editor\":\"mod_studio\"}"),"empty metadata gets editor marker");
        check(SteamWriter.marker(null)==null && SteamWriter.marker("other-format:data")==null,"unavailable and opaque metadata preserved");
        check(new org.json.JSONObject(SteamWriter.marker("{\"custom\":42}")).getInt("custom")==42,"merge keeps foreign JSON members");
        f=use();r=Bridge.saveSettings(item,null,3,"2\n5","1\n5",null);r.poll();
        check(!f.sent.containsKey("SetItemTags") && f.sent.get("SetItemVisibility").equals(3),"visibility-only does not send tags");
        check(f.sent.get("AddContentDescriptor").equals(1) && f.sent.get("RemoveContentDescriptor").equals(2),"descriptor delta");
        f=use();r=Bridge.saveSettings(item,"Build 42\nInterface",-1,"","",null);r.poll();
        check(f.sent.get("SetItemTags").equals(List.of("Build 42","Interface")),"SteamParamStringArray ABI");
        check(!f.sent.containsKey("SetItemVisibility"),"tag-only omits visibility");
        f=use();r=Bridge.saveSettings(item,"",-1,"","",null);r.poll();check(f.sent.get("SetItemTags").equals(List.of()),"empty tag set is deliberate");
        f=use();r=Bridge.savePreview(item,folder.resolve("preview.png").toString(),null);r.poll();
        check(f.sent.keySet().equals(new LinkedHashSet<>(List.of("SetItemPreview","SubmitItemUpdate"))),"preview-only");
        Path gif=folder.resolve("selected.gif");
        javax.imageio.ImageIO.write(new java.awt.image.BufferedImage(32,16,java.awt.image.BufferedImage.TYPE_INT_RGB),"gif",gif.toFile());
        f=use();r=Bridge.savePreview(item,gif.toString(),null);r.poll();check(f.sent.get("SetItemPreview").equals(gif.toString()),"Steam gets original GIF, not the UI thumbnail");
        Files.delete(gif);
        f=use();r=Bridge.publishFiles(item,"Fixed an issue",null);r.poll();
        check(f.sent.keySet().equals(new LinkedHashSet<>(List.of("SetItemContent","SubmitItemUpdate"))),"file publication omits all descriptive fields");
        check(f.sent.get("SubmitItemUpdate").equals("Fixed an issue"),"change note belongs only to file update");
        f=use();r=Bridge.saveDependencies(item,"12\n13","12\n14");r.poll();r.poll();
        check(r.getState().equals("saved") && r.getCompletedOperations()==2,"dependency callbacks are sequential");
        check(f.sent.get("AddDependency").equals(14L) && f.sent.get("RemoveDependency").equals(13L),"dependency diff preserves unchanged manual items");
        check(!f.calls.contains("StartItemUpdate"),"dependencies have independent API calls");
        f=use();r=Bridge.saveDependencies(item,"12\n13","12\n14");r.poll();f.result=15;r.poll();
        check(r.getState().equals("error") && r.getCompletedOperations()==1,"partial dependency failure is visible");
        f=use();f.complete=false;r=Bridge.saveText(item,"english","Changed",null,null);f.now=61_000_000_000L;r.poll();
        check(r.isSlow() && r.getState().equals("saving") && r.getProgress()==0.4,"slow updates stay pending, not false failure");
        boolean blocked=false;try{Bridge.saveText(item,"english","Again",null,null);}catch(IllegalStateException e){blocked=true;}
        check(blocked,"duplicate concurrent writes blocked");f.complete=true;r.poll();
        f=use();Bridge.confirmation=i->false;r=Bridge.saveText(item,"english","Changed",null,null);
        check(r.getState().equals("cancelled") && f.calls.isEmpty(),"cancelled game confirmation sends nothing");
        Bridge.confirmation=i->SteamWorkshop.instance.SubmitWorkshopItem(i);
        f=use();f.reject="SetItemTitle";r=Bridge.saveText(item,"english","Changed",null,null);
        check(r.getState().equals("error")&&!f.calls.contains("SubmitItemUpdate"),"rejected setter prevents submission");
        f=use();f.badIdentity=true;r=Bridge.saveText(item,"english","Changed",null,null);r.poll();check(r.getState().equals("error"),"callback identity checked");
        f=use();f.legal=true;r=Bridge.saveText(item,"english","Changed",null,null);r.poll();check(r.needsLegalAgreement(),"legal agreement callback visible");
        f=use();boolean invalid=false;try{Bridge.saveText(item,"english","я".repeat(65),null,null);}catch(IllegalArgumentException e){invalid=true;}
        check(invalid&&f.calls.isEmpty(),"title byte limit checked before native calls");
        Path txt=folder.resolve("workshop.txt");
        Files.writeString(txt,"# keep comment\nversion=1\nid=1234567890\ntitle=Old\ndescription=Before\ntags=Keep\nvisibility=private\ncustom=yes\n");
        LocalFiles.saveEnglish(item,"New","Text with description= intact\n\nSecond line 😃");
        var loaded=LocalFiles.loadEnglish(item);check(loaded.equals(List.of("New","Text with description= intact\n\nSecond line 😃")),"local English lossless round trip");
        String saved=Files.readString(txt);check(saved.contains("# keep comment")&&saved.contains("tags=Keep")&&saved.contains("custom=yes")&&saved.contains("id=1234567890"),"local save changes only title and description");
        LocalFiles.saveId(item);check(LocalFiles.loadEnglish(item).equals(loaded),"ID save preserves all text");
        try(var files=Files.list(folder)){check(files.noneMatch(p->p.getFileName().toString().startsWith(".mod-studio")),"atomic save temporary file cleaned");}
        SteamWorkshopItem fresh=new SteamWorkshopItem(folder.toString());
        f=use();Bridge.confirmation=i->false;
        PublicationRequest publication=Bridge.newPublication(fresh,"Title","Description","preview.png","Build 42",0,"2","First release");
        publication.addLanguage("german","Deutsch",null);publication.addDependencies("12\n13");
        Bridge.publishNew(publication);
        check(publication.getState().equals("cancelled") && f.calls.isEmpty(),"new publication cancellation never creates an empty item");
        Bridge.confirmation=i->SteamWorkshop.instance.SubmitWorkshopItem(i);
        publication=Bridge.newPublication(fresh,"Title","Description","preview.png","Build 42",0,"2","First release");
        publication.addLanguage("german","Deutsch",null);publication.addDependencies("12\n13");
        Bridge.publishNew(publication);check(f.calls.contains("CreateItem") && !f.calls.contains("StartItemUpdate"),"create precedes update");
        publication.poll();check(fresh.getID().equals("1234567890") && Files.readString(txt).contains("id=1234567890"),"allocated ID saved before initial content");
        String originalDescription=fresh.getDescription();
        fresh.setDescription("Description");String nativeDescription=fresh.getSubmitDescription();fresh.setDescription(originalDescription);
        check(f.descriptions.equals(List.of(nativeDescription)) && nativeDescription.contains("Workshop ID: 1234567890") && nativeDescription.contains("Mod ID: "),"new publication appends native package identifiers after ID allocation");
        check(fresh.getDescription().equals(originalDescription),"publication leaves local description unchanged");
        check(f.sent.get("SetItemVisibility").equals(2) && f.sent.containsKey("SetItemContent") && f.sent.containsKey("SetItemPreview"),"initial batch includes content and selected preview, stays private");
        f.result=15;publication.poll();check(publication.canRetry() && publication.getState().equals("error"),"failed initial batch retryable");
        Bridge.confirmation=i->false;int beforeCancelledRetry=f.calls.size();Bridge.publishNew(publication);
        check(publication.canRetry() && f.calls.size()==beforeCancelledRetry,"cancelled retry preserves unfinished plan and sends nothing");
        Bridge.confirmation=i->SteamWorkshop.instance.SubmitWorkshopItem(i);
        f.result=1;Bridge.publishNew(publication);for(int i=0;i<8;i++) publication.poll();
        check(publication.getState().equals("saved") && Collections.frequency(f.calls,"CreateItem")==1,"retry reuses ID and completes all steps");
        check(f.descriptions.equals(List.of(nativeDescription,nativeDescription)),"retry does not duplicate identifiers; title-only language omits description");
        Fake edits=use();var edited=Bridge.saveText(fresh,"english",null,"Freely edited description",null);edited.poll();
        check(edits.descriptions.equals(List.of("Freely edited description")),"later description edits do not restore identifiers");
        check(f.sent.get("SetItemUpdateLanguage").equals("german") && f.sent.get("SetItemVisibility").equals(0),"extra language uploaded before final visibility");
        check(Collections.frequency(f.calls,"AddDependency")==2,"each dependency sent exactly once");
        f=use();fresh=new SteamWorkshopItem(folder.toString());
        publication=Bridge.newPublication(fresh,"Title","Description","preview.png","",2,"",null);
        publication.addLanguage("russian","Русский","Описание");Bridge.publishNew(publication);publication.poll();publication.poll();
        check(f.descriptions.getLast().startsWith("Описание\n\nWorkshop ID: 1234567890") && f.descriptions.getLast().contains("Mod ID: "),"new localized description gets the same native identifiers");
        f.result=15;publication.poll();check(publication.completed==1 && publication.canRetry(),"failure preserves completed initial step");
        f.result=1;int initialContents=Collections.frequency(f.calls,"SetItemContent");Bridge.publishNew(publication);publication.poll();
        check(publication.state.equals("saved") && Collections.frequency(f.calls,"SetItemContent")==initialContents,"language retry does not reupload files");
        f=use();fresh=new SteamWorkshopItem(folder.toString());
        publication=Bridge.newPublication(fresh,"Title","Description","preview.png","",2,"",null);
        Bridge.publishNew(publication);f.reject="GetAPICallResult";publication.poll();
        check(publication.state.equals("error") && !publication.canRetry(),"uncertain creation result cannot duplicate publication");
        AssetTest.run(folder);
        Bridge.writer=null;Bridge.activeUpload=null;Bridge.confirmation=SteamWorkshopItem::submitUpdate;
        System.out.println("PASS: "+checks+" writer/local-file assertions; no Steam write calls executed.");
    }
}
