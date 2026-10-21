package me.pavel.modstudio;

import java.awt.*;
import java.awt.image.BufferedImage;
import java.nio.file.*;
import java.util.ArrayList;
import java.util.List;
import javax.imageio.ImageIO;
import org.w3c.dom.Node;
import me.zed_0xff.zombie_buddy.Exposer;
import zombie.ZomboidFileSystem;
import zombie.core.textures.Texture;
import zombie.core.opengl.RenderThread;

/** Decodes bounded UI frames off the game thread. Uploads always use the original file. */
@Exposer.LuaClass(name="ModStudioPreviewAnimation")
public final class PreviewAnimation {
    volatile String state="loading",error;
    volatile boolean cancelled;
    volatile List<String> frames=List.of();
    volatile List<Integer> delays=List.of();
    long duration;
    Path directory;
    final List<Path> generated=new ArrayList<>();
    final java.util.Map<String,Texture> textures=new java.util.HashMap<>();
    static PreviewAnimation open(Path path) throws Exception {
        LocalFiles.checkPreview(path);
        return openValidated(path);
    }
    static PreviewAnimation openValidated(Path path) {
        PreviewAnimation animation=new PreviewAnimation();
        Thread.ofVirtual().name("ModStudio-preview").start(()->animation.decode(path));
        return animation;
    }
    static Node child(Node root,String name) {
        if(root==null) return null;
        for(Node n=root.getFirstChild();n!=null;n=n.getNextSibling()) if(n.getNodeName().equals(name)) return n;
        return null;
    }
    static String attr(Node n,String name,String fallback) {
        if(n==null || n.getAttributes()==null || n.getAttributes().getNamedItem(name)==null) return fallback;
        return n.getAttributes().getNamedItem(name).getNodeValue();
    }
    static int number(Node n,String name,int fallback) {return Integer.parseInt(attr(n,name,""+fallback));}
    void decode(Path path) {
        try(var stream=ImageIO.createImageInputStream(path.toFile())) {
            var readers=ImageIO.getImageReaders(stream);
            if(!readers.hasNext()) throw new IllegalArgumentException("preview_format");
            var reader=readers.next();
            try {
                reader.setInput(stream);boolean gif=reader.getFormatName().equalsIgnoreCase("gif");
                int count=gif?reader.getNumImages(true):1;
                int width=reader.getWidth(0),height=reader.getHeight(0);
                if(gif && reader.getStreamMetadata()!=null) {
                    Node logical=child(reader.getStreamMetadata().getAsTree("javax_imageio_gif_stream_1.0"),"LogicalScreenDescriptor");
                    width=number(logical,"logicalScreenWidth",width);height=number(logical,"logicalScreenHeight",height);
                }
                if(count>512 || width<1 || height<1 || (long)width*height>64_000_000L) throw new IllegalArgumentException("preview_animation_limit");
                double scale=Math.min(1.0,256.0/Math.max(width,height));
                BufferedImage canvas=new BufferedImage(Math.max(1,(int)Math.ceil(width*scale)),Math.max(1,(int)Math.ceil(height*scale)),BufferedImage.TYPE_INT_ARGB);
                directory=Files.createTempDirectory(Path.of(ZomboidFileSystem.instance.getCacheDir()),"mod-studio-animation-");directory.toFile().deleteOnExit();
                List<String> paths=new ArrayList<>();List<Integer> times=new ArrayList<>();
                for(int i=0;i<count && !cancelled;i++) {
                    Node metadata=gif?reader.getImageMetadata(i).getAsTree("javax_imageio_gif_image_1.0"):null;
                    Node image=child(metadata,"ImageDescriptor"),control=child(metadata,"GraphicControlExtension");
                    String disposal=attr(control,"disposalMethod","none");
                    int x=(int)Math.round(number(image,"imageLeftPosition",0)*scale),y=(int)Math.round(number(image,"imageTopPosition",0)*scale);
                    int w=Math.max(1,(int)Math.ceil(number(image,"imageWidth",reader.getWidth(i))*scale));
                    int h=Math.max(1,(int)Math.ceil(number(image,"imageHeight",reader.getHeight(i))*scale));
                    BufferedImage previous=null;
                    if(disposal.equals("restoreToPrevious")) {
                        previous=new BufferedImage(canvas.getWidth(),canvas.getHeight(),BufferedImage.TYPE_INT_ARGB);
                        Graphics2D g=previous.createGraphics();g.drawImage(canvas,0,0,null);g.dispose();
                    }
                    var param=reader.getDefaultReadParam();int sample=Math.max(1,(int)(1.0/scale));param.setSourceSubsampling(sample,sample,0,0);
                    BufferedImage frame=reader.read(i,param);Graphics2D g=canvas.createGraphics();
                    g.drawImage(frame,x,y,w,h,null);g.dispose();frame.flush();
                    Path output=directory.resolve("frame-"+i+".png");output.toFile().deleteOnExit();generated.add(output);
                    ImageIO.write(canvas,"png",output.toFile());paths.add(output.toString());
                    int delay=gif?number(control,"delayTime",10)*10:1000;delay=delay<=10?100:delay;
                    times.add(delay);duration+=delay;
                    if(disposal.equals("restoreToBackgroundColor")) {g=canvas.createGraphics();g.setComposite(AlphaComposite.Clear);g.fillRect(x,y,w,h);g.dispose();}
                    else if(previous!=null) {canvas.flush();canvas=previous;}
                }
                canvas.flush();frames=List.copyOf(paths);delays=List.copyOf(times);
                state=cancelled?"cancelled":"ready";
            } finally {reader.dispose();}
        } catch(Exception e) {error=e.getMessage();state="error";}
        finally {if(cancelled) state="cancelled";if(cancelled || state.equals("error")) cleanup();}
    }
    synchronized void cleanup() {
        if(!textures.isEmpty()) {
            List<Texture> owned=List.copyOf(textures.values());textures.clear();
            RenderThread.queueInvokeOnRenderContext(()->owned.forEach(Texture::destroy));
        }
        for(Path path:generated) try {Files.deleteIfExists(path);} catch(Exception ignored) {}
        if(directory!=null) try {Files.deleteIfExists(directory);} catch(Exception ignored) {}
    }
    public void close(){cancelled=true;if(!state.equals("loading")) {state="cancelled";cleanup();}}
    public String getState(){return state;}
    public String getError(){return error;}
    public int getFrameCount(){return frames.size();}
    /** Own textures directly: shared game caches would retain every frame after closing the editor. */
    public synchronized Texture getFrameTexture(double elapsedMillis) {
        String path=getFramePath(elapsedMillis);if(path==null) return null;
        try {
            Texture texture=textures.get(path);
            if(texture==null) {texture=new Texture(path,true,true);textures.put(path,texture);}
            return texture;
        } catch(Exception e) {error=e.getMessage();state="error";return null;}
    }
    public String getFramePath(double elapsedMillis) {
        if(!state.equals("ready") || frames.isEmpty()) return null;
        long time=Math.max(0,(long)elapsedMillis)%Math.max(1,duration);
        for(int i=0;i<delays.size();i++) {if(time<delays.get(i)) return frames.get(i);time-=delays.get(i);}
        return frames.getFirst();
    }
}
