package me.pavel.modstudio;

import java.io.IOException;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

final class ManifestTest {
    static int checks;
    static void check(boolean test,String message){checks++;if(!test) throw new AssertionError(message);}
    static String hash(String content) throws Exception {return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-1").digest(content.getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
    static class Transport implements ManifestSource.Transport {
        String id="123";int ids,fetches;boolean failed,changesDuringRead;Map<String,String> files=new HashMap<>();
        public String currentId(String item) throws Exception {ids++;if(failed) throw new IOException("offline");return id;}
        public Map<String,String> fetch(String manifest,Consumer<String> progress) throws Exception {fetches++;if(changesDuringRead) id="456";return files;}
    }
    static ManifestSource sourceFor(Path root) throws Exception {
        Transport transport=new Transport();
        for(var file:new FileScan().read(root).entrySet()) transport.files.put(file.getKey(),file.getValue().bytes()+":"+file.getValue().hash());
        return new ManifestSource(transport);
    }
    static ManifestSource unavailable(){Transport t=new Transport();t.failed=true;return new ManifestSource(t);}
    static void await(FileScan scan) throws Exception {
        long until=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
        while(scan.getState().equals("loading") && System.nanoTime()<until) Thread.sleep(5);
        check(!scan.getState().equals("loading"),"scan must complete or cancel promptly");
    }
    static void run(Path folder) throws Exception {
        Transport t=new Transport();t.files.put("mods/abc.txt","3:"+hash("old"));
        ManifestSource source=new ManifestSource(t);
        var first=source.load("123",s->{});check(t.ids==2 && t.fetches==1,"manifest identity checked before and after download");
        var second=source.load("123",s->{});check(first==second && t.ids==3 && t.fetches==1,"fresh ID check reuses unchanged manifest");
        t.id="456";source.load("123",s->{});check(t.fetches==2,"changed remote revision replaces cached snapshot");
        t.failed=true;boolean failed=false;
        try{source.load("123",s->{});}catch(IOException e){failed=true;}
        check(failed,"offline refresh never treats cached manifest as current");
        t.failed=false;t.id="123";t.changesDuringRead=true;failed=false;
        try{new ManifestSource(t).load("123",s->{});}catch(IOException e){failed=e.getMessage().equals("manifest_changed");}
        check(failed,"publication replaced during fetch cannot be shown as current");
        for(String path:List.of("/absolute","../escape","a/../b","C:/absolute","a\\b","a//b","a/./b","a\tb")) {
            failed=false;try{ManifestSource.parse(Map.of(path,"3:"+hash("old")));}catch(IOException e){failed=true;}
            check(failed,"invalid remote filename rejected: "+path);
        }
        for(String value:List.of("-1:"+hash("old"),"3:123","abc:"+hash("old"),"9223372036854775808:"+hash("old"))) {
            failed=false;try{ManifestSource.parse(Map.of("valid",value));}catch(IOException e){failed=true;}
            check(failed,"bad fingerprint cannot look unchanged");
        }
        Path local=folder.resolve("manifest-fixture");Files.createDirectories(local.resolve("mods"));Files.writeString(local.resolve("mods/abc.txt"),"old");
        Transport fixtures=new Transport();fixtures.files.put("mods/abc.txt","3:"+hash("old"));var comparison=new ManifestSource(fixtures);
        FileScan scan=FileScan.start(local,"123",comparison);await(scan);
        check(scan.getBasis().equals("manifest") && scan.getUnchanged()==1 && scan.getAdded()+scan.getModified()+scan.getRemoved()==0,"matching SHA-1 is unchanged");
        Files.writeString(local.resolve("mods/abc.txt"),"new");Files.writeString(local.resolve("mods/added.txt"),"");
        scan=FileScan.start(local,"123",comparison);await(scan);check(scan.getAdded()==1 && scan.getModified()==1,"equal-sized edit and empty added file detected on refresh");
        Files.delete(local.resolve("mods/abc.txt"));scan=FileScan.start(local,"123",comparison);await(scan);
        check(scan.getRemoved()==1 && scan.getEntries().contains("removed\tmods/abc.txt"),"removed file remains visible without local copy");
        scan=FileScan.start(local,"123",unavailable());await(scan);
        check(scan.getState().equals("ready") && scan.getBasis().equals("unknown") && scan.getComparisonError()!=null && scan.getUnchanged()==0,"network failure leaves a usable unverified local listing");
        CountDownLatch entered=new CountDownLatch(1),interrupted=new CountDownLatch(1);
        var slow=new ManifestSource(new Transport(){public String currentId(String id) throws Exception {entered.countDown();try{Thread.sleep(20000);}catch(InterruptedException e){interrupted.countDown();throw e;}return "123";}});
        scan=FileScan.start(local,"123",slow);check(entered.await(2,TimeUnit.SECONDS),"worker starts away from UI thread");scan.cancel();await(scan);
        check(interrupted.await(2,TimeUnit.SECONDS) && scan.getState().equals("cancelled"),"closing/refresh interrupts outstanding read and cannot publish its result");
        scan=FileScan.start(folder.resolve("missing"),null,unavailable());await(scan);check(scan.getState().equals("error"),"local scan failure cannot be reported as no changes");
        System.out.println("PASS: "+checks+" manifest/cache/diff/cancellation checks; no network calls.");
    }
}
