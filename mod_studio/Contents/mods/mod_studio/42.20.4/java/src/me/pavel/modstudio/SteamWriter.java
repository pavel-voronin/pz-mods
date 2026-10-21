package me.pavel.modstudio;

import java.lang.foreign.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.*;
import java.util.function.LongSupplier;
import org.json.JSONObject;
import zombie.HiddenFromLua;
import static java.lang.foreign.ValueLayout.*;

/** Small independent updates. All entry points pass through the game's upload confirmation. */
@HiddenFromLua
final class SteamWriter {
    final SteamReader.Calls calls;
    final LongSupplier clock;
    SteamWriter(SteamReader.Calls calls, LongSupplier clock) { this.calls=calls;this.clock=clock; }
    static SteamWriter open(Path library) { return new SteamWriter(new NativeCalls(library),System::nanoTime); }
    record Change(String operation,Object value) {}
    static String checkedText(String value,int limit) {
        if(value!=null && (value.isBlank() || value.indexOf('\0')>=0 || value.getBytes(StandardCharsets.UTF_8).length>=limit))
            throw new IllegalArgumentException("invalid_text");
        return value;
    }
    static List<String> lines(String value) {
        if(value==null) return null;
        LinkedHashSet<String> result=new LinkedHashSet<>();
        for(String part:value.split("\n")) if(!part.isBlank()) result.add(part.trim());
        return List.copyOf(result);
    }
    static String marker(String metadata) {
        if(metadata==null) return null;
        if(metadata.isBlank()) return "{\"editor\":\"mod_studio\"}";
        try {
            JSONObject object=new JSONObject(metadata);
            if("mod_studio".equals(object.optString("editor"))) return null;
            object.put("editor","mod_studio");
            String result=object.toString();
            return result.getBytes(StandardCharsets.UTF_8).length<10000?result:null;
        } catch(Exception e) { return null; } // Opaque foreign formats must stay untouched.
    }
    void start(UploadRequest r) {
        if(!r.state.equals("prepared")) return;
        try {
            r.ugc=(MemorySegment)calls.call("SteamAPI_SteamUGC_v021");
            r.utils=(MemorySegment)calls.call("SteamAPI_SteamUtils_v010");
            if(r.ugc.address()==0 || r.utils.address()==0 || (int)calls.call("SteamAPI_ISteamUtils_GetAppID",r.utils)!=108600)
                throw new IllegalStateException("steam_unavailable");
            r.state="saving";
            if(r.dependencies) nextDependency(r); else update(r);
        } catch(Throwable e) { r.fail(e); }
    }
    void update(UploadRequest r) throws Throwable {
        r.stage="start";
        r.update=(long)calls.call("SteamAPI_ISteamUGC_StartItemUpdate",r.ugc,108600,Long.parseUnsignedLong(r.itemId));
        if(r.update==0 || r.update==-1) throw new IllegalStateException("start_failed");
        try(Arena arena=Arena.ofConfined()) {
            for(Change c:r.changes) {
                r.stage=c.operation();Object value=c.value();
                if(value instanceof String text) value=arena.allocateFrom(text);
                else if(value instanceof List<?> tags) {
                    MemorySegment pointers=arena.allocate(Math.max(1,tags.size())*8L,8);
                    for(int i=0;i<tags.size();i++) pointers.setAtIndex(ADDRESS,i,arena.allocateFrom((String)tags.get(i)));
                    MemorySegment array=arena.allocate(16,8);array.set(ADDRESS,0,pointers);array.set(JAVA_INT,8,tags.size());value=array;
                }
                boolean accepted=c.operation().equals("SetItemTags")
                    ? (boolean)calls.call("SteamAPI_ISteamUGC_SetItemTags",r.ugc,r.update,value,false)
                    : (boolean)calls.call("SteamAPI_ISteamUGC_"+c.operation(),r.ugc,r.update,value);
                if(!accepted)
                    throw new IllegalStateException("setter_failed");
            }
            r.stage="submit";
            r.apiCall=(long)calls.call("SteamAPI_ISteamUGC_SubmitItemUpdate",r.ugc,r.update,
                r.changeNote==null || r.changeNote.isBlank()?MemorySegment.NULL:arena.allocateFrom(r.changeNote));
            r.callback=3404;r.callbackSize=16;
            if(r.apiCall==0) throw new IllegalStateException("submit_failed");
            r.started=clock.getAsLong();
        }
    }
    void nextDependency(UploadRequest r) throws Throwable {
        if(r.completed==r.changes.size()) {r.state="saved";return;}
        Change change=r.changes.get(r.completed);r.stage=change.operation()+":"+change.value();
        r.apiCall=(long)calls.call("SteamAPI_ISteamUGC_"+change.operation(),r.ugc,
            Long.parseUnsignedLong(r.itemId),Long.parseUnsignedLong((String)change.value()));
        r.callback=change.operation().equals("AddDependency")?3412:3413;r.callbackSize=24;
        if(r.apiCall==0) throw new IllegalStateException("dependency_failed");
        r.started=clock.getAsLong();
    }
    void poll(UploadRequest r) {
        if(!r.state.equals("saving")) return;
        try(Arena arena=Arena.ofConfined()) {
            MemorySegment failed=arena.allocate(JAVA_BOOLEAN);
            boolean completed=(boolean)calls.call("SteamAPI_ISteamUtils_IsAPICallCompleted",r.utils,r.apiCall,failed);
            if(failed.get(JAVA_BOOLEAN,0)) throw new IllegalStateException("steam_call_failed");
            if(!completed) {
                // A timeout does not prove that the server rejected an upload. Continue polling.
                r.slow=clock.getAsLong()-r.started>60_000_000_000L;
                if(!r.dependencies && r.update!=0) {
                    MemorySegment processed=arena.allocate(JAVA_LONG),total=arena.allocate(JAVA_LONG);
                    calls.call("SteamAPI_ISteamUGC_GetItemUpdateProgress",r.ugc,r.update,processed,total);
                    long n=total.get(JAVA_LONG,0);r.progress=n>0?Math.min(1,(double)processed.get(JAVA_LONG,0)/n):0;
                }
                return;
            }
            MemorySegment data=arena.allocate(r.callbackSize,8);
            if(!(boolean)calls.call("SteamAPI_ISteamUtils_GetAPICallResult",r.utils,r.apiCall,data,r.callbackSize,r.callback,failed)
                || failed.get(JAVA_BOOLEAN,0)) throw new IllegalStateException("callback_failed");
            int result=data.get(JAVA_INT,0);
            if(result!=1) throw new IllegalStateException("steam_result_"+result);
            if(r.dependencies) {
                if(data.get(JAVA_LONG,8)!=Long.parseUnsignedLong(r.itemId) || data.get(JAVA_LONG,16)!=Long.parseUnsignedLong((String)r.changes.get(r.completed).value()))
                    throw new IllegalStateException("dependency_mismatch");
                r.completed++;nextDependency(r);
            } else {
                if(data.get(JAVA_LONG,8)!=Long.parseUnsignedLong(r.itemId)) throw new IllegalStateException("item_mismatch");
                r.legal=data.get(JAVA_BOOLEAN,4);r.state="saved";r.progress=1;
            }
        } catch(Throwable e) {r.fail(e);}
    }
    static final class NativeCalls extends SteamReader.NativeCalls {
        NativeCalls(Path library) {
            super(library);
            bind(symbols,"SteamAPI_ISteamUGC_CreateItem",JAVA_LONG,ADDRESS,JAVA_INT,JAVA_INT);
            bind(symbols,"SteamAPI_ISteamUGC_StartItemUpdate",JAVA_LONG,ADDRESS,JAVA_INT,JAVA_LONG);
            for(String n:List.of("SetItemTitle","SetItemDescription","SetItemUpdateLanguage","SetItemPreview","SetItemContent","SetItemMetadata"))
                bind(symbols,"SteamAPI_ISteamUGC_"+n,JAVA_BOOLEAN,ADDRESS,JAVA_LONG,ADDRESS);
            bind(symbols,"SteamAPI_ISteamUGC_SetItemTags",JAVA_BOOLEAN,ADDRESS,JAVA_LONG,ADDRESS,JAVA_BOOLEAN);
            for(String n:List.of("SetItemVisibility","AddContentDescriptor","RemoveContentDescriptor"))
                bind(symbols,"SteamAPI_ISteamUGC_"+n,JAVA_BOOLEAN,ADDRESS,JAVA_LONG,JAVA_INT);
            bind(symbols,"SteamAPI_ISteamUGC_SubmitItemUpdate",JAVA_LONG,ADDRESS,JAVA_LONG,ADDRESS);
            bind(symbols,"SteamAPI_ISteamUGC_GetItemUpdateProgress",JAVA_INT,ADDRESS,JAVA_LONG,ADDRESS,ADDRESS);
            for(String n:List.of("AddDependency","RemoveDependency"))
                bind(symbols,"SteamAPI_ISteamUGC_"+n,JAVA_LONG,ADDRESS,JAVA_LONG,JAVA_LONG);
        }
    }
}
