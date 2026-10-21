package me.pavel.modstudio;

import java.nio.file.*;
import java.awt.image.BufferedImage;
import javax.imageio.*;
import javax.imageio.metadata.IIOMetadataNode;
import zombie.core.znet.SteamWorkshopItem;

final class AssetTest {
    static void check(boolean value,String message){WriterTest.check(value,message);}
    static void await(FileScan scan) throws Exception {for(int i=0;i<1000&&scan.getState().equals("loading");i++) Thread.sleep(5);check(scan.getState().equals("ready"),"file scan: "+scan.getError());}
    static void run(Path folder) throws Exception {
        SteamWorkshopItem item=new SteamWorkshopItem(folder.toString());
        Files.writeString(folder.resolve("disabled.txt"),"text");Files.writeString(folder.resolve("fake.gif"),"not an image");
        var entries=LocalFiles.listAssets(item,"");
        check(entries.stream().anyMatch(e->e.name.equals("disabled.txt")&&!e.selectable),"nonimage listed disabled");
        check(entries.stream().anyMatch(e->e.name.equals("fake.gif")&&!e.selectable),"misnamed image listed disabled");
        check(entries.stream().anyMatch(e->e.name.equals("preview.png")&&e.selectable),"valid image selectable");
        boolean escaped=false;try{LocalFiles.assetPath(item,"../");}catch(IllegalArgumentException e){escaped=true;}
        check(escaped,"parent traversal blocked");
        escaped=false;try{LocalFiles.assetPath(item,folder.getParent().toString());}catch(IllegalArgumentException e){escaped=true;}
        check(escaped,"absolute outside path blocked");
        Path gif=folder.resolve("animation.gif");var writer=ImageIO.getImageWritersByFormatName("gif").next();
        try(var output=ImageIO.createImageOutputStream(gif.toFile())) {
            writer.setOutput(output);writer.prepareWriteSequence(null);
            for(int color:new int[]{0xFF0000,0x0000FF}) {
                BufferedImage image=new BufferedImage(8,8,BufferedImage.TYPE_INT_RGB);
                for(int y=0;y<8;y++) for(int x=0;x<8;x++) image.setRGB(x,y,color);
                var metadata=writer.getDefaultImageMetadata(ImageTypeSpecifier.createFromRenderedImage(image),null);
                var tree=(IIOMetadataNode)metadata.getAsTree("javax_imageio_gif_image_1.0");
                var control=(IIOMetadataNode)tree.getElementsByTagName("GraphicControlExtension").item(0);control.setAttribute("delayTime","10");
                metadata.setFromTree("javax_imageio_gif_image_1.0",tree);writer.writeToSequence(new IIOImage(image,null,metadata),null);
            }
            writer.endWriteSequence();
        } finally {writer.dispose();}
        byte[] original=Files.readAllBytes(gif);PreviewAnimation animation=PreviewAnimation.open(gif);
        for(int i=0;i<1000&&animation.getState().equals("loading");i++) Thread.sleep(5);
        check(animation.getState().equals("ready") && animation.getFrameCount()==2,"all GIF frames decoded");
        String first=animation.getFramePath(0),second=animation.getFramePath(110);
        zombie.ZomboidFileSystem.instance.validatePrefix(first);
        check(!first.equals(second) && animation.getFramePath(210).equals(first),"GIF advances and loops by frame delay");
        check((ImageIO.read(Path.of(first).toFile()).getRGB(0,0)&0xFFFFFF)==0xFF0000 && (ImageIO.read(Path.of(second).toFile()).getRGB(0,0)&0xFFFFFF)==0x0000FF,"GIF displays distinct frames");
        check(java.util.Arrays.equals(original,Files.readAllBytes(gif)),"decoding does not alter uploaded GIF");
        PreviewDownloadTest.run(folder,gif);
        animation.close();check(!Files.exists(Path.of(first)),"closing preview cleans frame files");
        Files.delete(gif);Files.delete(folder.resolve("disabled.txt"));Files.delete(folder.resolve("fake.gif"));
        byte[] png=Files.readAllBytes(folder.resolve("preview.png"));Path limits=folder.resolve("limits.png");
        Files.write(limits,java.util.Arrays.copyOf(png,(int)LocalFiles.PREVIEW_UPLOAD_BYTES));LocalFiles.checkPreview(limits);
        check(LocalFiles.inspectPreview(limits,LocalFiles.PREVIEW_UPLOAD_BYTES).canUpload(),"exact conservative upload byte cap accepted");
        Files.write(limits,java.util.Arrays.copyOf(png,(int)LocalFiles.PREVIEW_UPLOAD_BYTES+1));
        boolean large=false;try{LocalFiles.checkPreview(limits);}catch(IllegalArgumentException e){large=e.getMessage().equals("preview_size");}
        check(large,"oversize preview rejected before upload");
        check(!LocalFiles.inspectPreview(limits,LocalFiles.PREVIEW_DOWNLOAD_BYTES).canUpload(),"existing Steam image can be viewed/saved even when too large to upload again");
        byte[] huge=png.clone();java.nio.ByteBuffer.wrap(huge).putInt(16,100000).putInt(20,100000);
        var crc=new java.util.zip.CRC32();crc.update(huge,12,17);java.nio.ByteBuffer.wrap(huge).putInt(29,(int)crc.getValue());Files.write(limits,huge);
        boolean dimensions=false;try{LocalFiles.checkPreview(limits);}catch(IllegalArgumentException e){dimensions=e.getMessage().equals("preview_dimensions");}
        check(dimensions,"unreasonable pixel dimensions rejected before decoding");
        Files.write(limits,java.util.Arrays.copyOf(png,33));boolean truncated=false;
        try{LocalFiles.checkPreview(limits);}catch(IllegalArgumentException e){truncated=e.getMessage().equals("preview_format");}
        check(truncated,"valid header with missing pixels rejected");Files.delete(limits);
        Path local=folder.resolve("scan-local"),remote=folder.resolve("scan-remote");Files.createDirectories(local);Files.createDirectories(remote);
        Files.writeString(local.resolve("same"),"same");Files.writeString(remote.resolve("same"),"same");
        Files.writeString(local.resolve("changed"),"new");Files.writeString(remote.resolve("changed"),"old");
        Files.writeString(local.resolve("added"),"new");Files.writeString(remote.resolve("removed"),"old");
        FileScan scan=FileScan.start(local,"123",ManifestTest.sourceFor(remote));await(scan);
        check(scan.getAdded()==1 && scan.getModified()==1 && scan.getRemoved()==1 && scan.getFileCount()==3,"file diff uses content including equal-length edits");
        FileScan unknown=FileScan.start(local,"123",ManifestTest.unavailable());await(unknown);
        check(unknown.getAdded()==0 && unknown.getEntries().stream().allMatch(s->s.startsWith("unknown\t")),"missing baseline never claims unchanged");
        FileScan fresh=FileScan.start(local,null,ManifestTest.unavailable());await(fresh);check(fresh.getAdded()==3,"new publication shows all files as additions");
    }
}
