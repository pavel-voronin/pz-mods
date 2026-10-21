package me.pavel.modstudio;

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.Locale;
import me.zed_0xff.zombie_buddy.Exposer;
import zombie.ZomboidFileSystem;

/** Downloads the exact preview URL returned by Steam, without resizing or converting it. */
@Exposer.LuaClass(name="ModStudioPreviewDownload")
public final class PreviewDownload {
    interface Connections {HttpURLConnection open(URI uri) throws IOException;}
    static Connections connections=uri->(HttpURLConnection)uri.toURL().openConnection();
    final String itemId;
    volatile String state="loading",error;
    volatile boolean cancelled;
    volatile HttpURLConnection connection;
    Thread worker;
    Path file;
    PreviewInfo info;
    PreviewAnimation animation;
    PreviewDownload(String itemId){this.itemId=itemId;}
    static PreviewDownload start(ReadRequest snapshot) {
        if(!snapshot.getState().equals("loaded")) throw new IllegalArgumentException("preview_not_loaded");
        PreviewDownload result=new PreviewDownload(snapshot.getItemId());
        String url=snapshot.getPreviewUrl();
        result.worker=Thread.ofVirtual().name("ModStudio-preview-download").start(()->result.download(url));return result;
    }
    static URI checkedUrl(String text) {
        if(text==null || text.isBlank()) throw new IllegalArgumentException("preview_missing");
        URI uri=URI.create(text);String host=uri.getHost()==null?"":uri.getHost().toLowerCase(Locale.ROOT);
        if(!"https".equalsIgnoreCase(uri.getScheme()) || uri.getUserInfo()!=null || (uri.getPort()!=-1&&uri.getPort()!=443) ||
            !(host.equals("steamusercontent.com") || host.endsWith(".steamusercontent.com") || host.endsWith(".steamstatic.com") ||
              host.equals("steamuserimages-a.akamaihd.net") || host.equals("steamcdn-a.akamaihd.net"))) throw new IllegalArgumentException("preview_url");
        return uri;
    }
    void download(String url) {
        try {
            URI current=checkedUrl(url);long deadline=System.nanoTime()+30_000_000_000L;
            for(int redirect=0;redirect<5;redirect++) {
                if(cancelled) throw new InterruptedException();
                connection=connections.open(current);
                connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(10000);connection.setReadTimeout(15000);connection.setUseCaches(false);
                connection.setRequestProperty("Cache-Control","no-cache");
                int status=connection.getResponseCode();
                if(status>=300 && status<400) {
                    String location=connection.getHeaderField("Location");if(location==null) throw new IOException("preview_http_"+status);
                    current=checkedUrl(current.resolve(location).toString());connection.disconnect();connection=null;continue;
                }
                if(status!=200) throw new IOException("preview_http_"+status);
                if(connection.getContentLengthLong()>LocalFiles.PREVIEW_DOWNLOAD_BYTES) throw new IOException("preview_download_size");
                file=Files.createTempFile(Path.of(ZomboidFileSystem.instance.getCacheDir()),"mod-studio-download-",".image");file.toFile().deleteOnExit();
                try(var input=connection.getInputStream();var output=Files.newOutputStream(file)) {
                    copyLimited(input,output,LocalFiles.PREVIEW_DOWNLOAD_BYTES,deadline);
                }
                info=LocalFiles.inspectPreview(file,LocalFiles.PREVIEW_DOWNLOAD_BYTES,false);
                if(info.getRenderError()==null && !cancelled) {
                    animation=PreviewAnimation.openValidated(file);
                    while(animation.getState().equals("loading") && !cancelled) Thread.sleep(10);
                    if(!cancelled && !animation.getState().equals("ready")) error=animation.getError();
                }
                state=cancelled?"cancelled":"loaded";return;
            }
            throw new IOException("preview_redirects");
        } catch(Exception e) {error=e.getMessage();state=cancelled?"cancelled":"error";}
        finally {
            if(connection!=null) {connection.disconnect();connection=null;}
            if(cancelled) state="cancelled";
            if(!state.equals("loaded")) cleanup();
        }
    }
    void copyLimited(InputStream input,OutputStream output,long limit,long deadline) throws Exception {
        byte[] buffer=new byte[16384];long total=0;int count;
        while((count=input.read(buffer))!=-1) {
            if(cancelled) throw new InterruptedException("cancelled");
            if(System.nanoTime()>deadline) throw new IOException("timeout");
            total+=count;if(total>limit) throw new IOException("preview_download_size");output.write(buffer,0,count);
        }
    }
    synchronized void cleanup() {
        if(animation!=null) animation.close();
        if(file!=null) try {Files.deleteIfExists(file);} catch(IOException ignored) {}
    }
    public void cancel() {
        cancelled=true;HttpURLConnection active=connection;if(active!=null) active.disconnect();
        if(worker!=null) worker.interrupt();if(!state.equals("loading")) {state="cancelled";cleanup();}
    }
    public String getState(){return state;}
    public String getError(){return error;}
    public PreviewInfo getInfo(){return state.equals("loaded")?info:null;}
    public PreviewAnimation getAnimation(){return state.equals("loaded")&&animation!=null&&animation.getState().equals("ready")?animation:null;}
    public String getRenderError(){return info!=null&&info.getRenderError()!=null?info.getRenderError():error;}
}
