package me.pavel.modstudio;

import me.zed_0xff.zombie_buddy.Exposer;

@Exposer.LuaClass(name="ModStudioPreviewInfo")
public final class PreviewInfo {
    final String format;
    final int width,height,frames;
    final long bytes;
    PreviewInfo(String format,int width,int height,int frames,long bytes) {this.format=format;this.width=width;this.height=height;this.frames=frames;this.bytes=bytes;}
    public String getFormat(){return format.toUpperCase(java.util.Locale.ROOT);}
    public int getWidth(){return width;}
    public int getHeight(){return height;}
    public int getFrames(){return frames;}
    public double getBytes(){return bytes;}
    public boolean canUpload(){return getUploadError()==null;}
    public String getUploadError(){return bytes>LocalFiles.PREVIEW_UPLOAD_BYTES?"preview_size":getRenderError();}
    public String getRenderError(){return (long)width*height>64_000_000L?"preview_dimensions":frames>512?"preview_frames":null;}
}
