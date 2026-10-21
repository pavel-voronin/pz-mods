package me.pavel.modstudio;

import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.MessageDigest;
import java.util.*;
import me.zed_0xff.zombie_buddy.Exposer;

/** Local hashes compared with a freshly identified Steam manifest, without downloading mod files. */
@Exposer.LuaClass(name="ModStudioFileScan")
public final class FileScan {
    record Fingerprint(long bytes,String hash) {}
    volatile String state="loading",error,phase="checking";
    volatile boolean cancelled;
    private Thread worker;
    Map<String,Fingerprint> snapshot=Map.of();
    final ArrayList<String> entries=new ArrayList<>();
    String basis="unknown",manifestId,comparisonError;
    long bytes;
    String contentLabel="Contents";
    int added,modified,removed,same;
    static FileScan start(Path local,String itemId,ManifestSource source) {
        FileScan scan=new FileScan();
        if(local.getFileName().toString().equals("Contents.release"))scan.contentLabel="Contents (release)";
        scan.worker=Thread.ofVirtual().name("ModStudio-files").unstarted(()->scan.run(local,itemId,source));
        scan.worker.start();return scan;
    }
    private void check() throws InterruptedException {if(cancelled || Thread.currentThread().isInterrupted()) throw new InterruptedException("cancelled");}
    Map<String,Fingerprint> read(Path directory) throws Exception {
        Path root=directory.toRealPath();Map<String,Fingerprint> result=new TreeMap<>();
        Map<Path,BasicFileAttributes> observed=new HashMap<>();
        try(var walk=Files.walk(root)) {
            var paths=walk.iterator();
            while(paths.hasNext()) {
                check();Path path=paths.next();
                if(!path.toRealPath().startsWith(root) || Files.isSymbolicLink(path)) throw new IllegalArgumentException("linked_file:"+path.getFileName());
                if(Files.isDirectory(path)) continue;
                BasicFileAttributes before=Files.readAttributes(path,BasicFileAttributes.class);
                if(!before.isRegularFile()) throw new IllegalArgumentException("linked_file:"+path.getFileName());
                MessageDigest digest=MessageDigest.getInstance("SHA-1");
                try(var stream=Files.newInputStream(path)) {
                    byte[] buffer=new byte[65536];int n;
                    while((n=stream.read(buffer))!=-1) {check();digest.update(buffer,0,n);}
                }
                BasicFileAttributes after=Files.readAttributes(path,BasicFileAttributes.class);
                if(!unchanged(before,after)) throw new IllegalStateException("file_changed:"+path.getFileName());
                observed.put(path,after);
                result.put(root.relativize(path).toString().replace('\\','/'),new Fingerprint(after.size(),HexFormat.of().formatHex(digest.digest())));
            }
        }
        // Detect a save/add/remove that happened while other files were being hashed.
        Set<Path> found=new HashSet<>();
        try(var walk=Files.walk(root)) {
            var paths=walk.iterator();while(paths.hasNext()) {
                check();Path path=paths.next();
                if(Files.isSymbolicLink(path) || !path.toRealPath().startsWith(root)) throw new IllegalArgumentException("linked_file:"+path.getFileName());
                if(Files.isDirectory(path)) continue;
                found.add(path);
                if(!unchanged(observed.get(path),Files.readAttributes(path,BasicFileAttributes.class))) throw new IllegalStateException("file_changed:"+path.getFileName());
            }
        }
        if(!found.equals(observed.keySet())) throw new IllegalStateException("files_changed");
        return Map.copyOf(result);
    }
    static boolean unchanged(BasicFileAttributes a,BasicFileAttributes b) {
        return a!=null && a.size()==b.size() && a.lastModifiedTime().equals(b.lastModifiedTime()) && Objects.equals(a.fileKey(),b.fileKey());
    }
    void run(Path local,String itemId,ManifestSource source) {
        try {
            Map<String,Fingerprint> previous=Map.of();
            if(itemId==null) basis="new";
            else try {
                var remote=source.load(itemId,value->phase=value);previous=remote.files();manifestId=remote.id();basis="manifest";
            } catch(Exception e) {check();comparisonError=message(e);basis="unknown";}
            check();phase="hashing";snapshot=read(local);
            compare(previous);check();state="ready";
        } catch(Exception e) {error=message(e);state=cancelled || e instanceof InterruptedException?"cancelled":"error";}
        catch(LinkageError e) {error="manifest_client";state=cancelled?"cancelled":"error";}
    }
    static String message(Throwable e) {
        while(e.getCause()!=null) e=e.getCause();
        return e.getMessage()==null?e.getClass().getSimpleName():e.getMessage();
    }
    void compare(Map<String,Fingerprint> previous) throws InterruptedException {
        boolean known=!basis.equals("unknown");
        TreeSet<String> paths=new TreeSet<>(snapshot.keySet());if(known) paths.addAll(previous.keySet());
        for(String path:paths) {
            check();Fingerprint current=snapshot.get(path),old=previous.get(path);String change="unknown";
            if(current!=null) bytes+=current.bytes();
            if(known) {
                if(current==null) {removed++;change="removed";}
                else if(old==null) {added++;change="added";}
                else if(!current.equals(old)) {modified++;change="modified";}
                else {same++;change="same";}
            }
            entries.add(change+"\t"+path);
        }
    }
    public String getState(){return state;}
    public String getContentLabel(){return contentLabel;}
    public String getError(){return error;}
    public String getPhase(){return phase;}
    public String getBasis(){return basis;}
    public String getManifestId(){return manifestId;}
    public String getComparisonError(){return comparisonError;}
    public int getFileCount(){return snapshot.size();}
    public double getBytes(){return bytes;}
    public int getAdded(){return added;}
    public int getModified(){return modified;}
    public int getRemoved(){return removed;}
    public int getUnchanged(){return same;}
    public ArrayList<String> getEntries(){return state.equals("ready")?new ArrayList<>(entries):new ArrayList<>();}
    public void cancel(){cancelled=true;if(worker!=null) worker.interrupt();}
}
