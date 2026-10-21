package me.pavel.modstudio;

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import zombie.core.znet.SteamWorkshopItem;

final class PreviewDownloadTest {
    static void check(boolean value,String message){WriterTest.check(value,message);}
    static ReadRequest snapshot(String url) {
        ReadRequest r=new ReadRequest(null,"1234567890","english",0);r.state="loaded";
        r.data=new SteamReader.Snapshot("Title","Description",2,0,List.of(),List.of(),"",url,List.of());return r;
    }
    static void await(PreviewDownload r) throws Exception {for(int i=0;i<1000&&r.getState().equals("loading");i++) Thread.sleep(5);check(!r.getState().equals("loading"),"download finished");}
    static final class Reply extends HttpURLConnection {
        final byte[] body;final int status;final String redirect;boolean disconnected;
        Reply(URI uri,byte[] body,int status,String redirect) throws Exception {super(uri.toURL());this.body=body;this.status=status;this.redirect=redirect;}
        public void connect(){}public boolean usingProxy(){return false;}public void disconnect(){disconnected=true;}
        public int getResponseCode(){return status;}
        public String getHeaderField(String name){return name.equals("Location")?redirect:null;}
        public long getContentLengthLong(){return body.length;}
        public InputStream getInputStream(){return new ByteArrayInputStream(body);}
    }
    static void run(Path folder,Path gif) throws Exception {
        String url="https://images.steamusercontent.com/ugc/123/hash/";
        byte[] bytes=Files.readAllBytes(gif);var previous=PreviewDownload.connections;
        try {
            PreviewDownload.connections=uri->{try{return new Reply(uri,bytes,200,null);}catch(Exception e){throw new IOException(e);}};
            PreviewDownload request=PreviewDownload.start(snapshot(url));await(request);
            check(request.getState().equals("loaded"),"download and decode GIF: "+request.getError());
            check(request.getInfo().getFormat().equals("GIF")&&request.getAnimation().getFrameCount()==2,"downloaded preview keeps GIF format and frames");
            check(!Files.exists(folder.resolve("workshop-preview.gif")),"automatic download does not save into package");
            SteamWorkshopItem item=new SteamWorkshopItem(folder.toString());item.setID("1234567890");
            byte[] local=Files.readAllBytes(folder.resolve("preview.png"));
            String path=LocalFiles.savePreviewCopy(item,request);
            check(path.equals("workshop-preview.gif")&&Arrays.equals(bytes,Files.readAllBytes(folder.resolve(path))),"local save preserves exact downloaded bytes and actual extension");
            check(Arrays.equals(local,Files.readAllBytes(folder.resolve("preview.png"))),"existing local preview is never overwritten");
            check(LocalFiles.savePreviewCopy(item,request).equals(path),"same bytes reuse existing saved copy");
            Files.writeString(folder.resolve(path),"author file");
            String next=LocalFiles.savePreviewCopy(item,request);
            check(next.equals("workshop-preview-2.gif")&&Files.readString(folder.resolve(path)).equals("author file"),"different existing file preserved; next numbered name selected");
            item.setID("1234567891");boolean wrong=false;try{LocalFiles.savePreviewCopy(item,request);}catch(IllegalArgumentException e){wrong=true;}check(wrong,"download cannot be saved under another Workshop identity");
            Path downloaded=request.file;request.cancel();check(!Files.exists(downloaded),"closing editor removes downloaded cache file");
            for(String bad:List.of("file:///C:/secret.png","http://images.steamusercontent.com/a","https://127.0.0.1/a","https://images.steamusercontent.com.evil.test/a","https://user:password@images.steamusercontent.com/a","relative.png")) {
                boolean blocked=false;try{PreviewDownload.checkedUrl(bad);}catch(IllegalArgumentException e){blocked=true;}check(blocked,"reject non-Steam URL "+bad);
            }
            PreviewDownload.connections=uri->{try{return new Reply(uri,bytes,302,"https://127.0.0.1/a");}catch(Exception e){throw new IOException(e);}};
            request=PreviewDownload.start(snapshot(url));await(request);check(request.getState().equals("error")&&request.getError().equals("preview_url"),"redirect destination checked before following");
            PreviewDownload.connections=uri->{try{return new Reply(uri,"<html>error</html>".getBytes(),200,null);}catch(Exception e){throw new IOException(e);}};
            request=PreviewDownload.start(snapshot(url));await(request);check(request.getState().equals("error")&&!Files.exists(request.file),"HTML disguised as successful image rejected and cleaned");
            PreviewDownload.connections=uri->{try{return new Reply(uri,new byte[0],404,null);}catch(Exception e){throw new IOException(e);}};
            request=PreviewDownload.start(snapshot(url));await(request);check(request.getError().equals("preview_http_404"),"HTTP failure reported");
            PreviewDownload limit=new PreviewDownload("1234567890");boolean bounded=false;
            try{limit.copyLimited(new ByteArrayInputStream(new byte[20]),new ByteArrayOutputStream(),10,Long.MAX_VALUE);}catch(IOException e){bounded=true;}
            check(bounded,"stream byte limit enforced even without a Content-Length header");
            PreviewDownload missing=PreviewDownload.start(snapshot(""));await(missing);check(missing.getError().equals("preview_missing"),"absent Steam preview reported");
            Files.delete(folder.resolve(path));Files.delete(folder.resolve(next));
        } finally {PreviewDownload.connections=previous;}
    }
}
