package me.pavel.modstudio;

import java.lang.foreign.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.*;
import static java.lang.foreign.ValueLayout.*;

/** Synthetic Steam responses; no Steam initialization, account access or network requests. */
final class ReaderTest {
    static int checks;
    static void check(boolean value, String message) { checks++; if (!value) throw new AssertionError(message); }
    static final String DESCRIPTION = "[h1]Описание ☀[/h1]\n" + "Многоязычный текст 😃; ".repeat(100);
    static void put(MemorySegment data, long offset, String value) {
        byte[] bytes=value.getBytes(StandardCharsets.UTF_8);
        MemorySegment.copy(bytes,0,data,JAVA_BYTE,offset,bytes.length);
        data.set(JAVA_BYTE,offset+bytes.length,(byte)0);
    }
    static final class Fake implements SteamReader.Calls {
        final List<String> calls=new ArrayList<>();
        boolean completed=true, transportFailure, badIdentity, badApp, badUtf8, noMetadata;
        int releases, result=1, results=1, children=2;
        String reject;
        long now;
        SteamReader reader() { return new SteamReader(this,()->now); }
        public Object call(String full, Object... args) {
            String name=full.replace("SteamAPI_ISteamUGC_", "").replace("SteamAPI_ISteamUtils_", "");
            calls.add(name);
            if (name.equals(reject)) return false;
            return switch(name) {
                case "SteamAPI_SteamUGC_v021", "SteamAPI_SteamUtils_v010" -> MemorySegment.ofAddress(1);
                case "GetAppID" -> badApp ? 480 : 108600;
                case "CreateQueryUGCDetailsRequest" -> {
                    check(((MemorySegment)args[1]).get(JAVA_LONG,0)==3499163920L,"requested item id");
                    yield 77L;
                }
                case "SetLanguage" -> {
                    check(((MemorySegment)args[2]).getString(0).equals("russian"),"explicit Steam language"); yield true;
                }
                case "SetReturnLongDescription", "SetReturnChildren", "SetReturnMetadata" -> {
                    check(Boolean.TRUE.equals(args[2]),name+" enabled before send"); yield true;
                }
                case "SetAllowCachedResponse" -> { check(args[2].equals(0),"force fresh read"); yield true; }
                case "SendQueryUGCRequest" -> 88L;
                case "IsAPICallCompleted" -> {
                    ((MemorySegment)args[2]).set(JAVA_BOOLEAN,0,transportFailure); yield completed;
                }
                case "GetAPICallResult" -> {
                    check(args[3].equals(280) && args[4].equals(3401),"SDK callback ABI");
                    MemorySegment data=(MemorySegment)args[2];
                    data.set(JAVA_LONG,0,77L); data.set(JAVA_INT,8,result); data.set(JAVA_INT,12,results); yield true;
                }
                case "GetQueryUGCResult" -> {
                    MemorySegment data=(MemorySegment)args[3];
                    check(data.byteSize()>=9784,"v021 details include total file size");
                    data.set(JAVA_LONG,0,badIdentity?123:3499163920L); data.set(JAVA_INT,8,1);
                    data.set(JAVA_INT,20,108600); put(data,24,"Знаки Зодиака"); put(data,153,DESCRIPTION);
                    if(badUtf8) data.set(JAVA_BYTE,153,(byte)0xFF);
                    data.set(JAVA_INT,8172,1800000000); data.set(JAVA_INT,8180,2);
                    data.set(JAVA_BOOLEAN,8186,true); // Truncated old tags must not lose full tag entries.
                    data.set(JAVA_INT,9768,children); data.set(JAVA_LONG,9776,9000000000L); yield true;
                }
                case "GetQueryUGCChildren" -> {
                    MemorySegment data=(MemorySegment)args[3];
                    data.setAtIndex(JAVA_LONG,0,3619862853L); data.setAtIndex(JAVA_LONG,1,3499163921L); yield true;
                }
                case "GetQueryUGCNumTags" -> 2;
                case "GetQueryUGCTag" -> { put((MemorySegment)args[4],0,args[3].equals(0)?"Build 42":"Interface"); yield true; }
                case "GetQueryUGCMetadata" -> { put((MemorySegment)args[3],0,"existing:do_not_overwrite"); yield !noMetadata; }
                case "GetQueryUGCPreviewURL" -> { put((MemorySegment)args[3],0,"https://example.invalid/preview.png"); yield true; }
                case "GetQueryUGCContentDescriptors" -> { ((MemorySegment)args[3]).set(JAVA_INT,0,2); yield 1; }
                case "ReleaseQueryUGCRequest" -> { releases++; yield true; }
                default -> throw new AssertionError("Unexpected native operation: "+name);
            };
        }
    }
    static ReadRequest begin(Fake fake) { return fake.reader().begin("3499163920","russian"); }
    static void run(Path library) throws Exception {
        // Resolve real exports and construct FFM handles without invoking any native function.
        SteamReader.NativeCalls nativeCalls=new SteamReader.NativeCalls(library);
        check(nativeCalls.methods.size()==20,"all 20 read-only bindings exist in installed Steam DLL");
        check(nativeCalls.methods.keySet().stream().noneMatch(n->n.contains("SetItem")||n.contains("Submit")||n.contains("Init")||n.contains("RunCallbacks")),"reader cannot upload or initialize Steam");
        Fake fake=new Fake(); fake.completed=false; ReadRequest r=begin(fake);
        check(r.getState().equals("loading"),"initial loading state"); r.poll();
        check(r.getState().equals("loading") && fake.releases==0,"pending query retained");
        check(!fake.calls.contains("GetQueryUGCResult"),"do not read before successful callback");
        fake.completed=true; r.poll();
        check(r.getState().equals("loaded"),"successful read");
        check(r.getDescription().equals(DESCRIPTION),"full raw BBCode, UTF-8 and emoji survive");
        check(r.getDependencies().equals(List.of("3619862853","3499163921")),"dependency IDs");
        check(r.getTags().equals(List.of("Build 42","Interface")),"full tags, not truncated details string");
        check(r.getVisibility()==2 && r.getUpdated()==1800000000L,"publication properties");
        check(r.getMetadata().equals("existing:do_not_overwrite"),"metadata preserved verbatim");
        check(r.getContentDescriptors().equals(List.of(2)),"content descriptors");
        check(r.getTranslationPresence().equals("unknown"),"never claim fallback is a real translation");
        r.poll();r.cancel();check(fake.releases==1,"release once on success");
        List<String> dependencies=r.getDependencies();dependencies.clear();check(r.getDependencies().size()==2,"defensive result copy");
        for(String invalid:List.of("0","-1","abc","18446744073709551616")) {
            Fake f=new Fake();ReadRequest q=f.reader().begin(invalid,"russian");
            check(q.getState().equals("error") && f.calls.isEmpty(),"invalid ID rejected before Steam");
        }
        Fake unknown=new Fake();check(unknown.reader().begin("3499163920","RU").getState().equals("error")&&unknown.calls.isEmpty(),"require canonical language");
        Fake cancelled=new Fake();ReadRequest c=begin(cancelled);c.cancel();c.poll();c.cancel();
        check(c.getState().equals("cancelled")&&cancelled.releases==1&&!cancelled.calls.contains("GetQueryUGCResult"),"cancel releases pending read once");
        Fake timeout=new Fake();ReadRequest t=begin(timeout);timeout.now=SteamReader.TIMEOUT_NANOS;t.poll();
        check(t.getError().equals("timeout")&&timeout.releases==1,"timeout releases query");
        for(String failure:List.of("SetLanguage","SetReturnLongDescription","SetReturnChildren","SetReturnMetadata","SetAllowCachedResponse","GetAPICallResult","GetQueryUGCResult","GetQueryUGCChildren","GetQueryUGCTag")) {
            Fake f=new Fake();f.reject=failure;ReadRequest q=begin(f);q.poll();
            check(q.getState().equals("error")&&q.getDescription()==null&&f.releases==1,"failed read is never partial: "+failure);
            if(failure.startsWith("Set")) check(!f.calls.contains("SendQueryUGCRequest"),"no send after rejected option");
        }
        for(int condition=0;condition<7;condition++) {
            Fake f=new Fake();
            switch(condition){case 0->f.result=15;case 1->f.results=0;case 2->f.transportFailure=true;case 3->f.badIdentity=true;case 4->f.children=Integer.MAX_VALUE;case 5->f.badUtf8=true;case 6->f.badApp=true;}
            ReadRequest q=begin(f);q.poll();
            check(q.getState().equals("error")&&q.getDescription()==null,"invalid response "+condition);
            check(f.releases==(condition==6?0:1),"release on invalid response "+condition);
        }
        Fake absent=new Fake();absent.noMetadata=true;ReadRequest m=begin(absent);m.poll();
        check(m.getState().equals("loaded")&&m.getMetadata()==null,"unavailable metadata not confused with empty metadata");
        System.out.println("PASS: "+checks+" Steam reader assertions; real symbols resolved, no native calls executed.");
    }
}
