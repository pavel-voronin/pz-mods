package me.pavel.modstudio.manifest;

import in.dragonbra.javasteam.enums.EDepotFileFlag;
import in.dragonbra.javasteam.enums.EResult;
import in.dragonbra.javasteam.steam.steamclient.SteamClient;
import in.dragonbra.javasteam.steam.steamclient.configuration.SteamConfiguration;
import in.dragonbra.javasteam.steam.steamclient.callbackmgr.CallbackManager;
import in.dragonbra.javasteam.steam.steamclient.callbacks.ConnectedCallback;
import in.dragonbra.javasteam.steam.steamclient.callbacks.DisconnectedCallback;
import in.dragonbra.javasteam.steam.handlers.steamuser.SteamUser;
import in.dragonbra.javasteam.steam.handlers.steamuser.callback.LoggedOnCallback;
import in.dragonbra.javasteam.steam.handlers.steamapps.SteamApps;
import in.dragonbra.javasteam.steam.handlers.steamcontent.SteamContent;
import in.dragonbra.javasteam.steam.cdn.Server;
import in.dragonbra.javasteam.types.DepotManifest;
import kotlinx.coroutines.*;
import kotlinx.coroutines.future.FutureKt;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;
import java.util.zip.ZipInputStream;

/** Isolated library entry point. Anonymous read-only Steam session; no chunk-download calls. */
public final class ManifestClient {
    private static final int APP=108600;
    private final long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(55);
    private final CoroutineScope scope=CoroutineScopeKt.CoroutineScope(Dispatchers.getIO().plus(SupervisorKt.SupervisorJob(null)));
    private final OkHttpClient http=new OkHttpClient.Builder().connectTimeout(10,TimeUnit.SECONDS)
        .readTimeout(15,TimeUnit.SECONDS).callTimeout(20,TimeUnit.SECONDS).followRedirects(false).build();
    private final SteamClient steam=new SteamClient(SteamConfiguration.create(b->b.withConnectionTimeout(12000).withHttpClient(http)),scope);
    private final CallbackManager callbacks=new CallbackManager(steam);
    private boolean disconnected;

    private void check() throws InterruptedException,TimeoutException {
        if(Thread.currentThread().isInterrupted()) throw new InterruptedException();
        if(System.nanoTime()>deadline) throw new TimeoutException("manifest_timeout");
    }
    private <T> T waitFor(CompletableFuture<T> future) throws Exception {
        try {
            while(!future.isDone()) {
                check();if(disconnected) throw new IOException("manifest_disconnected");
                callbacks.runWaitAllCallbacks(50);
            }
            return future.get();
        } finally {if(!future.isDone()) future.cancel(true);}
    }
    private <T> T waitFor(Deferred<T> deferred) throws Exception {return waitFor(FutureKt.asCompletableFuture(deferred));}
    private byte[] readLimited(InputStream stream,int limit) throws Exception {
        ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buffer=new byte[32768];int n;
        while((n=stream.read(buffer))!=-1) {check();if(out.size()>limit-n) throw new IOException("manifest_too_large");out.write(buffer,0,n);}
        return out.toByteArray();
    }
    private DepotManifest download(Server server,long manifest,long code,byte[] key,String token) throws Exception {
        String host=server.getVHost()!=null?server.getVHost():server.getHost();
        if(host==null || !host.matches("[a-zA-Z0-9.-]+") || server.getUseAsProxy()) throw new IOException("manifest_server");
        // Prefer TLS even when the server advertises an HTTP endpoint. Only request manifests.
        String url="https://"+host+"/depot/"+APP+"/manifest/"+Long.toUnsignedString(manifest)+"/5/"+Long.toUnsignedString(code);
        if(token!=null && !token.isBlank()) url+=(token.startsWith("?")?token:"?"+token);
        var call=http.newCall(new Request.Builder().url(url).get().build());
        CompletableFuture<byte[]> body=new CompletableFuture<>();
        call.enqueue(new okhttp3.Callback() {
            public void onFailure(okhttp3.Call c,IOException e){body.completeExceptionally(e);}
            public void onResponse(okhttp3.Call c,okhttp3.Response response) {
                try(response) {
                    if(!response.isSuccessful()) throw new IOException("manifest_http_"+response.code());
                    if(response.body().contentLength()>16*1024*1024) throw new IOException("manifest_too_large");
                    body.complete(readLimited(response.body().byteStream(),16*1024*1024));
                } catch(Exception e){body.completeExceptionally(e);}
            }
        });
        byte[] data;
        try {data=waitFor(body);} finally {call.cancel();}
        try(var zip=new ZipInputStream(new ByteArrayInputStream(data))) {
            if(zip.getNextEntry()==null) throw new IOException("manifest_invalid");
            data=readLimited(zip,64*1024*1024);
        }
        DepotManifest result=DepotManifest.deserialize(data);
        if(result.getDepotID()!=APP || result.getManifestGID()!=manifest || !result.decryptFilenames(key)) throw new IOException("manifest_invalid");
        return result;
    }
    private Map<String,String> run(String id,Consumer<String> progress) throws Exception {
        long manifest=Long.parseUnsignedLong(id);
        var loggedOn=new CompletableFuture<Boolean>();
        var user=Objects.requireNonNull(steam.getHandler(SteamUser.class));
        callbacks.subscribe(ConnectedCallback.class,c->user.logOnAnonymous());
        callbacks.subscribe(DisconnectedCallback.class,c->disconnected=true);
        callbacks.subscribe(LoggedOnCallback.class,c->{
            if(c.getResult()==EResult.OK) loggedOn.complete(true);
            else loggedOn.completeExceptionally(new IOException("manifest_login_"+c.getResult()));
        });
        progress.accept("connecting");steam.connect();waitFor(loggedOn);
        SteamContent content=Objects.requireNonNull(steam.getHandler(SteamContent.class));
        var key=waitFor(Objects.requireNonNull(steam.getHandler(SteamApps.class)).getDepotDecryptionKey(APP,APP).toFuture());
        if(key.getResult()!=EResult.OK) throw new IOException("manifest_access");
        long code=waitFor(content.getManifestRequestCode(APP,APP,manifest,null,null,scope));
        if(code==0) throw new IOException("manifest_access");
        List<Server> servers=waitFor(content.getServersForSteamPipe(null,20,scope));
        progress.accept("manifest");Exception failure=new IOException("manifest_server");int attempts=0;
        for(Server server:servers) {
            if(server.getUseAsProxy() || !("CDN".equals(server.getType()) || "SteamCache".equals(server.getType()))) continue;
            if(++attempts>5) break;check();
            DepotManifest result;
            try {result=download(server,manifest,code,key.getDepotKey(),null);}
            catch(InterruptedException|TimeoutException e){throw e;}
            catch(Exception e) {
                failure=e;
                Throwable cause=e;while(cause.getCause()!=null) cause=cause.getCause();
                if(!"manifest_http_403".equals(cause.getMessage())) continue;
                try {
                    var auth=waitFor(content.getCDNAuthToken(APP,APP,server.getHost(),scope));
                    if(auth.getResult()!=EResult.OK) continue;
                    result=download(server,manifest,code,key.getDepotKey(),auth.getToken());
                } catch(InterruptedException|TimeoutException x){throw x;}
                catch(Exception x){failure=x;continue;}
            }
            Map<String,String> files=new TreeMap<>();
            for(var file:result.getFiles()) {
                check();if(file.getFlags().contains(EDepotFileFlag.Directory)) continue;
                if(file.getFlags().contains(EDepotFileFlag.Symlink) || file.getFileHash().length!=20 || file.getTotalSize()<0) throw new IOException("manifest_invalid");
                String name=file.getFileName().replace('\\','/');
                if(files.put(name,file.getTotalSize()+":"+HexFormat.of().formatHex(file.getFileHash()))!=null) throw new IOException("manifest_invalid");
            }
            return files;
        }
        throw failure;
    }
    /** All arguments and results use JDK types to keep game and dependency class loaders separate. */
    public static Map<String,String> fetch(String manifestId,Consumer<String> progress) throws Exception {
        ManifestClient client=new ManifestClient();
        try {return client.run(manifestId,progress);}
        finally {
            client.steam.disconnect();CoroutineScopeKt.cancel(client.scope,null);
            client.http.dispatcher().cancelAll();client.http.connectionPool().evictAll();client.http.dispatcher().executorService().shutdown();
        }
    }
}
