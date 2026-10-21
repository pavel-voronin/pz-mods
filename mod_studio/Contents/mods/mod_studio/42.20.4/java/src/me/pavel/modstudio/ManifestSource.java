package me.pavel.modstudio;

import java.io.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;
import java.lang.reflect.*;
import org.json.JSONObject;

/** Fetches current remote fingerprints. Cache entries are usable only after rechecking the ID. */
final class ManifestSource {
    record Snapshot(String id,Map<String,FileScan.Fingerprint> files) {}
    interface Transport {
        String currentId(String workshopId) throws Exception;
        Map<String,String> fetch(String manifestId,Consumer<String> progress) throws Exception;
    }
    static final ManifestSource LIVE=new ManifestSource(new Network());
    private final Transport transport;
    private final Map<String,Snapshot> cache=new LinkedHashMap<>();
    ManifestSource(Transport transport){this.transport=transport;}
    Snapshot load(String item,Consumer<String> progress) throws Exception {
        progress.accept("checking");String id=transport.currentId(item);checkId(id);
        synchronized(cache) {Snapshot old=cache.get(item);if(old!=null && old.id.equals(id)) return old;}
        Map<String,FileScan.Fingerprint> files=parse(transport.fetch(id,progress));
        // Don't display a comparison against a revision replaced during the request.
        if(!id.equals(transport.currentId(item))) throw new IOException("manifest_changed");
        Snapshot result=new Snapshot(id,files);
        synchronized(cache) {
            cache.remove(item);cache.put(item,result);
            while(cache.size()>8) cache.remove(cache.keySet().iterator().next());
        }
        return result;
    }
    static void checkId(String value) throws IOException {
        try {if(value==null || !value.matches("[1-9][0-9]{0,19}") || Long.parseUnsignedLong(value)==-1) throw new Exception();}
        catch(Exception e){throw new IOException("manifest_unavailable");}
    }
    static Map<String,FileScan.Fingerprint> parse(Map<String,String> rows) throws IOException {
        if(rows==null || rows.size()>500000) throw new IOException("manifest_invalid");
        Map<String,FileScan.Fingerprint> files=new TreeMap<>();
        for(var row:rows.entrySet()) {
            String path=row.getKey();
            if(path==null || path.isBlank() || path.startsWith("/") || path.contains("\\") || path.indexOf(':')>=0 || path.chars().anyMatch(c->c<32 || c==127)) throw new IOException("manifest_invalid");
            for(String part:path.split("/",-1)) if(part.isEmpty() || part.equals(".") || part.equals("..")) throw new IOException("manifest_invalid");
            String[] value=row.getValue().split(":",-1);
            if(value.length!=2 || !value[0].matches("[0-9]+") || !value[1].matches("[0-9a-fA-F]{40}")) throw new IOException("manifest_invalid");
            try {files.put(path,new FileScan.Fingerprint(Long.parseLong(value[0]),value[1].toLowerCase(Locale.ROOT)));}
            catch(NumberFormatException e){throw new IOException("manifest_invalid");}
        }
        return Map.copyOf(files);
    }
    private static final class Network implements Transport {
        public String currentId(String workshopId) throws Exception {
            checkId(workshopId);
            try(HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build()) {
                var request=HttpRequest.newBuilder(URI.create("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"))
                    .timeout(Duration.ofSeconds(15)).header("Content-Type","application/x-www-form-urlencoded").header("Cache-Control","no-cache")
                    .POST(HttpRequest.BodyPublishers.ofString("itemcount=1&publishedfileids%5B0%5D="+workshopId)).build();
                var response=http.send(request,info->new LimitedBody());
                {
                    if(response.statusCode()!=200) throw new IOException("manifest_http_"+response.statusCode());
                    byte[] body=response.body();
                    var details=new JSONObject(new String(body,java.nio.charset.StandardCharsets.UTF_8)).getJSONObject("response").getJSONArray("publishedfiledetails");
                    if(details.length()!=1) throw new IOException("manifest_unavailable");
                    var file=details.getJSONObject(0);
                    if(file.optInt("result")!=1 || !workshopId.equals(file.optString("publishedfileid")) || file.optInt("consumer_app_id")!=108600 || !file.optString("file_url").isEmpty()) throw new IOException("manifest_unavailable");
                    String id=file.optString("hcontent_file");checkId(id);return id;
                }
            }
        }
        @SuppressWarnings("unchecked")
        public Map<String,String> fetch(String id,Consumer<String> progress) throws Exception {
            ClassLoader old=Thread.currentThread().getContextClassLoader();
            try {
                ClassLoader loader=library();Thread.currentThread().setContextClassLoader(loader);
                return (Map<String,String>)loader.loadClass("me.pavel.modstudio.manifest.ManifestClient")
                    .getMethod("fetch",String.class,Consumer.class).invoke(null,id,progress);
            } catch(InvocationTargetException e) {
                Throwable cause=e.getCause();if(cause instanceof Exception ex) throw ex;throw new IOException("manifest_client",cause);
            } finally {Thread.currentThread().setContextClassLoader(old);}
        }
    }
    /** Complete only after the bounded body arrives, so HttpRequest's timeout covers it too. */
    private static final class LimitedBody implements HttpResponse.BodySubscriber<byte[]> {
        private final CompletableFuture<byte[]> result=new CompletableFuture<>();
        private final ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        private Flow.Subscription subscription;
        public CompletionStage<byte[]> getBody(){return result;}
        public void onSubscribe(Flow.Subscription value){subscription=value;value.request(1);}
        public void onNext(List<java.nio.ByteBuffer> buffers) {
            for(var buffer:buffers) {
                if(bytes.size()>1024*1024-buffer.remaining()) {subscription.cancel();result.completeExceptionally(new IOException("manifest_invalid"));return;}
                byte[] part=new byte[buffer.remaining()];buffer.get(part);bytes.writeBytes(part);
            }
            subscription.request(1);
        }
        public void onError(Throwable error){result.completeExceptionally(error);}
        public void onComplete(){result.complete(bytes.toByteArray());}
    }
    private static URLClassLoader loader;
    /** Extract only the dependency shipped inside the signed mod, never downloaded executable code. */
    private static synchronized ClassLoader library() throws Exception {
        if(loader!=null) return loader;
        byte[] jar;
        try(var stream=ManifestSource.class.getResourceAsStream("lib/manifest-client.jar")) {
            if(stream==null) throw new IOException("manifest_client");jar=stream.readAllBytes();
        }
        String hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(jar));
        Path folder=Files.createTempDirectory("mod-studio-library-");folder.toFile().deleteOnExit();
        Path file=folder.resolve(hash+".jar");Files.write(file,jar);file.toFile().deleteOnExit();
        loader=new URLClassLoader(new URL[]{file.toUri().toURL()},ClassLoader.getPlatformClassLoader());
        Runtime.getRuntime().addShutdownHook(new Thread(()->{try{loader.close();Files.deleteIfExists(file);Files.deleteIfExists(folder);}catch(IOException ignored){}},"ModStudio-library-close"));
        return loader;
    }
}
